// VO₂ MAX, estimated the way WHOOP describes its own: three tiers, updated
// weekly, each one sharper than the last when the data is there.
//
//   1. PASSIVE — for anyone wearing the strap. WHOOP trains a model on resting
//      physiology, activity, sleep and demographics. We do not have that model
//      and do not pretend to: this tier is the PUBLISHED non-exercise
//      regression of Jackson et al. (1990, Med Sci Sports Exerc 22:863):
//
//          VO₂max = 56.363 + 1.921·PA-R − 0.381·age − 0.754·BMI + 10.987·male
//
//      with PA-R, its 0–7 self-report activity code, measured by the strap
//      instead of asked: the minutes a week spent in the moderate and in the
//      hard heart-rate zones (see [paRFrom]). Its published error is about
//      ±5 mL/kg/min (SEE 5.3), so it is a level to follow the direction of,
//      not a number to quote. Like WHOOP's it waits for 14 scored recoveries
//      in the last 21 days — a strap worn for two weeks, not two nights.
//   2. GPS — a run outdoors of 15 minutes or more gives a direct reading:
//      pace and the heart rate it cost (ACSM running equation, Swain's %HRR ≈
//      %VO₂R; the per-run figure is made in `vo2maxSubmaxEstimate` and stored
//      on the session). The middle of the last five within 90 days stands in
//      for the passive level.
//   3. LAB — a gas-exchange result the person enters anchors the series: the
//      gap between it and what we estimated that week is carried onto every
//      week, so the trend keeps its shape and its level becomes theirs.
//
// What this deliberately does not do: dress a population regression as a
// measurement, or answer when it has nothing to go on. The earlier version of
// this figure was `15.3·HRmax/HRrest`, which is the resting-heart-rate chart
// in other units and was deleted for it; this one moves when activity,
// weight, age or a run moves, and it says which tier it is.
//
// ponytail: a metric belongs in the analytics sibling repo. This lives here
// because that repo is pinned and is not editable from this one; it is pure
// arithmetic over series edge already holds and nothing it returns is
// persisted, so no `kAlgoVersion` bump rides on it. Move it with the next
// analytics pin. The PA-R mapping is ours (Jackson defines the codes in words,
// not in zone minutes) and is the first thing to refit against lab data.

import 'dart:math' as math;

import '../data/day_label.dart';

enum Vo2Source { passive, gps, lab }

/// A person's profile, as far as this needs it.
typedef Vo2Profile = ({int? age, String? sex, double? weightKg, double? heightCm});

/// One outdoor run's own estimate, on the local day it was run.
typedef Vo2Run = ({String day, double v});

/// A lab test the person entered: its value, and the day it was taken.
typedef Vo2Lab = ({String day, double value});

class Vo2Result {
  /// The weekly estimate on each local day of that week.
  final Map<String, double> byDay;

  /// Where the latest figure came from, and why there is none.
  final Vo2Source? source;
  final String? why;

  /// Recoveries in the last 21 days, against the 14 the passive tier needs.
  final int recoveries;

  const Vo2Result(
      {this.byDay = const {},
      this.source,
      this.why,
      this.recoveries = 0});

  double? get latest {
    if (byDay.isEmpty) return null;
    final last = byDay.keys.reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    return byDay[last];
  }
}

/// Recoveries the passive tier needs, in the window it counts them over.
const int kVo2MinRecoveries = 14, kVo2RecoveryWindow = 21;

/// How far back a run still counts, and how many of them are looked at.
const int kVo2RunWindow = 90, kVo2RunsUsed = 5;

/// Days of zone minutes averaged into a weekly figure, and how many of them
/// must carry data.
const int kVo2ActivityWindow = 28, kVo2MinActivityDays = 14;

/// Jackson's regression for a person, or null off a missing input.
double? jackson({
  required double paR,
  required int? age,
  required String? sex,
  required double? weightKg,
  required double? heightCm,
}) {
  if (age == null ||
      weightKg == null ||
      heightCm == null ||
      heightCm <= 0 ||
      (sex != 'm' && sex != 'f')) {
    return null;
  }
  final bmi = weightKg / math.pow(heightCm / 100, 2);
  return 56.363 +
      1.921 * paR -
      .381 * age -
      .754 * bmi +
      (sex == 'm' ? 10.987 : 0);
}

double _lerp(double x, List<(double, double)> pts) {
  if (x <= pts.first.$1) return pts.first.$2;
  for (var i = 1; i < pts.length; i++) {
    if (x <= pts[i].$1) {
      final (x0, y0) = pts[i - 1];
      final (x1, y1) = pts[i];
      return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
    }
  }
  return pts.last.$2;
}

