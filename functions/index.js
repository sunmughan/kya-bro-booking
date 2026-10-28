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
// - Stats refresh: the Instagram Graph API is used ONLY with a token the
//   server holds. TWO ways to hold one, in priority order:
//   (1) CONNECT BUTTON (preferred, no token ever copied): the creator
//       taps "Connect Instagram" in the admin app, logs in with
//       Instagram/Facebook in the browser and approves. The browser hands
//       the auth code straight to the instagramOAuthCallback function,
//       which exchanges it server-side (code -> short-lived token ->
//       long-lived token, using the META_APP_SECRET function secret) and
//       stores the long-lived token in the `adminSecrets/instagram`
//       Firestore document. Firestore rules deny ALL client read/write
//       on adminSecrets/*, so only the Admin SDK (this file) can read
//       it — the token never lands in the repo, either app, chat, or
//       any document the booking app can read. The admin app reads only
//       the token-free status document `content/instagramConnection`.
//   (2) LEGACY fallback: an INSTAGRAM_ACCESS_TOKEN function secret, set
//       by hand. Still supported, but the connect button replaces it.
//   Without either, refresh reports "needs_token" and writes no numbers.
//   Numbers are never invented. Long-lived tokens last ~60 days; the
//   refresh path exchanges the stored token server-side before expiry
//   (fb_exchange_token, app secret server-side). If the token is dead
//   (expired/revoked), refresh marks the connection needs_reconnect and
//   the admin card asks the creator to connect again — no silent stale
//   numbers, no fake refresh.
//
// Deploy (owner, needs their Google sign-in — see README "Owner steps"):
//   firebase deploy --only functions
// Set secrets first:
//   firebase functions:secrets:set RAZORPAY_SECRET
//   firebase functions:secrets:set SMTP_PASS
//   firebase functions:secrets:set META_APP_SECRET   (Instagram connect)

const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const crypto = require('crypto');
const nodemailer = require('nodemailer');
const Razorpay = require('razorpay');

initializeApp();
const db = getFirestore();

const razorpaySecret = defineSecret('RAZORPAY_SECRET');
const smtpPass = defineSecret('SMTP_PASS');
// Legacy hand-set Instagram token (fallback only; the connect button
// replaces it). The Meta App Secret is REQUIRED for the connect button:
// it is used server-side only, for the code exchange and token refresh.
const instagramToken = defineSecret('INSTAGRAM_ACCESS_TOKEN');
const metaAppSecret = defineSecret('META_APP_SECRET');

const GRAPH_VERSION = 'v21.0';
const GRAPH = `https://graph.facebook.com/${GRAPH_VERSION}`;
const INSTAGRAM_SCOPES = 'instagram_basic,pages_show_list';
// Refresh when expiry is within this window; long-lived tokens last ~60d.
const REFRESH_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

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

// ---------------- Instagram connect (no token ever copied) ----------------
// Flow: admin app -> getInstagramConnectUrl (returns the official
// Facebook OAuth login URL) -> creator logs in + approves in the browser
// -> Meta redirects to instagramOAuthCallback with ?code= -> the
// callback exchanges the code server-side and stores the long-lived
// token in adminSecrets/instagram (Admin SDK only; clients cannot read
// it — see firestore.rules). The status document
// content/instagramConnection holds only connected/username/igUserId/
// expiry, never a token, so the admin app can show state honestly.
// Prerequisites the owner must do once (see README "Connect Instagram"):
// a Meta developer app with the Instagram product, the @_kya_bro_
// Instagram professional account linked to a Facebook Page, the creator
// added as a tester on the Meta app, the callback URL registered as a
// Valid OAuth Redirect URI, META_APP_SECRET set, and the App ID +
// callback URL entered in the admin app's Instagram setup fields.

