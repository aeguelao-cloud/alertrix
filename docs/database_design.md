# Alertrix Database Design

The implemented database layer uses Amazon DynamoDB. Tables are defined in `backend/template.yaml`, and table names are injected into Lambda handlers through environment variables in `backend/src/common/dynamo.js`.

Because DynamoDB is schemaless beyond primary keys, the field lists below are derived from items written or read by the Lambda code.

## Table Overview

| Logical table | Physical table name | Primary key | Sort key | Purpose |
|---|---|---|---|---|
| SensorTable | `alertrix-sensor-readings-my` | `sensorType` (String) | `capturedAt` (String) | Stores telemetry readings. |
| AlertTable | `alertrix-alerts-my` | `alertId` (String) | None | Stores threshold-generated alerts. |
| WorkOrderTable | `alertrix-work-orders-my` | `workOrderId` (String) | None | Stores work orders created from alerts. |
| PushTokenTable | `alertrix-push-tokens-my` | `token` (String) | None | Stores FCM tokens. |
| SettingsTable | `alertrix-settings-my` | `settingId` (String) | None | Stores device location, buzzer silence state, and email cooldown state. |
| UserProfileTable | `alertrix-user-profiles-my` | `userId` (String) | None | Stores user notification preferences/profile data. |
| AdminTable | `alertrix-admins-my` | `adminId` (String) | None | Stores admin contact and status records. |
| AuthUserTable | `alertrix-auth-users-my` | `username` (String) | None | Stores login credentials and user role. |
| VerificationCodeTable | `alertrix-verification-codes-my` | `email` (String) | None | Stores verification/reset codes with TTL. |

## Sensor Readings Table

**Table:** `alertrix-sensor-readings-my`

| Field | Type | Required by code | Description |
|---|---|---|---|
| `sensorType` | String | Yes | Partition key. Implemented sensor types include `waterLevel`, `vibration`, and `temperature`. |
| `capturedAt` | String | Yes | Sort key. ISO timestamp of reading capture or server receive time. |
| `value` | Number | Yes | Numeric reading value. |
| `zone` | String | Optional with default | Site or zone label; defaults to `Unknown Zone` in ingest handler if not supplied. |

Access pattern:

| Operation | Implementation |
|---|---|
| Store reading | `PutCommand` in `ingestSensorData.js`. |
| Latest reading by sensor type | `QueryCommand` with `sensorType`, descending `capturedAt`, `Limit: 1`. |
| Trend series | `QueryCommand` by `sensorType`, descending order, limited by range point count. |

## Alerts Table

**Table:** `alertrix-alerts-my`

| Field | Type | Required by code | Description |
|---|---|---|---|
| `alertId` | String | Yes | Primary key. Generated as `ALERT-{Date.now()}`. |
| `title` | String | Yes | Human-readable alert title. |
| `severity` | String | Yes | `WARNING` or `CRITICAL` for generated threshold alerts. |
| `status` | String | Yes | Initially `ACTIVE`; update endpoints use `OPEN`, `CONFIRMED`, `IGNORED`, or `WORK_ORDER_CREATED`. |
| `detectedAt` | String | Yes | Timestamp of reading that triggered the alert. |
| `zone` | String | Yes | Zone associated with the alert. |
| `triggerValue` | String | Yes | Reading value with unit, such as `90%`. |
| `updatedAt` | String | Optional | Written when alert status changes. |
| `updatedByRole` | String | Optional | Role submitted during status update. |
| `workOrderId` | String | Optional | Work order ID after work order creation. |

Access pattern:

| Operation | Implementation |
|---|---|
| Create alert | `PutCommand` in `ingestSensorData.js`. |
| List alerts | `ScanCommand` with optional in-memory filtering by `severity` and `status`. |
| Update status | `UpdateCommand` by `alertId`. |
| Link work order | `UpdateCommand` by `alertId` when work order is created. |

## Work Orders Table

