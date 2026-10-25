// What each alarm mode waits for, and when it may buzz early.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/alarm_item.dart';
import 'package:openstrap_edge/state/alarm_mode.dart';

void main() {
  final deadline = DateTime(2026, 8, 17, 6, 30);

  test('an exact alarm has no goal and never buzzes early', () {
    expect(goalInBedMin(AlarmMode.exact, 510), isNull);
    final onset = DateTime(2026, 8, 16, 22, 0);
    expect(
        goalWakeAt(
            mode: AlarmMode.exact,
            deadline: deadline,
            onset: onset,
            inBedMin: 510),
        deadline);
    expect(
        goalBuzzDue(
            mode: AlarmMode.exact,
            deadline: deadline,
            now: DateTime(2026, 8, 17, 6, 10),
            onset: onset,
            inBedMin: 510),
        isFalse);
  });

  test('a sleep goal wakes you when the time in bed has passed', () {
    // Asleep at 22:00, 8:30 in bed: the goal is met at 06:30, which is the
    // deadline itself. Asleep at 21:30, it is met at 06:00 (inside the window).
    final early = DateTime(2026, 8, 16, 21, 30);
    expect(
        goalWakeAt(
            mode: AlarmMode.sleepGoal,
            deadline: deadline,
            onset: early,
            inBedMin: 510),
        DateTime(2026, 8, 17, 6, 0));
    bool due(DateTime now) => goalBuzzDue(
        mode: AlarmMode.sleepGoal,
        deadline: deadline,
        now: now,
        onset: early,
        inBedMin: 510);
    expect(due(DateTime(2026, 8, 17, 5, 59)), isFalse);
    expect(due(DateTime(2026, 8, 17, 6, 0)), isTrue);
    // Not past the set time: the band's own alarm takes it from there.
    expect(due(DateTime(2026, 8, 17, 6, 30)), isFalse);
  });

  test('never earlier than the window, never later than the set time', () {
    // Asleep at 18:00 with a short goal: held at the start of the window.
    expect(
        goalWakeAt(
            mode: AlarmMode.sleepGoal,
            deadline: deadline,
            onset: DateTime(2026, 8, 16, 18, 0),
            inBedMin: 300),
        DateTime(2026, 8, 17, 5, 30));
    // Asleep at 01:00: the goal would be met after the set time, so the set time.
    expect(
        goalWakeAt(
            mode: AlarmMode.sleepGoal,
            deadline: deadline,
            onset: DateTime(2026, 8, 17, 1, 0),
            inBedMin: 510),
        deadline);
  });

  test('in the green waits half an hour longer than the goal', () {
    expect(goalInBedMin(AlarmMode.sleepGoal, 480), 480);
    expect(goalInBedMin(AlarmMode.inTheGreen, 480), 480 + kGreenMarginMin);
    final onset = DateTime(2026, 8, 16, 21, 30);
    expect(
        goalWakeAt(
            mode: AlarmMode.inTheGreen,
            deadline: deadline,
            onset: onset,
            inBedMin: 480),
        DateTime(2026, 8, 17, 6, 0));
  });

  test('with no need or no onset the alarm is exact', () {
    expect(goalInBedMin(AlarmMode.sleepGoal, null), isNull);
    expect(
        goalWakeAt(
            mode: AlarmMode.sleepGoal,
            deadline: deadline,
            onset: null,
            inBedMin: 480),
        deadline);
  });

  test('the onset is where the first still, quiet stretch begins', () {
    final base = DateTime(2026, 8, 16, 21, 0).millisecondsSinceEpoch ~/ 1000;
    // Two hours up (high HR, moving), then four hours asleep.
    final samples = <NightSample>[
      for (var s = 0; s < 7200; s++) (t: base + s, hr: 78, motion: .3),
      for (var s = 7200; s < 7200 + 4 * 3600; s++)
        (t: base + s, hr: 52, motion: .01),
    ];
    final onset = estimateSleepOnset(samples)!;
    expect(onset.millisecondsSinceEpoch ~/ 1000, base + 7200);
    // Too little to say.
    expect(estimateSleepOnset(samples.take(600).toList()), isNull);
    // Never still: no onset.
    expect(
        estimateSleepOnset([
          for (var s = 0; s < 7200; s++) (t: base + s, hr: 78, motion: .3),
        ]),
        isNull);
  });

  test('the planner\'s time in bed comes from the sleep coach', () {
    final insights = {
      'sleep_coach': {
        'bedtime': {
          'value': {'bedtime_min_of_day': 22 * 60}
        },
        'wake': {
          'value': {'wake_min_of_day': 6 * 60 + 30}
        },
      },
    };
    expect(inBedMinFromInsights(insights), 510);
    expect(inBedMinFromInsights({}), isNull);
  });

  test('an alarm keeps its mode through storage', () {
    const a = AlarmItem(
        id: 'a', hour: 6, minute: 30, mode: AlarmMode.inTheGreen, days: {1, 2});
    final back = AlarmItem.fromJson(a.toJson());
    expect(back.mode, AlarmMode.inTheGreen);
    expect(back.earlyWindowMinutes, kGoalWindowMin);
    // One stored before modes existed is exact, with its own smart window.
    final old = AlarmItem.fromJson({
      'id': 'b',
      'hour': 7,
      'minute': 0,
      'smartWindowMinutes': 30,
    });
    expect(old.mode, AlarmMode.exact);
    expect(old.earlyWindowMinutes, 30);
  });
}
