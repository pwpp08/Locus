// Turning off a repeating alarm can skip just its next morning.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/alarm_item.dart';
import 'package:openstrap_edge/state/alarm_manager.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart' show AlarmScreenView;

void main() {
  // Wed 5 Nov 2026, 22:00. The alarm rings Mon, Tue, Thu, Fri at 06:10.
  final now = DateTime(2026, 11, 5, 22);
  const a = AlarmItem(id: 'a', hour: 6, minute: 10, days: {1, 2, 4, 5});

  test('a skip drops only that morning', () {
    expect(a.nextOccurrence(now), DateTime(2026, 11, 6, 6, 10));
    final skipped = a.copyWith(skipDay: AlarmItem.dayKey(a.nextUnskipped(now)!));
    expect(skipped.skipDay, '2026-11-06');
    // Friday is skipped; the next ring is Monday.
    expect(skipped.nextOccurrence(now), DateTime(2026, 11, 9, 6, 10));
    // After the skipped day has passed it never matches again.
    expect(skipped.nextOccurrence(DateTime(2026, 11, 9, 7)),
        DateTime(2026, 11, 10, 6, 10));
  });

  test('the skip survives a save and can be cleared', () {
    final s = a.copyWith(skipDay: '2026-11-06');
    final back = AlarmItem.decodeList(AlarmItem.encodeList([s])).single;
    expect(back.skipDay, '2026-11-06');
    expect(back.copyWith(clearSkip: true).skipDay, isNull);
    expect(a.toJson().containsKey('skipDay'), isFalse);
  });

  test('a one-shot alarm has nothing to skip', () {
    const once = AlarmItem(id: 'o', hour: 7, minute: 0);
    expect(once.nextUnskipped(now), isNull);
  });

  test('the alarm list is always earliest time first', () {
    final m = AlarmManager()
      ..debugSetAlarms(const [
        AlarmItem(id: 'late', hour: 22, minute: 0, days: {1}),
        AlarmItem(id: 'early', hour: 5, minute: 45, days: {1}),
        AlarmItem(id: 'mid', hour: 7, minute: 30, days: {1}),
        AlarmItem(id: 'mid2', hour: 7, minute: 5, days: {1}),
      ]);
    expect([for (final x in m.alarms) x.id], ['early', 'mid2', 'mid', 'late']);
  });

  test('a skipped night reads as off until the skipped ring has passed', () {
    final skipped = a.copyWith(skipDay: '2026-11-06');
    expect(AlarmScreenView.skippedLabel(skipped, now), isNotNull);
    // The ring after it: the skip is spent and the alarm is plainly on again.
    expect(AlarmScreenView.skippedLabel(skipped, DateTime(2026, 11, 6, 6, 11)),
        isNull);
  });
}
