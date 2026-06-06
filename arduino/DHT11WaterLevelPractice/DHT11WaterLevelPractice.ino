#include <Arduino.h>
#include <DHT.h>
#if defined(ARDUINO_ARCH_ESP32)
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <PubSubClient.h>
#include "mqtt_secrets.h"
#endif

// ===== Pins (ESP32) =====
const uint8_t DHT_PIN = 4;
const uint8_t WATER_SENSOR_AO_PIN = 10;  // connect to AO of red water sensor
const uint8_t VIBRATION_SENSOR_AO_PIN = 1;  // connect to AO of vibration sensor on ESP32-S3 ADC
const uint8_t BUZZER_PIN = 14;

#define DHTTYPE DHT11
DHT dht(DHT_PIN, DHTTYPE);

// ===== Thresholds =====
const float TEMP_WARNING_C = 35.0f;
const float TEMP_CRITICAL_C = 40.0f;
const float WATER_LEVEL_WARNING_PERCENT = 70.0f;
const float WATER_LEVEL_CRITICAL_PERCENT = 85.0f;
const float VIBRATION_WARNING_LEVEL = 10.0f;
const float VIBRATION_CRITICAL_LEVEL = 14.0f;
const float DHT_VALID_TEMP_MIN_C = 10.0f;
const float DHT_VALID_TEMP_MAX_C = 60.0f;
const float DHT_VALID_HUM_MIN = 5.0f;
const float DHT_VALID_HUM_MAX = 100.0f;
const int ADC_FAULT_LOW = 50;
const int ADC_FAULT_HIGH = 4050;
const uint8_t ADC_FAULT_CONSECUTIVE = 4;
const int WATER_SHORT_ADC_LOW = 120;
const uint8_t WATER_SHORT_CONSECUTIVE = 2;
const float WATER_ADC_FILTER_ALPHA = 0.15f;
const float WATER_ALERT_RELEASE_MARGIN_PERCENT = 5.0f;

// ===== Cloud uplink =====
#ifndef WIFI_SSID_SECRET
#define WIFI_SSID_SECRET "YOUR_WIFI_SSID"
#endif
#ifndef WIFI_PASSWORD_SECRET
#define WIFI_PASSWORD_SECRET "YOUR_WIFI_PASSWORD"
#endif

const char* WIFI_SSID = WIFI_SSID_SECRET;
const char* WIFI_PASSWORD = WIFI_PASSWORD_SECRET;
const char* API_BASE_URL = "https://b4sm23mlze.execute-api.ap-southeast-5.amazonaws.com/prod";
const char* SITE_ZONE = "Zone A - Pump Station";
const char* FW_BUILD_ID = "FW_2026_06_05_WATER_SMOOTH_1300_1800";

// MQTT first, with optional HTTP fallback if MQTT publish fails.
const bool USE_MQTT_UPLINK = true;
const bool USE_HTTP_FALLBACK_IF_MQTT_FAILS = false;
// If MQTT is enabled but cert/endpoint is not configured:
// false = do not send (strict MQTT mode), true = fallback to HTTP.
const bool USE_HTTP_IF_MQTT_CONFIG_MISSING = false;

const char* MQTT_BROKER_ENDPOINT = MQTT_ENDPOINT;
const uint16_t MQTT_BROKER_PORT = 8883;
const char* MQTT_TOPIC = "alertrix/sensors/ingest";
const char* MQTT_CLIENT_ID = "alertrix-esp32-node01";

const char* AWS_ROOT_CA = MQTT_ROOT_CA;
const char* AWS_IOT_DEVICE_CERT = MQTT_DEVICE_CERT;
const char* AWS_IOT_PRIVATE_KEY = MQTT_DEVICE_PRIVATE_KEY;

const int VIBRATION_SAMPLE_COUNT = 120;
const unsigned long VIBRATION_SAMPLE_DELAY_US = 1000;
const float VIBRATION_RMS_ADC_PER_UNIT = 12.0f;
const float VIBRATION_NOISE_DEADBAND_ADC = 24.0f;
const float VIBRATION_LEVEL_MAX = 20.0f;
const uint8_t VIBRATION_BASELINE_WINDOWS = 40;
const unsigned long VIBRATION_STARTUP_REZERO_MS = 12000;

// Calibrate these two values using your own sensor:
// 1) dryValue: sensor out of water
// 2) wetValue: sensor in water at your "full" reference level
int dryValue = 1300;
int wetValue = 1800;

