# Cloud-Assisted IoT Framework for Disaster Response Management (Alertrix)

**Final Year Project Final Report Draft**

Author: `[To be completed]`  
Student ID: `[To be completed]`  
Programme: `[To be completed]`  
Supervisor: `[To be completed]`  
Academic Session: `[To be completed]`

## Abstract

Disaster response requires timely situational awareness, especially when water level and environmental readings may change before response users can inspect a site manually. This project implements Alertrix, a cloud-assisted Internet of Things (IoT) prototype for disaster response monitoring and alert management. The implemented system consists of an ESP32-based firmware layer, an AWS serverless backend, DynamoDB storage, Firebase Cloud Messaging notification support, and a Flutter Web dashboard. The inspected firmware reads DHT11 temperature/humidity values and an analog water level sensor, controls a local buzzer, publishes sensor telemetry to AWS IoT Core through MQTT, and can query a cloud-side buzzer silence state. The backend stores telemetry, evaluates fixed threshold rules for water level, vibration, and temperature, creates warning or critical alert records, sends Firebase push notifications to registered tokens, and provides API endpoints for readings, trends, alerts, work orders, notification settings, device location, authentication, and admin management. The vibration metric is implemented in the backend and dashboard, but the inspected firmware sends a fallback vibration value rather than reading a physical vibration sensor. The Flutter Web dashboard presents response overview, trend visualization, incident queue, alert detail, response settings, work orders, and admin management pages. The final empirical evaluation, including latency, reliability, field testing, and screenshot evidence, is still `[To be completed]`; therefore, this report draft separates implemented source-code evidence from unmeasured or unimplemented functions. The prototype demonstrates the feasibility of a serverless IoT disaster response workflow but remains limited by prototype-scale testing, fixed threshold rules, incomplete automated tests, and incomplete physical vibration sensing.

**Keywords:** Internet of Things, disaster response, AWS IoT Core, AWS Lambda, DynamoDB, Firebase Cloud Messaging, Flutter Web, threshold-based alerting.

## Abstrak

`[To be completed: Malay abstract corresponding to the English Abstract.]`

## Acknowledgements

`[To be completed: Acknowledge supervisor, examiner, university, family, friends, and any technical support received.]`

## Table of Contents

`[To be completed in Word or final document editor.]`

## List of Figures

`[To be completed after exporting diagrams and adding screenshots.]`

## List of Tables

`[To be completed after final table numbering.]`

# Chapter 1: Introduction

## 1.1 Background

Flood-related hazards and unsafe site conditions require early detection and rapid communication to response personnel. In disaster-prone areas, changes in water level or environmental readings may indicate that a site is moving toward an unsafe state. If these readings are collected only through manual inspection or isolated devices, response users may not receive timely and traceable information. IoT-based monitoring can improve this situation by allowing sensor nodes to collect readings continuously and transmit telemetry to a cloud backend for processing, storage, visualization, and alert notification.

Cloud-assisted IoT systems are commonly designed around four main functions: sensing, data transmission, cloud-side processing, and user notification. A sensor node collects local measurements and sends them through a network such as Wi-Fi or MQTT. A cloud backend receives the readings, stores them, and applies analysis rules. A notification service then delivers alerts to users, while a dashboard allows the current and historical state of the monitored site to be reviewed. This architecture is suitable for a prototype disaster response system because it avoids the need to operate a dedicated physical server while still supporting near real-time telemetry processing.

Alertrix was developed as a prototype cloud-assisted IoT framework for disaster response management. The implemented project combines an ESP32 sensor node, AWS IoT Core, AWS Lambda, DynamoDB, Firebase Cloud Messaging, and a Flutter Web dashboard. The source code confirms a rule-based threshold alerting approach rather than a machine learning prediction system. The prototype focuses on collecting sensor readings, storing them in the cloud, generating alerts when thresholds are exceeded, and presenting alert history and monitoring data through a web dashboard.

## 1.2 Problem Statement

The project addresses the following problems, which should be supported by the completed literature review:

1. Several IoT disaster monitoring prototypes focus on sensor collection but provide limited integrated response workflow, such as alert status tracking, work order creation, or notification preference management.
2. Some cloud monitoring approaches store telemetry but provide limited dashboard evidence for response users to review current readings, trend history, and recent incidents in one interface.
3. Alert delivery mechanisms in existing prototypes are often separated from dashboard-based incident management, making the alert less traceable after it is delivered.
4. Many prototype systems report architectural design but provide limited measured evaluation of alert latency, repeated telemetry reliability, and false alarm behaviour.

`[To be completed: connect each problem statement to specific literature sources and metrics after the 15-20 paper review is completed.]`

## 1.3 Motivation

The motivation of Alertrix is to demonstrate a low-cost, cloud-assisted monitoring workflow that can support early warning and disaster response. The ESP32 platform provides Wi-Fi connectivity and sensor interfacing at prototype cost. AWS serverless services allow telemetry to be processed without managing a traditional server. Firebase Cloud Messaging supports push notification delivery to dashboard users. A Flutter Web dashboard provides an accessible interface for viewing current readings, alert history, and response information.

The implemented project is not a nationwide emergency management system. It is a prototype intended to demonstrate feasibility and to provide a basis for future improvement through field testing, additional sensors, improved security, and larger-scale deployment.

## 1.4 Project Objectives

The implemented code supports the following project objectives:

| Objective ID | Objective | Implementation status |
|---|---|---|
| O1 | To develop an ESP32-based IoT sensor node for disaster-related telemetry. | Partially achieved. DHT11 temperature/humidity and analog water level sensor are implemented. Physical vibration sensor reading is `[Not implemented]`; vibration is sent as a fallback value in firmware. |
| O2 | To implement a cloud-assisted backend using AWS IoT Core, AWS Lambda, and DynamoDB. | Achieved in source code through SAM template, IoT Rule, Lambda handlers, and DynamoDB tables. Deployment evidence is `[To be completed]`. |
| O3 | To implement threshold-based alert processing for sensor readings. | Achieved for water level, vibration, and temperature using fixed backend thresholds. |
| O4 | To integrate Firebase Cloud Messaging for alert notification. | Achieved in source code for token registration and multicast push. End-to-end notification screenshot evidence is `[To be completed]`. |
| O5 | To develop a Flutter Web dashboard for monitoring and alert management. | Achieved in source code through dashboard, trends, alerts, settings, work orders, and admin pages. Screenshots are `[To be completed]`. |
| O6 | To evaluate functional correctness, latency, and reliability. | `[To be completed]`. Current repository includes scripts and one failing widget test, but measured results are not available. |

