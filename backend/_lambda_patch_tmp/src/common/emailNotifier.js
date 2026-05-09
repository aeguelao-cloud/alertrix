"use strict";

const { SESv2Client, SendEmailCommand } = require("@aws-sdk/client-sesv2");
const { resolveAlertRecipients } = require("./alertRecipients");

const ses = new SESv2Client({
  region: process.env.VERIFICATION_SES_REGION || process.env.AWS_REGION || "ap-southeast-5",
});

async function sendAlertEmail({ alertId, sensorType, severity, zone, value, unit, capturedAt }) {
  const fromEmail = String(process.env.ALERT_FROM_EMAIL || "").trim();
  if (!fromEmail) {
    return { delivered: false, reason: "Missing ALERT_FROM_EMAIL" };
  }

  const recipients = await resolveAlertRecipients();
  if (!recipients.toAddresses.length) {
    return { delivered: false, reason: "No active admin recipients configured" };
  }

  const localTime = formatLocalTime(capturedAt);
  const subject = `[Alertrix] ${severity} alert - ${sensorType} @ ${zone}`;
  const body = [
    "Alertrix Alert Notification",
    "--------------------------",
    `Alert ID: ${alertId}`,
    `Sensor: ${sensorType}`,
    `Severity: ${severity}`,
    `Zone: ${zone}`,
    `Value: ${value}${unit}`,
    `Local Time: ${localTime}`,
    `Time (UTC): ${capturedAt}`,
    `Recipients: ${recipients.toAddresses.join(", ")}`,
    "Please review the alert in Alertrix Alert Center.",
  ].join("\n");

  await ses.send(
    new SendEmailCommand({
      FromEmailAddress: fromEmail,
      Destination: {
        ToAddresses: recipients.toAddresses,
      },
      Content: {
        Simple: {
          Subject: {
            Data: subject,
          },
          Body: {
            Text: {
              Data: body,
            },
          },
        },
      },
    })
  );

  return { delivered: true, recipients: recipients.toAddresses };
}

function resolveDisplayTimezone() {
  return process.env.ALERT_LOCAL_TIMEZONE || "Asia/Kuala_Lumpur";
}

function formatLocalTime(isoText) {
  const timezone = resolveDisplayTimezone();
  const date = new Date(isoText);
  if (Number.isNaN(date.getTime())) {
    return isoText;
  }

  const datePart = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);

  const timePart = new Intl.DateTimeFormat("en-GB", {
    timeZone: timezone,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(date);

  const offset = formatOffsetByTimezone(date, timezone);
  const city = formatTimezoneCity(timezone);
  return `${datePart} ${timePart} (${offset}, ${city})`;
}

function formatOffsetByTimezone(date, timezone) {
  try {
    const raw = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      timeZoneName: "shortOffset",
    }).formatToParts(date);
    const value = raw.find((item) => item.type === "timeZoneName")?.value || "";
    if (value) {
      return value.replace("GMT", "GMT");
    }
  } catch (_) {
    // Fall through to known defaults below.
  }

  if (timezone === "Asia/Kuala_Lumpur") return "GMT+8";
  return timezone;
}

function formatTimezoneCity(timezone) {
  if (timezone === "Asia/Kuala_Lumpur") return "Kuala Lumpur";
  const parts = timezone.split("/");
  return parts.length > 1 ? parts[1].replaceAll("_", " ") : timezone;
}

module.exports = {
  sendAlertEmail,
};
