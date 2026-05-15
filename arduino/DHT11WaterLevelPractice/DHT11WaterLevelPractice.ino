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
const uint8_t WATER_SENSOR_AO_PIN = 11;  // connect to AO of red water sensor
const uint8_t BUZZER_PIN = 14;
const uint8_t ULTRASONIC_TRIG_PIN = 5;
const uint8_t ULTRASONIC_ECHO_PIN = 6;

#define DHTTYPE DHT11
DHT dht(DHT_PIN, DHTTYPE);

// ===== Thresholds =====
const float TEMP_HIGH_C = 35.0f;
const float WATER_LEVEL_HIGH_PERCENT = 80.0f;
const float DHT_VALID_TEMP_MIN_C = 10.0f;
const float DHT_VALID_TEMP_MAX_C = 60.0f;
const float DHT_VALID_HUM_MIN = 5.0f;
const float DHT_VALID_HUM_MAX = 100.0f;
const int ADC_FAULT_LOW = 50;
const int ADC_FAULT_HIGH = 4050;
const uint8_t ADC_FAULT_CONSECUTIVE = 4;

// ===== Cloud uplink =====
const char* WIFI_SSID = "HIGHERGROUND";
const char* WIFI_PASSWORD = "higherground";
const char* API_BASE_URL = "https://b4sm23mlze.execute-api.ap-southeast-5.amazonaws.com/prod";
const char* SITE_ZONE = "Zone A - Pump Station";
const char* FW_BUILD_ID = "FW_2026_04_26_MQTT_ONLY_HIGHERGROUND";

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

// Use ultrasonic sensor (Trig/Echo) as vibration channel value for now.
const bool SEND_VIBRATION_FROM_ULTRASONIC = true;
const float ULTRASONIC_INVALID_VALUE = -1.0f;

// Calibrate these two values using your own sensor:
// 1) dryValue: sensor out of water
// 2) wetValue: sensor in water at your "full" reference level
int dryValue = 700;
int wetValue = 1700;

// Water can be sampled quickly, DHT11 should be read more slowly for stability.
const unsigned long WATER_READ_INTERVAL_MS = 500;
const unsigned long DHT_READ_INTERVAL_MS = 2000;
unsigned long lastWaterReadMs = 0;
unsigned long lastDhtReadMs = 0;
float lastTempC = NAN;
float lastHum = NAN;
uint8_t waterAdcFaultCount = 0;
unsigned long lastWifiRetryMs = 0;
unsigned long wifiConnectStartMs = 0;
unsigned long lastWaterPostMs = 0;
unsigned long lastTempPostMs = 0;
unsigned long lastVibrationPostMs = 0;

const unsigned long WATER_POST_INTERVAL_MS = 1000;
const unsigned long TEMP_POST_INTERVAL_MS = 2000;
const unsigned long VIBRATION_POST_INTERVAL_MS = 2000;
const unsigned long BUZZER_STATE_FETCH_INTERVAL_MS = 1000;

bool cloudBuzzerSilenced = false;
unsigned long lastBuzzerStateFetchMs = 0;

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
         strcmp(WIFI_SSID, "cslab") != 0 &&
         strcmp(WIFI_PASSWORD, "aksesg31") != 0;
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
  // Small averaging to reduce jitter.
  const int samples = 10;
  long sum = 0;
  for (int i = 0; i < samples; i++) {
    sum += analogRead(WATER_SENSOR_AO_PIN);
    delay(5);
  }
  return (int)(sum / samples);
}

float adcToWaterLevelPercent(int adcValue) {
  if (wetValue == dryValue) return 0.0f;
  float percent = (float)(adcValue - dryValue) * 100.0f / (float)(wetValue - dryValue);
  if (percent < 0.0f) percent = 0.0f;
  if (percent > 100.0f) percent = 100.0f;
  return percent;
}

