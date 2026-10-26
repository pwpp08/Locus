// HIGH SLEEP STRESS: the share of a night's sleeping minutes spent in the high
// stress zone — heart rate up and HRV down against what is usual FOR YOU
// ASLEEP. It is the fourth contributor to sleep performance, next to hours,
// consistency and efficiency; a night with a lot of it was restless in the
// body even when it was long.
//
// The one thing that makes this its own function rather than a filter on the
// Stress Monitor: the baseline. The monitor scores a minute against the
// person's quiet WAKING heart rate and HRV, and a sleeping minute against that
// baseline is always "calm", so every night would read zero. Here the baseline
// is the person's own sleeping minutes on their previous nights, and a minute
// is high when it sits two-odd spreads off THAT — a night's worth of "your
// heart ran hotter or your HRV ran lower than it does on a normal night".
//
// Everything else is the Stress Monitor's own arithmetic ([stressScores]): the
// same z-scores, the same 0–3 scale, the same high cut-off (2), so a high
// minute asleep means what a high minute awake means.
//
// ponytail: a metric belongs in the analytics sibling repo; this lives here
// because that repo is pinned and not editable from this one. Pure arithmetic
// over series the day bundle already holds; nothing is persisted, so no
// `kAlgoVersion` bump rides on it. Move it with the next analytics pin.

import 'dart:math' as math;

import '../data/day_label.dart';
import 'stress_monitor.dart';

/// One night: epoch seconds, onset to wake.
typedef NightWindow = ({int onset, int wake});

/// The answer for one night.
class SleepStress {
  /// Percent of the night's scored minutes that were high (0–100).
  final double pct;

  /// Minutes that carried a score, and how many of them were high.
  final int scored, high;

  /// Previous nights the baseline was built from.
  final int nights;

  const SleepStress(
      {required this.pct,
      required this.scored,
      required this.high,
      required this.nights});
}

/// Fewest scored minutes a night needs to be judged: an hour and a half, one
/// sleep cycle. Under it the share is a handful of minutes' luck.
const int kSleepStressMinScored = 90;

/// Fewest previous nights, and sleeping minutes in all, a baseline needs.
const int kSleepStressMinNights = 3, kSleepStressMinBaselineMinutes = 200;

/// A night's minute series, assembled across midnight from the per-day
/// minute arrays. Index 0 is the minute the night began.
class _Night {
  final List<double?> hr, hrv;
  final List<double?>? motion;
  _Night(this.hr, this.hrv, this.motion);
}

_Night? _nightOf(NightWindow w, Map<String, StressDayInput> days) {
  final n = (w.wake - w.onset) ~/ 60;
  if (n < 1 || n > StressDayInput.minutes) return null;
  final hr = List<double?>.filled(n, null);
  final hrv = List<double?>.filled(n, null);
  var motion = List<double?>.filled(n, null);
  var anyMotion = false;
  for (var i = 0; i < n; i++) {
    final at = DateTime.fromMillisecondsSinceEpoch((w.onset + i * 60) * 1000);
    final d = days[dayLabelOf(at)];
    if (d == null) continue;
    final k = at.hour * 60 + at.minute;
    hr[i] = d.hr[k];
    hrv[i] = d.hrv[k];
    final m = d.motion?[k];
    if (m != null) {
      motion[i] = m;
      anyMotion = true;
    }
  }
  return _Night(hr, hrv, anyMotion ? motion : null);
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double _sigma(List<double> xs, double centre) =>
    1.4826 * _median([for (final x in xs) (x - centre).abs()]);

/// What is usual asleep, from [prior] nights — null with too few of them.
StressBaseline? sleepStressBaseline(
    List<NightWindow> prior, Map<String, StressDayInput> days) {
  final hrs = <double>[], lns = <double>[];
  var used = 0;
  for (final w in prior) {
    final night = _nightOf(w, days);
    if (night == null) continue;
    var got = 0;
    for (var i = 0; i < night.hr.length; i++) {
      final h = night.hr[i], v = night.hrv[i];
      if (h == null || v == null || v <= 0) continue;
      // Settled minutes only, where the strap says how much it moved: a turn
      // in bed lifts the heart rate and says nothing about the night.
      final m = night.motion?[i];
      if (night.motion != null && (m == null || m > stressQuietMotion)) continue;
      hrs.add(h);
      lns.add(math.log(v));
      got++;
    }
    if (got >= 60) used++;
  }
  if (used < kSleepStressMinNights || hrs.length < kSleepStressMinBaselineMinutes) {
    return null;
  }
  final hr = _median(hrs), ln = _median(lns);
  return StressBaseline(
    hr: hr,
    hrSigma: math.max(_sigma(hrs, hr), 2.0),
    lnHrv: ln,
    lnHrvSigma: math.max(_sigma(lns, ln), .15),
    days: used,
    minutes: hrs.length,
    motionKnown: true,
  );
}

/// High sleep stress for [night], against [prior] nights. Null — never zero —
/// when there is no baseline yet or the night carries too few scored minutes.
SleepStress? sleepStress(
    NightWindow night, List<NightWindow> prior, Map<String, StressDayInput> days) {
  final base = sleepStressBaseline(prior, days);
  if (base == null) return null;
  final n = _nightOf(night, days);
  if (n == null) return null;
  // The Stress Monitor's scorer takes a day of 1440 minutes; a night is
  // shorter, so it sits at the start of one.
  List<double?> pad(List<double?> xs) =>
      [...xs, ...List<double?>.filled(StressDayInput.minutes - xs.length, null)];
  final scores = stressScores(
      StressDayInput(
        day: 'night',
        hr: pad(n.hr),
        hrv: pad(n.hrv),
        motion: n.motion == null ? null : pad(n.motion!),
        asleep: List<bool>.filled(StressDayInput.minutes, true),
      ),
      base);
  var scored = 0, high = 0;
  for (var i = 0; i < n.hr.length; i++) {
    final s = scores[i];
    if (s == null) continue;
    scored++;
    if (stressLevel(s) == StressLevel.high) high++;
  }
  if (scored < kSleepStressMinScored) return null;
  return SleepStress(
      pct: high / scored * 100, scored: scored, high: high, nights: base.days);
}