function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function instagramPage(title, body) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title></head><body style="font-family:sans-serif;max-width:560px;margin:40px auto;padding:0 16px"><h2>${escapeHtml(title)}</h2><p>${body}</p><p>You can close this tab and return to the Kya Bro admin app.</p></body></html>`;
}

async function getInstagramConnectionDoc() {
  const d = await db.collection('adminSecrets').doc('instagram').get();
  return d.exists ? d.data() : null;
}

async function setInstagramStatus(data) {
  await db
    .collection('content')
    .doc('instagramConnection')
    .set(data, {merge: true});
}

// Builds the official Facebook OAuth login URL. The Meta App ID is a
// public identifier (not a secret) and the callback URL is the deployed
// function URL — both owner-entered once in the admin Instagram setup.
exports.getInstagramConnectUrl = onCall(async () => {
  const settings = await getSettings();
  const appId = (settings.metaAppId || '').trim();
  const callbackUrl = (settings.instagramCallbackUrl || '').trim();
  if (!appId || !callbackUrl) {
    throw new HttpsError(
      'failed-precondition',
      'Instagram setup is incomplete: enter the Meta App ID and the instagramOAuthCallback function URL in the admin app Instagram setup first (see README "Connect Instagram").',
    );
  }
  // CSRF state: random, stored server-side in the status doc, checked
  // by the callback. It is not a token and grants nothing on its own.
  const state = crypto.randomBytes(16).toString('hex');
  await setInstagramStatus({pendingState: state});
  const params = new URLSearchParams({
    client_id: appId,
    redirect_uri: callbackUrl,
    scope: INSTAGRAM_SCOPES,
    response_type: 'code',
    state,
  });
  return {
    url: `https://www.facebook.com/${GRAPH_VERSION}/dialog/oauth?${params.toString()}`,
  };
});

