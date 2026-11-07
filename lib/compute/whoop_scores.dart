// WHOOP-PARITY SCORES — the headline numbers computed the way WHOOP computes
// them, as far as WHOOP's own documents and fits to real WHOOP exports show.
// The sources and how far each is trusted are in
// docs/proposals/whoop-parity-research.md; every constant below names its own.
//
// "FIT" means a regression on one member's WHOOP export (121 days, Jun–Oct
// 2026, checked on held-out days), published in the reinmaker/noop fork. The
// numbers are reimplemented from its description (that code is PolyForm
// Noncommercial, this repo is AGPL), not copied.
//
// ponytail: metrics belong in the analytics sibling repo. These live here for
// the same reason stress_monitor.dart and vo2max_estimate.dart do: that repo is
// pinned and not editable from this one. Pure arithmetic, no IO. Move them with
// the next analytics pin.

import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart';

// ── RECOVERY ────────────────────────────────────────────────────────────────
//
// FIT: Recovery = 100 / (1 + e^-(0.7325 + 0.5978·z_HRV + 0.0877·z_RHR
// + 0.0582·z_resp)), each z against the previous 14 nights (mean, and 1.253 ×
// the mean absolute deviation about it), lower RHR and breathing rate counting
// as better. RMSE 6 points against WHOOP, colour band right 82% of the time; a
// night at baseline reads 67.5%. Sleep and skin temperature were tried and
// carried no weight, so they are not inputs (they still feed Health Monitor
// and the illness signals). WHOOP's support page names HRV and RHR "the two
// biggest contributors"; the fit says HRV by far.

const int kWhoopRecoveryWindow = 14;
const int kWhoopRecoveryMinNights = 5;
const double kWhoopRecoveryIntercept = 0.7325;
const double kWhoopRecoveryHrvCoef = 0.5978;
const double kWhoopRecoveryRhrCoef = 0.0877;
const double kWhoopRecoveryRespCoef = 0.0582;

/// WHOOP's colour bands (support article "WHOOP Recovery"): green 67 and up,
/// red 33 and below.
const double kWhoopRecoveryGreenFrom = 67;
const double kWhoopRecoveryRedBelow = 34;

/// One input's z against the last [kWhoopRecoveryWindow] values of [history]
/// (oldest first, strictly before tonight): (v − mean) / (1.253 × mean
/// absolute deviation). Null under [kWhoopRecoveryMinNights] values or with no
/// dispersion to scale by. [quantum] refuses a baseline whose spread the
/// instrument cannot resolve (`dispersionBelowQuantum`, the same guard the
/// analytics composite uses), rather than blowing quantization noise up.
double? whoopZ(double? v, List<double> history, {double quantum = 0}) {
  if (v == null || !v.isFinite) return null;
  final xs = [
    for (final x in history.length > kWhoopRecoveryWindow
        ? history.sublist(history.length - kWhoopRecoveryWindow)
        : history)
      if (x.isFinite) x,
  ];
  if (xs.length < kWhoopRecoveryMinNights) return null;
  if (dispersionBelowQuantum(xs, quantum)) return null;
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  final mad = xs.fold<double>(0, (a, x) => a + (x - mean).abs()) / xs.length;
  final spread = 1.253 * mad;
  if (!(spread > 0)) return null;
  return (v - mean) / spread;
}

