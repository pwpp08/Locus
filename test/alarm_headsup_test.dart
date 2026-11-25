// The "alarm in 30 minutes" heads-up: its buttons turn today's ring off (Skip
// once) or push it later for that morning only, on the one stored list every
// reader shares.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/alarm_item.dart';
import 'package:openstrap_edge/notify/alarm_headsup.dart';

void main() {
  // A Monday.
  final monday6 = DateTime(2026, 11, 23, 6, 0);
  const weekdays = {1, 2, 3, 4, 5};
  const alarm = AlarmItem(
      id: 'a', hour: 7, minute: 0, days: weekdays, label: 'Gym');

  test('a delay moves that morning only', () {
    final d = alarm.delayedNext(15, monday6)!;
    expect(d.nextOccurrence(monday6), DateTime(2026, 11, 23, 7, 15));
    // Tuesday is untouched.
    expect(d.nextOccurrence(DateTime(2026, 11, 23, 8, 0)),
        DateTime(2026, 11, 24, 7, 0));
  });

  test('delays add up, and the moved ring is still ahead past the set time', () {
    final once = alarm.delayedNext(15, monday6)!;
    final twice = once.delayedNext(30, monday6)!;
    expect(twice.nextOccurrence(monday6), DateTime(2026, 11, 23, 7, 45));
    // 07:10: the set time has passed but the moved ring has not.
    expect(once.nextOccurrence(DateTime(2026, 11, 23, 7, 10)),
        DateTime(2026, 11, 23, 7, 15));
    // Once it has rung, the next morning is back to the set time.
    expect(once.nextOccurrence(DateTime(2026, 11, 23, 7, 16)),
        DateTime(2026, 11, 24, 7, 0));
  });

  test('skipping drops the next ring of a repeating alarm only', () {
    final s = alarm.skippedNext(monday6)!;
    expect(s.enabled, isTrue);
    expect(s.nextOccurrence(monday6), DateTime(2026, 11, 24, 7, 0));
    // A move made earlier is dropped with it.
    final moved = alarm.delayedNext(15, monday6)!.skippedNext(monday6)!;
    expect(moved.nextOccurrence(monday6), DateTime(2026, 11, 24, 7, 0));
  });

  test('skipping a ring-once alarm turns it off', () {
    const once = AlarmItem(id: 'o', hour: 7, minute: 0);
    final s = once.skippedNext(monday6)!;
    expect(s.enabled, isFalse);
    expect(s.nextOccurrence(monday6), isNull);
  });

  test('a ring-once alarm can be delayed too', () {
    final once = const AlarmItem(id: 'o', hour: 7, minute: 0)
        .stampedAt(monday6);
    final d = once.delayedNext(30, monday6)!;
    expect(d.nextOccurrence(monday6), DateTime(2026, 11, 23, 7, 30));
  });

  test('the move survives storage and an old list without it still reads', () {
    final d = alarm.delayedNext(15, monday6)!;
    final back = AlarmItem.decodeList(AlarmItem.encodeList([d])).single;
    expect(back.nextOccurrence(monday6), DateTime(2026, 11, 23, 7, 15));
    expect(alarm.toJson().containsKey('moveDay'), isFalse);
  });

  test('a button changes the stored list and nothing else', () {
    final stored = AlarmItem.encodeList([
      alarm,
      const AlarmItem(id: 'b', hour: 9, minute: 0, days: {6, 7}),
    ]);
    final out = applyAlarmAction(stored, kAlarmActionPlus15, 'a', monday6)!;
    final list = AlarmItem.decodeList(out);
    expect(list.firstWhere((a) => a.id == 'a').nextOccurrence(monday6),
        DateTime(2026, 11, 23, 7, 15));
    expect(list.firstWhere((a) => a.id == 'b').moveDay, isNull);
    // Not ours, or no such alarm: nothing to write.
    expect(applyAlarmAction(stored, 'other', 'a', monday6), isNull);
    expect(applyAlarmAction(stored, kAlarmActionSkip, 'gone', monday6), isNull);
  });

  test('the next ring is the earliest of our own alarms', () {
    final r = nextOwnRing([
      const AlarmItem(id: 'late', hour: 9, minute: 0, days: weekdays),
      alarm,
      const AlarmItem(id: 'off', hour: 6, minute: 30, enabled: false),
    ], monday6)!;
    expect(r.alarm.id, 'a');
    expect(r.at, DateTime(2026, 11, 23, 7, 0));
  });

  test('the payload names the alarm', () {
    expect(alarmIdFromPayload(alarmHeadsUpPayload('abc')), 'abc');
    expect(alarmIdFromPayload('/today'), isNull);
    expect(alarmIdFromPayload(null), isNull);
  });
}