// Water can be sampled quickly, DHT11 should be read more slowly for stability.
const unsigned long WATER_READ_INTERVAL_MS = 500;
const unsigned long DHT_READ_INTERVAL_MS = 2000;
unsigned long lastWaterReadMs = 0;
unsigned long lastDhtReadMs = 0;
float lastTempC = NAN;
float lastHum = NAN;
uint8_t waterAdcFaultCount = 0;
uint8_t waterShortFaultCount = 0;
unsigned long lastWifiRetryMs = 0;
unsigned long wifiConnectStartMs = 0;
unsigned long lastWaterPostMs = 0;
unsigned long lastTempPostMs = 0;
unsigned long lastVibrationPostMs = 0;
int lastVibrationPeakToPeakAdc = 0;
float lastVibrationRmsAdc = 0.0f;
float vibrationBaselineRmsAdc = 0.0f;
bool vibrationStartupRezeroDone = false;

enum AlertSeverity : uint8_t {
  ALERT_NONE = 0,
  ALERT_WARNING = 1,
  ALERT_CRITICAL = 2,
};

float filteredWaterAdc = NAN;
AlertSeverity waterAlertState = ALERT_NONE;

struct VibrationStats {
  int peakToPeakAdc;
  float rmsAdc;
};

float adcToWaterLevelPercent(int adcValue);
float updateWaterAdcFilter(int rawAdc);
AlertSeverity waterSeverityForLevel(float value);
void printWaterCalibrationStatus();
VibrationStats readVibrationStats();
void calibrateVibrationBaseline(uint8_t windows);
float readVibrationLevel();

int waterCalDryCaptured = -1;
int waterCalWetCaptured = -1;

const unsigned long WATER_POST_INTERVAL_MS = 1000;
const unsigned long TEMP_POST_INTERVAL_MS = 2000;
const unsigned long VIBRATION_POST_INTERVAL_MS = 2000;
const unsigned long BUZZER_STATE_FETCH_INTERVAL_MS = 1000;
const unsigned long BUZZER_WARNING_PATTERN_MS = 2000;
const unsigned long BUZZER_WARNING_ON_MS = 300;
const unsigned long BUZZER_CRITICAL_PATTERN_MS = 1000;
const unsigned long BUZZER_CRITICAL_ON_MS = 120;
const unsigned long BUZZER_CRITICAL_GAP_MS = 120;

bool cloudBuzzerSilenced = false;
unsigned long lastBuzzerStateFetchMs = 0;
unsigned long lastBuzzerBeepStartMs = 0;
bool buzzerBeepActive = false;
AlertSeverity lastBuzzerSeverity = ALERT_NONE;

#if defined(ARDUINO_ARCH_ESP32)
WiFiClientSecure mqttNet;
PubSubClient mqttClient(mqttNet);
#endif

bool isValidDhtReading(float tempC, float hum) {
  if (isnan(tempC) || isnan(hum)) return false;
  if (tempC < DHT_VALID_TEMP_MIN_C || tempC > DHT_VALID_TEMP_MAX_C) return false;
  if (hum < DHT_VALID_HUM_MIN || hum > DHT_VALID_HUM_MAX) return false;
  return true;
}

#if defined(ARDUINO_ARCH_ESP32)
bool hasWifiConfig() {
  return strlen(WIFI_SSID) > 0 && strlen(WIFI_PASSWORD) > 0 &&
         strcmp(WIFI_SSID, "YOUR_WIFI_SSID") != 0 &&
         strcmp(WIFI_PASSWORD, "YOUR_WIFI_PASSWORD") != 0;
}

bool hasHttpConfig() {
  return strlen(API_BASE_URL) > 0 &&
         strstr(API_BASE_URL, "YOUR_API_BASE_URL") == nullptr;
}

bool hasPemContent(const char* pem) {
  if (!pem || strlen(pem) < 40) return false;
  if (strstr(pem, "YOUR_") != nullptr) return false;
  return strstr(pem, "BEGIN") != nullptr && strstr(pem, "END") != nullptr;
}

bool hasMqttConfig() {
  if (!USE_MQTT_UPLINK) return false;
  if (strlen(MQTT_BROKER_ENDPOINT) < 10) return false;
  if (strstr(MQTT_BROKER_ENDPOINT, "YOUR_AWS_IOT_ENDPOINT") != nullptr) return false;
  return hasPemContent(AWS_ROOT_CA) && hasPemContent(AWS_IOT_DEVICE_CERT) &&
         hasPemContent(AWS_IOT_PRIVATE_KEY);
}

