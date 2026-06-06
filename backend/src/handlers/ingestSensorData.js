"use strict";

const {
  DeleteCommand,
  GetCommand,
  PutCommand,
  QueryCommand,
  UpdateCommand,
} = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { sendNotificationToAll } = require("../common/fcm");
const { sendAlertEmail } = require("../common/emailNotifier");
const { ok, badRequest, serverError } = require("../common/response");
const { loadThresholdConfig } = require("../common/thresholds");
const { publishHeartbeat, touchLastSeen } = require("../common/heartbeat");
const { ALERT_STATUS } = require("../common/alertStatus");
const {
  buildActiveCorrelationSettingId,
  buildCorrelationKey,
  incidentTitleForSensor,
  normalizeIncidentRecord,
} = require("../common/incidents");

const EMAIL_COOLDOWN_SECONDS = Number(process.env.EMAIL_COOLDOWN_SECONDS || 60);
const CORRELATION_STATUS_INDEX_NAME = process.env.INCIDENT_CORRELATION_STATUS_INDEX_NAME || "CorrelationStatusIndex";

exports.handler = async (event) => {
  try {
    const payload = parsePayload(event);
    const sensorType = payload.sensorType;
    const value = Number(payload.value);
    const zone = payload.zone || "Unknown Zone";
    const capturedAt = payload.capturedAt || new Date().toISOString();
    const deviceId = payload.deviceId || deviceIdFromSensorType(sensorType);

    if (!sensorType || Number.isNaN(value)) {
      return badRequest("Missing sensorType or numeric value");
    }

    const thresholds = await loadThresholdConfig();

    await docClient.send(
      new PutCommand({
        TableName: tables.sensor,
        Item: {
          sensorType,
          capturedAt,
          value,
          zone,
        },
      })
    );

    const [lastSeenResult, heartbeatResult] = await Promise.all([
      touchLastSeen({ sensorType, zone, capturedAt }),
      publishHeartbeat({
        sensorType,
        zone,
        capturedAt,
        source: inferTransport(event),
      }).catch((error) => {
        console.error("heartbeat publish failed", error);
        return { published: false, reason: "Heartbeat publish failed" };
      }),
    ]);

    const threshold = thresholds[sensorType];
    if (!threshold) {
      return ok({
        stored: true,
        incidentCreated: false,
        message: "Sensor stored without threshold profile",
        heartbeat: heartbeatResult,
        lastSeen: lastSeenResult,
      });
    }

    let severity = "NORMAL";
    if (value >= threshold.critical) severity = "CRITICAL";
    else if (value >= threshold.warning) severity = "WARNING";

    if (severity === "NORMAL") {
      return ok({
        stored: true,
        incidentCreated: false,
        severity,
        heartbeat: heartbeatResult,
        lastSeen: lastSeenResult,
      });
    }

    const measuredValue = `${value}${threshold.unit}`;
    const correlationKey = buildCorrelationKey({ deviceId, zone, sensorType });

    let incident = null;
    let createdNewIncident = false;

    const activeIncident = await findActiveIncidentByCorrelationKey(correlationKey);
    if (!activeIncident) {
      const createResult = await createIncidentOrReuseActive({
        correlationKey,
        sensorType,
        deviceId,
        zone,
        severity,
        capturedAt,
        measuredValue,
      });
      createdNewIncident = createResult.created;
      if (createdNewIncident) {
        incident = normalizeIncidentRecord(createResult.incident);
      } else {
        incident = await incrementExistingIncident({
          incident: createResult.incident,
          severity,
          measuredValue,
          capturedAt,
        });
      }
    }
    if (!incident) {
      incident = await incrementExistingIncident({
        incident: activeIncident,
        severity,
        measuredValue,
        capturedAt,
      });
    }

    const sensorEvent = await writeSensorEvent({
      incident,
      sensorType,
      deviceId,
      zone,
      severity,
      measuredValue,
      value,
      threshold,
      capturedAt,
      ingestTransport: inferTransport(event),
    });

    let pushResult = null;
    let emailResult = null;
    if (createdNewIncident) {
      pushResult = await notifyNewIncident({
        incident,
        sensorType,
        zone,
        severity,
        measuredValue,
      });
    }
    emailResult = await emailAlertWithCooldown({
      incident,
      sensorType,
      zone,
      severity,
      value,
      unit: threshold.unit,
      threshold,
      capturedAt,
    });

    return ok({
      stored: true,
      incidentCreated: createdNewIncident,
      incident,
      sensorEvent,
      pushResult,
      emailResult,
      ingestTransport: inferTransport(event),
      heartbeat: heartbeatResult,
      lastSeen: lastSeenResult,
      thresholdsSource: "configurable",
    });
  } catch (error) {
    console.error("ingestSensorData error", error);
    return serverError("Failed to ingest sensor data");
  }
};