## 1.5 Project Scope

The project scope includes:

| Included scope | Description |
|---|---|
| ESP32 firmware | Reads DHT11 temperature/humidity and analog water level, controls buzzer, publishes telemetry, and checks cloud buzzer silence state. |
| AWS IoT Core ingestion | MQTT topic `alertrix/sensors/ingest` is configured in SAM through an IoT Rule. |
| Serverless backend | AWS Lambda functions process telemetry, alerts, work orders, settings, authentication, admin records, and notifications. |
| DynamoDB persistence | Tables store sensor readings, alerts, work orders, push tokens, settings, user profiles, admins, auth users, and verification codes. |
| Firebase Cloud Messaging | Web push token acquisition and backend multicast notification are implemented. |
| Flutter Web dashboard | Provides monitoring, trend, alert, settings, work order, and admin user interfaces. |
| Threshold-based alerting | Fixed warning/critical thresholds are implemented in backend code. |

The project scope excludes:

| Excluded or unconfirmed scope | Status |
|---|---|
| Nationwide or production emergency dispatch integration | `[Not implemented]` |
| Machine learning prediction | `[Not implemented]`; rule-based threshold analysis is used. |
| Confirmed physical vibration sensor firmware | `[Not implemented]` in inspected firmware. |
| Humidity cloud alerting | `[Not implemented]`; humidity is read locally but not stored as a backend sensor metric. |
| Managed JWT/Cognito/Firebase Auth authorizer | `[Not implemented]`; custom email/password and header/body role checks are used. |
| Dynamic threshold storage and update API | `[Not implemented]` / not confirmed. |
| Field deployment evaluation | `[To be completed]` |

## 1.6 Report Organization

Chapter 1 introduces the project background, problem statement, motivation, objectives, and scope. Chapter 2 reviews related work and identifies the research gap; references remain `[To be completed]`. Chapter 3 describes the system analysis and design based on the implemented repository. Chapter 4 presents the implementation of firmware, cloud backend, database, notification, and frontend modules. Chapter 5 discusses testing and evaluation based on available tests and required future measurements. Chapter 6 summarizes results, limitations, and objective achievement. Chapter 7 explains alignment with Sustainable Development Goals. Chapter 8 concludes the report and proposes future work.

# Chapter 2: Literature Review and Related Work

## 2.1 IoT-Based Disaster Monitoring

IoT-based disaster monitoring systems typically use distributed sensors to measure hazard indicators, transmit readings through a communication network, and process the readings at an edge or cloud layer. Such systems are relevant for flood monitoring, water-level monitoring, environmental safety monitoring, and structural or vibration-related monitoring when the required hardware is implemented. The main benefit of IoT in this context is continuous sensing, which reduces dependence on manual observation and allows alert logic to operate when hazardous conditions are detected.

`[To be completed: Add peer-reviewed citations for IoT disaster monitoring systems.]`

## 2.2 Flood Early Warning Systems

Flood early warning systems commonly use water level sensors, ultrasonic sensors, rain gauges, or river monitoring stations. In Alertrix, the implemented firmware uses an analog water level sensor connected to an ESP32. The firmware maps ADC values to a water level percentage using dry and wet calibration values. The backend then applies fixed warning and critical thresholds to the cloud-stored `waterLevel` metric.

`[To be completed: Add citations and compare sensor types such as ultrasonic, pressure, float, and conductive water level sensors.]`

## 2.3 Vibration and Structural Monitoring

Vibration monitoring is commonly used for structural health monitoring, machinery monitoring, landslide detection, and seismic-related studies. The Alertrix backend and frontend include a `vibration` metric with warning and critical thresholds. However, the inspected firmware does not read an actual vibration sensor. It sends a fallback vibration value when `SEND_VIBRATION_FALLBACK` is enabled. Therefore, vibration monitoring should be described as a supported cloud/dashboard metric but not as a completed physical sensor feature unless firmware and hardware are later added.

`[To be completed: Add citations for vibration and structural health monitoring.]`

## 2.4 Cloud-Assisted IoT Architecture

Cloud-assisted IoT architectures support remote storage, serverless processing, and integration with notification services. Alertrix uses AWS IoT Core for MQTT ingestion, AWS Lambda for event processing, API Gateway for HTTP endpoints, and DynamoDB for persistence. This architecture reduces backend server maintenance for a prototype and supports event-driven processing when sensor readings arrive.

`[To be completed: Add citations on serverless IoT architectures and AWS IoT Core/Lambda-based designs.]`

## 2.5 Alert Notification and Dashboard Systems

A disaster monitoring system should not only collect readings but also communicate actionable alerts to users. Alertrix implements multiple notification-related components: Firebase Cloud Messaging for browser push notifications, SESv2 email notification for alert emails and verification codes, local dashboard sound alerts, and a cloud buzzer silence state that firmware can read. The Flutter Web dashboard provides pages for response overview, situation trends, incident queue, and response settings.

`[To be completed: Add citations comparing SMS, email, push notification, mobile app, and web dashboard alert systems.]`

## 2.6 Comparison of Existing Works

The SRD feedback requires a stronger related work chapter with at least 15-20 relevant studies and a comparison table. The table below is prepared as the required structure. The rows must be completed using verified sources before final submission. Alertrix is included only as an implemented prototype comparison row.

| No. | Study/System | Hazard type | Sensors | Platform/communication | Alert method | Dashboard | Measured metric reported | Limitation / gap |
|---:|---|---|---|---|---|---|---|---|
| 1 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 2 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 3 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 4 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 5 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 6 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 7 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 8 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 9 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 10 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 11 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 12 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 13 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 14 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 15 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 16 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 17 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 18 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 19 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 20 | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 21 | Alertrix | Flood-related water level and environmental monitoring; vibration metric supported in backend/frontend | DHT11 and analog water level implemented; physical vibration sensor `[Not implemented]` | ESP32 Wi-Fi, AWS IoT Core MQTT, API Gateway/Lambda, DynamoDB | FCM push, SES email, local sound/buzzer | Flutter Web | Latency/reliability `[To be completed]` | Prototype scale; fixed thresholds; physical vibration sensing incomplete |

