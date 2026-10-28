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
   followers line, bio, "Book Kya Bro" button, direct-call button. The
   direct-call number is the public bio number, shown with a
   "public bio number, to confirm" note.
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
- **Bookings** — list with detail dialog; Confirm / Done / back-to-New.
- **Content** — profile text, viral pick, week/month engagement numbers.
- **Slots** — pick a day, block/unblock the whole day, free/block a slot.

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
content/settings           { nextDayMultiplier }   // 1.25–1.30, default 1.25
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
                             paymentStatus: pending_payment | paid
```

Starter content: the admin Dashboard button writes profile identity and
settings only. Engagement numbers and prices are deliberately NOT
seeded, so the public app never shows invented numbers.

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

## Razorpay — placeholder key only

The key is read only from `--dart-define=RAZORPAY_KEY_ID=...`
(see `lib/config.dart`; the default is the literal placeholder
`YOUR_RAZORPAY_KEY_ID_HERE`). No real key is stored anywhere in this
repo. With no key configured, checkout is skipped gracefully and the
booking is saved with `paymentStatus = pending_payment`; the owner
confirms it in the admin app. A payment is never faked as successful.
Build with a real key when the owner supplies one:

```
flutter build apk --dart-define=RAZORPAY_KEY_ID=rzp_live_xxxx
```

## SMTP email — server-side stub, NOT in-app

No SMTP credential is embedded in the app (that would leak it to every
install). The design is: booking saved to Firestore -> a server-side
email sender (Cloud Function) sends the SMTP email to Himanshu.
`functions/index.js` in this repo is that stub: deploy it, set the
SMTP credentials as Cloud Function secrets (never in code), and it
sends on every new booking document. Until it is deployed, the
confirmation screen shows the booking summary for manual sending, and
the app never claims an email was sent. This is the pending backend
step, documented honestly — not working email.

## Firebase app status — PREPARED, pending the owner's console step

No Firebase app has been created for Kya Bro yet, and no Google
sign-in was attempted (the agent has no user Google credentials and
must not ask for them). Everything else is ready: placeholder config
via `--dart-define` in `lib/config.dart`, the full collection/document
layout above, `firestore.rules`, and the admin + public code paths.

**Exact steps the user must do in the Firebase console:**

1. Create a new Firebase project (or use the Codeair apps area) and add
   an Android app (package `tech.codeair.kya_bro_booking`) and an iOS
   app (bundle id `tech.codeair.kyaBroBooking`).
2. Create a Firestore database and deploy `firestore.rules` from this
   repo (see "Security note" first).
3. Run `flutterfire configure` (or copy the real values) and pass them
   as `--dart-define` values, or replace the placeholder
   `FirebaseOptions` in `lib/main.dart` / `lib/main_admin.dart` with
   the generated `firebase_options.dart`. Do NOT commit real keys to
   this public repo — use `--dart-define` at build time.
4. In the admin app, tap "Load starter profile content", then fill
   engagement numbers and plan prices. The public app then shows real
   content with no code change.
5. Deploy `functions/index.js` and set SMTP secrets there (see above).
6. Supply a Razorpay key id at build time (see above) to enable
   checkout; without it bookings save as pending payment.

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

## iOS next step (no macOS host here — NOT built, NOT faked)

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
   without a separate order.

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
- Razorpay key id (placeholder until supplied at build time).
- All plan base prices (TBD until the owner sets them in the admin app).
- All engagement numbers and the viral pick (empty until the owner
  sets them in the admin app).
- Himanshu's email: the starter profile value is literally
  "to confirm" until the owner fills a real address.
- SMTP sending: stub only until `functions/index.js` is deployed with
  secrets set server-side.
- The direct-call number shown comes from the Firestore profile
  document (starter value: the public bio number from the brief).

Video durations are 30 / 45 / 60 seconds only, everywhere. No WhatsApp
integration. No store publish has been done.
