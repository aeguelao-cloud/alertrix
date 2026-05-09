"use strict";

const { ok, serverError } = require("../common/response");
const { getNotificationSettings } = require("../common/notificationSettings");

exports.handler = async (event) => {
  try {
    const headers = event.headers || {};
    const userId = headers["x-user-id"] || headers["X-User-Id"] || "";
    const role = headers["x-user-role"] || headers["X-User-Role"] || "User";
    const settings = await getNotificationSettings({ userId, role });
    return ok(settings);
  } catch (error) {
    console.error("getNotificationSettings error", error);
    return serverError("Failed to fetch notification settings");
  }
};