bool ensureWiFiConnected() {
  wl_status_t status = WiFi.status();
  if (status == WL_CONNECTED) return true;

  const unsigned long now = millis();

  // If a connection attempt is already in progress, wait for it to complete
  // instead of calling WiFi.begin() repeatedly.
  if (status == WL_IDLE_STATUS) {
    if (wifiConnectStartMs > 0 && (now - wifiConnectStartMs) > 10000) {
      Serial.println("WiFi connect timeout, retrying...");
      WiFi.disconnect(true, true);
      wifiConnectStartMs = 0;
      lastWifiRetryMs = now;
    }
    return false;
  }

  if (now - lastWifiRetryMs < 3000) return false;
  lastWifiRetryMs = now;

  Serial.print("WiFi connecting to ");
  Serial.println(WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  wifiConnectStartMs = now;

  // Give a short non-blocking window for quick success on good networks.
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - start) < 1200) {
    delay(100);
  }

  if (WiFi.status() == WL_CONNECTED) {
    wifiConnectStartMs = 0;
    Serial.print("WiFi connected. IP=");
    Serial.println(WiFi.localIP());
    return true;
  }

  return false;
}

bool postReadingToApi(const char* sensorType, float value) {
  if (!ensureWiFiConnected()) return false;

  WiFiClientSecure client;
  client.setInsecure();  // Demo mode: skip cert pinning.

  HTTPClient http;
  String url = String(API_BASE_URL) + "/api/sensors/ingest";
  if (!http.begin(client, url)) {
    Serial.println("HTTP begin failed.");
    return false;
  }

  http.setTimeout(4000);
  http.addHeader("Content-Type", "application/json");

  String body = "{\"sensorType\":\"" + String(sensorType) + "\",\"value\":" + String(value, 2) +
                ",\"zone\":\"" + String(SITE_ZONE) + "\"}";
  int code = http.POST(body);
  bool ok = (code >= 200 && code < 300);
  if (!ok) {
    Serial.print("POST failed ");
    Serial.print(sensorType);
    Serial.print(" code=");
    Serial.println(code);
    String res = http.getString();
    if (res.length() > 0) {
      Serial.print("Response: ");
      Serial.println(res);
    }
  }
  http.end();
  return ok;
}

bool ensureMqttConnected() {
  if (!hasMqttConfig()) return false;
  if (mqttClient.connected()) return true;
  if (!ensureWiFiConnected()) return false;

  mqttNet.setCACert(AWS_ROOT_CA);
  mqttNet.setCertificate(AWS_IOT_DEVICE_CERT);
  mqttNet.setPrivateKey(AWS_IOT_PRIVATE_KEY);

  mqttClient.setServer(MQTT_BROKER_ENDPOINT, MQTT_BROKER_PORT);
  Serial.print("MQTT connecting to ");
  Serial.println(MQTT_BROKER_ENDPOINT);

  if (mqttClient.connect(MQTT_CLIENT_ID)) {
    Serial.println("MQTT connected.");
    return true;
  }

  Serial.print("MQTT connect failed, state=");
  Serial.println(mqttClient.state());
  return false;
}

bool publishReadingToMqtt(const char* sensorType, float value) {
  if (!ensureMqttConnected()) return false;

  String body = "{\"sensorType\":\"" + String(sensorType) + "\",\"value\":" + String(value, 2) +
                ",\"zone\":\"" + String(SITE_ZONE) + "\"}";
  const bool published = mqttClient.publish(MQTT_TOPIC, body.c_str());

  if (!published) {
    Serial.print("MQTT publish failed for ");
    Serial.print(sensorType);
    Serial.print(", state=");
    Serial.println(mqttClient.state());
  }
  return published;
}

bool sendReadingToCloud(const char* sensorType, float value) {
  if (USE_MQTT_UPLINK) {
    if (hasMqttConfig()) {
      if (publishReadingToMqtt(sensorType, value)) return true;
      if (!USE_HTTP_FALLBACK_IF_MQTT_FAILS) return false;
      Serial.println("MQTT publish failed, fallback to HTTP.");
    } else {
      Serial.println("MQTT config incomplete.");
      if (!USE_HTTP_IF_MQTT_CONFIG_MISSING) return false;
      Serial.println("Using HTTP fallback because MQTT config is incomplete.");
    }
  }

  if (hasHttpConfig()) {
    return postReadingToApi(sensorType, value);
  }

  return false;
}

String urlEncode(const String& input) {
  String out;
  out.reserve(input.length() * 3);
  const char* hex = "0123456789ABCDEF";
  for (size_t i = 0; i < input.length(); i++) {
    const uint8_t c = (uint8_t)input[i];
    const bool unreserved =
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~';
    if (unreserved) {
      out += (char)c;
    } else if (c == ' ') {
      out += "%20";
    } else {
      out += '%';
      out += hex[(c >> 4) & 0x0F];
      out += hex[c & 0x0F];
    }
  }
  return out;
}

