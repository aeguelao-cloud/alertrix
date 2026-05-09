"use strict";

const { GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { sendNotificationToAll } = require("../common/fcm");
const { sendAlertEmail } = require("../common/emailNotifier");
const { ok, badRequest, serverError } = require("../common/response");

const EMAIL_COOLDOWN_SECONDS = Number(process.env.EMAIL_COOLDOWN_SECONDS || 600);

const thresholds = {
  waterLevel: { warning: 70, critical: 85, unit: "%" },
  vibration: { warning: 2.8, critical: 4.0, unit: "mm/s RMS" },
  temperature: { warning: 35, critical: 40, unit: "°C" }
};

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const sensorType = body.sensorType;
    const value = Number(body.value);
    const zone = body.zone || "Unknown Zone";
    const capturedAt = body.capturedAt || new Date().toISOString();

    if (!sensorType || Number.isNaN(value)) {
      return badRequest("Missing sensorType or numeric value");
    }

    await docClient.send(
      new PutCommand({
        TableName: tables.sensor,
        Item: {
          sensorType,
          capturedAt,
          value,
          zone
        }
      })
    );

    const threshold = thresholds[sensorType];
    if (!threshold) {
      return ok({ stored: true, alertGenerated: false, message: "Sensor stored without threshold profile" });
    }

    let severity = "NORMAL";
    if (value >= threshold.critical) severity = "CRITICAL";
    else if (value >= threshold.warning) severity = "WARNING";

    if (severity === "NORMAL") {
      return ok({ stored: true, alertGenerated: false, severity });
    }

    const alertId = `ALERT-${Date.now()}`;
    const alertItem = {
      alertId,
      title: `${sensorType} threshold exceeded`,
      severity,
      status: "ACTIVE",
      detectedAt: capturedAt,
      zone,
      triggerValue: `${value}${threshold.unit}`
    };

    await docClient.send(
      new PutCommand({
        TableName: tables.alert,
        Item: alertItem
      })
    );

    let pushResult = null;
    try {
      pushResult = await sendNotificationToAll({
        title: `Alertrix ${severity} Alert`,
        body: `${sensorType} at ${zone} reached ${value}${threshold.unit}`,
        data: {
          alertId,
          sensorType,
          severity
        }
      });
    } catch (error) {
      console.error("FCM push failed", error);
      pushResult = { successCount: 0, failureCount: 0, reason: "FCM push failed" };
    }

    let emailResult = null;
    const emailGate = await shouldSendEmailNow({ sensorType, zone, severity, capturedAt });
    if (!emailGate.allowed) {
      emailResult = {
        delivered: false,
        suppressed: true,
        reason: "Email cooldown active",
        nextSendAt: emailGate.nextSendAt,
      };
    } else {
      try {
        emailResult = await sendAlertEmail({
          alertId,
          sensorType,
          severity,
          zone,
          value,
          unit: threshold.unit,
          capturedAt
        });
      } catch (error) {
        console.error("Alert email failed", error);
        emailResult = { delivered: false, reason: "Email publish failed" };
      }
    }

    return ok({
      stored: true,
      alertGenerated: true,
      alert: alertItem,
      pushResult,
      emailResult
    });
  } catch (error) {
    console.error("ingestSensorData error", error);
    return serverError("Failed to ingest sensor data");
  }
};

async function shouldSendEmailNow({ sensorType, zone, severity, capturedAt }) {
  if (EMAIL_COOLDOWN_SECONDS <= 0) {
    return { allowed: true };
  }

  const nowMs = Date.parse(capturedAt) || Date.now();
  const key = buildEmailCooldownKey(sensorType, zone, severity);

  const existing = await docClient.send(
    new GetCommand({
      TableName: tables.settings,
      Key: { settingId: key },
    })
  );

  const lastSentAt = existing.Item?.lastSentAt;
  if (lastSentAt) {
    const lastMs = Date.parse(lastSentAt);
    const waitMs = EMAIL_COOLDOWN_SECONDS * 1000 - (nowMs - lastMs);
    if (!Number.isNaN(lastMs) && waitMs > 0) {
      return {
        allowed: false,
        nextSendAt: new Date(nowMs + waitMs).toISOString(),
      };
    }
  }

  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: {
        settingId: key,
        type: "emailCooldown",
        sensorType,
        zone,
        severity,
        lastSentAt: new Date(nowMs).toISOString(),
        updatedAt: new Date().toISOString(),
      },
    })
  );

  return { allowed: true };
}

function buildEmailCooldownKey(sensorType, zone, severity) {
  const s = String(sensorType || "unknown").trim();
  const z = String(zone || "Unknown Zone").trim();
  const lv = String(severity || "UNKNOWN").trim().toUpperCase();
  return `EMAIL_COOLDOWN#${s}#${z}#${lv}`;
}