/// WHOOP-style Recovery from tonight's HRV (RMSSD, ms), resting HR and
/// breathing rate against the nights before. HRV is required — WHOOP's score
/// is built on it — so without HRV, or without [kWhoopRecoveryMinNights] of
/// HRV history, this is absent with a reason, never a partial score.
///
/// The returned [Readiness.compositeZ] is the weighted z (the logit minus the
/// intercept), so `kReadinessZCap` keeps guarding degenerate baselines.
Metric<Readiness> whoopRecovery({
  required double? hrvMs,
  required List<double> hrvHistoryMs,
  required double? rhr,
  required List<double> rhrHistory,
  required double? resp,
  required List<double> respHistory,
}) {
  const inputs = ['hrv', 'rhr', 'resp'];
  if (hrvMs == null) {
    return const Metric<Readiness>.absent(
      tier: Tier.estimate,
      inputs_used: inputs,
      note: 'need_inputs:hrv',
    );
  }
  final zHrv = whoopZ(hrvMs, hrvHistoryMs);
  if (zHrv == null) {
    final have = hrvHistoryMs.where((x) => x.isFinite).length;
    return Metric<Readiness>.absent(
      tier: Tier.estimate,
      inputs_used: inputs,
      note: have < kWhoopRecoveryMinNights
          ? needBaselineNote(have: have, need: kWhoopRecoveryMinNights)
          : 'hrv: baseline_has_no_dispersion',
    );
  }
  // Oriented so + is good: lower RHR and breathing rate are better.
  final zRhr = whoopZ(rhr, rhrHistory, quantum: 1);
  final zResp = whoopZ(resp, respHistory);
  final drivers = <Driver>[
    Driver('HRV', kWhoopRecoveryHrvCoef * zHrv),
    if (zRhr != null) Driver('RHR', -kWhoopRecoveryRhrCoef * zRhr),
    if (zResp != null) Driver('RR', -kWhoopRecoveryRespCoef * zResp),
  ]..sort((a, b) => b.contribution.abs().compareTo(a.contribution.abs()));
  final z = drivers.fold<double>(0, (a, d) => a + d.contribution);
  final score = 100 / (1 + math.exp(-(kWhoopRecoveryIntercept + z)));
  return Metric<Readiness>(
    value: Readiness(score, z),
    confidence: (0.45 + 0.15 * drivers.length).clamp(0.0, 0.9),
    tier: Tier.estimate,
    inputs_used: [for (final d in drivers) d.label],
    drivers: drivers,
    note: 'WHOOP-fit recovery: logistic(0.7325 + 0.5978 z_HRV + 0.0877 z_RHR↓ '
        '+ 0.0582 z_RR↓), z vs previous $kWhoopRecoveryWindow nights.',
  );
}

// ── STRAIN ──────────────────────────────────────────────────────────────────
//
// WHOOP's patent (US9750415B2) weights each moment's heart-rate-reserve
// fraction more steeply the higher it sits and maps the integral onto 0-21;
// WHOOP publishes neither the weights' cut points nor the map. FIT supplies
// both as one curve: a minute at reserve fraction x (0-1) adds
// x·e^(4.025x), less what a minute at x = 0.1735 would (so sitting around is
// free), and Strain = 3.584·ln(1 + load/11.48), capped at 21. RMSE 1.3 per
// activity against WHOOP's Activity Strain. Against WHOOP's own published
// examples (Locker, "How does the WHOOP Strain Target work?"): an hour at 35%
// of reserve reads 6.8 (WHOOP's hour of walking: about 6.5), an hour at 60%
// reads 12.7 (an hour of running: about 12.0).
//
// The fit priced reserve on a fixed 190 bpm ceiling; this uses the wearer's
// own (`estimatedMaxHr`), which is what WHOOP's HRR zones do.

const double kWhoopStrainB = 4.025;
const double kWhoopStrainFloorHrr = 0.1735;
const double kWhoopStrainA = 3.584;
const double kWhoopStrainC = 11.48;

/// The load one minute at reserve fraction [x] adds (0 at or below the floor).
double whoopMinuteLoad(double x) {
  final xc = x.clamp(0.0, 1.0);
  final floor = kWhoopStrainFloorHrr * math.exp(kWhoopStrainB * kWhoopStrainFloorHrr);
  return math.max(0.0, xc * math.exp(kWhoopStrainB * xc) - floor);
}

/// Strain on WHOOP's 0-21 axis for an accumulated [load].
double whoopStrainFromLoad(double load) => load <= 0
    ? 0.0
    : math.min(21.0, kWhoopStrainA * math.log(1 + load / kWhoopStrainC));

/// The load behind a Strain (inverse of [whoopStrainFromLoad]).
double whoopLoadForStrain(double strain) =>
    kWhoopStrainC * (math.exp(strain.clamp(0.0, 21.0) / kWhoopStrainA) - 1);

/// The muscular load WHOOP adds to a strength-type session it has no logged
/// sets for: it estimates it "based on activity type and duration" (support
/// article "WHOOP Strain"). FIT: 0.0773 × minutes² of load on top of the
/// heart-rate load matched WHOOP's Activity Strain for 36 weightlifting
/// sessions of 22-57 min to 0.18 Strain (heart rate alone: 1.1 off).
double whoopMuscularLoad(double minutes) =>
    minutes <= 0 ? 0.0 : 0.0773 * minutes * minutes;

