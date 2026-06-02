"use strict";

const { GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");
const { docClient, tables } = require("./dynamo");
const { getThresholdConfigParam } = require("./runtimeConfig");

const ssm = new SSMClient({});

const defaultThresholds = {
  waterLevel: { warning: 70, critical: 85, unit: "%" },
  vibration: { warning: 10.0, critical: 14.0, unit: "mm/s RMS" },
  temperature: { warning: 35, critical: 40, unit: "°C" },
};

async function loadThresholdConfig() {
  const fromDb = await loadFromDynamo();
  if (fromDb) return mergeThresholds(fromDb);

  const fromSsm = await loadFromSsm();
  if (fromSsm) return mergeThresholds(fromSsm);

  return defaultThresholds;
}

async function loadFromDynamo() {
  try {
    const result = await docClient.send(
      new GetCommand({
        TableName: tables.settings,
        Key: { settingId: "THRESHOLD_CONFIG" },
      })
    );
    if (!result.Item) return null;
    return result.Item.thresholds || result.Item.value || null;
  } catch (error) {
    console.error("loadFromDynamo threshold failed", error);
    return null;
  }
}

async function saveThresholdConfig(candidate) {
  const thresholds = mergeThresholds(candidate);
  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: {
        settingId: "THRESHOLD_CONFIG",
        thresholds,
        updatedAt: new Date().toISOString(),
      },
    })
  );
  return thresholds;
}

async function loadFromSsm() {
  const name = getThresholdConfigParam();
  if (!name) return null;
  try {
    const result = await ssm.send(
      new GetParameterCommand({
        Name: name,
        WithDecryption: true,
      })
    );
    const raw = result.Parameter?.Value;
    if (!raw) return null;
    return JSON.parse(raw);
  } catch (error) {
    console.error("loadFromSsm threshold failed", error);
    return null;
  }
}

function mergeThresholds(candidate) {
  const normalized = { ...defaultThresholds };
  for (const key of Object.keys(defaultThresholds)) {
    const row = candidate?.[key];
    if (!row || typeof row !== "object") continue;
    const warning = Number(row.warning);
    const critical = Number(row.critical);
    normalized[key] = {
      warning: Number.isFinite(warning) ? warning : defaultThresholds[key].warning,
      critical: Number.isFinite(critical) ? critical : defaultThresholds[key].critical,
      unit:
        typeof row.unit === "string" && row.unit.trim().length > 0
          ? row.unit.trim()
          : defaultThresholds[key].unit,
    };
  }
  return normalized;
}

module.exports = {
  defaultThresholds,
  loadThresholdConfig,
  saveThresholdConfig,
};
