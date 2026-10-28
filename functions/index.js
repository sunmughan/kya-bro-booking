// Cloud Function STUB — server-side SMTP email sender for new bookings.
// This file is NOT deployed yet and sends NOTHING on its own.
// Deploy steps (owner, Firebase console / firebase CLI):
//   1. `firebase init functions` in this project (or copy this file into
//      an existing functions folder), then `firebase deploy --only functions`.
//   2. Set SMTP credentials as function secrets / env config — NEVER in
//      this file and NEVER in the Flutter app:
//        firebase functions:secrets:set SMTP_HOST
//        firebase functions:secrets:set SMTP_USER
//        firebase functions:secrets:set SMTP_PASS
//        firebase functions:secrets:set OWNER_EMAIL   (Himanshu's email, once confirmed)
//   3. Fill in the nodemailer send below (requires the `nodemailer`
//      dependency) and redeploy.
// Until then, the app shows the booking summary for manual sending and
// never claims an email was sent.
//
// const {onDocumentCreated} = require('firebase-functions/v2/firestore');
// const nodemailer = require('nodemailer');
// exports.onBookingCreated = onDocumentCreated('bookings/{bookingId}', async (event) => {
//   const b = event.data.data();
//   const transporter = nodemailer.createTransport({
//     host: process.env.SMTP_HOST,
//     auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
//   });
//   await transporter.sendMail({
//     from: process.env.SMTP_USER,
//     to: process.env.OWNER_EMAIL,
//     subject: `New Kya Bro booking: ${b.type} — ${b.slotDate} ${b.slotStart}`,
//     text: JSON.stringify(b, null, 2),
//   });
// });
module.exports = {};
