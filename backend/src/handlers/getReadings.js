"use strict";

const { QueryCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, serverError } = require("../common/response");
const { getSystemSettings } = require("../common/systemSettings");

const SENSOR_TYPES = ["waterLevel", "vibration", "temperature"];
const DEFAULT_LIVE_WINDOW_SECONDS = 60;

function parseTimestamp(raw) {
  if (!raw) return null;
  const dt = new Date(raw);
  if (Number.isNaN(dt.getTime())) return null;
  return dt;
}

exports.handler = async () => {
  try {
    const systemSettings = await getSystemSettings();
    const latest = [];
    const liveWindowSeconds = Number(process.env.LIVE_WINDOW_SECONDS || DEFAULT_LIVE_WINDOW_SECONDS);
    const now = new Date();
    const liveCutoffMs = now.getTime() - liveWindowSeconds * 1000;
    let freshestCapturedAt = null;

    for (const sensorType of SENSOR_TYPES) {
      const result = await docClient.send(
        new QueryCommand({
          TableName: tables.sensor,
          KeyConditionExpression: "sensorType = :sensorType",
          ExpressionAttributeValues: {":sensorType": sensorType},
          ScanIndexForward: false,
          Limit: 1
        })
      );

      if (result.Items && result.Items.length > 0) {
        const item = result.Items[0];
        const capturedAt = parseTimestamp(item.capturedAt);
        if (!capturedAt) continue;
        if (capturedAt.getTime() < liveCutoffMs) continue;
        latest.push(item);
        if (!freshestCapturedAt || capturedAt > freshestCapturedAt) {
          freshestCapturedAt = capturedAt;
        }
      }
    }

    return ok({
      siteName: systemSettings.siteName,
      updatedAt: (freshestCapturedAt || now).toISOString(),
      liveWindowSeconds,
      readings: latest
    });
  } catch (error) {
    console.error("getReadings error", error);
    return serverError("Failed to load latest readings");
  }
};
