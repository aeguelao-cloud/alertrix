"use strict";

const { sendNotificationToAll } = require("../common/fcm");
const { ok, serverError } = require("../common/response");

exports.handler = async () => {
  try {
    const result = await sendNotificationToAll({
      title: "Alertrix Test Alert",
      body: "Lambda triggered a test FCM notification.",
      data: {
        type: "TEST_ALERT"
      }
    });

    return ok({
      message: "Test alert dispatched",
      result
    });
  } catch (error) {
    console.error("sendTestAlert error", error);
    return serverError("Failed to send test alert");
  }
};