## 2.7 Research Gap

Based on the intended project direction, the research gap can be stated as follows after completing the literature review:

1. Many existing systems focus on data collection but provide limited integrated alert management and response workflow.
2. Some systems provide hazard monitoring but do not combine telemetry, alert history, notification settings, and dashboard-based response views.
3. Several prototypes lack documented cloud-side storage, alert traceability, and user-facing evidence for alert response.
4. Performance and reliability results are often needed to demonstrate whether the system can support timely disaster response.

`[To be completed: Refine these gaps after inserting actual literature citations.]`

## 2.8 Contribution of Alertrix

The implemented contribution of Alertrix is a working prototype that integrates ESP32 telemetry, AWS serverless processing, DynamoDB persistence, Firebase push notification, and Flutter Web monitoring. The contribution is practical rather than predictive: the system uses threshold-based rules to create alerts and supports dashboard workflows for monitoring, confirming alerts, managing work orders, and configuring notifications.

# Chapter 3: System Analysis and Design

## 3.1 System Overview

Alertrix follows a layered IoT architecture. The sensor node collects readings and sends JSON telemetry to the cloud. Telemetry can enter the backend through AWS IoT Core MQTT or through an HTTP POST endpoint. The Lambda ingest function stores readings in DynamoDB, compares readings against fixed thresholds, creates alerts when needed, sends notifications, and returns an API response. The Flutter Web frontend retrieves the latest readings, alerts, trends, work orders, settings, and admin records through API Gateway endpoints.

The implemented data flow is:

1. ESP32 reads DHT11 temperature/humidity and water level ADC.
2. ESP32 publishes telemetry to AWS IoT Core MQTT topic `alertrix/sensors/ingest`; HTTP fallback exists but is disabled by current strict MQTT flags.
3. AWS IoT Rule invokes the ingest Lambda.
4. Lambda stores readings in DynamoDB.
5. Lambda evaluates fixed threshold profiles.
6. Lambda creates alert records for warning/critical readings.
7. Lambda sends FCM push notification and attempts alert email delivery.
8. Flutter Web dashboard loads readings, alerts, trends, and response data through REST APIs.

## 3.2 System Users

| User type | Description | Implemented permissions |
|---|---|---|
| User/Operator | General monitoring user who views dashboard, alerts, trends, and settings. | Can view monitoring pages, confirm alerts, update own notification settings, and silence buzzer using allowed role value. |
| Admin | Elevated user resolved through active admin record or internal admin configuration. | Can access admin navigation, create work orders, ignore alerts, and change admin status. |
| Super admin/internal admin | Admin request with `X-User-Id` matching configured internal admin IDs. | Required for creating, updating, and deleting admin records. |

## 3.3 Functional Requirements

| ID | Functional requirement | Implemented status |
|---|---|---|
| FR1 | The system shall collect sensor data from an ESP32 node. | Partially implemented: temperature/humidity and water level are read; physical vibration sensor is `[Not implemented]`. |
| FR2 | The system shall transmit telemetry to the cloud. | Implemented through MQTT to AWS IoT Core and optional HTTP fallback. |
| FR3 | The backend shall store sensor readings. | Implemented using DynamoDB SensorTable. |
| FR4 | The backend shall evaluate readings against thresholds. | Implemented using fixed thresholds for water level, vibration, and temperature. |
| FR5 | The backend shall generate alerts when thresholds are exceeded. | Implemented using AlertTable records. |
| FR6 | The system shall send push notifications. | Implemented using Firebase Cloud Messaging. End-to-end evidence `[To be completed]`. |
| FR7 | The web dashboard shall display readings and alerts. | Implemented in Flutter Web pages. Screenshots `[To be completed]`. |
| FR8 | The system shall provide alert history. | Implemented through `/api/alerts` and dashboard alert views. |
| FR9 | Users shall be able to confirm or ignore alerts. | Implemented; ignore is restricted to Admin role in backend. |
| FR10 | Admins shall be able to create work orders from alerts. | Implemented; backend requires `Admin` role. |
| FR11 | Users shall be able to configure notification settings. | Implemented for push rule, alert sound, and notification email. |
| FR12 | The system shall support login and registration. | Implemented with custom email/password and email verification code. |

## 3.4 Non-Functional Requirements

| ID | Requirement | Target | Implementation status |
|---|---|---|---|
| NFR1 | Responsiveness | Dashboard should refresh monitoring data frequently. | Implemented adaptive polling in frontend controller: 1s for critical, 2s for warning, 3s for stable state. |
| NFR2 | Reliability | Telemetry and alert flow should work across repeated trials. | `[To be completed]`; repeated trial results are not in repository. |
| NFR3 | Security | Cloud MQTT should use TLS and device certificates. | Implemented for MQTT path using certificates in firmware. HTTP fallback uses insecure TLS mode in demo firmware. |
| NFR4 | Scalability | Backend should be able to support additional sensor events. | Serverless Lambda/DynamoDB design supports prototype scaling, but scan-based queries and no GSIs limit large-scale performance. |
| NFR5 | Usability | Dashboard should be understandable for response users. | Implemented UI pages; usability evaluation `[To be completed]`. |
| NFR6 | Maintainability | Backend should be modular. | Implemented through separate handler and common modules. |
| NFR7 | Testability | System should include functional and integration tests. | Limited. One Flutter widget test fails; backend tests are placeholder only. |

## 3.5 System Architecture

Figure references for this chapter should be inserted after the Mermaid diagrams are exported. For example, the system architecture diagram in `docs/diagrams.md` should be cited in the text as "Figure 3.x illustrates the overall Alertrix system architecture." The architecture consists of five main layers:

