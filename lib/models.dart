// Firestore document models. Every display value in the app comes from one
// of these documents (see README "Firestore layout"). Missing/empty docs
// mean "not set by the owner yet" and the UI shows TBD / updated-by-owner
// states — never invented numbers.

class Profile {
  final String displayName, creatorName, handle, city, contentStyle;
  final String? followersText, phone, email, bio;
  const Profile({
    required this.displayName,
    required this.creatorName,
    required this.handle,
    required this.city,
    required this.contentStyle,
    this.followersText,
    this.phone,
    this.email,
    this.bio,
  });
  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        displayName: (m['displayName'] ?? '') as String,
        creatorName: (m['creatorName'] ?? '') as String,
        handle: (m['handle'] ?? '') as String,
        city: (m['city'] ?? '') as String,
        contentStyle: (m['contentStyle'] ?? '') as String,
        followersText: m['followersText'] as String?,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        bio: m['bio'] as String?,
      );
  bool get isEmpty =>
      displayName.isEmpty && creatorName.isEmpty && handle.isEmpty;
}

class ViralPick {
  final String? id, title, videoUrl, note;
  const ViralPick({this.id, this.title, this.videoUrl, this.note});
  factory ViralPick.fromMap(Map<String, dynamic> m, [String? id]) => ViralPick(
        id: id,
        title: m['title'] as String?,
        videoUrl: m['videoUrl'] as String?,
        note: m['note'] as String?,
      );
  bool get isEmpty => title == null || title!.isEmpty;
}

class Engagement {
  final int? weekViews, weekLikes, weekComments, weekShares;
  final int? monthViews, monthLikes, monthComments, monthShares;
  const Engagement({
    this.weekViews, this.weekLikes, this.weekComments, this.weekShares,
    this.monthViews, this.monthLikes, this.monthComments, this.monthShares,
  });
  factory Engagement.fromMap(Map<String, dynamic> m) => Engagement(
        weekViews: (m['weekViews'] as num?)?.toInt(),
        weekLikes: (m['weekLikes'] as num?)?.toInt(),
        weekComments: (m['weekComments'] as num?)?.toInt(),
        weekShares: (m['weekShares'] as num?)?.toInt(),
        monthViews: (m['monthViews'] as num?)?.toInt(),
        monthLikes: (m['monthLikes'] as num?)?.toInt(),
        monthComments: (m['monthComments'] as num?)?.toInt(),
        monthShares: (m['monthShares'] as num?)?.toInt(),
      );
  bool get isEmpty =>
      weekViews == null && monthViews == null && weekLikes == null;
}

class Plan {
  final String id, name, kind; // kind: weekly | monthly | storyPack | video
  final double? basePrice; // null = TBD by owner
  final int? durationSeconds; // video plans only: 30, 45 or 60
  final int? storyCount; // story packs only
  const Plan({
    required this.id,
    required this.name,
    required this.kind,
    this.basePrice,
    this.durationSeconds,
    this.storyCount,
  });
  factory Plan.fromMap(String id, Map<String, dynamic> m) => Plan(
        id: id,
        name: (m['name'] ?? id) as String,
        kind: (m['kind'] ?? '') as String,
        basePrice: (m['basePrice'] as num?)?.toDouble(),
        durationSeconds: (m['durationSeconds'] as num?)?.toInt(),
        storyCount: (m['storyCount'] as num?)?.toInt(),
      );
}

class AppSettings {
  final double nextDayMultiplier; // owner-set, clamped to 1.25..1.30
  final String? razorpayKeyId; // owner-set in admin Payments tab; null = unset
  const AppSettings({required this.nextDayMultiplier, this.razorpayKeyId});
  factory AppSettings.fromMap(Map<String, dynamic> m) {
    final v = (m['nextDayMultiplier'] as num?)?.toDouble() ?? 1.25;
    final key = (m['razorpayKeyId'] as String?)?.trim();
    return AppSettings(
      nextDayMultiplier: v < 1.25 || v > 1.30 ? 1.25 : v,
      razorpayKeyId: key == null || key.isEmpty ? null : key,
    );
  }
}

/// Creator stats for the real-time tracking pipeline. Values come ONLY from
/// the stats refresh function (Instagram Graph API when the owner supplies a
/// token) or from manual owner entry in the admin app. `source` records
/// which one it was, so the public app never presents a manual number as a
/// live platform number. Null followersCount = not set yet, shown honestly.
class CreatorStats {
  final int? followersCount, mediaCount;
  final String? source; // 'instagram_graph' | 'manual' | null
  final String? updatedAtIso, lastError;
  const CreatorStats({
    this.followersCount,
    this.mediaCount,
    this.source,
    this.updatedAtIso,
    this.lastError,
  });
  factory CreatorStats.fromMap(Map<String, dynamic> m) => CreatorStats(
        followersCount: (m['followersCount'] as num?)?.toInt(),
        mediaCount: (m['mediaCount'] as num?)?.toInt(),
        source: m['source'] as String?,
        updatedAtIso: m['updatedAt'] as String?,
        lastError: m['lastError'] as String?,
      );
  bool get isEmpty => followersCount == null && mediaCount == null;
}

