"use strict";

const { GetCommand, PutCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { roleCanCreateWorkOrder } = require("../common/policy");
const { ok, badRequest, forbidden, notFound, serverError } = require("../common/response");

const makeWorkOrderId = () => {
  const now = Date.now().toString();
  return `WO-${now.slice(-8)}`;
};

exports.handler = async (event) => {
  try {
    const alertId = event.pathParameters?.alertId;
    if (!alertId) {
      return badRequest("Missing path parameter: alertId");
    }

    const body = JSON.parse(event.body || "{}");
    const actorRole = body.actorRole || "Operator";
    const assignee = body.assignee || "Emergency Team";
    const note = body.note || "Generated from alert workflow";

    if (!roleCanCreateWorkOrder(actorRole)) {
      return forbidden("Only Admin can create work orders");
    }

    const existingAlert = await docClient.send(
      new GetCommand({
        TableName: tables.alert,
        Key: { alertId }
      })
    );

    if (!existingAlert.Item) {
      return notFound("Alert not found");
    }

    const workOrderId = makeWorkOrderId();
    const now = new Date().toISOString();

    const workOrder = {
      workOrderId,
      alertId,
      status: "OPEN",
      assignee,
      note,
      createdAt: now,
      createdByRole: actorRole
    };

    await docClient.send(
      new PutCommand({
        TableName: tables.workOrder,
        Item: workOrder
      })
    );

    await docClient.send(
      new UpdateCommand({
        TableName: tables.alert,
        Key: { alertId },
        UpdateExpression:
          "SET #status = :status, workOrderId = :workOrderId, updatedAt = :updatedAt, updatedByRole = :role",
        ExpressionAttributeNames: { "#status": "status" },
        ExpressionAttributeValues: {
          ":status": "WORK_ORDER_CREATED",
          ":workOrderId": workOrderId,
          ":updatedAt": now,
          ":role": actorRole
        }
      })
    );

    return ok({ item: workOrder });
  } catch (error) {
    console.error("createWorkOrder error", error);
    return serverError("Failed to create work order");
  }
};
