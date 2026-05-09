"use strict";

const { listActiveAdminEmails } = require("./admins");

async function resolveAlertRecipients() {
  const adminEmails = await listActiveAdminEmails();
  if (adminEmails.length === 0) {
    const fallback = String(process.env.ALERT_FROM_EMAIL || "").trim().toLowerCase();
    if (fallback) {
      return { adminEmails: [fallback], toAddresses: [fallback] };
    }
  }
  return {
    adminEmails,
    toAddresses: adminEmails,
  };
}

module.exports = {
  resolveAlertRecipients,
};
