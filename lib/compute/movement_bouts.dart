// movement_bouts.dart — walks and runs the heart-rate detector cannot see,
// and what the user has taught us about their own movement.
//
// WHY A SECOND PASS. `autoDetectWorkouts` (analytics) proposes a bout off an
// elevated %HRR. A brisk walk sits well under its floor, so a 40-minute walk
// to work never surfaced. A walk is plainly visible in the band's own step
// counter, though: a sustained cadence of 60–135 steps a minute is walking,
// above that is running. This reads that counter minute by minute.
//
// Gen4 has no counter (`stepCount` is -1 every second). Its day is read from
// the resolved step spans instead (`live_coverage`: the phone's 5-minute
// slices and the band's live runs), but only short ones: an hour's count
// spread evenly over the hour would invent an hour-long walk. No cadence
// means no claim: the pass never guesses a walk from the 1 Hz gravity
// vector, which arm work out-accelerates (see derivation_engine's notes on
// stirring vs walking ENMO).
//
// WHAT IT LEARNS. [ActivityHabits] is built from the sessions the user kept.
// For each sport it holds when in the week they do it and, for sports with a
// measured cadence, how fast they step. A new bout is named after the kept
// sport that fits it best (a 100 spm bout on Saturday morning, when they
// always log "Hiking", is proposed as Hiking), and the card says when they
// usually do it. It is a few counts and averages, not a trained model:
// ponytail: nearest-mean on cadence × hour-of-week prior; upgrade to a real
// classifier once sessions carry more than cadence (pace, GPS, elevation).
//
// Pure and isolate-safe: plain lists in, plain values out.

import 'dart:math' as math;

import 'step_cadence.dart' show cadenceSpmForMinutes;

/// Cadence (steps a minute) that counts as walking, and where running starts.
const int kWalkMinSpm = 60;
const int kRunMinSpm = 140;

/// A bout must hold up this long (minutes), measured on its refined edges…
const int kMovementMinMinutes = 15;

/// …and may pause this long (minutes) without ending: a crossing, a door.
const int kMovementMaxGapMinutes = 2;

/// One detected walk or run.
class MovementBout {
  const MovementBout({
    required this.startSec,
    required this.endSec,
    required this.steps,
    required this.sport,
  });

  final int startSec, endSec, steps;

  /// 'walking' or 'running' (a session type key) from cadence alone;
  /// [ActivityHabits.name] may rename it after one of the user's own sports.
  final String sport;

  int get minutes => ((endSec - startSec) / 60).round();
  double get cadenceSpm => minutes == 0 ? 0 : steps / minutes;
}

/// Per-minute steps from the cumulative counter (u16, wraps at 65536; -1 =
/// the record carried none). Keyed by epoch minute. A minute with fewer than
/// two counter readings is left out: unmeasured, not zero.
Map<int, int> stepsPerMinute(List<int> tsSec, List<int> stepCount) {
  final first = <int, int>{}, last = <int, int>{};
  final total = <int, int>{};
  int? prevMin, prevCount;
  for (var i = 0; i < tsSec.length && i < stepCount.length; i++) {
    final c = stepCount[i];
    if (c < 0) continue;
    final m = tsSec[i] ~/ 60;
    first.putIfAbsent(m, () => c);
    if (prevMin == m && prevCount != null) {
      var d = c - prevCount;
      if (d < 0) d += 65536; // the counter wrapped
      // A jump of thousands inside one second is a counter reset, not steps.
      if (d < 50) total[m] = (total[m] ?? 0) + d;
    }
    last[m] = c;
    prevMin = m;
    prevCount = c;
  }
  return {
    for (final m in first.keys)
      if (first[m] != last[m] || total.containsKey(m)) m: total[m] ?? 0,
  };
}

/// The longest step span ([stepsPerMinuteFromSpans]) whose count can be
/// placed minute by minute: the phone's 5-minute slices pass, its old hourly
/// rows do not.
// ponytail: a band live run longer than this is skipped too (a missed walk,
// never an invented one); carry the source through if that ever matters.
const int kMovementMaxSpanSec = 10 * 60;