function parsePayload(event) {
  if (typeof event?.body === "string" && event.body.trim().length > 0) {
    const parsed = JSON.parse(event.body);
    if (parsed && typeof parsed === "object") return parsed;
  }

  if (event?.body && typeof event.body === "object") {
    return event.body;
  }

  if (event?.state?.reported && typeof event.state.reported === "object") {
    return event.state.reported;
  }

  if (event?.payload && typeof event.payload === "object") {
    return event.payload;
  }

  if (event && typeof event === "object") {
    return event;
  }

  return {};
}

function inferTransport(event) {
  if (event?.requestContext?.http || event?.requestContext?.resourcePath) return "HTTP";
  return "MQTT";
}

async function findActiveIncidentByCorrelationKey(correlationKey) {
  const result = await docClient.send(
    new QueryCommand({
      TableName: tables.incident,
      IndexName: CORRELATION_STATUS_INDEX_NAME,
      KeyConditionExpression: "correlationKey = :correlationKey AND begins_with(statusUpdatedAt, :activePrefix)",
      ExpressionAttributeValues: {
        ":correlationKey": correlationKey,
        ":activePrefix": `${ALERT_STATUS.ACTIVE}#`,
      },
      ScanIndexForward: false,
      Limit: 1,
    })
  );

  const record = result.Items?.[0];
  return record ? normalizeIncidentRecord(record) : null;
}

async function createIncidentOrReuseActive({
  correlationKey,
  sensorType,
  deviceId,
  zone,
  severity,
  capturedAt,
  measuredValue,
}) {
  const incidentId = makeIncidentId();
  const settingId = buildActiveCorrelationSettingId(correlationKey);

  const lockAcquired = await tryAcquireActiveIncidentLock({
    settingId,
    correlationKey,
    incidentId,
    sensorType,
    deviceId,
    zone,
    capturedAt,
  });

  if (!lockAcquired.acquired) {
    const existingFromLock = await findIncidentById(lockAcquired.incidentId);
    if (existingFromLock && existingFromLock.status === ALERT_STATUS.ACTIVE) {
      return { created: false, incident: existingFromLock };
    }

    const existingFromIndex = await findActiveIncidentByCorrelationKey(correlationKey);
    if (existingFromIndex) {
      return { created: false, incident: existingFromIndex };
    }

    await docClient.send(
      new PutCommand({
        TableName: tables.settings,
        Item: {
          settingId,
          type: "incidentActivePointer",
          correlationKey,
          incidentId,
          sensorType,
          deviceId,
          zone,
          lastSeenAt: capturedAt,
          updatedAt: new Date().toISOString(),
        },
      })
    );
  }

  const incident = {
    incidentId,
    correlationKey,
    deviceId,
    zone,
    sensorType,
    severity,
    status: ALERT_STATUS.ACTIVE,
    title: incidentTitleForSensor(sensorType),
    latestMeasuredValue: measuredValue,
    latestEventAt: capturedAt,
    eventCount: 1,
    createdAt: capturedAt,
    startedAt: capturedAt,
    updatedAt: capturedAt,
    lastUpdatedAt: capturedAt,
    statusUpdatedAt: `${ALERT_STATUS.ACTIVE}#${capturedAt}`,
    acknowledgedAt: null,
    resolvedAt: null,
  };

  try {
    await docClient.send(
      new PutCommand({
        TableName: tables.incident,
        Item: incident,
        ConditionExpression: "attribute_not_exists(incidentId)",
      })
    );
  } catch (error) {
    await safeReleaseIncidentLock(settingId);
    throw error;
  }

  return { created: true, incident: normalizeIncidentRecord(incident) };
}

