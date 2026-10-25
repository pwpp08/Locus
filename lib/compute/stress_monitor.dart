// Stress Monitor: a 0–3 score for every minute of a day, from how far the
// heart rate is above, and the HRV below, what is usual for THIS person, with
// motion taken out.
//
// The method is the one the public description of a live stress monitor gives:
// heart rate and HRV in the moment, compared with a personal baseline from the
// past 14 days, and motion accounted for so exercise is not read as stress.
// Everything here is that sentence, made concrete:
//
//   * BASELINE — the median heart rate and the median ln(RMSSD) over the
//     person's quiet, awake minutes in the 14 days before the day shown, with
//     a robust spread (1.4826 × MAD) for each. "Quiet" is the strap's own
//     motion reading at or under 5 % of seconds moving. A strap that gives no
//     motion reading falls back to the lower half of each day's waking heart
//     rate, and the result says so ([StressBaseline.motionKnown]).
//   * SCORE — z-scores of heart rate (above baseline) and of HRV (below it, in
//     log space, since RMSSD is skewed), averaged. When there is no HRV for a
//     minute the heart-rate z-score stands alone at 60 % weight: a minute that
//     says less moves the score less.
//   * MOTION — the z is multiplied by (1 − 0.85 × motion/0.35, floored at 0.15).
//     Without a motion reading, a heart rate more than three spreads above
//     baseline is treated as exertion and halved.
//   * SCALE — 0.8 + 0.7 × z (z bounded to −3…4.5), clamped to 0–3, smoothed over five minutes. A
//     quiet minute at baseline reads 0.8 (low); +1 spread is 1.5 (medium); two
//     spreads and more is high.
//
// ponytail: a metric belongs in the analytics sibling repo. This lives here
// because that repo is pinned and is not editable from this one; it is pure
// arithmetic over series the day bundle already holds, and nothing it returns
// is persisted, so no `kAlgoVersion` bump rides on it. Move it with the next
// analytics pin.

import 'dart:math' as math;

import '../data/day_label.dart';

/// One local day's minute series, the input to the score. All series have
/// [minutes] slots; null is "not recorded", never zero.
class StressDayInput {
  static const minutes = 1440;

  final String day;
  final List<double?> hr;

  /// RMSSD in ms, held for up to four minutes (it is a 5-minute window).
  final List<double?> hrv;

  /// Fraction of seconds moving, 0–1. Null when the strap gave no motion.
  final List<double?>? motion;

  final List<bool> asleep;

  const StressDayInput({
    required this.day,
    required this.hr,
    required this.hrv,
    required this.motion,
    required this.asleep,
  });

  /// Reads a day's `getDayTimeline` payload. Points from any other local day
  /// (a bundle served in place of the day asked for) are left out.
  factory StressDayInput.fromTimeline(String day, Map<String, dynamic> t) {
    List<double?> perMinute(Object? raw, {double Function(double)? map}) {
      final out = List<double?>.filled(minutes, null);
      if (raw is! List) return out;
      for (final e in raw) {
        if (e is! Map || e['t'] is! num || e['v'] is! num) continue;
        final at = DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt() * 1000);
        if (dayLabelOf(at) != day) continue;
        final v = (e['v'] as num).toDouble();
        if (v <= 0) continue;
        out[at.hour * 60 + at.minute] = map == null ? v : map(v);
      }
      return out;
    }

    final hr = perMinute(t['hr']);
    final rawHrv = perMinute(t['hrv']);
    // HRV is a 5-minute rolling window: hold it forward for four minutes.
    final hrv = List<double?>.of(rawHrv);
    var held = 0;
    double? last;
    for (var i = 0; i < minutes; i++) {
      if (rawHrv[i] != null) {
        last = rawHrv[i];
        held = 0;
      } else if (last != null && ++held <= 4) {
        hrv[i] = last;
      } else {
        last = null;
      }
    }

    // Motion arrives in 5-minute buckets; spread each over its minutes.
    List<double?>? motion;
    final act = t['activity'];
    if (act is List && act.isNotEmpty) {
      motion = List<double?>.filled(minutes, null);
      for (final e in act) {
        if (e is! Map || e['t'] is! num || e['v'] is! num) continue;
        for (var k = 0; k < 5; k++) {
          final at = DateTime.fromMillisecondsSinceEpoch(
              ((e['t'] as num).toInt() + 60 * k) * 1000);
          if (dayLabelOf(at) != day) continue;
          motion[at.hour * 60 + at.minute] = (e['v'] as num).toDouble();
        }
      }
    }

    final asleep = List<bool>.filled(minutes, false);
    final sleep = t['sleep'];
    if (sleep is List) {
      for (final w in sleep) {
        if (w is! Map || w['onset_ts'] is! num || w['wake_ts'] is! num) continue;
        var at = DateTime.fromMillisecondsSinceEpoch((w['onset_ts'] as num).toInt() * 1000);
        final end = DateTime.fromMillisecondsSinceEpoch((w['wake_ts'] as num).toInt() * 1000);
        while (at.isBefore(end)) {
          if (dayLabelOf(at) == day) asleep[at.hour * 60 + at.minute] = true;
          at = at.add(const Duration(minutes: 1));
        }
      }
    }
    return StressDayInput(day: day, hr: hr, hrv: hrv, motion: motion, asleep: asleep);
  }
}

