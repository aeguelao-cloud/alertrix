"use strict";

const { ALERT_STATUS, normalizeSeverity } = require("../common/alertStatus");
const { listIncidentsByStatusesPage } = require("../common/incidentStore");
const { ok, serverError } = require("../common/response");

exports.handler = async (event) => {
  try {
    const severityFilter = event.queryStringParameters?.severity
      ? normalizeSeverity(event.queryStringParameters.severity)
      : null;
    const limitRaw = event.queryStringParameters?.limit;
    const limit = Math.max(1, Math.min(Number.parseInt(limitRaw || "120", 10) || 120, 1000));
    const cursor = event.queryStringParameters?.cursor || null;

    const page = await listIncidentsByStatusesPage(
      [ALERT_STATUS.ACTIVE, ALERT_STATUS.ACKNOWLEDGED],
      { limit, cursor }
    );
    let incidents = page.items;

    if (severityFilter) {
      incidents = incidents.filter((item) => item.severity === severityFilter);
    }

    return ok({
      items: incidents.slice(0, limit),
      nextCursor: page.nextCursor,
      hasMore: Boolean(page.nextCursor),
    });
  } catch (error) {
    console.error("getActiveIncidents error", error);
    return serverError("Failed to load active incidents");
  }
};
