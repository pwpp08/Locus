// VO₂ max: the three tiers, the 14-in-21 gate, the weekly hold and the lab
// anchor. The numbers pinned here are the published equation's, worked by hand.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/vo2max_estimate.dart';

String _day(String from, int by) {
  final d = DateTime.parse(from);
  final x = DateTime(d.year, d.month, d.day + by);
  return '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
}

void main() {
  const start = '2026-08-03'; // a Monday
  const me = (age: 30, sex: 'm', weightKg: 75.0, heightCm: 177.0);

  /// Every day from [start] for [n] days, with [mod] and [vig] minutes.
  Map<String, double> daily(int n, double v) =>
      {for (var i = 0; i < n; i++) _day(start, i): v};

  Vo2Result run(
    int n, {
    double mod = 20,
    double vig = 10,
    List<Vo2Run> runs = const [],
    Vo2Lab? lab,
    Vo2Profile profile = me,
  }) =>
      estimateVo2max(
        today: _day(start, n - 1),
        firstDay: start,
        profile: profile,
        recovery: daily(n, 70),
        moderate: daily(n, mod),
        vigorous: daily(n, vig),
        runs: runs,
        lab: lab,
      );

  test('Jackson worked by hand', () {
    // 30 y, 24 BMI, PA-R 5, male: 56.363 + 9.605 − 11.43 − 18.096 + 10.987
    final v = jackson(
        paR: 5, age: 30, sex: 'm', weightKg: 24 * 1.8 * 1.8, heightCm: 180)!;
    expect(v, closeTo(47.43, .05));
    // A woman of the same age, BMI and activity sits 10.987 lower.
    final f = jackson(
        paR: 5, age: 30, sex: 'f', weightKg: 24 * 1.8 * 1.8, heightCm: 180)!;
    expect(v - f, closeTo(10.987, 1e-9));
  });

  test('the activity code is continuous and follows Jackson\'s codes', () {
    expect(paRFrom(moderateMin: 0, vigorousMin: 0), 1);
    expect(paRFrom(moderateMin: 60, vigorousMin: 0), 3);
    expect(paRFrom(moderateMin: 0, vigorousMin: 30), 5);
    expect(paRFrom(moderateMin: 0, vigorousMin: 60), 6);
    expect(paRFrom(moderateMin: 0, vigorousMin: 180), 7);
    expect(paRFrom(moderateMin: 500, vigorousMin: 500), 7);
    // One more minute never lowers it.
    var last = 0.0;
    for (var m = 0; m <= 200; m += 5) {
      final c = paRFrom(moderateMin: 0, vigorousMin: m.toDouble());
      expect(c, greaterThanOrEqualTo(last));
      last = c;
    }
  });

  test('the passive tier waits for 14 recoveries in 21 days', () {
    final early = run(13);
    expect(early.byDay, isEmpty);
    expect(early.why, contains('14 recoveries'));
    expect(early.recoveries, lessThan(14));
    // Two full weeks of wear: the first Monday after has a figure.
    final later = run(22);
    expect(later.byDay, isNotEmpty);
    expect(later.source, Vo2Source.passive);
  });

  test('more hard time a week is a higher estimate', () {
    final easy = run(35, mod: 10, vig: 0).latest!;
    final hard = run(35, mod: 10, vig: 40).latest!;
    expect(hard, greaterThan(easy));
  });

  test('a figure holds for the week and changes on a Monday', () {
    final r = run(42, vig: 10);
    // 2026-08-24 is a Monday, 08-30 the Sunday after it.
    final week = [for (var i = 0; i < 7; i++) r.byDay[_day('2026-08-24', i)]];
    expect(week.toSet().length, 1);
    expect(week.first, isNotNull);
  });

  test('a recent outdoor run stands in, as the middle of the last five', () {
    final r = run(35, runs: [
      (day: _day(start, 18), v: 44.0),
      (day: _day(start, 22), v: 50.0),
      (day: _day(start, 26), v: 46.0),
      // Run on the Monday of the last week: it is next week's figure.
      (day: _day(start, 28), v: 80.0),
    ]);
    expect(r.source, Vo2Source.gps);
    expect(r.latest, 46.0);
  });

  test('a run older than 90 days no longer counts', () {
    final r = run(130, runs: [(day: _day(start, 1), v: 60.0)]);
    expect(r.source, Vo2Source.passive);
  });

  test('a lab result anchors the series and keeps its shape', () {
    final plain = run(56, vig: 10);
    final labDay = _day(start, 35);
    final anchored = run(56, vig: 10, lab: (day: labDay, value: 55.0));
    expect(anchored.source, Vo2Source.lab);
    // The week of the test reads the test.
    expect(anchored.byDay[labDay], closeTo(55.0, 1e-9));
    // Every other week is the plain estimate, moved by the same gap.
    final gap = anchored.byDay[labDay]! - plain.byDay[labDay]!;
    for (final d in plain.byDay.keys) {
      expect(anchored.byDay[d]! - plain.byDay[d]!, closeTo(gap, 1e-9));
    }
  });

  test('without a profile it says what to add, not a number', () {
    final r = run(35,
        profile: (age: null, sex: 'm', weightKg: 75.0, heightCm: 177.0));
    expect(r.byDay, isEmpty);
    expect(r.why, contains('profile'));
  });

  test('nothing is estimated off an implausible profile', () {
    expect(
        jackson(paR: 5, age: 30, sex: null, weightKg: 70, heightCm: 175), isNull);
    expect(
        jackson(paR: 5, age: 30, sex: 'm', weightKg: 70, heightCm: 0), isNull);
  });
}
