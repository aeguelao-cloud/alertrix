# Alertrix Implementation Summary

This document summarizes the implementation observed in the repository for **Alertrix: Cloud-Assisted IoT Framework for Disaster Response Management**. The summary is based on the source code under `lib/`, `backend/`, `arduino/`, `web/`, `scripts/`, and `test/`.

## Confirmed Technology Stack

| Layer | Implemented technology | Evidence in repository |
|---|---|---|
| Sensor node firmware | Arduino/ESP32 C++ sketch | `arduino/DHT11WaterLevelPractice/DHT11WaterLevelPractice.ino` |
| Cloud ingress | AWS IoT Core MQTT rule and HTTP API fallback | `backend/template.yaml`, Arduino sketch |
| Backend compute | AWS Lambda functions using Node.js | `backend/src/handlers/*.js` |
| API layer | Amazon API Gateway via AWS SAM | `backend/template.yaml` |
| Database | Amazon DynamoDB | `backend/template.yaml`, `backend/src/common/dynamo.js` |
| Push notification | Firebase Cloud Messaging | `lib/services/push_notification_service.dart`, `backend/src/common/fcm.js`, `web/firebase-messaging-sw.js` |
| Email notification | AWS SESv2 for verification and alert email | `backend/src/common/verificationEmail.js`, `backend/src/common/emailNotifier.js` |
| Optional email topics | AWS SNS topics/subscriptions for notification preferences | `backend/template.yaml`, `backend/src/common/notificationSettings.js` |
| Frontend | Flutter Web dashboard | `lib/`, `web/` |
| Testing/scripts | Flutter widget test, PowerShell demo and deployment scripts | `test/widget_test.dart`, `scripts/*.ps1` |

## Frontend Implementation

The frontend is a Flutter Web application. The application starts from `lib/main.dart` and loads `AlertrixApp` from `lib/app.dart`. The app selects either the login page or the authenticated home shell based on an in-memory `SessionController`.

Implemented frontend modules include:

| Module | Implemented behavior |
|---|---|
| Login and registration | Login, account registration, email verification code request, password reset, and a local/demo admin shortcut path are present in `lib/pages/login_page.dart`. |
| Dashboard / Response Overview | Displays current readings, alert counts, recent alerts, field device overview, and trend previews from a `MonitoringSnapshot`. |
| Situation Trends | Displays local and remote trend series for water level, vibration, and temperature over `1H`, `6H`, `24H`, `7D`, `14D`, and `30D`. |
| Alert Center | Lists alert events from the current snapshot and supports alert confirmation, ignore, and work-order creation through controller methods. |
| Alert Detail | Provides a detailed alert view and response actions. |
| Response Settings | Provides notification settings, alert sound setting, and device location settings. Threshold editor UI exists, but backend persistence for threshold changes was not confirmed. |
| Admin Management | Lists, creates, updates, deletes, and changes status of admin records via `/api/admins` endpoints. |
| Work Orders | Loads work orders and related alert data from `/api/work-orders` and `/api/alerts`. |
| FCM registration | Initializes Firebase Messaging on web, obtains a web push token, and registers the token with the backend. |
| Local audio alert | Web-specific alert audio utility and alert sound loop are implemented. |

The frontend can operate in two modes:

| Mode | Description |
|---|---|
| Remote API mode | Used when `API_BASE_URL` is provided through `--dart-define`. Calls the AWS backend. |
| Mock mode | Used when no API base URL is provided. `FakeMonitoringApi` generates local sample readings and alerts. |

## Backend Implementation

The backend is an AWS SAM application using Node.js Lambda handlers. `backend/template.yaml` defines the API Gateway routes, Lambda handlers, DynamoDB tables, AWS IoT rule, SNS topics, and relevant IAM policies.

Implemented backend functions include:

