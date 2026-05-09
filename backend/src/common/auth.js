"use strict";

const crypto = require("crypto");

function hashPassword(password) {
  const text = String(password || "");
  return crypto.createHash("sha256").update(text).digest("hex");
}

function generateVerificationCode() {
  return `${Math.floor(100000 + Math.random() * 900000)}`;
}

function isEmailValid(email) {
  const text = String(email || "").trim();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(text);
}

module.exports = {
  hashPassword,
  generateVerificationCode,
  isEmailValid,
};

