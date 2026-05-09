"use strict";

const { ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { isEmailValid } = require("./auth");
const { docClient, tables } = require("./dynamo");
const { listActiveAdminEmails } = require("./admins");

async function resolveAlertRecipients({ severity } = {}) {
  const adminEmails = await listActiveAdminEmails();
  const userEmails = await listActiveUserNotificationEmails({ severity });
  const all = dedupeEmails([...adminEmails, ...userEmails]);

  if (all.length === 0) {
    const fallback = String(process.env.ALERT_FROM_EMAIL || "").trim().toLowerCase();
    if (fallback) {
      return { adminEmails: [fallback], toAddresses: [fallback] };
    }
  }
  return {
    adminEmails,
    userEmails,
    toAddresses: all,
  };
}

async function listActiveUserNotificationEmails({ severity } = {}) {
  const tableName = tables.userProfile;
  if (!tableName) return [];

  const result = await docClient.send(
    new ScanCommand({
      TableName: tableName,
      ProjectionExpression: "userId, notificationEmail, pushRule",
    })
  );

  const level = String(severity || "NORMAL").trim().toUpperCase();

  return (result.Items || [])
    .filter((item) => shouldSendByRule(item.pushRule, level))
    .map((item) => String(item.notificationEmail || "").trim().toLowerCase())
    .filter((email) => isEmailValid(email));
}

function shouldSendByRule(rawRule, severity) {
  const rule = String(rawRule || "Warning + Critical").trim();
  if (rule === "Disabled") return false;
  if (rule === "Critical only") return severity === "CRITICAL";
  return severity === "CRITICAL" || severity === "WARNING";
}

function dedupeEmails(list) {
  const seen = new Set();
  const out = [];
  for (const raw of list) {
    const email = String(raw || "").trim().toLowerCase();
    if (!isEmailValid(email)) continue;
    if (seen.has(email)) continue;
    seen.add(email);
    out.push(email);
  }
  return out;
}

module.exports = {
  resolveAlertRecipients,
};
