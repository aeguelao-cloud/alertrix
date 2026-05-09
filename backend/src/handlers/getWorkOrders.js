"use strict";

const { ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, serverError } = require("../common/response");

exports.handler = async (event) => {
  try {
    const status = event.queryStringParameters?.status;
    const alertId = event.queryStringParameters?.alertId;
    const limitRaw = event.queryStringParameters?.limit;
    const limit = Math.max(1, Math.min(parseInt(limitRaw || "100", 10) || 100, 500));

    const result = await docClient.send(
      new ScanCommand({
        TableName: tables.workOrder
      })
    );

    let items = result.Items ?? [];

    if (status) {
      items = items.filter((item) => (item.status || "").toUpperCase() === status.toUpperCase());
    }
    if (alertId) {
      items = items.filter((item) => (item.alertId || "").toString().includes(alertId));
    }

    items.sort((a, b) => ((a.createdAt || "") < (b.createdAt || "") ? 1 : -1));
    items = items.slice(0, limit);

    return ok({ items });
  } catch (error) {
    console.error("getWorkOrders error", error);
    return serverError("Failed to load work orders");
  }
};

