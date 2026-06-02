"use strict";

const { ok, badRequest, forbidden, serverError } = require("../common/response");
const {
  ALLOWED_REFRESH_INTERVALS,
  ALLOWED_REFRESH_MODES,
  ALLOWED_TREND_WINDOWS,
  getSystemSettings,
  saveSystemSettings,
} = require("../common/systemSettings");
const { loadThresholdConfig, saveThresholdConfig } = require("../common/thresholds");
const { isAdminRole } = require("../common/policy");
const { getNotificationSettings } = require("../common/notificationSettings");
const { sendSettingsChangeEmail } = require("../common/settingsChangeEmail");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const headers = event.headers || {};
    const userId = String(headers["x-user-id"] || headers["X-User-Id"] || body.userId || "").trim();
    const role = String(headers["x-user-role"] || headers["X-User-Role"] || body.role || "User").trim();
    if (!isAdminRole(role)) {
      return forbidden("Only Admin can update system settings");
    }

    const systemPartial = {};
    if (body.autoRefreshIntervalSeconds !== undefined) {
      const refreshSeconds = Number(body.autoRefreshIntervalSeconds);
      if (!ALLOWED_REFRESH_INTERVALS.has(refreshSeconds)) {
        return badRequest("Invalid autoRefreshIntervalSeconds");
      }
      systemPartial.autoRefreshIntervalSeconds = refreshSeconds;
    }

    if (body.defaultTrendWindow !== undefined) {
      const trendWindow = String(body.defaultTrendWindow || "").trim().toUpperCase();
      if (!ALLOWED_TREND_WINDOWS.has(trendWindow)) {
        return badRequest("Invalid defaultTrendWindow");
      }
      systemPartial.defaultTrendWindow = trendWindow;
    }

    if (body.dashboardRefreshMode !== undefined) {
      const refreshMode = String(body.dashboardRefreshMode || "").trim();
      if (!ALLOWED_REFRESH_MODES.has(refreshMode)) {
        return badRequest("Invalid dashboardRefreshMode");
      }
      systemPartial.dashboardRefreshMode = refreshMode;
    }

    if (body.siteName !== undefined) {
      const siteName = String(body.siteName || "").trim();
      if (!siteName) {
        return badRequest("siteName is required");
      }
      systemPartial.siteName = siteName;
    }

    if (body.siteDescription !== undefined) {
      const siteDescription = String(body.siteDescription || "").trim();
      systemPartial.siteDescription = siteDescription;
    }

    let thresholdPartial = null;
    if (body.thresholds !== undefined) {
      if (!body.thresholds || typeof body.thresholds !== "object") {
        return badRequest("thresholds must be an object");
      }
      thresholdPartial = body.thresholds;
    }

    if (Object.keys(systemPartial).length === 0 && thresholdPartial == null) {
      return badRequest("No valid fields to update");
    }

    const [beforeSystem, beforeThresholds] = await Promise.all([
      getSystemSettings(),
      loadThresholdConfig(),
    ]);

    if (Object.keys(systemPartial).length > 0) {
      await saveSystemSettings(systemPartial);
    }
    if (thresholdPartial != null) {
      await saveThresholdConfig(thresholdPartial);
    }

    const [system, thresholds] = await Promise.all([
      getSystemSettings(),
      loadThresholdConfig(),
    ]);

    let settingsChangeEmail = { delivered: false, reason: "Not attempted" };
    try {
      const notification = await getNotificationSettings({ userId, role });
      const changes = buildSystemChanges(beforeSystem, beforeThresholds, system, thresholds);
      settingsChangeEmail = await sendSettingsChangeEmail({
        toEmail: notification.notificationEmail,
        userId: userId || notification.userId,
        role,
        changes,
        changedAt: new Date().toISOString(),
      });
    } catch (mailError) {
      console.error("sendSystemSettingsChangeEmail error", mailError);
      settingsChangeEmail = { delivered: false, reason: "Email send failed" };
    }

    return ok({
      ...system,
      thresholds,
      settingsChangeEmail,
    });
  } catch (error) {
    console.error("updateSystemSettings error", error);
    return serverError("Failed to update system settings");
  }
};

function buildSystemChanges(beforeSystem, beforeThresholds, afterSystem, afterThresholds) {
  const changes = [];
  if (beforeSystem.autoRefreshIntervalSeconds !== afterSystem.autoRefreshIntervalSeconds) {
    changes.push({
      field: "autoRefreshIntervalSeconds",
      from: beforeSystem.autoRefreshIntervalSeconds,
      to: afterSystem.autoRefreshIntervalSeconds,
    });
  }
  if (beforeSystem.defaultTrendWindow !== afterSystem.defaultTrendWindow) {
    changes.push({
      field: "defaultTrendWindow",
      from: beforeSystem.defaultTrendWindow,
      to: afterSystem.defaultTrendWindow,
    });
  }
  if (beforeSystem.dashboardRefreshMode !== afterSystem.dashboardRefreshMode) {
    changes.push({
      field: "dashboardRefreshMode",
      from: beforeSystem.dashboardRefreshMode,
      to: afterSystem.dashboardRefreshMode,
    });
  }
  if (beforeSystem.siteName !== afterSystem.siteName) {
    changes.push({
      field: "siteName",
      from: beforeSystem.siteName,
      to: afterSystem.siteName,
    });
  }
  if (beforeSystem.siteDescription !== afterSystem.siteDescription) {
    changes.push({
      field: "siteDescription",
      from: beforeSystem.siteDescription,
      to: afterSystem.siteDescription,
    });
  }
  const sensors = ["waterLevel", "vibration", "temperature"];
  for (const sensor of sensors) {
    const before = beforeThresholds?.[sensor] || {};
    const after = afterThresholds?.[sensor] || {};
    if (Number(before.warning) !== Number(after.warning)) {
      changes.push({
        field: `${sensor}.warning`,
        from: before.warning,
        to: after.warning,
      });
    }
    if (Number(before.critical) !== Number(after.critical)) {
      changes.push({
        field: `${sensor}.critical`,
        from: before.critical,
        to: after.critical,
      });
    }
  }
  return changes;
}
