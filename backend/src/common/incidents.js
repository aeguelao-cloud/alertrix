"use strict";

const { ALERT_STATUS, normalizeAlertStatus, normalizeSeverity } = require("./alertStatus");

const INCIDENT_ACTIVE_STATUSES = Object.freeze([
  ALERT_STATUS.ACTIVE,
  ALERT_STATUS.ACKNOWLEDGED,
]);

function incidentTitleForSensor(sensorType) {
  const normalized = String(sensorType || "").trim();
  if (!normalized) return "Sensor threshold exceeded";
  return `${normalized} threshold exceeded`;
}

function buildCorrelationKey({ deviceId, zone, sensorType }) {
  const normalizedDevice = String(deviceId || "UNKNOWN_DEVICE").trim().toUpperCase();
  const normalizedZone = String(zone || "Unknown Zone").trim().toUpperCase();
  const normalizedSensor = String(sensorType || "unknown").trim().toLowerCase();
  return `${normalizedDevice}#${normalizedZone}#${normalizedSensor}`;
}

function buildActiveCorrelationSettingId(correlationKey) {
  return `INCIDENT_ACTIVE#${String(correlationKey || "").trim()}`;
}

function normalizeIncidentRecord(item = {}) {
  const status = normalizeAlertStatus(item.status, ALERT_STATUS.ACTIVE);
  const createdAt = item.createdAt || item.startedAt || item.updatedAt || null;
  const eventCount = toInt(item.eventCount, 1);
  return {
    ...item,
    status,
    createdAt,
    startedAt: item.startedAt || createdAt,
    updatedAt: item.updatedAt || createdAt,
    lastUpdatedAt: item.lastUpdatedAt || item.updatedAt || createdAt,
    acknowledgedAt: item.acknowledgedAt || null,
    resolvedAt: item.resolvedAt || null,
    eventCount: eventCount < 1 ? 1 : eventCount,
    severity: normalizeSeverity(item.severity),
    incidentId: item.incidentId || null,
    deviceId: item.deviceId || null,
    zone: item.zone || "Unknown Zone",
    sensorType: item.sensorType || null,
    title: item.title || incidentTitleForSensor(item.sensorType),
    latestMeasuredValue: item.latestMeasuredValue || item.triggerValue || null,
  };
}

function toInt(raw, fallback = 0) {
  if (typeof raw === "number" && Number.isFinite(raw)) return Math.trunc(raw);
  const parsed = Number.parseInt(String(raw ?? ""), 10);
  if (Number.isNaN(parsed)) return fallback;
  return parsed;
}

module.exports = {
  INCIDENT_ACTIVE_STATUSES,
  buildCorrelationKey,
  buildActiveCorrelationSettingId,
  incidentTitleForSensor,
  normalizeIncidentRecord,
};
