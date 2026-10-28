import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart';

/// All Firestore access for both apps. Collection layout (see README):
///   content/profile            (single doc)
///   content/viral              (single doc)
///   content/engagement         (single doc)
///   content/settings           (single doc: nextDayMultiplier)
///   plans/<planId>             (Weekly, Monthly, Story packs, Video 30/45/60)
///   slots/<YYYY-MM-DD_HHmm>    (slot ledger: free/held/booked/blocked)
///   blockedDays/<YYYY-MM-DD>   (admin-blocked whole days)
///   bookings/<autoId>          (status new/confirmed/done)
///
/// [available] is false until Firebase is initialised with real config.
/// Callers must surface that state honestly; they must not substitute
/// invented content when Firestore is unavailable.
class FirestoreService {
  static bool available = false;
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Stream<Profile?> profileStream() => _db
      .collection('content')
      .doc('profile')
      .snapshots()
      .map((d) => d.data() == null ? null : Profile.fromMap(d.data()!));

  static Stream<ViralPick?> viralStream() => _db
      .collection('content')
      .doc('viral')
      .snapshots()
      .map((d) => d.data() == null ? null : ViralPick.fromMap(d.data()!));

  static Stream<Engagement?> engagementStream() => _db
      .collection('content')
      .doc('engagement')
      .snapshots()
      .map((d) => d.data() == null ? null : Engagement.fromMap(d.data()!));

  static Stream<AppSettings> settingsStream() => _db
      .collection('content')
      .doc('settings')
      .snapshots()
      .map((d) => d.data() == null
          ? const AppSettings(nextDayMultiplier: 1.25)
          : AppSettings.fromMap(d.data()!));

  static Future<AppSettings> settingsOnce() async {
    final d = await _db.collection('content').doc('settings').get();
    return d.data() == null
        ? const AppSettings(nextDayMultiplier: 1.25)
        : AppSettings.fromMap(d.data()!);
  }

  static Stream<List<Plan>> plansStream() => _db
      .collection('plans')
      .snapshots()
      .map((s) => s.docs.map((d) => Plan.fromMap(d.id, d.data())).toList());

  static Stream<List<Slot>> slotsForDayStream(DateTime day) {
    final prefix =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _db
        .collection('slots')
        .where('date', isEqualTo: prefix)
        .snapshots()
        .map((s) => s.docs.map((d) => Slot.fromMap(d.id, d.data())).toList());
  }

