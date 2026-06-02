"use strict";

const { ALERT_STATUS, normalizeAlertStatus, normalizeSeverity } = require("../common/alertStatus");
const { listIncidentsByStatuses, queryIncidentsByStatus } = require("../common/incidentStore");
const { ok, serverError } = require("../common/response");

const DEFAULT_STATUSES = Object.freeze([
  ALERT_STATUS.ACTIVE,
  ALERT_STATUS.ACKNOWLEDGED,
  ALERT_STATUS.RESOLVED,
  ALERT_STATUS.CLOSED,
]);

exports.handler = async (event) => {
  try {
    const severityFilter = event.queryStringParameters?.severity
      ? normalizeSeverity(event.queryStringParameters.severity)
      : null;
    const statusFilter = event.queryStringParameters?.status
      ? normalizeAlertStatus(event.queryStringParameters.status)
      : null;
    const limitRaw = event.queryStringParameters?.limit;
    const limit = Math.max(1, Math.min(Number.parseInt(limitRaw || "200", 10) || 200, 1000));

    let incidents;
    if (statusFilter) {
      const result = await queryIncidentsByStatus(statusFilter, { limit });
      incidents = result.items;
    } else {
      incidents = await listIncidentsByStatuses(DEFAULT_STATUSES, { limitPerStatus: limit });
    }

    if (severityFilter) {
      incidents = incidents.filter((item) => item.severity === severityFilter);
    }

    incidents.sort((a, b) => {
      const left = String(a.lastUpdatedAt || a.updatedAt || a.createdAt || "");
      const right = String(b.lastUpdatedAt || b.updatedAt || b.createdAt || "");
      if (left === right) return 0;
      return left < right ? 1 : -1;
    });

    return ok({
      items: incidents.slice(0, limit).map(toLegacyAlertShape),
    });
  } catch (error) {
    console.error("getAlerts error", error);
    return serverError("Failed to load alerts");
  }
};

function toLegacyAlertShape(incident) {
  const detectedAt = incident.latestEventAt || incident.lastUpdatedAt || incident.createdAt;
  return {
    ...incident,
    alertId: incident.incidentId,
    incidentId: incident.incidentId,
    detectedAt,
    triggerValue: incident.latestMeasuredValue,
  };
}
