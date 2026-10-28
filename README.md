# Kya Bro Booking

Book Himanshu Sarwa ("Kya Bro", @_kya_bro_, Durg-Bhilai) to make a video.
One Flutter codebase, two apps:

| App | Entry point | Build |
|---|---|---|
| Public booking app | `lib/main.dart` | `flutter build apk` / `flutter build appbundle` |
| Admin app (owner only) | `lib/main_admin.dart` | `flutter build apk -t lib/main_admin.dart` |

Stack: Flutter 3.35.4 (stable), Dart 3.9, Firebase (`firebase_core` +
`cloud_firestore`), Razorpay (`razorpay_flutter`), device calendar
(`device_calendar`), `url_launcher`. Android + iOS from the same code.
No preview banner, no AI badge, no AI-made marking anywhere in the app.

## What was built — public app (screens)

1. **Profile** — display name, creator name, handle, city, content style,
   followers line (from the stats pipeline, labelled by source), bio,
   "Book Kya Bro" button, direct-call button. Phone and email show only
   when the owner has set them in the admin app; unset means they are
   hidden, never a guessed value.
2. **Viral showcase** — recent viral video card (title, note, tap to open
   the video URL). Empty until the owner sets it in the admin app.
3. **Engagement** — this week + this month: views, likes, comments, shares.
   Empty until the owner sets real numbers in the admin app.
4. **Booking form** — type chips (Story / Video / Post / Carousel), story
   count selector (Story only), weekly/monthly package chips, video
   duration chips **30s / 45s / 60s ONLY** (no other duration option
   exists anywhere), name, business/purpose, day + time slot
   picker, delivery-needed-by picker, transparent price breakdown.
5. **Confirmation summary** — booking id, all booking fields, urgency
   tier + multiplier + formula, base/total (or TBD), payment status,
   "Pay now (Razorpay)" and "Add to my phone calendar" buttons, and the
   email note below.

## What was built — admin app (tabs)

- **Dashboard** — week/month booking counts, pending/confirmed/done
  counts, "Load starter profile content" (identity/contact only).
- **Plans & Pricing** — add/edit/delete plans (Weekly, Monthly, Story
  packs, Video 30/45/60); price left empty = TBD in the public app; the
  next-day urgency multiplier setting (owner sets 1.25–1.30, default
  1.25; values outside the range are rejected in the UI and clamped in
  code).
- **Payments** — Razorpay setup: enter the Key ID here and it is saved
  into Firebase (`content/settings`); the booking app reads it from
  Firebase at runtime. The secret is never entered here (see "Razorpay"
  below). Per-booking payment list with Mark paid / Mark failed.
- **Bookings** — list with detail dialog; Confirm / Done / back-to-New,
  plus Mark paid / Mark failed for payments.
- **Content** — profile text, viral pick + viral videos list, week/month
  engagement numbers, and real-time stats refresh (Instagram live fetch
  or manual owner entry, always labelled by source).
- **Slots** — pick a day, block/unblock the whole day, free/block a slot.
- **SMTP** — SMTP configuration screen (account sunmughan@gmail.com):
  host, port, user, sender, owner email, test recipient. The password
  field is used only for the test send tapped right after typing it and
  is never stored anywhere. Booking mail uses the SMTP_PASS function
  secret (see "SMTP email" below).

## Firestore is the source of truth (no hardcoded display content)

Widgets never contain display content. Every value on screen comes from
Firestore; a missing/empty document renders an honest TBD /
"updated by owner" state, never an invented number. After the owner
fills a value in the admin app, the public app shows it with no code
change.