  static Stream<Set<String>> blockedDaysStream() => _db
      .collection('blockedDays')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());

  static Stream<List<Booking>> bookingsStream() => _db
      .collection('bookings')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Booking.fromMap(d.id, d.data())).toList());

  /// Booking write with server-side safety: the slot document is read and
  /// written inside ONE Firestore transaction, which rejects the write if
  /// the slot is no longer free — even if the UI were bypassed. UI
  /// disabling alone is never the only guard.
  static Future<String> bookSlotTransaction({
    required Map<String, dynamic> bookingData,
    required String slotId,
    required Map<String, dynamic> slotData,
  }) async {
    final slotRef = _db.collection('slots').doc(slotId);
    final bookingRef = _db.collection('bookings').doc();
    await _db.runTransaction((tx) async {
      final snap = await tx.get(slotRef);
      if (snap.exists) {
        final status = (snap.data()?['status'] ?? 'free') as String;
        if (status != 'free') {
          throw StateError('Slot already booked: $slotId ($status)');
        }
      }
      tx.set(slotRef, {
        ...slotData,
        'status': 'booked',
        'bookingId': bookingRef.id,
      });
      tx.set(bookingRef, {
        ...bookingData,
        'slotId': slotId,
        'status': 'new',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return bookingRef.id;
  }

  // ---- Admin writes (admin app only) ----
  static Future<void> saveProfile(Map<String, dynamic> data) =>
      _db.collection('content').doc('profile').set(data, SetOptions(merge: true));
  static Future<void> saveViral(Map<String, dynamic> data) =>
      _db.collection('content').doc('viral').set(data, SetOptions(merge: true));
  static Future<void> saveEngagement(Map<String, dynamic> data) => _db
      .collection('content')
      .doc('engagement')
      .set(data, SetOptions(merge: true));
  static Future<void> saveSettings(Map<String, dynamic> data) => _db
      .collection('content')
      .doc('settings')
      .set(data, SetOptions(merge: true));
  static Future<void> savePlan(String id, Map<String, dynamic> data) =>
      _db.collection('plans').doc(id).set(data, SetOptions(merge: true));
  static Future<void> deletePlan(String id) =>
      _db.collection('plans').doc(id).delete();
  static Future<void> setSlot(String id, Map<String, dynamic> data) =>
      _db.collection('slots').doc(id).set(data, SetOptions(merge: true));
  static Future<void> blockDay(String date, String reason) => _db
      .collection('blockedDays')
      .doc(date)
      .set({'reason': reason, 'blockedAt': FieldValue.serverTimestamp()});
  static Future<void> unblockDay(String date) =>
      _db.collection('blockedDays').doc(date).delete();
  static Future<void> setBookingStatus(String id, String status) =>
      _db.collection('bookings').doc(id).update({'status': status});

  /// Writes the owner-editable starter content (identity only).
  /// Followers, phone, email, engagement numbers and prices are
  /// deliberately NOT seeded: they stay empty until the owner fills them
  /// in the admin app (or the stats refresh function writes real values),
  /// so the public app never shows an unconfirmed number as fact.
  static Future<void> seedStarterContent() async {
    await saveProfile({
      'displayName': 'Kya Bro',
      'creatorName': 'Himanshu Sarwa',
      'handle': '@_kya_bro_',
      'city': 'Durg-Bhilai',
      'contentStyle': 'Comedy, roasts, reactions and vlogs',
      'bio': 'Book Kya Bro to make a video for you.',
    });
    await saveSettings({'nextDayMultiplier': 1.25});
  }

  // ---- Real-time tracking: creator stats, viral picks, SMTP config ----
  static Stream<CreatorStats?> statsStream() => _db
      .collection('content')
      .doc('stats')
      .snapshots()
      .map((d) => d.data() == null ? null : CreatorStats.fromMap(d.data()!));

  static Future<void> saveStats(Map<String, dynamic> data) =>
      _db.collection('content').doc('stats').set(data, SetOptions(merge: true));

  static Stream<List<ViralPick>> viralPicksStream() => _db
      .collection('viralPicks')
      .orderBy('fetchedAt', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => ViralPick.fromMap(d.data(), d.id)).toList());

  static Future<void> saveViralPick(Map<String, dynamic> data) =>
      _db.collection('viralPicks').add({
        ...data,
        'fetchedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> deleteViralPick(String id) =>
      _db.collection('viralPicks').doc(id).delete();

  static Stream<SmtpConfig?> smtpStream() => _db
      .collection('content')
      .doc('smtp')
      .snapshots()
      .map((d) => d.data() == null ? null : SmtpConfig.fromMap(d.data()!));

  /// Instagram connection STATUS stream (content/instagramConnection).
  /// This document never contains a token — only connected flag,
  /// username, IG user id and expiry — so it is safe for the admin app
  /// to read. The token itself is server-side only (adminSecrets).
  static Stream<InstagramConnection?> instagramConnectionStream() => _db
      .collection('content')
      .doc('instagramConnection')
      .snapshots()
      .map((d) =>
          d.data() == null ? null : InstagramConnection.fromMap(d.data()!));

  /// Saves NON-SECRET SMTP fields only. The password is never written here:
  /// it is a Cloud Functions secret set by the owner via the Firebase CLI.
  static Future<void> saveSmtpConfig(Map<String, dynamic> data) =>
      _db.collection('content').doc('smtp').set(data, SetOptions(merge: true));

  // ---- Payments ----
  static Future<void> setBookingPaymentStatus(String id, String status) =>
      _db.collection('bookings').doc(id).update({'paymentStatus': status});

  static Future<void> saveBookingPaymentDetails(
          String id, Map<String, dynamic> data) =>
      _db.collection('bookings').doc(id).update(data);
}