| Function area | Implemented behavior |
|---|---|
| Sensor ingest | Accepts JSON sensor payloads from HTTP API or AWS IoT Rule event, stores telemetry in DynamoDB, evaluates fixed threshold rules, creates alerts, sends FCM push, and attempts alert email delivery. |
| Latest readings | Queries the latest reading for `waterLevel`, `vibration`, and `temperature`, limited to a live time window. |
| Trends | Queries recent sensor records and returns sampled time-series data by metric/range. If insufficient records exist, the function pads series values. |
| Alerts | Lists alerts, filters by status/severity, and updates alert status. |
| Work orders | Creates a work order from an alert and lists work orders. |
| Push notification | Stores FCM tokens and sends test or alert notifications to all registered tokens. |
| Authentication | Supports email-code registration, login using SHA-256 password hash comparison, and password reset using verification codes. |
| Admin management | Lists admins, creates admins, updates admin records, deletes admins, and changes active/inactive status. |
| Notification settings | Stores per-user push/email preferences and subscribes/unsubscribes email addresses through SNS. |
| Device location | Stores and retrieves a configured device/site zone. |
| Buzzer silence state | Stores temporary cloud-side buzzer silence state by zone. |
| App bootstrap | Aggregates navigation, overview, incident queue, settings, admin blocks, and work order summary for the page layout. |

## Firmware Implementation

The firmware is implemented in `arduino/DHT11WaterLevelPractice/DHT11WaterLevelPractice.ino`.

Confirmed firmware behavior:

| Area | Implemented behavior |
|---|---|
| Microcontroller target | ESP32-specific code paths are present using `WiFi.h`, `WiFiClientSecure.h`, `HTTPClient.h`, and `PubSubClient.h`. |
| Sensors | DHT11 temperature/humidity and analog water level sensor are implemented. |
| Buzzer | GPIO buzzer output is activated for local temperature/water-level alarm conditions unless cloud silence state is active. |
| Telemetry | Publishes JSON sensor readings for `waterLevel` and `temperature`. It also sends a `vibration` fallback value when enabled. |
| MQTT uplink | Supports MQTT over TLS to AWS IoT Core topic `alertrix/sensors/ingest`. |
| HTTP fallback | HTTP POST to `/api/sensors/ingest` exists but is disabled in the current strict MQTT configuration unless flags are changed. |
| Cloud buzzer silence | Periodically queries `/api/device/buzzer/state?zone=...` by HTTP and suppresses the local buzzer if silenced. |
| Sensor validation | DHT range validation and water ADC fault detection are implemented. |

Not confirmed or not implemented in firmware:

| Item | Status |
|---|---|
| Physical vibration sensor reading | `[Not implemented]` in the inspected firmware. The sketch sends `vibration` as a fallback value `0.0` when `SEND_VIBRATION_FALLBACK` is true. |
| Humidity upload to cloud | `[Not implemented]` as a backend sensor type. Firmware reads humidity for validation/serial output, but the backend threshold profiles only handle `waterLevel`, `vibration`, and `temperature`. |
| Secure HTTP certificate validation | `[Not implemented]` for HTTP fallback; the sketch uses `client.setInsecure()` for demo HTTP mode. |
| Dynamic threshold download | `[Not implemented]`; thresholds are fixed in code. |

## Cloud and Lambda Logic

AWS cloud behavior confirmed in `backend/template.yaml`:

| Cloud service | Implemented role |
|---|---|
| API Gateway | Exposes REST endpoints under `/api/...`. |
| Lambda | Runs all backend handlers. |
| AWS IoT Core Rule | Invokes `IngestSensorDataFunction` for messages on `alertrix/sensors/ingest`. |
| DynamoDB | Stores sensor readings, alerts, work orders, push tokens, settings, profiles, auth users, admins, and verification codes. |
| Firebase Cloud Messaging | Used by Lambda to send push alerts to registered device tokens. |
| SESv2 | Sends verification code email and alert email. |
| SNS | Defines critical/warning topics and supports email subscription preferences. |

Threshold-based alerting is implemented using fixed thresholds in `ingestSensorData.js`:

| Sensor type | Warning threshold | Critical threshold | Unit |
|---|---:|---:|---|
| waterLevel | 70 | 85 | `%` |
| vibration | 2.8 | 4.0 | `mm/s RMS` |
| temperature | 35 | 40 | `degC` |

When a reading reaches warning or critical threshold, the backend creates an alert with `status: ACTIVE`, stores it in DynamoDB, sends FCM notification to registered tokens, and attempts an email alert subject to cooldown settings.

## Database Implementation

The project uses DynamoDB tables defined in SAM. See `docs/database_design.md` for detailed schema documentation.

Confirmed tables:

