"use strict";

const { ok, badRequest, serverError } = require("../common/response");
const { saveNotificationSettings } = require("../common/notificationSettings");
const { sendSettingsChangeEmail } = require("../common/settingsChangeEmail");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const headers = event.headers || {};
    const userId = headers["x-user-id"] || headers["X-User-Id"] || body.userId || "";
    const role = headers["x-user-role"] || headers["X-User-Role"] || body.role || "User";
    const partial = {};

    if (body.pushRule !== undefined) {
      const pushRule = String(body.pushRule).trim();
      if (!["Warning + Critical", "Critical only", "Disabled"].includes(pushRule)) {
        return badRequest("Invalid pushRule");
      }
      partial.pushRule = pushRule;
    }

    if (body.alertSoundEnabled !== undefined) {
      partial.alertSoundEnabled = Boolean(body.alertSoundEnabled);
    }

    if (body.notificationEmail !== undefined) {
      const email = String(body.notificationEmail || "").trim();
      if (email.length > 0 && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return badRequest("Invalid notificationEmail");
      }
      partial.notificationEmail = email;
    }

    if (Object.keys(partial).length === 0) {
      return badRequest("No valid fields to update");
    }

    const saved = await saveNotificationSettings({ userId, role, partial });

    let settingsChangeEmail = { delivered: false, reason: "Not attempted" };
    try {
      settingsChangeEmail = await sendSettingsChangeEmail({
        toEmail: saved.notificationEmail,
        userId: saved.userId,
        role: saved.role,
        changes: saved.changes,
        changedAt: saved.updatedAt,
      });
    } catch (mailError) {
      console.error("sendSettingsChangeEmail error", mailError);
      settingsChangeEmail = {
        delivered: false,
        reason: "Email send failed",
      };
    }

    return ok({
      ...saved,
      settingsChangeEmail,
    });
  } catch (error) {
    console.error("updateNotificationSettings error", error);
    return serverError("Failed to update notification settings");
  }
};
