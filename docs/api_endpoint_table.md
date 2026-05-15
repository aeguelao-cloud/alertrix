# Alertrix API Endpoint Table

This table lists the implemented API Gateway routes found in `backend/template.yaml` and their behavior in the corresponding Lambda handlers. Authentication is described according to the inspected backend code; no API Gateway authorizer or JWT middleware was found.

## Endpoint Summary

| Method | Route | Request body / query | Response body | Authentication / authorization | Purpose |
|---|---|---|---|---|---|
| POST | `/api/auth/send-code` | Body: `name`, `email`, optional `purpose` (`register` or `reset`) | `message`, `emailResult` or `error` | Public endpoint; validates email and account existence rules | Sends a 6-digit email verification code and stores it in DynamoDB with TTL. |
| POST | `/api/auth/register` | Body: `name`, `email`, `password`, `code` | `message` or `error` | Public endpoint; requires valid verification code | Creates auth user and user profile records. |
| POST | `/api/auth/login` | Body: `email` or `login`, `password` | `user.username`, `user.role` or `error` | Public endpoint; validates password hash against DynamoDB | Authenticates user and resolves Admin role if email matches active admin/internal admin rule. |
| POST | `/api/auth/reset-password` | Body: `email`, `code`, `password` | `message` or `error` | Public endpoint; requires valid verification code | Updates password hash and removes verification record. |
| GET | `/api/readings/latest` | Optional cache-busting query ignored by backend | `siteName`, `updatedAt`, `readings[]` | No backend authorization check | Returns latest live readings for water level, vibration, and temperature. |
| GET | `/api/app/bootstrap` | Headers optionally: `X-User-Role`, `X-User-Id` | Navigation, overview, incident queue, settings, optional admin/work-order blocks | Role is read from header; no token validation | Aggregates dashboard bootstrap data. |
| GET | `/api/trends` | Query: `metric`, `range` | `metric`, `range`, `points[]`, `series[]` | No backend authorization check | Returns trend series for `waterLevel`, `vibration`, or `temperature`. |
| GET | `/api/alerts` | Query: optional `severity`, `status` | `items[]` | No backend authorization check | Lists alert records sorted by detected time. |
| GET | `/api/work-orders` | Query: optional `status`, `alertId`, `limit` | `items[]` | No backend authorization check | Lists work orders with optional filtering. |
| POST | `/api/alerts/{alertId}/status` | Body: `status`, optional `actorRole` | `item` or `error` | Body `actorRole` controls ignore permission; `IGNORED` requires `Admin` | Updates alert status to `OPEN`, `CONFIRMED`, `IGNORED`, or `WORK_ORDER_CREATED`. |
| POST | `/api/alerts/{alertId}/work-orders` | Body: optional `actorRole`, `assignee`, `note` | `item` work order or `error` | Body `actorRole` must be `Admin` | Creates a work order for an existing alert and updates the alert status. |
| POST | `/api/push/register-token` | Body: `token`, optional `userId`, `platform` | `message`, `token`, `userId`, `platform`, `updatedAt` | No backend authorization check | Stores an FCM token for push notification delivery. |
| POST | `/api/push/test-alert` | No body required | `message`, `result` or `error` | No backend authorization check | Sends a test FCM notification to registered tokens. |
| GET | `/api/device/buzzer/state` | Query: optional `zone` | `zone`, `silenced`, `silencedUntil`, `remainingSeconds`, `updatedAt` | No backend authorization check | Returns whether a zone buzzer is currently silenced. |
| POST | `/api/device/buzzer/silence` | Body: optional `zone`, `actorRole`, `requestedBy`, `durationSeconds` | `message`, buzzer state fields | `actorRole` must be `Admin` or `User`; no token validation | Stores temporary buzzer silence state. |
| GET | `/api/settings/notifications` | Headers optionally: `X-User-Id`, `X-User-Role` | User notification settings | Header-based identity only; no token validation | Reads per-user notification preference and email subscription state. |
| POST | `/api/settings/notifications` | Body: `pushRule`, `alertSoundEnabled`, and/or `notificationEmail`; headers optionally identify user | Saved settings and subscription status | Header/body-based identity only; no token validation | Updates notification preferences and optionally subscribes email to SNS topics. |
| GET | `/api/settings/device-location` | No body | `location` | No backend authorization check | Reads configured device/site location. |
| POST | `/api/settings/device-location` | Body: `location` | `location` or `error` | No backend authorization check | Saves configured device/site location. |
| GET | `/api/admins` | Headers: `X-User-Role: Admin`, `X-User-Id` | `items[]` | Requires Admin role header | Lists admin records. |
| POST | `/api/admins` | Headers: `X-User-Role: Admin`, `X-User-Id`; body: `name`, `email`, optional `role`, `status` | `item` or `error` | Requires Admin role and internal super admin ID | Creates an admin record. |
| POST | `/api/admins/{adminId}` | Headers: `X-User-Role: Admin`, `X-User-Id`; body may include `name`, `email`, `role`, `status` | `item` or `error` | Requires Admin role and internal super admin ID | Updates an admin record. |
| DELETE | `/api/admins/{adminId}` | Headers: `X-User-Role: Admin`, `X-User-Id` | `deleted`, `adminId` or `error` | Requires Admin role and internal super admin ID | Deletes an admin record. |
| POST | `/api/admins/{adminId}/status` | Headers: `X-User-Role: Admin`, `X-User-Id`; body: `status` (`active` or `inactive`) | `item` or `error` | Requires Admin role header | Updates admin active/inactive status. |
| POST | `/api/sensors/ingest` | Body/event: `sensorType`, `value`, optional `zone`, `capturedAt` | `stored`, `alertGenerated`, optional `alert`, `pushResult`, `emailResult`, `ingestTransport` | No backend authorization check for HTTP route; AWS IoT Rule invokes Lambda for MQTT path | Stores telemetry and generates warning/critical alerts based on fixed thresholds. |

