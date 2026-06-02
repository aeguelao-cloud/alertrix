"use strict";

const { ok, serverError } = require("../common/response");
const { getSystemSettings } = require("../common/systemSettings");
const { loadThresholdConfig } = require("../common/thresholds");

exports.handler = async () => {
  try {
    const [system, thresholds] = await Promise.all([
      getSystemSettings(),
      loadThresholdConfig(),
    ]);
    return ok({
      ...system,
      thresholds,
    });
  } catch (error) {
    console.error("getSystemSettings error", error);
    return serverError("Failed to fetch system settings");
  }
};