| Table | Purpose |
|---|---|
| `alertrix-sensor-readings-my` | Telemetry readings keyed by sensor type and capture time. |
| `alertrix-alerts-my` | Alert records keyed by alert ID. |
| `alertrix-work-orders-my` | Work orders created from alerts. |
| `alertrix-push-tokens-my` | Registered FCM tokens. |
| `alertrix-settings-my` | Device location, buzzer silence state, and email cooldown settings. |
| `alertrix-user-profiles-my` | User notification preferences and profile data. |
| `alertrix-admins-my` | Admin contact records. |
| `alertrix-auth-users-my` | Registered login accounts. |
| `alertrix-verification-codes-my` | Email verification/reset codes with TTL. |

## Authentication and Authorization

Authentication is implemented at the application level rather than through a managed API Gateway authorizer.

Confirmed behavior:

| Area | Implemented behavior |
|---|---|
| Registration | `/api/auth/send-code` stores verification codes and sends email; `/api/auth/register` validates the code and creates auth/profile records. |
| Login | `/api/auth/login` checks the email and SHA-256 password hash and returns a role. |
| Password reset | `/api/auth/reset-password` validates email verification code and updates the password hash. |
| Role handling | Frontend stores role in memory. Backend role checks use request body fields or headers such as `X-User-Role` and `X-User-Id`. |
| Admin protection | Admin endpoints require `X-User-Role: Admin`; create/update/delete require internal super admin identity through `X-User-Id`. |

Not confirmed:

| Item | Status |
|---|---|
| JWT/session token issuing | `[Not implemented]` in inspected backend code. |
| API Gateway authorizer | `[Not implemented]` in `template.yaml`. |
| Password salting/adaptive hashing | `[Not implemented]`; backend uses plain SHA-256 hash. |

## Notification Implementation

Confirmed notification channels:

| Channel | Implemented behavior |
|---|---|
| FCM push | Frontend obtains web FCM token and backend stores token. Lambda sends multicast push notifications to all stored tokens. |
| Web background notification | `web/firebase-messaging-sw.js` displays background notifications. |
| Alert email | Lambda sends alert email through SESv2 to active admins and eligible user notification emails. |
| Verification email | Registration/reset code emails are sent through SESv2. |
| Local dashboard sound | Flutter web alert sound loop is implemented and configurable. |
| Cloud buzzer silence | Frontend can call backend to silence buzzer state; firmware reads this state. |

## API Endpoints

The complete endpoint table is provided in `docs/api_endpoint_table.md`.

## Implemented Tests and Scripts

Confirmed testing and support assets:

| Asset | Status |
|---|---|
| `test/widget_test.dart` | Contains one Flutter widget test, but current run fails because expected login text is not found. |
| `backend/package.json` test script | Placeholder only: prints `"add tests if needed"`. |
| `scripts/seed_demo_data.ps1` | Posts historical/demo readings to the deployed API. |
| `scripts/stream_demo_data.ps1` | Continuously posts simulated readings with optional critical spikes. |
| `scripts/start_normal_stream.ps1` | Continuously posts normal readings below warning thresholds. |
| `scripts/trigger_all_critical.ps1` | Posts critical readings for all three sensor types. |
| `scripts/trigger_warning_then_critical.ps1` | Posts a warning reading followed by a critical reading. |
| `scripts/stream_arduino_serial_to_api.ps1` | Reads Arduino serial output and forwards readings to the HTTP API. |
| `scripts/check_fcm_web_setup.ps1` | Checks Firebase installation and FCM registration APIs. |

Measured latency, reliability percentage, field trial data, and false alarm statistics were not found in the repository and must be completed manually.

## Important Gaps and Limitations

| Gap | Status |
|---|---|
| Measured performance results | `[To be completed]` |
| Real field deployment evidence | `[To be completed]` |
| Screenshots for final report | `[To be completed]` |
| Literature references and citations | `[To be completed]` |
| Physical vibration sensor support | `[Not implemented]` in inspected firmware |
| Humidity cloud storage/threshold alerting | `[Not implemented]` |
| Dynamic threshold persistence from UI to backend | `[Not implemented]` / not confirmed |
| Managed token-based API authentication | `[Not implemented]` |
| Automated backend unit/integration tests | `[Not implemented]` |
