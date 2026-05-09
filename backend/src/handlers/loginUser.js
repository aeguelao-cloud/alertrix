"use strict";

const { GetCommand, ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("../common/dynamo");
const { badRequest, forbidden, ok, serverError } = require("../common/response");
const { hashPassword } = require("../common/auth");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const email = String(body.email || body.login || "").trim().toLowerCase();
    const password = String(body.password || "");

    if (!email || !password) return badRequest("Missing email or password");

    const result = await docClient.send(
      new GetCommand({
        TableName: tables.authUser,
        Key: { username: email },
      })
    );

    const user = result.Item;
    if (!user) return forbidden("Invalid email or password");
    if (user.passwordHash !== hashPassword(password)) return forbidden("Invalid email or password");

    const internalAdmin = await resolveInternalAdmin(email);
    return ok({
      user: {
        username: user.username || email,
        role: internalAdmin ? "Admin" : user.role || "User",
      },
    });
  } catch (error) {
    console.error("loginUser error", error);
    return serverError("Failed to login");
  }
};

async function resolveInternalAdmin(email) {
  const adminIds = new Set(parseInternalAdminIds());
  if (adminIds.has(email)) return true;

  const adminList = await docClient.send(
    new ScanCommand({
      TableName: tables.admin,
    })
  );

  return (adminList.Items || []).some((item) => {
    const adminEmail = String(item.email || "").trim().toLowerCase();
    const active = String(item.status || "active").trim().toLowerCase() === "active";
    return active && adminEmail === email;
  });
}

function parseInternalAdminIds() {
  const raw =
    process.env.INTERNAL_ADMIN_USER_IDS ||
    process.env.INTERNAL_ADMIN_USER ||
    process.env.ADMIN_EMAIL ||
    "";
  return String(raw)
    .split(",")
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean);
}
