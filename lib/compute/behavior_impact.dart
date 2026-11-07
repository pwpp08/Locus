// What a behavior's days did to the next morning's Recovery, read off the user's
// own series: the mean of the days they did it against the mean of the days they
// did not. An association in their own history, never a claim about cause, and
// nothing at all until both sides have enough days.

import 'dart:math' as math;

/// Days a side needs before its mean is compared.
const kBehaviorMinDays = 5;

/// A strain the day before counts as a hard day from here.
const kHardStrain = 14.0;

/// A bed or wake this far from the usual is still consistent.
const kConsistentWithinMin = 30.0;

/// The share of a day in the high stress zone that counts as a stressful one.
const kHighStressDayPct = 14.0;

/// A workout starting before this hour counts as an early one.
const kEarlyWorkoutHour = 10;

enum BehaviorKind {
  sleepPerformance,
  consistentBed,
  consistentWake,
  earlyWorkout,
  highStress,
  highStrain,
  journalTag,
}

/// One behavior against Recovery.
class BehaviorImpact {
  final BehaviorKind kind;
  final String title;

  /// Days with Recovery on each side.
  final int yes, no;

  /// Mean Recovery on each side. Null with too few days to compare.
  final double? meanYes, meanNo;
  const BehaviorImpact({
    required this.kind,
    required this.title,
    required this.yes,
    required this.no,
    this.meanYes,
    this.meanNo,
  });

  /// Points of Recovery between the two sides, or null while locked.
  double? get impact =>
      meanYes == null || meanNo == null ? null : meanYes! - meanNo!;

  bool get auto => kind != BehaviorKind.journalTag;
}

