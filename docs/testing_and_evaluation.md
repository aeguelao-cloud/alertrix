# Testing and Evaluation

This document records the testing assets and verification status found in the Alertrix repository. It does not invent measured latency, reliability, or field-trial values. Any missing measured result is marked as `[To be completed]`.

## Available Test Assets

| Asset | Purpose | Status |
|---|---|---|
| `test/widget_test.dart` | Flutter widget test for login page rendering. | Present, but currently failing. |
| `backend/package.json` test script | Backend test command. | Placeholder only. |
| `flutter analyze` | Static analysis for Flutter/Dart code. | Produces warnings/infos. |
| `scripts/seed_demo_data.ps1` | Seeds historical sensor readings and optional critical alert. | Runnable script; measured result not stored. |
| `scripts/stream_demo_data.ps1` | Streams simulated readings and optional critical spikes. | Runnable script; measured result not stored. |
| `scripts/start_normal_stream.ps1` | Streams normal readings below warning thresholds. | Runnable script; useful for false alarm testing. |
| `scripts/trigger_all_critical.ps1` | Posts critical readings for all three sensor types. | Runnable script; useful for alert-generation testing. |
| `scripts/trigger_warning_then_critical.ps1` | Posts warning then critical water-level readings. | Runnable script; useful for alert transition testing. |
| `scripts/stream_arduino_serial_to_api.ps1` | Reads Arduino serial output and posts readings to API. | Runnable script; useful for hardware-to-cloud integration testing. |
| `scripts/check_fcm_web_setup.ps1` | Checks Firebase Installations and FCM Registration API access. | Runnable script; does not test end-to-end dashboard receipt. |

## Commands Executed During Repository Inspection

| Command | Result | Notes |
|---|---|---|
| `flutter test` | Failed | The widget test expected text `Alertrix Login`, but no matching widget was found. |
| `npm test` in `backend/` | Completed | Script only echoes `"add tests if needed"`; no backend tests are implemented. |
| `flutter analyze` | Failed analysis gate due to 21 issues | Issues are warnings/infos including deprecated APIs and one unused declaration. |

## Testing Strategy for Final Report

The final report should evaluate the system across functional, integration, performance, reliability, and false alarm testing.

| Test category | What should be tested | Evidence required |
|---|---|---|
| Functional testing | Individual functions such as sensor reading, telemetry ingest, alert creation, dashboard display, FCM token registration, notification preferences, and work order creation. | Test table, screenshots, API responses, serial monitor output. |
| Integration testing | End-to-end ESP32 to AWS IoT Core to Lambda to DynamoDB to FCM to Flutter Web flow. | Prototype photo, MQTT/AWS IoT evidence, Lambda logs, DynamoDB item, notification screenshot, dashboard screenshot. |
| Performance testing | Alert processing and notification latency. | Timestamped trials with detection time, backend processing time, notification time, and total latency. |
| Reliability testing | Repeated telemetry submissions and repeated alert-trigger trials. | Number of trials, successes, failures, success rate. |
| False alarm testing | Normal sensor ranges should not create warning/critical alerts. | Normal stream script output plus alerts table evidence showing no new critical alert. |
| Security testing | Role-limited alert ignore/admin actions and verification code flow. | API response screenshots for allowed and denied cases. |

## Functional Test Cases

| Test ID | Test case | Expected result | Actual result | Status |
|---|---|---|---|---|
| FT1 | ESP32 reads DHT11 temperature/humidity. | Serial monitor prints valid temperature and humidity values. | `[To be completed]` | `[To be completed]` |
| FT2 | ESP32 reads water level sensor. | Serial monitor prints ADC and water-level percentage. | `[To be completed]` | `[To be completed]` |
| FT3 | ESP32 publishes telemetry to AWS IoT Core topic `alertrix/sensors/ingest`. | AWS IoT/Lambda receives JSON payload. | `[To be completed]` | `[To be completed]` |
| FT4 | HTTP fallback posts telemetry to `/api/sensors/ingest`. | API returns `stored: true`. | `[To be completed]` | `[To be completed]` |
| FT5 | Lambda stores normal reading. | Reading appears in `alertrix-sensor-readings-my`. | `[To be completed]` | `[To be completed]` |
| FT6 | Warning threshold is exceeded. | Alert is generated with `severity: WARNING`. | `[To be completed]` | `[To be completed]` |
| FT7 | Critical threshold is exceeded. | Alert is generated with `severity: CRITICAL`. | `[To be completed]` | `[To be completed]` |
| FT8 | FCM token registration. | Token is stored in `alertrix-push-tokens-my`. | `[To be completed]` | `[To be completed]` |
| FT9 | Alert push notification. | Browser receives FCM notification. | `[To be completed]` | `[To be completed]` |
| FT10 | Dashboard latest reading display. | Flutter Web shows current water level, vibration, and temperature readings. | `[To be completed]` | `[To be completed]` |
| FT11 | Alert confirmation. | Alert status is updated through `/api/alerts/{alertId}/status`. | `[To be completed]` | `[To be completed]` |
| FT12 | Work order creation by admin. | Work order is created and alert is linked to the work order. | `[To be completed]` | `[To be completed]` |
| FT13 | Notification settings update. | User profile stores updated `pushRule`, email, and alert sound setting. | `[To be completed]` | `[To be completed]` |
| FT14 | Device location update. | Settings table stores new device location. | `[To be completed]` | `[To be completed]` |
| FT15 | Buzzer silence. | Firmware reads cloud silence state and suppresses local buzzer. | `[To be completed]` | `[To be completed]` |

