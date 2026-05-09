"use strict";

const { GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("./dynamo");

const DEFAULT_ZONE = "Zone A - Pump Station";
const DEFAULT_DURATION_SECONDS = 120;
const MAX_DURATION_SECONDS = 3600;
const SETTING_PREFIX = "buzzer-silence:";

function normalizeZone(zone) {
  const clean = String(zone || "").trim();
  return clean || DEFAULT_ZONE;
}

function normalizeDurationSeconds(raw) {
  if (raw === undefined || raw === null || raw === "") {
    return DEFAULT_DURATION_SECONDS;
  }
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) {
    return DEFAULT_DURATION_SECONDS;
  }
  const rounded = Math.round(parsed);
  if (rounded < 0) return 0;
  if (rounded > MAX_DURATION_SECONDS) return MAX_DURATION_SECONDS;
  return rounded;
}

function settingIdForZone(zone) {
  return `${SETTING_PREFIX}${zone}`;
}

function parseIsoDate(raw) {
  const text = String(raw || "").trim();
  if (!text) return null;
  const parsed = new Date(text);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

async function getBuzzerSilenceState({ zone }) {
  const zoneName = normalizeZone(zone);
  const settingId = settingIdForZone(zoneName);
  const result = await docClient.send(
    new GetCommand({
      TableName: tables.settings,
      Key: { settingId },
    })
  );

  const item = result.Item || {};
  const nowMs = Date.now();
  const silencedUntilDate = parseIsoDate(item.silencedUntil);
  const silenced = silencedUntilDate !== null && silencedUntilDate.getTime() > nowMs;
  const remainingSeconds = silenced
    ? Math.ceil((silencedUntilDate.getTime() - nowMs) / 1000)
    : 0;

  return {
    zone: zoneName,
    silenced,
    silencedUntil: silenced ? silencedUntilDate.toISOString() : null,
    remainingSeconds,
    updatedAt: item.updatedAt || null,
  };
}

async function saveBuzzerSilence({ zone, durationSeconds, requestedBy }) {
  const zoneName = normalizeZone(zone);
  const normalizedDuration = normalizeDurationSeconds(durationSeconds);
  const now = new Date();
  const silencedUntil =
    normalizedDuration > 0
      ? new Date(now.getTime() + normalizedDuration * 1000).toISOString()
      : null;

  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: {
        settingId: settingIdForZone(zoneName),
        zone: zoneName,
        durationSeconds: normalizedDuration,
        silencedUntil,
        requestedBy: String(requestedBy || "").trim() || "unknown",
        updatedAt: now.toISOString(),
      },
    })
  );

  return getBuzzerSilenceState({ zone: zoneName });
}

module.exports = {
  getBuzzerSilenceState,
  saveBuzzerSilence,
};