/// Jackson's 0–7 activity code from a week of heart-rate zones: [moderateMin]
/// the minutes in the middle zones (2–3), [vigorousMin] in the hard ones
/// (4–5). His codes 1–3 are moderate activity (up to ten minutes, ten to
/// sixty, over an hour a week) and 4–7 running (under 30 minutes, 30–60, one
/// to three hours, over three), "or comparable activity" — which hard zone
/// time is. The code is drawn continuous between those points so one more
/// workout moves the estimate a little instead of a whole step.
double paRFrom({required double moderateMin, required double vigorousMin}) {
  final mod = _lerp(moderateMin, const [(0, 1), (10, 2), (60, 3)]);
  final vig = vigorousMin < 5
      ? 0.0
      : _lerp(vigorousMin, const [(5, 4), (30, 5), (60, 6), (180, 7)]);
  return math.max(mod, vig);
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

String _shift(String day, int by) {
  final d = DateTime.parse(day);
  return dayLabelOf(DateTime(d.year, d.month, d.day + by, 12));
}

/// The Monday on or before [day].
String weekStart(String day) {
  final d = DateTime.parse(day);
  return dayLabelOf(DateTime(d.year, d.month, d.day - (d.weekday - 1), 12));
}

/// The estimate as of the end of [asOf] (a day), before any lab anchor, and
/// which tier it came from — or why there is none.
({double? v, Vo2Source? src, String? why, int recoveries}) _asOf(
  String asOf, {
  required Vo2Profile profile,
  required Map<String, double> recovery,
  required Map<String, double> moderate,
  required Map<String, double> vigorous,
  required List<Vo2Run> runs,
}) {
  var recoveries = 0;
  for (var i = 0; i < kVo2RecoveryWindow; i++) {
    if (recovery.containsKey(_shift(asOf, -i))) recoveries++;
  }

  // A recent run is a measurement; it stands on its own.
  final recent = [
    for (final r in runs)
      if (r.day.compareTo(asOf) <= 0 && r.day.compareTo(_shift(asOf, -kVo2RunWindow)) > 0) r,
  ]..sort((a, b) => b.day.compareTo(a.day));
  if (recent.isNotEmpty) {
    final v = _median([for (final r in recent.take(kVo2RunsUsed)) r.v]);
    return (v: v, src: Vo2Source.gps, why: null, recoveries: recoveries);
  }

  if (recoveries < kVo2MinRecoveries) {
    return (
      v: null,
      src: null,
      why: 'Needs $kVo2MinRecoveries recoveries in the last '
          '$kVo2RecoveryWindow days; $recoveries so far. Wear the strap '
          'through the night and it appears.',
      recoveries: recoveries,
    );
  }
  var days = 0;
  var mod = 0.0, vig = 0.0;
  for (var i = 0; i < kVo2ActivityWindow; i++) {
    final d = _shift(asOf, -i);
    final m = moderate[d], v = vigorous[d];
    if (m == null && v == null) continue;
    days++;
    mod += m ?? 0;
    vig += v ?? 0;
  }
  if (days < kVo2MinActivityDays) {
    return (
      v: null,
      src: null,
      why: 'Too few days of heart-rate zones to read your activity '
          '($days of the last $kVo2ActivityWindow).',
      recoveries: recoveries,
    );
  }
  final perWeek = 7 / days;
  final v = jackson(
    paR: paRFrom(moderateMin: mod * perWeek, vigorousMin: vig * perWeek),
    age: profile.age,
    sex: profile.sex,
    weightKg: profile.weightKg,
    heightCm: profile.heightCm,
  );
  if (v == null) {
    return (
      v: null,
      src: null,
      why: 'Add your age, sex, height and weight to your profile: the '
          'estimate starts from them.',
      recoveries: recoveries,
    );
  }
  return (v: v, src: Vo2Source.passive, why: null, recoveries: recoveries);
}

/// The weekly series from [firstDay] to [today]: one value a week, held on
/// each day of it, each from the data up to the Sunday before.
Vo2Result estimateVo2max({
  required String today,
  required String firstDay,
  required Vo2Profile profile,
  required Map<String, double> recovery,
  required Map<String, double> moderate,
  required Map<String, double> vigorous,
  List<Vo2Run> runs = const [],
  Vo2Lab? lab,
}) {
  final weeks = <String>[];
  for (var w = weekStart(firstDay);
      w.compareTo(today) <= 0;
      w = _shift(w, 7)) {
    weeks.add(w);
  }
  final raw = <String, double>{};
  final src = <String, Vo2Source>{};
  String? lastWhy;
  var recoveries = 0;
  for (final w in weeks) {
    final r = _asOf(_shift(w, -1),
        profile: profile,
        recovery: recovery,
        moderate: moderate,
        vigorous: vigorous,
        runs: runs);
    lastWhy = r.why;
    recoveries = r.recoveries;
    if (r.v != null) {
      raw[w] = r.v!;
      src[w] = r.src!;
    }
  }

  // The lab anchor: the gap between the result and what was estimated the
  // week it was taken (the first estimated week at or after it, when that
  // week had none), carried onto every week.
  var offset = 0.0;
  var anchored = false;
  if (lab != null) {
    final at = weekStart(lab.day);
    final w = raw.keys.where((k) => k.compareTo(at) >= 0).toList()..sort();
    if (w.isNotEmpty) {
      offset = lab.value - raw[w.first]!;
      anchored = true;
    }
  }

  final out = <String, double>{};
  for (final w in weeks) {
    final v = raw[w];
    if (v == null) continue;
    final x = (v + offset).clamp(10.0, 90.0);
    for (var i = 0; i < 7; i++) {
      final d = _shift(w, i);
      if (d.compareTo(today) <= 0) out[d] = x;
    }
  }
  final latestWeek = weekStart(today);
  return Vo2Result(
    byDay: out,
    source: raw.isEmpty
        ? null
        : (anchored ? Vo2Source.lab : src[(raw.keys.toList()..sort()).last]),
    // Said when this week has no figure: a reason beats a silent gap.
    why: raw.containsKey(latestWeek) ? null : lastWhy,
    recoveries: recoveries,
  );
}
