"use strict";

const { ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, serverError } = require("../common/response");

exports.handler = async (event) => {
  try {
    const severity = event.queryStringParameters?.severity;
    const status = event.queryStringParameters?.status;

    const result = await docClient.send(
      new ScanCommand({
        TableName: tables.alert
      })
    );

    let alerts = result.Items ?? [];
    if (severity) {
      alerts = alerts.filter((item) => item.severity === severity);
    }
    if (status) {
      alerts = alerts.filter((item) => item.status === status);
    }

    alerts.sort((a, b) => (a.detectedAt < b.detectedAt ? 1 : -1));

    return ok({ items: alerts });
  } catch (error) {
    console.error("getAlerts error", error);
    return serverError("Failed to load alerts");
  }
};
