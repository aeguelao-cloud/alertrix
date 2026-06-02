"use strict";

const { GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("./dynamo");

const SETTINGS_ID = "SYSTEM_SETTINGS";
const DEFAULT_SYSTEM_SETTINGS = Object.freeze({
  autoRefreshIntervalSeconds: 4,
  defaultTrendWindow: "1H",
  dashboardRefreshMode: "Auto + Manual",
  siteName: "Pilot Monitoring Site",
  siteDescription: "Primary monitoring station",
});

const ALLOWED_REFRESH_INTERVALS = new Set([4, 10, 30, 60]);
const ALLOWED_TREND_WINDOWS = new Set(["1H", "6H", "24H", "7D", "14D", "30D"]);
const ALLOWED_REFRESH_MODES = new Set(["Auto", "Manual", "Auto + Manual"]);

async function getSystemSettings() {
  const result = await docClient.send(
    new GetCommand({
      TableName: tables.settings,
      Key: { settingId: SETTINGS_ID },
    })
  );

  const item = result.Item || {};
  return normalizeSystemSettings(item);
}

async function saveSystemSettings(partial) {
  const current = await getSystemSettings();
  const next = normalizeSystemSettings({
    ...current,
    ...(partial || {}),
  });

  const updatedAt = new Date().toISOString();
  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: {
        settingId: SETTINGS_ID,
        ...next,
        updatedAt,
      },
    })
  );

  return {
    ...next,
    updatedAt,
  };
}

function normalizeSystemSettings(source) {
  const refreshSeconds = Number(source.autoRefreshIntervalSeconds);
  const defaultTrendWindow = String(source.defaultTrendWindow || "").trim().toUpperCase();
  const refreshMode = String(source.dashboardRefreshMode || "").trim();
  const siteName = String(source.siteName || "").trim();
  const siteDescription = String(source.siteDescription || "").trim();

  return {
    autoRefreshIntervalSeconds: ALLOWED_REFRESH_INTERVALS.has(refreshSeconds)
      ? refreshSeconds
      : DEFAULT_SYSTEM_SETTINGS.autoRefreshIntervalSeconds,
    defaultTrendWindow: ALLOWED_TREND_WINDOWS.has(defaultTrendWindow)
      ? defaultTrendWindow
      : DEFAULT_SYSTEM_SETTINGS.defaultTrendWindow,
    dashboardRefreshMode: ALLOWED_REFRESH_MODES.has(refreshMode)
      ? refreshMode
      : DEFAULT_SYSTEM_SETTINGS.dashboardRefreshMode,
    siteName: siteName || DEFAULT_SYSTEM_SETTINGS.siteName,
    siteDescription: siteDescription || DEFAULT_SYSTEM_SETTINGS.siteDescription,
  };
}

module.exports = {
  DEFAULT_SYSTEM_SETTINGS,
  ALLOWED_REFRESH_INTERVALS,
  ALLOWED_TREND_WINDOWS,
  ALLOWED_REFRESH_MODES,
  getSystemSettings,
  saveSystemSettings,
};
