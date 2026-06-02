"use strict";

const { ok, serverError } = require("../common/response");
const { ensureAdminRequest } = require("../common/adminAuth");
const { listDevices } = require("../common/deviceRegistry");

exports.handler = async (event) => {
  try {
    const gate = ensureAdminRequest(event);
    if (!gate.ok) return gate.response;

    const items = await listDevices();
    return ok({
      items,
      capabilities: {
        register: true,
        editLocation: true,
        testTelemetry: true,
        disable: true,
        heartbeat: true,
      },
    });
  } catch (error) {
    console.error("getAdminDevices error", error);
    return serverError("Failed to load devices");
  }
};
