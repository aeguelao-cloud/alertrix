"use strict";

const { ok, serverError } = require("../common/response");
const { ensureAdminRequest } = require("../common/adminAuth");
const { listAdmins } = require("../common/admins");

exports.handler = async (event) => {
  try {
    const gate = ensureAdminRequest(event);
    if (!gate.ok) return gate.response;

    const items = await listAdmins();
    return ok({ items });
  } catch (error) {
    console.error("getAdmins error", error);
    return serverError("Failed to fetch admins");
  }
};

