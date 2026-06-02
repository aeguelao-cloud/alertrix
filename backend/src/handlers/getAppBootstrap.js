"use strict";

const { QueryCommand, ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, serverError } = require("../common/response");
const { getNotificationSettings } = require("../common/notificationSettings");
const { getDeviceLocation } = require("../common/deviceLocationSettings");
const { isAdminRole } = require("../common/policy");
const { loadThresholdConfig } = require("../common/thresholds");
const { getSystemSettings } = require("../common/systemSettings");
const { getEmergencyAgency } = require("../common/runtimeConfig");
const { ALERT_STATUS, normalizeAlertRecord } = require("../common/alertStatus");
const { listIncidentsByStatuses } = require("../common/incidentStore");
const { SENSOR_TYPES, buildDashboardOverview } = require("../common/dashboardOverview");

exports.handler = async (event) => {
  try {
    const headers = event.headers || {};
    const role = String(headers["x-user-role"] || headers["X-User-Role"] || "User").trim();
    const userId = String(headers["x-user-id"] || headers["X-User-Id"] || "").trim();
    const isAdmin = isAdminRole(role);

    const [latestReadings, alerts, workOrders, notificationSettings, deviceLocation, thresholdConfig, systemSettings] = await Promise.all([
      loadLatestReadings(),
      loadIncidents(),
      loadWorkOrders(),
      getNotificationSettings({ userId, role }),
      getDeviceLocation(),
      loadThresholdConfig(),
      getSystemSettings(),
    ]);
    const dashboardOverview = buildDashboardOverview({
      latestReadings,
      alerts,
      now: new Date(),
    });

    const response = {
      navigation: buildNavigation(isAdmin),
      responseOverview: buildOverview(latestReadings, alerts, dashboardOverview),
      incidentQueue: buildIncidentQueue(alerts),
      responseSettings: buildSettings(notificationSettings, deviceLocation, role, isAdmin, thresholdConfig, systemSettings),
      dashboardOverview,
      generatedAt: new Date().toISOString(),
    };

    if (isAdmin) {
      response.adminManagement = {
        enabled: true,
        recipientsPolicy: "Only active admins receive alert emails",
      };
      response.workOrders = {
        enabled: true,
        total: workOrders.length,
        open: workOrders.filter((w) => String(w.status || "").toUpperCase() === "OPEN").length,
      };
    }

    return ok(response);
  } catch (error) {
    console.error("getAppBootstrap error", error);
    return serverError("Failed to load app bootstrap data");
  }
};

async function loadLatestReadings() {
  const results = await Promise.all(
    SENSOR_TYPES.map(async (sensorType) => {
      const res = await docClient.send(
        new QueryCommand({
          TableName: tables.sensor,
          KeyConditionExpression: "sensorType = :sensorType",
          ExpressionAttributeValues: { ":sensorType": sensorType },
          ScanIndexForward: false,
          Limit: 1,
        })
      );
      return res.Items?.[0] || null;
    })
  );
  return results.filter(Boolean);
}

async function loadIncidents() {
  return listIncidentsByStatuses(
    [ALERT_STATUS.ACTIVE, ALERT_STATUS.ACKNOWLEDGED, ALERT_STATUS.RESOLVED, ALERT_STATUS.CLOSED],
    { limitPerStatus: 500 }
  );
}

async function loadWorkOrders() {
  const result = await docClient.send(
    new ScanCommand({
      TableName: tables.workOrder,
    })
  );
  return result.Items || [];
}

function buildNavigation(isAdmin) {
  const items = ["Response Overview", "Situation Trends", "Incident Queue", "Response Settings"];
  if (isAdmin) items.push("Admin Management", "Work Orders");
  return items;
}

function buildOverview(readings, alerts, dashboardOverview) {
  const activeAlerts = alerts
    .map((a) => normalizeAlertRecord(a))
    .filter((a) => a.status === ALERT_STATUS.ACTIVE || a.status === ALERT_STATUS.ACKNOWLEDGED);
  const sortedAlerts = activeAlerts.slice().sort((a, b) => String(a.detectedAt || "") < String(b.detectedAt || "") ? 1 : -1);
  const latestIncident = sortedAlerts[0] || null;

  return {
    summary: {
      currentRisk: dashboardOverview.currentRisk,
      openAlerts: dashboardOverview.activeIncidents,
      siteHealth: dashboardOverview.systemStatus,
      latestSync: dashboardOverview.latestReadingAt || new Date().toISOString(),
    },
    highestPriorityIncident: latestIncident,
    fieldDeviceOverview: readings,
    recentAlertLog: sortedAlerts.slice(0, 10),
  };
}

function buildIncidentQueue(alerts) {
  const now = Date.now();
  const normalized = alerts.map((a) => normalizeAlertRecord(a));
  const resolvedToday = normalized.filter((a) => {
    const status = String(a.status || "").toUpperCase();
    if (status !== "RESOLVED") return false;
    const ts = Date.parse(a.updatedAt || a.detectedAt || "");
    if (Number.isNaN(ts)) return false;
    return now - ts <= 24 * 60 * 60 * 1000;
  }).length;

  const open = normalized.filter(
    (a) => a.status === ALERT_STATUS.ACTIVE || a.status === ALERT_STATUS.ACKNOWLEDGED
  );
  return {
    stats: {
      openIncidents: open.length,
      critical: open.filter((a) => String(a.severity || "").toUpperCase() === "CRITICAL").length,
      warning: open.filter((a) => String(a.severity || "").toUpperCase() === "WARNING").length,
      resolvedToday,
    },
    filters: ["All Severity", "Stable", "Warning", "Critical"],
  };
}

function buildSettings(notificationSettings, deviceLocation, role, isAdmin, thresholdConfig, systemSettings) {
  return {
    systemPolicy: {
      autoRefreshInterval: `${systemSettings.autoRefreshIntervalSeconds}s`,
      defaultTrendWindow: systemSettings.defaultTrendWindow,
      dashboardRefreshMode: systemSettings.dashboardRefreshMode,
    },
    alertThresholds: { ...thresholdConfig, thresholdAudit: "Enabled" },
    notificationSettings,
    siteAndUser: {
      siteName: systemSettings.siteName,
      currentRole: role || "User",
      deviceLocation: deviceLocation.location,
      emergencyAgency: getEmergencyAgency() || "Not configured",
    },
    permissions: {
      canManageThresholds: isAdmin,
      canManageAdmins: isAdmin,
    },
  };
}
