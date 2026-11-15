// A nap's stages: the night's own stager run over the nap's window.
//
// Naps used to carry only a window and the minutes asleep. An earlier nap
// screen drew stages anyway, from a script (deep 40 %, REM 10 %), and that was
// rightly removed. These are not that: they are `segmentSleep`'s output over
// the nap's seconds, forced to the window the person confirmed, exactly as a
// night set by hand is staged. Light and deep carry the same low-confidence
// caveat as a night's (`deep_low_confidence` in the analytics output).
//
// Abstains (null) rather than stage a nap the band barely saw: under
// [kNapStageMinSec] of window, or under [kNapStageMinCoverage] of its seconds
// recorded with a heart rate.

import 'package:openstrap_analytics/onehz.dart' as ana;

import 'substrate.dart';

/// The shortest nap that is staged.
const int kNapStageMinSec = 15 * 60;

/// The share of a nap's seconds that must carry a heart rate.
const double kNapStageMinCoverage = .7;

/// The stages of the nap in [startSec, endSec) from [s], or null.
///
/// `{asleep_min, in_bed_min, wake_min, light_min, deep_min, rem_min,
/// efficiency, runs}`, where `runs` is the hypnogram as `[start, end, stage]`
/// (epoch seconds, stage one of wake / light / deep / rem / unobserved).
Map<String, dynamic>? stageNap(Substrate s, int startSec, int endSec) {
  if (endSec - startSec < kNapStageMinSec) return null;
  final w = s.slice(startSec, endSec);
  if (w.isEmpty) return null;
  final worn = [for (final h in w.hr) if (h > 0) h].length;
  if (worn < (endSec - startSec) * kNapStageMinCoverage) return null;
  final accel = <ana.AccelSample>[
    for (var i = 0; i < w.length; i++)
      ana.AccelSample(w.tsSec[i] * 1000.0, w.ax[i], w.ay[i], w.az[i],
          valid: w.accelPresentAt(i)),
  ];
  final seg = ana.segmentSleep(
    accel,
    [for (final h in w.hr) h.toDouble()],
    rrMs: w.rrMs,
    rrTsMs: w.rrTsMs,
    forcedWindow: (onsetSec: startSec, offsetSec: endSec),
  );
  final labels = seg.stages4;
  final onsetMs = seg.window?.onsetMs;
  final tst = seg.tstSec;
  if (labels.isEmpty || onsetMs == null || tst == null) return null;
  final t0 = (onsetMs / 1000).round();
  final runs = <List<Object>>[];
  var from = 0;
  for (var i = 1; i <= labels.length; i++) {
    if (i == labels.length || labels[i] != labels[from]) {
      runs.add([t0 + from, t0 + i, labels[from]]);
      from = i;
    }
  }
  int min(int? sec) => ((sec ?? 0) / 60).round();
  return {
    'asleep_min': min(tst),
    'in_bed_min': min(seg.inBedSec ?? labels.length),
    'wake_min': min(seg.wakeSec),
    'light_min': min(seg.lightSec),
    'deep_min': min(seg.deepSec),
    'rem_min': min(seg.remSec),
    'efficiency': seg.efficiencyPct,
    'runs': runs,
  };
}
