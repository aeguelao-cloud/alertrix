"use strict";

const json = (statusCode, body) => ({
  statusCode,
  headers: {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id,X-User-Role",
    "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS"
  },
  body: JSON.stringify(body)
});

const ok = (body) => json(200, body);
const badRequest = (message) => json(400, { error: message });
const forbidden = (message) => json(403, { error: message });
const notFound = (message) => json(404, { error: message });
const serverError = (message) => json(500, { error: message });

module.exports = { ok, badRequest, forbidden, notFound, serverError };
