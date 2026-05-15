# Screenshot and Evidence Checklist

Use this checklist to collect evidence for the final report. Do not claim a feature as tested or completed unless a screenshot, log, API response, or physical photo supports it.

## Hardware and Firmware Evidence

| Evidence item | Required? | Status |
|---|---|---|
| ESP32 prototype photo showing wiring and sensors | Yes | `[To be completed]` |
| Close-up photo of water level sensor connection | Yes | `[To be completed]` |
| Close-up photo of DHT11 connection | Yes | `[To be completed]` |
| Buzzer hardware photo | Yes | `[To be completed]` |
| Physical vibration sensor photo | Only if implemented | `[Not implemented in inspected firmware]` |
| Arduino IDE / serial monitor showing temperature, humidity, ADC, water level, alarm, and cloud silence fields | Yes | `[To be completed]` |
| Serial monitor showing MQTT connected message | Yes | `[To be completed]` |
| Serial monitor showing successful cloud telemetry publish | Yes | `[To be completed]` |

## AWS IoT Core Evidence

| Evidence item | Required? | Status |
|---|---|---|
| AWS IoT Thing page | Yes | `[To be completed]` |
| AWS IoT certificate attached to Thing | Yes | `[To be completed]` |
| AWS IoT policy attached to certificate | Yes | `[To be completed]` |
| MQTT test client receiving/publishing `alertrix/sensors/ingest` payload | Yes | `[To be completed]` |
| IoT Rule for Lambda invoke | Yes | `[To be completed]` |

## Backend and Lambda Evidence

| Evidence item | Required? | Status |
|---|---|---|
| SAM stack deployed successfully | Yes | `[To be completed]` |
| API Gateway stage/base URL | Yes | `[To be completed]` |
| Lambda function list | Yes | `[To be completed]` |
| CloudWatch log for `/api/sensors/ingest` normal reading | Yes | `[To be completed]` |
| CloudWatch log for warning/critical alert | Yes | `[To be completed]` |
| API response from `/api/sensors/ingest` for normal reading | Yes | `[To be completed]` |
| API response from `/api/sensors/ingest` for critical reading | Yes | `[To be completed]` |
| API response from `/api/readings/latest` | Yes | `[To be completed]` |
| API response from `/api/alerts` | Yes | `[To be completed]` |
| API response from `/api/trends` | Yes | `[To be completed]` |
| API response from `/api/alerts/{alertId}/status` | Yes | `[To be completed]` |
| API response from `/api/alerts/{alertId}/work-orders` | If reporting work orders | `[To be completed]` |

## DynamoDB Evidence

| Evidence item | Required? | Status |
|---|---|---|
| `alertrix-sensor-readings-my` item for water level | Yes | `[To be completed]` |
| `alertrix-sensor-readings-my` item for temperature | Yes | `[To be completed]` |
| `alertrix-sensor-readings-my` item for vibration fallback or actual vibration reading | Yes, but label accurately | `[To be completed]` |
| `alertrix-alerts-my` warning alert item | Yes | `[To be completed]` |
| `alertrix-alerts-my` critical alert item | Yes | `[To be completed]` |
| `alertrix-push-tokens-my` registered token item | Yes | `[To be completed]` |
| `alertrix-work-orders-my` work order item | If reporting work orders | `[To be completed]` |
| `alertrix-user-profiles-my` notification settings item | If reporting user settings | `[To be completed]` |
| `alertrix-settings-my` device location item | If reporting device location | `[To be completed]` |
| `alertrix-settings-my` buzzer silence item | If reporting buzzer silence | `[To be completed]` |

## Firebase and Notification Evidence

| Evidence item | Required? | Status |
|---|---|---|
| Browser notification permission prompt or granted status | Yes | `[To be completed]` |
| Frontend status showing FCM token registered | Yes | `[To be completed]` |
| FCM push notification displayed in browser | Yes | `[To be completed]` |
| Background notification displayed while app is not focused | Optional | `[To be completed]` |
| `/api/push/test-alert` response | Yes | `[To be completed]` |
| SES verification email screenshot | If reporting registration email flow | `[To be completed]` |
| SES alert email screenshot | If reporting alert email flow | `[To be completed]` |

## Flutter Web UI Screenshots

| Page / UI state | Required? | Status |
|---|---|---|
| Login page | Yes | `[To be completed]` |
| Registration page with verification code flow | If reporting registration | `[To be completed]` |
| Password reset dialog/page | If reporting reset password | `[To be completed]` |
| Response Overview dashboard with normal readings | Yes | `[To be completed]` |
| Response Overview dashboard with active warning/critical alert | Yes | `[To be completed]` |
| Situation Trends page with selected metric/range | Yes | `[To be completed]` |
| Alert Center / Incident Queue | Yes | `[To be completed]` |
| Alert Detail page | Yes | `[To be completed]` |
| Alert confirmation result | Yes | `[To be completed]` |
| Work Orders page | If reporting work orders | `[To be completed]` |
| Admin Management page | If reporting admin management | `[To be completed]` |
| Response Settings notification settings | Yes | `[To be completed]` |
| Device location setting | If reporting device location | `[To be completed]` |
| Buzzer silence UI/action result | If reporting buzzer silence | `[To be completed]` |

## Testing Evidence

| Evidence item | Required? | Status |
|---|---|---|
| Functional testing table filled with actual results | Yes | `[To be completed]` |
| Performance latency trial table | Yes | `[To be completed]` |
| Reliability test table with success rate | Yes | `[To be completed]` |
| False alarm test evidence using normal stream | Yes | `[To be completed]` |
| `flutter test` result after updating test or documenting current failure | Yes | Current run failed |
| `flutter analyze` result after fixing or documenting warnings | Recommended | Current run reports 21 issues |
| Backend API manual test responses | Yes | `[To be completed]` |

## Report Figure Checklist

| Figure | Source | Status |
|---|---|---|
| System architecture diagram | `docs/diagrams.md` Mermaid export | `[To be completed]` |
| Module diagram | `docs/diagrams.md` Mermaid export | `[To be completed]` |
| Alert processing sequence diagram | `docs/diagrams.md` Mermaid export | `[To be completed]` |
| Database design diagram | `docs/diagrams.md` Mermaid export | `[To be completed]` |
| User flow diagram | `docs/diagrams.md` Mermaid export | `[To be completed]` |
| Hardware prototype photo | Camera photo | `[To be completed]` |
| Circuit/wiring diagram | Drawn diagram or clear annotated photo | `[To be completed]` |
| Dashboard screenshot | Flutter Web | `[To be completed]` |
| Notification screenshot | Browser/OS notification | `[To be completed]` |
| DynamoDB screenshot | AWS Console | `[To be completed]` |
| Lambda CloudWatch log screenshot | AWS Console | `[To be completed]` |

## Important Accuracy Notes

| Topic | How to describe in report |
|---|---|
| Vibration | The backend/frontend support `vibration`, and firmware sends a fallback value. Do not claim a physical vibration sensor unless hardware and firmware support are added. |
| Humidity | Firmware reads humidity, but backend cloud storage/alerting for humidity is not implemented. |
| Authentication | Describe as custom email/password and header/body role gating, not full managed JWT or API Gateway authorizer. |
| Threshold settings | Fixed thresholds are implemented in backend code; editable/persistent dynamic thresholds are not confirmed. |
| Test results | Use actual measured values only. Use `[To be completed]` until trials are performed. |
