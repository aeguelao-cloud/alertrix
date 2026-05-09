"use strict";

const { GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { SNSClient, SubscribeCommand, UnsubscribeCommand } = require("@aws-sdk/client-sns");
const { docClient, tables } = require("./dynamo");

const sns = new SNSClient({});

const defaultSettings = {
  pushRule: "Warning + Critical",
  alertSoundEnabled: true,
  notificationEmail: ""
};

async function getNotificationSettings({ userId, role }) {
  const key = normalizeUserId(userId, role);
  const result = await docClient.send(
    new GetCommand({
      TableName: tables.userProfile,
      Key: { userId: key },
    })
  );

  const item = result.Item || {};
  return {
    userId: key,
    role: role || item.role || "User",
    pushRule: normalizePushRule(item.pushRule),
    alertSoundEnabled: typeof item.alertSoundEnabled === "boolean" ? item.alertSoundEnabled : defaultSettings.alertSoundEnabled,
    notificationEmail: item.notificationEmail || defaultSettings.notificationEmail,
    emailSubscriptionStatus: item.emailSubscriptionStatus || "Not configured",
    criticalTopicSubscriptionArn: item.criticalTopicSubscriptionArn || null,
    warningTopicSubscriptionArn: item.warningTopicSubscriptionArn || null,
  };
}

async function saveNotificationSettings({ userId, role, partial }) {
  const current = await getNotificationSettings({ userId, role });
  const next = {
    ...current,
    ...partial,
  };

  const normalized = {
    pushRule: normalizePushRule(next.pushRule),
    alertSoundEnabled: Boolean(next.alertSoundEnabled),
    notificationEmail: String(next.notificationEmail || "").trim(),
  };

  const previousEmail = String(current.notificationEmail || "").trim();
  const previousRule = normalizePushRule(current.pushRule);

  const topicArns = getTopicArns();
  const needsCritical = normalized.notificationEmail.length > 0 && normalized.pushRule !== "Disabled";
  const needsWarning = normalized.notificationEmail.length > 0 && normalized.pushRule === "Warning + Critical";

  let criticalArn = null;
  let warningArn = null;
  let status = normalized.notificationEmail.length > 0 ? "Pending confirmation" : "Not configured";

  // Re-subscribe when email/rule changed.
  if (topicArns.critical && needsCritical) {
    criticalArn = await subscribeEmail(topicArns.critical, normalized.notificationEmail);
  }
  if (topicArns.warning && needsWarning) {
    warningArn = await subscribeEmail(topicArns.warning, normalized.notificationEmail);
  }

  if (criticalArn && criticalArn !== "pending confirmation") {
    status = "Subscribed";
  }

  // Best-effort cleanup for old subscriptions when email/rule changed.
  if (previousEmail && (previousEmail !== normalized.notificationEmail || previousRule !== normalized.pushRule)) {
    await unsubscribeIfArn(current.criticalTopicSubscriptionArn);
    await unsubscribeIfArn(current.warningTopicSubscriptionArn);
  }

  await docClient.send(
    new PutCommand({
      TableName: tables.userProfile,
      Item: {
        userId: current.userId,
        role: current.role,
        pushRule: normalized.pushRule,
        alertSoundEnabled: normalized.alertSoundEnabled,
        notificationEmail: normalized.notificationEmail,
        criticalTopicSubscriptionArn: criticalArn,
        warningTopicSubscriptionArn: warningArn,
        emailSubscriptionStatus: status,
        updatedAt: new Date().toISOString(),
      },
    })
  );

  return {
    ...normalized,
    emailSubscriptionStatus: status,
    userId: current.userId,
    role: current.role,
  };
}

function shouldSendPush(pushRule, severity) {
  const rule = normalizePushRule(pushRule);
  const level = String(severity || "NORMAL").toUpperCase();
  if (rule === "Disabled") return false;
  if (rule === "Critical only") return level === "CRITICAL";
  return level === "CRITICAL" || level === "WARNING";
}

function normalizePushRule(value) {
  const text = String(value || "").trim();
  if (text === "Critical only") return "Critical only";
  if (text === "Disabled") return "Disabled";
  return defaultSettings.pushRule;
}

function normalizeUserId(userId, role) {
  const cleaned = String(userId || "").trim();
  if (cleaned.length > 0) return cleaned;
  return String(role || "User").toLowerCase() === "admin" ? "admin" : "user";
}

function getTopicArns() {
  return {
    critical: process.env.ALERT_CRITICAL_TOPIC_ARN || "",
    warning: process.env.ALERT_WARNING_TOPIC_ARN || "",
  };
}

async function subscribeEmail(topicArn, email) {
  if (!topicArn || !email) return null;
  const result = await sns.send(
    new SubscribeCommand({
      TopicArn: topicArn,
      Protocol: "email",
      Endpoint: email,
      ReturnSubscriptionArn: true,
    })
  );
  return result.SubscriptionArn || "pending confirmation";
}

async function unsubscribeIfArn(subscriptionArn) {
  const arn = String(subscriptionArn || "").trim();
  if (!arn || arn === "pending confirmation") return;
  try {
    await sns.send(new UnsubscribeCommand({ SubscriptionArn: arn }));
  } catch (_) {
    // Best effort.
  }
}

module.exports = {
  getNotificationSettings,
  saveNotificationSettings,
  shouldSendPush,
};
