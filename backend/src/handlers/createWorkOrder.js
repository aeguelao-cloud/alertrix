"use strict";

const { PutCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { roleCanCreateWorkOrder } = require("../common/policy");
const { ALERT_STATUS } = require("../common/alertStatus");
const { fetchIncidentById, updateIncidentStatus } = require("../common/incidentStore");
const { ok, badRequest, forbidden, notFound, serverError } = require("../common/response");

const makeWorkOrderId = () => {
  const now = Date.now().toString();
  return `WO-${now.slice(-8)}`;
};

exports.handler = async (event) => {
  try {
    const incidentId = event.pathParameters?.alertId;
    if (!incidentId) {
      return badRequest("Missing path parameter: alertId");
    }

    const body = JSON.parse(event.body || "{}");
    const actorRole = body.actorRole || "Operator";
    const assignee = body.assignee || "Emergency Team";
    const note = body.note || "Generated from incident workflow";

    if (!roleCanCreateWorkOrder(actorRole)) {
      return forbidden("Only Admin can create work orders");
    }

    const existingIncident = await fetchIncidentById(incidentId);
    if (!existingIncident) {
      return notFound("Incident not found");
    }

    const workOrderId = makeWorkOrderId();
    const now = new Date().toISOString();

    const workOrder = {
      workOrderId,
      incidentId,
      alertId: incidentId,
      status: "OPEN",
      assignee,
      note,
      createdAt: now,
      createdByRole: actorRole,
    };

    await docClient.send(
      new PutCommand({
        TableName: tables.workOrder,
        Item: workOrder,
      })
    );

    await updateIncidentStatus({
      incidentId,
      status: ALERT_STATUS.ACKNOWLEDGED,
      actorRole,
    });

    await docClient.send(
      new UpdateCommand({
        TableName: tables.incident,
        Key: { incidentId },
        UpdateExpression: "SET workOrderId = :workOrderId, updatedAt = :updatedAt, lastUpdatedAt = :lastUpdatedAt",
        ExpressionAttributeValues: {
          ":workOrderId": workOrderId,
          ":updatedAt": now,
          ":lastUpdatedAt": now,
        },
      })
    );

    return ok({ item: workOrder });
  } catch (error) {
    console.error("createWorkOrder error", error);
    return serverError("Failed to create work order");
  }
};
