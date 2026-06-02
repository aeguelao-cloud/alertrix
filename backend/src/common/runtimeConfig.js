"use strict";

function envFirst(...keys) {
  for (const key of keys) {
    const value = process.env[key];
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim();
    }
  }
  return "";
}

function getAlertCriticalTopicArn() {
  // Backward compatible: legacy SNS_ENDPOINT may carry the same ARN.
  return envFirst("ALERT_CRITICAL_TOPIC_ARN", "SNS_ENDPOINT");
}

function getAlertWarningTopicArn() {
  return envFirst("ALERT_WARNING_TOPIC_ARN");
}

function getHeartbeatTopicArn() {
  return envFirst("HEARTBEAT_TOPIC_ARN");
}

function getEmergencyAgency() {
  return envFirst("EMERGENCY_AGENCY", "EmergencyAgency");
}

function getThresholdConfigParam() {
  // Preferred new key; keep legacy alias for smooth migration.
  return envFirst("THRESHOLD_CONFIG_PARAM", "THRESHOLD_CONFIG_PARAMETER");
}

module.exports = {
  getAlertCriticalTopicArn,
  getAlertWarningTopicArn,
  getHeartbeatTopicArn,
  getEmergencyAgency,
  getThresholdConfigParam,
};
