"use strict";

const { SESv2Client, SendEmailCommand } = require("@aws-sdk/client-sesv2");

const ses = new SESv2Client({
  region: process.env.VERIFICATION_SES_REGION || process.env.AWS_REGION || "ap-southeast-5",
});

async function sendVerificationEmail({ toEmail, code, name, purpose }) {
  const fromEmail = process.env.ALERT_FROM_EMAIL;
  if (!fromEmail) {
    throw new Error("Missing ALERT_FROM_EMAIL");
  }

  const { subject, textBody } = buildVerificationEmailContent({ code, name, purpose });

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

function buildVerificationEmailContent({ code, name, purpose }) {
  const normalizedPurpose = String(purpose || "register").trim().toLowerCase();
  const isReset = normalizedPurpose === "reset";
  const title = isReset ? "Alertrix Password Reset Verification" : "Alertrix Account Verification";
  const purposeLine = isReset ? "Purpose: Password reset" : "Purpose: Account registration";
  const subject = isReset
    ? "[Alertrix] Verification code - password reset"
    : "[Alertrix] Verification code - account registration";
  const safeName = String(name || "").trim();

  const textBody = [
    title,
    "--------------------------------",
    purposeLine,
    `Verification Code: ${String(code || "").trim() || "N/A"}`,
    `Name: ${safeName || "User"}`,
    "",
    "This code expires in 10 minutes.",
    "If you did not request this code, please ignore this email.",
  ].join("\n");

  return { subject, textBody };
}

module.exports = {
  sendVerificationEmail,
  buildVerificationEmailContent,
};
