# Alertrix AWS Lambda + API

This backend supports:
- Sensor ingest and anomaly detection
- Alert/work-order APIs
- FCM token registration
- FCM test push and anomaly push

## Endpoints

- `GET /api/readings/latest`
- `GET /api/trends?metric=water_level&range=24h`
- `GET /api/alerts`
- `POST /api/alerts/{alertId}/status`
- `POST /api/alerts/{alertId}/work-orders`
- `POST /api/push/register-token`
- `POST /api/push/test-alert`
- `POST /api/sensors/ingest`

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
