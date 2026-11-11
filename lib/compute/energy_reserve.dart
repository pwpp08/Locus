// energy_reserve.dart — a 5–100 estimate of how much is left in the tank,
// run the way Garmin and Firstbeat describe Body Battery:
//
//  * It charges and drains at the same time, all day. The line is the net.
//  * Only real rest charges it: a calm heart, above all in sleep. Sitting
//    still with a raised stress score is not rest.
//  * Stress drains it even sitting still; effort drains it faster.
//  * It carries over. This morning starts where last night began, plus what
//    the night put back; a hard yesterday is a lower start today.
//  * It runs 5 to 100. Charged and drained count from midnight.
//
// The minute's stress is the Stress Monitor's own score (heart rate and HRV
// against your last 14 days, movement taken out; `stress_monitor.dart`), put
// on Garmin's 0–100 stress scale (× 100 / 3). Garmin's rest band ends at 25,
// which is where our neutral minute (z = 0, score 0.8) lands.
//
// A gap in the heart rate (off the wrist) changes nothing: time nobody
// measured is neither rest nor effort. A night asleep with no stress score
// charges at a flat rate: the sleep is known, its quality is not.
//
// ponytail: Garmin publishes no rates. These are set so a calm 7–8 h night
// puts back 60–80, an ordinary awake hour costs 2–4, and an hour's hard
// session 25–40, the ranges its users report; they are not fitted. A metric,
// so it belongs in the analytics repo; it lives here as whoop_age.dart does.
// Nothing it returns is persisted, so no kAlgoVersion bump rides on it.

import 'dart:math' as math;

/// The floor and the ceiling Garmin draws.
const double kEnergyFloor = 5, kEnergyCeiling = 100;

/// Points an hour asleep with a stress of 0 puts back, per minute.
const double kEnergySleepChargeMax = .2;

/// Asleep with no stress score: the sleep is known, its quality is not.
const double kEnergySleepChargeUnscored = .11;

/// Awake and properly at rest (stress 0): a slow charge, per minute.
const double kEnergyRestChargeMax = .05;

/// Garmin's rest band: at or under this stress an awake minute charges.
const double kEnergyRestLine = 25;

/// Minimum minutes of sustained effort to list as an activity.
const int kEnergyActivityMinMin = 8;

/// Heart-rate reserve from which a minute counts as effort.
const double kEnergyEffortHrr = .4;

/// Longest gap between readings still treated as one continuous stretch.
const int _gapSec = 300;

class EnergyEvent {
  final int ts, delta;
  const EnergyEvent(this.ts, this.delta);
}

class EnergyReserve {
  final double level, wokeLevel;
  final int wokeTs;
  final int charged, drained;

  /// (epoch seconds, level), oldest first.
  final List<(int, double)> points;
  final List<EnergyEvent> activities;

  const EnergyReserve({
    required this.level,
    required this.wokeLevel,
    required this.wokeTs,
    required this.charged,
    required this.drained,
    required this.points,
    required this.activities,
  });
}

/// Points lost per minute at heart-rate reserve [hrr] while awake, when the
/// minute has no stress score to say whether it was rest.
double energyDrainPerMin(double hrr) {
  if (hrr < .05) return .03;
  if (hrr < .2) return .06;
  if (hrr < kEnergyEffortHrr) return .12;
  return .2 + 1.2 * (hrr - kEnergyEffortHrr);
}

/// The net change, per minute, of one minute: positive charges, negative
/// drains. [stress] is the Stress Monitor's 0–3 score, null when unscored;
/// [hrr] the minute's heart-rate reserve.
double energyRatePerMin({
  required bool asleep,
  double? stress,
  double hrr = 0,
}) {
  final g = stress == null ? null : stress.clamp(0.0, 3.0) / 3 * 100;
  if (asleep) {
    return g == null
        ? kEnergySleepChargeUnscored
        : kEnergySleepChargeMax * (1 - g / (2 * kEnergyRestLine)).clamp(0.0, 1.0);
  }
  if (hrr >= kEnergyEffortHrr) return -energyDrainPerMin(hrr);
  if (g == null) return -energyDrainPerMin(hrr);
  if (g <= kEnergyRestLine) {
    return kEnergyRestChargeMax * (kEnergyRestLine - g) / kEnergyRestLine;
  }
  return -(.03 + .09 * (g - kEnergyRestLine) / (100 - kEnergyRestLine));
}

