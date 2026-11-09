// energy_reserve.dart — a 0–100 estimate of how much is left in the tank today.
//
// Battery-style scores from other wearables publish no formula. What they
// describe in common: sleep charges it, effort and raised heart rate drain it,
// and the morning level reflects how recovered you are. So this anchors the
// wake level on the day's recovery score, charges through sleep, and drains
// from each measured minute's heart-rate reserve.
//
// A gap in the heart rate (off the wrist) changes nothing: time nobody measured
// is neither rest nor effort. With no recovery, resting heart rate, max heart
// rate or wake time there is no reading at all.
//
// ponytail: the rates are hand-set so a normal day charges and drains roughly
// 40–60 points; they are not fitted to anything. A metric, so it belongs in the
// analytics repo; it lives here as whoop_age.dart does. Nothing it returns is
// persisted, so no kAlgoVersion bump rides on it.

import 'dart:math' as math;

/// Points gained per minute asleep.
const double kEnergyChargePerMin = .11;

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

/// Points lost per minute at heart-rate reserve [hrr] while awake.
double energyDrainPerMin(double hrr) {
  if (hrr < .05) return .03;
  if (hrr < .2) return .06;
  if (hrr < kEnergyEffortHrr) return .12;
  return .2 + 1.2 * (hrr - kEnergyEffortHrr);
}

/// [hr] is (epoch seconds, bpm) in any order. [naps] are (start, end) epochs.
/// [midnight] clips the night to today's chart.
EnergyReserve? energyReserve({
  required List<(int, double)> hr,
  required int? onsetTs,
  required int? wakeTs,
  required double? recovery,
  required double? restingHr,
  required double? maxHr,
  required int midnight,
  List<(int, int)> naps = const [],
}) {
  if (wakeTs == null ||
      onsetTs == null ||
      recovery == null ||
      restingHr == null ||
      maxHr == null ||
      maxHr <= restingHr) {
    return null;
  }
  final awake = [
    for (final s in hr)
      if (s.$1 >= wakeTs && s.$2 > 0) s,
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (awake.isEmpty) return null;

  final woke = (25 + .7 * recovery).clamp(0.0, 100.0).toDouble();
  final asleepMin = math.max(0, wakeTs - onsetTs) / 60;
  final startLevel = math.max(5.0, woke - asleepMin * kEnergyChargePerMin);
  final chartStart = math.max(onsetTs, midnight);
  final atChartStart =
      woke - (wakeTs - chartStart) / 60 * kEnergyChargePerMin;
  final points = <(int, double)>[
    if (chartStart < wakeTs) (chartStart, math.max(startLevel, atChartStart)),
    (wakeTs, woke),
  ];

  var level = woke;
  var charged = woke - startLevel;
  var drained = 0.0;
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
  var prev = awake.first.$1;
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
    if (napping(t)) {
      closeEffort();
      final gain = math.min(100 - level, mins * kEnergyChargePerMin);
      level += gain;
      charged += gain;
    } else {
      final hrr = (bpm - restingHr) / (maxHr - restingHr);
      final loss = math.min(level, energyDrainPerMin(hrr) * mins);
      level -= loss;
      drained += loss;
      if (hrr >= kEnergyEffortHrr) {
        effortStart ??= t;
        effortLoss += loss;
        effortSec += dt;
      } else {
        closeEffort();
      }
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