float readUltrasonicDistanceCm() {
  digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(ULTRASONIC_TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(ULTRASONIC_TRIG_PIN, LOW);

  const unsigned long durationUs = pulseIn(ULTRASONIC_ECHO_PIN, HIGH, 30000UL);
  if (durationUs == 0) return ULTRASONIC_INVALID_VALUE;
  return (float)durationUs * 0.0343f / 2.0f;
}

void setup() {
  Serial.begin(115200);
  dht.begin();
  delay(2000);  // DHT11 startup stabilization

  pinMode(WATER_SENSOR_AO_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(ULTRASONIC_TRIG_PIN, OUTPUT);
  pinMode(ULTRASONIC_ECHO_PIN, INPUT);
  digitalWrite(BUZZER_PIN, LOW);

#if defined(ARDUINO_ARCH_ESP32)
  analogReadResolution(12);  // 0..4095
  analogSetPinAttenuation(WATER_SENSOR_AO_PIN, ADC_11db);
#endif

  Serial.println("DHT11 + Water Level + Buzzer practice started.");
  Serial.print("Build=");
  Serial.println(FW_BUILD_ID);
  Serial.print("FW WIFI_SSID=");
  Serial.println(WIFI_SSID);
  Serial.println("Format: T=xx.x,H=yy.y,ADC=zzzz,WL=pp.pp,ALARM=ON/OFF,ADC_FAULT=n,STATUS=text");
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
}

void loop() {
  unsigned long now = millis();
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
  int waterAdc = readWaterAdc();
  float waterLevelPercent = adcToWaterLevelPercent(waterAdc);
  float ultrasonicDistanceCm = readUltrasonicDistanceCm();
  const bool waterAdcOutOfRange = (waterAdc < ADC_FAULT_LOW || waterAdc > ADC_FAULT_HIGH);
  if (waterAdcOutOfRange) {
    if (waterAdcFaultCount < 255) waterAdcFaultCount++;
  } else {
    waterAdcFaultCount = 0;
  }
  const bool waterAdcFault = waterAdcFaultCount >= ADC_FAULT_CONSECUTIVE;

  bool tempBad = !isnan(tempC) && tempC >= TEMP_HIGH_C;
  bool waterBad = !waterAdcFault && waterLevelPercent >= WATER_LEVEL_HIGH_PERCENT;
  bool alarm = tempBad || waterBad;

#if defined(ARDUINO_ARCH_ESP32)
  if (hasWifiConfig() && hasHttpConfig() &&
      (now - lastBuzzerStateFetchMs >= BUZZER_STATE_FETCH_INTERVAL_MS)) {
    lastBuzzerStateFetchMs = now;
    cloudBuzzerSilenced = fetchCloudBuzzerSilenced();
  }
#endif

  const bool buzzerActive = alarm && !cloudBuzzerSilenced;
  digitalWrite(BUZZER_PIN, buzzerActive ? HIGH : LOW);

  Serial.print("T=");
  if (isnan(tempC)) Serial.print("nan"); else Serial.print(tempC, 1);
  Serial.print(",H=");
  if (isnan(hum)) Serial.print("nan"); else Serial.print(hum, 1);
  Serial.print(",ADC=");
  Serial.print(waterAdc);
  Serial.print(",WL=");
  if (waterLevelPercent < 0) Serial.print("nan"); else Serial.print(waterLevelPercent, 2);
  Serial.print(",US_CM=");
  if (ultrasonicDistanceCm < 0) Serial.print("nan"); else Serial.print(ultrasonicDistanceCm, 1);
  Serial.print(",ALARM=");
  Serial.print(alarm ? "ON" : "OFF");
  Serial.print(",ADC_FAULT=");
  Serial.print(waterAdcFaultCount);
  Serial.print(",CLOUD_SILENCE=");
  Serial.print(cloudBuzzerSilenced ? "ON" : "OFF");
  Serial.print(",");

  if (isnan(tempC) || isnan(hum)) {
    Serial.println("DHT_ERR");
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

    if (!waterAdcFault && (now - lastWaterPostMs >= WATER_POST_INTERVAL_MS)) {
      if (sendReadingToCloud("waterLevel", waterLevelPercent)) {
        lastWaterPostMs = now;
      }
    }

    if (!isnan(tempC) && (now - lastTempPostMs >= TEMP_POST_INTERVAL_MS)) {
      if (sendReadingToCloud("temperature", tempC)) {
        lastTempPostMs = now;
      }
    }

    if (SEND_VIBRATION_FROM_ULTRASONIC &&
        ultrasonicDistanceCm >= 0 &&
        (now - lastVibrationPostMs >= VIBRATION_POST_INTERVAL_MS)) {
      if (sendReadingToCloud("vibration", ultrasonicDistanceCm)) {
        lastVibrationPostMs = now;
      }
    }
  }
#endif
}
