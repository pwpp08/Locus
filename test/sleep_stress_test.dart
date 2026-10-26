// High sleep stress: the share of a night's minutes in the high zone against
// the person's OWN earlier nights — not against their waking baseline, which
// would call every sleeping minute calm.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/sleep_stress.dart';
import 'package:openstrap_edge/compute/stress_monitor.dart';
import 'package:openstrap_edge/data/day_label.dart';

/// A small deterministic wobble so the baseline has a spread.
double _w(int i, double amp) => amp * math.sin(i * 1.7) * math.cos(i * .31);

void main() {
  final base = DateTime(2026, 10, 20);

  /// The minute arrays for [count] days from [base], with each night (23:00 to
  /// 07:00) written by [at]: heart rate and HRV for night [n], minute [m].
  Map<String, StressDayInput> build(
      int count, ({double hr, double hrv}) Function(int night, int m) at) {
    final out = <String, StressDayInput>{};
    for (var d = 0; d < count; d++) {
      final day = DateTime(base.year, base.month, base.day + d);
      final hr = List<double?>.filled(1440, null);
      final hrv = List<double?>.filled(1440, null);
      for (var m = 0; m < 1440; m++) {
        // Midnight to 07:00 is the tail of the night that ENDS on this day;
        // 23:00 on is the head of the night that ends on the next.
        if (m < 7 * 60) {
          final v = at(d, 60 + m);
          hr[m] = v.hr;
          hrv[m] = v.hrv;
        } else if (m >= 23 * 60) {
          final v = at(d + 1, m - 23 * 60);
          hr[m] = v.hr;
          hrv[m] = v.hrv;
        }
      }
      out[dayLabelOf(day)] = StressDayInput(
          day: dayLabelOf(day),
          hr: hr,
          hrv: hrv,
          motion: null,
          asleep: List<bool>.filled(1440, false));
    }
    return out;
  }

  NightWindow night(int d) {
    // Night d ends on day d at 07:00 and began the evening before at 23:00.
    final end = DateTime(base.year, base.month, base.day + d, 7);
    final start = DateTime(base.year, base.month, base.day + d - 1, 23);
    return (
      onset: start.millisecondsSinceEpoch ~/ 1000,
      wake: end.millisecondsSinceEpoch ~/ 1000
    );
  }

  // Night n, minute m since 23:00 (the post-midnight tail is 60 + minute).
  ({double hr, double hrv}) calm(int n, int m) =>
      (hr: 54 + _w(m + n, 2.5), hrv: 62 + _w(m * 3 + n, 8));

  test('a night like the others has no high sleep stress', () {
    final days = build(8, calm);
    final s = sleepStress(night(7), [for (var d = 1; d <= 6; d++) night(d)], days);
    expect(s, isNotNull);
    expect(s!.pct, lessThan(5));
    expect(s.scored, greaterThan(400));
    expect(s.nights, 6);
  });

  test('an hour of raised heart rate and low HRV shows as that share', () {
    // Night 7: minutes 120–180 since 23:00 run hot with the HRV on the floor.
    final days = build(8, (n, m) {
      if (n == 7 && m >= 120 && m < 180) return (hr: 82, hrv: 22);
      return calm(n, m);
    });
    final s = sleepStress(night(7), [for (var d = 1; d <= 6; d++) night(d)], days)!;
    // 60 of 480 minutes, less the smoothing's blur at the two edges.
    expect(s.pct, inInclusiveRange(8, 16));
  });

  test('too few earlier nights says nothing, not zero', () {
    final days = build(4, calm);
    expect(sleepStress(night(3), [night(1), night(2)], days), isNull);
  });

  test('a night with no heart rate says nothing', () {
    final days = build(8, (n, m) => n == 7 ? (hr: 0, hrv: 0) : calm(n, m));
    // Zero is the strap's "no reading": nothing is scored on it.
    final blank = <String, StressDayInput>{
      for (final e in days.entries)
        e.key: StressDayInput(
            day: e.key,
            hr: [for (final h in e.value.hr) h == 0 ? null : h],
            hrv: [for (final h in e.value.hrv) h == 0 ? null : h],
            motion: null,
            asleep: e.value.asleep),
    };
    expect(sleepStress(night(7), [for (var d = 1; d <= 6; d++) night(d)], blank),
        isNull);
  });
}
