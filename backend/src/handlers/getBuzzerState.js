"use strict";

const { ok, serverError } = require("../common/response");
const { getBuzzerSilenceState } = require("../common/buzzerSilenceSettings");

exports.handler = async (event) => {
  try {
    const zone = event.queryStringParameters?.zone;
    const state = await getBuzzerSilenceState({ zone });
    return ok(state);
  } catch (error) {
    console.error("getBuzzerState error", error);
    return serverError("Failed to fetch buzzer state");
  }
};