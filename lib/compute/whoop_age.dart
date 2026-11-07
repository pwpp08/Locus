// whoop_age.dart — WHOOP Age and Pace of Aging, the way WHOOP's Healthspan
// white paper describes them (docs/proposals/whoop-parity-research.md).
//
// Each contributor (sleep, sleep consistency, steps, zone 1–3 and zone 4–5
// minutes, strength minutes, RHR, VO₂max, lean mass) becomes a hazard ratio
// against a health-optimised target, and a hazard ratio becomes years by
// `10 × ln(HR)` (all-cause mortality rises about 10% per year of age).
// WHOOP Age = age + the sum over the last six months. Pace of Aging asks how
// fast that age would move if the last 30 days carried on for six months:
// 1.0× is one year per year.
//
// The targets and the evidence behind each slope are WHOOP's (Table 1 and the
// cited meta-analyses). WHOOP does not publish its curve shapes or its overlap
// correction (the contributors share variance, so their years cannot simply
// add), so those are ours.
//
// ponytail: curve shapes and [kWhoopAgeOverlap] are our own, set so the white
// paper's Table 2 holds: a typical WHOOP member aged 30 reads about −1.6 years,
// a typical US adult aged 30 about +6 (test/whoop_age_test.dart). Refit when
// a WHOOP readout with its inputs is available. A metric, so it belongs in the
// analytics repo; it lives here for the same reason vo2max_estimate.dart does.
// Nothing it returns is persisted, so no kAlgoVersion bump rides on it.

import 'dart:math' as math;

import '../data/day_label.dart';

/// Recoveries WHOOP wants in the last [kWhoopAgeUnlockWindow] days first.
const int kWhoopAgeUnlockRecoveries = 21;
const int kWhoopAgeUnlockWindow = 31;

/// The long window WHOOP Age is read over, and Pace of Aging's short one.
const int kWhoopAgeWindowDays = 182;
const int kWhoopAgePaceDays = 30;

/// Share of the summed years kept once overlap between contributors is
/// removed (see the ponytail note above).
const double kWhoopAgeOverlap = 0.55;

/// One contributor's place in the result: its average over the window, the
/// target it is held against, and the years it adds (negative: takes off).
typedef WhoopAgePart = ({double value, double target, double years});

class WhoopAgeResult {
  /// Null when [why] says why there is no reading.
  final double? whoopAge;

  /// Years per year, −1.0 to 3.0. Null without enough of the last 30 days.
  final double? pace;

  /// Each contributor that had data, by key (sleep_hours, consistency, steps,
  /// zones_13, zones_45, strength, resting_hr, vo2max, lean_mass).
  final Map<String, WhoopAgePart> parts;

  final String? why;

  const WhoopAgeResult({
    this.whoopAge,
    this.pace,
    this.parts = const {},
    this.why,
  });
}

