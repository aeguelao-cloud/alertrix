"use strict";

const { GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { docClient, tables } = require("./dynamo");

const SETTINGS_ID = "device-location";
const defaultLocation = "Zone A - Pump Station";

async function getDeviceLocation() {
  const result = await docClient.send(
    new GetCommand({
      TableName: tables.settings,
      Key: { settingId: SETTINGS_ID }
    })
  );

  const item = result.Item || {};
  const location = String(item.location || "").trim();
  return {
    location: location || defaultLocation
  };
}

async function saveDeviceLocation(location) {
  const clean = String(location || "").trim();
  if (!clean) {
    throw new Error("Invalid location");
  }

  const payload = {
    settingId: SETTINGS_ID,
    location: clean,
    updatedAt: new Date().toISOString()
  };

  await docClient.send(
    new PutCommand({
      TableName: tables.settings,
      Item: payload
    })
  );

  return { location: clean };
}

module.exports = {
  getDeviceLocation,
  saveDeviceLocation
};