```
content/profile            { displayName, creatorName, handle, city,
                             contentStyle, followersText, phone, email, bio }
content/viral              { title, videoUrl, note }
content/engagement         { weekViews, weekLikes, weekComments, weekShares,
                             monthViews, monthLikes, monthComments, monthShares }
content/stats              { followersCount, mediaCount, profileUrl, source,
                             updatedAt, lastError }
                             source: instagram_graph | manual
content/smtp               { host, port, user, from, ownerEmail, testRecipient }
                             NON-SECRET fields only. No password is ever stored here.
content/settings           { nextDayMultiplier, razorpayKeyId }
                             nextDayMultiplier: 1.25–1.30, default 1.25
                             razorpayKeyId: owner-entered in admin Payments tab;
                             booking app reads it from Firebase at runtime
viralPicks/<autoId>        { title, videoUrl, note, source, fetchedAt }
                             newest first; public app shows the top 3
plans/<planId>             { name, kind, basePrice, durationSeconds, storyCount }
                             kind: weekly | monthly | storyPack | video
                             basePrice null = TBD. Video durations: 30/45/60 only.
slots/<YYYY-MM-DD_HHmm>    { date, startTime, endTime, status, bookingId? }
                             status: free | held | booked | blocked
blockedDays/<YYYY-MM-DD>   { reason }
bookings/<autoId>          { name, purpose, type, storyCount?, durationSeconds?,
                             packageKind?, slotId, slotDate, slotStart, slotEnd,
                             deliveryDue, urgencyTier, multiplier, basePrice,
                             totalPrice?, paymentStatus, status, createdAt }
                             status: new | confirmed | done
                             paymentStatus: pending_payment | paid | failed
                             failed is set only by server signature
                             verification; a dismissed checkout stays
                             pending_payment so the booker can retry
                             razorpayOrderId, razorpayPaymentId,
                             razorpaySignature, paymentVerification?
                             emailStatus: sent_to_owner |
                             skipped_no_owner_email |
                             skipped_smtp_not_configured
```

Starter content: the admin Dashboard button writes profile identity and
settings only. Followers, phone, email, engagement numbers and prices
are deliberately NOT seeded, so the public app never shows an
unconfirmed number as fact. The owner fills them in the admin app (or
the stats refresh function writes real values).

## In-app booking calendar — visible occupancy (two guards)

- **UI guard:** the slot picker reads the live `slots` ledger for the
  chosen day plus `blockedDays`. Booked/blocked times render greyed and
  are not selectable (`onSelected: null`); a blocked day greys the whole
  day. Default day times are 09:00–18:00 hourly; a time with no slot
  document is treated as free until booked.
- **Server-side guard:** the booking write runs in a single Firestore
  transaction (`FirestoreService.bookSlotTransaction`): it re-reads the
  slot document inside the transaction and throws
  `Slot already booked` if the status is not `free`, even if the UI
  were bypassed. UI disabling alone is never the only guard.

## Calendar architecture — two layers, split on purpose

1. **Firestore slot ledger = shared availability (real time).** A slot
   is held/booked in Firestore first. This is what every booker sees,
   and it is what prevents double-booking. Free to run on Firestore's
   free tier at this scale; no server cost beyond Firebase itself.
2. **Device calendar = personal copy (free, no server cost).** After a
   booking is saved, the booker can tap "Add to my phone calendar".
   That writes one event to the phone's own calendar — Android Calendar
   Provider / iOS EventKit via `device_calendar`, after permission.
   It is a personal reminder only: it does NOT block the slot for other
   bookers and is never read back as availability.

So the answer to "can the phone's own calendar be used in real time to
keep it totally free": the phone calendar is free and is used, but it
cannot be the shared real-time availability — only the Firestore ledger
can, because one phone's calendar is invisible to other bookers.

## Urgency / priority pricing (precedence order, never ambiguous)

Multipliers apply to the owner-set base price. T = hours from booking
order to required delivery.

| # | Condition | Tier | Multiplier |
|---|---|---|---|
| 1 | T <= 12h | Within 12 hours (shoot + ready) | 2.0x (wins over everything, even next calendar day) |
| 2 | T <= 24h | Within 24 hours | 1.5x |
| 3 | Delivery date = next calendar day after order date | Next day delivery | Admin-set 1.25x–1.30x (default 1.25x) |
| 4 | Otherwise | Normal | 1.0x (covers 2+ calendar days out, including within 3 days and longer) |