async function tryAcquireActiveIncidentLock({
  settingId,
  correlationKey,
  incidentId,
  sensorType,
  deviceId,
  zone,
  capturedAt,
}) {
  try {
    await docClient.send(
      new PutCommand({
        TableName: tables.settings,
        Item: {
          settingId,
          type: "incidentActivePointer",
          correlationKey,
          incidentId,
          sensorType,
          deviceId,
          zone,
          lastSeenAt: capturedAt,
          updatedAt: new Date().toISOString(),
        },
        ConditionExpression: "attribute_not_exists(settingId)",
      })
    );
    return { acquired: true, incidentId };
  } catch (error) {
    if (error?.name !== "ConditionalCheckFailedException") {
      throw error;
    }
  }

  const existingLock = await docClient.send(
    new GetCommand({
      TableName: tables.settings,
      Key: { settingId },
    })
  );

  return {
    acquired: false,
    incidentId: existingLock.Item?.incidentId || null,
  };
}

async function incrementExistingIncident({ incident, severity, measuredValue, capturedAt }) {
  const normalized = normalizeIncidentRecord(incident);
  const nextSeverity = mergeSeverity(normalized.severity, severity);

  const result = await docClient.send(
    new UpdateCommand({
      TableName: tables.incident,
      Key: { incidentId: normalized.incidentId },
      UpdateExpression:
        "SET latestMeasuredValue = :latestMeasuredValue, latestEventAt = :latestEventAt, updatedAt = :updatedAt, lastUpdatedAt = :lastUpdatedAt, #severity = :severity, statusUpdatedAt = :statusUpdatedAt ADD eventCount :eventIncrement",
      ExpressionAttributeNames: {
        "#severity": "severity",
      },
      ExpressionAttributeValues: {
        ":latestMeasuredValue": measuredValue,
        ":latestEventAt": capturedAt,
        ":updatedAt": capturedAt,
        ":lastUpdatedAt": capturedAt,
        ":severity": nextSeverity,
        ":statusUpdatedAt": `${ALERT_STATUS.ACTIVE}#${capturedAt}`,
        ":eventIncrement": 1,
      },
      ReturnValues: "ALL_NEW",
    })
  );

  return normalizeIncidentRecord(result.Attributes || {});
}

async function writeSensorEvent({
  incident,
  sensorType,
  deviceId,
  zone,
  severity,
  measuredValue,
  value,
  threshold,
  capturedAt,
  ingestTransport,
}) {
  const eventId = makeSensorEventId();
  const eventAt = `${capturedAt}#${eventId}`;
  const item = {
    incidentId: incident.incidentId,
    eventAt,
    eventId,
    capturedAt,
    receivedAt: new Date().toISOString(),
    sensorType,
    deviceId,
    zone,
    severity,
    measuredValue,
    value,
    thresholdWarning: threshold.warning,
    thresholdCritical: threshold.critical,
    unit: threshold.unit,
    ingestTransport,
  };

  await docClient.send(
    new PutCommand({
      TableName: tables.sensorEvent,
      Item: item,
    })
  );

  return item;
}

async function notifyNewIncident({ incident, sensorType, zone, severity, measuredValue }) {
  try {
    return await sendNotificationToAll({
      title: `Alertrix ${severity} Incident`,
      body: `${sensorType} at ${zone} reached ${measuredValue}`,
      data: {
        incidentId: incident.incidentId,
        sensorType,
        severity,
      },
    });
  } catch (error) {
    console.error("FCM push failed", error);
    return { successCount: 0, failureCount: 0, reason: "FCM push failed" };
  }
}