bool fetchCloudBuzzerSilenced() {
  if (!hasHttpConfig()) return false;
  if (!ensureWiFiConnected()) return cloudBuzzerSilenced;

  WiFiClientSecure client;
  client.setInsecure();  // Demo mode: skip cert pinning.

  HTTPClient http;
  String url = String(API_BASE_URL) + "/api/device/buzzer/state?zone=" + urlEncode(String(SITE_ZONE));
  if (!http.begin(client, url)) {
    Serial.println("Buzzer state HTTP begin failed.");
    return cloudBuzzerSilenced;
  }

  http.setTimeout(2500);
  int code = http.GET();
  if (code < 200 || code >= 300) {
    Serial.print("Buzzer state GET failed code=");
    Serial.println(code);
    http.end();
    return cloudBuzzerSilenced;
  }

  String res = http.getString();
  http.end();
  if (res.indexOf("\"silenced\":true") >= 0) return true;
  if (res.indexOf("\"silenced\":false") >= 0) return false;
  return cloudBuzzerSilenced;
}
#endif

int readWaterAdc() {
  // Trim one high and one low sample, then average the rest.
  const int samples = 20;
  long sum = 0;
  int minValue = 4095;
  int maxValue = 0;
  for (int i = 0; i < samples; i++) {
    const int value = analogRead(WATER_SENSOR_AO_PIN);
    sum += value;
    if (value < minValue) minValue = value;
    if (value > maxValue) maxValue = value;
    delay(5);
  }
  return (int)((sum - minValue - maxValue) / (samples - 2));
}

float updateWaterAdcFilter(int rawAdc) {
  if (isnan(filteredWaterAdc)) {
    filteredWaterAdc = (float)rawAdc;
  } else {
    filteredWaterAdc += WATER_ADC_FILTER_ALPHA * ((float)rawAdc - filteredWaterAdc);
  }
  return filteredWaterAdc;
}

float clampVibrationLevel(float level) {
  if (level < 0.0f) return 0.0f;
  if (level > VIBRATION_LEVEL_MAX) return VIBRATION_LEVEL_MAX;
  return level;
}

const char* alertSeverityLabel(AlertSeverity severity) {
  switch (severity) {
    case ALERT_CRITICAL: return "CRITICAL";
    case ALERT_WARNING: return "WARNING";
    case ALERT_NONE:
    default: return "NORMAL";
  }
}

AlertSeverity maxSeverity(AlertSeverity left, AlertSeverity right) {
  return (left > right) ? left : right;
}

AlertSeverity severityForValue(float value, float warningThreshold, float criticalThreshold) {
  if (value >= criticalThreshold) return ALERT_CRITICAL;
  if (value >= warningThreshold) return ALERT_WARNING;
  return ALERT_NONE;
}

AlertSeverity waterSeverityForLevel(float value) {
  if (waterAlertState == ALERT_CRITICAL) {
    if (value < WATER_LEVEL_WARNING_PERCENT - WATER_ALERT_RELEASE_MARGIN_PERCENT) {
      waterAlertState = ALERT_NONE;
    } else if (value < WATER_LEVEL_CRITICAL_PERCENT - WATER_ALERT_RELEASE_MARGIN_PERCENT) {
      waterAlertState = ALERT_WARNING;
    }
    return waterAlertState;
  }

  if (waterAlertState == ALERT_WARNING) {
    if (value >= WATER_LEVEL_CRITICAL_PERCENT) {
      waterAlertState = ALERT_CRITICAL;
    } else if (value < WATER_LEVEL_WARNING_PERCENT - WATER_ALERT_RELEASE_MARGIN_PERCENT) {
      waterAlertState = ALERT_NONE;
    }
    return waterAlertState;
  }

  waterAlertState = severityForValue(value, WATER_LEVEL_WARNING_PERCENT, WATER_LEVEL_CRITICAL_PERCENT);
  return waterAlertState;
}

void printVibrationCommandHelp() {
  Serial.println("VIB commands:");
  Serial.println("  VIB HELP          -> show this help");
  Serial.println("  VIB ZERO          -> calibrate current still sensor as zero baseline");
  Serial.println("  VIB STATUS        -> print current real sensor baseline");
  Serial.println("Water calibration: type WL HELP");
}

void printWaterCalibrationHelp() {
  Serial.println("WL calibration commands:");
  Serial.println("  WL HELP           -> show water calibration help");
  Serial.println("  WL SAMPLE         -> print current water ADC and WL%");
  Serial.println("  WL DRY            -> capture DRY point (probe out of water)");
  Serial.println("  WL WET            -> capture WET point (probe in water)");
  Serial.println("  WL CAL            -> print suggested dryValue/wetValue");
  Serial.println("  WL APPLY          -> apply captured DRY/WET now");
  Serial.println("  WL STATUS         -> show current config and captures");
}

