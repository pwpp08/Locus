// activity_classifier.dart — what a detected bout most likely was.
//
// The heart-rate detector (analytics' `autoDetectWorkouts`) finds WHEN a
// workout happened and leaves WHAT it was to a seam that, by default, says
// "detected". This file fills that in from what the 1 Hz bundle actually
// carries, in two layers:
//
// 1. Generic rules, from published practice. Cadence off the step counter
//    (the band's, or the phone's 5-minute slices) separates running from
//    walking, the same 60 / 140 spm lines the walk pass uses. Without steps,
//    the wrist and the heart separate the rest: a wrist held still under a
//    steady raised heart rate is a handlebar or an oar (cycling); a heart
//    rate that climbs and falls every few minutes under bursty wrist motion
//    is sets and rests (weight training) or, harder, intervals (HIIT). The
//    1 Hz gravity vector cannot see gait (Nyquist 0.5 Hz, under the
//    1.4–2.5 Hz of a step), so the wrist only ever reads as an AMPLITUDE.
// 2. The person's own kept sessions. A bout that fits one of their sports —
//    the same time of the week, the same intensity, a similar length — is
//    named after it ("Tennis", Tuesdays at six), which no generic rule can.
//
// When neither layer is sure, the answer is [kUnknownSport]: a bout the user
// names is better than one we named wrong. Sequence smoothing for walks and
// runs (a Viterbi pass over per-minute gait, after the Oxford biobank
// pipeline's random-forest + HMM design) lives in movement_bouts.dart.
//
// Pure and isolate-safe: plain lists in, plain values out.

import 'dart:math' as math;

/// The label for a bout we could not type.
const String kUnknownSport = 'detected';

/// Mean per-second turn of the gravity vector under which the wrist counts
/// as still: the analytics detector's own motion-confirmation line.
const double kStillWrist = 0.15;

/// A swing in heart rate this large (bpm, peak to trough on 30-second means)
/// is one set-and-rest.
const double kSwingBpm = 10;

/// What a bout looked like, from the 1 Hz bundle.
class BoutFeatures {
  const BoutFeatures({
    required this.startSec,
    required this.endSec,
    required this.hrrMean,
    required this.hrrPeak,
    required this.hrrSd,
    required this.swingsPer10Min,
    this.motionMean,
    this.motionCv,
    this.cadenceSpm,
    this.cadenceCover = 0,
  });

  final int startSec, endSec;

  /// Heart rate as a share of the reserve (0 = resting, 1 = max): the mean,
  /// the highest 30-second mean, and the spread of the 30-second means.
  final double hrrMean, hrrPeak, hrrSd;

  /// Heart-rate swings of [kSwingBpm] or more, per ten minutes.
  final double swingsPer10Min;

  /// Mean per-second gravity turn, and how much its 30-second means vary
  /// (coefficient of variation). Null without enough wrist samples.
  final double? motionMean, motionCv;

  /// Steps a minute over the minutes whose steps are known, and the share of
  /// the bout's minutes that is.
  final double? cadenceSpm;
  final double cadenceCover;

  double get minutes => (endSec - startSec) / 60;

  /// Cadence when enough of the bout carries one to speak for it.
  double? get cadence => cadenceCover >= .5 ? cadenceSpm : null;
}

