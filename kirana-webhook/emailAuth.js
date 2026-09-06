require('dotenv').config();
const nodemailer = require('nodemailer');
const { getAuth } = require('firebase-admin/auth');

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.GMAIL_USER,
    pass: process.env.GMAIL_APP_PASSWORD,
  },
});

function generateOtp() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

async function sendOtpEmail(db, email) {
  const otp = generateOtp();
  const expiresAt = Date.now() + 10 * 60 * 1000; // 10 minutes

  await db.collection('emailOtps').doc(email).set({
    otp,
    expiresAt,
  });

      const info = await transporter.sendMail({
    from: `"DukanDesk" <${process.env.GMAIL_USER}>`,
    replyTo: process.env.GMAIL_USER,
    to: email,
    subject: `Your DukanDesk sign-in code`,
    text: `Hello,\n\nHere is your DukanDesk sign-in code: ${otp}\n\nThis code is valid for 10 minutes.\n\nThanks,\nDukanDesk Team`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 400px; margin: 0 auto; padding: 20px;">
        <p>Hello,</p>
        <p>Here is your DukanDesk sign-in code:</p>
        <h1 style="letter-spacing: 4px; color: #1E1B2E; font-size: 32px;">${otp}</h1>
        <p>This code is valid for 10 minutes.</p>
        <p>Thanks,<br>DukanDesk Team</p>
      </div>
    `,
  });
  console.log(`OTP sent to ${email}`);
  return true;
}

async function verifyOtpOnly(db, email, submittedOtp) {
  const otpDoc = await db.collection('emailOtps').doc(email).get();

  if (!otpDoc.exists) {
    throw new Error('No verification code found. Please request a new one.');
  }

  const { otp, expiresAt } = otpDoc.data();

  if (Date.now() > expiresAt) {
    throw new Error('Code expired. Please request a new one.');
  }

  if (submittedOtp !== otp) {
    throw new Error('Incorrect code.');
  }

  // Delete used OTP - just confirms the code was correct, nothing else
  await db.collection('emailOtps').doc(email).delete();

  return true;
}

module.exports = { sendOtpEmail, verifyOtpOnly };