Shown transparently at booking time: tier name, multiplier, and the
formula `base price x multiplier = total`. While the base price is
unset, the multiplier and formula are shown and the total reads
"TBD until a base price is set" — a base price is never invented to
make the math look complete. Logic lives in `lib/urgency.dart` and is
unit-tested in `test/urgency_test.dart` (6 tests, all passing).

## Razorpay — full flow, key ID from Firebase, secret server-side only

Flow: booker taps "Pay now" -> the app asks the `createRazorpayOrder`
Cloud Function for a server-side order -> checkout opens with that
order id -> on success the app asks the `verifyRazorpayPayment`
function to verify the signature -> only a server-verified payment
flips `paymentStatus` to `paid`; a failed verification flips it to
`failed`; a dismissed checkout stays `pending_payment` so the booker
can retry. A payment is never marked paid from the client alone.

Key storage, exactly as the owner confirmed it:

- **Key ID:** entered in the admin app Payments tab, saved into the
  `content/settings` Firestore document, and read by the booking app
  from Firebase at runtime. No rebuild is needed after changing it.
  The Key ID is a publishable checkout identifier, not a secret.
- **Secret:** NEVER in the repo, NEVER in Firestore, NEVER in either
  app. It lives only as a Cloud Functions secret, used server-side for
  order creation and signature verification:
  `firebase functions:secrets:set RAZORPAY_SECRET`, then deploy.
- **Fallback:** if Cloud Functions are not deployed yet, checkout opens
  directly with the Firebase key ID (or the build-time
  `--dart-define=RAZORPAY_KEY_ID=...` fallback) and the booking stays
  `pending_payment` with the payment ids recorded, so the owner can
  confirm it manually in the admin app. With no key anywhere, checkout
  is skipped gracefully and the booking saves as `pending_payment`.

## SMTP email — full implementation, account sunmughan@gmail.com

No SMTP credential is embedded in the app (that would leak it to every
install). `functions/index.js` is the complete server sender:

- **Booking mail:** the `onBookingCreated` trigger fires on every new
  booking document and emails the owner address from the admin SMTP
  tab, using the stored host/port/user/sender plus the SMTP_PASS
  function secret. Booking mail goes ONLY to the owner email, never to
  the test recipient. If SMTP is not configured, the booking is
  annotated (`emailStatus: skipped_smtp_not_configured`) and the mail
  is skipped, never faked as sent.
- **Test mail:** the admin SMTP tab's "Send test mail" button sends a
  test mail ONLY to the test recipient (default sunmughan@gmail.com).
  A password typed in that screen is used for that one test send only
  and is never stored anywhere; with the field empty, the function
  uses the stored config plus the SMTP_PASS secret.
- Set the secret with `firebase functions:secrets:set SMTP_PASS`, then
  `firebase deploy --only functions`.

## Real-time tracking — stats pipeline, honest about Instagram limits

- **Connect Instagram (no token to copy):** the admin Content tab has
  a "Connect Instagram" button. The creator taps it, logs in with the
  @_kya_bro_ Instagram account in the browser, and approves. The
  browser hands the auth code straight to the server callback
  (`instagramOAuthCallback`), which exchanges it server-side (code ->
  short-lived token -> long-lived token, ~60 days) and stores the
  token where only the server can read it: the
  `adminSecrets/instagram` Firestore document, which firestore.rules
  deny to ALL clients. The admin app reads only the token-free status
  document (`content/instagramConnection`: connected flag, username,
  IG user id, expiry) — the token never appears in either app, the
  repo, or chat, and the creator never sees, copies, or pastes one.
- **Admin refresh:** the Content tab's "Refresh from Instagram" button
  calls the `refreshCreatorStats` function, which uses the connected
  token to read followers/media counts from the Instagram Graph API
  and writes them to `content/stats` with source `instagram_graph`
  and an update time. Before expiry (within 7 days) the server
  refreshes the token itself with the Meta App Secret — no re-login.
  If the token is dead (expired/revoked), refresh marks the
  connection `needs_reconnect` and the admin card asks the creator to
  connect again; no stale numbers are shown as live.