/// Per-minute steps from resolved step spans `[startSec, endSec, steps]`,
/// each spread evenly over its own length. Spans longer than
/// [kMovementMaxSpanSec] are left out, and so is every minute none covers.
Map<int, int> stepsPerMinuteFromSpans(List<List<int>> spans) {
  final short = [
    for (final s in spans)
      if (s.length >= 3 && s[1] > s[0] && s[1] - s[0] <= kMovementMaxSpanSec) s,
  ];
  final keys = {
    for (final s in short)
      for (var k = s[0] ~/ 60; k * 60 < s[1]; k++) k,
  }.toList()
    ..sort();
  final v = cadenceSpmForMinutes(keys, short);
  return {
    for (var i = 0; i < keys.length; i++)
      if (v[i] case final n?) keys[i]: n.round(),
  };
}

/// Walks and runs in one day of 1 Hz samples, outside [excluded] spans
/// (`[startSec, endSec]`, already-logged sessions and HR-detected bouts).
/// Without the band's own counter, the day's step [spans] are read instead.
///
/// The steps find the bout; its edges are then put on the second
/// ([refineBoutEdges]): from the band's counter where it has one, else from
/// the band's own wrist movement ([ax], [ay], [az], 1 Hz beside [tsSec])
/// inside the first and last slice. A bout must last [kMovementMinMinutes]
/// on those edges.
List<MovementBout> detectMovementBouts({
  required List<int> tsSec,
  required List<int> stepCount,
  List<List<int>> spans = const [],
  List<List<int>> excluded = const [],
  List<double> ax = const [],
  List<double> ay = const [],
  List<double> az = const [],
}) {
  final counter = stepsPerMinute(tsSec, stepCount);
  final perMin =
      counter.isNotEmpty ? counter : stepsPerMinuteFromSpans(spans);
  if (perMin.isEmpty) return const [];
  return [
    for (final b in _coarseBouts(perMin, excluded))
      if (refineBoutEdges(b,
              tsSec: tsSec,
              stepCount: counter.isNotEmpty ? stepCount : const [],
              ax: ax,
              ay: ay,
              az: az,
              excluded: excluded)
          case final r when r.endSec - r.startSec >= kMovementMinMinutes * 60)
        ...splitByGait(r, perMin),
  ];
}

/// The shortest stretch of one gait (minutes) that becomes a bout of its
/// own when a walk turns into a run, or back.
const int kGaitMinMinutes = 10;

/// [b] as one bout per sustained gait. Each minute's cadence is read as
/// walking or running, and the sequence is smoothed with a two-state hidden
/// Markov model (Viterbi): changing gait is rare, so a single fast minute in
/// a walk, or a walk break in a run, does not flip the label. A stretch of
/// one gait at least [kGaitMinMinutes] long, with another on either side of
/// it, is split off; otherwise the bout keeps one label, its majority.
List<MovementBout> splitByGait(MovementBout b, Map<int, int> perMin) {
  final m0 = b.startSec ~/ 60, m1 = (b.endSec - 1) ~/ 60;
  final minutes = [
    for (var m = m0; m <= m1; m++)
      if (perMin[m] case final s? when s >= kWalkMinSpm) m,
  ];
  if (minutes.length < 2) return [b];
  final run = gaitPath([for (final m in minutes) perMin[m]!.toDouble()]);
  // Runs of one state, in minutes.
  final segs = <(int from, int to, bool run)>[];
  var from = 0;
  for (var i = 1; i <= run.length; i++) {
    if (i == run.length || run[i] != run[from]) {
      segs.add((from, i - 1, run[from]));
      from = i;
    }
  }
  // Fold a short stretch into the one before it (or after, at the start).
  final merged = <(int, int, bool)>[];
  for (final s in segs) {
    final len = minutes[s.$2] - minutes[s.$1] + 1;
    if (merged.isNotEmpty && len < kGaitMinMinutes) {
      final last = merged.removeLast();
      merged.add((last.$1, s.$2, last.$3));
    } else if (merged.isNotEmpty && merged.last.$3 == s.$3) {
      final last = merged.removeLast();
      merged.add((last.$1, s.$2, s.$3));
    } else {
      merged.add(s);
    }
  }
  if (merged.length > 1) {
    final firstLen = minutes[merged.first.$2] - minutes[merged.first.$1] + 1;
    if (firstLen < kGaitMinMinutes) {
      final a = merged.removeAt(0), c = merged.removeAt(0);
      merged.insert(0, (a.$1, c.$2, c.$3));
    }
  }
  String label(int i0, int i1) {
    var runs = 0;
    for (var i = i0; i <= i1; i++) {
      if (run[i]) runs++;
    }
    return runs * 2 > i1 - i0 + 1 ? 'running' : 'walking';
  }

  if (merged.length == 1) {
    return [
      MovementBout(
          startSec: b.startSec,
          endSec: b.endSec,
          steps: b.steps,
          sport: label(0, run.length - 1)),
    ];
  }
  final out = <MovementBout>[];
  for (var k = 0; k < merged.length; k++) {
    final (i0, i1, _) = merged[k];
    final start = k == 0 ? b.startSec : minutes[i0] * 60;
    final end = k == merged.length - 1 ? b.endSec : (minutes[i1] + 1) * 60;
    var steps = 0;
    for (var m = start ~/ 60; m * 60 < end; m++) {
      steps += perMin[m] ?? 0;
    }
    out.add(MovementBout(
        startSec: start, endSec: end, steps: steps, sport: label(i0, i1)));
  }
  return out;
}

