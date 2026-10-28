import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

/// Device calendar layer (free, no server cost).
/// Android: Calendar Provider. iOS: EventKit (see Info.plist keys in README).
/// This is a PERSONAL copy on the booker's own phone only. Shared
/// availability always lives in the Firestore slot ledger — the device
/// calendar is never the source of truth for availability, and it cannot
/// block a slot for other bookers.
class DeviceCalendarService {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  Future<bool> addConfirmedBooking({
    required String title,
    required DateTime start,
    required DateTime end,
    required String description,
  }) async {
    final perm = await _plugin.requestPermissions();
    if (!perm.isSuccess || !(perm.data ?? false)) return false;
    final calendars = await _plugin.retrieveCalendars();
    final writable = (calendars.data ?? [])
        .where((c) => c.isReadOnly == false)
        .toList();
    if (writable.isEmpty) return false;
    final event = Event(
      writable.first.id,
      title: title,
      start: tz.TZDateTime.from(start, tz.local),
      end: tz.TZDateTime.from(end, tz.local),
      description: description,
    );
    final result = await _plugin.createOrUpdateEvent(event);
    return result?.isSuccess == true;
  }
}
