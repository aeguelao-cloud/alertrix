"use strict";

const admin = require("firebase-admin");
const { ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("./dynamo");

let initialized = false;

function ensureFirebaseInitialized() {
  if (initialized) return;
  if (admin.apps.length > 0) {
    initialized = true;
    return;
  }

  // Prefer B64 config to avoid CLI truncation issues on long JSON values.
  let serviceJson = null;
  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_JSON_B64;
  if (b64) {
    serviceJson = Buffer.from(b64, "base64").toString("utf8");
  } else {
    serviceJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  }

  if (!serviceJson) {
    throw new Error("Missing FIREBASE_SERVICE_ACCOUNT_JSON");
  }

  const credentials = JSON.parse(serviceJson);
  admin.initializeApp({
    credential: admin.credential.cert(credentials)
  });
  initialized = true;
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
  ensureFirebaseInitialized();
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
