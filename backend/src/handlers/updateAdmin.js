"use strict";

const { badRequest, notFound, ok, serverError } = require("../common/response");
const { ensureSuperAdminRequest } = require("../common/adminAuth");
const { updateAdmin } = require("../common/admins");

exports.handler = async (event) => {
  try {
    const gate = ensureSuperAdminRequest(event);
    if (!gate.ok) return gate.response;

    const adminId = event.pathParameters?.adminId;
    if (!adminId) return badRequest("Missing path parameter: adminId");

    const body = JSON.parse(event.body || "{}");
    const item = await updateAdmin(adminId, body, gate.actor);
    if (!item) return notFound("Admin not found");
    return ok({ item });
  } catch (error) {
    console.error("updateAdmin error", error);
    if (error.code === "BAD_INPUT" || error.code === "DUPLICATE_EMAIL") {
      return badRequest(error.message);
    }
    return serverError("Failed to update admin");
  }
};
