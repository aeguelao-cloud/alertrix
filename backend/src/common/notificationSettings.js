"use strict";

const { GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { SNSClient, SubscribeCommand, UnsubscribeCommand } = require("@aws-sdk/client-sns");
const { docClient, tables } = require("./dynamo");
const { getAlertCriticalTopicArn, getAlertWarningTopicArn } = require("./runtimeConfig");

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
  const currentNormalized = {
    pushRule: normalizePushRule(current.pushRule),
    alertSoundEnabled: Boolean(current.alertSoundEnabled),
    notificationEmail: String(current.notificationEmail || "").trim(),
  };
  const next = {
    ...current,
    ...partial,
  };

  const normalized = {
    pushRule: normalizePushRule(next.pushRule),
    alertSoundEnabled: Boolean(next.alertSoundEnabled),
    notificationEmail: String(next.notificationEmail || "").trim(),
  };
  const changes = buildSettingsChanges(currentNormalized, normalized);
  const updatedAt = new Date().toISOString();
  if (changes.length === 0) {
    return {
      ...normalized,
      emailSubscriptionStatus: current.emailSubscriptionStatus || "Not configured",
      userId: current.userId,
      role: current.role,
      updatedAt,
      changes,
      changed: false,
    };
  }

  const previousEmail = currentNormalized.notificationEmail;
  const previousRule = currentNormalized.pushRule;
  const emailOrRuleChanged =
    previousEmail !== normalized.notificationEmail || previousRule !== normalized.pushRule;

  const topicArns = getTopicArns();
  const needsCritical = normalized.notificationEmail.length > 0 && normalized.pushRule !== "Disabled";
  const needsWarning = normalized.notificationEmail.length > 0 && normalized.pushRule === "Warning + Critical";

  let criticalArn = current.criticalTopicSubscriptionArn || null;
  let warningArn = current.warningTopicSubscriptionArn || null;
  let status = current.emailSubscriptionStatus || "Not configured";

  if (emailOrRuleChanged) {
    // Best-effort cleanup for old subscriptions when email/rule changed.
    await unsubscribeIfArn(current.criticalTopicSubscriptionArn);
    await unsubscribeIfArn(current.warningTopicSubscriptionArn);

    criticalArn = null;
    warningArn = null;
    status = normalized.notificationEmail.length > 0 ? "Pending confirmation" : "Not configured";

    if (topicArns.critical && needsCritical) {
      criticalArn = await subscribeEmail(topicArns.critical, normalized.notificationEmail);
    }
    if (topicArns.warning && needsWarning) {
      warningArn = await subscribeEmail(topicArns.warning, normalized.notificationEmail);
    }

    if (criticalArn && criticalArn !== "pending confirmation") {
      status = "Subscribed";
    }
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
        updatedAt,
      },
    })
  );

  return {
    ...normalized,
    emailSubscriptionStatus: status,
    userId: current.userId,
    role: current.role,
    updatedAt,
    changes,
    changed: true,
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

function buildSettingsChanges(current, next) {
  const changes = [];
  if (current.pushRule !== next.pushRule) {
    changes.push({
      field: "pushRule",
      from: current.pushRule,
      to: next.pushRule,
    });
  }
  if (current.alertSoundEnabled !== next.alertSoundEnabled) {
    changes.push({
      field: "alertSoundEnabled",
      from: current.alertSoundEnabled,
      to: next.alertSoundEnabled,
    });
  }
  if (current.notificationEmail !== next.notificationEmail) {
    changes.push({
      field: "notificationEmail",
      from: current.notificationEmail,
      to: next.notificationEmail,
    });
  }
  return changes;
}

function getTopicArns() {
  return {
    critical: getAlertCriticalTopicArn(),
    warning: getAlertWarningTopicArn(),
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