/// Daily inputs, each keyed by local day ('YYYY-MM-DD'). A day with no entry
/// is a day with no data, except in the minute maps, where a worn day with no
/// entry is a day with none of those minutes.
WhoopAgeResult whoopAge({
  required String today,
  required int? age,
  required String? sex,
  required Map<String, double> recovery,
  Map<String, double> sleepMin = const {},
  Map<String, double> consistency = const {},
  Map<String, double> steps = const {},
  Map<String, double> zones13Min = const {},
  Map<String, double> zones45Min = const {},
  Map<String, double> strengthMin = const {},
  Map<String, double> restingHr = const {},
  Map<String, double> vo2max = const {},
  double? leanMassPct,
}) {
  if (age == null) return const WhoopAgeResult(why: 'needs_age');
  if (age < 18) return const WhoopAgeResult(why: 'under_18');
  final recent =
      recovery.keys.where((d) => _within(d, today, kWhoopAgeUnlockWindow));
  if (recent.length < kWhoopAgeUnlockRecoveries) {
    return WhoopAgeResult(
        why: 'needs_recoveries:have=${recent.length},'
            'need=$kWhoopAgeUnlockRecoveries');
  }

  Map<String, WhoopAgePart> partsOver(int days) {
    bool inWin(String d) => _within(d, today, days);
    double? mean(Map<String, double> m) {
      final v = [for (final e in m.entries) if (inWin(e.key)) e.value];
      return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    }

    // Weekly minutes over the days worn, so a week off the wrist is not a
    // week of no exercise.
    final worn = {
      for (final d in [...recovery.keys, ...zones13Min.keys, ...steps.keys])
        if (inWin(d)) d,
    };
    double? weekly(Map<String, double> m) {
      if (worn.length < 7) return null;
      var sum = 0.0;
      for (final e in m.entries) {
        if (inWin(e.key)) sum += e.value;
      }
      return sum / worn.length * 7;
    }

    final older = age >= 60;
    final out = <String, WhoopAgePart>{};
    void add(String key, double? v, double target, double hr) {
      if (v != null) out[key] = (value: v, target: target, years: 10 * math.log(hr));
    }

    final h = mean(sleepMin);
    if (h != null) add('sleep_hours', h / 60, 7, _sleepHr(h / 60));
    final c = mean(consistency);
    if (c != null) add('consistency', c, 70, _consistencyHr(c));
    final st = mean(steps);
    final stTarget = older ? 5600.0 : 8000.0;
    if (st != null) add('steps', st, stTarget, _stepsHr(st, stTarget));
    final z13 = weekly(zones13Min);
    final z13Target = older ? 70.0 : 100.0;
    if (z13 != null) {
      add('zones_13', z13, z13Target,
          _doseHr(z13, z13Target, cap: 600, worst: 1.3, best: 0.9));
    }
    final z45 = weekly(zones45Min);
    final z45Target = older ? 7.0 : 10.0;
    if (z45 != null) {
      add('zones_45', z45, z45Target,
          _doseHr(z45, z45Target, cap: 75, worst: 1.2, best: 0.9));
    }
    final sm = weekly(strengthMin);
    if (sm != null) {
      add('strength', sm, 40, _doseHr(sm, 40, cap: 120, worst: 1.2, best: 0.9));
    }
    final rhr = mean(restingHr);
    final rhrTarget = sex == 'm' ? 60.0 : sex == 'f' ? 64.0 : 62.0;
    if (rhr != null) {
      // +9% all-cause risk per 10 bpm.
      add('resting_hr', rhr, rhrTarget,
          math.pow(1.09, (rhr - rhrTarget).clamp(-15.0, 30.0) / 10).toDouble());
    }
    final vo2 = mean(vo2max);
    final vo2Target = whoopVo2Target(age, sex);
    if (vo2 != null) {
      // About 15% lower risk per MET (3.5 mL/kg/min) of fitness.
      add('vo2max', vo2, vo2Target,
          math.pow(1.15, (vo2Target - vo2).clamp(-15.0, 15.0) / 3.5).toDouble());
    }
    if (leanMassPct != null) {
      // +11% risk per 10% body fat over target; no benefit past it, and no
      // effect at all when it was never entered.
      final t = sex == 'f' ? 67.0 : 80.0;
      add('lean_mass', leanMassPct, t,
          math.pow(1.11, math.max(0.0, t - leanMassPct) / 10).toDouble());
    }
    return out;
  }

  double sum(Map<String, WhoopAgePart> p) =>
      p.values.fold(0.0, (a, x) => a + x.years) * kWhoopAgeOverlap;

  final long = partsOver(kWhoopAgeWindowDays);
  if (long.isEmpty) return const WhoopAgeResult(why: 'needs_inputs');
  final yLong = sum(long);
  final short = partsOver(kWhoopAgePaceDays);
  // If the last 30 days carried on for half a year, the age would move by
  // half a year plus the change in contributed years.
  final pace = short.isEmpty
      ? null
      : (1 + (sum(short) - yLong) / 0.5).clamp(-1.0, 3.0).toDouble();
  return WhoopAgeResult(whoopAge: age + yLong, pace: pace, parts: long);
}

/// WHOOP's VO₂max target (Table 1) by age and sex, in steps of 5 years from
/// 20 to 100. No sex on file: the middle of the two.
double whoopVo2Target(int age, String? sex) {
  const f = [40, 40, 38, 36, 34, 32, 30, 29, 27, 26, 25, 23, 22, 21, 20, 19, 18];
  const m = [46, 46, 44, 42, 40, 37, 36, 34, 32, 30, 29, 27, 26, 25, 23, 22, 21];
  final i = ((age.clamp(20, 100) - 20) / 5).floor();
  return switch (sex) {
    'm' => m[i].toDouble(),
    'f' => f[i].toDouble(),
    _ => (m[i] + f[i]) / 2,
  };
}

/// Short sleep: +12% per hour under 7. Seven to nine: a small benefit. Past
/// nine: neutral (WHOOP gives long sleep no credit).
double _sleepHr(double h) => h < 7
    ? math.pow(1.12, math.min(4.0, 7 - h)).toDouble()
    : h <= 9
        ? 0.97
        : 1.0;

/// Regular sleepers carry 20–48% lower risk: up to 1.4 below the 70% target,
/// down to 0.9 at 100%.
double _consistencyHr(double c) => c < 70
    ? 1 + 0.4 * (70 - c.clamp(0.0, 70.0)) / 70
    : 1 - 0.1 * (c.clamp(70.0, 100.0) - 70) / 30;

/// Steps: about −23% risk per 1,000 a day below the target, on a log dose so
/// the first thousands count most; past the target a small, capped benefit.
double _stepsHr(double s, double target) => s < target
    ? math.pow(target / math.max(s, 500.0), 0.71).toDouble()
    : 1 - 0.05 * math.min(s - target, 4000.0) / 4000;

/// Weekly minutes: [worst] at none, 1 at [target], falling to [best] at [cap]
/// and no further.
double _doseHr(double v, double target,
        {required double cap, required double worst, required double best}) =>
    v < target
        ? 1 + (worst - 1) * (target - v) / target
        : 1 - (1 - best) * (math.min(v, cap) - target) / (cap - target);

/// Is [day] one of the [days] days ending on [today]?
bool _within(String day, String today, int days) {
  final t = DateTime.parse(today);
  final from = dayLabelOf(DateTime(t.year, t.month, t.day - days + 1));
  return day.compareTo(from) >= 0 && day.compareTo(today) <= 0;
}
