"use strict";

const { GetCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { allowedStatus, roleCanIgnore } = require("../common/policy");
const { ok, badRequest, forbidden, notFound, serverError } = require("../common/response");

exports.handler = async (event) => {
  try {
    const alertId = event.pathParameters?.alertId;
    if (!alertId) {
      return badRequest("Missing path parameter: alertId");
    }

    const body = JSON.parse(event.body || "{}");
    const status = body.status;
    const actorRole = body.actorRole || "Operator";

    if (!allowedStatus.includes(status)) {
      return badRequest("Invalid status");
    }

    if (status === "IGNORED" && !roleCanIgnore(actorRole)) {
      return forbidden("Only Admin can ignore alerts");
    }

    const existing = await docClient.send(
      new GetCommand({
        TableName: tables.alert,
        Key: { alertId }
      })
    );

    if (!existing.Item) {
      return notFound("Alert not found");
    }

    const updated = await docClient.send(
      new UpdateCommand({
        TableName: tables.alert,
        Key: { alertId },
        UpdateExpression: "SET #status = :status, updatedAt = :updatedAt, updatedByRole = :role",
        ExpressionAttributeNames: { "#status": "status" },
        ExpressionAttributeValues: {
          ":status": status,
          ":updatedAt": new Date().toISOString(),
          ":role": actorRole
        },
        ReturnValues: "ALL_NEW"
      })
    );

    return ok({ item: updated.Attributes });
  } catch (error) {
    console.error("updateAlertStatus error", error);
    return serverError("Failed to update alert status");
  }
};