/// The reserve from last night's onset to the last reading, or to [until].
///
/// [hr] is (epoch seconds, bpm) in any order. [stress] is (epoch seconds of
/// the minute's start, 0–3 score). [naps] are (start, end) epochs.
/// [onsetLevel] is where last night began, carried over from yesterday's own
/// run; without it the morning is anchored on [recovery] instead, the night
/// drawn back from it. [midnight] clips charged and drained to today.
EnergyReserve? energyReserve({
  required List<(int, double)> hr,
  required int? onsetTs,
  required int? wakeTs,
  required double? recovery,
  required double? restingHr,
  required double? maxHr,
  required int midnight,
  List<(int, int)> naps = const [],
  List<(int, double)> stress = const [],
  double? onsetLevel,
  int? until,
}) {
  if (wakeTs == null ||
      onsetTs == null ||
      (recovery == null && onsetLevel == null) ||
      restingHr == null ||
      maxHr == null ||
      maxHr <= restingHr) {
    return null;
  }
  final awake = [
    for (final s in hr)
      if (s.$1 >= wakeTs && s.$2 > 0 && (until == null || s.$1 < until)) s,
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (awake.isEmpty && until == null) return null;

  final scoreAt = <int, double>{
    for (final (t, v) in stress) t ~/ 60: v,
  };
  double? scoreOf(int t) => scoreAt[t ~/ 60];

  var charged = 0.0, drained = 0.0;
  void count(int t, double delta) {
    if (t < midnight) return;
    if (delta > 0) {
      charged += delta;
    } else {
      drained -= delta;
    }
  }

  double step(double level, double rate, double mins) =>
      (level + rate * mins).clamp(kEnergyFloor, kEnergyCeiling).toDouble();

  // ── the night ──
  final points = <(int, double)>[];
  final double woke;
  if (onsetLevel != null) {
    var level = onsetLevel.clamp(kEnergyFloor, kEnergyCeiling).toDouble();
    points.add((onsetTs, level));
    for (var t = onsetTs; t < wakeTs; t += 60) {
      final mins = math.min(60, wakeTs - t) / 60;
      final next = step(level,
          energyRatePerMin(asleep: true, stress: scoreOf(t)), mins);
      count(t, next - level);
      level = next;
      if (t + 60 >= wakeTs || (t - points.last.$1) >= 300) {
        points.add((math.min(t + 60, wakeTs), level));
      }
    }
    woke = level;
  } else {
    // No yesterday to carry: the morning comes off recovery, as before, and
    // the night is drawn back from it at the flat sleep rate.
    woke = (25 + .7 * recovery!).clamp(kEnergyFloor, kEnergyCeiling).toDouble();
    final asleepMin = math.max(0, wakeTs - onsetTs) / 60;
    final startLevel =
        math.max(kEnergyFloor, woke - asleepMin * kEnergySleepChargeUnscored);
    final chartStart = math.max(onsetTs, midnight);
    final atChartStart =
        woke - (wakeTs - chartStart) / 60 * kEnergySleepChargeUnscored;
    if (chartStart < wakeTs) {
      final from = math.max(startLevel, atChartStart);
      points.add((chartStart, from));
      charged += woke - from;
    }
    points.add((wakeTs, woke));
  }

  // ── the day ──
  var level = woke;
  final activities = <EnergyEvent>[];
  int? effortStart;
  var effortLoss = 0.0, effortSec = 0;
  void closeEffort() {
    if (effortStart != null && effortSec >= kEnergyActivityMinMin * 60) {
      activities.add(EnergyEvent(effortStart!, -effortLoss.round()));
    }
    effortStart = null;
    effortLoss = 0;
    effortSec = 0;
  }

  bool napping(int t) => naps.any((n) => t >= n.$1 && t < n.$2);
  var prev = awake.isEmpty ? wakeTs : awake.first.$1;
  for (final (t, bpm) in awake) {
    final dt = t - prev;
    prev = t;
    if (dt <= 0) continue;
    if (dt > _gapSec) {
      closeEffort();
      points.add((t, level));
      continue;
    }
    final mins = dt / 60;
    final hrr = (bpm - restingHr) / (maxHr - restingHr);
    final asleep = napping(t);
    final rate = energyRatePerMin(asleep: asleep, stress: scoreOf(t), hrr: hrr);
    final next = step(level, rate, mins);
    final delta = next - level;
    count(t, delta);
    level = next;
    if (!asleep && hrr >= kEnergyEffortHrr) {
      effortStart ??= t;
      effortLoss -= delta;
      effortSec += dt;
    } else {
      closeEffort();
    }
    if (t - points.last.$1 >= 300) points.add((t, level));
  }
  closeEffort();
  if (points.last.$1 != prev) points.add((prev, level));
  return EnergyReserve(
    level: level,
    wokeLevel: woke,
    wokeTs: wakeTs,
    charged: charged.round(),
    drained: drained.round(),
    points: points,
    activities: activities,
  );
}