/// The most likely walk (false) / run (true) sequence for per-minute
/// cadences: a two-state Viterbi with Gaussian emissions (walking around
/// 110 spm, running around 160) and a sticky transition.
List<bool> gaitPath(List<double> spm) {
  const stay = .95;
  final logStay = math.log(stay), logMove = math.log(1 - stay);
  double emit(double x, bool run) {
    final mean = run ? 160.0 : 110.0, sd = run ? 15.0 : 20.0;
    final z = (x - mean) / sd;
    return -0.5 * z * z - math.log(sd);
  }

  final n = spm.length;
  final score = List.generate(n, (_) => [0.0, 0.0]);
  final back = List.generate(n, (_) => [0, 0]);
  score[0] = [emit(spm[0], false), emit(spm[0], true)];
  for (var i = 1; i < n; i++) {
    for (var s = 0; s < 2; s++) {
      final fromSame = score[i - 1][s] + logStay;
      final fromOther = score[i - 1][1 - s] + logMove;
      back[i][s] = fromSame >= fromOther ? s : 1 - s;
      score[i][s] = math.max(fromSame, fromOther) + emit(spm[i], s == 1);
    }
  }
  final path = List<bool>.filled(n, false);
  var s = score[n - 1][1] > score[n - 1][0] ? 1 : 0;
  for (var i = n - 1; i >= 0; i--) {
    path[i] = s == 1;
    s = back[i][s];
  }
  return path;
}

/// Seconds either side of a coarse edge searched for the real one: a slice.
const int _edgeSearchSec = 5 * 60;

/// The window movement must hold through to count as walking (seconds), and
/// the share of its seconds that must be moving.
const int _edgeHoldSec = 60;
const double _edgeHoldShare = .8;

