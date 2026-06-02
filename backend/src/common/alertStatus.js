"use strict";

const ALERT_STATUS = Object.freeze({
  ACTIVE: "ACTIVE",
  ACKNOWLEDGED: "ACKNOWLEDGED",
  RESOLVED: "RESOLVED",
  CLOSED: "CLOSED",
});

const LEGACY_STATUS_TO_CANONICAL = Object.freeze({
  OPEN: ALERT_STATUS.ACTIVE,
  CONFIRMED: ALERT_STATUS.ACKNOWLEDGED,
  WORK_ORDER_CREATED: ALERT_STATUS.ACKNOWLEDGED,
  IGNORED: ALERT_STATUS.CLOSED,
});

function normalizeAlertStatus(rawStatus, defaultStatus = ALERT_STATUS.ACTIVE) {
  const normalized = String(rawStatus || "").trim().toUpperCase();
  if (!normalized) return defaultStatus;
  if (Object.values(ALERT_STATUS).includes(normalized)) return normalized;
  return LEGACY_STATUS_TO_CANONICAL[normalized] || defaultStatus;
}

function normalizeSeverity(rawSeverity) {
  const normalized = String(rawSeverity || "").trim().toUpperCase();
  if (normalized === "CRITICAL") return "CRITICAL";
  if (normalized === "WARNING") return "WARNING";
  if (normalized === "NORMAL") return "NORMAL";
  return "WARNING";
}

function normalizeAlertRecord(item = {}) {
  const status = normalizeAlertStatus(item.status, ALERT_STATUS.ACTIVE);
  const createdAt = item.createdAt || item.detectedAt || item.updatedAt || null;
  return {
    ...item,
    status,
    createdAt,
    detectedAt: item.detectedAt || createdAt,
    acknowledgedAt: item.acknowledgedAt || null,
    resolvedAt: item.resolvedAt || null,
    incidentId: item.incidentId || item.alertId || null,
    deviceId: item.deviceId || null,
    severity: normalizeSeverity(item.severity),
  };
}

module.exports = {
  ALERT_STATUS,
  normalizeAlertStatus,
  normalizeSeverity,
  normalizeAlertRecord,
};