/// Features for the bout [startSec, endSec) from the day's 1 Hz samples.
/// [hr] is bpm per second (0 = none) beside [tsSec]; [ax]/[ay]/[az] the
/// gravity vector, read only where [accelAt] says one was measured.
/// [stepsPerMin] is steps keyed by epoch minute (absent = unknown). Null
/// when the bout has too little heart rate to describe.
BoutFeatures? boutFeatures({
  required List<int> tsSec,
  required List<int> hr,
  required int startSec,
  required int endSec,
  required int restingBpm,
  required int maxBpm,
  List<double> ax = const [],
  List<double> ay = const [],
  List<double> az = const [],
  bool Function(int i)? accelAt,
  Map<int, int> stepsPerMin = const {},
}) {
  final reserve = (maxBpm - restingBpm).toDouble();
  if (reserve <= 0 || endSec <= startSec) return null;

  // 30-second means of heart rate and wrist movement.
  final hrBins = <int, List<int>>{};
  final moveBins = <int, List<double>>{};
  final moves = <double>[];
  final n = tsSec.length;
  for (var i = 0; i < n; i++) {
    final t = tsSec[i];
    if (t < startSec || t >= endSec) continue;
    final bin = (t - startSec) ~/ 30;
    if (i < hr.length && hr[i] > 0) (hrBins[bin] ??= []).add(hr[i]);
    if (i == 0 || tsSec[i - 1] != t - 1) continue;
    if (accelAt != null && (!accelAt(i) || !accelAt(i - 1))) continue;
    if (i >= ax.length || i >= ay.length || i >= az.length) continue;
    final dx = ax[i] - ax[i - 1], dy = ay[i] - ay[i - 1], dz = az[i] - az[i - 1];
    final v = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (!v.isFinite) continue;
    moves.add(v);
    (moveBins[bin] ??= []).add(v);
  }
  final hrMeans = <double>[
    for (final k in (hrBins.keys.toList()..sort()))
      if (hrBins[k]!.length >= 10)
        hrBins[k]!.reduce((a, b) => a + b) / hrBins[k]!.length,
  ];
  if (hrMeans.length < 6) return null; // under three minutes of heart rate
  final hrr = [for (final b in hrMeans) ((b - restingBpm) / reserve)];
  final hrrMean = hrr.reduce((a, b) => a + b) / hrr.length;
  final hrrPeak = hrr.reduce(math.max);
  final hrrSd = _sd(hrr);

  // Swings: turning points of the 30-second means with hysteresis.
  var swings = 0;
  double? lo, hi;
  var rising = true;
  for (final b in hrMeans) {
    lo = lo == null ? b : math.min(lo, b);
    hi = hi == null ? b : math.max(hi, b);
    if (rising && hi - b >= kSwingBpm) {
      swings++;
      rising = false;
      lo = b;
    } else if (!rising && b - lo >= kSwingBpm) {
      rising = true;
      hi = b;
    }
  }
  final minutes = (endSec - startSec) / 60;

  double? motionMean, motionCv;
  if (moves.length >= 120) {
    motionMean = moves.reduce((a, b) => a + b) / moves.length;
    final binMeans = [
      for (final v in moveBins.values)
        if (v.length >= 10) v.reduce((a, b) => a + b) / v.length,
    ];
    if (binMeans.length >= 4 && motionMean > 0) {
      motionCv = _sd(binMeans) / motionMean;
    }
  }

  // Cadence over the minutes whose steps are known.
  var known = 0, steps = 0;
  final m0 = startSec ~/ 60, m1 = (endSec - 1) ~/ 60;
  for (var m = m0; m <= m1; m++) {
    final s = stepsPerMin[m];
    if (s == null) continue;
    known++;
    steps += s;
  }
  final total = m1 - m0 + 1;

  return BoutFeatures(
    startSec: startSec,
    endSec: endSec,
    hrrMean: hrrMean,
    hrrPeak: hrrPeak,
    hrrSd: hrrSd,
    swingsPer10Min: minutes <= 0 ? 0 : swings / minutes * 10,
    motionMean: motionMean,
    motionCv: motionCv,
    cadenceSpm: known == 0 ? null : steps / known,
    cadenceCover: total <= 0 ? 0 : known / total,
  );
}

double _sd(List<double> xs) {
  if (xs.length < 2) return 0;
  final m = xs.reduce((a, b) => a + b) / xs.length;
  var s = 0.0;
  for (final x in xs) {
    s += (x - m) * (x - m);
  }
  return math.sqrt(s / (xs.length - 1));
}

/// The generic reading of [f], or [kUnknownSport].
String genericSport(BoutFeatures f) {
  final cad = f.cadence;
  if (cad != null) {
    if (cad >= 140) return 'running';
    // A jog's cadence can sit in a brisk walk's range; the heart decides.
    if (cad >= 100) return f.hrrMean >= .5 ? 'running' : 'walking';
    if (cad >= 60) return 'walking';
  }
  final m = f.motionMean;
  if (m == null) return kUnknownSport;
  // Steps were counted and there were next to none: not on foot.
  final offFoot = cad != null && cad < 30;
  final noSteps = cad == null || offFoot;
  final cv = f.motionCv ?? 0;
  if (noSteps && f.swingsPer10Min >= 1.5 && cv >= .5) {
    return f.hrrMean >= .55 ? 'hiit' : 'weight_training';
  }
  if (noSteps && m < kStillWrist && f.hrrSd < .1 && f.minutes >= 15) {
    return 'cycling';
  }
  return kUnknownSport;
}

