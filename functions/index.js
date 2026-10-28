// Cloud Functions for the Kya Bro booking app (2nd gen).
//
// SECRET RULES — read before touching this file:
// - The Razorpay KEY ID is NOT a secret and NOT stored here: the owner
//   enters it in the admin app's Payments tab, it is saved in the
//   `content/settings` Firestore document, and both this file and the
//   booking app read it from Firebase at runtime.
// - The Razorpay SECRET lives ONLY as a Cloud Functions secret
//   (RAZORPAY_SECRET), set by the owner with:
//     firebase functions:secrets:set RAZORPAY_SECRET
//   It is never written to Firestore, the repo, or either app.
// - SMTP: host/port/user/sender/owner-email/test-recipient come from the
//   `content/smtp` Firestore document (admin SMTP tab). The SMTP password
//   lives ONLY as the SMTP_PASS function secret, except for a test send
//   where the owner may pass a password for that one send only (never
//   stored, never logged).
// - The SMTP account is sunmughan@gmail.com. Test mail goes ONLY to the
//   test recipient (default sunmughan@gmail.com). Booking mail goes ONLY
//   to the owner email, never to the test recipient.
// - Stats refresh: the Instagram Graph API is used ONLY when the owner
//   sets an INSTAGRAM_ACCESS_TOKEN secret. Without it the function reports
//   "needs_token" and writes no numbers. Numbers are never invented.
//
// Deploy (owner, needs their Google sign-in — see README "Owner steps"):
//   firebase deploy --only functions
// Set secrets first:
//   firebase functions:secrets:set RAZORPAY_SECRET
//   firebase functions:secrets:set SMTP_PASS
//   firebase functions:secrets:set INSTAGRAM_ACCESS_TOKEN   (optional)

const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const crypto = require('crypto');
const nodemailer = require('nodemailer');
const Razorpay = require('razorpay');

initializeApp();
const db = getFirestore();

const razorpaySecret = defineSecret('RAZORPAY_SECRET');
const smtpPass = defineSecret('SMTP_PASS');
const instagramToken = defineSecret('INSTAGRAM_ACCESS_TOKEN');

const TEST_RECIPIENT_FALLBACK = 'sunmughan@gmail.com';

async function getSettings() {
  const d = await db.collection('content').doc('settings').get();
  return d.data() || {};
}

async function getSmtpConfig() {
  const d = await db.collection('content').doc('smtp').get();
  return d.data() || {};
}

function razorpayClient(keyId) {
  return new Razorpay({
    key_id: keyId,
    key_secret: razorpaySecret.value(),
  });
}

function mailTransport({host, port, user, pass, from}) {
  return nodemailer.createTransport({
    host,
    port: Number(port) || 587,
    secure: Number(port) === 465,
    auth: {user, pass},
    from,
  });
}

// ---------------- Razorpay: server-side order ----------------
exports.createRazorpayOrder = onCall(
  {secrets: [razorpaySecret]},
  async (request) => {
    const bookingId = request.data && request.data.bookingId;
    if (!bookingId || typeof bookingId !== 'string') {
      throw new HttpsError('invalid-argument', 'bookingId is required.');
    }
    const bookingSnap = await db.collection('bookings').doc(bookingId).get();
    if (!bookingSnap.exists) {
      throw new HttpsError('not-found', 'Booking not found.');
    }
    const booking = bookingSnap.data();
    const total = Number(booking.totalPrice);
    if (!Number.isFinite(total) || total <= 0) {
      throw new HttpsError(
        'failed-precondition',
        'This booking has no price yet. The owner sets prices in the admin app first.',
      );
    }
    // Key ID comes from Firebase (admin-entered), never from this file.
    const settings = await getSettings();
    const keyId = (settings.razorpayKeyId || '').trim();
    if (!keyId.startsWith('rzp_')) {
      throw new HttpsError(
        'failed-precondition',
        'Razorpay Key ID is not set. Enter it in the admin app Payments tab first.',
      );
    }
    if (!razorpaySecret.value()) {
      throw new HttpsError(
        'failed-precondition',
        'Razorpay secret is not configured. Set it with: firebase functions:secrets:set RAZORPAY_SECRET',
      );
    }
    const order = await razorpayClient(keyId).orders.create({
      amount: Math.round(total * 100),
      currency: 'INR',
      receipt: bookingId.slice(0, 40),
      notes: {bookingId},
    });
    await db.collection('bookings').doc(bookingId).update({
      razorpayOrderId: order.id,
      paymentStatus: 'pending_payment',
    });
    return {orderId: order.id, keyId, amount: total};
  },
);

