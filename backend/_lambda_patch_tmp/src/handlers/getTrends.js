"use strict";

const { QueryCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, badRequest, serverError } = require("../common/response");

const SENSOR_TYPES = new Set(["waterLevel", "vibration", "temperature"]);

const RANGE_POINTS = {
  "1H": 8,
  "6H": 16,
  "24H": 24,
  "7D": 48
};

exports.handler = async (event) => {
  try {
    const query = event.queryStringParameters ?? {};
    const metric = normalizeMetric(query.metric || "water_level");
    const range = normalizeRange(query.range || "1h");
    const points = RANGE_POINTS[range] ?? RANGE_POINTS["1H"];

    if (!SENSOR_TYPES.has(metric)) {
      return badRequest("Invalid metric. Use waterLevel|vibration|temperature");
    }

    const baseSeries = await loadSeries(metric, points);
    const payload = baseSeries.map((item) => ({ timestamp: item.capturedAt, value: Number(item.value.toFixed(3)) }));

    return ok({
      metric,
      range,
      points: payload,
      series: payload.map((item) => item.value)
    });
  } catch (error) {
    console.error("getTrends error", error);
    return serverError("Failed to load trends");
  }
};

async function loadSeries(metric, points) {
  const result = await docClient.send(
    new QueryCommand({
      TableName: tables.sensor,
      KeyConditionExpression: "sensorType = :sensorType",
      ExpressionAttributeValues: { ":sensorType": metric },
      ScanIndexForward: false,
      Limit: points
    })
  );

  const items = (result.Items ?? [])
    .filter((item) => typeof item.value === "number" || typeof item.value === "string")
    .map((item) => ({
      capturedAt: item.capturedAt || new Date().toISOString(),
      value: Number(item.value)
    }))
    .filter((item) => !Number.isNaN(item.value));

  items.sort((a, b) => (a.capturedAt < b.capturedAt ? -1 : 1));

  if (items.length === 0) {
    const now = Date.now();
    return Array.from({ length: points }, (_, index) => ({
      capturedAt: new Date(now - (points - index) * 60 * 1000).toISOString(),
      value: 0
    }));
  }

  if (items.length >= points) {
    return items.slice(items.length - points);
  }

  const seed = items[0];
  const missing = points - items.length;
  const prefix = Array.from({ length: missing }, (_, index) => ({
    capturedAt: new Date(new Date(seed.capturedAt).getTime() - (missing - index) * 60 * 1000).toISOString(),
    value: seed.value
  }));

  return [...prefix, ...items];
}

function normalizeMetric(metric) {
  const value = String(metric).trim().toLowerCase();
  if (value === "water_level" || value === "waterlevel") return "waterLevel";
  if (value === "vibration") return "vibration";
  if (value === "temperature") return "temperature";
  return String(metric);
}

function normalizeRange(range) {
  const value = String(range).trim().toLowerCase();
  if (value === "1h") return "1H";
  if (value === "6h") return "6H";
  if (value === "24h") return "24H";
  if (value === "7d") return "7D";
  return String(range).toUpperCase();
}