- **Without a connection** the function returns `needs_token` and
  writes no numbers. On API failure it records only the error note.
  Numbers are never guessed, and automated unauthenticated scraping
  is not used: Instagram blocks it and it would violate platform
  terms. The old hand-set `INSTAGRAM_ACCESS_TOKEN` function secret
  still works as a fallback, but the connect button replaces it.
- **Manual entry:** the owner can also type a follower count in the
  admin app; it is stored with source `manual`, and the public app
  labels it "Set by owner" so a manual number is never presented as a
  live platform number.
- **Viral videos:** the admin Content tab maintains the `viralPicks`
  list (newest first); the public app shows the top 3. Week/month
  engagement numbers are owner-entered in the admin app until an
  insights-permitted token makes an automated fetch possible; until
  then they stay empty rather than estimated.

### Connect Instagram — one-time owner setup (do once, then the creator just taps Connect)

The creator's step is only "tap Connect, log in, approve". The setup
below is the owner's (sunmughan's) one-time work, and it is the only
part that needs any technical step:

1. Create a Meta developer app at developers.facebook.com and add the
   Instagram product. Note the App ID (a public identifier, not a
   secret) and the App Secret.
2. The @_kya_bro_ Instagram account must be a professional
   (Business/Creator) account linked to a Facebook Page (Page
   Settings). Add the creator as a tester on the Meta app: in
   Development mode only app-role users (admin/developer/tester) can
   log in and grant permissions, so no App Review is needed for this
   single-owner connection. For any wider public use, App Review for
   `instagram_basic` (and `instagram_manage_insights` if media
   insights are ever added) would be required — not needed here.
3. Deploy functions, then find the callback URL:
   `firebase functions:list` (the `instagramOAuthCallback` URL). Paste
   that URL into the Meta app as a Valid OAuth Redirect URI, and
   paste the same URL plus the App ID into the admin app's Instagram
   setup fields (Content tab, shown until setup is complete).
4. Set the secret (typed by you in your own terminal, never in chat):
   `firebase functions:secrets:set META_APP_SECRET`
   then `firebase deploy --only functions`.
5. In the admin app, the creator taps "Connect Instagram", logs in,
   and approves the `instagram_basic` + `pages_show_list` permissions
   (read account info/media and list the linked Page). The admin card
   then shows "Connected as @username • Token valid until <date>".
   Disconnect is a button in the same card; it deletes the server-held
   token immediately.

What is true and what is not: the token lasts ~60 days and refreshes
itself server-side, but Meta gives no permanent token — if the
creator changes their Instagram password, revokes the app, or
unlinks the Page, the connection dies and must be re-connected with
one tap. The token is never stored in a document any app can read;
if Firebase Auth is later added, the `content/*` write rules should
be tightened as the existing security note describes.

## Firebase app status — PREPARED, pending the owner's console step

No Firebase app has been created for Kya Bro yet, and no Google
sign-in was attempted (the agent has no user Google credentials and
must not ask for them). Everything else is ready: the full
collection/document layout above, `firestore.rules`,
`firestore.indexes.json`, `firebase.json`, the Cloud Functions in
`functions/` (with `functions/package.json`), and the admin + public
code paths. `.firebaserc` carries the placeholder project id
`YOUR_FIREBASE_PROJECT_ID`; replace it in step 1.

**Exact steps the user must do (owner steps, in order):**

1. Sign in to Google/Firebase yourself and create a new Firebase
   project (or use the Codeair apps area). In `.firebaserc`, replace
   `YOUR_FIREBASE_PROJECT_ID` with the real project id. Add an Android
   app (package `tech.codeair.kya_bro_booking`) and an iOS app (bundle
   id `tech.codeair.kyaBroBooking`).
2. Create a Firestore database and deploy the rules + indexes:
   `firebase deploy --only firestore`.
3. Run `flutterfire configure` (or copy the real values) and pass them
   as `--dart-define` values, or replace the placeholder
   `FirebaseOptions` in `lib/main.dart` / `lib/main_admin.dart` with
   the generated `firebase_options.dart`. Do NOT commit real keys to
   this public repo — use `--dart-define` at build time.
