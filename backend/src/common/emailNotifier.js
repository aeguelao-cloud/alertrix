"use strict";

const { SESv2Client, SendEmailCommand } = require("@aws-sdk/client-sesv2");
const { resolveAlertRecipients } = require("./alertRecipients");

const ses = new SESv2Client({
  region: process.env.VERIFICATION_SES_REGION || process.env.AWS_REGION || "ap-southeast-5",
});

async function sendAlertEmail({ alertId, sensorType, severity, zone, location, value, unit, threshold, capturedAt }) {
  const fromEmail = String(process.env.ALERT_FROM_EMAIL || "").trim();
  if (!fromEmail) {
    return { delivered: false, reason: "Missing ALERT_FROM_EMAIL" };
  }

  const recipients = await resolveAlertRecipients({ severity });
  if (!recipients.toAddresses.length) {
    return { delivered: false, reason: "No active admin recipients configured" };
  }

  const normalizedSeverity = String(severity || "WARNING").trim().toUpperCase();
  const { subject, body } = buildAlertEmailContent({
    alertId,
    sensorType,
    severity: normalizedSeverity,
    zone,
    location,
    value,
    unit,
    threshold,
    capturedAt,
    recipients: recipients.toAddresses,
  });

  const result = await ses.send(
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

  return {
    delivered: true,
    recipients: recipients.toAddresses,
    messageId: result?.MessageId || null,
  };
}

function buildAlertEmailContent({
  alertId,
  sensorType,
  severity,
  zone,
  location,
  value,
  unit,
  threshold,
  capturedAt,
  recipients,
}) {
  const normalizedSeverity = String(severity || "WARNING").trim().toUpperCase();
  const zoneLabel = String(zone || "Unknown Zone").trim() || "Unknown Zone";
  const locationLabel = String(location || zoneLabel).trim() || zoneLabel;
  const template = resolveAlertTemplate(sensorType, normalizedSeverity, zoneLabel);
  const localTime = formatLocalTime(capturedAt);
  const subject = `[Alertrix] ${normalizedSeverity} alert - ${template.subjectTag} @ ${zoneLabel} - ${locationLabel}`;
  const valueText = formatReading(value, unit);
  const thresholdText = formatReading(threshold, unit);
  const recipientText = Array.isArray(recipients) && recipients.length > 0 ? recipients.join(", ") : "(none)";

  const body = [
    "Alertrix Alert Notification",
    "--------------------------------",
    `Alert ID: ${alertId}`,
    `Sensor: ${template.sensorLabel}`,
    `Severity: ${normalizedSeverity}`,
    `Zone: ${zoneLabel}`,
    `Location: ${locationLabel}`,
    `Value: ${valueText}`,
    `Threshold: ${thresholdText}`,
    `Local Time: ${localTime}`,
    `Time (UTC): ${capturedAt}`,
    `Recipients: ${recipientText}`,
    "",
    "Summary:",
    template.summary,
    "",
    "Recommended Action:",
    template.recommendedAction,
    "",
    "Please review the alert in Alertrix Alert Center.",
  ].join("\n");

  return { subject, body };
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

function resolveAlertTemplate(sensorType, severity, zone) {
  const sensorKey = normalizeSensorKey(sensorType);
  const level = String(severity || "WARNING").trim().toUpperCase();
  const sensorLabel = sensorLabelForKey(sensorKey);

  const templates = {
    vibration: {
      WARNING: {
        subjectTag: "vibration",
        summary: `Abnormal vibration has been detected at ${zone}. The current vibration level is above the warning threshold but has not reached the critical level.`,
        recommendedAction:
          "Inspect the affected area or equipment within the next few minutes. Check for pump imbalance, loose mounting, external impact, or unusual machine operation.",
      },
      CRITICAL: {
        subjectTag: "severe vibration",
        summary:
          `Severe vibration has been detected at ${zone}. The reading has exceeded the critical threshold and may indicate equipment failure, structural instability, or hazardous movement.`,
        recommendedAction:
          "Take immediate action. Stop nearby equipment if safe to do so, restrict access to the affected area, and dispatch maintenance or emergency personnel for urgent inspection.",
      },
    },
    water: {
      WARNING: {
        subjectTag: "rising water level",
        summary:
          `The water level at ${zone} has exceeded the warning threshold. This may indicate early flood risk or abnormal water accumulation.`,
        recommendedAction:
          "Monitor the water level closely. Prepare for possible escalation and inspect the drainage, riverbank, tank, or monitored water area if accessible.",
      },
      CRITICAL: {
        subjectTag: "dangerous water level",
        summary:
          `The water level at ${zone} has exceeded the critical threshold. Flooding, overflow, or unsafe water accumulation may occur if the level continues to rise.`,
        recommendedAction:
          "Take immediate safety action. Notify responsible personnel, avoid entering the affected area, and initiate evacuation or flood response procedures if required.",
      },
    },
    temperature: {
      WARNING: {
        subjectTag: "high temperature",
        summary:
          `The temperature at ${zone} has exceeded the warning threshold. This may indicate an abnormal environmental condition or early heat-related risk.`,
        recommendedAction:
          "Inspect the monitored area and check for possible heat sources, ventilation problems, electrical overheating, or environmental changes.",
      },
      CRITICAL: {
        subjectTag: "extreme temperature",
        summary:
          `The temperature at ${zone} has exceeded the critical threshold. This may indicate a dangerous heat condition, possible equipment overheating, or fire-related risk.`,
        recommendedAction:
          "Take immediate action. Avoid unnecessary access to the affected area, inspect for fire or overheating sources, and contact responsible personnel immediately.",
      },
    },
    humidity: {
      WARNING: {
        subjectTag: "abnormal humidity",
        summary:
          `The humidity level at ${zone} has exceeded the warning threshold. This may indicate environmental instability, moisture buildup, or possible water intrusion.`,
        recommendedAction:
          "Inspect the monitored area for condensation, leakage, poor ventilation, or early signs of water accumulation.",
      },
      CRITICAL: {
        subjectTag: "extreme humidity",
        summary:
          `The humidity level at ${zone} has exceeded the critical threshold. This may indicate serious moisture exposure, flooding risk, or unsafe environmental conditions.`,
        recommendedAction:
          "Take immediate action. Inspect the area for leakage or flooding, protect sensitive equipment, and notify the responsible personnel.",
      },
    },
    environment: {
      WARNING: {
        subjectTag: "abnormal environment",
        summary:
          `Both temperature and humidity readings at ${zone} have exceeded warning levels. This may indicate an abnormal environmental condition that requires attention.`,
        recommendedAction:
          "Inspect the area for poor ventilation, moisture accumulation, overheating, or possible equipment/environmental issues.",
      },
      CRITICAL: {
        subjectTag: "hazardous environment",
        summary:
          `Temperature and humidity readings at ${zone} have exceeded critical levels. The monitored environment may be unsafe or unstable.`,
        recommendedAction:
          "Take immediate action. Restrict access if necessary, inspect for overheating, leakage, or flooding, and notify responsible personnel immediately.",
      },
    },
    offline: {
      WARNING: {
        subjectTag: "device offline",
        summary:
          `The device at ${zone} has stopped sending telemetry data. The system cannot confirm the current safety condition of the monitored area.`,
        recommendedAction:
          "Check the device power supply, Wi-Fi connection, MQTT connection, and physical condition of the sensor node.",
      },
    },
    fault: {
      WARNING: {
        subjectTag: "sensor fault",
        summary:
          `The sensor at ${zone} is reporting invalid, missing, or out-of-range data. The reading may not represent the actual environmental condition.`,
        recommendedAction:
          "Inspect the sensor wiring, calibration, power supply, and physical placement. Replace or recalibrate the sensor if necessary.",
      },
    },
  };

  const selected = templates[sensorKey]?.[level];
  if (selected) {
    return {
      sensorLabel,
      subjectTag: selected.subjectTag,
      summary: selected.summary,
      recommendedAction: selected.recommendedAction,
    };
  }

  return {
    sensorLabel,
    subjectTag: sensorLabel.toLowerCase(),
    summary: `An abnormal ${sensorLabel.toLowerCase()} reading has been detected at ${zone}.`,
    recommendedAction:
      "Review the monitored area immediately and follow the established safety response procedure.",
  };
}

function normalizeSensorKey(sensorType) {
  const raw = String(sensorType || "").trim().toLowerCase();
  if (raw.includes("water")) return "water";
  if (raw.includes("vibration")) return "vibration";
  if (raw.includes("temp") && raw.includes("humid")) return "environment";
  if (raw.includes("temperature")) return "temperature";
  if (raw.includes("humidity")) return "humidity";
  if (raw.includes("offline")) return "offline";
  if (raw.includes("fault")) return "fault";
  return raw || "sensor";
}

function sensorLabelForKey(sensorKey) {
  if (sensorKey === "water") return "Water Level Sensor";
  if (sensorKey === "vibration") return "Vibration Sensor";
  if (sensorKey === "temperature") return "Temperature Sensor";
  if (sensorKey === "humidity") return "Humidity Sensor";
  if (sensorKey === "environment") return "Combined Temperature + Humidity";
  if (sensorKey === "offline") return "Device Offline";
  if (sensorKey === "fault") return "Sensor Fault";
  return "Sensor";
}

function formatReading(value, unit) {
  const hasValue = value !== undefined && value !== null && String(value).trim() !== "";
  if (!hasValue) {
    return "N/A";
  }
  const number = Number(value);
  const rendered = Number.isNaN(number) ? String(value).trim() : String(number);
  const suffix = String(unit || "").trim();
  return suffix ? `${rendered} ${suffix}` : rendered;
}

module.exports = {
  sendAlertEmail,
  buildAlertEmailContent,
};
