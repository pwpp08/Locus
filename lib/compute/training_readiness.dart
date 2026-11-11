// training_readiness.dart — how ready the day is for hard training, 0–100,
// from the same six things Garmin's Training Readiness names: last night's
// sleep, recovery time, HRV status, acute load, the last three nights' sleep
// and the last three days' stress. Locus has a recovery score of its own, so
// it is a seventh.
//
// Every factor is read off a stored value and turned into 0–100, and each is
// shown next to the score, so the number can always be traced back. A factor
// with no stored input is left out, never filled in; with fewer than four
// there is no score.
//
// ponytail: Garmin publishes no weights. The score is the mean of the factors
// pulled toward the weakest (70 % mean, 30 % lowest), so one poor input holds
// the day back as Garmin's does, and recovery time is 0.2 × strain² hours
// after a session (strain 8 ≈ 13 h, 12 ≈ 29 h, 15 = 45 h, 18 ≈ 65 h), the
// spread Garmin's own recovery times show. Neither is fitted. A metric, so it
// belongs in the analytics repo; it lives here as energy_reserve.dart does.
// Nothing is persisted, so no kAlgoVersion bump rides on it.

import 'dart:math' as math;

/// The fewest factors a score is made from.
const int kReadinessMinFactors = 4;

/// Hours of recovery time at which that factor reaches 0.
const double kReadinessRecoveryHoursZero = 48;

/// Hours a session of [strain] (0–21) asks to recover from.
double recoveryHoursFor(double strain) => .2 * strain * strain;

/// Hours still owed at [now] (epoch seconds) after [sessions], each
/// (end epoch seconds, strain). The longest still running wins: recovery
/// times overlap, they do not add.
double recoveryHoursLeft(List<(int, double)> sessions, int now) {
  var left = 0.0;
  for (final (end, strain) in sessions) {
    if (end > now) continue;
    final owed = recoveryHoursFor(strain) - (now - end) / 3600;
    left = math.max(left, owed);
  }
  return left;
}

enum ReadinessFactor {
  recoveryTime,
  sleep,
  recovery,
  hrv,
  load,
  sleepHistory,
  stressHistory,
}

enum ReadinessLevel { prime, high, moderate, low, poor }

/// Garmin's bands: 95+ prime, 75 high, 50 moderate, 25 low, under it poor.
ReadinessLevel readinessLevelOf(int score) => score >= 95
    ? ReadinessLevel.prime
    : score >= 75
        ? ReadinessLevel.high
        : score >= 50
            ? ReadinessLevel.moderate
            : score >= 25
                ? ReadinessLevel.low
                : ReadinessLevel.poor;

class TrainingReadiness {
  /// 0–100, or null with too few factors.
  final int? score;

  /// Each factor's 0–100, only those with an input.
  final Map<ReadinessFactor, int> factors;

  /// Recovery time still owed, hours; null when no session was read.
  final double? recoveryHours;

  const TrainingReadiness({
    required this.score,
    required this.factors,
    this.recoveryHours,
  });

  ReadinessLevel? get level => score == null ? null : readinessLevelOf(score!);

  /// The factor holding the score down most, or null when none is under 75.
  ReadinessFactor? get weakest {
    ReadinessFactor? out;
    for (final e in factors.entries) {
      if (e.value >= 75) continue;
      if (out == null || e.value < factors[out]!) out = e.key;
    }
    return out;
  }
}

/// [sleepPerf] last night's sleep performance, %. [recovery] today's, %.
/// [hrv7] the mean HRV of the last 7 nights and [hrvBase] the mean and SD of
/// the 30 before them. [acute] / [chronic] the 7- and 42-day loads.
/// [sleep3] the last three nights' sleep performance. [stress3] the last
/// three days' mean stress, 0–3. [sessions] (end, strain) over the last three
/// days, with [now]; null when sessions were not read.
TrainingReadiness trainingReadiness({
  double? sleepPerf,
  double? recovery,
  double? hrv7,
  ({double mean, double sd})? hrvBase,
  double? acute,
  double? chronic,
  List<double> sleep3 = const [],
  List<double> stress3 = const [],
  List<(int, double)>? sessions,
  int? now,
}) {
  int pct(double v) => v.clamp(0.0, 100.0).round();
  final f = <ReadinessFactor, int>{};
  double? hours;

  if (sessions != null && now != null) {
    hours = recoveryHoursLeft(sessions, now);
    f[ReadinessFactor.recoveryTime] =
        pct(100 * (1 - hours / kReadinessRecoveryHoursZero));
  }
  if (sleepPerf != null) f[ReadinessFactor.sleep] = pct(sleepPerf);
  if (recovery != null) f[ReadinessFactor.recovery] = pct(recovery);
  if (hrv7 != null && hrvBase != null && hrvBase.sd > 0) {
    // Inside or above the usual range is balanced; each SD under its floor
    // costs half the factor.
    final floor = hrvBase.mean - hrvBase.sd;
    f[ReadinessFactor.hrv] =
        pct(hrv7 >= floor ? 100 : 100 - 50 * (floor - hrv7) / hrvBase.sd);
  }
  if (acute != null && chronic != null && chronic > 0) {
    // Acute over chronic: up to 1.3 is productive; past it the factor falls,
    // to 0 at 2.0.
    final r = acute / chronic;
    f[ReadinessFactor.load] = pct(r <= 1.3 ? 100 : 100 * (2.0 - r) / .7);
  }
  if (sleep3.isNotEmpty) {
    f[ReadinessFactor.sleepHistory] =
        pct(sleep3.reduce((a, b) => a + b) / sleep3.length);
  }
  if (stress3.isNotEmpty) {
    // The neutral score (0.8) and under is no cost; 3 is all of it.
    final s = stress3.reduce((a, b) => a + b) / stress3.length;
    f[ReadinessFactor.stressHistory] = pct(100 * (1 - (s - .8) / 2.2));
  }

  if (f.length < kReadinessMinFactors) {
    return TrainingReadiness(score: null, factors: f, recoveryHours: hours);
  }
  final vs = f.values;
  final mean = vs.reduce((a, b) => a + b) / vs.length;
  final low = vs.reduce(math.min);
  return TrainingReadiness(
    score: pct(.7 * mean + .3 * low),
    factors: f,
    recoveryHours: hours,
  );
}