| Layer | Components | Description |
|---|---|---|
| Sensor layer | ESP32, DHT11, analog water level sensor, buzzer | Collects local readings, performs basic validation, controls buzzer, and sends telemetry. |
| Connectivity layer | Wi-Fi, MQTT, HTTP fallback | Sends JSON payloads from sensor node to cloud. |
| Cloud processing layer | AWS IoT Core, API Gateway, Lambda | Receives telemetry, routes events, evaluates thresholds, and exposes APIs. |
| Data and notification layer | DynamoDB, FCM, SESv2, SNS | Stores data and delivers push/email notifications. |
| Application layer | Flutter Web dashboard | Displays readings, trends, alerts, settings, admin records, and work orders. |

See `docs/diagrams.md` for the Mermaid system architecture diagram.

## 3.6 Module Design

The implemented system modules are:

| Module | Sub-modules |
|---|---|
| Firmware module | Sensor reading, local alarm, MQTT publish, HTTP fallback, cloud buzzer silence check. |
| Backend module | Auth, ingest, threshold analysis, alert management, work orders, push notification, email notification, settings, admin management, app bootstrap. |
| Data module | Sensor readings, alerts, work orders, tokens, settings, user profiles, admin records, auth users, verification codes. |
| Frontend module | Login/register/reset, response overview, situation trends, incident queue, alert detail, response settings, admin management, work orders, FCM registration, local alert sound. |

The module diagram must include these sub-modules rather than showing only broad blocks. This addresses the SRD feedback that the previous module diagram did not show login, sign-up, or other important sub-modules.

## 3.7 Database Design

Alertrix uses DynamoDB tables defined in the AWS SAM template. The database design is documented in detail in `docs/database_design.md`.

Summary:

| Table | Key | Purpose |
|---|---|---|
| Sensor readings | `sensorType`, `capturedAt` | Stores telemetry. |
| Alerts | `alertId` | Stores generated alerts. |
| Work orders | `workOrderId` | Stores work orders linked to alerts. |
| Push tokens | `token` | Stores FCM tokens. |
| Settings | `settingId` | Stores device location, buzzer silence, and email cooldown records. |
| User profiles | `userId` | Stores notification settings. |
| Admins | `adminId` | Stores admin contacts and statuses. |
| Auth users | `username` | Stores custom login accounts. |
| Verification codes | `email` | Stores email verification/reset codes with TTL. |

## 3.8 API Design

The backend exposes routes for authentication, readings, trends, alerts, work orders, push notification, device settings, notification settings, admin records, and sensor ingest. The full endpoint table is provided in `docs/api_endpoint_table.md`.

The route design is REST-like but not fully protected by token-based authentication. Role and identity are passed through request bodies or headers in the inspected implementation.

## 3.9 Security Design

Confirmed security-related implementation:

| Area | Implemented status |
|---|---|
| MQTT transport | AWS IoT MQTT over TLS is implemented using root CA, device certificate, and private key. |
| Verification code email | Registration/reset code flow is implemented using SESv2. |
| Password storage | Password is stored as SHA-256 hash. |
| Admin role checks | Admin endpoints use `X-User-Role` and `X-User-Id` checks. |
| CORS | API Gateway and response helper allow CORS for configured methods/headers. |

Limitations:

| Limitation | Status |
|---|---|
| API Gateway authorizer/JWT validation | `[Not implemented]` |
| Salted/adaptive password hashing | `[Not implemented]` |
| Secure HTTP certificate pinning in firmware fallback | `[Not implemented]`; demo code uses `setInsecure()`. |
| Secret management for firmware credentials | `[To be completed]`; sensitive values should not be committed in final production practice. |

# Chapter 4: System Implementation

This chapter explains how Alertrix was implemented based on the completed source code. The implementation follows a cloud-assisted IoT architecture that connects an ESP32 sensor node, AWS IoT Core, AWS Lambda, DynamoDB, Firebase Cloud Messaging, AWS SESv2 Email, and a Flutter Web dashboard. The description in this chapter is limited to functions that are present in the inspected repository. Any feature that is not confirmed from the code is marked as `[To be completed]` or `[Not implemented]`.

## 4.1 Implementation Environment

Alertrix was developed using a combination of embedded firmware, serverless cloud services, and a web-based dashboard. The implementation environment is summarized in Table 4.1.

| Layer | Technology / Tool | Purpose |
|---|---|---|
| Embedded device | ESP32 | Sensor reading, local buzzer control, Wi-Fi communication, and MQTT telemetry publishing. |
| Firmware platform | Arduino-style ESP32 firmware | Implementation of DHT11 reading, water-level reading, MQTT communication, and buzzer logic. |
| Cloud ingest | AWS IoT Core | Receives MQTT telemetry from ESP32 and triggers the ingest Lambda through an IoT Rule. |
| Backend runtime | Node.js AWS Lambda | Processes API requests, stores readings, evaluates thresholds, manages alerts, and sends notifications. |
| API layer | Amazon API Gateway | Provides REST endpoints used by the Flutter Web dashboard and HTTP ingest fallback. |
| Database | Amazon DynamoDB | Stores sensor readings, alerts, work orders, push tokens, settings, users, verification codes, and admin accounts. |
| Push notification | Firebase Cloud Messaging | Sends browser push notifications to registered web clients. |
| Email notification | AWS SESv2 Email | Sends verification emails and alert email notifications. |
| Frontend | Flutter Web | Provides dashboard, trends, alerts, settings, work orders, and admin management pages. |
| Deployment support | AWS SAM and PowerShell scripts | Defines and deploys cloud resources and runs demo/testing flows. |

The repository contains deployment and demonstration scripts such as `deploy_backend_with_fcm.ps1`, `run_alertrix_one_click.ps1`, `stream_demo_data.ps1`, `start_normal_stream.ps1`, `trigger_all_critical.ps1`, and `trigger_warning_then_critical.ps1`. These scripts support deployment, frontend launching, sample data seeding, and alert scenario testing. Final deployment screenshots are `[To be completed]`.

## 4.2 Hardware Implementation

The hardware implementation is centred on an ESP32 sensor node. The inspected firmware confirms the use of DHT11, an analog water-level sensor, and a buzzer. The ESP32 reads the connected sensors, applies local validation and threshold logic, controls the buzzer, and publishes telemetry to the cloud.