// ---------------- Razorpay: server-side signature verification ----------------
// Only a verified signature flips paymentStatus to 'paid'. A failed check
// flips it to 'failed'. Nothing on the client can mark a payment paid.
exports.verifyRazorpayPayment = onCall(
  {secrets: [razorpaySecret]},
  async (request) => {
    const {bookingId, paymentId, orderId, signature} = request.data || {};
    if (!bookingId || !paymentId || !orderId || !signature) {
      throw new HttpsError(
        'invalid-argument',
        'bookingId, paymentId, orderId and signature are all required.',
      );
    }
    if (!razorpaySecret.value()) {
      throw new HttpsError(
        'failed-precondition',
        'Razorpay secret is not configured on the server.',
      );
    }
    const expected = crypto
      .createHmac('sha256', razorpaySecret.value())
      .update(`${orderId}|${paymentId}`)
      .digest('hex');
    let verified = false;
    try {
      verified = crypto.timingSafeEqual(
        Buffer.from(expected),
        Buffer.from(signature),
      );
    } catch (_) {
      verified = false;
    }
    await db.collection('bookings').doc(bookingId).update({
      razorpayPaymentId: paymentId,
      razorpayOrderId: orderId,
      razorpaySignature: signature,
      paymentStatus: verified ? 'paid' : 'failed',
      paymentVerification: verified ? 'server_verified' : 'server_rejected',
    });
    return {verified};
  },
);

// ---------------- Booking notification mail (server trigger) ----------------
// Fires on booking creation. Sends ONLY to the owner email from the SMTP
// config doc, never to the test recipient, never a fake "sent" claim: if
// SMTP is not configured, the booking is annotated and the mail is skipped.
exports.onBookingCreated = onDocumentCreated(
  {document: 'bookings/{bookingId}', secrets: [smtpPass]},
  async (event) => {
    const booking = event.data.data();
    const bookingId = event.params.bookingId;
    const smtp = await getSmtpConfig();
    const ownerEmail = (smtp.ownerEmail || '').trim();
    if (!ownerEmail) {
      await db.collection('bookings').doc(bookingId).update({
        emailStatus: 'skipped_no_owner_email',
      });
      return;
    }
    if (!smtp.host || !smtp.user || !smtpPass.value()) {
      await db.collection('bookings').doc(bookingId).update({
        emailStatus: 'skipped_smtp_not_configured',
      });
      return;
    }
    const transporter = mailTransport({
      host: smtp.host,
      port: smtp.port,
      user: smtp.user,
      pass: smtpPass.value(),
      from: smtp.from || smtp.user,
    });
    const total =
      booking.totalPrice == null ? 'TBD (owner sets the price)' : booking.totalPrice;
    await transporter.sendMail({
      from: smtp.from || smtp.user,
      to: ownerEmail,
      subject: `New Kya Bro booking: ${booking.type || ''} — ${booking.slotDate || ''} ${booking.slotStart || ''}`,
      text: [
        `New booking ${bookingId}`,
        `Name: ${booking.name || ''}`,
        `Business / purpose: ${booking.purpose || ''}`,
        `Type: ${booking.type || ''}${booking.durationSeconds ? ` (${booking.durationSeconds}s)` : ''}${booking.storyCount ? ` x ${booking.storyCount}` : ''}`,
        `Package: ${booking.packageKind || 'none'}`,
        `Slot: ${booking.slotDate || ''} ${booking.slotStart || ''} - ${booking.slotEnd || ''}`,
        `Delivery needed by: ${booking.deliveryDue || ''}`,
        `Urgency: ${booking.urgencyTier || ''} (x${booking.multiplier || ''})`,
        `Base price: ${booking.basePrice == null ? 'TBD' : booking.basePrice}`,
        `Total: ${total}`,
        `Payment status: ${booking.paymentStatus || 'pending_payment'}`,
        '',
        'Confirm or update this booking in the Kya Bro admin app.',
      ].join('\n'),
    });
    await db.collection('bookings').doc(bookingId).update({
      emailStatus: 'sent_to_owner',
    });
  },
);

