// activity_classifier.dart — what a detected bout most likely was.
//
// The heart-rate detector (analytics' `autoDetectWorkouts`) finds WHEN a
// workout happened and leaves WHAT it was to a seam that, by default, says
// "detected". This file fills that in from what the 1 Hz bundle actually
// carries:
//
// 1. Generic rules, from published practice. Cadence off the step counter
//    (the band's, or the phone's 5-minute slices) separates running from
//    walking, the same 60 / 140 spm lines the walk pass uses. Without steps,
//    the wrist separates the rest: still most of the time under a raised
//    heart rate is a handlebar (cycling); still about a third of the time,
//    busy between, is sets and rests (weight training, or HIIT when the
//    heart runs high). The lines were measured on logged rides and a logged
//    weights session. The 1 Hz gravity vector cannot see gait (Nyquist
//    0.5 Hz, under the 1.4–2.5 Hz of a step), so the wrist only ever reads
//    as an AMPLITUDE.
// 3. Edges. The detector cuts where heart rate crosses a fixed floor, which
//    starts a ride at the walk to the bike and ends it in the recovery tail;
//    [refineWorkoutEdges] moves each edge to where the effort began and
//    ended.
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

/// A second whose gravity vector turned less than this counts as a still
/// wrist.
const double kStillSecond = 0.1;

/// What a bout looked like, from the 1 Hz bundle.
class BoutFeatures {
  const BoutFeatures({
    required this.startSec,
    required this.endSec,
    required this.hrrMean,
    required this.hrrPeak,
    required this.hrrSd,
    this.motionMedian,
    this.stillShare,
    this.cadenceSpm,
    this.cadenceCover = 0,
  });

  final int startSec, endSec;

  /// Heart rate as a share of the reserve (0 = resting, 1 = max): the mean,
  /// the highest 30-second mean, and the spread of the 30-second means.
  final double hrrMean, hrrPeak, hrrSd;

  /// The wrist over the middle 80 % of the bout (the edges are the walk to
  /// the bike, the bag onto the bench): the median per-second turn of the
  /// gravity vector, and the share of seconds under [kStillSecond]. Null
  /// without two minutes of wrist samples.
  final double? motionMedian, stillShare;

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
  final trim = (endSec - startSec) ~/ 10;
  final midLo = startSec + trim, midHi = endSec - trim;

  final hrBins = <int, List<int>>{};
  final moves = <double>[];
  final n = tsSec.length;
  for (var i = 0; i < n; i++) {
    final t = tsSec[i];
    if (t < startSec || t >= endSec) continue;
    if (i < hr.length && hr[i] > 0) {
      (hrBins[(t - startSec) ~/ 30] ??= []).add(hr[i]);
    }
    if (t < midLo || t >= midHi) continue;
    if (i == 0 || tsSec[i - 1] != t - 1) continue;
    if (accelAt != null && (!accelAt(i) || !accelAt(i - 1))) continue;
    if (i >= ax.length || i >= ay.length || i >= az.length) continue;
    final dx = ax[i] - ax[i - 1], dy = ay[i] - ay[i - 1], dz = az[i] - az[i - 1];
    final v = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (v.isFinite) moves.add(v);
  }
  final hrMeans = <double>[
    for (final k in (hrBins.keys.toList()..sort()))
      if (hrBins[k]!.length >= 10)
        hrBins[k]!.reduce((a, b) => a + b) / hrBins[k]!.length,
  ];
  if (hrMeans.length < 6) return null; // under three minutes of heart rate
  final hrr = [for (final b in hrMeans) ((b - restingBpm) / reserve)];

