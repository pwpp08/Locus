// A ring-once alarm is for one instant, a skipped morning stays skipped on
// every path that arms the band, and a hand-started sleep is not a nap.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/accepted_naps.dart';
import 'package:openstrap_edge/models/alarm_item.dart';
import 'package:openstrap_edge/state/alarm_manager.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';

void main() {
  // Thursday evening.
  final thu = DateTime(2026, 11, 12, 22, 0);

  group('a ring-once alarm', () {
    const once = AlarmItem(id: 'a', hour: 6, minute: 30);

    test('is stamped with its one instant, and spent once that has passed',
        () {
      final a = once.stampedAt(thu);
      expect(a.nextOccurrence(thu), DateTime(2026, 11, 13, 6, 30));
      final after = DateTime(2026, 11, 13, 6, 31);
      // Not "06:30 tomorrow": it rang, or its moment went by.
      expect(a.nextOccurrence(after), isNull);
      expect(a.spentAt(after), isTrue);
      expect(a.spentAt(thu), isFalse);
    });

    test('survives a round trip, and a repeating alarm carries no stamp', () {
      final a = once.stampedAt(thu);
      final back = AlarmItem.decodeList(AlarmItem.encodeList([a])).single;
      expect(back.onceAt, a.onceAt);
      const weekly = AlarmItem(id: 'w', hour: 7, minute: 0, days: {1, 2});
      expect(weekly.stampedAt(thu).onceAt, isNull);
      // Made repeating: the stamp goes.
      expect(a.copyWith(days: {5}).stampedAt(thu).onceAt, isNull);
    });

    test('a new time is a new instant; the same time keeps its own', () {
      final a = once.stampedAt(thu);
      expect(a.stampedAt(thu.add(const Duration(hours: 1))).onceAt, a.onceAt);
      final moved = a.copyWith(hour: 5).stampedAt(thu);
      expect(moved.nextOccurrence(thu), DateTime(2026, 11, 13, 5, 30));
    });

    test('one saved before the stamp existed still reads the old way', () {
      expect(once.nextOccurrence(DateTime(2026, 11, 13, 6, 31)),
          DateTime(2026, 11, 14, 6, 30));
    });
  });

  group('what a headless sync arms', () {
    // Weekdays 07:00 with Friday skipped, and a ring-once for Friday 06:30.
    final list = AlarmItem.encodeList([
      const AlarmItem(
          id: 'w',
          hour: 7,
          minute: 0,
          days: {1, 2, 3, 4, 5},
          skipDay: '2026-11-13'),
      const AlarmItem(id: 'o', hour: 6, minute: 30).stampedAt(thu),
    ]);

    test('the ring-once alarm, not the skipped morning', () {
      expect(AlarmManager.nextFromStored(list, thu),
          DateTime(2026, 11, 13, 6, 30));
    });

    test('after it rang: Monday, since Friday is skipped and it is spent', () {
      expect(
          AlarmManager.nextFromStored(list, DateTime(2026, 11, 13, 6, 31)),
          DateTime(2026, 11, 16, 7, 0));
    });

    test('the phone\'s own alarm counts when it is sooner', () {
      final sys = DateTime(2026, 11, 13, 5, 0);
      expect(AlarmManager.nextFromStored(list, thu, systemAlarm: sys), sys);
      expect(AlarmManager.nextFromStored('[]', thu), isNull);
    });
  });

  test('the skip line goes once the skipped ring\'s time has passed', () {
    const a = AlarmItem(
        id: 'w', hour: 7, minute: 0, days: {5}, skipDay: '2026-11-13');
    expect(AlarmScreenView.skippedLabel(a, thu), 'Fri 13 Nov');
    expect(
        AlarmScreenView.skippedLabel(a, DateTime(2026, 11, 13, 6, 59)),
        'Fri 13 Nov');
    expect(AlarmScreenView.skippedLabel(a, DateTime(2026, 11, 13, 7, 0)),
        isNull);
  });

  group('a sleep started by hand', () {
    test('its text parses; anything else is no recording', () {
      expect(Prefs.parseRestPending('sleep|1763000000000'),
          (sleep: true, sinceSec: 1763000000));
      expect(Prefs.parseRestPending('nap|1763000000000')?.sleep, isFalse);
      expect(Prefs.parseRestPending(''), isNull);
      expect(Prefs.parseRestPending('walk|12'), isNull);
    });

    test('nothing inside it is proposed as a nap', () {
      const since = 1000;
      final kept = napsOutsideRecording([
        {'start_ts': 100, 'end_ts': 900}, // before it started
        {'start_ts': 900, 'end_ts': 1500}, // reaches into it
        {'start': 2000, 'end': 4000}, // inside it
      ], since);
      expect(kept, [
        {'start_ts': 100, 'end_ts': 900},
      ]);
    });
  });
}
