"use strict";

const { QueryCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, badRequest, serverError } = require("../common/response");

const SENSOR_TYPES = new Set(["waterLevel", "vibration", "temperature"]);

const RANGE_CONFIG = {
  "1H": { durationMs: 60 * 60 * 1000, points: 8, maxRawItems: 2000 },
  "6H": { durationMs: 6 * 60 * 60 * 1000, points: 16, maxRawItems: 4000 },
  "24H": { durationMs: 24 * 60 * 60 * 1000, points: 24, maxRawItems: 8000 },
  "7D": { durationMs: 7 * 24 * 60 * 60 * 1000, points: 48, maxRawItems: 12000 },
  "14D": { durationMs: 14 * 24 * 60 * 60 * 1000, points: 84, maxRawItems: 16000 },
  "30D": { durationMs: 30 * 24 * 60 * 60 * 1000, points: 120, maxRawItems: 24000 },
};

exports.handler = async (event) => {
  try {
    const query = event.queryStringParameters ?? {};
    const metric = normalizeMetric(query.metric || "water_level");
    const range = normalizeRange(query.range || "1h");
    const config = RANGE_CONFIG[range] ?? RANGE_CONFIG["1H"];
    const now = new Date();
    const windowStart = new Date(now.getTime() - config.durationMs);

    if (!SENSOR_TYPES.has(metric)) {
      return badRequest("Invalid metric. Use waterLevel|vibration|temperature");
    }

    const baseSeries = await loadSeries({
      metric,
      startIso: windowStart.toISOString(),
      endIso: now.toISOString(),
      maxRawItems: config.maxRawItems,
    });
    const sampledSeries = sampleRealSeries(baseSeries, {
      startMs: windowStart.getTime(),
      endMs: now.getTime(),
      points: config.points,
    });
    const payload = sampledSeries.map((item) => ({ timestamp: item.capturedAt, value: Number(item.value.toFixed(3)) }));

    return ok({
      metric,
      range,
      source: "real_sensor_readings",
      windowStart: windowStart.toISOString(),
      windowEnd: now.toISOString(),
      requestedPoints: config.points,
      rawPoints: baseSeries.length,
      points: payload,
      series: payload,
      timestamps: payload.map((item) => item.timestamp)
    });
  } catch (error) {
    console.error("getTrends error", error);
    return serverError("Failed to load trends");
  }
};

async function loadSeries({ metric, startIso, endIso, maxRawItems }) {
  const items = [];
  let lastEvaluatedKey;

  do {
    const result = await docClient.send(
      new QueryCommand({
        TableName: tables.sensor,
        KeyConditionExpression: "sensorType = :sensorType AND capturedAt BETWEEN :start AND :end",
        ExpressionAttributeNames: { "#value": "value" },
        ExpressionAttributeValues: {
          ":sensorType": metric,
          ":start": startIso,
          ":end": endIso,
        },
        ProjectionExpression: "capturedAt, #value",
        ScanIndexForward: true,
        ExclusiveStartKey: lastEvaluatedKey,
      })
    );

    for (const item of result.Items ?? []) {
      if (items.length >= maxRawItems) break;
      const value = Number(item.value);
      if (!item.capturedAt || Number.isNaN(value)) continue;
      items.push({ capturedAt: item.capturedAt, value });
    }

    lastEvaluatedKey = result.LastEvaluatedKey;
  } while (lastEvaluatedKey && items.length < maxRawItems);

  items.sort((a, b) => (a.capturedAt < b.capturedAt ? -1 : 1));
  return items;
}

function sampleRealSeries(items, { startMs, endMs, points }) {
  if (items.length <= points) return items;

  const bucketMs = Math.max(1, (endMs - startMs) / points);
  const buckets = Array.from({ length: points }, () => ({
    count: 0,
    sum: 0,
    lastCapturedAt: null,
  }));

  for (const item of items) {
    const capturedMs = new Date(item.capturedAt).getTime();
    if (Number.isNaN(capturedMs)) continue;
    const rawIndex = Math.floor((capturedMs - startMs) / bucketMs);
    const index = Math.max(0, Math.min(points - 1, rawIndex));
    const bucket = buckets[index];
    bucket.count += 1;
    bucket.sum += item.value;
    bucket.lastCapturedAt = item.capturedAt;
  }

  return buckets
    .filter((bucket) => bucket.count > 0)
    .map((bucket) => ({
      capturedAt: bucket.lastCapturedAt,
      value: bucket.sum / bucket.count,
    }));
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
  if (value === "14d") return "14D";
  if (value === "30d") return "30D";
  return String(range).toUpperCase();
}
