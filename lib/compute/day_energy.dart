// A day's active energy, with the minutes under the heart-rate gate priced.
//
// WHY THIS EXISTS. `Calories.dailyEnergy` (analytics) bills a wake minute the
// Keytel rate only when its heart rate is at or over 40 % of heart-rate
// reserve, and a minute under that gate earns nothing unless its measured
// step cadence is at least 100 a minute. So a day of walking about at 90 bpm
// and 80 steps a minute read 0 kcal, and a day a few beats over the gate read
// a thousand: two days of similar strain could differ tenfold (a strain-8 day
// at 104 kcal next to a strain-15 day at 1,336). The gate itself is right
// (Keytel's regression has no data under it); the cliff under it is not.
//
// What changes, and only under the gate:
//   * A measured cadence under 100 a minute is priced on a straight line from
//     1 MET at no steps to the 3 METs CADENCE-Adults puts at 100, where the
//     package's own pricing takes over, so the two meet with no step.
//   * A minute with no cadence but a moving wrist is priced from its heart
//     rate on a straight line from 1 MET at the resting rate to 3 METs at the
//     gate (ACSM's moderate floor is both 40 % of reserve and 3 METs, so the
//     line ends where the gate's own definition does), weighted by how much
//     of the minute the wrist was moving.
//   * A still wrist with a raised pulse (stress, caffeine, a hot room) earns
//     nothing, as before: only measured movement opens this door.
// A minute takes the larger of its two prices, never both. Over the gate,
// and the basal floor, are the package's arithmetic unchanged.
//
// This is metric arithmetic that belongs in the analytics repo; it lives here
// because analytics is pinned upstream. It reuses that package's constants
// (the gate, Keytel, Mifflin, the cadence METs) so nothing is defined twice.

import 'package:openstrap_analytics/onehz.dart' as ana;

/// A measured cadence under this many steps a minute is no walking at all.
const double kLightCadenceFloorSpm = 10.0;

/// The METs at the top of the light band: CADENCE-Adults at 100 steps a
/// minute, and ACSM's moderate floor at 40 % of heart-rate reserve.
const double kLightBandTopMet = 3.0;

/// The wrist's moving share of a minute (`compute/movement.dart`) at which a
/// minute counts as moving at all, and at which it counts fully.
const double kMoveShareFloor = .05;
const double kMoveShareFull = .30;

/// METs for a measured cadence under the package's 100-a-minute floor, or
/// null when it is too few steps to call walking.
double? lightCadenceMet(double spm) {
  if (!spm.isFinite || spm < kLightCadenceFloorSpm) return null;
  if (spm >= 100) return ana.Calories.metFromCadenceSpm(spm);
  return 1 + (kLightBandTopMet - 1) * spm / 100;
}

/// How much of the light band a moving minute earns, 0…1: [hr]'s place
/// between [restingHr] and [gateHr], times how much the wrist moved.
double lightMoveShare(double hr, double moveShare, double restingHr,
    double gateHr) {
  if (!hr.isFinite || !moveShare.isFinite || gateHr <= restingHr) return 0;
  final f = ((hr - restingHr) / (gateHr - restingHr)).clamp(0.0, 1.0);
  final w = ((moveShare - kMoveShareFloor) / (kMoveShareFull - kMoveShareFloor))
      .clamp(0.0, 1.0);
  return f * w;
}

/// The day's energy: `basal` over [dayMinutes], `active` the surplus over it
/// across the wake minutes, `walking` the part of active priced from cadence
/// under the gate, `light` the part priced from a moving wrist under it.
///
/// [hrPerMin], [cadenceSpmPerMin] and [moveSharePerMin] are index-aligned,
/// one entry per wake minute with a heart rate; a null cadence or moving share
/// is a minute nobody measured. Null when the anchors cannot define a gate,
/// exactly as `Calories.dailyEnergy`.
({double total, double active, double basal, double walking, double light})?
    dayEnergy(
  List<double> hrPerMin, {
  required ana.WorkoutUserProfile profile,
  required double hrmax,
  required double restingHr,
  int dayMinutes = 1440,
  List<double?>? cadenceSpmPerMin,
  List<double?>? moveSharePerMin,
}) {
  final n = hrPerMin.length;
  if ((cadenceSpmPerMin != null && cadenceSpmPerMin.length != n) ||
      (moveSharePerMin != null && moveSharePerMin.length != n)) {
    throw ArgumentError('cadence and moving share must align with the '
        'heart rate: one entry per wake minute');
  }
  final gate = ana.Calories.activeGateHr(hrmax, restingHr);
  if (gate == null) return null;
  // The package's own floors for a profile value it was handed as 0.
  final kg = profile.weightKg > 0 ? profile.weightKg : 70.0;
  final cm = profile.heightCm > 0 ? profile.heightCm : 170.0;
  final age = profile.age > 0 ? profile.age : 30.0;
  final coeffs = ana.Calories.resolveCoeffs(profile.sex);
  final basalPerMin =
      ana.Calories.mifflinBmrKcalDay(kg, cm, age, profile.sex) / 1440.0;

  var active = 0.0, walking = 0.0, light = 0.0;
  for (var i = 0; i < n; i++) {
    final hr = hrPerMin[i];
    if (hr.isFinite && hr >= gate) {
      final perMin =
          ana.Calories.activeKcalPerS(coeffs, hr, hrmax, kg, age) * 60.0;
      if (perMin > basalPerMin) active += perMin - basalPerMin;
      continue;
    }
    final cad = cadenceSpmPerMin?[i];
    final met = cad == null ? null : lightCadenceMet(cad);
    final byCadence = met == null ? 0.0 : (met - 1) * basalPerMin;
    final move = moveSharePerMin?[i];
    final byMove = move == null
        ? 0.0
        : lightMoveShare(hr, move, restingHr, gate) *
            (kLightBandTopMet - 1) *
            basalPerMin;
    if (byCadence >= byMove) {
      walking += byCadence;
    } else {
      light += byMove;
    }
  }
  active += walking + light;
  final basal = basalPerMin * dayMinutes;
  return (
    total: basal + active,
    active: active,
    basal: basal,
    walking: walking,
    light: light,
  );
}

/// The wrist's moving share of each of [minuteKeys] (epoch seconds ~/ 60),
/// from `movementBuckets`' per-minute output; null for a minute it did not
/// count.
List<double?> moveShareForMinutes(
  List<int> minuteKeys,
  List<({int t, double v})> perMinute,
) {
  final byKey = {for (final b in perMinute) b.t ~/ 60: b.v};
  return [for (final k in minuteKeys) byKey[k]];
}
