"use strict";

const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  PutCommand,
  ScanCommand,
} = require("@aws-sdk/lib-dynamodb");
const { normalizeAlertRecord } = require("../src/common/alertStatus");
const {
  buildCorrelationKey,
  incidentTitleForSensor,
} = require("../src/common/incidents");

const args = parseArgs(process.argv.slice(2));
const dryRun = args["dry-run"] === "true" || args["dry-run"] === true;
const overwrite = args.overwrite === "true" || args.overwrite === true;
const pageLimit = parsePositiveInt(args.limit, 200);

const alertTableName =
  args["alert-table"] ||
  process.env.ALERT_TABLE_NAME ||
  process.env.LEGACY_ALERT_TABLE_NAME;
const incidentTableName =
  args["incident-table"] || process.env.INCIDENT_TABLE_NAME;
const sensorEventTableName =
  args["sensor-event-table"] || process.env.SENSOR_EVENT_TABLE_NAME;

if (!alertTableName || !incidentTableName || !sensorEventTableName) {
  console.error(
    "Missing table names. Provide --alert-table, --incident-table, --sensor-event-table or matching env vars."
  );
  process.exit(1);
}

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

async function main() {
  console.log("Starting migration alerts -> incidents/events");
  console.log(
    JSON.stringify(
      {
        dryRun,
        overwrite,
        pageLimit,
        alertTableName,
        incidentTableName,
        sensorEventTableName,
      },
      null,
      2
    )
  );

  let scannedAlerts = 0;
  let skippedInvalid = 0;
  let insertedIncidents = 0;
  let insertedEvents = 0;
  let duplicateIncidents = 0;
  let duplicateEvents = 0;

  const incidentMap = new Map();
  let lastEvaluatedKey = undefined;
  do {
    const scan = await docClient.send(
      new ScanCommand({
        TableName: alertTableName,
        Limit: pageLimit,
        ExclusiveStartKey: lastEvaluatedKey,
      })
    );
    lastEvaluatedKey = scan.LastEvaluatedKey;

    for (const raw of scan.Items || []) {
      scannedAlerts += 1;
      const alert = normalizeAlertRecord(raw);
      const materialized = materializeLegacyAlert(alert);
      if (!materialized) {
        skippedInvalid += 1;
        continue;
      }

      const existing = incidentMap.get(materialized.incident.incidentId);
      if (!existing) {
        incidentMap.set(materialized.incident.incidentId, {
          incident: materialized.incident,
          events: [materialized.event],
        });
      } else {
        mergeIncident(existing.incident, materialized.incident);
        existing.events.push(materialized.event);
      }
    }

    console.log(
      `Scanned ${scannedAlerts} legacy alerts... incidents aggregated=${incidentMap.size}`
    );
  } while (lastEvaluatedKey);

  const incidentEntries = Array.from(incidentMap.values());
  for (const { incident, events } of incidentEntries) {
    if (!dryRun) {
      try {
        await docClient.send(
          new PutCommand({
            TableName: incidentTableName,
            Item: incident,
            ...(overwrite
              ? {}
              : { ConditionExpression: "attribute_not_exists(incidentId)" }),
          })
        );
        insertedIncidents += 1;
      } catch (error) {
        if (isConditionalFailure(error)) {
          duplicateIncidents += 1;
        } else {
          throw error;
        }
      }

      for (const event of events) {
        try {
          await docClient.send(
            new PutCommand({
              TableName: sensorEventTableName,
              Item: event,
              ...(overwrite
                ? {}
                : {
                    ConditionExpression:
                      "attribute_not_exists(incidentId) AND attribute_not_exists(eventAt)",
                  }),
            })
          );
          insertedEvents += 1;
        } catch (error) {
          if (isConditionalFailure(error)) {
            duplicateEvents += 1;
          } else {
            throw error;
          }
        }
      }
    } else {
      insertedIncidents += 1;
      insertedEvents += events.length;
    }
  }

  console.log("Migration summary");
  console.log(
    JSON.stringify(
      {
        dryRun,
        scannedAlerts,
        skippedInvalid,
        incidentCount: incidentEntries.length,
        insertedIncidents,
        duplicateIncidents,
        insertedEvents,
        duplicateEvents,
      },
      null,
      2
    )
  );
}