/// The middle value of [xs], or null with none.
double? medianOf(Iterable<double> xs) {
  final s = xs.toList()..sort();
  if (s.isEmpty) return null;
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Compares the [outcome] of the [yes] days with the [no] days. A day with no
/// outcome counts for neither side; a day on both sides is a caller's bug and
/// counts as yes.
BehaviorImpact impactOf(
  BehaviorKind kind,
  String title,
  Map<String, double> outcome, {
  required Iterable<String> yes,
  required Iterable<String> no,
}) {
  final yesSet = yes.toSet();
  final y = [for (final d in yesSet) ?outcome[d]];
  final n = [
    for (final d in no.toSet())
      if (!yesSet.contains(d)) ?outcome[d],
  ];
  double? mean(List<double> xs) =>
      xs.length < kBehaviorMinDays ? null : xs.reduce((a, b) => a + b) / xs.length;
  final enough = y.length >= kBehaviorMinDays && n.length >= kBehaviorMinDays;
  return BehaviorImpact(
    kind: kind,
    title: title,
    yes: y.length,
    no: n.length,
    meanYes: enough ? mean(y) : null,
    meanNo: enough ? mean(n) : null,
  );
}

/// Splits the [days] by whether [value] holds [test]. A day with no value is on
/// neither side: not measured is not the same as not done.
({List<String> yes, List<String> no}) splitDays(
  Iterable<String> days,
  double? Function(String day) value,
  bool Function(double v) test,
) {
  final yes = <String>[], no = <String>[];
  for (final d in days) {
    final v = value(d);
    if (v == null) continue;
    (test(v) ? yes : no).add(d);
  }
  return (yes: yes, no: no);
}

/// The behaviors the app can see for itself, strongest help first, then those
/// still locked.
///
/// [days] are the outcome days. Sleep Performance, bed and wake belong to the
/// night that ended on the day; strain, stress and a morning workout to the day
/// before it, which is what its Recovery can answer for.
List<BehaviorImpact> autoBehaviors({
  required List<String> days,
  required Map<String, double> recovery,
  required Map<String, double> sleepPerformance,
  required Map<String, double> bed,
  required Map<String, double> wake,
  required Map<String, double> strain,
  required Map<String, double> highStressPct,
  required Set<String> earlyWorkoutDays,
  required String Function(String day) dayBefore,
}) {
  final out = <BehaviorImpact>[];

  final recent = [for (final d in days) ?sleepPerformance[d]];
  final typical = medianOf(recent);
  if (typical != null) {
    final split = splitDays(days, (d) => sleepPerformance[d], (v) => v >= typical);
    out.add(impactOf(BehaviorKind.sleepPerformance,
        '${typical.round()}%+ Sleep Performance', recovery,
        yes: split.yes, no: split.no));
  }

  void consistent(BehaviorKind kind, String title, Map<String, double> m) {
    final usual = medianOf([for (final d in days) ?m[d]]);
    if (usual == null) return;
    final split = splitDays(days, (d) => m[d],
        (v) => (v - usual).abs() <= kConsistentWithinMin);
    out.add(impactOf(kind, title, recovery, yes: split.yes, no: split.no));
  }

  consistent(BehaviorKind.consistentBed, 'Consistent Bed Time', bed);
  consistent(BehaviorKind.consistentWake, 'Consistent Wake Time', wake);

  // Every day with an outcome is either a day after a morning workout or not;
  // no session on record is the same as none done.
  out.add(impactOf(BehaviorKind.earlyWorkout, 'Early Workout', recovery,
      yes: days.where((d) => earlyWorkoutDays.contains(dayBefore(d))),
      no: days.where((d) => !earlyWorkoutDays.contains(dayBefore(d)))));

  final stress = splitDays(days, (d) => highStressPct[dayBefore(d)],
      (v) => v >= kHighStressDayPct);
  if (stress.yes.isNotEmpty || stress.no.isNotEmpty) {
    out.add(impactOf(BehaviorKind.highStress,
        '${kHighStressDayPct.round()}%+ of the Day in High Stress Zone', recovery,
        yes: stress.yes, no: stress.no));
  }

  final hard =
      splitDays(days, (d) => strain[dayBefore(d)], (v) => v >= kHardStrain);
  out.add(impactOf(BehaviorKind.highStrain, '${kHardStrain.round()}+ Strain', recovery,
      yes: hard.yes, no: hard.no));
  return out;
}

/// Each journal tag against Recovery. [logged] is each logged day's tags. Its
/// outcome is [lagOf] days on: a day's behaviour lands on the next morning, a
/// note about the night already over on that same morning. An unlogged day is
/// on neither side.
List<BehaviorImpact> tagBehaviors({
  required Map<String, Set<String>> logged,
  required Map<String, double> recovery,
  required int Function(String tag) lagOf,
  required String Function(String day, int by) shift,
}) {
  final tags = {for (final t in logged.values) ...t};
  return [
    for (final tag in tags)
      impactOf(BehaviorKind.journalTag, _titleOf(tag), recovery,
          yes: [
            for (final e in logged.entries)
              if (e.value.contains(tag)) shift(e.key, lagOf(tag)),
          ],
          no: [
            for (final e in logged.entries)
              if (!e.value.contains(tag)) shift(e.key, lagOf(tag)),
          ]),
  ];
}

String _titleOf(String tag) => tag
    .split(RegExp(r'[\s_]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Sorted for the screen: what helps most at the top, what hurts most at the
/// foot. Locked behaviors are left out; ask [lockedOf] for those.
List<BehaviorImpact> rankedOf(Iterable<BehaviorImpact> all) {
  final open = [
    for (final b in all)
      if (b.impact != null) b,
  ]..sort((a, b) => b.impact!.compareTo(a.impact!));
  return open;
}

/// Those with too few days on a side, the ones closest to unlocking first.
List<BehaviorImpact> lockedOf(Iterable<BehaviorImpact> all) {
  final locked = [
    for (final b in all)
      if (b.impact == null) b,
  ]..sort((a, b) =>
      (math.min(b.yes, kBehaviorMinDays) + math.min(b.no, kBehaviorMinDays))
          .compareTo(math.min(a.yes, kBehaviorMinDays) +
              math.min(a.no, kBehaviorMinDays)));
  return locked;
}
