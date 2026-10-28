import 'package:flutter_test/flutter_test.dart';
import 'package:kya_bro_booking/models.dart';

void main() {
  group('Slot.endTimeFor', () {
    test('adds one hour to a morning slot', () {
      expect(Slot.endTimeFor('09:00'), '10:00');
    });
    test('wraps past midnight instead of producing 24:00', () {
      expect(Slot.endTimeFor('23:30'), '00:30');
    });
    test('keeps half-hour starts', () {
      expect(Slot.endTimeFor('17:30'), '18:30');
    });
  });

  group('AppSettings', () {
    test('clamps the next-day multiplier into 1.25..1.30', () {
      expect(AppSettings.fromMap({'nextDayMultiplier': 2.0}).nextDayMultiplier, 1.25);
      expect(AppSettings.fromMap({'nextDayMultiplier': 1.28}).nextDayMultiplier, 1.28);
    });
    test('razorpayKeyId is null when unset, kept when set', () {
      expect(AppSettings.fromMap({}).razorpayKeyId, isNull);
      expect(
        AppSettings.fromMap({'razorpayKeyId': 'rzp_test_EXAMPLE'}).razorpayKeyId,
        'rzp_test_EXAMPLE',
      );
      expect(AppSettings.fromMap({'razorpayKeyId': '  '}).razorpayKeyId, isNull);
    });
    test('metaAppId and instagramCallbackUrl are null when unset', () {
      expect(AppSettings.fromMap({}).metaAppId, isNull);
      expect(AppSettings.fromMap({}).instagramCallbackUrl, isNull);
      expect(
        AppSettings.fromMap({'metaAppId': '123', 'instagramCallbackUrl': 'https://example.invalid/cb'}).metaAppId,
        '123',
      );
    });
  });

  group('InstagramConnection', () {
    test('connected flag and username parse', () {
      final c = InstagramConnection.fromMap({
        'connected': true,
        'username': 'kya_bro_',
        'igUserId': '17841',
        'expiresAt': '2099-01-01T00:00:00.000Z',
      });
      expect(c.connected, isTrue);
      expect(c.username, 'kya_bro_');
      expect(c.isExpired, isFalse);
      expect(c.refreshDue, isFalse);
    });
    test('expired token reports expired and refresh due', () {
      final c = InstagramConnection.fromMap({
        'connected': true,
        'expiresAt': '2020-01-01T00:00:00.000Z',
      });
      expect(c.isExpired, isTrue);
      expect(c.refreshDue, isTrue);
    });
    test('expiry within 7 days reports refresh due but not expired', () {
      final soon = DateTime.now().add(const Duration(days: 3)).toIso8601String();
      final c = InstagramConnection.fromMap({'connected': true, 'expiresAt': soon});
      expect(c.isExpired, isFalse);
      expect(c.refreshDue, isTrue);
    });
    test('unknown expiry is neither expired nor refresh-due', () {
      final c = InstagramConnection.fromMap({'connected': false});
      expect(c.isExpired, isFalse);
      expect(c.refreshDue, isFalse);
    });
  });

  group('CreatorStats', () {
    test('isEmpty when no numbers are stored', () {
      expect(CreatorStats.fromMap({}).isEmpty, isTrue);
      expect(
        CreatorStats.fromMap({'followersCount': 10}).isEmpty,
        isFalse,
      );
    });
  });

  group('SmtpConfig', () {
    test('isEmpty without a host', () {
      expect(SmtpConfig.fromMap({}).isEmpty, isTrue);
      expect(SmtpConfig.fromMap({'host': 'smtp.gmail.com'}).isEmpty, isFalse);
    });
  });
}
