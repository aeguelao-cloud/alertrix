"use strict";

const { ALERT_STATUS, normalizeAlertRecord } = require("./alertStatus");

const SENSOR_TYPES = ["waterLevel", "vibration", "temperature"];
const DEFAULT_LIVE_WINDOW_SECONDS = Number(process.env.DASHBOARD_LIVE_WINDOW_SECONDS || 60);
const SENSOR_THRESHOLDS = {
  waterLevel: { warning: 70, critical: 85 },
  vibration: { warning: 10, critical: 14 },
  temperature: { warning: 35, critical: 40 },
};

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
  let liveCriticalQueue = 0;
  let liveWarningQueue = 0;

  const sensorStatus = {};
  for (const sensorType of SENSOR_TYPES) {
    const item = readingsBySensor.get(sensorType);
    const readingMs = parseTimeMs(item?.capturedAt);
    const hasReading = Number.isFinite(readingMs) && readingMs > 0;
    const isLive = hasReading && readingMs >= liveCutoffMs;
    const severity = isLive
      ? severityForSensorValue(sensorType, item?.value)
      : "UNKNOWN";
    if (isLive) liveSensors += 1;
    if (severity === "CRITICAL") liveCriticalQueue += 1;
    if (severity === "WARNING") liveWarningQueue += 1;
    if (hasReading && readingMs > latestReadingMs) latestReadingMs = readingMs;

    sensorStatus[sensorType] = {
      lastSeenAt: hasReading ? new Date(readingMs).toISOString() : null,
      live: isLive,
      value: item?.value ?? null,
      severity,
    };
  }

  const latestReadingAt = latestReadingMs > 0 ? new Date(latestReadingMs) : null;
  const latestReadingAgeSeconds = latestReadingAt
    ? Math.max(0, Math.floor((nowMs - latestReadingMs) / 1000))
    : null;
  const noTelemetry = !latestReadingAt || latestReadingMs < liveCutoffMs;

  let historicalActiveIncidents = 0;
  let historicalCriticalQueue = 0;
  let historicalWarningQueue = 0;
  if (incidentQueueStats) {
    historicalActiveIncidents = toInt(incidentQueueStats.activeIncidents, 0);
    historicalCriticalQueue = toInt(incidentQueueStats.criticalQueue, 0);
    historicalWarningQueue = toInt(incidentQueueStats.warningQueue, 0);
  } else {
    const normalizedAlerts = alerts.map((item) => normalizeAlertRecord(item));
    const activeAlerts = normalizedAlerts.filter(
      (item) =>
        item.status === ALERT_STATUS.ACTIVE ||
        item.status === ALERT_STATUS.ACKNOWLEDGED
    );
    historicalActiveIncidents = activeAlerts.length;
    historicalCriticalQueue = activeAlerts.filter((item) => item.severity === "CRITICAL").length;
    historicalWarningQueue = activeAlerts.filter((item) => item.severity === "WARNING").length;
  }

  const criticalQueue = noTelemetry ? 0 : liveCriticalQueue;
  const warningQueue = noTelemetry ? 0 : liveWarningQueue;
  const activeIncidents = criticalQueue + warningQueue;

  const telemetryCoverage = Math.round((liveSensors / SENSOR_TYPES.length) * 100);
  const latestSyncDate = latestReadingAt || now;
  const latestSync = formatHHmm(latestSyncDate);

  let systemStatus = "NORMAL";
  let currentRisk = "NORMAL";
  if (noTelemetry) {
    systemStatus = "NO_TELEMETRY";
    currentRisk = "UNKNOWN";
  } else if (liveCriticalQueue > 0) {
    systemStatus = "CRITICAL";
    currentRisk = "CRITICAL";
  } else if (liveWarningQueue > 0) {
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
    historicalActiveIncidents,
    historicalCriticalQueue,
    historicalWarningQueue,
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
        message: "A live sensor reading has exceeded the critical threshold.",
      };
    case "WARNING":
      return {
        type: "WARNING",
        title: "Warning condition detected",
        message: "A live sensor reading is approaching the warning threshold.",
      };
    default:
      return {
        type: "NORMAL",
        title: "System operating normally",
        message: "All active sensors are within safe thresholds.",
      };
  }
}

function severityForSensorValue(sensorType, rawValue) {
  const value = Number(rawValue);
  if (!Number.isFinite(value)) return "UNKNOWN";
  const threshold = SENSOR_THRESHOLDS[sensorType];
  if (!threshold) return "NORMAL";
  if (value >= threshold.critical) return "CRITICAL";
  if (value >= threshold.warning) return "WARNING";
  return "NORMAL";
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
