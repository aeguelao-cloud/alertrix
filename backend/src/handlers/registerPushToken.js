"use strict";

const { PutCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { ok, badRequest, serverError } = require("../common/response");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const token = body.token;
    const userId = body.userId || "anonymous";
    const platform = body.platform || "unknown";

    if (!token || typeof token !== "string") {
      return badRequest("Missing token");
    }

    const now = new Date().toISOString();
    await docClient.send(
      new PutCommand({
        TableName: tables.pushToken,
        Item: {
          token,
          userId,
          platform,
          updatedAt: now
        }
      })
    );

    return ok({ message: "Token registered", token, userId, platform, updatedAt: now });
  } catch (error) {
    console.error("registerPushToken error", error);
    return serverError("Failed to register token");
  }
};
