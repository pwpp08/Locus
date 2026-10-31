// strain_peak.dart — strain never falls through a day (or a session).
//
// Analytics nets quiet waking minutes against light activity banked earlier
// (`strainCurveFromSeries`, NetTrimp), so its running score can dip through a
// quiet afternoon and the day ended lower than it had already been. The app's
// strain is the HIGHEST that running score reached: once earned, it stays.
//
// ponytail: done here as orchestration over the analytics curve rather than in
// analytics, at the user's call (2026-10-31). analytics' own doc warns that a
// running max of a random walk around the quiet level drifts up on idle days
// (MOT-05); the netting still holds the walk near zero, so the drift is small,
// but if quiet days read high, move this upstream with a dead-band on living.

import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart' as ana;

/// The running 0–21 strain after each minute of [hrPerMin], never lower than
/// it has been: analytics' curve held at its highest so far. Null when
/// analytics abstains (missing or degenerate anchors, no valid minute).
List<double>? keptStrainCurve(
  List<double> hrPerMin, {
  required double? restingHr,
  required double? maxHr,
  required double? quietHrr,
  required ana.Sex sex,
}) {
  final c = ana.strainCurveFromSeries(
    hrPerMin,
    restingHr: restingHr,
    maxHr: maxHr,
    quietHrr: quietHrr,
    sex: sex,
  );
  if (c == null) return null;
  var hi = 0.0;
  return [for (final v in c) hi = math.max(hi, v)];
}

/// The window's strain: the highest its running score reached. Null when
/// analytics abstains.
double? peakStrain(
  List<double> hrPerMin, {
  required double? restingHr,
  required double? maxHr,
  required double? quietHrr,
  required ana.Sex sex,
}) {
  final c = keptStrainCurve(hrPerMin,
      restingHr: restingHr, maxHr: maxHr, quietHrr: quietHrr, sex: sex);
  return c == null || c.isEmpty ? null : c.last;
}