function materializeLegacyAlert(alert) {
  const incidentId = String(alert.incidentId || alert.alertId || "").trim();
  if (!incidentId) return null;

  const capturedAt = pickBestTime(alert);
  if (!capturedAt) return null;

  const sensorType = inferSensorType(alert);
  const deviceId = String(alert.deviceId || deviceIdFromSensorType(sensorType)).trim();
  const zone = String(alert.zone || "Unknown Zone").trim();
  const correlationKey = buildCorrelationKey({ deviceId, zone, sensorType });
  const status = String(alert.status || "ACTIVE").toUpperCase();
  const severity = String(alert.severity || "WARNING").toUpperCase();
  const measuredValue = String(
    alert.latestMeasuredValue || alert.triggerValue || ""
  ).trim() || null;
  const createdAt = toIso(alert.createdAt || alert.detectedAt || capturedAt);
  const updatedAt = toIso(
    alert.updatedAt || alert.detectedAt || alert.createdAt || capturedAt
  );

  const incident = {
    incidentId,
    correlationKey,
    deviceId,
    zone,
    sensorType,
    title: alert.title || incidentTitleForSensor(sensorType),
    severity,
    status,
    latestMeasuredValue: measuredValue,
    latestEventAt: capturedAt,
    eventCount: 1,
    createdAt,
    startedAt: createdAt,
    updatedAt,
    lastUpdatedAt: updatedAt,
    statusUpdatedAt: `${status}#${updatedAt}`,
    acknowledgedAt: toIso(alert.acknowledgedAt),
    resolvedAt: toIso(alert.resolvedAt),
  };

  const baseEventId = `MIG-${incidentId}-${String(alert.alertId || incidentId)}`;
  const event = {
    incidentId,
    eventAt: `${capturedAt}#${baseEventId}`,
    eventId: baseEventId,
    capturedAt,
    receivedAt: new Date().toISOString(),
    sensorType,
    deviceId,
    zone,
    severity,
    measuredValue,
    value: parseNumericValue(measuredValue),
    unit: inferUnit(measuredValue),
    ingestTransport: "MIGRATION",
  };

  return { incident, event };
}

function mergeIncident(target, candidate) {
  target.eventCount = toNumber(target.eventCount, 1) + 1;

  if (compareIso(candidate.createdAt, target.createdAt) < 0) {
    target.createdAt = candidate.createdAt;
    target.startedAt = candidate.startedAt || candidate.createdAt;
  }

  if (compareIso(candidate.latestEventAt, target.latestEventAt) > 0) {
    target.latestEventAt = candidate.latestEventAt;
    target.latestMeasuredValue =
      candidate.latestMeasuredValue || target.latestMeasuredValue;
    target.updatedAt = candidate.updatedAt || target.updatedAt;
    target.lastUpdatedAt = candidate.lastUpdatedAt || target.lastUpdatedAt;
    target.status = candidate.status || target.status;
    target.statusUpdatedAt =
      candidate.statusUpdatedAt || `${target.status}#${target.updatedAt}`;
  }

  target.severity = strongerSeverity(target.severity, candidate.severity);
  if (!target.acknowledgedAt && candidate.acknowledgedAt) {
    target.acknowledgedAt = candidate.acknowledgedAt;
  }
  if (!target.resolvedAt && candidate.resolvedAt) {
    target.resolvedAt = candidate.resolvedAt;
  }
}

function inferSensorType(alert) {
  const raw = String(alert.sensorType || "").trim();
  if (raw) return raw;
  const title = String(alert.title || "").toLowerCase();
  if (title.includes("water")) return "waterLevel";
  if (title.includes("vibration")) return "vibration";
  if (title.includes("temp")) return "temperature";
  return "unknown";
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

function parseNumericValue(text) {
  if (!text) return null;
  const matched = /[-+]?\d*\.?\d+/.exec(String(text));
  if (!matched) return null;
  const parsed = Number.parseFloat(matched[0]);
  return Number.isFinite(parsed) ? parsed : null;
}

function inferUnit(text) {
  if (!text) return null;
  const raw = String(text).toLowerCase();
  if (raw.includes("mm/s")) return "mm/s RMS";
  if (raw.includes("deg c") || raw.includes("°c")) return "deg C";
  if (raw.includes("%")) return "%";
  return null;
}

function strongerSeverity(left, right) {
  const rank = { CRITICAL: 3, WARNING: 2, NORMAL: 1 };
  const l = String(left || "NORMAL").toUpperCase();
  const r = String(right || "NORMAL").toUpperCase();
  return (rank[r] || 1) > (rank[l] || 1) ? r : l;
}

function pickBestTime(alert) {
  return (
    toIso(alert.detectedAt) ||
    toIso(alert.createdAt) ||
    toIso(alert.updatedAt) ||
    null
  );
}

function toIso(value) {
  if (!value) return null;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return null;
  return dt.toISOString();
}

function compareIso(left, right) {
  const l = Date.parse(left || "");
  const r = Date.parse(right || "");
  if (Number.isNaN(l) && Number.isNaN(r)) return 0;
  if (Number.isNaN(l)) return -1;
  if (Number.isNaN(r)) return 1;
  return l === r ? 0 : l < r ? -1 : 1;
}

function toNumber(value, fallback) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const parsed = Number.parseInt(String(value || ""), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseArgs(argv) {
  const output = {};
  for (let i = 0; i < argv.length; i += 1) {
    const current = argv[i];
    if (!current.startsWith("--")) continue;
    const key = current.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      output[key] = true;
      continue;
    }
    output[key] = next;
    i += 1;
  }
  return output;
}

function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value || ""), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return parsed;
}

function isConditionalFailure(error) {
  return error?.name === "ConditionalCheckFailedException";
}

main().catch((error) => {
  console.error("Migration failed", error);
  process.exit(1);
});