/// SMTP configuration. NON-SECRET fields only: host, port, user, sender,
/// owner email, test recipient. The SMTP password is NEVER stored here, in
/// the app, or in the repo — it lives only as a Cloud Functions secret
/// (see README "SMTP secrets"), set by the owner via the Firebase CLI.
class SmtpConfig {
  final String? host, user, from, ownerEmail, testRecipient;
  final int? port;
  const SmtpConfig({
    this.host,
    this.user,
    this.from,
    this.ownerEmail,
    this.testRecipient,
    this.port,
  });
  factory SmtpConfig.fromMap(Map<String, dynamic> m) => SmtpConfig(
        host: m['host'] as String?,
        user: m['user'] as String?,
        from: m['from'] as String?,
        ownerEmail: m['ownerEmail'] as String?,
        testRecipient: m['testRecipient'] as String?,
        port: (m['port'] as num?)?.toInt(),
      );
  bool get isEmpty => host == null || host!.isEmpty;
}

/// A bookable time slot. Doc id: `YYYY-MM-DD_HHmm`.
/// status: free | held | booked | blocked (admin-blocked day/time).
class Slot {
  final String id, date, startTime, endTime, status;
  final String? bookingId, blockReason;
  const Slot({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
  })  : bookingId = null,
        blockReason = null;
  Slot.withDetail({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.bookingId,
    this.blockReason,
  });
  factory Slot.fromMap(String id, Map<String, dynamic> m) =>
      Slot.withDetail(
        id: id,
        date: (m['date'] ?? '') as String,
        startTime: (m['startTime'] ?? '') as String,
        endTime: (m['endTime'] ?? '') as String,
        status: (m['status'] ?? 'free') as String,
        bookingId: m['bookingId'] as String?,
        blockReason: m['blockReason'] as String?,
      );
  bool get bookable => status == 'free';
  static String docIdFor(DateTime day, String hhmm) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}_$hhmm';

  /// End time for an hourly slot: start + 60 minutes, wrapping past midnight
  /// as 00:xx. Used instead of a "TBD" placeholder everywhere a slot end is
  /// stored, so booking records always carry a real end time.
  static String endTimeFor(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final total = (h * 60 + m + 60) % (24 * 60);
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

/// Booking statuses: new -> confirmed -> done. Payment is separate:
/// pending_payment until a Razorpay payment succeeds (or the owner confirms).
class Booking {
  final String id, name, purpose, type, status, paymentStatus;
  final String slotId, slotDate, slotStart, slotEnd;
  final int? storyCount, durationSeconds;
  final String? packageKind, urgencyTier;
  final double? multiplier, basePrice, totalPrice;
  final String? razorpayPaymentId, razorpayOrderId, paymentVerification;
  const Booking({
    required this.id,
    required this.name,
    required this.purpose,
    required this.type,
    required this.status,
    required this.paymentStatus,
    required this.slotId,
    required this.slotDate,
    required this.slotStart,
    required this.slotEnd,
    this.storyCount,
    this.durationSeconds,
    this.packageKind,
    this.urgencyTier,
    this.multiplier,
    this.basePrice,
    this.totalPrice,
    this.razorpayPaymentId,
    this.razorpayOrderId,
    this.paymentVerification,
  });
  factory Booking.fromMap(String id, Map<String, dynamic> m) => Booking(
        id: id,
        name: (m['name'] ?? '') as String,
        purpose: (m['purpose'] ?? '') as String,
        type: (m['type'] ?? '') as String,
        status: (m['status'] ?? 'new') as String,
        paymentStatus: (m['paymentStatus'] ?? 'pending_payment') as String,
        slotId: (m['slotId'] ?? '') as String,
        slotDate: (m['slotDate'] ?? '') as String,
        slotStart: (m['slotStart'] ?? '') as String,
        slotEnd: (m['slotEnd'] ?? '') as String,
        storyCount: (m['storyCount'] as num?)?.toInt(),
        durationSeconds: (m['durationSeconds'] as num?)?.toInt(),
        packageKind: m['packageKind'] as String?,
        urgencyTier: m['urgencyTier'] as String?,
        multiplier: (m['multiplier'] as num?)?.toDouble(),
        basePrice: (m['basePrice'] as num?)?.toDouble(),
        totalPrice: (m['totalPrice'] as num?)?.toDouble(),
        razorpayPaymentId: m['razorpayPaymentId'] as String?,
        razorpayOrderId: m['razorpayOrderId'] as String?,
        paymentVerification: m['paymentVerification'] as String?,
      );
}
