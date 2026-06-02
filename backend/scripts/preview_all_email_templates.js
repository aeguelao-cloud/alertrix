"use strict";

const { buildAlertEmailContent } = require("../src/common/emailNotifier");
const { buildVerificationEmailContent } = require("../src/common/verificationEmail");
const { buildSettingsChangeEmailContent } = require("../src/common/settingsChangeEmail");

const lines = [];

function section(title) {
  lines.push("");
  lines.push("=".repeat(88));
  lines.push(title);
  lines.push("=".repeat(88));
}

function mailBlock(title, subject, body) {
  lines.push("");
  lines.push("-".repeat(88));
  lines.push(title);
  lines.push("-".repeat(88));
  lines.push(`Subject: ${subject}`);
  lines.push("");
  lines.push(body);
}

section("Alertrix Email Preview - All Current Email Possibilities");
lines.push("Note: NORMAL sensor readings do not send emails.");
lines.push("Note: RECOVERED email is optional in design and is not currently triggered in code.");

section("Verification Emails");
{
  const registerMail = buildVerificationEmailContent({
    code: "123456",
    name: "Demo User",
    purpose: "register",
  });
  mailBlock("Case: Account Registration Verification", registerMail.subject, registerMail.textBody);

  const resetMail = buildVerificationEmailContent({
    code: "654321",
    name: "Demo User",
    purpose: "reset",
  });
  mailBlock("Case: Password Reset Verification", resetMail.subject, resetMail.textBody);
}

section("Alert Emails");
{
  const base = {
    alertId: "INC-20260602-EXAMPLE",
    zone: "Zone A - Pump Station",
    location: "Main Pump House",
    capturedAt: "2026-06-02T10:30:00Z",
    recipients: ["admin1@example.com", "admin2@example.com"],
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
    mailBlock(`Case: ${item.label}`, rendered.subject, rendered.body);
  }
}

section("Settings Change Emails");
{
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
  mailBlock("Case: Notification Settings Updated", notificationMail.subject, notificationMail.textBody);

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
  mailBlock("Case: System Settings Updated", systemMail.subject, systemMail.textBody);
}

console.log(lines.join("\n"));
