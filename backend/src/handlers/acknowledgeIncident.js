"use strict";

const { ALERT_STATUS } = require("../common/alertStatus");
const { updateIncidentStatus } = require("../common/incidentStore");
const { ok, badRequest, notFound, serverError } = require("../common/response");

exports.handler = async (event) => {
  try {
    const incidentId = event.pathParameters?.incidentId;
    if (!incidentId) {
      return badRequest("Missing path parameter: incidentId");
    }

    const body = JSON.parse(event.body || "{}");
    const actorRole = body.actorRole || "Operator";

    const updated = await updateIncidentStatus({
      incidentId,
      status: ALERT_STATUS.ACKNOWLEDGED,
      actorRole,
    });
    if (!updated) return notFound("Incident not found");

    return ok({ item: updated });
  } catch (error) {
    console.error("acknowledgeIncident error", error);
    return serverError("Failed to acknowledge incident");
  }
};