async function emailAlertWithCooldown({ incident, sensorType, zone, severity, value, unit, threshold, capturedAt }) {
  const emailGate = await shouldSendEmailNow({ zone, severity, capturedAt });
  if (!emailGate.allowed) {
    return {
      delivered: false,
      suppressed: true,
      reason: "Email cooldown active",
      nextSendAt: emailGate.nextSendAt,
    };
  }

  try {
    return await sendAlertEmail({
      alertId: incident.incidentId,
      sensorType,
      severity,
      zone,
      value,
      unit,
      threshold: thresholdValueForSeverity(threshold, severity),
      capturedAt,
    });
  } catch (error) {
    console.error("Alert email failed", error);
    return { delivered: false, reason: "Email publish failed" };
  }
}

function thresholdValueForSeverity(threshold, severity) {
  if (!threshold || typeof threshold !== "object") return null;
  const level = String(severity || "").trim().toUpperCase();
  if (level === "CRITICAL") return threshold.critical;
  if (level === "WARNING") return threshold.warning;
  return null;
}

async function shouldSendEmailNow({ zone, severity, capturedAt }) {
  if (EMAIL_COOLDOWN_SECONDS <= 0) {
    return { allowed: true };
  }

  const nowMs = Date.parse(capturedAt) || Date.now();
  const key = buildEmailCooldownKey(zone, severity);

  const existing = await docClient.send(
    new GetCommand({
      TableName: tables.settings,
      Key: { settingId: key },
    })
  );

  const lastSentAt = existing.Item?.lastSentAt;
  if (lastSentAt) {
    const lastMs = Date.parse(lastSentAt);
    const waitMs = EMAIL_COOLDOWN_SECONDS * 1000 - (nowMs - lastMs);
    if (!Number.isNaN(lastMs) && waitMs > 0) {
      return {
        allowed: false,
        nextSendAt: new Date(nowMs + waitMs).toISOString(),
      };
    }
  }

  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: {
        settingId: key,
        type: "emailCooldown",
        zone,
        severity,
        lastSentAt: new Date(nowMs).toISOString(),
        updatedAt: new Date().toISOString(),
      },
    })
  );

  return { allowed: true };
}

function buildEmailCooldownKey(zone, severity) {
  const z = String(zone || "Unknown Zone").trim();
  const lv = String(severity || "UNKNOWN").trim().toUpperCase();
  return `EMAIL_COOLDOWN#${z}#${lv}`;
}

function mergeSeverity(currentSeverity, nextSeverity) {
  const rank = {
    CRITICAL: 3,
    WARNING: 2,
    NORMAL: 1,
  };
  const current = String(currentSeverity || "NORMAL").trim().toUpperCase();
  const next = String(nextSeverity || "NORMAL").trim().toUpperCase();
  return (rank[next] || 1) >= (rank[current] || 1) ? next : current;
}

async function findIncidentById(incidentId) {
  if (!incidentId) return null;
  const result = await docClient.send(
    new GetCommand({
      TableName: tables.incident,
      Key: { incidentId },
    })
  );
  return result.Item ? normalizeIncidentRecord(result.Item) : null;
}

async function safeReleaseIncidentLock(settingId) {
  try {
    await docClient.send(
      new DeleteCommand({
        TableName: tables.settings,
        Key: { settingId },
      })
    );
  } catch (error) {
    console.error("safeReleaseIncidentLock failed", error);
  }
}

function makeIncidentId() {
  return `INC-${Date.now()}-${Math.random().toString(36).slice(2, 8).toUpperCase()}`;
}

function makeSensorEventId() {
  return `SE-${Date.now()}-${Math.random().toString(36).slice(2, 7).toUpperCase()}`;
}

function deviceIdFromSensorType(sensorType) {
  switch (String(sensorType || "").trim()) {
    case "waterLevel":
      return "WL-01";
    case "vibration":
      return "VB-01";
    case "temperature":
      return "TP-01";
    default:
      return "ESP32-01";
  }
}
