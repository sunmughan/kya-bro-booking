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
  final String? title, videoUrl, note;
  const ViralPick({this.title, this.videoUrl, this.note});
  factory ViralPick.fromMap(Map<String, dynamic> m) => ViralPick(
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
  const AppSettings({required this.nextDayMultiplier});
  factory AppSettings.fromMap(Map<String, dynamic> m) {
    final v = (m['nextDayMultiplier'] as num?)?.toDouble() ?? 1.25;
    return AppSettings(nextDayMultiplier: v < 1.25 || v > 1.30 ? 1.25 : v);
  }
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
}

/// Booking statuses: new -> confirmed -> done. Payment is separate:
/// pending_payment until a Razorpay payment succeeds (or the owner confirms).
class Booking {
  final String id, name, purpose, type, status, paymentStatus;
  final String slotId, slotDate, slotStart, slotEnd;
  final int? storyCount, durationSeconds;
  final String? packageKind, urgencyTier;
  final double? multiplier, basePrice, totalPrice;
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
      );
}