**Table:** `alertrix-work-orders-my`

| Field | Type | Required by code | Description |
|---|---|---|---|
| `workOrderId` | String | Yes | Primary key. Generated as `WO-{last 8 digits of Date.now()}`. |
| `alertId` | String | Yes | Alert that produced the work order. |
| `status` | String | Yes | Initially `OPEN`. |
| `assignee` | String | Yes | Defaults to `Emergency Team`. |
| `note` | String | Yes | Defaults to `Generated from alert workflow`. |
| `createdAt` | String | Yes | ISO timestamp. |
| `createdByRole` | String | Yes | Role submitted by caller. |

Relationship:

| Relationship | Description |
|---|---|
| Alert to Work Order | One alert can be linked to one created work order through `AlertTable.workOrderId` and `WorkOrderTable.alertId`. This is enforced by application logic, not by DynamoDB constraints. |

## Push Tokens Table

**Table:** `alertrix-push-tokens-my`

| Field | Type | Required by code | Description |
|---|---|---|---|
| `token` | String | Yes | Primary key. FCM registration token. |
| `userId` | String | Optional | Defaults to `anonymous`. |
| `platform` | String | Optional | Defaults to `unknown`; frontend sends `web` for Flutter Web. |
| `updatedAt` | String | Yes | Last registration timestamp. |

Access pattern:

| Operation | Implementation |
|---|---|
| Register/update token | `PutCommand` in `registerPushToken.js`. |
| Send notification | `ScanCommand` in `fcm.js` to load all tokens. |

## Settings Table

**Table:** `alertrix-settings-my`

This table stores multiple record types using `settingId`.

### Device Location Record

| Field | Type | Description |
|---|---|---|
| `settingId` | String | Fixed value `device-location`. |
| `location` | String | Configured location; default fallback is `Zone A - Pump Station`. |
| `updatedAt` | String | Last update timestamp. |

### Buzzer Silence Record

| Field | Type | Description |
|---|---|---|
| `settingId` | String | `buzzer-silence:{zone}`. |
| `zone` | String | Zone label. |
| `durationSeconds` | Number | Silence duration, default `120`, maximum `3600`. |
| `silencedUntil` | String or null | Timestamp until which buzzer should remain silenced. |
| `requestedBy` | String | User ID or fallback `unknown`. |
| `updatedAt` | String | Last update timestamp. |

### Alert Email Cooldown Record

| Field | Type | Description |
|---|---|---|
| `settingId` | String | `EMAIL_COOLDOWN#{sensorType}#{zone}#{severity}`. |
| `type` | String | `emailCooldown`. |
| `sensorType` | String | Sensor type. |
| `zone` | String | Zone label. |
| `severity` | String | Alert severity. |
| `lastSentAt` | String | Last email send timestamp for cooldown logic. |
| `updatedAt` | String | Last update timestamp. |

## User Profiles Table

**Table:** `alertrix-user-profiles-my`

| Field | Type | Required by code | Description |
|---|---|---|---|
| `userId` | String | Yes | Primary key; usually email/username or fallback role key. |
| `name` | String | Optional | User display name created during registration. |
| `role` | String | Optional | Defaults to `User`. |
| `pushRule` | String | Optional | `Warning + Critical`, `Critical only`, or `Disabled`. |
| `alertSoundEnabled` | Boolean | Optional | Controls local alert sound in frontend. |
| `notificationEmail` | String | Optional | Email recipient for alert emails/SNS subscription. |
| `emailSubscriptionStatus` | String | Optional | `Not configured`, `Pending confirmation`, or `Subscribed`. |
| `criticalTopicSubscriptionArn` | String/null | Optional | SNS subscription ARN for critical topic. |
| `warningTopicSubscriptionArn` | String/null | Optional | SNS subscription ARN for warning topic. |
| `updatedAt` | String | Optional | Last update timestamp. |

Relationship:

