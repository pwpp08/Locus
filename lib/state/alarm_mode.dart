// ALARM MODES — what an alarm waits for before it wakes you.
//
//   exact       Wake at the time set, whatever the night was.
//   sleepGoal   Wake once the time in bed that covers tonight's sleep need has
//               passed since you fell asleep, but no earlier than a window
//               before the set time and never later than it.
//   inTheGreen  The same, with a margin on top for the restorative sleep that
//               recovery is built from.
//
// The band's own alarm is always armed at the set time and stays the
// fallback. A goal mode only ever adds an EARLY buzz inside its window, the
// way Smart Wake does (see `smart_wake.dart`): nothing here moves or clears the
// armed alarm, so a missing sleep need, a missed onset or a failed read all
// end in the set time, which is what the user asked for in the first place.
//
// The need is the planner's: tonight's time in bed, from `sleep_coach`
// (`SleepPlan.inBedMin`). A night with no need on record has no goal, and the
// alarm is exact. The green margin is a fixed rule of thumb, not a recovery
// forecast: Locus cannot know tomorrow's recovery before it happens.

/// How an alarm decides when to wake you.
enum AlarmMode {
  exact,
  sleepGoal,
  inTheGreen;

  String get title => switch (this) {
        exact => 'EXACT TIME',
        sleepGoal => 'SLEEP GOAL',
        inTheGreen => 'IN THE GREEN',
      };

  String get blurb => switch (this) {
        exact => 'Wake up at a specific time.',
        sleepGoal => 'Balance sleep need with performance',
        inTheGreen => 'Optimize recovery',
      };

  static AlarmMode fromName(Object? name) => AlarmMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => AlarmMode.exact,
      );
}

/// How long before the set time a goal alarm may wake you early.
const int kGoalWindowMin = 60;

/// What In the green adds to the sleep goal.
const int kGreenMarginMin = 30;

/// The time in bed [mode] waits for, in minutes: null for an exact alarm, and
/// for a night with no sleep need on record.
int? goalInBedMin(AlarmMode mode, int? inBedMin) {
  if (mode == AlarmMode.exact || inBedMin == null || inBedMin <= 0) return null;
  return inBedMin + (mode == AlarmMode.inTheGreen ? kGreenMarginMin : 0);
}

/// When the alarm should wake you, given when you fell asleep: onset plus the
/// goal, held inside `[deadline - window, deadline]`. The deadline whenever
/// there is no onset or no goal.
DateTime goalWakeAt({
  required AlarmMode mode,
  required DateTime deadline,
  required DateTime? onset,
  required int? inBedMin,
  int windowMin = kGoalWindowMin,
}) {
  final goal = goalInBedMin(mode, inBedMin);
  if (goal == null || onset == null) return deadline;
  final reached = onset.add(Duration(minutes: goal));
  final earliest = deadline.subtract(Duration(minutes: windowMin));
  if (reached.isAfter(deadline)) return deadline;
  return reached.isBefore(earliest) ? earliest : reached;
}

/// Whether the early buzz is due: inside the window and the goal's moment has
/// come. False for an exact alarm, whose only buzz is the band's own.
bool goalBuzzDue({
  required AlarmMode mode,
  required DateTime deadline,
  required DateTime now,
  required DateTime? onset,
  required int? inBedMin,
  int windowMin = kGoalWindowMin,
}) {
  if (goalInBedMin(mode, inBedMin) == null || onset == null) return false;
  final start = deadline.subtract(Duration(minutes: windowMin));
  if (now.isBefore(start) || !now.isBefore(deadline)) return false;
  return !now.isBefore(goalWakeAt(
      mode: mode,
      deadline: deadline,
      onset: onset,
      inBedMin: inBedMin,
      windowMin: windowMin));
}

/// Tonight's time in bed from the cross-day rollup (`getInsights()`): the
/// planner's own figure, wake less bedtime. Null with no sleep coach yet.
int? inBedMinFromInsights(Map<String, dynamic>? insights) {
  final coach = insights?['sleep_coach'];
  if (coach is! Map) return null;
  num? at(String k, String f) {
    final env = coach[k];
    final v = env is Map ? env['value'] : null;
    final x = v is Map ? v[f] : null;
    return x is num ? x : null;
  }

  final bed = at('bedtime', 'bedtime_min_of_day');
  final wake = at('wake', 'wake_min_of_day');
  return bed == null || wake == null ? null : ((wake - bed) % 1440).round();
}

/// One second of the night, as the onset estimate reads it.
typedef NightSample = ({int t, double hr, double motion});

/// When the night's sleep began, from its 1 Hz heart rate and movement: the
/// start of the first stretch of [stillMin] minutes where every minute's
/// heart rate sits within [bandBpm] of the quietest fifth of the span and the
/// wrist is still. Null when there is no such stretch (still up, or too
/// little data), which leaves a goal alarm exact.
///
/// ponytail: one pass over minute medians, no staging. Ceiling: a long, quiet
/// evening on the sofa reads as sleep. Upgrade path: take the onset from the
/// live cardio stager once it has a streaming feed.
DateTime? estimateSleepOnset(List<NightSample> samples,
    {int stillMin = 20, double bandBpm = 6, double stillG = .05}) {
  if (samples.length < stillMin * 60) return null;
  final byMinute = <int, List<NightSample>>{};
  for (final s in samples) {
    byMinute.putIfAbsent(s.t ~/ 60, () => []).add(s);
  }
  final minutes = byMinute.keys.toList()..sort();
  if (minutes.length < stillMin) return null;
  double med(List<double> xs) {
    final v = [...xs]..sort();
    return v[v.length ~/ 2];
  }

  final hrOf = {
    for (final m in minutes) m: med([for (final s in byMinute[m]!) s.hr])
  };
  final moveOf = {
    for (final m in minutes)
      m: byMinute[m]!.fold<double>(0, (a, s) => a + s.motion) / byMinute[m]!.length
  };
  final sorted = [...hrOf.values]..sort();
  final quiet = sorted[(sorted.length * .2).floor()];
  var runStart = -1, run = 0;
  for (final m in minutes) {
    final calm = hrOf[m]! <= quiet + bandBpm && moveOf[m]! < stillG;
    final contiguous = run > 0 && m == minutes[minutes.indexOf(m) - 1] + 1;
    if (!calm || (run > 0 && !contiguous)) {
      run = 0;
      runStart = -1;
      if (!calm) continue;
    }
    if (run == 0) runStart = m;
    run++;
    if (run >= stillMin) {
      return DateTime.fromMillisecondsSinceEpoch(runStart * 60 * 1000);
    }
  }
  return null;
}