// ---------------- SMTP test mail (admin app button) ----------------
// Sends a TEST mail only, to the test recipient. With transient SMTP
// credentials in the request body, those are used for this one send and
// are never stored or logged. Otherwise the stored config + SMTP_PASS
// secret are used.
exports.sendTestMail = onCall(
  {secrets: [smtpPass]},
  async (request) => {
    const smtp = await getSmtpConfig();
    const t = (request.data && request.data.smtp) || {};
    const host = t.host || smtp.host;
    const port = t.port || smtp.port || 587;
    const user = t.user || smtp.user;
    const from = t.from || smtp.from || user;
    // Transient password wins for this send only; otherwise the secret.
    // The password value is never logged and never written anywhere.
    const pass = t.pass || smtpPass.value();
    const to = t.to || smtp.testRecipient || TEST_RECIPIENT_FALLBACK;
    if (!host || !user || !pass) {
      throw new HttpsError(
        'failed-precondition',
        'SMTP is not configured: set host/user in the admin SMTP tab and either type a password for this test or set the SMTP_PASS function secret.',
      );
    }
    const transporter = mailTransport({host, port, user, pass, from});
    await transporter.sendMail({
      from,
      to,
      subject: 'Kya Bro SMTP test mail',
      text: 'This is a test mail from the Kya Bro admin app SMTP settings. If you received this, SMTP is working. Booking notification mail goes to the owner email, not to this test address.',
    });
    return {sent: true, to};
  },
);

// ---------------- Creator stats refresh (real-time tracking) ----------------
// Instagram Graph API, ONLY when the owner sets an access token secret.
// Without a token it reports needs_token and writes no numbers. On API
// failure it records the error note only — never invented stats.
exports.refreshCreatorStats = onCall(
  {secrets: [instagramToken]},
  async () => {
    const token = instagramToken.value();
    if (!token) {
      return {
        status: 'needs_token',
        message:
          'No Instagram access token is configured. Set it with: firebase functions:secrets:set INSTAGRAM_ACCESS_TOKEN (a token for the @_kya_bro_ account with instagram_basic + pages_read_engagement), deploy functions, and tap Refresh again. Nothing was written.',
      };
    }
    try {
      const res = await fetch(
        'https://graph.instagram.com/me?fields=id,username,followers_count,media_count',
        {headers: {Authorization: `Bearer ${token}`}},
      );
      if (!res.ok) {
        const detail = await res.text();
        await db.collection('content').doc('stats').set(
          {
            lastError: `Instagram API ${res.status}: ${detail.slice(0, 200)}`,
            lastRefreshAttempt: new Date().toISOString(),
          },
          {merge: true},
        );
        return {
          status: 'error',
          message: `Instagram API returned ${res.status}. No numbers were written.`,
        };
      }
      const me = await res.json();
      const now = new Date().toISOString();
      await db.collection('content').doc('stats').set(
        {
          followersCount: me.followers_count ?? null,
          mediaCount: me.media_count ?? null,
          profileUrl: me.username
            ? `https://www.instagram.com/${me.username}/`
            : null,
          source: 'instagram_graph',
          updatedAt: now,
          lastError: null,
        },
        {merge: true},
      );
      return {
        status: 'ok',
        followersCount: me.followers_count ?? null,
        mediaCount: me.media_count ?? null,
      };
    } catch (e) {
      await db.collection('content').doc('stats').set(
        {
          lastError: `Refresh failed: ${String(e).slice(0, 200)}`,
          lastRefreshAttempt: new Date().toISOString(),
        },
        {merge: true},
      );
      return {status: 'error', message: `Refresh failed: ${e.message || e}`};
    }
  },
);

module.exports = {};