| Relationship | Description |
|---|---|
| User profile to alert recipients | `alertRecipients.js` scans user profiles and sends email based on `pushRule` and `notificationEmail`. |

## Admins Table

**Table:** `alertrix-admins-my`

| Field | Type | Required by code | Description |
|---|---|---|---|
| `adminId` | String | Yes | Primary key. Generated as `ADM-{random hex}`. |
| `name` | String | Yes | Admin name. |
| `email` | String | Yes | Admin email; duplicate email is rejected by application scan. |
| `role` | String | Yes | `admin` or `super_admin`. |
| `status` | String | Yes | `active` or `inactive`. |
| `createdAt` | String | Yes | Creation timestamp. |
| `updatedAt` | String | Yes | Last update timestamp. |
| `createdBy` | String | Yes | Actor ID creating record. |
| `updatedBy` | String | Yes | Actor ID updating record. |

Relationship:

| Relationship | Description |
|---|---|
| Admin to alert email | `listActiveAdminEmails()` returns emails for active admin records. These become alert email recipients. |
| Admin to login role | `/api/auth/login` scans active admins to resolve an authenticated user as `Admin`. |

## Auth Users Table

**Table:** `alertrix-auth-users-my`

| Field | Type | Required by code | Description |
|---|---|---|---|
| `username` | String | Yes | Primary key; implemented as lowercase email. |
| `name` | String | Yes | Registered name. |
| `passwordHash` | String | Yes | SHA-256 hash of password. |
| `email` | String | Yes | Email address. |
| `role` | String | Yes | Defaults to `User`. |
| `createdAt` | String | Yes | Creation timestamp. |
| `updatedAt` | String | Yes | Last update timestamp. |

Security note:

| Item | Status |
|---|---|
| Salted/adaptive password hashing | `[Not implemented]` in inspected code. |
| JWT/session storage | `[Not implemented]` in inspected code. |

## Verification Codes Table

**Table:** `alertrix-verification-codes-my`

| Field | Type | Required by code | Description |
|---|---|---|---|
| `email` | String | Yes | Primary key. |
| `code` | String | Yes | 6-digit verification code. |
| `name` | String | Yes for registration flow | Name associated with verification request. |
| `expiresAtMs` | Number | Yes | Expiry timestamp in milliseconds. |
| `ttl` | Number | Yes | DynamoDB TTL attribute in epoch seconds. |
| `updatedAt` | String | Yes | Last update timestamp. |

## Database Relationship Diagram

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

    USER_PROFILES {
        string userId PK
        string role
        string pushRule
        boolean alertSoundEnabled
        string notificationEmail
    }

    AUTH_USERS {
        string username PK
        string name
        string passwordHash
        string email
        string role
    }

    ADMINS {
        string adminId PK
        string name
        string email
        string role
        string status
    }

    SETTINGS {
        string settingId PK
        string type
        string location
        string zone
        string silencedUntil
    }

    VERIFICATION_CODES {
        string email PK
        string code
        string name
        number expiresAtMs
        number ttl
    }

    ALERTS ||--o| WORK_ORDERS : "creates"
    AUTH_USERS ||--o| USER_PROFILES : "profile"
    USER_PROFILES ||--o{ PUSH_TOKENS : "registers"
    ADMINS ||--o{ ALERTS : "email recipients"
```

## Confirmed Database Limitations

| Limitation | Impact |
|---|---|
| Alerts and work orders are listed using `ScanCommand` | Acceptable for prototype scale but may not scale efficiently for large datasets. |
| No Global Secondary Indexes were found | Querying by status, severity, alert ID substring, email uniqueness, or created time is performed in application code. |
| Thresholds are fixed in Lambda code | Dynamic threshold configuration is not stored in DynamoDB in the inspected backend. |
| No device table was found | Device inventory/registration is `[Not implemented]`; location is stored as a setting only. |
| No humidity table/attribute flow was found | Humidity is read in firmware but not stored as a cloud metric. |
