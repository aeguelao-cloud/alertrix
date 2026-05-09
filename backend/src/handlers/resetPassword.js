"use strict";

const { DeleteCommand, GetCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { badRequest, notFound, ok, serverError } = require("../common/response");
const { hashPassword, isEmailValid } = require("../common/auth");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const email = String(body.email || "").trim().toLowerCase();
    const code = String(body.code || "").trim();
    const password = String(body.password || "");

    if (!isEmailValid(email)) return badRequest("Invalid email");
    if (!/^\d{6}$/.test(code)) return badRequest("Invalid verification code");
    if (password.length < 8) return badRequest("Password must be at least 8 characters");

    const verification = await docClient.send(
      new GetCommand({
        TableName: tables.verification,
        Key: { email },
      })
    );
    const record = verification.Item;
    if (!record) return badRequest("Verification code not found");
    if (record.code !== code) return badRequest("Verification code incorrect");
    if (Date.now() > Number(record.expiresAtMs || 0)) return badRequest("Verification code expired");

    const user = await docClient.send(
      new GetCommand({
        TableName: tables.authUser,
        Key: { username: email },
      })
    );
    if (!user.Item) return notFound("Account not found");

    await docClient.send(
      new UpdateCommand({
        TableName: tables.authUser,
        Key: { username: email },
        UpdateExpression: "SET passwordHash = :hash, updatedAt = :updatedAt",
        ExpressionAttributeValues: {
          ":hash": hashPassword(password),
          ":updatedAt": new Date().toISOString(),
        },
      })
    );

    await docClient.send(
      new DeleteCommand({
        TableName: tables.verification,
        Key: { email },
      })
    );

    return ok({ message: "Password reset successful" });
  } catch (error) {
    console.error("resetPassword error", error);
    return serverError("Failed to reset password");
  }
};

