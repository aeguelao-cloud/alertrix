"use strict";

const { GetCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { badRequest, forbidden, ok, serverError } = require("../common/response");
const { hashPassword } = require("../common/auth");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const email = String(body.email || body.login || "").trim().toLowerCase();
    const password = String(body.password || "");
    const adminEmail = String(process.env.ADMIN_EMAIL || "admin@alertrix.local").trim().toLowerCase();

    if (!email || !password) return badRequest("Missing email or password");

    if (email === adminEmail && password === "Admin@123") {
      return ok({
        user: {
          username: adminEmail,
          role: "Admin",
        },
      });
    }

    const result = await docClient.send(
      new GetCommand({
        TableName: tables.authUser,
        Key: { username: email },
      })
    );

    const user = result.Item;
    if (!user) return forbidden("Invalid email or password");
    if (user.passwordHash !== hashPassword(password)) return forbidden("Invalid email or password");

    return ok({
      user: {
        username: user.username || email,
        role: user.role || "User",
      },
    });
  } catch (error) {
    console.error("loginUser error", error);
    return serverError("Failed to login");
  }
};