/// One kept session, as the classifier needs it.
class KeptSession {
  const KeptSession(
    this.sport,
    this.startSec,
    this.endSec, {
    this.hrrPeak,
    this.cadenceSpm,
  });
  final String sport;
  final int startSec, endSec;

  /// The session's highest heart rate as a share of the reserve, when known.
  final double? hrrPeak;
  final double? cadenceSpm;

  double get minutes => (endSec - startSec) / 60;
}

/// A sport key, the form sessions store: 'Trail Run' → 'trail_run'.
String sportKey(String sport) => sport.toLowerCase().replaceAll(' ', '_');

/// The person's own sport for [f], when one of their kept sports fits it
/// well enough by time of week, intensity, length and cadence; else null.
/// A sport needs two kept sessions before it is ever suggested.
String? personalSport(BoutFeatures f, Iterable<KeptSession> kept) {
  final by = <String, List<KeptSession>>{};
  for (final s in kept) {
    if (s.sport.isEmpty || s.endSec <= s.startSec) continue;
    if (sportKey(s.sport) == kUnknownSport) continue;
    by.putIfAbsent(sportKey(s.sport), () => []).add(s);
  }
  final start = DateTime.fromMillisecondsSinceEpoch(f.startSec * 1000);
  final at = start.hour * 60 + start.minute;
  final weekend = start.weekday >= DateTime.saturday;
  String? best;
  var bestScore = 0.0;
  for (final e in by.entries) {
    final list = e.value;
    if (list.length < 2) continue;
    // Time: the share of their sessions within 90 minutes of this start on
    // the same kind of day, with a little weight for the same weekday.
    var near = 0.0;
    for (final s in list) {
      final d = DateTime.fromMillisecondsSinceEpoch(s.startSec * 1000);
      if ((d.weekday >= DateTime.saturday) != weekend) continue;
      if (_gap(d.hour * 60 + d.minute, at) > 90) continue;
      near += d.weekday == start.weekday ? 1 : .6;
    }
    final time = near / list.length;
    if (time < .3) continue;
    // Intensity: their usual peak against this bout's.
    final peaks = [for (final s in list) ?s.hrrPeak]..sort();
    final intensity = peaks.isEmpty
        ? .7
        : 1 - ((f.hrrPeak - peaks[peaks.length ~/ 2]).abs() / .25).clamp(0, 1);
    // Length: within a factor of two of their median.
    final mins = [for (final s in list) s.minutes]..sort();
    final med = mins[mins.length ~/ 2];
    final ratio = med <= 0 ? 0 : math.min(f.minutes, med) / math.max(f.minutes, med);
    final length = ratio >= .5 ? 1.0 : ratio * 2;
    // Cadence, when both carry one.
    final cads = [for (final s in list) ?s.cadenceSpm]..sort();
    final fc = f.cadence;
    final cadence = cads.isEmpty || fc == null
        ? 1.0
        : 1 - ((fc - cads[cads.length ~/ 2]).abs() / 30).clamp(0, 1);
    final score = time * intensity * length * cadence;
    if (score > bestScore) {
      bestScore = score;
      best = e.key;
    }
  }
  return bestScore >= .45 ? best : null;
}

/// The name for a detected bout: the person's own sport when one fits,
/// else the generic reading. A bout the steps show was on foot is renamed
/// only after a sport whose kept sessions carry a cadence too (hiking, trail
/// running), never after one that was never measured stepping.
String classifyBout(BoutFeatures f, Iterable<KeptSession> kept) {
  final generic = genericSport(f);
  final own = personalSport(f, kept);
  if (own == null) return generic;
  if (generic == 'running' || generic == 'walking') {
    final stepped = kept.any(
        (s) => sportKey(s.sport) == own && s.cadenceSpm != null);
    return stepped ? own : generic;
  }
  return own;
}

/// Circular minute-of-day distance, so 23:50 and 00:10 are 20 min apart.
int _gap(int a, int b) {
  final d = (a - b).abs() % 1440;
  return math.min(d, 1440 - d);
}
