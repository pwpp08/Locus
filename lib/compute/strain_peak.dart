// strain_peak.dart — the running 0–21 strain of a day or a session.
//
// WHOOP's curve (whoop_scores.dart): each minute adds load by how far up the
// heart-rate reserve it sits, and the strain is a log of the total. Load only
// ever adds, so the curve never falls and its last point is its peak — the
// "strain never falls through a day" rule this file used to enforce on
// analytics' net curve now holds by construction.
//
// ponytail: the quiet-waking level no longer prices strain (WHOOP's curve has
// its own fixed floor), but every caller still GATES on having one, so strain
// keeps its 3-day cold start. Strip `quietHrr` from `strainFromPerMinuteHr`,
// the pipeline and the engine's absent notes to show strain from day one.

import 'whoop_scores.dart';

/// The running 0–21 strain after each minute of [hrPerMin]. Null when the
/// reserve anchors are missing or degenerate, or no minute is valid.
List<double>? keptStrainCurve(
  List<double> hrPerMin, {
  required double? restingHr,
  required double? maxHr,
}) {
  if (restingHr == null || maxHr == null) return null;
  final reserve = maxHr - restingHr;
  if (!(reserve > 0) || !restingHr.isFinite) return null;
  var load = 0.0;
  var valid = 0;
  final out = <double>[];
  for (final hr in hrPerMin) {
    if (hr.isFinite && hr > 0) {
      load += whoopMinuteLoad((hr - restingHr) / reserve);
      valid++;
    }
    out.add(whoopStrainFromLoad(load));
  }
  return valid == 0 ? null : out;
}

/// The window's strain (the curve's last point). Null when [keptStrainCurve]
/// abstains.
double? peakStrain(
  List<double> hrPerMin, {
  required double? restingHr,
  required double? maxHr,
}) {
  final c = keptStrainCurve(hrPerMin, restingHr: restingHr, maxHr: maxHr);
  return c == null || c.isEmpty ? null : c.last;
}
