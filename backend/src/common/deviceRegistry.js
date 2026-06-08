"use strict";

const { QueryCommand, PutCommand, ScanCommand, GetCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("./dynamo");
const { getDeviceLocation } = require("./deviceLocationSettings");

const DEVICE_KEY_PREFIX = "DEVICE#";
const SENSOR_TYPES = ["gateway", "waterLevel", "vibration", "temperature"];
const DEFAULT_FIRMWARE = "v1.0";
const OFFLINE_WINDOW_SECONDS = Number(process.env.OFFLINE_WINDOW_SECONDS || 120);

const defaultDeviceTemplate = [
  {
    deviceId: "ESP32-01",
    sensorType: "gateway",
    zone: "Zone A - Pump Station",
    status: "active",
    firmwareVersion: DEFAULT_FIRMWARE,
  },
  {
    deviceId: "WL-01",
    sensorType: "waterLevel",
    zone: "Zone A - Pump Station",
    status: "active",
    firmwareVersion: DEFAULT_FIRMWARE,
  },
  {
    deviceId: "VB-01",
    sensorType: "vibration",
    zone: "Zone A - Pump Station",
    status: "active",
    firmwareVersion: DEFAULT_FIRMWARE,
  },
  {
    deviceId: "TP-01",
    sensorType: "temperature",
    zone: "Zone A - Pump Station",
    status: "active",
    firmwareVersion: DEFAULT_FIRMWARE,
  },
];

async function listDevices() {
  const [registered, latestBySensorType, location] = await Promise.all([
    listRegisteredDevices(),
    loadLatestReadingsBySensor(),
    getDeviceLocation(),
  ]);

  const baseZone = location.location || "Zone A - Pump Station";
  const source = registered.length > 0
    ? registered
    : defaultDeviceTemplate.map((item) => ({ ...item, zone: baseZone }));

  const nowMs = Date.now();
  return source.map((item) => toDeviceView(item, latestBySensorType, nowMs));
}

async function registerDevice(input = {}, actor = "system") {
  const device = normalizeDeviceInput(input, { requireDeviceId: true });
  const now = new Date().toISOString();
  const item = {
    settingId: keyForDevice(device.deviceId),
    type: "device",
    deviceId: device.deviceId,
    sensorType: device.sensorType,
    zone: device.zone,
    status: "active",
    firmwareVersion: device.firmwareVersion || DEFAULT_FIRMWARE,
    createdAt: now,
    updatedAt: now,
    updatedBy: actor,
  };
  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: item,
    })
  );
  return item;
}

async function updateDevice(deviceId, input = {}, actor = "system") {
  const cleanId = normalizeDeviceId(deviceId);
  const existing = await getStoredDevice(cleanId);
  if (!existing) return null;
  const patch = normalizeDeviceInput(input, { requireDeviceId: false });
  const now = new Date().toISOString();
  const next = {
    ...existing,
    sensorType: patch.sensorType || existing.sensorType,
    zone: patch.zone || existing.zone,
    status: patch.status || existing.status || "active",
    firmwareVersion: patch.firmwareVersion || existing.firmwareVersion || DEFAULT_FIRMWARE,
    updatedAt: now,
    updatedBy: actor,
  };
  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: next,
    })
  );
  return next;
}

async function setDeviceStatus(deviceId, status, actor = "system") {
  const targetStatus = String(status || "").trim().toLowerCase();
  if (!["active", "disabled"].includes(targetStatus)) {
    const error = new Error("Invalid status");
    error.code = "BAD_INPUT";
    throw error;
  }
  return updateDevice(deviceId, { status: targetStatus }, actor);
}

async function recordDeviceTest(deviceId, actor = "system") {
  const cleanId = normalizeDeviceId(deviceId);
  const existing = await getStoredDevice(cleanId);
  if (!existing) return null;
  const now = new Date().toISOString();
  const next = {
    ...existing,
    lastTestAt: now,
    updatedAt: now,
    updatedBy: actor,
  };
  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: next,
    })
  );
  return next;
}

async function getStoredDevice(deviceId) {
  const cleanId = normalizeDeviceId(deviceId);
  const result = await docClient.send(
    new GetCommand({
      TableName: tables.settings,
      Key: { settingId: keyForDevice(cleanId) },
    })
  );
  return result.Item || null;
}

async function listRegisteredDevices() {
  const result = await docClient.send(
    new ScanCommand({
      TableName: tables.settings,
      FilterExpression: "begins_with(settingId, :prefix)",
      ExpressionAttributeValues: {
        ":prefix": DEVICE_KEY_PREFIX,
      },
    })
  );
  const items = (result.Items || []).filter((item) => item && item.deviceId);
  return items.map((item) => ({
    deviceId: normalizeDeviceId(item.deviceId),
    sensorType: normalizeSensorType(item.sensorType),
    zone: String(item.zone || "").trim() || "Zone A - Pump Station",
    status: normalizeDeviceStatus(item.status),
    firmwareVersion: String(item.firmwareVersion || DEFAULT_FIRMWARE),
    lastTestAt: item.lastTestAt || null,
    createdAt: item.createdAt || null,
    updatedAt: item.updatedAt || null,
    updatedBy: item.updatedBy || null,
  }));
}