4. Deploy the functions and set the secrets (secret values are typed
   by you in your own terminal, never shared in chat):
   `firebase functions:secrets:set RAZORPAY_SECRET`
   `firebase functions:secrets:set SMTP_PASS`
   `firebase functions:secrets:set META_APP_SECRET` (Instagram connect)
   then `firebase deploy --only functions`. The old
   `INSTAGRAM_ACCESS_TOKEN` secret still works as a fallback but is no
   longer the way to connect — use the Connect Instagram button (see
   "Connect Instagram" above).
5. In the admin app, tap "Load starter profile content", then fill
   engagement numbers and plan prices; enter the Razorpay Key ID in
   the Payments tab; fill the SMTP screen (account
   sunmughan@gmail.com) and send a test mail. The public app then
   shows real content with no code change.
6. Build: CI builds Android APK/AAB on every push to main and iOS
   unsigned .app bundles on the macOS runner (see below). Or build
   locally with the commands under "Android build".

Until step 3 is done, the apps run but show the honest
"Firebase is not connected yet" banner and TBD/empty states, and
booking attempts explain the missing step instead of failing silently.
Live Firestore reads/writes cannot work before that step — that is the
one part of "fully functional" that is blocked on the console step,
and it is stated here plainly rather than claimed as working.

Security note: `firestore.rules` as shipped allows public reads and
booking creation (needed for a public booking app) and writes to
content/plans/slots/bookings. Before any wide public distribution,
enable Firebase Auth for the admin app and tighten the rules so only
an authenticated owner can write content/plans/slots and change
booking status; the commented authenticated variant is in the rules
file. The admin APK is distributed to the owner only, not published.

## iOS build code (CI macOS runner — unsigned .app, NOT a signed IPA)

`.github/workflows/ios.yml` builds both apps on `macos-latest` with
`flutter build ios --release --no-codesign` and uploads the unsigned
`.app` bundles as artifacts. An unsigned .app is NOT installable on a
real device as-is. To distribute:

1. On a Mac with Xcode: `cd kya-bro-booking && flutter build ipa`
   (public app) and `flutter build ipa -t lib/main_admin.dart`
   (admin app). Create the iOS app in Firebase first (step 1 above)
   and add the real `GoogleService-Info.plist`.
2. EventKit permission keys are already in `ios/Runner/Info.plist`:
   `NSCalendarsUsageDescription` and
   `NSCalendarsFullAccessUsageDescription` (plus reminders key).
   Calendar writes go through EventKit via `device_calendar`.
3. Signing: set the development team / bundle id in Xcode, or pass
   `--export-options-plist` for distribution. No store publish is done
   without a separate order. No signing certificate or provisioning
   profile lives in this repo.

## Android build

```
export JAVA_HOME=~/workspace/tools/jdk17 ANDROID_HOME=~/workspace/android-sdk
flutter build apk            # public app, lib/main.dart
flutter build apk -t lib/main_admin.dart   # admin app
flutter build appbundle      # AAB, if needed for Play
flutter test                 # urgency + tier tests
```

## Placeholders — complete list (nothing else is placeholder)

- Firebase config values (placeholders until the console step above).
- Razorpay Key ID (unset until the owner enters it in the admin
  Payments tab; build-time `--dart-define` is only a fallback).
- Razorpay secret, SMTP password, Meta App Secret (function secrets
  only, set by the owner via the Firebase CLI, never in this repo).
  The Instagram token itself is never in this repo at all: it is
  created by the Connect Instagram button and held server-side only.
- All plan base prices (TBD until the owner sets them in the admin app).
- All engagement numbers, creator stats and viral picks (empty until
  the owner sets them or the stats function refreshes real values).
- Himanshu's email and phone (empty until the owner fills a real
  address/number in the admin app; the starter seed no longer writes
  any phone, email or follower figure).
- The direct-call number shown comes from the Firestore profile
  document only when the owner has set it.

Video durations are 30 / 45 / 60 seconds only, everywhere. No WhatsApp
integration. No store publish has been done.
