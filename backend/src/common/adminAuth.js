"use strict";

const { forbidden } = require("./response");
const { isAdminRole } = require("./policy");

function parseInternalAdminIds() {
  const raw =
    process.env.INTERNAL_ADMIN_USER_IDS ||
    process.env.INTERNAL_ADMIN_USER ||
    process.env.ADMIN_EMAIL ||
    "admin@alertrix.local";
  const entries = String(raw)
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);

  const aliases = [];
  for (const id of entries) {
    aliases.push(id);
    const at = id.indexOf("@");
    if (at > 0) {
      aliases.push(id.slice(0, at));
    }
  }
  return Array.from(new Set(aliases));
}

function ensureAdminRequest(event) {
  const headers = event.headers || {};
  const role = String(headers["x-user-role"] || headers["X-User-Role"] || "").trim();
  const actor = String(headers["x-user-id"] || headers["X-User-Id"] || "").trim().toLowerCase();

  if (!isAdminRole(role)) {
    return {
      ok: false,
      response: forbidden("Admin access required"),
      actor: null,
    };
  }

  const internalAdminIds = parseInternalAdminIds();
  if (!internalAdminIds.includes(actor)) {
    return {
      ok: false,
      response: forbidden("Internal admin account required"),
      actor: null,
    };
  }

  return { ok: true, actor };
}

module.exports = {
  ensureAdminRequest,
};
