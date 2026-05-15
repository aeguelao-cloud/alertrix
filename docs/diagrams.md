# Alertrix Diagrams

The diagrams below are generated from the implemented repository structure. Items marked `[Not implemented]` or `[To be completed]` should not be described as completed in the final report until evidence is added.

## System Architecture Diagram

```mermaid
flowchart LR
    subgraph SensorLayer["Sensor Layer"]
        ESP32["ESP32 firmware"]
        DHT11["DHT11 temperature/humidity"]
        Water["Analog water level sensor"]
        Buzzer["Local buzzer"]
        VibFallback["Vibration fallback value\n[physical sensor not implemented]"]
    end

    subgraph NetworkLayer["Connectivity Layer"]
        WiFi["Wi-Fi"]
        MQTT["MQTT over TLS"]
        HTTP["HTTP fallback\n(configurable)"]
    end

    subgraph AWS["AWS Cloud"]
        IoT["AWS IoT Core Rule\nalertrix/sensors/ingest"]
        Api["API Gateway\n/prod/api"]
        Lambda["Node.js Lambda handlers"]
        DDB["DynamoDB tables"]
        SES["SESv2 email"]
        SNS["SNS email topics"]
    end

    subgraph Firebase["Firebase"]
        FCM["Firebase Cloud Messaging"]
        SW["Web service worker"]
    end

    subgraph Frontend["Flutter Web Dashboard"]
        Login["Login/Register"]
        Dash["Response Overview"]
        Trends["Situation Trends"]
        Alerts["Incident Queue"]
        Settings["Response Settings"]
        Admin["Admin Management"]
        WO["Work Orders"]
    end

    DHT11 --> ESP32
    Water --> ESP32
    VibFallback --> ESP32
    ESP32 --> Buzzer
    ESP32 --> WiFi
    WiFi --> MQTT
    WiFi --> HTTP
    MQTT --> IoT
    IoT --> Lambda
    HTTP --> Api
    Api --> Lambda
    Lambda --> DDB
    Lambda --> FCM
    Lambda --> SES
    Lambda --> SNS
    FCM --> SW
    SW --> Frontend
    Frontend --> Api
    Api --> Lambda
```

## Module Diagram

```mermaid
flowchart TB
    Alertrix["Alertrix System"]

    subgraph Firmware["Firmware Module"]
        SensorRead["Read DHT11 and water ADC"]
        LocalAlarm["Local alarm and buzzer"]
        MqttPublish["MQTT publish"]
        HttpPost["HTTP ingest fallback"]
        CloudSilence["Fetch buzzer silence state"]
    end

    subgraph Backend["Backend Module"]
        Auth["Authentication and verification"]
        Ingest["Sensor ingest and threshold analysis"]
        Alert["Alert management"]
        WorkOrder["Work order management"]
        Push["FCM push notification"]
        Email["SES alert and verification email"]
        Settings["Notification/device/buzzer settings"]
        AdminMgmt["Admin management"]
        Bootstrap["App bootstrap aggregation"]
    end

    subgraph Data["Data Module"]
        ReadingsTable["Sensor readings table"]
        AlertsTable["Alerts table"]
        WorkOrdersTable["Work orders table"]
        TokensTable["Push tokens table"]
        ProfilesTable["User profiles table"]
        AdminsTable["Admins table"]
        AuthUsersTable["Auth users table"]
        SettingsTable["Settings table"]
        CodesTable["Verification codes table"]
    end

    subgraph UI["Flutter Web Module"]
        LoginUI["Login/Register/Reset"]
        DashboardUI["Response overview dashboard"]
        TrendsUI["Situation trends"]
        AlertsUI["Alert center and detail"]
        SettingsUI["Response settings"]
        AdminUI["Admin management"]
        WorkOrderUI["Work orders"]
        PushUI["FCM token registration"]
        SoundUI["Local alert sound"]
    end

    Alertrix --> Firmware
    Alertrix --> Backend
    Alertrix --> Data
    Alertrix --> UI

    Firmware --> Ingest
    Backend --> Data
    UI --> Backend
    Push --> PushUI
```

## Use Case Diagram