/// What is usual for this person: the centre and spread of heart rate and of
/// ln(RMSSD) over quiet waking minutes.
class StressBaseline {
  final double hr, hrSigma, lnHrv, lnHrvSigma;

  /// Days that contributed, and quiet minutes in all.
  final int days, minutes;

  /// False when the strap gave no motion reading and "quiet" was taken to be
  /// the lower half of each day's waking heart rate.
  final bool motionKnown;

  const StressBaseline({
    required this.hr,
    required this.hrSigma,
    required this.lnHrv,
    required this.lnHrvSigma,
    required this.days,
    required this.minutes,
    required this.motionKnown,
  });
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// 1.4826 × the median absolute deviation: a spread an outlier cannot drag.
double _robustSigma(List<double> xs, double centre) =>
    1.4826 * _median([for (final x in xs) (x - centre).abs()]);

/// Fraction of seconds moving at or under which a minute counts as quiet.
const double stressQuietMotion = .05;

/// The baseline from the days BEFORE the one shown. Null with fewer than three
/// usable days or 200 quiet minutes: a baseline from a weekend is not one.
StressBaseline? stressBaseline(List<StressDayInput> days) {
  final hrs = <double>[], lns = <double>[];
  var used = 0;
  var motionDays = 0;
  for (final d in days) {
    final awakeHr = [
      for (var i = 0; i < StressDayInput.minutes; i++)
        if (!d.asleep[i] && d.hr[i] != null) d.hr[i]!,
    ];
    if (awakeHr.isEmpty) continue;
    final med = _median(awakeHr);
    var got = 0;
    for (var i = 0; i < StressDayInput.minutes; i++) {
      if (d.asleep[i]) continue;
      final h = d.hr[i], v = d.hrv[i];
      if (h == null || v == null || v <= 0) continue;
      final m = d.motion?[i];
      final quiet = d.motion != null ? (m != null && m <= stressQuietMotion) : h <= med;
      if (!quiet) continue;
      hrs.add(h);
      lns.add(math.log(v));
      got++;
    }
    if (got >= 30) {
      used++;
      if (d.motion != null) motionDays++;
    }
  }
  if (used < 3 || hrs.length < 200) return null;
  final hr = _median(hrs), ln = _median(lns);
  return StressBaseline(
    hr: hr,
    hrSigma: math.max(_robustSigma(hrs, hr), 3.0),
    lnHrv: ln,
    lnHrvSigma: math.max(_robustSigma(lns, ln), .15),
    days: used,
    minutes: hrs.length,
    motionKnown: motionDays * 2 > used,
  );
}

/// The score for every minute of [d], 0–3, null where there is no heart rate.
List<double?> stressScores(StressDayInput d, StressBaseline b) {
  final raw = List<double?>.filled(StressDayInput.minutes, null);
  for (var i = 0; i < StressDayInput.minutes; i++) {
    final h = d.hr[i];
    if (h == null) continue;
    final zHr = (h - b.hr) / b.hrSigma;
    final v = d.hrv[i];
    final z = v != null && v > 0
        ? .5 * zHr + .5 * (b.lnHrv - math.log(v)) / b.lnHrvSigma
        : .6 * zHr;
    final m = d.motion?[i];
    final double keep;
    if (d.motion != null) {
      // Moving: the exertion is the reason, not the stress.
      keep = m == null ? 1 : math.max(.15, 1 - .85 * (m / .35).clamp(0.0, 1.0));
    } else {
      keep = zHr > 3 ? .5 : 1;
    }
    // Bounded first: a sprint's z-score is enormous, and no discount on an
    // enormous number leaves a small one.
    raw[i] = (.8 + .7 * z.clamp(-3.0, 4.5) * keep).clamp(0.0, 3.0).toDouble();
  }
  // Five minutes, trailing: a score is a state, not a flicker.
  final out = List<double?>.filled(StressDayInput.minutes, null);
  for (var i = 0; i < StressDayInput.minutes; i++) {
    if (raw[i] == null) continue;
    var sum = 0.0;
    var n = 0;
    for (var k = math.max(0, i - 4); k <= i; k++) {
      final x = raw[k];
      if (x != null) {
        sum += x;
        n++;
      }
    }
    out[i] = sum / n;
  }
  return out;
}

enum StressLevel { low, medium, high }

StressLevel stressLevel(double score) => score < 1
    ? StressLevel.low
    : score < 2
        ? StressLevel.medium
        : StressLevel.high;

/// Minutes at each level over [scores].
({int low, int medium, int high}) stressMinutes(List<double?> scores) {
  var lo = 0, mid = 0, hi = 0;
  for (final s in scores) {
    if (s == null) continue;
    switch (stressLevel(s)) {
      case StressLevel.low:
        lo++;
      case StressLevel.medium:
        mid++;
      case StressLevel.high:
        hi++;
    }
  }
  return (low: lo, medium: mid, high: hi);
}
