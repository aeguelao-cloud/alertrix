"use strict";

const { ok, serverError } = require("../common/response");
const { getDeviceLocation } = require("../common/deviceLocationSettings");

exports.handler = async () => {
  try {
    const payload = await getDeviceLocation();
    return ok(payload);
  } catch (error) {
    console.error("getDeviceLocation error", error);
    return serverError("Failed to fetch device location");
  }
};