## Request and Response Notes

### `/api/sensors/ingest`

Accepted sensor types with threshold profiles:

| Sensor type | Warning | Critical | Unit |
|---|---:|---:|---|
| `waterLevel` | 70 | 85 | `%` |
| `vibration` | 2.8 | 4.0 | `mm/s RMS` |
| `temperature` | 35 | 40 | `degC` |

If `sensorType` is not in the threshold profile, the reading is stored and no alert is generated.

Example request:

```json
{
  "sensorType": "waterLevel",
  "value": 90,
  "zone": "Zone A - Pump Station",
  "capturedAt": "2026-05-11T12:00:00.000Z"
}
```

Example success response shape:

```json
{
  "stored": true,
  "alertGenerated": true,
  "alert": {
    "alertId": "ALERT-...",
    "title": "waterLevel threshold exceeded",
    "severity": "CRITICAL",
    "status": "ACTIVE",
    "detectedAt": "2026-05-11T12:00:00.000Z",
    "zone": "Zone A - Pump Station",
    "triggerValue": "90%"
  },
  "pushResult": {
    "successCount": 0,
    "failureCount": 0
  },
  "emailResult": {
    "delivered": false
  },
  "ingestTransport": "HTTP"
}
```

### Alert Status Values

The backend allows the following status values:

| Status | Meaning |
|---|---|
| `OPEN` | Alert is open. |
| `CONFIRMED` | Alert has been acknowledged/confirmed. |
| `IGNORED` | Alert has been ignored; backend requires actor role `Admin`. |
| `WORK_ORDER_CREATED` | A work order has been created from the alert. |

### Authentication Caveat

The code implements role checks using request body fields and HTTP headers. No JWT, cookie session, API Gateway authorizer, Cognito authorizer, or Firebase Auth token verification was found in the inspected backend code. Therefore, security claims in the final report should describe this as application-level role gating, not full production-grade authenticated API protection.
