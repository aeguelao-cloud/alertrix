"use strict";

const { badRequest, notFound, ok, serverError } = require("../common/response");
const { ensureSuperAdminRequest } = require("../common/adminAuth");
const { updateAdmin, getAdminById, listAdmins } = require("../common/admins");

exports.handler = async (event) => {
  try {
    const gate = ensureSuperAdminRequest(event);
    if (!gate.ok) return gate.response;

    const adminId = event.pathParameters?.adminId;
    if (!adminId) return badRequest("Missing path parameter: adminId");

    const body = JSON.parse(event.body || "{}");
    const target = await getAdminById(adminId);
    if (!target) return notFound("Admin not found");
    if (body.status !== undefined) {
      const nextStatus = String(body.status || "").trim().toLowerCase();
      if (nextStatus === "inactive" && isActorTarget(gate.actor, target.email)) {
        return badRequest("Cannot deactivate yourself.");
      }
      if (nextStatus === "inactive") {
        const allAdmins = await listAdmins();
        const activeCount = allAdmins.filter((item) => String(item.status || "").toLowerCase() === "active").length;
        if (String(target.status || "").toLowerCase() === "active" && activeCount <= 1) {
          return badRequest("Cannot deactivate the last active admin.");
        }
      }
    }
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

function isActorTarget(actor, email) {
  const a = String(actor || "").trim().toLowerCase();
  const e = String(email || "").trim().toLowerCase();
  if (!a || !e) return false;
  if (a === e) return true;
  const at = e.indexOf("@");
  return at > 0 && a === e.slice(0, at);
}
