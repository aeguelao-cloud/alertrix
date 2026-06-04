"use strict";

const { SESv2Client, SendEmailCommand } = require("@aws-sdk/client-sesv2");
const { buildAlertEmailContent } = require("../src/common/emailNotifier");
const { buildVerificationEmailContent } = require("../src/common/verificationEmail");
const { buildSettingsChangeEmailContent } = require("../src/common/settingsChangeEmail");

const region = process.env.VERIFICATION_SES_REGION || process.env.AWS_REGION || "ap-southeast-5";
const fromEmail = String(process.env.ALERT_FROM_EMAIL || "").trim();
const recipients = parseRecipients(process.env.TEST_EMAIL_TO);
const delayMs = Number(process.env.TEST_EMAIL_DELAY_MS || 1200);
const ses = new SESv2Client({ region });

async function main() {
  if (!fromEmail) {
    throw new Error("Missing ALERT_FROM_EMAIL");
  }
  if (recipients.length === 0) {
    throw new Error("Missing TEST_EMAIL_TO");
  }

  const mails = buildAllEmails();
  const results = [];

  for (const mail of mails) {
    const result = await ses.send(
      new SendEmailCommand({
        FromEmailAddress: fromEmail,
        Destination: {
          ToAddresses: recipients,
        },
        Content: {
          Simple: {
            Subject: { Data: mail.subject },
            Body: {
              Text: { Data: mail.body },
            },
          },
        },
      })
    );

    results.push({
      case: mail.caseName,
      subject: mail.subject,
      messageId: result?.MessageId || null,
    });

    console.log(`[sent] ${mail.caseName} -> ${result?.MessageId || "no-message-id"}`);
    await sleep(delayMs);
  }

  console.log(JSON.stringify({
    fromEmail,
    recipients,
    sent: results.length,
    results,
  }, null, 2));
}

function buildAllEmails() {
  const mails = [];

  const registerMail = buildVerificationEmailContent({
    code: "123456",
    name: "Demo User",
    purpose: "register",
  });
  mails.push({
    caseName: "Account Registration Verification",
    subject: registerMail.subject,
    body: registerMail.textBody,
  });

  const resetMail = buildVerificationEmailContent({
    code: "654321",
    name: "Demo User",
    purpose: "reset",
  });
  mails.push({
    caseName: "Password Reset Verification",
    subject: resetMail.subject,
    body: resetMail.textBody,
  });

  const base = {
    alertId: "INC-20260602-EXAMPLE",
    zone: "Zone A - Pump Station",
    location: "Main Pump House",
    capturedAt: "2026-06-02T10:30:00Z",
    recipients,
  };

  const alertCases = [
    { label: "Water Level WARNING", sensorType: "waterLevel", severity: "WARNING", value: 72, threshold: 70, unit: "cm" },
    { label: "Water Level CRITICAL", sensorType: "waterLevel", severity: "CRITICAL", value: 89, threshold: 85, unit: "cm" },
    { label: "Vibration WARNING", sensorType: "vibration", severity: "WARNING", value: 3.2, threshold: 2.8, unit: "g" },
    { label: "Vibration CRITICAL", sensorType: "vibration", severity: "CRITICAL", value: 4.5, threshold: 4.0, unit: "g" },
    { label: "Temperature WARNING", sensorType: "temperature", severity: "WARNING", value: 35.8, threshold: 35, unit: "C" },
    { label: "Temperature CRITICAL", sensorType: "temperature", severity: "CRITICAL", value: 41.2, threshold: 40, unit: "C" },
    { label: "Humidity WARNING", sensorType: "humidity", severity: "WARNING", value: 81, threshold: 80, unit: "%" },
    { label: "Humidity CRITICAL", sensorType: "humidity", severity: "CRITICAL", value: 91, threshold: 90, unit: "%" },
    { label: "Combined Temp+Humidity WARNING", sensorType: "temperatureHumidityCombined", severity: "WARNING", value: "Temp 36, Humidity 82", threshold: "warning profile", unit: "" },
    { label: "Combined Temp+Humidity CRITICAL", sensorType: "temperatureHumidityCombined", severity: "CRITICAL", value: "Temp 41, Humidity 92", threshold: "critical profile", unit: "" },
    { label: "Device Offline WARNING", sensorType: "deviceOffline", severity: "WARNING", value: "No telemetry", threshold: null, unit: "" },
    { label: "Sensor Fault WARNING", sensorType: "sensorFault", severity: "WARNING", value: "Invalid/out-of-range", threshold: null, unit: "" },
  ];

  for (const item of alertCases) {
    const rendered = buildAlertEmailContent({
      ...base,
      alertId: `${base.alertId}-${item.severity}`,
      sensorType: item.sensorType,
      severity: item.severity,
      value: item.value,
      threshold: item.threshold,
      unit: item.unit,
    });
    mails.push({
      caseName: item.label,
      subject: rendered.subject,
      body: rendered.body,
    });
  }

  const notificationMail = buildSettingsChangeEmailContent({
    userId: "operator01@example.com",
    role: "User",
    changedAt: "2026-06-02T10:45:00Z",
    changes: [
      { field: "pushRule", from: "Disabled", to: "Warning + Critical" },
      { field: "alertSoundEnabled", from: false, to: true },
      { field: "notificationEmail", from: "", to: "operator01@example.com" },
    ],
  });
  mails.push({
    caseName: "Notification Settings Updated",
    subject: notificationMail.subject,
    body: notificationMail.textBody,
  });

  const systemMail = buildSettingsChangeEmailContent({
    userId: "admin01@example.com",
    role: "Admin",
    changedAt: "2026-06-02T10:50:00Z",
    changes: [
      { field: "siteName", from: "Alertrix Site", to: "Alertrix Main Site" },
      { field: "autoRefreshIntervalSeconds", from: 30, to: 15 },
      { field: "waterLevel.warning", from: 70, to: 72 },
      { field: "waterLevel.critical", from: 85, to: 88 },
      { field: "temperature.warning", from: 35, to: 36 },
      { field: "temperature.critical", from: 40, to: 42 },
    ],
  });
  mails.push({
    caseName: "System Settings Updated",
    subject: systemMail.subject,
    body: systemMail.textBody,
  });

  return mails;
}

function parseRecipients(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
