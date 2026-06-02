"use strict";

const { SESv2Client, SendEmailCommand } = require("@aws-sdk/client-sesv2");

const ses = new SESv2Client({
  region: process.env.VERIFICATION_SES_REGION || process.env.AWS_REGION || "ap-southeast-5",
});

async function sendSettingsChangeEmail({ toEmail, userId, role, changes, changedAt }) {
  const recipient = String(toEmail || "").trim();
  if (!recipient) {
    return { delivered: false, reason: "Missing notification email" };
  }

  const fromEmail = String(process.env.ALERT_FROM_EMAIL || "").trim();
  if (!fromEmail) {
    return { delivered: false, reason: "Missing ALERT_FROM_EMAIL" };
  }

  const { subject, textBody, safeChanges } = buildSettingsChangeEmailContent({
    userId,
    role,
    changes,
    changedAt,
  });
  if (safeChanges.length === 0) {
    return { delivered: false, reason: "No changes detected" };
  }

  const result = await ses.send(
    new SendEmailCommand({
      FromEmailAddress: fromEmail,
      Destination: {
        ToAddresses: [recipient],
      },
      Content: {
        Simple: {
          Subject: { Data: subject },
          Body: {
            Text: { Data: textBody },
          },
        },
      },
    })
  );

  return {
    delivered: true,
    recipient,
    messageId: result?.MessageId || null,
  };
}

function buildSettingsChangeEmailContent({ userId, role, changes, changedAt }) {
  const safeChanges = Array.isArray(changes) ? changes.filter((item) => item && item.field) : [];
  const scope = inferSettingsScope(safeChanges);
  const subject = scope === "system"
    ? "[Alertrix] System settings updated"
    : "[Alertrix] Notification settings updated";

  const textBody = [
    "Alertrix Settings Change Notification",
    "--------------------------------",
    `Scope: ${scope === "system" ? "System settings" : "Notification settings"}`,
    `User: ${String(userId || "").trim() || "unknown"}`,
    `Role: ${String(role || "").trim() || "User"}`,
    `Updated At (UTC): ${changedAt || new Date().toISOString()}`,
    "",
    "Changed fields:",
    ...safeChanges.map((item) => {
      const label = fieldLabel(item.field);
      const from = formatValue(item.from);
      const to = formatValue(item.to);
      return `- ${label}: ${from} -> ${to}`;
    }),
    "",
    "If you did not make this change, please contact your administrator immediately.",
  ].join("\n");

  return { subject, textBody, safeChanges };
}

function inferSettingsScope(changes) {
  const fields = new Set((changes || []).map((item) => String(item.field || "").trim()));
  const systemFields = new Set([
    "autoRefreshIntervalSeconds",
    "defaultTrendWindow",
    "dashboardRefreshMode",
    "siteName",
    "siteDescription",
    "waterLevel.warning",
    "waterLevel.critical",
    "vibration.warning",
    "vibration.critical",
    "temperature.warning",
    "temperature.critical",
  ]);

  for (const field of fields) {
    if (systemFields.has(field)) {
      return "system";
    }
  }
  return "notification";
}

function fieldLabel(field) {
  if (field === "pushRule") return "Push notification policy";
  if (field === "alertSoundEnabled") return "Alert sound";
  if (field === "notificationEmail") return "Notification email";
  if (field === "autoRefreshIntervalSeconds") return "Auto refresh interval (seconds)";
  if (field === "defaultTrendWindow") return "Default trend window";
  if (field === "dashboardRefreshMode") return "Dashboard refresh mode";
  if (field === "siteName") return "Site name";
  if (field === "siteDescription") return "Site description";
  if (field === "waterLevel.warning") return "Water threshold warning";
  if (field === "waterLevel.critical") return "Water threshold critical";
  if (field === "vibration.warning") return "Vibration threshold warning";
  if (field === "vibration.critical") return "Vibration threshold critical";
  if (field === "temperature.warning") return "Temperature threshold warning";
  if (field === "temperature.critical") return "Temperature threshold critical";
  return field;
}

function formatValue(value) {
  if (typeof value === "boolean") {
    return value ? "Enabled" : "Disabled";
  }
  const text = String(value || "").trim();
  return text.length > 0 ? text : "(empty)";
}

module.exports = {
  sendSettingsChangeEmail,
  buildSettingsChangeEmailContent,
};
