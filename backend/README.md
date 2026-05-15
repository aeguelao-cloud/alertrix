# Alertrix AWS Lambda + API

This backend supports:
- Sensor ingest and anomaly detection
- Alert/work-order APIs
- FCM token registration
- FCM test push and anomaly push

## Endpoints

- `GET /api/readings/latest`
- `GET /api/app/bootstrap`
- `GET /api/trends?metric=water_level&range=24h`
- `GET /api/alerts`
- `POST /api/alerts/{alertId}/status`
- `POST /api/alerts/{alertId}/work-orders`
- `POST /api/push/register-token`
- `POST /api/push/test-alert`
- `POST /api/sensors/ingest`

## Page layout aligned API

`GET /api/app/bootstrap` is designed for the rebuilt UI structure and returns:

- role-based `navigation`
- `responseOverview` summary and incident highlights
- `incidentQueue` counts and severity filters
- `responseSettings` grouped policy/threshold/notification/site data
- admin-only blocks for `adminManagement` and `workOrders`

Role context comes from request headers `X-User-Role` and `X-User-Id`.

## Device ingest flow (MQTT-first)

1. ESP32 publishes sensor data to MQTT topic `alertrix/sensors/ingest` (AWS IoT Core).
2. IoT Rule triggers Lambda `IngestSensorDataFunction`.
3. Lambda stores sensor data / alerts in DynamoDB and sends push notifications.
4. HTTP endpoint `POST /api/sensors/ingest` remains available as compatibility fallback.

Accepted ingest payload fields:

```json
{
  "sensorType": "waterLevel",
  "value": 91,
  "zone": "Zone A - Pump Station",
  "capturedAt": "2026-05-14T12:00:00Z"
}
```

## FCM flow

1. Flutter gets FCM token via `firebase_messaging`.
2. Flutter sends token to `POST /api/push/register-token`.
3. Lambda (`/api/sensors/ingest`) detects threshold breach and sends multicast FCM push.
4. You can manually test push via `POST /api/push/test-alert`.

## Required deploy parameter

Set `FirebaseServiceAccountJson` during `sam deploy --guided`.
Use a minified JSON string of your Firebase service account key.

## Local setup on this machine

- `aws`: `C:\Users\JUN\AppData\Roaming\Python\Python314\Scripts\aws.cmd`
- `sam`: `C:\Users\JUN\AppData\Roaming\Python\Python314\Scripts\sam.exe`

## Build and deploy

```powershell
cd F:\403\demo\backend
npm install
C:\Users\JUN\AppData\Roaming\Python\Python314\Scripts\sam.exe build
C:\Users\JUN\AppData\Roaming\Python\Python314\Scripts\sam.exe deploy --guided
```

## Test examples

Register token:

```json
{
  "token": "<fcm_token>",
  "userId": "operator01",
  "platform": "web"
}
```

Ingest sensor reading (will auto-trigger alert + push if over threshold):

```json
{
  "sensorType": "waterLevel",
  "value": 90,
  "zone": "Zone A - Pump Station"
}
```

Test push:

```powershell
Invoke-RestMethod -Method Post "<ApiBaseUrl>/api/push/test-alert"
```

Get trends:

```powershell
Invoke-RestMethod -Method Get "<ApiBaseUrl>/api/trends?metric=water_level&range=24h"
```
