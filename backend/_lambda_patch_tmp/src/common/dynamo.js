"use strict";

const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient } = require("@aws-sdk/lib-dynamodb");

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client, {
  marshallOptions: { removeUndefinedValues: true }
});

const tables = {
  sensor: process.env.SENSOR_TABLE_NAME,
  alert: process.env.ALERT_TABLE_NAME,
  workOrder: process.env.WORK_ORDER_TABLE_NAME,
  pushToken: process.env.PUSH_TOKEN_TABLE_NAME,
  settings: process.env.SETTINGS_TABLE_NAME,
  userProfile: process.env.USER_PROFILE_TABLE_NAME,
  authUser: process.env.AUTH_USER_TABLE_NAME,
  verification: process.env.VERIFICATION_CODE_TABLE_NAME,
  admin: process.env.ADMIN_TABLE_NAME
};

module.exports = { docClient, tables };
