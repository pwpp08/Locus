// Stress Monitor: what the 0–3 score does with heart rate, HRV and motion.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/stress_monitor.dart';

StressDayInput _day(
  String day, {
  double hr = 62,
  double? hrv = 70,
  double? motion = 0,
  bool withMotion = true,
}) =>
    StressDayInput(
      day: day,
      hr: List.filled(StressDayInput.minutes, hr),
      hrv: List.filled(StressDayInput.minutes, hrv),
      motion: withMotion ? List.filled(StressDayInput.minutes, motion) : null,
      asleep: List.filled(StressDayInput.minutes, false),
    );

List<StressDayInput> _history(int n) => [
      for (var i = 0; i < n; i++) _day('2026-05-${(i + 1).toString().padLeft(2, '0')}'),
    ];

void main() {
  test('a baseline needs three usable days, not a weekend of one', () {
    expect(stressBaseline(_history(2)), isNull);
    final b = stressBaseline(_history(14))!;
    expect(b.days, 14);
    expect(b.hr, 62);
    expect(b.motionKnown, isTrue);
  });

  test('a minute at baseline reads low, and is the same number every time', () {
    final b = stressBaseline(_history(14))!;
    final s = stressScores(_day('2026-05-20'), b);
    expect(s.first, closeTo(.8, 1e-9));
    expect(stressLevel(s.first!), StressLevel.low);
  });

  test('a faster heart and a flatter HRV score higher, and each counts', () {
    final b = stressBaseline(_history(14))!;
    final base = stressScores(_day('2026-05-20'), b).first!;
    final fast = stressScores(_day('2026-05-20', hr: 72), b).first!;
    final flat = stressScores(_day('2026-05-20', hrv: 40), b).first!;
    final both = stressScores(_day('2026-05-20', hr: 72, hrv: 40), b).first!;
    expect(fast, greaterThan(base));
    expect(flat, greaterThan(base));
    expect(both, greaterThan(fast));
    expect(both, greaterThan(flat));
    expect(both, lessThanOrEqualTo(3));
  });

  test('a calmer minute than usual scores lower than baseline', () {
    final b = stressBaseline(_history(14))!;
    final calm = stressScores(_day('2026-05-20', hr: 55, hrv: 95), b).first!;
    expect(calm, lessThan(.8));
    expect(calm, greaterThanOrEqualTo(0));
  });

  test('motion takes the exertion out of the score', () {
    final b = stressBaseline(_history(14))!;
    final still = stressScores(_day('2026-05-20', hr: 120, hrv: 20), b).first!;
    final running =
        stressScores(_day('2026-05-20', hr: 120, hrv: 20, motion: .6), b).first!;
    expect(still, 3);
    expect(running, lessThan(still));
    expect(stressLevel(running), isNot(StressLevel.high),
        reason: 'a run is not a stress event');
  });

  test('no HRV for a minute still scores, at reduced weight', () {
    final b = stressBaseline(_history(14))!;
    final withHrv = stressScores(_day('2026-05-20', hr: 72, hrv: 70), b).first!;
    final without = stressScores(_day('2026-05-20', hr: 72, hrv: null), b).first!;
    expect(without, greaterThan(.8));
    expect(without, lessThan(withHrv + 1));
  });

  test('a strap with no motion says so, and still builds a baseline', () {
    final b = stressBaseline([
      for (var i = 0; i < 5; i++)
        _day('2026-05-0${i + 1}', withMotion: false),
    ])!;
    expect(b.motionKnown, isFalse);
  });

  test('a minute with no heart rate has no score, not a zero', () {
    final b = stressBaseline(_history(14))!;
    final d = StressDayInput(
      day: '2026-05-20',
      hr: List.filled(1440, null),
      hrv: List.filled(1440, 70),
      motion: List.filled(1440, 0),
      asleep: List.filled(1440, false),
    );
    expect(stressScores(d, b).every((v) => v == null), isTrue);
  });

  test('levels split at 1 and 2, and minutes are counted by level', () {
    expect(stressLevel(.99), StressLevel.low);
    expect(stressLevel(1), StressLevel.medium);
    expect(stressLevel(1.99), StressLevel.medium);
    expect(stressLevel(2), StressLevel.high);
    final m = stressMinutes([.2, .9, 1.5, null, 2.5, 3]);
    expect((m.low, m.medium, m.high), (2, 1, 2));
  });

  test('a timeline payload lands on the right minutes of the right day', () {
    int ts(int h, int m) => DateTime(2026, 5, 20, h, m).millisecondsSinceEpoch ~/ 1000;
    final d = StressDayInput.fromTimeline('2026-05-20', {
      'hr': [
        {'t': ts(8, 0), 'v': 64},
        {'t': DateTime(2026, 5, 19, 8, 0).millisecondsSinceEpoch ~/ 1000, 'v': 99},
      ],
      'hrv': [
        {'t': ts(8, 0), 'v': 70},
      ],
      'activity': [
        {'t': ts(8, 0), 'v': .1},
      ],
      'sleep': [
        {'onset_ts': ts(0, 0), 'wake_ts': ts(6, 30)},
      ],
    });
    expect(d.hr[8 * 60], 64);
    expect(d.hr.where((v) => v != null), hasLength(1),
        reason: 'the point from yesterday is not today\'s');
    // HRV is a 5-minute window: held for four minutes, then gone.
    expect(d.hrv[8 * 60 + 4], 70);
    expect(d.hrv[8 * 60 + 5], isNull);
    expect(d.motion![8 * 60 + 3], .1);
    expect(d.asleep[3 * 60], isTrue);
    expect(d.asleep[7 * 60], isFalse);
  });
}