```mermaid
flowchart LR
    Operator["User / Operator"]
    Admin["Admin"]
    SuperAdmin["Super Admin"]
    ESP32["ESP32 Sensor Node"]
    FCMUser["Dashboard Browser"]

    subgraph Alertrix["Alertrix System"]
        UC1(("Register account"))
        UC2(("Login"))
        UC3(("View response overview"))
        UC4(("View latest sensor readings"))
        UC5(("View situation trends"))
        UC6(("View alert history"))
        UC7(("Confirm alert"))
        UC8(("Ignore alert"))
        UC9(("Create work order"))
        UC10(("Manage notification settings"))
        UC11(("Update device location"))
        UC12(("Silence buzzer"))
        UC13(("Receive push notification"))
        UC14(("Manage admin accounts"))
        UC15(("Send sensor telemetry"))
        UC16(("Process threshold alert"))
        UC17(("Store telemetry and alert records"))
    end

    Operator --> UC1
    Operator --> UC2
    Operator --> UC3
    Operator --> UC4
    Operator --> UC5
    Operator --> UC6
    Operator --> UC7
    Operator --> UC10
    Operator --> UC11
    Operator --> UC12
    Operator --> UC13

    Admin --> UC2
    Admin --> UC3
    Admin --> UC4
    Admin --> UC5
    Admin --> UC6
    Admin --> UC7
    Admin --> UC8
    Admin --> UC9
    Admin --> UC10
    Admin --> UC11
    Admin --> UC12
    Admin --> UC13
    Admin --> UC14

    SuperAdmin --> UC14

    ESP32 --> UC15
    UC15 --> UC16
    UC16 --> UC17
    UC16 --> UC13
    FCMUser --> UC13
```

## Alert Processing Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    participant ESP32 as ESP32 sensor node
    participant IoT as AWS IoT Core
    participant API as API Gateway
    participant Lambda as Ingest Lambda
    participant DDB as DynamoDB
    participant FCM as Firebase Cloud Messaging
    participant SES as SESv2 Email
    participant Web as Flutter Web Dashboard

    ESP32->>IoT: Publish MQTT JSON on alertrix/sensors/ingest
    IoT->>Lambda: Invoke Lambda through IoT Rule
    alt HTTP fallback or demo script
        ESP32->>API: POST /api/sensors/ingest
        API->>Lambda: Invoke ingest handler
    end
    Lambda->>Lambda: Validate sensorType and numeric value
    Lambda->>DDB: Store sensor reading
    Lambda->>Lambda: Compare value against fixed thresholds
    alt Normal reading
        Lambda-->>API: stored=true, alertGenerated=false
    else Warning/Critical reading
        Lambda->>DDB: Store alert record
        Lambda->>DDB: Read push tokens
        Lambda->>FCM: Send multicast notification
        Lambda->>DDB: Check/store email cooldown setting
        Lambda->>SES: Send alert email if allowed
        Lambda-->>API: stored=true, alertGenerated=true
        FCM-->>Web: Browser push notification
    end
    Web->>API: GET /api/readings/latest and /api/alerts
    API->>DDB: Query/scan latest data
    API-->>Web: Updated dashboard snapshot
