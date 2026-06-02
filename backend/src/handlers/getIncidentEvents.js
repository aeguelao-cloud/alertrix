"use strict";

const { QueryCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, badRequest, serverError } = require("../common/response");

exports.handler = async (event) => {
  try {
    const incidentId = event.pathParameters?.incidentId;
    if (!incidentId) {
      return badRequest("Missing path parameter: incidentId");
    }

    const limitRaw = event.queryStringParameters?.limit;
    const limit = Math.max(1, Math.min(Number.parseInt(limitRaw || "200", 10) || 200, 1000));
    const order = String(event.queryStringParameters?.order || "desc").trim().toLowerCase();
    const scanForward = order === "asc";
    const nextToken = parseNextToken(event.queryStringParameters?.nextToken);

    const result = await docClient.send(
      new QueryCommand({
        TableName: tables.sensorEvent,
        KeyConditionExpression: "incidentId = :incidentId",
        ExpressionAttributeValues: {
          ":incidentId": incidentId,
        },
        ScanIndexForward: scanForward,
        Limit: limit,
        ExclusiveStartKey: nextToken || undefined,
      })
    );

    return ok({
      items: result.Items || [],
      nextToken: encodeNextToken(result.LastEvaluatedKey),
    });
  } catch (error) {
    console.error("getIncidentEvents error", error);
    return serverError("Failed to load incident events");
  }
};

function parseNextToken(raw) {
  if (!raw) return null;
  try {
    const json = Buffer.from(String(raw), "base64").toString("utf8");
    return JSON.parse(json);
  } catch (_) {
    return null;
  }
}

function encodeNextToken(key) {
  if (!key) return null;
  return Buffer.from(JSON.stringify(key), "utf8").toString("base64");
}
