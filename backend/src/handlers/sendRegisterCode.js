"use strict";

const { GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { badRequest, ok, serverError } = require("../common/response");
const { generateVerificationCode, isEmailValid } = require("../common/auth");
const { sendVerificationEmail } = require("../common/verificationEmail");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const name = String(body.name || "").trim();
    const email = String(body.email || "").trim().toLowerCase();
    const purpose = String(body.purpose || "register").trim().toLowerCase();

    if (!name) return badRequest("Missing name");
    if (!isEmailValid(email)) return badRequest("Invalid email");
    const username = email;

    const userExisting = await docClient.send(
      new GetCommand({
        TableName: tables.authUser,
        Key: { username },
      })
    );
    if (purpose === "reset") {
      if (!userExisting.Item) {
        return badRequest("Account not found");
      }
    } else {
      if (userExisting.Item) {
        return badRequest("Email already registered");
      }
    }

    const code = generateVerificationCode();
    const nowMs = Date.now();
    const ttl = Math.floor((nowMs + 10 * 60 * 1000) / 1000);

    await docClient.send(
      new PutCommand({
        TableName: tables.verification,
        Item: {
          email,
          code,
          name,
          expiresAtMs: nowMs + 10 * 60 * 1000,
          ttl,
          updatedAt: new Date().toISOString(),
        },
      })
    );

    const emailResult = await sendVerificationEmail({ toEmail: email, code, name });
    return ok({
      message: "Verification code sent",
      emailResult,
    });
  } catch (error) {
    console.error("sendRegisterCode error", error);
    return serverError("Failed to send verification code");
  }
};
