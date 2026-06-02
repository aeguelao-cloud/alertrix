"use strict";

const { badRequest, notFound, ok, serverError } = require("../common/response");
const { ensureSuperAdminRequest } = require("../common/adminAuth");
const { deleteAdmin, getAdminById, listAdmins } = require("../common/admins");

exports.handler = async (event) => {
  try {
    const gate = ensureSuperAdminRequest(event);
    if (!gate.ok) return gate.response;

    const adminId = event.pathParameters?.adminId;
    if (!adminId) return badRequest("Missing path parameter: adminId");

    const target = await getAdminById(adminId);
    if (!target) return notFound("Admin not found");
    if (isActorTarget(gate.actor, target.email)) {
      return badRequest("Cannot delete yourself.");
    }

    const allAdmins = await listAdmins();
    const activeCount = allAdmins.filter((item) => String(item.status || "").toLowerCase() === "active").length;
    if (String(target.status || "").toLowerCase() === "active" && activeCount <= 1) {
      return badRequest("Cannot delete the last active admin.");
    }

    const removed = await deleteAdmin(adminId);
    if (!removed) return notFound("Admin not found");
    return ok({ deleted: true, adminId });
  } catch (error) {
    console.error("deleteAdmin error", error);
    return serverError("Failed to delete admin");
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
