"use strict";

const { badRequest, ok, serverError } = require("../common/response");
const { ensureSuperAdminRequest } = require("../common/adminAuth");
const { createAdmin } = require("../common/admins");

exports.handler = async (event) => {
  try {
    const gate = ensureSuperAdminRequest(event);
    if (!gate.ok) return gate.response;

    const body = JSON.parse(event.body || "{}");
    if (!body.name || !body.email) return badRequest("Missing name or email");

    const item = await createAdmin({
      name: body.name,
      email: body.email,
      role: body.role || "admin",
      status: body.status || "active",
      actor: gate.actor,
    });

    return ok({ item });
  } catch (error) {
    console.error("createAdmin error", error);
    if (error.code === "BAD_INPUT" || error.code === "DUPLICATE_EMAIL") {
      return badRequest(error.message);
    }
    return serverError("Failed to create admin");
  }
};