```

## Database Design Diagram

```mermaid
erDiagram
    SENSOR_READINGS {
        string sensorType PK
        string capturedAt SK
        number value
        string zone
    }

    ALERTS {
        string alertId PK
        string title
        string severity
        string status
        string detectedAt
        string zone
        string triggerValue
        string workOrderId
    }

    WORK_ORDERS {
        string workOrderId PK
        string alertId FK
        string status
        string assignee
        string note
        string createdAt
    }

    PUSH_TOKENS {
        string token PK
        string userId
        string platform
        string updatedAt
    }

    SETTINGS {
        string settingId PK
        string location
        string zone
        string silencedUntil
        string lastSentAt
    }

    USER_PROFILES {
        string userId PK
        string role
        string pushRule
        boolean alertSoundEnabled
        string notificationEmail
    }

    ADMINS {
        string adminId PK
        string name
        string email
        string role
        string status
    }

    AUTH_USERS {
        string username PK
        string name
        string passwordHash
        string email
        string role
    }

    VERIFICATION_CODES {
        string email PK
        string code
        string name
        number expiresAtMs
        number ttl
    }

    ALERTS ||--o| WORK_ORDERS : "alertId"
    AUTH_USERS ||--o| USER_PROFILES : "username/userId"
    USER_PROFILES ||--o{ PUSH_TOKENS : "userId"
```

## Class Diagram

```mermaid
classDiagram
    direction LR

    class ESP32Firmware {
        +readSensors()
        +publishMqtt()
        +fetchBuzzerState()
        +controlBuzzer()
    }

    class SensorReading {
        +sensorType: string
        +value: number
        +zone: string
        +capturedAt: string
    }

    class AWSIoTCore {
        +topic: string
        +invokeIngestLambda()
    }

    class ApiGateway {
        +routeRequest()
    }

    class LambdaFunctions {
        +storeReading()
        +evaluateThreshold()
        +createAlert()
        +updateAlertStatus()
    }

    class DynamoDB {
        +SensorTable
        +AlertTable
        +PushTokenTable
        +SettingsTable
        +UserProfileTable
        +AdminTable
    }

    class Alert {
        +alertId: string
        +severity: string
        +status: string
        +zone: string
        +triggerValue: string
    }

    class FCMService {
        +sendNotificationToAll()
    }

    class EmailNotifier {
        +resolveAlertRecipients()
        +sendAlertEmail()
    }

    class FlutterWebDashboard {
        +viewDashboard()
        +viewAlerts()
        +confirmAlert()
        +manageSettings()
    }

    class MonitoringController {
        +fetchSnapshot()
        +confirmAlert()
        +createWorkOrder()
    }

    class AwsMonitoringApi {
        +fetchSnapshot()
        +updateAlertStatus()
        +createWorkOrder()
    }

    ESP32Firmware --> SensorReading : creates
    ESP32Firmware --> AWSIoTCore : MQTT telemetry
    ESP32Firmware ..> ApiGateway : HTTP fallback
    AWSIoTCore --> LambdaFunctions : IoT Rule
    ApiGateway --> LambdaFunctions : REST API
    LambdaFunctions --> DynamoDB : read/write
    LambdaFunctions --> Alert : creates/updates
    LambdaFunctions --> FCMService : push alert
    LambdaFunctions --> EmailNotifier : email alert
    FlutterWebDashboard --> MonitoringController : uses
    MonitoringController --> AwsMonitoringApi : uses
    AwsMonitoringApi --> ApiGateway : calls
```

## User Flow Diagram

```mermaid
flowchart TD
    Start["Open Alertrix Web App"] --> HasAccount{"Has account?"}
    HasAccount -- No --> Register["Request verification code"]
    Register --> EmailCode["Receive email code"]
    EmailCode --> CreateAccount["Create account"]
    CreateAccount --> Login["Login"]
    HasAccount -- Yes --> Login

    Login --> Role{"Resolved role"}
    Role -- User --> UserHome["Response Overview"]
    Role -- Admin --> AdminHome["Response Overview with admin navigation"]

    UserHome --> Dashboard["View latest readings and alert summary"]
    AdminHome --> Dashboard
    Dashboard --> Trends["View situation trends"]
    Dashboard --> Alerts["Open incident queue"]

    Alerts --> Detail["Open alert detail"]
    Detail --> Confirm["Confirm alert"]
    Detail --> Ignore{"Ignore alert?"}
    Ignore -- Admin only --> Ignored["Alert status updated to IGNORED"]
    Ignore -- User --> Denied["Denied by backend policy"]
    Detail --> WorkOrder{"Create work order?"}
    WorkOrder -- Admin only --> WO["Work order created"]
    WorkOrder -- User --> DeniedWO["Denied by backend policy"]

    Dashboard --> Settings["Response settings"]
    Settings --> Notify["Update push/email/sound settings"]
    Settings --> Location["Update device location"]
    Dashboard --> Push["Enable browser push notification"]
    Dashboard --> Logout["Logout"]
```

## Report Figure Notes

The diagrams are Mermaid drafts. For the final submitted report, export them as high-resolution images and add captions such as:

| Figure | Suggested caption |
|---|---|
| System architecture | Overall Alertrix cloud-assisted IoT architecture. |
| Module diagram | Main implementation modules of the Alertrix prototype. |
| Use case diagram | Main actors and use cases supported by the Alertrix prototype. |
| Sequence diagram | Alert processing sequence from sensor telemetry to dashboard notification. |
| Database design | DynamoDB table structure and application-level relationships. |
| Class diagram | Main firmware, backend, and Flutter Web classes/components in Alertrix. |
| User flow | User interaction flow for authentication, monitoring, alert response, and settings. |
