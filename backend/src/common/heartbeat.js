"use strict";

const { PutCommand } = require("@aws-sdk/lib-dynamodb");
const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");
const { docClient, tables } = require("./dynamo");
const { getHeartbeatTopicArn } = require("./runtimeConfig");

const sns = new SNSClient({});
const OFFLINE_WINDOW_SECONDS = Number(process.env.OFFLINE_WINDOW_SECONDS || 120);

async function publishHeartbeat({ sensorType, zone, capturedAt, source }) {
  const topicArn = getHeartbeatTopicArn();
  if (!topicArn) return { published: false, reason: "HEARTBEAT_TOPIC_ARN not configured" };

  const payload = {
    type: "DEVICE_HEARTBEAT",
    sensorType,
    zone,
    capturedAt,
    source: source || "ingestSensorData",
    offlineWindowSeconds: OFFLINE_WINDOW_SECONDS,
  };

  const res = await sns.send(
    new PublishCommand({
      TopicArn: topicArn,
      Subject: "Alertrix Heartbeat",
      Message: JSON.stringify(payload),
    })
  );

  return { published: true, messageId: res.MessageId || null };
}

async function touchLastSeen({ sensorType, zone, capturedAt }) {
  const ts = capturedAt || new Date().toISOString();
  const key = `LAST_SEEN#${String(zone || "Unknown Zone").trim()}#${String(sensorType || "unknown").trim()}`;
  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: {
        settingId: key,
        type: "lastSeen",
        zone: zone || "Unknown Zone",
        sensorType: sensorType || "unknown",
        lastSeenAt: ts,
        offlineAfterSeconds: OFFLINE_WINDOW_SECONDS,
        updatedAt: new Date().toISOString(),
      },
    })
  );
  return { key, lastSeenAt: ts, offlineAfterSeconds: OFFLINE_WINDOW_SECONDS };
}

module.exports = {
  publishHeartbeat,
  touchLastSeen,
};
