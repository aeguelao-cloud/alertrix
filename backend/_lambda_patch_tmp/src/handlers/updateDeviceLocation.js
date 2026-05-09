"use strict";

const { ok, badRequest, serverError } = require("../common/response");
const { saveDeviceLocation } = require("../common/deviceLocationSettings");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const location = body.location;
    if (typeof location !== "string" || !location.trim()) {
      return badRequest("location is required");
    }

    const saved = await saveDeviceLocation(location);
    return ok(saved);
  } catch (error) {
    console.error("updateDeviceLocation error", error);
    return serverError("Failed to update device location");
  }
};

