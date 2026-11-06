// movement_bouts.dart — walks and runs the heart-rate detector cannot see,
// and what the user has taught us about their own movement.
//
// WHY A SECOND PASS. `autoDetectWorkouts` (analytics) proposes a bout off an
// elevated %HRR. A brisk walk sits well under its floor, so a 40-minute walk
// to work never surfaced. A walk is plainly visible in the band's own step
// counter, though: a sustained cadence of 60–135 steps a minute is walking,
// above that is running. This reads that counter minute by minute.
//
// Gen4 has no counter (`stepCount` is -1 every second). No cadence means no
// claim: the pass returns nothing rather than guessing a walk from the 1 Hz
// gravity vector, which arm work out-accelerates (see derivation_engine's
// notes on stirring vs walking ENMO).
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

/// Cadence (steps a minute) that counts as walking, and where running starts.
const int kWalkMinSpm = 60;
const int kRunMinSpm = 140;

/// A bout must hold up this long (minutes)…
const int kMovementMinMinutes = 10;

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

/// Walks and runs in one day of 1 Hz samples, outside [excluded] spans
/// (`[startSec, endSec]`, already-logged sessions and HR-detected bouts).
List<MovementBout> detectMovementBouts({
  required List<int> tsSec,
  required List<int> stepCount,
  List<List<int>> excluded = const [],
}) {
  final perMin = stepsPerMinute(tsSec, stepCount);
  if (perMin.isEmpty) return const [];
  final mins = perMin.keys.toList()..sort();
  bool blocked(int m) =>
      excluded.any((s) => s.length >= 2 && m * 60 < s[1] && (m + 1) * 60 > s[0]);

  final out = <MovementBout>[];
  int? start, lastActive;
  var steps = 0;
  void close() {
    if (start != null && lastActive != null) {
      final n = lastActive! - start! + 1;
      if (n >= kMovementMinMinutes) {
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
  const HabitSession(this.sport, this.startSec, this.endSec, {this.cadenceSpm});
  final String sport;
  final int startSec, endSec;
  final double? cadenceSpm;
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