| Hardware component | Implemented role |
|---|---|
| ESP32 | Main embedded controller for sensor reading, Wi-Fi, MQTT, HTTP fallback, and buzzer control. |
| DHT11 sensor | Reads temperature and humidity values. |
| Analog water-level sensor | Reads ADC values and maps them to water-level percentage. |
| Buzzer | Provides local alarm output when temperature or water-level thresholds are exceeded, unless silenced by cloud state. |
| Vibration sensor | `[Not implemented]` in the inspected firmware. The firmware sends a fallback vibration value instead of reading a physical vibration sensor. |

The firmware performs repeated ADC sampling for the water-level sensor and maps the raw reading using configured dry and wet calibration values. It also checks whether the ADC reading appears faulty based on repeated out-of-range readings. For the DHT11 sensor, the firmware validates temperature and humidity values before using them in the telemetry payload.

The buzzer implementation combines local threshold behaviour with cloud control. When the temperature or water-level threshold is exceeded, the buzzer can be activated locally. The firmware also checks a backend buzzer state endpoint so that the buzzer can be silenced from the dashboard. Prototype wiring photos, hardware setup evidence, and serial monitor screenshots are `[To be completed]`.

## 4.3 Backend / Cloud Implementation

The backend is implemented using AWS serverless services. The primary telemetry path starts from the ESP32 publishing an MQTT JSON message to AWS IoT Core on the topic `alertrix/sensors/ingest`. The AWS SAM template defines an IoT Rule that invokes the sensor ingest Lambda when telemetry is received on this topic. The system also includes an HTTP ingest endpoint, `/api/sensors/ingest`, which functions as a fallback or demo path rather than the main device communication route.

The main sensor ingest Lambda performs the following operations:

1. Receives a telemetry payload from AWS IoT Core or the HTTP ingest endpoint.
2. Parses the request body or IoT event payload.
3. Validates the `sensorType` and numeric `value`.
4. Stores the sensor reading in DynamoDB.
5. Compares the sensor value against fixed warning and critical thresholds.
6. Returns a normal result when the value does not exceed an alert threshold.
7. Creates an alert record for warning or critical readings.
8. Reads registered FCM push tokens from DynamoDB.
9. Sends browser push notifications through Firebase Cloud Messaging.
10. Checks email cooldown/settings and sends alert email through AWS SESv2 when allowed.

Other Lambda handlers support latest reading retrieval, trend retrieval, alert listing, alert status update, work order creation/listing, notification settings, device location settings, buzzer silence state, push token registration, account registration, login, password reset, verification email sending, admin management, and application bootstrap. The implemented backend therefore covers both telemetry processing and dashboard-facing API operations.

The cloud implementation is designed as a serverless architecture. This reduces the need to manage a fixed backend server and allows individual functions to be invoked by API Gateway or AWS IoT Core events. However, several backend operations use DynamoDB scans, which may limit scalability if the number of records becomes large. API Gateway authorizer/JWT validation was not found in the inspected code and is therefore marked as `[Not implemented]`.

## 4.4 Frontend / Dashboard Implementation

The frontend is implemented as a Flutter Web dashboard. Its role is to provide users and administrators with a browser-based interface for monitoring sensor conditions, reviewing alerts, and performing response actions.

The implemented dashboard includes the following main pages and functions:

| Page / module | Implemented function |
|---|---|
| Login and registration page | Supports account registration, login, verification code request, and password reset flow. |
| Home shell | Provides navigation, session state management, push notification registration, alert sound handling, and role-based page access. |
| Dashboard page | Displays response overview, latest readings, risk indicators, field device overview, trend preview, and recent alerts. |
| Trends page | Displays metric-based and time-range-based trend visualizations. |
| Alerts page | Displays alert history/incident queue and supports alert actions. |
| Alert detail page | Displays selected alert information and response actions. |
| Settings page | Supports notification settings, alert sound settings, device/site location, and related configuration views. |
| Work orders page | Displays and manages work orders linked to alerts. |
| Admin management page | Supports administrator account management functions. |

The frontend communicates with the backend using an API client layer. In the logical class diagram, this layer is represented as `AlertrixApiClient`; in the actual source code, the corresponding implemented API client is named `AwsMonitoringApi`. The dashboard uses API calls to fetch snapshots, readings, trends, alerts, settings, and work-order data. It also sends alert status updates and notification settings updates to the backend.

Firebase Messaging is initialized on the web client so that the browser can register a push token. The token is sent to the backend through the push token registration API. A Firebase messaging service worker is also included to support background web notifications. Final screenshots for dashboard pages, alert details, settings, work orders, and admin management are `[To be completed]`.

## 4.5 Database Implementation

Alertrix uses DynamoDB as its main storage layer. The inspected backend template and handlers show multiple tables used for telemetry, alerts, accounts, settings, and notification data.

| Table / data store | Purpose |
|---|---|
| Sensor readings table | Stores sensor telemetry records such as sensor type, value, zone, severity, and captured time. |
| Alerts table | Stores generated warning and critical alert records with status and update information. |
| Work orders table | Stores response work orders linked to alerts. |
| Push tokens table | Stores Firebase Cloud Messaging web push tokens. |
| Settings table | Stores device location, buzzer silence state, notification settings, and cooldown-related values. |
| User profiles table | Stores profile and notification-related user information. |
| Admins table | Stores administrator account metadata and role-related information. |
| Auth users table | Stores custom authentication account data. |
| Verification codes table | Stores verification codes used for registration and password reset flows. |

The main operational data objects are `SensorReading` and `Alert`. A sensor reading stores monitored values from the device or demo ingest flow. An alert is created when the backend evaluates a warning or critical threshold condition. The implemented alert fields include identifiers, title, severity, status, zone, trigger value, detected time, and update-related fields. Detailed table keys, fields, and relationships are documented separately in `docs/database_design.md`.

The current database design is suitable for prototype-level monitoring and report demonstration. However, some read operations are scan-based. For larger deployment, secondary indexes and more explicit partition-key design would be required. DynamoDB screenshots and sample item evidence are `[To be completed]`.

## 4.6 Notification and Alert Implementation

The alert implementation is threshold-based. The backend evaluates supported sensor readings against fixed warning and critical thresholds. When a reading is normal, it is stored without creating an alert. When a reading reaches warning or critical level, the backend creates an alert record and dispatches notifications.