## Integration Test Plan

| Test ID | Integration path | Procedure | Expected result | Actual result |
|---|---|---|---|---|
| IT1 | Firmware to AWS IoT Core | Run ESP32 firmware in MQTT mode and publish a normal reading. | Lambda receives payload and stores reading. | `[To be completed]` |
| IT2 | AWS IoT Core to DynamoDB | Publish a reading on `alertrix/sensors/ingest`. | DynamoDB SensorTable contains new item. | `[To be completed]` |
| IT3 | Threshold alert flow | Publish `waterLevel` value >= 85. | AlertTable contains `CRITICAL` alert. | `[To be completed]` |
| IT4 | Notification flow | Register FCM token, trigger critical alert. | Browser displays push notification. | `[To be completed]` |
| IT5 | Dashboard refresh flow | Trigger alert and open dashboard. | Dashboard shows latest readings and active alert. | `[To be completed]` |
| IT6 | Response workflow | Confirm alert or create work order. | Alert status changes and work order is visible. | `[To be completed]` |

## Performance Test Template

The repository does not include stored measured latency results. The following table should be completed using timestamps from serial monitor, Lambda logs, DynamoDB items, and browser notification receipt time.

| Trial | Sensor | Trigger value | Device publish time | Lambda processing time | Notification received time | Total latency | Status |
|---|---|---:|---|---|---|---|---|
| 1 | waterLevel | 90 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 2 | vibration | 4.6 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 3 | temperature | 46 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 4 | waterLevel | 74 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 5 | waterLevel | 90 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |

## Reliability Test Template

| Test | Number of attempts | Successful attempts | Failed attempts | Success rate | Evidence |
|---|---:|---:|---:|---:|---|
| Normal telemetry ingest | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| Warning alert generation | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| Critical alert generation | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| FCM notification delivery | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| Dashboard refresh after alert | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |

## False Alarm Test Template

Use `scripts/start_normal_stream.ps1` to send values below warning thresholds:

| Sensor type | Normal test value range | Warning threshold | Critical threshold | Expected result |
|---|---:|---:|---:|---|
| waterLevel | Around 49.5-54.5 | 70 | 85 | No warning/critical alert. |
| vibration | Around 1.05-1.75 | 2.8 | 4.0 | No warning/critical alert. |
| temperature | Around 29.0-31.4 | 35 | 40 | No warning/critical alert. |

| Trial period | Readings sent | Alerts generated | False alarms | Status |
|---|---:|---:|---:|---|
| `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |

## Static Analysis Result

`flutter analyze` reported 21 issues during inspection:

| Category | Count / examples | Status |
|---|---|---|
| Deprecated Flutter/Dart APIs | `value` on form fields, `withOpacity`, `dart:html` | Present |
| Web-only library warning | `dart:html` usage in web utility files | Present |
| Unused declaration | `_warning` in `alert_detail_page.dart` | Present |

No source code was modified as part of this documentation task.

## Automated Test Result

| Test command | Current result | Interpretation |
|---|---|---|
| `flutter test` | Failed | Test expectation is out of sync with current login page UI text. |
| `npm test` | Placeholder echo | Backend automated tests are not implemented. |

## Evaluation Summary

The repository contains substantial implementation for the intended Alertrix prototype, including firmware, serverless backend, DynamoDB persistence, FCM notification, and Flutter Web dashboard. However, the repository does not contain completed empirical evaluation data. The final report should therefore include:

1. Actual screenshots and logs from the deployed system.
2. Measured alert latency trials.
3. Repeated reliability trials.
4. False alarm test data under normal sensor ranges.
5. Updated automated tests or a clear explanation that automated coverage remains limited.
