"use strict";

const crypto = require("crypto");
const { GetCommand, PutCommand, DeleteCommand, ScanCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("./dynamo");
const { isEmailValid } = require("./auth");

function normalizeAdminInput(input = {}) {
  const name = String(input.name || "").trim();
  const email = String(input.email || "").trim().toLowerCase();
  const role = String(input.role || "Admin").trim();
  const status = String(input.status || "active").trim().toLowerCase();
  return { name, email, role, status };
}

function validateAdminInput(input = {}) {
  const normalized = normalizeAdminInput(input);
  if (!normalized.name) return { ok: false, error: "Missing admin name" };
  if (!isEmailValid(normalized.email)) return { ok: false, error: "Invalid admin email" };
  if (!["admin", "super_admin"].includes(normalized.role.toLowerCase())) {
    return { ok: false, error: "Invalid admin role" };
  }
  if (!["active", "inactive"].includes(normalized.status)) {
    return { ok: false, error: "Invalid admin status" };
  }
  return { ok: true, data: normalized };
}

async function listAdmins() {
  const result = await docClient.send(
    new ScanCommand({
      TableName: tables.admin,
    })
  );
  const items = (result.Items || []).slice().sort((a, b) => {
    const t1 = String(a.createdAt || "");
    const t2 = String(b.createdAt || "");
    return t1 < t2 ? 1 : -1;
  });
  return items;
}

async function getAdminById(adminId) {
  const result = await docClient.send(
    new GetCommand({
      TableName: tables.admin,
      Key: { adminId: String(adminId || "") },
    })
  );
  return result.Item || null;
}

async function createAdmin({ name, email, role = "admin", status = "active", actor = "system" }) {
  const checked = validateAdminInput({ name, email, role, status });
  if (!checked.ok) {
    const error = new Error(checked.error);
    error.code = "BAD_INPUT";
    throw error;
  }

  const normalized = checked.data;
  const allAdmins = await listAdmins();
  if (allAdmins.some((item) => String(item.email || "").toLowerCase() === normalized.email)) {
    const error = new Error("Admin email already exists");
    error.code = "DUPLICATE_EMAIL";
    throw error;
  }

  const now = new Date().toISOString();
  const adminId = `ADM-${crypto.randomBytes(4).toString("hex").toUpperCase()}`;
  const item = {
    adminId,
    name: normalized.name,
    email: normalized.email,
    role: normalized.role.toLowerCase(),
    status: normalized.status,
    createdAt: now,
    updatedAt: now,
    createdBy: actor,
    updatedBy: actor,
  };

  await docClient.send(
    new PutCommand({
      TableName: tables.admin,
      Item: item,
    })
  );
  return item;
}

async function updateAdmin(adminId, updates = {}, actor = "system") {
  const existing = await getAdminById(adminId);
  if (!existing) return null;

  const allowed = {};
  if (updates.name !== undefined) allowed.name = String(updates.name || "").trim();
  if (updates.email !== undefined) allowed.email = String(updates.email || "").trim().toLowerCase();
  if (updates.role !== undefined) allowed.role = String(updates.role || "").trim().toLowerCase();
  if (updates.status !== undefined) allowed.status = String(updates.status || "").trim().toLowerCase();

  const merged = {
    name: allowed.name !== undefined ? allowed.name : existing.name,
    email: allowed.email !== undefined ? allowed.email : existing.email,
    role: allowed.role !== undefined ? allowed.role : existing.role,
    status: allowed.status !== undefined ? allowed.status : existing.status,
  };

  const checked = validateAdminInput(merged);
  if (!checked.ok) {
    const error = new Error(checked.error);
    error.code = "BAD_INPUT";
    throw error;
  }

  if (allowed.email && allowed.email !== String(existing.email || "").toLowerCase()) {
    const allAdmins = await listAdmins();
    if (allAdmins.some((item) => item.adminId !== adminId && String(item.email || "").toLowerCase() === allowed.email)) {
      const error = new Error("Admin email already exists");
      error.code = "DUPLICATE_EMAIL";
      throw error;
    }
  }

  const now = new Date().toISOString();
  const updated = await docClient.send(
    new UpdateCommand({
      TableName: tables.admin,
      Key: { adminId },
      UpdateExpression: "SET #name = :name, email = :email, #role = :role, #status = :status, updatedAt = :updatedAt, updatedBy = :updatedBy",
      ExpressionAttributeNames: {
        "#name": "name",
        "#role": "role",
        "#status": "status",
      },
      ExpressionAttributeValues: {
        ":name": checked.data.name,
        ":email": checked.data.email,
        ":role": checked.data.role.toLowerCase(),
        ":status": checked.data.status,
        ":updatedAt": now,
        ":updatedBy": actor,
      },
      ReturnValues: "ALL_NEW",
    })
  );
  return updated.Attributes || null;
}

async function deleteAdmin(adminId) {
  const existing = await getAdminById(adminId);
  if (!existing) return false;
  await docClient.send(
    new DeleteCommand({
      TableName: tables.admin,
      Key: { adminId },
    })
  );
  return true;
}

async function listActiveAdminEmails() {
  const allAdmins = await listAdmins();
  return allAdmins
    .filter((item) => String(item.status || "").toLowerCase() === "active" && isEmailValid(item.email))
    .map((item) => String(item.email || "").trim().toLowerCase());
}

module.exports = {
  listAdmins,
  getAdminById,
  createAdmin,
  updateAdmin,
  deleteAdmin,
  listActiveAdminEmails,
};

