"use strict";

const { DeleteCommand, GetCommand, QueryCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("./dynamo");
const { ALERT_STATUS, normalizeAlertStatus } = require("./alertStatus");
const {
  buildActiveCorrelationSettingId,
  buildCorrelationKey,
  normalizeIncidentRecord,
} = require("./incidents");

const STATUS_UPDATED_AT_INDEX_NAME =
  process.env.INCIDENT_STATUS_UPDATED_AT_INDEX_NAME || "StatusUpdatedAtIndex";

async function fetchIncidentById(incidentId) {
  const result = await docClient.send(
    new GetCommand({
      TableName: tables.incident,
      Key: { incidentId },
    })
  );
  return result.Item ? normalizeIncidentRecord(result.Item) : null;
}

async function queryIncidentsByStatus(
  status,
  { limit = 200, startKey = null, beforeTime = null, inclusiveBefore = true } = {}
) {
  const canonicalStatus = normalizeAlertStatus(status, ALERT_STATUS.ACTIVE);
  const safeLimit = Math.max(
    1,
    Math.min(Number.parseInt(String(limit || 200), 10) || 200, 1000)
  );

  const expressionAttributeNames = { "#status": "status" };
  const expressionAttributeValues = { ":status": canonicalStatus };
  let keyConditionExpression = "#status = :status";

  if (beforeTime) {
    expressionAttributeNames["#statusUpdatedAt"] = "statusUpdatedAt";
    expressionAttributeValues[":beforeStatusUpdatedAt"] = `${canonicalStatus}#${String(beforeTime)}`;
    keyConditionExpression = inclusiveBefore
      ? `${keyConditionExpression} AND #statusUpdatedAt <= :beforeStatusUpdatedAt`
      : `${keyConditionExpression} AND #statusUpdatedAt < :beforeStatusUpdatedAt`;
  }

  const result = await docClient.send(
    new QueryCommand({
      TableName: tables.incident,
      IndexName: STATUS_UPDATED_AT_INDEX_NAME,
      KeyConditionExpression: keyConditionExpression,
      ExpressionAttributeNames: expressionAttributeNames,
      ExpressionAttributeValues: expressionAttributeValues,
      ScanIndexForward: false,
      Limit: safeLimit,
      ExclusiveStartKey: startKey || undefined,
    })
  );

  return {
    items: (result.Items || []).map((item) => normalizeIncidentRecord(item)),
    lastEvaluatedKey: result.LastEvaluatedKey || null,
  };
}

function sortIncidentsByLatestDesc(left, right) {
  const l = incidentSortTime(left);
  const r = incidentSortTime(right);
  if (l !== r) return l < r ? 1 : -1;

  const leftId = String(left.incidentId || "");
  const rightId = String(right.incidentId || "");
  if (leftId === rightId) return 0;
  return leftId < rightId ? 1 : -1;
}

function incidentSortTime(incident) {
  return String(
    incident.lastUpdatedAt || incident.updatedAt || incident.createdAt || ""
  );
}

function encodeIncidentCursor(payload) {
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
}

function decodeIncidentCursor(cursor) {
  if (!cursor || typeof cursor !== "string") return null;
  try {
    const decoded = Buffer.from(cursor, "base64").toString("utf8");
    const parsed = JSON.parse(decoded);
    if (!parsed || typeof parsed !== "object") return null;
    const beforeTime = String(parsed.beforeTime || "").trim();
    const excludeIncidentIdsAtBoundary = Array.isArray(parsed.excludeIncidentIdsAtBoundary)
      ? parsed.excludeIncidentIdsAtBoundary
          .map((value) => String(value || "").trim())
          .filter(Boolean)
      : [];
    if (!beforeTime) return null;
    return { beforeTime, excludeIncidentIdsAtBoundary };
  } catch (_) {
    return null;
  }
}

async function listIncidentsByStatusesPage(
  statuses,
  { limit = 100, cursor = null, scanFactor = 3, maxScanPerStatus = 600 } = {}
) {
  const safeLimit = Math.max(1, Math.min(Number.parseInt(String(limit || 100), 10) || 100, 1000));
  const uniqueStatuses = Array.from(
    new Set(
      (statuses || [])
        .map((status) => normalizeAlertStatus(status, ALERT_STATUS.ACTIVE))
        .filter(Boolean)
    )
  );
  if (uniqueStatuses.length === 0) {
    return { items: [], nextCursor: null };
  }

  const decodedCursor = decodeIncidentCursor(cursor);
  const beforeTime = decodedCursor?.beforeTime || null;
  const excludedBoundaryIds = new Set(decodedCursor?.excludeIncidentIdsAtBoundary || []);
  const perStatusLimit = Math.max(
    safeLimit,
    Math.min(maxScanPerStatus, safeLimit * Math.max(1, scanFactor))
  );

  const statusResults = await Promise.all(
    uniqueStatuses.map((status) =>
      queryIncidentsByStatus(status, {
        limit: perStatusLimit,
        beforeTime,
        inclusiveBefore: true,
      })
    )
  );

  let merged = [];
  for (const result of statusResults) {
    merged.push(...result.items);
  }

  if (beforeTime) {
    merged = merged.filter((incident) => {
      const time = incidentSortTime(incident);
      if (!time) return false;
      if (time < beforeTime) return true;
      if (time > beforeTime) return false;
      return !excludedBoundaryIds.has(String(incident.incidentId || ""));
    });
  }

  merged.sort(sortIncidentsByLatestDesc);
  const items = merged.slice(0, safeLimit);

  if (items.length === 0) {
    return { items, nextCursor: null };
  }

  const hasMoreInScan = merged.length > items.length;
  const hasMoreInStore = statusResults.some((result) => Boolean(result.lastEvaluatedKey));
  const hasMore = hasMoreInScan || hasMoreInStore;
  if (!hasMore) {
    return { items, nextCursor: null };
  }

  const boundaryTime = incidentSortTime(items[items.length - 1]);
  const boundaryIds = items
    .filter((incident) => incidentSortTime(incident) === boundaryTime)
    .map((incident) => String(incident.incidentId || ""))
    .filter(Boolean);
  const priorBoundaryIds = beforeTime === boundaryTime
    ? Array.from(excludedBoundaryIds)
    : [];
  const nextBoundaryIds = Array.from(new Set([...priorBoundaryIds, ...boundaryIds])).slice(-500);

  return {
    items,
    nextCursor: encodeIncidentCursor({
      beforeTime: boundaryTime,
      excludeIncidentIdsAtBoundary: nextBoundaryIds,
    }),
  };
}

async function listIncidentsByStatuses(statuses, { limitPerStatus = 200 } = {}) {
  const uniqueStatuses = Array.from(
    new Set(
      (statuses || [])
        .map((status) => normalizeAlertStatus(status, ALERT_STATUS.ACTIVE))
        .filter(Boolean)
    )
  );

  const results = await Promise.all(
    uniqueStatuses.map((status) => queryIncidentsByStatus(status, { limit: limitPerStatus }))
  );

  const merged = [];
  for (const result of results) {
    merged.push(...result.items);
  }

  merged.sort(sortIncidentsByLatestDesc);

  return merged;
}

async function countActiveIncidentQueuesByScan({
  statuses = [ALERT_STATUS.ACTIVE, ALERT_STATUS.ACKNOWLEDGED],
  pageLimit = 500,
} = {}) {
  const uniqueStatuses = Array.from(
    new Set(
      (statuses || [])
        .map((status) => normalizeAlertStatus(status, ALERT_STATUS.ACTIVE))
        .filter(Boolean)
    )
  );

  const perStatusCounts = await Promise.all(
    uniqueStatuses.map((status) =>
      countIncidentSeverityByStatus(status, { pageLimit })
    )
  );

  let activeIncidents = 0;
  let criticalQueue = 0;
  let warningQueue = 0;
  for (const item of perStatusCounts) {
    activeIncidents += item.total;
    criticalQueue += item.critical;
    warningQueue += item.warning;
  }

  return {
    activeIncidents,
    criticalQueue,
    warningQueue,
  };
}

async function countIncidentSeverityByStatus(status, { pageLimit = 500 } = {}) {
  const canonicalStatus = normalizeAlertStatus(status, ALERT_STATUS.ACTIVE);
  const limit = Math.max(
    1,
    Math.min(Number.parseInt(String(pageLimit || 500), 10) || 500, 1000)
  );
  const counts = {
    total: 0,
    critical: 0,
    warning: 0,
  };

  let startKey = null;
  do {
    const result = await docClient.send(
      new QueryCommand({
        TableName: tables.incident,
        IndexName: STATUS_UPDATED_AT_INDEX_NAME,
        KeyConditionExpression: "#status = :status",
        ExpressionAttributeNames: {
          "#status": "status",
          "#severity": "severity",
        },
        ExpressionAttributeValues: {
          ":status": canonicalStatus,
        },
        ProjectionExpression: "#severity",
        ScanIndexForward: false,
        Limit: limit,
        ExclusiveStartKey: startKey || undefined,
      })
    );

    const items = result.Items || [];
    counts.total += items.length;
    for (const raw of items) {
      const severity = String(raw?.severity || "").trim().toUpperCase();
      if (severity === "CRITICAL") counts.critical += 1;
      else if (severity === "WARNING") counts.warning += 1;
    }
    startKey = result.LastEvaluatedKey || null;
  } while (startKey);

  return counts;
}

async function updateIncidentStatus({
  incidentId,
  status,
  actorRole = "Operator",
}) {
  const canonicalStatus = normalizeAlertStatus(status, ALERT_STATUS.ACTIVE);
  const existing = await fetchIncidentById(incidentId);
  if (!existing) return null;

  const now = new Date().toISOString();
  const nextAcknowledgedAt =
    canonicalStatus === ALERT_STATUS.ACKNOWLEDGED || canonicalStatus === ALERT_STATUS.RESOLVED
      ? existing.acknowledgedAt || now
      : existing.acknowledgedAt;
  const nextResolvedAt =
    canonicalStatus === ALERT_STATUS.RESOLVED || canonicalStatus === ALERT_STATUS.CLOSED
      ? existing.resolvedAt || now
      : null;

  const result = await docClient.send(
    new UpdateCommand({
      TableName: tables.incident,
      Key: { incidentId },
      UpdateExpression:
        "SET #status = :status, acknowledgedAt = :acknowledgedAt, resolvedAt = :resolvedAt, updatedAt = :updatedAt, lastUpdatedAt = :lastUpdatedAt, statusUpdatedAt = :statusUpdatedAt, updatedByRole = :role",
      ExpressionAttributeNames: {
        "#status": "status",
      },
      ExpressionAttributeValues: {
        ":status": canonicalStatus,
        ":acknowledgedAt": nextAcknowledgedAt || null,
        ":resolvedAt": nextResolvedAt || null,
        ":updatedAt": now,
        ":lastUpdatedAt": now,
        ":statusUpdatedAt": `${canonicalStatus}#${now}`,
        ":role": actorRole,
      },
      ReturnValues: "ALL_NEW",
    })
  );

  const updated = normalizeIncidentRecord(result.Attributes || {});
  if (updated.status !== ALERT_STATUS.ACTIVE) {
    await releaseActiveLockForIncident(updated);
  }

  return updated;
}

async function releaseActiveLockForIncident(incident) {
  const correlationKey =
    incident.correlationKey ||
    buildCorrelationKey({
      deviceId: incident.deviceId,
      zone: incident.zone,
      sensorType: incident.sensorType,
    });
  const settingId = buildActiveCorrelationSettingId(correlationKey);

  try {
    await docClient.send(
      new DeleteCommand({
        TableName: tables.settings,
        Key: { settingId },
      })
    );
  } catch (error) {
    console.error("releaseActiveLockForIncident failed", {
      incidentId: incident.incidentId,
      correlationKey,
      error,
    });
  }
}

module.exports = {
  fetchIncidentById,
  queryIncidentsByStatus,
  listIncidentsByStatusesPage,
  listIncidentsByStatuses,
  countActiveIncidentQueuesByScan,
  updateIncidentStatus,
  releaseActiveLockForIncident,
};
