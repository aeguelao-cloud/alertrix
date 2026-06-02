"use strict";

const admin = require("firebase-admin");
const { ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");
const { docClient, tables } = require("./dynamo");

let initialized = false;
let initializingPromise = null;
const ssm = new SSMClient({});

function looksLikeBase64(value) {
  if (typeof value !== "string") return false;
  const trimmed = value.trim();
  if (!trimmed || trimmed.includes("{")) return false;
  return /^[A-Za-z0-9+/=\r\n]+$/.test(trimmed) && trimmed.length % 4 === 0;
}

function tryParseJsonCandidates(raw) {
  const attempts = [];
  if (typeof raw !== "string") return null;

  const trimmed = raw.trim();
  attempts.push(trimmed);

  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    attempts.push(trimmed.slice(1, -1));
  }

  for (const candidate of attempts) {
    if (!candidate) continue;

    try {
      const parsed = JSON.parse(candidate);
      if (parsed && typeof parsed === "object") return parsed;
      if (typeof parsed === "string") {
        const nested = JSON.parse(parsed);
        if (nested && typeof nested === "object") return nested;
      }
    } catch (_) {}

    try {
      const normalized = candidate
        .replace(/([{,]\s*)'([^']+?)'\s*:/g, '$1"$2":')
        .replace(/:\s*'([^']*?)'(\s*[,}])/g, ': "$1"$2');
      const parsed = JSON.parse(normalized);
      if (parsed && typeof parsed === "object") return parsed;
    } catch (_) {}

    if (looksLikeBase64(candidate)) {
      try {
        const decoded = Buffer.from(candidate, "base64").toString("utf8");
        const parsed = JSON.parse(decoded);
        if (parsed && typeof parsed === "object") return parsed;
      } catch (_) {}
    }
  }

  return null;
}

function getFirebaseServiceAccountParamName() {
  const keys = [
    "FIREBASE_SERVICE_ACCOUNT_PARAM",
    "FIREBASE_SERVICE_ACCOUNT_PARAM_NAME",
    "FIREBASE_SERVICE_ACCOUNT_SSM_PARAM"
  ];
  for (const key of keys) {
    const value = process.env[key];
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim();
    }
  }
  return "";
}

async function loadFirebaseConfigFromSsm() {
  const name = getFirebaseServiceAccountParamName();
  if (!name) return "";

  const result = await ssm.send(
    new GetParameterCommand({
      Name: name,
      WithDecryption: true
    })
  );
  return result.Parameter?.Value || "";
}

async function ensureFirebaseInitialized() {
  if (initialized) return;
  if (admin.apps.length > 0) {
    initialized = true;
    return;
  }

  if (initializingPromise) {
    await initializingPromise;
    return;
  }

  initializingPromise = (async () => {
    const rawB64 =
      process.env.FIREBASE_SERVICE_ACCOUNT_JSON_B64 ||
      process.env.FIREBASE_SERVICE_ACCOUNT_JSON_BASE64;
    const rawJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;

    let ssmValue = "";
    try {
      ssmValue = await loadFirebaseConfigFromSsm();
    } catch (error) {
      throw new Error(`Failed to load Firebase config from SSM: ${error.message}`);
    }

    if (!rawB64 && !rawJson && !ssmValue) {
      throw new Error(
        "Missing Firebase config. Set FIREBASE_SERVICE_ACCOUNT_PARAM or FIREBASE_SERVICE_ACCOUNT_JSON_B64"
      );
    }

    const credentials =
      tryParseJsonCandidates(rawB64 ? Buffer.from(rawB64, "base64").toString("utf8") : "") ||
      tryParseJsonCandidates(rawJson || "") ||
      tryParseJsonCandidates(ssmValue || "");

    if (!credentials) {
      throw new Error(
        "Invalid Firebase service account JSON from env/SSM (FIREBASE_SERVICE_ACCOUNT_PARAM / FIREBASE_SERVICE_ACCOUNT_JSON_B64)"
      );
    }

    admin.initializeApp({
      credential: admin.credential.cert(credentials)
    });
    initialized = true;
  })();

  try {
    await initializingPromise;
  } finally {
    initializingPromise = null;
  }
}

async function getRegisteredTokens() {
  const result = await docClient.send(
    new ScanCommand({
      TableName: tables.pushToken
    })
  );
  return (result.Items ?? [])
    .map((x) => x.token)
    .filter((x) => typeof x === "string" && x.trim().length > 0);
}

async function sendNotificationToAll({ title, body, data }) {
  await ensureFirebaseInitialized();
  const tokens = await getRegisteredTokens();
  if (tokens.length === 0) {
    return { successCount: 0, failureCount: 0, reason: "No tokens registered" };
  }

  const message = {
    tokens,
    notification: { title, body },
    data: data || {}
  };

  const response = await admin.messaging().sendEachForMulticast(message);
  return {
    successCount: response.successCount,
    failureCount: response.failureCount
  };
}

module.exports = {
  sendNotificationToAll
};