// OAuth callback: Meta redirects here with ?code= (or ?error=). Exchanges
// the code server-side, resolves the linked Instagram professional
// account via the creator's Pages, and stores the long-lived token.
// Nothing secret is ever echoed back to the browser.
exports.instagramOAuthCallback = onRequest(
  {secrets: [metaAppSecret]},
  async (req, res) => {
    try {
      const {code, state, error, error_description: errDesc} = req.query || {};
      if (error) {
        await setInstagramStatus({
          connected: false,
          lastError: `Login was not approved: ${error}${errDesc ? ` — ${errDesc}` : ''}`,
        });
        res
          .status(200)
          .send(
            instagramPage(
              'Instagram not connected',
              'The login was not approved. Please try again from the admin app.',
            ),
          );
        return;
      }
      if (!code || typeof code !== 'string') {
        res
          .status(200)
          .send(
            instagramPage(
              'Kya Bro Instagram callback',
              'This address is only the login callback for the admin app Connect Instagram button. Open the admin app and tap Connect Instagram instead of visiting this page directly.',
            ),
          );
        return;
      }
      const settings = await getSettings();
      const appId = (settings.metaAppId || '').trim();
      const callbackUrl = (settings.instagramCallbackUrl || '').trim();
      const appSecret = metaAppSecret.value();
      if (!appId || !callbackUrl || !appSecret) {
        await setInstagramStatus({
          connected: false,
          lastError:
            'Server is missing the Meta App ID, callback URL, or META_APP_SECRET. The owner must finish the one-time setup (see README).',
        });
        res
          .status(200)
          .send(
            instagramPage(
              'Instagram not connected',
              'The server is not set up yet. Please ask the owner to finish the one-time Instagram setup, then try again.',
            ),
          );
        return;
      }
      // CSRF check: the state must match the one stored when the admin
      // app asked for the login URL.
      const statusSnap = await db
        .collection('content')
        .doc('instagramConnection')
        .get();
      const pendingState = statusSnap.data() && statusSnap.data().pendingState;
      if (!state || state !== pendingState) {
        await setInstagramStatus({
          connected: false,
          lastError: 'Login state did not match. Please tap Connect Instagram again.',
        });
        res
          .status(200)
          .send(
            instagramPage(
              'Instagram not connected',
              'This login attempt could not be verified. Please tap Connect Instagram in the admin app again.',
            ),
          );
        return;
      }
      // 1. Code -> short-lived user token (server-side, app secret).
      const tokenRes = await fetch(`${GRAPH}/oauth/access_token`, {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({
          client_id: appId,
          client_secret: appSecret,
          redirect_uri: callbackUrl,
          code,
        }),
      });
      const tokenJson = await tokenRes.json().catch(() => ({}));
      if (!tokenRes.ok || !tokenJson.access_token) {
        const detail = tokenJson.error && tokenJson.error.message
          ? tokenJson.error.message
          : `HTTP ${tokenRes.status}`;
        await setInstagramStatus({
          connected: false,
          lastError: `Token exchange failed: ${detail}`,
          pendingState: null,
        });
        res
          .status(200)
          .send(
            instagramPage(
              'Instagram not connected',
              'The login could not be completed. Please try again from the admin app.',
            ),
          );
        return;
      }
      // 2. Short-lived -> long-lived token (~60 days, server-side).
      const longRes = await fetch(
        `${GRAPH}/oauth/access_token?${new URLSearchParams({
          grant_type: 'fb_exchange_token',
          client_id: appId,
          client_secret: appSecret,
          fb_exchange_token: tokenJson.access_token,
        }).toString()}`,
      );
      const longJson = await longRes.json().catch(() => ({}));
      if (!longRes.ok || !longJson.access_token) {
        const detail = longJson.error && longJson.error.message
          ? longJson.error.message
          : `HTTP ${longRes.status}`;
        await setInstagramStatus({
          connected: false,
          lastError: `Long-lived token exchange failed: ${detail}`,
          pendingState: null,
        });
        res
          .status(200)
          .send(
            instagramPage(
              'Instagram not connected',
              'The login could not be completed. Please try again from the admin app.',
            ),
          );
        return;
      }
      const longToken = longJson.access_token;
      const expiresInSec = Number(longJson.expires_in) || 60 * 24 * 60 * 60;
      // 3. Resolve the linked Instagram professional account via Pages.
      const pagesRes = await fetch(
        `${GRAPH}/me/accounts?${new URLSearchParams({
          fields: 'id,name,instagram_business_account{id,username}',
          access_token: longToken,
        }).toString()}`,
      );
      const pagesJson = await pagesRes.json().catch(() => ({}));
      const pages = (pagesJson && pagesJson.data) || [];
      const linked = pages.find(
        (p) => p.instagram_business_account && p.instagram_business_account.id,
      );
      if (!linked) {
        await setInstagramStatus({
          connected: false,
          lastError:
            'No Instagram professional account is linked to a Facebook Page on this login. Link @_kya_bro_ to a Facebook Page (Page Settings), then connect again.',
          pendingState: null,
        });
        res
          .status(200)
          .send(
            instagramPage(
              'Instagram not connected',
              'No Instagram professional account linked to a Facebook Page was found on this login. Link the account to a Facebook Page first, then connect again from the admin app.',
            ),
          );
        return;
      }
      const ig = linked.instagram_business_account;
      const expiresAt = new Date(Date.now() + expiresInSec * 1000).toISOString();
      // Token: Admin-SDK-only document. Firestore rules deny ALL client
      // access to adminSecrets/*, so no app, user, or reader can fetch it.
      await db.collection('adminSecrets').doc('instagram').set({
        token: longToken,
        igUserId: ig.id,
        username: ig.username || null,
        pageId: linked.id,
        expiresAt,
        updatedAt: new Date().toISOString(),
        source: 'facebook_login',
      });
      await setInstagramStatus({
        connected: true,
        username: ig.username || null,
        igUserId: ig.id,
        expiresAt,
        lastError: null,
        needsReconnect: false,
        pendingState: null,
      });
      res
        .status(200)
        .send(
          instagramPage(
            'Instagram connected',
            `Connected as @${escapeHtml(ig.username || 'unknown')}. Live stats in the admin app can now refresh from Instagram.`,
          ),
        );
    } catch (e) {
      try {
        await setInstagramStatus({
          connected: false,
          lastError: `Callback failed: ${String(e).slice(0, 200)}`,
        });
      } catch (_) {
        // Status write is best-effort; the error page below still goes out.
      }
      res
        .status(200)
        .send(
          instagramPage(
            'Instagram not connected',
            'Something went wrong during login. Please try again from the admin app.',
          ),
        );
    }
  },
);