void handleSerialCommands() {
  if (!Serial.available()) return;
  String cmd = Serial.readStringUntil('\n');
  cmd.trim();
  if (cmd.length() == 0) return;

  String upper = cmd;
  upper.toUpperCase();

  if (upper == "VIB HELP") {
    printVibrationCommandHelp();
    return;
  }

  if (upper == "VIB ZERO") {
    Serial.println("VIB zero calibration: keep the sensor still...");
    calibrateVibrationBaseline(VIBRATION_BASELINE_WINDOWS);
    Serial.print("VIB zero baseline RMS_ADC=");
    Serial.println(vibrationBaselineRmsAdc, 2);
    return;
  }

  if (upper == "VIB STATUS") {
    Serial.print("VIB source=REAL_AO, baseline_rms_adc=");
    Serial.print(vibrationBaselineRmsAdc, 2);
    Serial.print(", last_rms_adc=");
    Serial.print(lastVibrationRmsAdc, 2);
    Serial.print(", adc_per_unit=");
    Serial.print(VIBRATION_RMS_ADC_PER_UNIT, 2);
    Serial.print(", deadband_adc=");
    Serial.print(VIBRATION_NOISE_DEADBAND_ADC, 2);
    Serial.print(", max=");
    Serial.println(VIBRATION_LEVEL_MAX, 2);
    return;
  }

  if (upper == "WL HELP") {
    printWaterCalibrationHelp();
    return;
  }

  if (upper == "WL SAMPLE") {
    int adc = readWaterAdc();
    Serial.print("WL sample ADC=");
    Serial.print(adc);
    Serial.print(", WL=");
    Serial.print(adcToWaterLevelPercent(adc), 2);
    Serial.println("%");
    return;
  }

  if (upper == "WL DRY") {
    waterCalDryCaptured = readWaterAdc();
    Serial.print("Captured WL DRY ADC=");
    Serial.println(waterCalDryCaptured);
    printWaterCalibrationStatus();
    return;
  }

  if (upper == "WL WET") {
    waterCalWetCaptured = readWaterAdc();
    Serial.print("Captured WL WET ADC=");
    Serial.println(waterCalWetCaptured);
    printWaterCalibrationStatus();
    return;
  }

  if (upper == "WL CAL" || upper == "WL STATUS") {
    printWaterCalibrationStatus();
    return;
  }

  if (upper == "WL APPLY") {
    if (waterCalDryCaptured < 0 || waterCalWetCaptured < 0) {
      Serial.println("WL APPLY failed: capture both points first (WL DRY + WL WET).");
      return;
    }
    if (waterCalWetCaptured <= waterCalDryCaptured) {
      Serial.println("WL APPLY failed: WET ADC must be greater than DRY ADC.");
      Serial.println("Check wiring/sensor direction and capture again.");
      return;
    }
    dryValue = waterCalDryCaptured;
    wetValue = waterCalWetCaptured;
    filteredWaterAdc = NAN;
    waterAlertState = ALERT_NONE;
    Serial.print("WL applied: dryValue=");
    Serial.print(dryValue);
    Serial.print(", wetValue=");
    Serial.println(wetValue);
    return;
  }

  Serial.print("Unknown command: ");
  Serial.println(cmd);
  Serial.println("Type VIB HELP or WL HELP for available commands.");
}

float adcToWaterLevelPercent(int adcValue) {
  if (wetValue == dryValue) return 0.0f;
  float percent = (float)(adcValue - dryValue) * 100.0f / (float)(wetValue - dryValue);
  if (percent < 0.0f) percent = 0.0f;
  if (percent > 100.0f) percent = 100.0f;
  return percent;
}

void printWaterCalibrationStatus() {
  Serial.print("WL config dryValue=");
  Serial.print(dryValue);
  Serial.print(", wetValue=");
  Serial.print(wetValue);
  Serial.print(", delta=");
  Serial.println(wetValue - dryValue);

  Serial.print("WL captured dry=");
  Serial.print(waterCalDryCaptured);
  Serial.print(", wet=");
  Serial.println(waterCalWetCaptured);

  if (waterCalDryCaptured < 0 || waterCalWetCaptured < 0) {
    Serial.println("To calibrate: run WL DRY, then WL WET, then WL CAL.");
    return;
  }

  if (waterCalWetCaptured <= waterCalDryCaptured) {
    Serial.println("Captured values invalid: wet must be greater than dry.");
    return;
  }

  Serial.println("Suggested code values:");
  Serial.print("  int dryValue = ");
  Serial.print(waterCalDryCaptured);
  Serial.println(";");
  Serial.print("  int wetValue = ");
  Serial.print(waterCalWetCaptured);
  Serial.println(";");
  Serial.println("Use WL APPLY to test immediately without reflashing.");
}

