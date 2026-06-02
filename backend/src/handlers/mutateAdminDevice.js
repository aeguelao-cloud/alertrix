"use strict";

const { badRequest, notFound, ok, serverError } = require("../common/response");
const { ensureAdminRequest } = require("../common/adminAuth");
const {
  registerDevice,
  updateDevice,
  setDeviceStatus,
  recordDeviceTest,
} = require("../common/deviceRegistry");

exports.handler = async (event) => {
  try {
    const gate = ensureAdminRequest(event);
    if (!gate.ok) return gate.response;

    const body = JSON.parse(event.body || "{}");
    const action = String(body.action || "").trim().toLowerCase();
    if (!action) return badRequest("action is required");

    if (action === "register") {
      const item = await registerDevice(body, gate.actor);
      return ok({ action: "register", item });
    }

    const deviceId = String(body.deviceId || "").trim();
    if (!deviceId) return badRequest("deviceId is required");

    if (action === "edit") {
      const item = await updateDevice(deviceId, body, gate.actor);
      if (!item) return notFound("Device not found");
      return ok({ action: "edit", item });
    }

    if (action === "disable") {
      const item = await setDeviceStatus(deviceId, "disabled", gate.actor);
      if (!item) return notFound("Device not found");
      return ok({ action: "disable", item });
    }

    if (action === "enable") {
      const item = await setDeviceStatus(deviceId, "active", gate.actor);
      if (!item) return notFound("Device not found");
      return ok({ action: "enable", item });
    }

    if (action === "test") {
      const item = await recordDeviceTest(deviceId, gate.actor);
      if (!item) return notFound("Device not found");
      return ok({
        action: "test",
        item,
        message: "Telemetry test requested. Verify latest sync and heartbeat.",
      });
    }

    return badRequest("Unsupported action");
  } catch (error) {
    console.error("mutateAdminDevice error", error);
    if (error.code === "BAD_INPUT") {
      return badRequest(error.message);
    }
    return serverError("Failed to update device");
  }
};