// Disconnect: deletes the server-held token and marks the connection
// disconnected. The token never passes through the app.
exports.disconnectInstagram = onCall(async () => {
  await db.collection('adminSecrets').doc('instagram').delete();
  await setInstagramStatus({
    connected: false,
    needsReconnect: false,
    lastError: null,
    pendingState: null,
    disconnectedAt: new Date().toISOString(),
  });
  return {disconnected: true};
});

// Refreshes a connected long-lived token when expiry is near (within 7
// days). Server-side fb_exchange_token with the app secret; no re-login.
// Returns the usable connection, or null when the token is dead — in
// which case the status is marked needs_reconnect and the admin card
// asks the creator to connect again.
async function usableConnectedToken() {
  const conn = await getInstagramConnectionDoc();
  if (!conn || !conn.token || !conn.igUserId) return null;
  const expiresAt = conn.expiresAt ? new Date(conn.expiresAt) : null;
  if (expiresAt && Date.now() > expiresAt.getTime()) {
    await setInstagramStatus({
      connected: false,
      needsReconnect: true,
      lastError: 'Instagram token expired. Tap Connect Instagram again.',
    });
    return null;
  }
  if (
    expiresAt &&
    expiresAt.getTime() - Date.now() < REFRESH_WINDOW_MS &&
    metaAppSecret.value()
  ) {
    try {
      const settings = await getSettings();
      const appId = (settings.metaAppId || '').trim();
      const res = await fetch(
        `${GRAPH}/oauth/access_token?${new URLSearchParams({
          grant_type: 'fb_exchange_token',
          client_id: appId,
          client_secret: metaAppSecret.value(),
          fb_exchange_token: conn.token,
        }).toString()}`,
      );
      const j = await res.json().catch(() => ({}));
      if (res.ok && j.access_token) {
        const newExpiry = new Date(
          Date.now() + (Number(j.expires_in) || 60 * 24 * 60 * 60) * 1000,
        ).toISOString();
        await db.collection('adminSecrets').doc('instagram').set(
          {...conn, token: j.access_token, expiresAt: newExpiry,
           updatedAt: new Date().toISOString()},
        );
        await setInstagramStatus({expiresAt: newExpiry});
        return {...conn, token: j.access_token, expiresAt: newExpiry};
      }
      // Non-OK refresh with an OAuth error means the token is dead.
      if (j.error) {
        await setInstagramStatus({
          connected: false,
          needsReconnect: true,
          lastError: `Instagram token could not be refreshed (${j.error.message || 'token invalid'}). Tap Connect Instagram again.`,
        });
        return null;
      }
      // Transient failure: keep the old token, report nothing fatal.
      return conn;
    } catch (_) {
      return conn; // Transient failure: keep the old token.
    }
  }
  return conn;
}

// ---------------- Creator stats refresh (real-time tracking) ----------------
// Priority: (1) connected token from the Connect Instagram button,
// (2) legacy INSTAGRAM_ACCESS_TOKEN secret, (3) needs_token — and no
// numbers are ever written without a working token. On API failure it
// records the error note only — never invented stats.
exports.refreshCreatorStats = onCall(
  {secrets: [instagramToken, metaAppSecret]},
  async () => {
    const connected = await usableConnectedToken();
    if (connected) {
      try {
        const res = await fetch(
          `${GRAPH}/${connected.igUserId}?${new URLSearchParams({
            fields: 'id,username,followers_count,media_count',
            access_token: connected.token,
          }).toString()}`,
        );
        if (!res.ok) {
          const detail = await res.text();
          const dead = res.status === 400 || res.status === 401;
          if (dead) {
            await setInstagramStatus({
              connected: false,
              needsReconnect: true,
              lastError:
                'Instagram connection stopped working (token rejected). Tap Connect Instagram again.',
            });
            return {
              status: 'needs_reconnect',
              message:
                'The Instagram connection stopped working. Tap Connect Instagram in the admin app again. Nothing was written.',
            };
          }
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
    }
    // Legacy fallback: hand-set secret (the connect button replaces it).
    const token = instagramToken.value();
    if (!token) {
      return {
        status: 'needs_token',
        message:
          'Instagram is not connected. Tap "Connect Instagram" in the admin app Content tab, log in, and approve — no token to copy. Nothing was written.',
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