The implemented alert flow is:

1. ESP32 publishes telemetry to AWS IoT Core using MQTT.
2. AWS IoT Core invokes the sensor ingest Lambda through an IoT Rule.
3. The Lambda validates and stores the reading.
4. The Lambda compares the value with fixed thresholds.
5. If the reading is normal, no alert is generated.
6. If the reading is warning or critical, an alert record is created.
7. Registered FCM tokens are loaded from DynamoDB.
8. A push notification is sent using Firebase Cloud Messaging.
9. Email cooldown/settings and recipients are checked.
10. An alert email is sent through AWS SESv2 if allowed.
11. The dashboard displays alert history and allows alert status updates.

The repository confirms push notification support through Firebase Admin SDK on the backend and Firebase Messaging on the Flutter Web frontend. The backend sends notifications to registered tokens, and the web service worker handles background notification display.

The email implementation uses AWS SESv2. SESv2 is used for registration/password reset verification emails and alert email delivery. The backend also includes logic to resolve alert recipients and apply email cooldown behaviour. Final evidence of delivered push and email notifications is `[To be completed]`.

## 4.7 Security Implementation

The implemented security functions focus mainly on custom account authentication, email verification, and role-based dashboard behaviour. The backend includes registration, login, verification code, and password reset handlers. Passwords are hashed before storage using SHA-256 in the inspected code. Email verification codes are sent through SESv2.

The frontend stores session-related state and uses role information to determine available dashboard pages and actions. Admin management is implemented in the dashboard and backend, allowing administrator-related operations to be managed through API calls.

The security limitations must be clearly stated in the final report. API Gateway authorizer/JWT verification was not found in the inspected implementation. Password hashing uses SHA-256 without confirmed salt or adaptive hashing. The firmware HTTP fallback uses insecure TLS mode in demo code. Firmware credentials and cloud certificates also require careful handling in a production deployment. Therefore, the implemented security is suitable for prototype demonstration, but production deployment would require stronger authentication, authorization, credential protection, and transport-security hardening.

| Security area | Implementation status |
|---|---|
| Email/password registration and login | Implemented. |
| Email verification and password reset codes | Implemented through SESv2 email. |
| Role-based dashboard access | Implemented in frontend/backend logic. |
| API Gateway JWT/authorizer | `[Not implemented]` in inspected code. |
| Salted/adaptive password hashing | `[Not implemented]`; SHA-256 hashing found. |
| Firmware HTTP TLS verification | `[Not implemented]` for fallback demo mode; insecure TLS mode found. |
| Production secret management | `[To be completed]`. |

# Chapter 5: System Testing and Evaluation

This chapter describes the testing strategy and evaluation plan for Alertrix. The repository contains useful demo scripts and one Flutter widget test, but complete measured evaluation results are not stored in the repository. Therefore, this chapter separates confirmed test/tool status from result tables that still require final evidence.

## 5.1 Testing Strategy

The testing strategy is divided into functional testing, integration testing, performance testing, and usability testing. Functional testing verifies whether individual features work as expected. Integration testing verifies the communication between ESP32, AWS IoT Core, Lambda, DynamoDB, notification services, and the dashboard. Performance testing measures alert latency and repeated-trial reliability. Usability testing evaluates whether users can understand and perform the dashboard workflows.

The overall test coverage should address the following areas:

| Test area | Purpose |
|---|---|
| Hardware and firmware testing | Verify sensor reading, local buzzer, Wi-Fi connection, MQTT publishing, and cloud silence control. |
| Backend functional testing | Verify API responses, Lambda handlers, threshold logic, data storage, and alert status update. |
| Integration testing | Verify end-to-end data flow from sensor telemetry to dashboard and notifications. |
| Notification testing | Verify Firebase push delivery and SESv2 email delivery. |
| Security testing | Verify login, registration, password reset, and role-based access behaviour. |
| Performance testing | Measure alert latency, repeated ingest success rate, and notification delivery rate. |
| Usability testing | Evaluate whether users can monitor readings, understand alerts, and complete response actions. |

## 5.2 Functional Testing

Functional testing focuses on the expected behaviour of each implemented module. The functional test cases in Table 5.1 should be completed using serial monitor output, API responses, DynamoDB screenshots, dashboard screenshots, and notification screenshots.

| Test ID | Function tested | Test procedure | Expected result | Actual result | Status |
|---|---|---|---|---|---|
| FT1 | ESP32 DHT11 reading | Run firmware and observe serial monitor. | Temperature and humidity values are printed when sensor reading is valid. | `[To be completed]` | `[To be completed]` |
| FT2 | ESP32 water-level reading | Place sensor in different water levels and observe output. | ADC value and water-level percentage change accordingly. | `[To be completed]` | `[To be completed]` |
| FT3 | Local buzzer | Trigger local threshold condition. | Buzzer activates unless cloud silence state is enabled. | `[To be completed]` | `[To be completed]` |
| FT4 | MQTT telemetry publish | Connect ESP32 to Wi-Fi and AWS IoT Core. | Telemetry is published to `alertrix/sensors/ingest`. | `[To be completed]` | `[To be completed]` |
| FT5 | HTTP fallback ingest | Send test data to `/api/sensors/ingest`. | Backend stores reading and returns ingest result. | `[To be completed]` | `[To be completed]` |
| FT6 | Normal reading | Submit value below warning threshold. | Reading is stored and no alert is generated. | `[To be completed]` | `[To be completed]` |
| FT7 | Warning/Critical reading | Submit value above warning or critical threshold. | Alert record is created with correct severity. | `[To be completed]` | `[To be completed]` |
| FT8 | Latest readings dashboard | Open dashboard after telemetry submission. | Latest sensor values are displayed. | `[To be completed]` | `[To be completed]` |
| FT9 | Alert status update | Confirm alert from dashboard. | Alert status is updated in backend storage. | `[To be completed]` | `[To be completed]` |
| FT10 | Notification settings | Update notification settings from dashboard. | Backend stores the updated settings. | `[To be completed]` | `[To be completed]` |
| FT11 | Work order creation | Create a work order from an alert. | Work order record is created and linked to alert. | `[To be completed]` | `[To be completed]` |
| FT12 | Admin management | Perform admin management operation. | Admin-related data is updated according to role. | `[To be completed]` | `[To be completed]` |