/// [b] with its start and end put on the second, or [b] unchanged when the
/// samples cannot say.
///
/// With the band's counter ([stepCount] non-empty): the first second the
/// counter moves in the first minute, the last in the last minute.
///
/// Without it, the band's 1 Hz gravity vector: each second's movement is
/// how far the vector turned since the last, smoothed over 15 s. Inside the
/// bout (the steps proved it) that sets the walking level; the start is the
/// first second within a slice of the coarse start from which movement holds
/// above 40 % of it for a minute, the end the last such second before the
/// coarse end. Movement never decides THAT it was a walk, only where the walk
/// the steps found begins and ends.
MovementBout refineBoutEdges(
  MovementBout b, {
  required List<int> tsSec,
  List<int> stepCount = const [],
  List<double> ax = const [],
  List<double> ay = const [],
  List<double> az = const [],
  List<List<int>> excluded = const [],
}) {
  bool free(int t) =>
      !excluded.any((s) => s.length >= 2 && t >= s[0] && t < s[1]);
  MovementBout at(int start, int end) => MovementBout(
      startSec: free(start) ? start : b.startSec,
      endSec: free(end - 1) ? end : b.endSec,
      steps: b.steps,
      sport: b.sport);

  if (stepCount.isNotEmpty) {
    int? first, last;
    for (var i = 1; i < tsSec.length && i < stepCount.length; i++) {
      final t = tsSec[i];
      if (t < b.startSec || t >= b.endSec) continue;
      final c0 = stepCount[i - 1], c1 = stepCount[i];
      if (c0 < 0 || c1 < 0 || tsSec[i - 1] != t - 1) continue;
      var d = c1 - c0;
      if (d < 0) d += 65536;
      if (d <= 0 || d >= 50) continue;
      first ??= t;
      last = t;
    }
    return first == null ? b : at(first, last! + 1);
  }

  final n = math.min(tsSec.length,
      math.min(ax.length, math.min(ay.length, az.length)));
  if (n < 2) return b;
  final lo = b.startSec - _edgeSearchSec - _edgeHoldSec;
  final hi = b.endSec + _edgeSearchSec + _edgeHoldSec;
  // Raw movement per second, keyed by epoch second.
  final raw = <int, double>{};
  for (var i = 1; i < n; i++) {
    final t = tsSec[i];
    if (t < lo || t > hi || tsSec[i - 1] != t - 1) continue;
    final dx = ax[i] - ax[i - 1], dy = ay[i] - ay[i - 1], dz = az[i] - az[i - 1];
    final v = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (v.isFinite) raw[t] = v;
  }
  // Smoothed over 15 s, centred.
  final smooth = <int, double>{};
  for (final t in raw.keys) {
    var sum = 0.0, k = 0;
    for (var u = t - 7; u <= t + 7; u++) {
      final v = raw[u];
      if (v != null) {
        sum += v;
        k++;
      }
    }
    if (k >= 8) smooth[t] = sum / k;
  }
  final inside = [
    for (final e in smooth.entries)
      if (e.key >= b.startSec + _edgeSearchSec &&
          e.key < b.endSec - _edgeSearchSec)
        e.value,
  ]..sort();
  if (inside.length < 120) return b;
  final walking = inside[inside.length ~/ 2];
  if (walking <= 0) return b;
  final line = walking * .4;
  bool holds(int from) {
    var moving = 0;
    for (var u = from; u < from + _edgeHoldSec; u++) {
      if ((smooth[u] ?? 0) >= line) moving++;
    }
    return moving >= _edgeHoldSec * _edgeHoldShare;
  }

  int? start, end;
  for (var t = b.startSec - _edgeSearchSec;
      t <= b.startSec + _edgeSearchSec;
      t++) {
    if ((smooth[t] ?? 0) >= line && holds(t)) {
      start = t;
      break;
    }
  }
  for (var t = b.endSec + _edgeSearchSec;
      t >= b.endSec - _edgeSearchSec;
      t--) {
    if ((smooth[t - 1] ?? 0) >= line && holds(t - _edgeHoldSec)) {
      end = t;
      break;
    }
  }
  if (start == null || end == null || end <= start) return b;
  return at(start, end);
}

/// Minute-resolution bouts off per-minute steps, before their edges are
/// refined. Kept a slice short of [kMovementMinMinutes]: a walk that starts
/// late in one slice and ends early in another is longer than its full
/// slices, and the real length is only known once the edges are.
List<MovementBout> _coarseBouts(
    Map<int, int> perMin, List<List<int>> excluded) {
  final mins = perMin.keys.toList()..sort();
  bool blocked(int m) =>
      excluded.any((s) => s.length >= 2 && m * 60 < s[1] && (m + 1) * 60 > s[0]);

  final out = <MovementBout>[];
  int? start, lastActive;
  var steps = 0;
  void close() {
    if (start != null && lastActive != null) {
      final n = lastActive! - start! + 1;
      if (n >= kMovementMinMinutes - _edgeSearchSec ~/ 60) {
        final spm = steps / n;
        out.add(MovementBout(
          startSec: start! * 60,
          endSec: (lastActive! + 1) * 60,
          steps: steps,
          sport: spm >= kRunMinSpm ? 'running' : 'walking',
        ));
      }
    }
    start = null;
    lastActive = null;
    steps = 0;
  }

  for (final m in mins) {
    final spm = perMin[m]!;
    final moving = spm >= kWalkMinSpm && !blocked(m);
    if (lastActive != null && m - lastActive! > kMovementMaxGapMinutes + 1) {
      close();
    }
    if (!moving) continue;
    start ??= m;
    // Steps in a short pause still count: they were taken inside the bout.
    steps += spm;
    lastActive = m;
  }
  close();
  return out;
}

/// One kept session, as the habits need it.
class HabitSession {
  const HabitSession(this.sport, this.startSec, this.endSec,
      {this.cadenceSpm, this.maxHr});
  final String sport;
  final int startSec, endSec;
  final double? cadenceSpm;

  /// The session's highest heart rate, when it was scored.
  final int? maxHr;
}

