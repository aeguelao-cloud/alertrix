"use strict";

const { ok, badRequest, serverError } = require("../common/response");
const { saveBuzzerSilence } = require("../common/buzzerSilenceSettings");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const headers = event.headers || {};
    const headerRole = headers["x-user-role"] || headers["X-User-Role"] || "";
    const headerUserId = headers["x-user-id"] || headers["X-User-Id"] || "";
    const actorRole = String(body.actorRole || headerRole || "User").trim();
    const requestedBy = String(body.requestedBy || headerUserId || "unknown").trim();
    const zone = body.zone;
    const durationSeconds = body.durationSeconds;

    if (zone !== undefined && String(zone).trim().length == 0) {
      return badRequest("Invalid zone");
    }

    if (durationSeconds !== undefined) {
      const numericDuration = Number(durationSeconds);
      if (!Number.isFinite(numericDuration)) {
        return badRequest("Invalid durationSeconds");
      }
    }

    // Both Admin and User can silence buzzer for on-site safety.
    if (!["Admin", "User"].includes(actorRole)) {
      return badRequest("Invalid actorRole");
    }

    const state = await saveBuzzerSilence({ zone, durationSeconds, requestedBy });
    return ok({
      message: "Buzzer silenced",
      actorRole,
      ...state,
    });
  } catch (error) {
    console.error("silenceBuzzer error", error);
    return serverError("Failed to silence buzzer");
  }
};
