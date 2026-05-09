"use strict";

const { QueryCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, serverError } = require("../common/response");

const SENSOR_TYPES = ["waterLevel", "vibration", "temperature"];

exports.handler = async () => {
  try {
    const latest = [];

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
        latest.push(result.Items[0]);
      }
    }

    return ok({
      siteName: "Pilot Monitoring Site",
      updatedAt: new Date().toISOString(),
      readings: latest
    });
  } catch (error) {
    console.error("getReadings error", error);
    return serverError("Failed to load latest readings");
  }
};
