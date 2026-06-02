"use strict";

const { ALERT_STATUS } = require("./alertStatus");

const allowedStatus = Object.freeze([
  ALERT_STATUS.ACTIVE,
  ALERT_STATUS.ACKNOWLEDGED,
  ALERT_STATUS.RESOLVED,
  ALERT_STATUS.CLOSED,
]);

const roleCanIgnore = (role) => role === "Admin";
const roleCanCreateWorkOrder = (role) => role === "Admin";
const isAdminRole = (role) => String(role || "").trim().toLowerCase() === "admin";

module.exports = {
  allowedStatus,
  roleCanIgnore,
  roleCanCreateWorkOrder,
  isAdminRole,
};
