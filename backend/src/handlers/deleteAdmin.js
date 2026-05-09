"use strict";

const { badRequest, notFound, ok, serverError } = require("../common/response");
const { ensureAdminRequest } = require("../common/adminAuth");
const { deleteAdmin } = require("../common/admins");

exports.handler = async (event) => {
  try {
    const gate = ensureAdminRequest(event);
    if (!gate.ok) return gate.response;

    const adminId = event.pathParameters?.adminId;
    if (!adminId) return badRequest("Missing path parameter: adminId");

    const removed = await deleteAdmin(adminId);
    if (!removed) return notFound("Admin not found");
    return ok({ deleted: true, adminId });
  } catch (error) {
    console.error("deleteAdmin error", error);
    return serverError("Failed to delete admin");
  }
};

