"use strict";

const allowedStatus = ["OPEN", "CONFIRMED", "IGNORED", "WORK_ORDER_CREATED"];
const roleCanIgnore = (role) => role === "Admin";
const roleCanCreateWorkOrder = (role) => role === "Admin";
const isAdminRole = (role) => String(role || "").trim().toLowerCase() === "admin";

module.exports = {
  allowedStatus,
  roleCanIgnore,
  roleCanCreateWorkOrder,
  isAdminRole
};
