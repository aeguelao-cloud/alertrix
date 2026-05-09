# Alertrix (Flutter + AWS Lambda + Arduino)

## Time Ranges (Frontend + Backend)
Supported trend windows are:

- `1H`
- `6H`
- `24H`
- `7D`
- `14D`
- `30D`

These are already wired end-to-end in:

- Frontend labels and selectors: `/lib/config/metrics_config.dart`
- Dashboard trend chips: `/lib/pages/dashboard_page.dart`
- Trends page selector: `/lib/pages/trends_page.dart`
- Backend trend API parsing and sampling: `/backend/src/handlers/getTrends.js`

## Run Frontend
From project root:

```powershell
cd F:\403\demo
flutter run -d chrome --web-port 18082 --dart-define=API_BASE_URL=https://<your-api-id>.execute-api.<region>.amazonaws.com/prod
```

If port is occupied, change `18082` to another free port (for example `18090`).

## Arduino Cloud Uplink Modes
Main sketch:

- `F:\403\demo\arduino\DHT11WaterLevelPractice\DHT11WaterLevelPractice.ino`

Cloud mode switches in sketch:

- `USE_MQTT_UPLINK = true`  
  Use AWS IoT Core MQTT first.
- `USE_HTTP_FALLBACK_IF_MQTT_FAILS = true`  
  If MQTT publish fails, fallback to HTTP `/api/sensors/ingest`.
- `USE_HTTP_IF_MQTT_CONFIG_MISSING = true`  
  If MQTT cert/endpoint not configured yet, still allow HTTP fallback.

To enforce strict MQTT only, set:

```cpp
const bool USE_HTTP_IF_MQTT_CONFIG_MISSING = false;
const bool USE_HTTP_FALLBACK_IF_MQTT_FAILS = false;
```

## MQTT Setup (AWS IoT Core)
1. In AWS IoT Core, create Thing + certificates.
2. Fill these values in the sketch:
   - `MQTT_BROKER_ENDPOINT`
   - `AWS_ROOT_CA`
   - `AWS_IOT_DEVICE_CERT`
   - `AWS_IOT_PRIVATE_KEY`
3. Keep topic:
   - `alertrix/sensors/ingest`
4. Backend already has IoT Rule event in SAM template:
   - `IngestSensorDataFromIoT` in `/backend/template.yaml`

When serial monitor shows `Cloud uplink mode: MQTT (AWS IoT Core)`, Arduino is publishing via MQTT.

## Backend Deploy (SAM)
From backend folder:

```powershell
cd F:\403\demo\backend
C:\Users\JUN\AppData\Roaming\Python\Python314\Scripts\sam.exe build
C:\Users\JUN\AppData\Roaming\Python\Python314\Scripts\sam.exe deploy
```

If `sam` command is not in PATH, use full executable path as above.
