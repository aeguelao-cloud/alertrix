"use strict";

const { QueryCommand, ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, serverError } = require("../common/response");
const { getNotificationSettings } = require("../common/notificationSettings");
const { getDeviceLocation } = require("../common/deviceLocationSettings");
const { isAdminRole } = require("../common/policy");

const SENSOR_TYPES = ["waterLevel", "vibration", "temperature"];

exports.handler = async (event) => {
  try {
    const headers = event.headers || {};
    const role = String(headers["x-user-role"] || headers["X-User-Role"] || "User").trim();
    const userId = String(headers["x-user-id"] || headers["X-User-Id"] || "").trim();
    const isAdmin = isAdminRole(role);

    const [latestReadings, alerts, workOrders, notificationSettings, deviceLocation] = await Promise.all([
      loadLatestReadings(),
      loadAlerts(),
      loadWorkOrders(),
      getNotificationSettings({ userId, role }),
      getDeviceLocation(),
    ]);

    const response = {
      navigation: buildNavigation(isAdmin),
      responseOverview: buildOverview(latestReadings, alerts),
      incidentQueue: buildIncidentQueue(alerts),
      responseSettings: buildSettings(notificationSettings, deviceLocation, role, isAdmin),
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

async function loadAlerts() {
  const result = await docClient.send(
    new ScanCommand({
      TableName: tables.alert,
    })
  );
  return result.Items || [];
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

function buildOverview(readings, alerts) {
  const activeAlerts = alerts.filter((a) => String(a.status || "").toUpperCase() === "ACTIVE");
  const critical = activeAlerts.filter((a) => String(a.severity || "").toUpperCase() === "CRITICAL");
  const warning = activeAlerts.filter((a) => String(a.severity || "").toUpperCase() === "WARNING");
  const sortedAlerts = activeAlerts.slice().sort((a, b) => String(a.detectedAt || "") < String(b.detectedAt || "") ? 1 : -1);
  const latestIncident = sortedAlerts[0] || null;

  const latestSync = readings
    .map((r) => r.capturedAt)
    .filter(Boolean)
    .sort()
    .reverse()[0] || new Date().toISOString();

  return {
    summary: {
      currentRisk: critical.length > 0 ? "Critical" : warning.length > 0 ? "Warning" : "Stable",
      openAlerts: activeAlerts.length,
      siteHealth: critical.length > 0 ? "Degraded" : "Healthy",
      latestSync,
    },
    highestPriorityIncident: latestIncident,
    fieldDeviceOverview: readings,
    recentAlertLog: sortedAlerts.slice(0, 10),
  };
}

function buildIncidentQueue(alerts) {
  const now = Date.now();
  const resolvedToday = alerts.filter((a) => {
    const status = String(a.status || "").toUpperCase();
    if (status !== "RESOLVED") return false;
    const ts = Date.parse(a.updatedAt || a.detectedAt || "");
    if (Number.isNaN(ts)) return false;
    return now - ts <= 24 * 60 * 60 * 1000;
  }).length;

  const open = alerts.filter((a) => String(a.status || "").toUpperCase() === "ACTIVE");
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

function buildSettings(notificationSettings, deviceLocation, role, isAdmin) {
  return {
    systemPolicy: {
      autoRefreshInterval: "30s",
      defaultTrendWindow: "24H",
      dashboardRefreshMode: "Cloud Sync",
    },
    alertThresholds: {
      waterLevel: { warning: 70, critical: 85, unit: "%" },
      vibration: { warning: 2.8, critical: 4.0, unit: "mm/s RMS" },
      temperature: { warning: 35, critical: 40, unit: "degC" },
      thresholdAudit: "Enabled",
    },
    notificationSettings,
    siteAndUser: {
      siteName: "Pilot Monitoring Site",
      currentRole: role || "User",
      deviceLocation: deviceLocation.location,
    },
    permissions: {
      canManageThresholds: isAdmin,
      canManageAdmins: isAdmin,
    },
  };
}