/// Activity types WHOOP adds muscular load to without logged sets (support
/// article: weightlifting, functional fitness, HIIT, powerlifting; yoga,
/// Pilates and barre "calculated automatically").
/// Keys are the session `type` spellings `health_export.dart` maps to
/// strength training, plus the others WHOOP names.
const Set<String> kWhoopMuscularTypes = {
  'strength', 'weights', 'lifting', 'weight_training', 'weightlifting',
  'powerlifting', 'kettlebell', 'functional_fitness', 'crossfit', 'hiit',
  'yoga', 'pilates', 'barre',
};

// ── SLEEP NEED, DEBT, CONSISTENCY, PERFORMANCE ──────────────────────────────
//
// WHOOP (support article "WHOOP Sleep"): need = baseline + today's Strain +
// sleep debt − naps, and naps reduce need, not debt.
//
// Strain term, WHOOP's patent US9750415B2: f(i) = 1.7 / (1 + e^((17 − i)/3.5))
// hours for a Day Strain i. It reproduces every WHOOP figure we have: Strain
// 15 → 36.8 min (WHOOP's own example: 37), 10.2 → 12 min and 11.1 → 16 min
// (two WHOOP app readouts quoted in the FIT).
//
// Debt, FIT: half of the previous night's shortfall against that night's own
// need, one night deep: RMSE 5.7 min against WHOOP's Sleep debt column, where
// a 14-night 55 % ledger overstated it by about 70 min.

/// Minutes of sleep need a Day Strain adds (patent curve).
double whoopStrainSleepMin(double strain) =>
    60 * 1.7 / (1 + math.exp((17 - strain.clamp(0.0, 21.0)) / 3.5));

/// The share of a night's shortfall carried into the next night's need.
const double kWhoopDebtCarry = 0.5;

/// One night's need in its parts, minutes.
class WhoopNightNeed {
  final double baselineMin, strainMin, debtMin, napMin;
  const WhoopNightNeed(
      this.baselineMin, this.strainMin, this.debtMin, this.napMin);
  double get needMin =>
      math.max(0.0, baselineMin + strainMin + debtMin - napMin);
}

/// The chain of needs, oldest night first. [nights] are aligned by the caller:
/// each entry is the night's own minutes asleep (null: no night recorded) and
/// the Strain and nap minutes of the DAY BEFORE it (null: none measured, which
/// adds and removes nothing). Returns the need of every night, then one more:
/// tonight's, from [todayStrain] and [todayNapMin].
List<WhoopNightNeed> whoopSleepNeeds({
  required double baselineMin,
  required List<({double? tstMin, double? priorStrain, double? priorNapMin})>
      nights,
  required double? todayStrain,
  required double? todayNapMin,
}) {
  double? lastNeed;
  double? lastTst;
  WhoopNightNeed needWith(double? strain, double? napMin) => WhoopNightNeed(
        baselineMin,
        strain == null ? 0.0 : whoopStrainSleepMin(strain),
        lastNeed == null || lastTst == null
            ? 0.0
            : kWhoopDebtCarry * math.max(0.0, lastNeed - lastTst),
        napMin ?? 0.0,
      );
  final out = <WhoopNightNeed>[];
  for (final n in nights) {
    final need = needWith(n.priorStrain, n.priorNapMin);
    out.add(need);
    // Only a night with a sleep total hands debt on; one without is skipped.
    if (n.tstMin != null) {
      lastNeed = need.needMin;
      lastTst = n.tstMin;
    }
  }
  out.add(needWith(todayStrain, todayNapMin));
  return out;
}

/// WHOOP Sleep Consistency (white paper: "how similar sleep and wake times are
/// over the last 24 hours compared to the previous 4 days"; support: needs 3
/// consecutive nights). FIT: the newest night against each of up to three
/// before it, each pair scored max(0, 1 − ((|Δonset| + |Δwake|)/700 min)^0.75),
/// averaged, in percent. [windows] are oldest first, as local clock minutes
/// with onset on a noon-to-noon clock (so 23:00 and 01:00 are 120 apart) and
/// wake = onset + minutes in between. Null under three nights.
double? whoopSleepConsistency(List<({double onset, double wake})> windows) {
  if (windows.length < 3) return null;
  final last = windows.last;
  final prior = windows.sublist(math.max(0, windows.length - 4),
      windows.length - 1);
  var sum = 0.0;
  for (final p in prior) {
    final shift = (last.onset - p.onset).abs() + (last.wake - p.wake).abs();
    sum += math.max(0.0, 1 - math.pow(shift / 700, 0.75));
  }
  return sum / prior.length * 100;
}

