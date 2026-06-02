"use strict";

const { QueryCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, serverError } = require("../common/response");
const { countActiveIncidentQueuesByScan } = require("../common/incidentStore");
const { SENSOR_TYPES, buildDashboardOverview } = require("../common/dashboardOverview");

exports.handler = async () => {
  try {
    const [latestReadings, incidentQueueStats] = await Promise.all([
      loadLatestReadings(),
      loadIncidentQueueStats(),
    ]);

    const overview = buildDashboardOverview({
      latestReadings,
      incidentQueueStats,
      now: new Date(),
    });

    return ok(overview);
  } catch (error) {
    console.error("getDashboardOverview error", error);
    return serverError("Failed to load dashboard overview");
  }
};

async function loadLatestReadings() {
  const readings = await Promise.all(
    SENSOR_TYPES.map(async (sensorType) => {
      const result = await docClient.send(
        new QueryCommand({
          TableName: tables.sensor,
          KeyConditionExpression: "sensorType = :sensorType",
          ExpressionAttributeValues: { ":sensorType": sensorType },
          ScanIndexForward: false,
          Limit: 1,
        })
      );
      return result.Items?.[0] || null;
    })
  );
  return readings.filter(Boolean);
}

async function loadIncidentQueueStats() {
  return countActiveIncidentQueuesByScan({
    pageLimit: 1000,
  });
}