The automated test status observed during repository inspection is shown below.

| Command | Observed result |
|---|---|
| `flutter test` | Failed because the widget test expected old text `Alertrix Login`, which did not match the current login page. |
| `npm test` in backend | Completed but only printed `"add tests if needed"`; no backend tests were executed. |
| `flutter analyze` | Reported warnings/information, mainly deprecated API usage, web-only library warnings, and one unused declaration. |

## 5.3 Integration Testing

Integration testing verifies whether independently implemented modules work together as a complete monitoring and alerting workflow. The most important integration path is the alert notification flow from ESP32 telemetry to cloud processing and dashboard display.

| Integration test | Components involved | Expected result | Actual result |
|---|---|---|---|
| IT1: MQTT ingest flow | ESP32, AWS IoT Core, SensorIngestLambda, DynamoDB | Sensor reading published by ESP32 is received by Lambda and stored in DynamoDB. | `[To be completed]` |
| IT2: HTTP fallback ingest flow | Demo script/ESP32 fallback, API Gateway, SensorIngestLambda, DynamoDB | HTTP telemetry request is routed to Lambda and stored. | `[To be completed]` |
| IT3: Alert generation flow | Lambda, DynamoDB, threshold logic | Warning/critical reading creates an alert record. | `[To be completed]` |
| IT4: Push notification flow | Lambda, DynamoDB push tokens, FCM, Flutter Web browser | Registered browser receives push alert. | `[To be completed]` |
| IT5: Email notification flow | Lambda, settings/user/admin data, SESv2 | Eligible recipient receives alert email. | `[To be completed]` |
| IT6: Dashboard data flow | Flutter Web, API Gateway, Lambda, DynamoDB | Dashboard displays latest readings, trends, and alert history. | `[To be completed]` |
| IT7: Alert response flow | Flutter Web, API Gateway, AlertStatusLambda, DynamoDB | Confirmed alert status is persisted and shown in dashboard. | `[To be completed]` |

The recommended end-to-end integration evidence is: ESP32 serial monitor screenshot, AWS IoT Core test client or IoT Rule evidence, CloudWatch Lambda logs, DynamoDB item screenshots, FCM/browser notification screenshot, SES email screenshot, and dashboard alert screenshot.

## 5.4 Performance Testing

Performance testing should measure whether the system can deliver alerts within an acceptable time for a prototype disaster-response monitoring system. The main measurement is end-to-end alert latency, defined as the time from telemetry publishing to alert notification receipt.

| Trial | Sensor type | Trigger value | Publish time | Alert created time | Notification received time | End-to-end latency |
|---|---|---:|---|---|---|---|
| 1 | waterLevel | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 2 | temperature | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| 3 | vibration | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |

Reliability should also be measured using repeated submissions. The repository includes scripts that can support normal-stream and critical-alert trials, but final measured results are `[To be completed]`.

| Test type | Number of attempts | Successful attempts | Failed attempts | Success rate |
|---|---:|---:|---:|---:|
| Normal telemetry ingest | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| Critical alert generation | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| Push notification delivery | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |
| Email notification delivery | `[To be completed]` | `[To be completed]` | `[To be completed]` | `[To be completed]` |

Because no confirmed measured latency or reliability results are available in the repository, the final report should not claim a specific latency value until actual measurements are collected.

## 5.5 Usability Testing

Usability testing evaluates whether target users can understand and use the dashboard during a monitoring or response scenario. For this project, the recommended participants are `[To be completed]`, such as students, supervisors, or potential response users. The testing tasks should focus on common dashboard workflows.

| Task ID | Usability task | Success criteria | Result |
|---|---|---|---|
| UT1 | Log in to the dashboard. | User can access dashboard without assistance. | `[To be completed]` |
| UT2 | Identify latest water-level or temperature reading. | User can locate current reading within a short time. | `[To be completed]` |
| UT3 | View trend page. | User can select metric/time range and understand chart. | `[To be completed]` |
| UT4 | Open an alert detail page. | User can identify severity, zone, trigger value, and status. | `[To be completed]` |
| UT5 | Confirm an alert. | User can complete alert confirmation successfully. | `[To be completed]` |
| UT6 | Update notification settings. | User can save setting changes successfully. | `[To be completed]` |
| UT7 | Create or review a work order. | User can complete the response workflow. | `[To be completed]` |

Usability feedback should be summarized using completion rate, observed difficulties, and participant comments. Screenshots or photos of usability testing sessions are `[To be completed]`.

## 5.6 Testing Results and Discussion

The current implementation provides a working prototype foundation, but final evaluation evidence is not yet complete. The source code confirms that the system supports telemetry ingest, threshold-based alert generation, alert storage, push notification, email notification, dashboard monitoring, alert response, work orders, and settings management. However, actual deployment evidence and measured test results must be collected before the final submission.

The current testing status is summarized in Table 5.6.

| Evaluation item | Current status | Discussion |
|---|---|---|
| Firmware function | Partially confirmed by code. | DHT11, water-level, buzzer, MQTT, and cloud silence logic are implemented. Physical vibration sensor is `[Not implemented]`. |
| Backend API function | Confirmed by code. | API Gateway and Lambda handlers implement telemetry, readings, alerts, settings, work orders, auth, and admin functions. |
| Database storage | Confirmed by code. | DynamoDB tables and Put/Update/Scan/Get operations are implemented. Screenshot evidence is `[To be completed]`. |
| Push notification | Confirmed by code. | FCM token registration and multicast sending are implemented. Delivery screenshot is `[To be completed]`. |
| Email notification | Confirmed by code. | SESv2 verification and alert email logic are implemented. Delivery screenshot is `[To be completed]`. |
| Frontend dashboard | Confirmed by code. | Dashboard pages are implemented. Final screenshots are `[To be completed]`. |
| Automated testing | Incomplete. | Flutter widget test currently fails and backend tests are placeholders. |
| Performance testing | `[To be completed]`. | Latency and reliability should be measured using repeated trials. |
| Usability testing | `[To be completed]`. | Participant task results and feedback should be collected. |

