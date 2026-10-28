// Urgency / priority pricing tiers.
// Base price itself is always owner-set (TBD until set in the admin app).
// Only the multiplier is computed here, in this exact precedence order so
// tiers never overlap ambiguously. T = hours from booking order to the
// required delivery time.
//   1. T <= 12h  -> 2.0x  (wins over everything, even next calendar day)
//   2. T <= 24h  -> 1.5x
//   3. delivery date is the next calendar day after the order date
//                -> admin-set value inside 1.25x..1.30x (default 1.25x)
//   4. otherwise  -> 1.0x  (normal, covers 2+ calendar days out)

class UrgencyResult {
  final String tierName;
  final double multiplier;
  final String formula;
  const UrgencyResult(this.tierName, this.multiplier, this.formula);
}

UrgencyResult calculateUrgency({
  required DateTime orderedAt,
  required DateTime deliveryDue,
  double? nextDayMultiplier,
}) {
  final hours = deliveryDue.difference(orderedAt).inMinutes / 60.0;
  double nextDay = nextDayMultiplier ?? 1.25;
  if (nextDay < 1.25 || nextDay > 1.30) nextDay = 1.25;
  String fmt(double m) => m.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');
  if (hours <= 12) {
    return UrgencyResult('Within 12 hours (shoot + ready)', 2.0,
        'base price x ${fmt(2.0)} = total');
  }
  if (hours <= 24) {
    return UrgencyResult('Within 24 hours', 1.5,
        'base price x ${fmt(1.5)} = total');
  }
  final orderDay = DateTime(orderedAt.year, orderedAt.month, orderedAt.day);
  final deliveryDay =
      DateTime(deliveryDue.year, deliveryDue.month, deliveryDue.day);
  if (deliveryDay.difference(orderDay).inDays == 1) {
    return UrgencyResult('Next day delivery', nextDay,
        'base price x ${fmt(nextDay)} = total');
  }
  return UrgencyResult(
      'Normal', 1.0, 'base price x ${fmt(1.0)} = total');
}

/// Total in the same currency unit as [basePrice], or null while the owner
/// has not set a base price. Never invent a base price to complete the math.
double? urgencyTotal({required double? basePrice, required double multiplier}) {
  if (basePrice == null) return null;
  return basePrice * multiplier;
}