VibrationStats readVibrationStats() {
  int minValue = 4095;
  int maxValue = 0;
  long sum = 0;
  int samples[VIBRATION_SAMPLE_COUNT];

  for (int i = 0; i < VIBRATION_SAMPLE_COUNT; i++) {
    const int value = analogRead(VIBRATION_SENSOR_AO_PIN);
    samples[i] = value;
    sum += value;
    if (value < minValue) minValue = value;
    if (value > maxValue) maxValue = value;
    delayMicroseconds(VIBRATION_SAMPLE_DELAY_US);
  }

  const float mean = (float)sum / (float)VIBRATION_SAMPLE_COUNT;
  float squareSum = 0.0f;
  for (int i = 0; i < VIBRATION_SAMPLE_COUNT; i++) {
    const float centered = (float)samples[i] - mean;
    squareSum += centered * centered;
  }

  VibrationStats stats;
  stats.peakToPeakAdc = maxValue - minValue;
  stats.rmsAdc = sqrt(squareSum / (float)VIBRATION_SAMPLE_COUNT);
  return stats;
}

void calibrateVibrationBaseline(uint8_t windows) {
  if (windows == 0) windows = 1;
  float sum = 0.0f;
  for (uint8_t i = 0; i < windows; i++) {
    VibrationStats stats = readVibrationStats();
    sum += stats.rmsAdc;
  }
  vibrationBaselineRmsAdc = sum / (float)windows;
}

float readVibrationLevel() {
  VibrationStats stats = readVibrationStats();
  lastVibrationPeakToPeakAdc = stats.peakToPeakAdc;
  lastVibrationRmsAdc = stats.rmsAdc;

  const float dynamicRmsAdc = stats.rmsAdc - vibrationBaselineRmsAdc;
  if (dynamicRmsAdc <= VIBRATION_NOISE_DEADBAND_ADC) return 0.0f;

  const float level = (dynamicRmsAdc - VIBRATION_NOISE_DEADBAND_ADC) / VIBRATION_RMS_ADC_PER_UNIT;
  return clampVibrationLevel(level);
}

bool buzzerPulseOn(AlertSeverity severity, unsigned long elapsedMs) {
  if (severity == ALERT_WARNING) {
    return (elapsedMs % BUZZER_WARNING_PATTERN_MS) < BUZZER_WARNING_ON_MS;
  }

  if (severity == ALERT_CRITICAL) {
    const unsigned long phase = elapsedMs % BUZZER_CRITICAL_PATTERN_MS;
    const unsigned long secondStart = BUZZER_CRITICAL_ON_MS + BUZZER_CRITICAL_GAP_MS;
    const unsigned long thirdStart = secondStart + BUZZER_CRITICAL_ON_MS + BUZZER_CRITICAL_GAP_MS;
    return phase < BUZZER_CRITICAL_ON_MS ||
           (phase >= secondStart && phase < secondStart + BUZZER_CRITICAL_ON_MS) ||
           (phase >= thirdStart && phase < thirdStart + BUZZER_CRITICAL_ON_MS);
  }

  return false;
}

bool updateBuzzer(AlertSeverity severity, unsigned long now) {
  if (severity == ALERT_NONE) {
    buzzerBeepActive = false;
    lastBuzzerBeepStartMs = 0;
    lastBuzzerSeverity = ALERT_NONE;
    digitalWrite(BUZZER_PIN, LOW);
    return false;
  }

  if (!buzzerBeepActive || severity != lastBuzzerSeverity) {
    buzzerBeepActive = true;
    lastBuzzerBeepStartMs = now;
    lastBuzzerSeverity = severity;
  }

  const bool pulseOn = buzzerPulseOn(severity, now - lastBuzzerBeepStartMs);
  digitalWrite(BUZZER_PIN, pulseOn ? HIGH : LOW);
  return pulseOn;
}

