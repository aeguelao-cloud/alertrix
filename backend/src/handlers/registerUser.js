"use strict";

const { GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { badRequest, ok, serverError } = require("../common/response");
const { hashPassword, isEmailValid } = require("../common/auth");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const name = String(body.name || "").trim();
    const password = String(body.password || "");
    const email = String(body.email || "").trim().toLowerCase();
    const code = String(body.code || "").trim();
    const username = email;

    if (!name) return badRequest("Missing name");
    if (password.length < 6) return badRequest("Password must be at least 6 characters");
    if (!isEmailValid(email)) return badRequest("Invalid email");
    if (!/^\d{6}$/.test(code)) return badRequest("Invalid verification code");

    const userExisting = await docClient.send(
      new GetCommand({
        TableName: tables.authUser,
        Key: { username },
      })
    );
    if (userExisting.Item) {
      return badRequest("Email already registered");
    }

    const verification = await docClient.send(
      new GetCommand({
        TableName: tables.verification,
        Key: { email },
      })
    );

    const record = verification.Item;
    if (!record) return badRequest("Verification code not found");
    if (String(record.name || "").trim().toLowerCase() !== name.toLowerCase()) {
      return badRequest("Verification name mismatch");
    }
    if (record.code !== code) return badRequest("Verification code incorrect");
    if (Date.now() > Number(record.expiresAtMs || 0)) return badRequest("Verification code expired");

    const now = new Date().toISOString();
    await docClient.send(
      new PutCommand({
        TableName: tables.authUser,
        Item: {
          username,
          name,
          passwordHash: hashPassword(password),
          email,
          role: "User",
          createdAt: now,
          updatedAt: now,
        },
      })
    );

    await docClient.send(
      new PutCommand({
        TableName: tables.userProfile,
        Item: {
          userId: username,
          name,
          role: "User",
          pushRule: "Warning + Critical",
          alertSoundEnabled: true,
          notificationEmail: email,
          emailSubscriptionStatus: "Not configured",
          updatedAt: now,
        },
      })
    );

    return ok({ message: "Registration successful" });
  } catch (error) {
    console.error("registerUser error", error);
    return serverError("Failed to register user");
  }
};