/// When and how the user moves, from the sessions they kept.
class ActivityHabits {
  ActivityHabits._(this._bySport);

  final Map<String, List<HabitSession>> _bySport;

  factory ActivityHabits.fromSessions(Iterable<HabitSession> sessions) {
    final by = <String, List<HabitSession>>{};
    for (final s in sessions) {
      if (s.sport.isEmpty || s.endSec <= s.startSec) continue;
      by.putIfAbsent(_key(s.sport), () => []).add(s);
    }
    return ActivityHabits._(by);
  }

  /// Type keys, the form sessions store: 'Trail Run' → 'trail_run'.
  static String _key(String sport) => sport.toLowerCase().replaceAll(' ', '_');

  /// The sports the user has kept at least once.
  Iterable<String> get sports => _bySport.keys;

  static int _minuteOfDay(int sec) {
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    return d.hour * 60 + d.minute;
  }

  /// Circular minute-of-day distance, so 23:50 and 00:10 are 20 min apart.
  static int _gap(int a, int b) {
    final d = (a - b).abs() % 1440;
    return math.min(d, 1440 - d);
  }

  /// The name a bout should carry: the kept movement sport whose cadence and
  /// time of day fit it, else the detector's own Walking / Running. Needs two
  /// kept sessions of that sport, so one odd log does not rename every walk.
  String name(MovementBout b) {
    final at = _minuteOfDay(b.startSec);
    final weekend = DateTime.fromMillisecondsSinceEpoch(b.startSec * 1000)
            .weekday >=
        DateTime.saturday;
    String best = b.sport;
    var bestScore = 0.0;
    for (final e in _bySport.entries) {
      final withCadence =
          e.value.where((s) => s.cadenceSpm != null).toList();
      if (withCadence.length < 2) continue;
      final mean = withCadence.map((s) => s.cadenceSpm!).reduce((a, c) => a + c) /
          withCadence.length;
      // Cadence fit: 1 at the user's own mean, 0 by 30 spm off.
      final cad = 1 - ((b.cadenceSpm - mean).abs() / 30).clamp(0.0, 1.0);
      if (cad == 0) continue;
      // Time fit: the share of their sessions within 90 min of this start on
      // the same kind of day (weekday / weekend).
      final near = e.value.where((s) {
        final d = DateTime.fromMillisecondsSinceEpoch(s.startSec * 1000);
        return (d.weekday >= DateTime.saturday) == weekend &&
            _gap(_minuteOfDay(s.startSec), at) <= 90;
      }).length;
      final time = near / e.value.length;
      // The detector's own label keeps a head start: renaming needs evidence.
      final score = cad * (0.4 + 0.6 * time) * (e.key == b.sport ? 1.2 : 1.0);
      if (score > bestScore && score >= 0.5) {
        bestScore = score;
        best = e.key;
      }
    }
    return best;
  }

  /// "Usually weekdays around 7:40" — when [sport] is mostly done, from at
  /// least three kept sessions; null when there is no habit yet.
  String? usual(String sport) {
    final list = _bySport[_key(sport)];
    if (list == null || list.length < 3) return null;
    final mins = list.map((s) => _minuteOfDay(s.startSec)).toList();
    // The circular mean, so a habit straddling midnight averages right.
    var x = 0.0, y = 0.0;
    for (final m in mins) {
      final a = m / 1440 * 2 * math.pi;
      x += math.cos(a);
      y += math.sin(a);
    }
    var mean = (math.atan2(y, x) / (2 * math.pi) * 1440).round() % 1440;
    if (mean < 0) mean += 1440;
    // Only a habit if most sessions sit near that time.
    final close = mins.where((m) => _gap(m, mean) <= 90).length;
    if (close * 3 < list.length * 2) return null;
    final weekends = list
        .where((s) =>
            DateTime.fromMillisecondsSinceEpoch(s.startSec * 1000).weekday >=
            DateTime.saturday)
        .length;
    final days = weekends * 4 >= list.length * 3
        ? 'weekends '
        : weekends * 4 <= list.length
            ? 'weekdays '
            : '';
    // Round to five minutes: "7:40", not "7:43".
    final r = (mean / 5).round() * 5 % 1440;
    final hh = r ~/ 60, mm = (r % 60).toString().padLeft(2, '0');
    return 'Usually ${days}around $hh:$mm';
  }
}
