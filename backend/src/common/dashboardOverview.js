"use strict";

const { ALERT_STATUS, normalizeAlertRecord } = require("./alertStatus");

const SENSOR_TYPES = ["waterLevel", "vibration", "temperature"];
const DEFAULT_LIVE_WINDOW_SECONDS = Number(process.env.DASHBOARD_LIVE_WINDOW_SECONDS || 60);

function buildDashboardOverview({
  latestReadings = [],
  alerts = [],
  incidentQueueStats = null,
  now = new Date(),
  liveWindowSeconds = DEFAULT_LIVE_WINDOW_SECONDS,
} = {}) {
  const readingsBySensor = new Map();
  for (const sensorType of SENSOR_TYPES) {
    readingsBySensor.set(sensorType, null);
  }

  for (const raw of latestReadings) {
    const sensorType = String(raw?.sensorType || "").trim();
    if (!SENSOR_TYPES.includes(sensorType)) continue;
    const current = readingsBySensor.get(sensorType);
    if (!current) {
      readingsBySensor.set(sensorType, raw);
      continue;
    }
    const currentMs = parseTimeMs(current.capturedAt);
    const nextMs = parseTimeMs(raw.capturedAt);
    if (nextMs > currentMs) {
      readingsBySensor.set(sensorType, raw);
    }
  }

  const nowMs = now.getTime();
  const liveCutoffMs = nowMs - Math.max(0, liveWindowSeconds) * 1000;
  let latestReadingMs = 0;
  let liveSensors = 0;

  const sensorStatus = {};
  for (const sensorType of SENSOR_TYPES) {
    const item = readingsBySensor.get(sensorType);
    const readingMs = parseTimeMs(item?.capturedAt);
    const hasReading = Number.isFinite(readingMs) && readingMs > 0;
    const isLive = hasReading && readingMs >= liveCutoffMs;
    if (isLive) liveSensors += 1;
    if (hasReading && readingMs > latestReadingMs) latestReadingMs = readingMs;

    sensorStatus[sensorType] = {
      lastSeenAt: hasReading ? new Date(readingMs).toISOString() : null,
      live: isLive,
      value: item?.value ?? null,
    };
  }

  const latestReadingAt = latestReadingMs > 0 ? new Date(latestReadingMs) : null;
  const latestReadingAgeSeconds = latestReadingAt
    ? Math.max(0, Math.floor((nowMs - latestReadingMs) / 1000))
    : null;
  const noTelemetry = !latestReadingAt || latestReadingMs < liveCutoffMs;

  let activeIncidents = 0;
  let criticalQueue = 0;
  let warningQueue = 0;
  if (incidentQueueStats) {
    activeIncidents = toInt(incidentQueueStats.activeIncidents, 0);
    criticalQueue = toInt(incidentQueueStats.criticalQueue, 0);
    warningQueue = toInt(incidentQueueStats.warningQueue, 0);
  } else {
    const normalizedAlerts = alerts.map((item) => normalizeAlertRecord(item));
    const activeAlerts = normalizedAlerts.filter(
      (item) =>
        item.status === ALERT_STATUS.ACTIVE ||
        item.status === ALERT_STATUS.ACKNOWLEDGED
    );
    activeIncidents = activeAlerts.length;
    criticalQueue = activeAlerts.filter((item) => item.severity === "CRITICAL").length;
    warningQueue = activeAlerts.filter((item) => item.severity === "WARNING").length;
  }

  const telemetryCoverage = Math.round((liveSensors / SENSOR_TYPES.length) * 100);
  const latestSyncDate = latestReadingAt || now;
  const latestSync = formatHHmm(latestSyncDate);

  let systemStatus = "NORMAL";
  let currentRisk = "NORMAL";
  if (noTelemetry) {
    systemStatus = "NO_TELEMETRY";
    currentRisk = "UNKNOWN";
  } else if (criticalQueue > 0) {
    systemStatus = "CRITICAL";
    currentRisk = "CRITICAL";
  } else if (warningQueue > 0) {
    systemStatus = "WARNING";
    currentRisk = "WARNING";
  }

  return {
    systemStatus,
    currentRisk,
    activeIncidents,
    criticalQueue,
    warningQueue,
    telemetryCoverage: clamp(telemetryCoverage, 0, 100),
    latestSync,
    latestReadingAt: latestReadingAt ? latestReadingAt.toISOString() : null,
    latestReadingAgeSeconds,
    liveWindowSeconds,
    banner: buildBanner(systemStatus),
    sensorStatus,
  };
}

function buildBanner(systemStatus) {
  switch (systemStatus) {
    case "NO_TELEMETRY":
      return {
        type: "NO_TELEMETRY",
        title: "Telemetry unavailable",
        message: "No live sensor data received. Please check device connection.",
      };
    case "CRITICAL":
      return {
        type: "CRITICAL",
        title: "Critical incident response required",
        message: "Water level or vibration threshold exceeded.",
      };
    case "WARNING":
      return {
        type: "WARNING",
        title: "Warning condition detected",
        message: "One or more incidents require operator review.",
      };
    default:
      return {
        type: "NORMAL",
        title: "System operating normally",
        message: "All active sensors are within safe thresholds.",
      };
  }
}

function parseTimeMs(raw) {
  if (!raw) return 0;
  const ms = Date.parse(raw);
  if (Number.isNaN(ms)) return 0;
  return ms;
}

function formatHHmm(date) {
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function toInt(value, fallback = 0) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (Number.isNaN(parsed)) return fallback;
  return parsed;
}

module.exports = {
  SENSOR_TYPES,
  buildDashboardOverview,
};