async function loadLatestReadingsBySensor() {
  const sensorTypes = ["waterLevel", "vibration", "temperature"];
  const entries = await Promise.all(
    sensorTypes.map(async (sensorType) => {
      const result = await docClient.send(
        new QueryCommand({
          TableName: tables.sensor,
          KeyConditionExpression: "sensorType = :sensorType",
          ExpressionAttributeValues: { ":sensorType": sensorType },
          ScanIndexForward: false,
          Limit: 1,
        })
      );
      const latest = result.Items?.[0] || null;
      return [sensorType, latest];
    })
  );
  return Object.fromEntries(entries);
}

function toDeviceView(item, latestBySensorType, nowMs) {
  const sensorType = normalizeSensorType(item.sensorType);
  const latest = sensorType === "gateway"
    ? newestReading(Object.values(latestBySensorType))
    : latestBySensorType[sensorType] || null;
  const capturedAt = latest?.capturedAt || null;
  const lastSyncMs = capturedAt ? Date.parse(capturedAt) : NaN;
  const isOnline = Number.isFinite(lastSyncMs) && nowMs - lastSyncMs <= OFFLINE_WINDOW_SECONDS * 1000;
  const statusValue = normalizeDeviceStatus(item.status);
  const status = statusValue === "disabled"
    ? "Disabled"
    : (isOnline ? "Online" : "Offline");
  return {
    deviceId: item.deviceId,
    sensorType,
    zone: item.zone,
    status,
    state: statusValue,
    firmwareVersion: item.firmwareVersion || DEFAULT_FIRMWARE,
    lastSync: capturedAt,
    lastHeartbeat: capturedAt,
    latestValue: latest?.value ?? null,
    latestUnit: sensorUnit(sensorType),
    lastTestAt: item.lastTestAt || null,
    createdAt: item.createdAt || null,
    updatedAt: item.updatedAt || null,
    updatedBy: item.updatedBy || null,
  };
}

function newestReading(readings) {
  const valid = readings.filter(Boolean);
  if (valid.length === 0) return null;
  valid.sort((a, b) => {
    const ta = Date.parse(a.capturedAt || "");
    const tb = Date.parse(b.capturedAt || "");
    if (!Number.isFinite(ta)) return 1;
    if (!Number.isFinite(tb)) return -1;
    return tb - ta;
  });
  return valid[0];
}

function normalizeDeviceInput(input = {}, options = {}) {
  const zone = String(input.zone || "").trim();
  const firmwareVersion = String(input.firmwareVersion || "").trim();
  const deviceId = input.deviceId === undefined ? "" : normalizeDeviceId(input.deviceId);
  const sensorType = normalizeSensorType(input.sensorType);
  const status = input.status !== undefined ? normalizeDeviceStatus(input.status) : undefined;

  if (options.requireDeviceId && !deviceId) {
    const error = new Error("deviceId is required");
    error.code = "BAD_INPUT";
    throw error;
  }
  if (input.sensorType !== undefined && !SENSOR_TYPES.includes(sensorType)) {
    const error = new Error("sensorType must be gateway|waterLevel|vibration|temperature");
    error.code = "BAD_INPUT";
    throw error;
  }
  return {
    deviceId,
    sensorType,
    zone,
    firmwareVersion,
    status,
  };
}

function normalizeDeviceId(deviceId) {
  return String(deviceId || "").trim().toUpperCase();
}

function normalizeSensorType(sensorType) {
  const raw = String(sensorType || "").trim().toLowerCase();
  if (!raw) return "gateway";
  if (raw === "water" || raw === "water_level" || raw === "waterlevel") return "waterLevel";
  if (raw === "vibration") return "vibration";
  if (raw === "temperature" || raw === "temp") return "temperature";
  if (raw === "gateway" || raw === "esp32") return "gateway";
  return sensorType;
}

function normalizeDeviceStatus(status) {
  const raw = String(status || "").trim().toLowerCase();
  return raw === "disabled" ? "disabled" : "active";
}

function sensorUnit(sensorType) {
  switch (sensorType) {
    case "waterLevel":
      return "%";
    case "vibration":
      return "index";
    case "temperature":
      return "deg C";
    default:
      return "";
  }
}

function keyForDevice(deviceId) {
  return `${DEVICE_KEY_PREFIX}${normalizeDeviceId(deviceId)}`;
}

module.exports = {
  listDevices,
  registerDevice,
  updateDevice,
  setDeviceStatus,
  recordDeviceTest,
  getStoredDevice,
};
