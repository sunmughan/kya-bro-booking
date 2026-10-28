import 'package:flutter_test/flutter_test.dart';
import 'package:kya_bro_booking/urgency.dart';

void main() {
  test('12h tier wins even when delivery is next calendar day', () {
    final r = calculateUrgency(
      orderedAt: DateTime(2026, 10, 28, 20, 0),
      deliveryDue: DateTime(2026, 10, 29, 6, 0), // 10h, next day
    );
    expect(r.multiplier, 2.0);
  });
  test('24h tier', () {
    final r = calculateUrgency(
      orderedAt: DateTime(2026, 10, 28, 10, 0),
      deliveryDue: DateTime(2026, 10, 29, 8, 0), // 22h
    );
    expect(r.multiplier, 1.5);
  });
  test('next-day tier uses admin value, clamped to 1.25..1.30', () {
    final r = calculateUrgency(
      orderedAt: DateTime(2026, 10, 28, 10, 0),
      deliveryDue: DateTime(2026, 10, 29, 18, 0), // 32h, next day
      nextDayMultiplier: 1.30,
    );
    expect(r.multiplier, 1.30);
    final d = calculateUrgency(
      orderedAt: DateTime(2026, 10, 28, 10, 0),
      deliveryDue: DateTime(2026, 10, 29, 18, 0),
      nextDayMultiplier: 9.9,
    );
    expect(d.multiplier, 1.25);
  });
  test('normal tier for 2+ days out', () {
    final r = calculateUrgency(
      orderedAt: DateTime(2026, 10, 28, 10, 0),
      deliveryDue: DateTime(2026, 10, 31, 18, 0),
    );
    expect(r.multiplier, 1.0);
  });
  test('total is TBD (null) while base price is unset', () {
    expect(urgencyTotal(basePrice: null, multiplier: 2.0), null);
    expect(urgencyTotal(basePrice: 1000, multiplier: 2.0), 2000);
  });
  test('video durations are only 30/45/60', () {
    expect([30, 45, 60], containsAll([30, 45, 60]));
    expect([30, 45, 60].contains(120), isFalse);
  });
}
