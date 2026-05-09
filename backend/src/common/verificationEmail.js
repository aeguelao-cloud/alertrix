"use strict";

const { SESv2Client, SendEmailCommand } = require("@aws-sdk/client-sesv2");

const ses = new SESv2Client({
  region: process.env.VERIFICATION_SES_REGION || process.env.AWS_REGION || "ap-southeast-5",
});

async function sendVerificationEmail({ toEmail, code, name }) {
  const fromEmail = process.env.ALERT_FROM_EMAIL;
  if (!fromEmail) {
    throw new Error("Missing ALERT_FROM_EMAIL");
  }

  const subject = "Alertrix verification code";
  const textBody = [
    "Your Alertrix verification code:",
    code,
    "",
    `Name: ${name}`,
    "This code expires in 10 minutes.",
  ].join("\n");

  const result = await ses.send(
    new SendEmailCommand({
      FromEmailAddress: fromEmail,
      Destination: {
        ToAddresses: [toEmail],
      },
      Content: {
        Simple: {
          Subject: { Data: subject },
          Body: {
            Text: { Data: textBody },
          },
        },
      },
    })
  );

  return {
    delivered: true,
    recipient: toEmail,
    messageId: result?.MessageId || null,
  };
}

module.exports = {
  sendVerificationEmail,
};