/// WHOOP Sleep Performance (support: sufficiency, consistency, efficiency and
/// sleep stress, weighted). FIT: 0.272 × hours vs needed (capped at 100) +
/// 0.327 × consistency + 0.368 × efficiency, all in percent; RMSE 3 points
/// against WHOOP (hours vs needed alone: 11). Sleep stress added nothing to
/// the fit. Without consistency (under three nights) the other two carry the
/// same total weight. Null without minutes asleep, a need, or efficiency.
double? whoopSleepPerformance({
  required double? tstMin,
  required double? needMin,
  required double? efficiencyPct,
  double? consistencyPct,
}) {
  if (tstMin == null || needMin == null || efficiencyPct == null) return null;
  if (tstMin <= 0 || needMin <= 0) return null;
  final hvn = math.min(100.0, tstMin / needMin * 100);
  final eff = efficiencyPct <= 1 ? efficiencyPct * 100 : efficiencyPct;
  final score = consistencyPct == null
      ? (0.272 * hvn + 0.368 * eff) * (0.967 / 0.640)
      : 0.272 * hvn + 0.327 * consistencyPct + 0.368 * eff;
  return score.clamp(0.0, 100.0).toDouble();
}

// ---------------------------------------------------------------------------
// Health Monitor
// ---------------------------------------------------------------------------

/// Nights the Health Monitor range looks back over, and the fewest it needs.
const int kWhoopMonitorWindow = 30;
const int kWhoopMonitorMinNights = 14;

/// How far out on the harmful side a reading must sit to be flagged.
const double kWhoopMonitorFlagSd = 2.0;

/// WHOOP's Health Monitor reading of one vital against the nights BEFORE it.
///
/// FIT: the printed "typical range" is the 25th–75th percentile of the last 30
/// nights (it matched WHOOP's ranges to the digit). A reading just outside it
/// stays green; WHOOP only flags a reading far out on the harmful side
/// ([harmfulUp]: RHR, resp and skin temp up; HRV down), seen at about 1.4–3.5
/// SD, so [kWhoopMonitorFlagSd]. Null under [kWhoopMonitorMinNights] nights or
/// on a flat history.
({double lo, double hi, bool flagged})? whoopMonitorReading(
  double v,
  List<double> prior, {
  required bool harmfulUp,
}) {
  final w = [
    for (final x in prior.skip(math.max(0, prior.length - kWhoopMonitorWindow)))
      if (x.isFinite) x,
  ];
  if (w.length < kWhoopMonitorMinNights) return null;
  final mean = w.reduce((a, b) => a + b) / w.length;
  final sd = math.sqrt(
      w.fold<double>(0, (a, x) => a + (x - mean) * (x - mean)) / (w.length - 1));
  if (!(sd > 0)) return null;
  final s = [...w]..sort();
  double pct(double p) {
    final i = p * (s.length - 1);
    final f = i.floor();
    return f + 1 >= s.length ? s[f] : s[f] + (s[f + 1] - s[f]) * (i - f);
  }

  final z = (v - mean) / sd;
  return (
    lo: pct(0.25),
    hi: pct(0.75),
    flagged: harmfulUp ? z >= kWhoopMonitorFlagSd : z <= -kWhoopMonitorFlagSd,
  );
}

// ---------------------------------------------------------------------------
// Strain target
// ---------------------------------------------------------------------------

/// Today's strain target from today's recovery.
///
/// WHOOP (Locker) sizes the target from today's recovery (and moves it with
/// the strain already taken), not from past training load; its one published
/// example is recovery 70% → 8.3–16.3, optimal 12.3. Nothing else is
/// published, so the optimal is a straight line through that point that
/// spans most of the 0–21 scale (6 at 0%, 15 at 100%) and the range is ±4.
// ponytail: a line through WHOOP's one example. Refit if more readouts turn
// up; WHOOP's intent setting (rest / maintain / perform) would be a ±2 shift.
({double lo, double hi, double optimal})? whoopStrainTarget(double? recovery) {
  if (recovery == null || !recovery.isFinite) return null;
  final optimal = 6 + 0.09 * recovery.clamp(0.0, 100.0);
  return (
    lo: math.max(0.0, optimal - 4),
    hi: math.min(21.0, optimal + 4),
    optimal: optimal,
  );
}