  double? motionMedian, stillShare;
  if (moves.length >= 120) {
    moves.sort();
    motionMedian = moves[moves.length ~/ 2];
    stillShare = moves.where((v) => v < kStillSecond).length / moves.length;
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
    hrrMean: hrr.reduce((a, b) => a + b) / hrr.length,
    hrrPeak: hrr.reduce(math.max),
    hrrSd: _sd(hrr),
    motionMedian: motionMedian,
    stillShare: stillShare,
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
///
/// The wrist lines come from logged sessions: on rides the wrist was still
/// for 62-70 % of the seconds with a median turn near 0.06; through a weights
/// session it was still for 31 % with a median near 0.18 (stillness between
/// sets, movement through them). A wrist that never rests is a walk or a run
/// the steps did not see, which the wrist alone cannot tell from intervals,
/// so it stays unnamed.
String genericSport(BoutFeatures f) {
  final cad = f.cadence;
  if (cad != null) {
    if (cad >= 140) return 'running';
    // A jog's cadence can sit in a brisk walk's range; the heart decides.
    if (cad >= 100) return f.hrrMean >= .5 ? 'running' : 'walking';
    if (cad >= 60) return 'walking';
  }
  final still = f.stillShare, med = f.motionMedian;
  if (still == null || med == null) return kUnknownSport;
  // Steps were counted and there were next to none, or none were counted.
  if (cad != null && cad >= 30) return kUnknownSport;
  if (still >= .55 && med < kStillSecond && f.minutes >= 10) return 'cycling';
  if (still >= .15 && still <= .45 && med >= .12) {
    return f.hrrMean >= .65 ? 'hiit' : 'weight_training';
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

/// How far either way of a detector edge the real one is looked for.
const int kEdgeSearchSec = 8 * 60;

/// Where on the climb from the level before a bout to the level inside it
/// the bout starts: a steady effort (a ride, a run) rises sharply and starts
/// [kSteadyStartShare] of the way up, so a walk to the bike is left out; sets
/// and rests rise slowly and start lower, at [kIntervalStartShare]. The end
/// is the last moment the heart held [kEndShare] of the way above the level
/// after it, so the recovery tail is not counted. Fitted on logged rides and
/// a logged weights session, where the detector's own floor-crossing edges
/// were off by 1.9 minutes on average and these by half a minute.
const double kSteadyStartShare = .5;
const double kIntervalStartShare = .2;
const double kEndShare = .6;

/// The bout [startSec, endSec) with its edges put where the heart rate says
/// the effort began and ended, or the input unchanged where it cannot say
/// (no heart rate before or after it, or no clear rise). [interval] is a
/// sets-and-rests sport. An edge never moves into an [excluded] span.
(int, int) refineWorkoutEdges({
  required List<int> tsSec,
  required List<int> hr,
  required int startSec,
  required int endSec,
  bool interval = false,
  List<List<int>> excluded = const [],
}) {
  final at = <int, int>{};
  for (var i = 0; i < tsSec.length && i < hr.length; i++) {
    final t = tsSec[i];
    if (hr[i] > 0 &&
        t >= startSec - kEdgeSearchSec - 300 &&
        t < endSec + kEdgeSearchSec + 300) {
      at[t] = hr[i];
    }
  }
  double? median(int a, int b) {
    final v = [
      for (var t = a; t < b; t++) ?at[t]?.toDouble(),
    ];
    if (v.length < 60) return null;
    v.sort();
    return v[v.length ~/ 2];
  }

  // Heart rate smoothed over 31 s, centred.
  final smooth = <int, double>{};
  double? sm(int t) => smooth[t] ??= () {
        var sum = 0, k = 0;
        for (var u = t - 15; u <= t + 15; u++) {
          final v = at[u];
          if (v != null) {
            sum += v;
            k++;
          }
        }
        return k >= 15 ? sum / k : double.nan;
      }();
  bool above(int t, double line) {
    final v = sm(t);
    return v != null && !v.isNaN && v >= line;
  }

  bool free(int t) =>
      !excluded.any((s) => s.length >= 2 && t >= s[0] && t < s[1]);

  // Whether the heart stays above [line] from [from]: every ten seconds of
  // two minutes, or, [loose], 70 % of three (the start of sets and rests,
  // whose rests dip between the sets).
  bool holds(int from, double line, {bool loose = false}) {
    final len = loose ? 180 : 120;
    var up = 0, all = 0;
    for (var u = from; u < from + len; u += 10) {
      all++;
      if (above(u, line)) {
        up++;
      } else if (!loose) {
        return false;
      }
    }
    return up >= all * (loose ? .7 : 1);
  }

  final plateau = median(startSec, endSec);
  if (plateau == null) return (startSec, endSec);
  var start = startSec, end = endSec;

  final before =
      median(startSec - kEdgeSearchSec - 300, startSec - kEdgeSearchSec);
  if (before != null && plateau - before >= 10) {
    final line =
        before + (interval ? kIntervalStartShare : kSteadyStartShare) *
            (plateau - before);
    // Sets and rests climb slowly: their start only ever moves earlier than
    // the detector's floor crossing, never later.
    final last = interval ? startSec : startSec + kEdgeSearchSec;
    for (var t = startSec - kEdgeSearchSec; t < last; t++) {
      if (!above(t, line) || !holds(t, line, loose: interval)) continue;
      if (free(t)) start = t;
      break;
    }
  }

  final after = median(endSec + kEdgeSearchSec, endSec + kEdgeSearchSec + 300);
  if (after != null && plateau - after >= 10) {
    final line = after + kEndShare * (plateau - after);
    for (var t = endSec + kEdgeSearchSec; t > endSec - kEdgeSearchSec; t--) {
      if (!above(t, line) || !holds(t - 120, line)) continue;
      if (free(t - 1)) end = t;
      break;
    }
  }
  if (end - start < 5 * 60) return (startSec, endSec);
  return (start, end);
}

/// Sports whose heart rate climbs and falls with sets and rests.
const Set<String> kIntervalSports = {
  'weight_training', 'hiit', 'powerlifting', 'bodyweight', 'calisthenics',
  'kettlebell', 'crossfit', 'circuit_training', 'functional',
};