The main strength of Alertrix is the integration of embedded sensing, cloud processing, database storage, notifications, and dashboard-based response functions. The main limitations are incomplete measured evaluation, fixed threshold rules, scan-based database reads, incomplete automated tests, and prototype-level security. Therefore, the results should be discussed as evidence of a functioning prototype rather than as proof of production-ready disaster response performance.

# Chapter 6: SDG Alignment

## 6.1 Relevant Sustainable Development Goal

Alertrix aligns most directly with Sustainable Development Goal 13: Climate Action. SDG 13 emphasizes the need to strengthen resilience and adaptive capacity to climate-related hazards and natural disasters. Alertrix supports this direction by demonstrating how IoT sensing, cloud processing, and digital notifications can contribute to early awareness of hazardous environmental conditions.

## 6.2 Contribution to Disaster Preparedness and Early Warning

The implemented system contributes to disaster preparedness by collecting environmental telemetry and converting abnormal readings into warning or critical alerts. In the implemented prototype, water-level and temperature readings are collected by the ESP32 firmware, while the backend also contains alert logic for vibration values. When readings exceed fixed thresholds, the system stores alert records and notifies users through browser push notification and email.

This supports an early-warning workflow because users do not need to manually inspect the site continuously. Instead, they can monitor the dashboard, receive alert notifications, review alert history, and respond by confirming alerts or creating work orders. These functions are relevant to disaster response management because they improve visibility of changing field conditions.

## 6.3 Social and Practical Impact

At prototype level, Alertrix demonstrates a low-cost approach for monitoring risk indicators and notifying users. The system may be useful in educational, laboratory, or small-site monitoring scenarios where real-time awareness is required. The dashboard and alert history can also support post-incident review by showing when readings were captured and when alerts were generated or updated.

However, the system should not be presented as a fully deployed public emergency system. Actual SDG impact would require field validation, reliable connectivity under disaster conditions, multiple deployed sensor nodes, backup power, agency-level response procedures, and stronger security. These items remain future work.

## 6.4 Limitations of SDG Contribution

The SDG contribution is limited by the prototype scope. The inspected firmware does not implement a physical vibration sensor, and measured latency, reliability, usability, and field results are still `[To be completed]`. Therefore, the project contributes mainly as a proof-of-concept implementation that demonstrates how a cloud-assisted IoT architecture can support early warning and disaster response monitoring.

# Chapter 7: Conclusion and Future Work

## 7.1 Conclusion

This project implemented Alertrix, a cloud-assisted IoT prototype for disaster response management. The implemented system integrates ESP32 firmware, AWS IoT Core MQTT ingest, AWS Lambda backend processing, DynamoDB storage, Firebase Cloud Messaging push notifications, AWS SESv2 email notifications, and a Flutter Web dashboard. The system supports sensor telemetry storage, threshold-based alert generation, alert history, alert status updates, work orders, notification settings, device location settings, cloud buzzer silence, custom authentication, and admin management.

The project achieves the main goal of demonstrating an end-to-end IoT disaster response monitoring workflow. The ESP32 collects sensor values and publishes telemetry to the cloud. AWS Lambda processes the readings and creates alerts when threshold conditions are met. DynamoDB stores readings, alerts, and related system data. The Flutter Web dashboard allows users to view current conditions, inspect trends, review alert history, and perform response actions.

At the same time, the implementation has limitations that must be clearly stated. Physical vibration sensing is not implemented in the inspected firmware, although vibration is represented in backend/dashboard logic. Evaluation evidence such as latency, reliability, usability results, deployed screenshots, CloudWatch logs, and notification delivery proof is still `[To be completed]`. Automated tests are also incomplete. Therefore, Alertrix should be concluded as a functional prototype, not as a production-ready disaster response system.

## 7.2 Future Work

Future work should improve both implementation completeness and evaluation quality. The recommended improvements are:

1. Add and validate a physical vibration sensor in the ESP32 firmware.
2. Add humidity storage and alert logic if humidity remains within the final project scope.
3. Move threshold values from hardcoded constants to secured database configuration.
4. Add stronger authentication and authorization using JWT, Amazon Cognito, Firebase Auth token verification, or API Gateway authorizers.
5. Replace SHA-256-only password hashing with salted adaptive password hashing.
6. Improve firmware credential and certificate management.
7. Remove insecure TLS behaviour from HTTP fallback before any production deployment.
8. Add automated backend unit tests and integration tests.
9. Fix the outdated Flutter widget test and address analyzer warnings.
10. Add DynamoDB secondary indexes for scalable querying.
11. Add offline buffering on the ESP32 when network connection is unavailable.
12. Support multiple sensor nodes with device registration and location mapping.
13. Add map-based visualization for deployed sensor locations.
14. Conduct controlled field testing using real sensor conditions.
15. Measure alert latency, reliability, notification success rate, and false alarm rate using repeated trials.

# References

`[To be completed: Use IEEE or required university citation style. Add 15-20 related works covering IoT disaster monitoring, flood early warning, vibration/structural monitoring, cloud-assisted IoT, serverless architectures, notification systems, and dashboard visualization.]`

Example placeholder format:

`[1] [To be completed]`

`[2] [To be completed]`

`[3] [To be completed]`

# Appendices

## Appendix A: Source Code Structure

| Folder/file | Description |
|---|---|
| `arduino/DHT11WaterLevelPractice/` | ESP32 firmware, MQTT secrets, and certificates. |
| `backend/` | AWS SAM backend and Lambda code. |
| `lib/` | Flutter Web frontend source code. |
| `web/` | Flutter Web assets and Firebase messaging service worker. |
| `scripts/` | Deployment, launch, demo stream, seed, and testing helper scripts. |
| `test/` | Flutter widget test. |
| `docs/` | Generated final report documentation files. |

## Appendix B: API Endpoint Table

See `docs/api_endpoint_table.md`.

## Appendix C: Database Design

See `docs/database_design.md`.

## Appendix D: Testing and Evaluation Tables

See `docs/testing_and_evaluation.md`.

## Appendix E: Diagrams

See `docs/diagrams.md`.

## Appendix F: Screenshot Checklist

See `docs/screenshot_checklist.md`.
