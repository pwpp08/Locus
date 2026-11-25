// "Woke up to an alarm?" answered from the ring and the wake time.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/alarm_wake_answer.dart';

void main() {
  final day = DateTime(2026, 11, 24).millisecondsSinceEpoch ~/ 1000;
  int at(int h, int m) => day + h * 3600 + m * 60;

  test('rang and you were up soon after: yes, with the times', () {
    final a = alarmWakeAnswer(
        dayStart: day, firedSec: [at(6, 30)], wakeTs: at(6, 34))!;
    expect(a.woke, isTrue);
    expect(a.why, contains('rang at'));
    expect(a.why, contains('up by'));
  });

  test('already up before the ring: no', () {
    final a = alarmWakeAnswer(
        dayStart: day, firedSec: [at(6, 30)], wakeTs: at(6, 5))!;
    expect(a.woke, isFalse);
    expect(a.why, contains('before the alarm'));
  });

  test('slept on well past it: no', () {
    final a = alarmWakeAnswer(
        dayStart: day, firedSec: [at(6, 30)], wakeTs: at(7, 40))!;
    expect(a.woke, isFalse);
    expect(a.why, contains('slept until'));
  });

  test('a ring with no wake time yet is a yes', () {
    final a = alarmWakeAnswer(dayStart: day, firedSec: [at(7, 0)])!;
    expect(a.woke, isTrue);
  });

  test('no ring that morning says nothing either way', () {
    expect(alarmWakeAnswer(dayStart: day, firedSec: const [], wakeTs: at(7, 0)),
        isNull);
    // Yesterday morning's ring and the afternoon's are not this morning's.
    expect(
        alarmWakeAnswer(
            dayStart: day,
            firedSec: [at(6, 0) - 86400, at(15, 0)],
            wakeTs: at(7, 0)),
        isNull);
  });

  test('a snooze: the ring nearest your waking decides', () {
    final a = alarmWakeAnswer(
        dayStart: day,
        firedSec: [at(6, 30), at(6, 40), at(6, 50)],
        wakeTs: at(6, 52))!;
    expect(a.woke, isTrue);
    expect(a.why, contains('6:50'));
  });
}
