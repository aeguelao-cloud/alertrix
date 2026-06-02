"use strict";

const { allowedStatus, roleCanIgnore } = require("../common/policy");
const { ALERT_STATUS, normalizeAlertStatus } = require("../common/alertStatus");
const { updateIncidentStatus } = require("../common/incidentStore");
const { ok, badRequest, forbidden, notFound, serverError } = require("../common/response");

const LEGACY_STATUS_INPUTS = new Set(["OPEN", "CONFIRMED", "IGNORED", "WORK_ORDER_CREATED"]);

exports.handler = async (event) => {
  try {
    const incidentId = event.pathParameters?.alertId;
    if (!incidentId) {
      return badRequest("Missing path parameter: alertId");
    }

    const body = JSON.parse(event.body || "{}");
    const rawStatus = String(body.status || "").trim().toUpperCase();
    const actorRole = body.actorRole || "Operator";

    if (!rawStatus) {
      return badRequest("Missing status");
    }
    if (!allowedStatus.includes(rawStatus) && !LEGACY_STATUS_INPUTS.has(rawStatus)) {
      return badRequest("Invalid status");
    }

    const status = normalizeAlertStatus(rawStatus, ALERT_STATUS.ACTIVE);
    if (status === ALERT_STATUS.CLOSED && !roleCanIgnore(actorRole)) {
      return forbidden("Only Admin can close alerts as false alarms");
    }

    const updated = await updateIncidentStatus({
      incidentId,
      status,
      actorRole,
    });
    if (!updated) return notFound("Incident not found");

    return ok({
      item: {
        ...updated,
        alertId: updated.incidentId,
      },
    });
  } catch (error) {
    console.error("updateAlertStatus error", error);
    return serverError("Failed to update alert status");
  }
};