void setup() {
  Serial.begin(115200);
  dht.begin();
  delay(2000);  // DHT11 startup stabilization

  pinMode(WATER_SENSOR_AO_PIN, INPUT);
  pinMode(VIBRATION_SENSOR_AO_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

#if defined(ARDUINO_ARCH_ESP32)
  analogReadResolution(12);  // 0..4095
  analogSetPinAttenuation(WATER_SENSOR_AO_PIN, ADC_11db);
  analogSetPinAttenuation(VIBRATION_SENSOR_AO_PIN, ADC_11db);
#endif

  Serial.println("DHT11 + Water Level + Buzzer practice started.");
  Serial.print("Build=");
  Serial.println(FW_BUILD_ID);
  Serial.println("Buzzer mode: continuous while ALARM=ON; stops when alert clears or cloud silence is requested.");
  Serial.println("Buzzer tones: WARNING slow pulse, CRITICAL rapid triple pulse.");
  Serial.print("FW WIFI_SSID=");
  Serial.println(WIFI_SSID);
  Serial.println("Format: T=xx.x,H=yy.y,ADC_RAW=zzzz,ADC=zzzz,WL=pp.pp,VIB=n.nn,VIB_RMS_ADC=n.nn,VIB_ADC_PP=n,VIB_BASE_ADC=n.nn,VIB_SOURCE=text,SEVERITY=text,ALARM=ON/OFF,BUZZER=ON/OFF,ADC_FAULT=n,WATER_SHORT=n,STATUS=text");
  Serial.println("VIB is a calibrated vibration RMS index from the AO signal on GPIO1.");
  Serial.print("VIB adc_per_unit=");
  Serial.print(VIBRATION_RMS_ADC_PER_UNIT, 2);
  Serial.print(", VIB max=");
  Serial.println(VIBRATION_LEVEL_MAX, 2);
  Serial.println("Vibration commands: VIB HELP / VIB ZERO / VIB STATUS");
  Serial.println("Water calibration: WL HELP / WL DRY / WL WET / WL CAL / WL APPLY");
  Serial.println("Tip: if DHT stays nan, try DHT data pin on GPIO6/7 and keep common GND.");

#if defined(ARDUINO_ARCH_ESP32)
  if (!hasWifiConfig()) {
    Serial.println("Cloud disabled: fill WIFI_SSID / WIFI_PASSWORD first.");
  } else {
    ensureWiFiConnected();
    if (USE_MQTT_UPLINK && hasMqttConfig()) {
      Serial.println("Cloud uplink mode: MQTT (AWS IoT Core)");
    } else if (USE_MQTT_UPLINK && USE_HTTP_IF_MQTT_CONFIG_MISSING) {
      Serial.println("Cloud uplink mode: HTTP fallback (MQTT config incomplete).");
    } else if (USE_MQTT_UPLINK) {
      Serial.println("Cloud uplink mode: strict MQTT (waiting for MQTT config).");
    } else if (hasHttpConfig()) {
      Serial.println("Cloud uplink mode: HTTP API direct");
    } else {
      Serial.println("Cloud uplink disabled: fill MQTT or HTTP config first.");
    }
  }
#endif

  Serial.println("Keep the vibration sensor still for baseline calibration...");
  calibrateVibrationBaseline(VIBRATION_BASELINE_WINDOWS);
  Serial.print("VIB baseline RMS_ADC=");
  Serial.println(vibrationBaselineRmsAdc, 2);
  Serial.println("Keep still again: VIB auto-zero will refine baseline after startup.");
}

void loop() {
  handleSerialCommands();

  unsigned long now = millis();
  if (!vibrationStartupRezeroDone && now >= VIBRATION_STARTUP_REZERO_MS) {
    vibrationStartupRezeroDone = true;
    Serial.println("VIB startup auto-zero: keep the sensor still...");
    calibrateVibrationBaseline(VIBRATION_BASELINE_WINDOWS);
    Serial.print("VIB startup baseline RMS_ADC=");
    Serial.println(vibrationBaselineRmsAdc, 2);
  }

  if (now - lastWaterReadMs < WATER_READ_INTERVAL_MS) return;
  lastWaterReadMs = now;

  if (now - lastDhtReadMs >= DHT_READ_INTERVAL_MS) {
    lastDhtReadMs = now;
    float t = dht.readTemperature();
    float h = dht.readHumidity();
    if (isValidDhtReading(t, h)) {
      lastTempC = t;
      lastHum = h;
    } else {
      Serial.print("DHT glitch ignored. raw T=");
      Serial.print(t, 1);
      Serial.print(", raw H=");
      Serial.println(h, 1);
    }
  }

  float tempC = lastTempC;
  float hum = lastHum;
  int rawWaterAdc = readWaterAdc();
  const bool waterShortSample = rawWaterAdc <= WATER_SHORT_ADC_LOW;
  if (waterShortSample) {
    if (waterShortFaultCount < 255) waterShortFaultCount++;
  } else {
    waterShortFaultCount = 0;
  }
  const bool waterShortFault = waterShortFaultCount >= WATER_SHORT_CONSECUTIVE;

  int waterAdc = isnan(filteredWaterAdc) ? rawWaterAdc : (int)(filteredWaterAdc + 0.5f);
  if (!waterShortFault) {
    waterAdc = (int)(updateWaterAdcFilter(rawWaterAdc) + 0.5f);
  }
  float waterLevelPercent = adcToWaterLevelPercent(waterAdc);
  float vibrationLevel = readVibrationLevel();
  const bool waterAdcOutOfRange = !waterShortFault && (waterAdc < ADC_FAULT_LOW || waterAdc > ADC_FAULT_HIGH);
  if (waterAdcOutOfRange) {
    if (waterAdcFaultCount < 255) waterAdcFaultCount++;
  } else {
    waterAdcFaultCount = 0;
  }
  const bool waterAdcFault = waterAdcFaultCount >= ADC_FAULT_CONSECUTIVE;

  const AlertSeverity tempSeverity = isnan(tempC)
      ? ALERT_NONE
      : severityForValue(tempC, TEMP_WARNING_C, TEMP_CRITICAL_C);
  if (waterAdcFault) waterAlertState = ALERT_NONE;
  const AlertSeverity waterSeverity = waterShortFault
      ? ALERT_CRITICAL
      : (waterAdcFault ? ALERT_NONE : waterSeverityForLevel(waterLevelPercent));
  const AlertSeverity vibrationSeverity =
      severityForValue(vibrationLevel, VIBRATION_WARNING_LEVEL, VIBRATION_CRITICAL_LEVEL);
  const AlertSeverity alertSeverity =
      maxSeverity(tempSeverity, maxSeverity(waterSeverity, vibrationSeverity));
  const bool alarm = alertSeverity != ALERT_NONE;

#if defined(ARDUINO_ARCH_ESP32)
  if (hasWifiConfig() && hasHttpConfig() &&
      (now - lastBuzzerStateFetchMs >= BUZZER_STATE_FETCH_INTERVAL_MS)) {
    lastBuzzerStateFetchMs = now;
    cloudBuzzerSilenced = fetchCloudBuzzerSilenced();
  }
#endif

  const AlertSeverity buzzerSeverity = cloudBuzzerSilenced ? ALERT_NONE : alertSeverity;
  const bool buzzerOutputOn = updateBuzzer(buzzerSeverity, now);

  Serial.print("T=");
  if (isnan(tempC)) Serial.print("nan"); else Serial.print(tempC, 1);
  Serial.print(",H=");
  if (isnan(hum)) Serial.print("nan"); else Serial.print(hum, 1);
  Serial.print(",ADC_RAW=");
  Serial.print(rawWaterAdc);
  Serial.print(",ADC=");
  Serial.print(waterAdc);
  Serial.print(",WL=");
  if (waterLevelPercent < 0) Serial.print("nan"); else Serial.print(waterLevelPercent, 2);
  Serial.print(",VIB=");
  Serial.print(vibrationLevel, 2);
  Serial.print(",VIB_RMS_ADC=");
  Serial.print(lastVibrationRmsAdc, 2);
  Serial.print(",VIB_ADC_PP=");
  Serial.print(lastVibrationPeakToPeakAdc);
  Serial.print(",VIB_BASE_ADC=");
  Serial.print(vibrationBaselineRmsAdc, 2);
  Serial.print(",VIB_SOURCE=REAL_AO");
  Serial.print(",SEVERITY=");
  Serial.print(alertSeverityLabel(alertSeverity));
  Serial.print(",ALARM=");
  Serial.print(alarm ? "ON" : "OFF");
  Serial.print(",BUZZER=");
  Serial.print(buzzerOutputOn ? "ON" : "OFF");
  Serial.print(",ADC_FAULT=");
  Serial.print(waterAdcFaultCount);
  Serial.print(",WATER_SHORT=");
  Serial.print(waterShortFaultCount);
  Serial.print(",CLOUD_SILENCE=");
  Serial.print(cloudBuzzerSilenced ? "ON" : "OFF");
  Serial.print(",");

  if (isnan(tempC) || isnan(hum)) {
    Serial.println("DHT_ERR");
  } else if (waterShortFault) {
    Serial.println("WATER_SHORT_OR_SUBMERGED");
  } else if (waterAdcFault) {
    Serial.println("WATER_WIRING_OR_PIN_ERR");
  } else {
    Serial.println("OK");
  }

#if defined(ARDUINO_ARCH_ESP32)
  if (hasWifiConfig()) {
    if (hasMqttConfig()) {
      mqttClient.loop();
    }

    if (!waterAdcFault && !waterShortFault && (now - lastWaterPostMs >= WATER_POST_INTERVAL_MS)) {
      if (sendReadingToCloud("waterLevel", waterLevelPercent)) {
        lastWaterPostMs = now;
      }
    }

    if (!isnan(tempC) && (now - lastTempPostMs >= TEMP_POST_INTERVAL_MS)) {
      if (sendReadingToCloud("temperature", tempC)) {
        lastTempPostMs = now;
      }
    }

    if (now - lastVibrationPostMs >= VIBRATION_POST_INTERVAL_MS) {
      if (sendReadingToCloud("vibration", vibrationLevel)) {
        lastVibrationPostMs = now;
      }
    }
  }
#endif
}
