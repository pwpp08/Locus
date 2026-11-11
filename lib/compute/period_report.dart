// period_report.dart — a week's or a month's report, read off stored daily
// series and nothing else: the three averages against the period before, the
// days by recovery colour, the averages that make up a day, training balance,
// and the best and worst day. A figure with no stored days behind it is null;
// nothing here is filled in.

import '../data/day_label.dart' show dayLabelOf;
import 'whoop_scores.dart' show whoopStrainTarget;

enum ReportSpan { week, month }

/// The metrics the averages card lists, in its order.
enum ReportMetric {
  recovery,
  strain,
  sleepPerformance,
  sleepHours,
  sleepConsistency,
  hrv,
  restingHr,
}

/// The stored series each metric reads.
const kReportSeries = <ReportMetric, String>{
  ReportMetric.recovery: 'recovery',
  ReportMetric.strain: 'strain',
  ReportMetric.sleepPerformance: 'sleep_performance',
  ReportMetric.sleepHours: 'tst_min',
  ReportMetric.sleepConsistency: 'sleep_consistency',
  ReportMetric.hrv: 'hrv',
  ReportMetric.restingHr: 'resting_hr',
};

/// +1 where up is better, -1 where down is, 0 where neither.
int reportBetter(ReportMetric m) => switch (m) {
      ReportMetric.strain => 0,
      ReportMetric.restingHr => -1,
      _ => 1,
    };

/// Training balance bands on fatigue (7-day mean strain) over fitness
/// (42-day): under 0.8 easing off, to 1.3 balanced, over it overreaching.
enum TrainingBalance { easing, balanced, overreaching }

TrainingBalance trainingBalanceOf(double ratio) => ratio < .8
    ? TrainingBalance.easing
    : ratio <= 1.3
        ? TrainingBalance.balanced
        : TrainingBalance.overreaching;

typedef ReportDay = ({String day, double recovery, double? strain});

class PeriodReport {
  final ReportSpan span;

  /// First and last day, inclusive, as local day labels.
  final String from, to;

  /// The period is still running (it holds today).
  final bool partial;

  /// Each metric's mean over the period, and over the period before.
  final Map<ReportMetric, double?> now, before;

  final ({int green, int yellow, int red}) recoveryDays;

  /// Days with strain inside the target their recovery set, of days with
  /// both.
  final int targetDays, targetOf;

  /// Mean strain over the 7 and 42 days ending on [to].
  final double? fatigue, fitness;

  final ReportDay? best, worst;

  const PeriodReport({
    required this.span,
    required this.from,
    required this.to,
    required this.partial,
    required this.now,
    required this.before,
    required this.recoveryDays,
    required this.targetDays,
    required this.targetOf,
    required this.fatigue,
    required this.fitness,
    required this.best,
    required this.worst,
  });

  double? get balanceRatio =>
      fatigue == null || fitness == null || fitness! <= 0
          ? null
          : fatigue! / fitness!;

  bool get isEmpty => now.values.every((v) => v == null);

  /// The plain-words summary: how the period went by recovery, how often
  /// strain sat in its target, and the biggest change on the period before.
  String get summary {
    final word = span == ReportSpan.week ? 'week' : 'month';
    final rec = now[ReportMetric.recovery];
    final lead = rec == null
        ? 'This $word'
        : rec >= 67
            ? 'A strong $word'
            : rec >= 34
                ? 'A steady $word'
                : 'A hard $word';
    final parts = <String>[];
    final g = recoveryDays.green;
    if (recoveryDays.green + recoveryDays.yellow + recoveryDays.red > 0) {
      parts.add('$g green ${g == 1 ? 'day' : 'days'}');
    }
    if (targetOf > 0) {
      parts.add('strain inside your target on $targetDays of $targetOf days');
    }
    final first = parts.isEmpty ? '$lead.' : '$lead: ${parts.join(' and ')}.';

    // The biggest move, in its own unit, if it is worth a sentence.
    String? move;
    var size = 0.0;
    for (final (m, name, unit, min) in const [
      (ReportMetric.sleepPerformance, 'Sleep performance', 'points', 3.0),
      (ReportMetric.recovery, 'Recovery', 'points', 3.0),
      (ReportMetric.hrv, 'HRV', 'ms', 3.0),
    ]) {
      final a = now[m], b = before[m];
      if (a == null || b == null) continue;
      final d = a - b;
      if (d.abs() < min || d.abs() / min <= size) continue;
      size = d.abs() / min;
      move = '$name ${d > 0 ? 'rose' : 'fell'} ${d.abs().round()} $unit '
          'from last $word.';
    }
    return move == null ? first : '$first $move';
  }
}

String _shift(String day, int by) {
  final d = DateTime.parse(day);
  return dayLabelOf(DateTime(d.year, d.month, d.day + by));
}

/// The days from [from] to [to], inclusive.
List<String> reportDays(String from, String to) {
  final out = <String>[];
  for (var d = from; d.compareTo(to) <= 0; d = _shift(d, 1)) {
    out.add(d);
  }
  return out;
}

/// The Monday of [day]'s week.
String weekStartOf(String day) {
  final d = DateTime.parse(day);
  return dayLabelOf(DateTime(d.year, d.month, d.day - (d.weekday - 1)));
}

/// The period [span] holding [day]: (first, last).
(String, String) periodOf(ReportSpan span, String day) {
  if (span == ReportSpan.week) {
    final a = weekStartOf(day);
    return (a, _shift(a, 6));
  }
  final d = DateTime.parse(day);
  return (
    dayLabelOf(DateTime(d.year, d.month, 1)),
    dayLabelOf(DateTime(d.year, d.month + 1, 0)),
  );
}

/// The period before the one starting [from].
(String, String) periodBefore(ReportSpan span, String from) =>
    periodOf(span, _shift(from, -1));

/// The report for the [span] holding [day]. [series] maps each
/// [kReportSeries] key to a value per local day. [today] marks a running
/// period; its unfinished day is left out of every average.
PeriodReport periodReport({
  required ReportSpan span,
  required String day,
  required String today,
  required Map<String, Map<String, double>> series,
}) {
  final (from, to) = periodOf(span, day);
  final (pFrom, pTo) = periodBefore(span, from);
  final partial = from.compareTo(today) <= 0 && to.compareTo(today) >= 0;
  final days = [
    for (final d in reportDays(from, to))
      if (d.compareTo(today) <= 0) d,
  ];
  final prevDays = reportDays(pFrom, pTo);

  double? mean(Iterable<double?> xs) {
    final v = [for (final x in xs) ?x];
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  Map<String, double> of(ReportMetric m) => series[kReportSeries[m]] ?? const {};
  // Recovery and sleep belong to the morning, so today's count once they
  // land; strain is the day's own and today's is still running.
  List<String> counted(ReportMetric m) => [
        for (final d in days)
          if (!(m == ReportMetric.strain && d == today)) d,
      ];

  final now = {
    for (final m in ReportMetric.values) m: mean([for (final d in counted(m)) of(m)[d]]),
  };
  final before = {
    for (final m in ReportMetric.values) m: mean([for (final d in prevDays) of(m)[d]]),
  };

  final rec = of(ReportMetric.recovery), strain = of(ReportMetric.strain);
  var green = 0, yellow = 0, red = 0, inTarget = 0, both = 0;
  ReportDay? best, worst;
  for (final d in days) {
    final r = rec[d];
    if (r == null) continue;
    if (r >= 67) {
      green++;
    } else if (r >= 34) {
      yellow++;
    } else {
      red++;
    }
    final s = d == today ? null : strain[d];
    final entry = (day: d, recovery: r, strain: s);
    if (best == null || r > best.recovery) best = entry;
    if (worst == null || r < worst.recovery) worst = entry;
    final t = whoopStrainTarget(r);
    if (s != null && t != null) {
      both++;
      if (s >= t.lo && s <= t.hi) inTarget++;
    }
  }
  // One scored day is not a best and a worst.
  if (best != null && best.day == worst?.day) worst = null;

  final end = to.compareTo(today) > 0 ? _shift(today, -1) : to;
  double? strainMean(int n) => mean([for (var i = 0; i < n; i++) strain[_shift(end, -i)]]);
  final fitnessDays = [for (var i = 0; i < 42; i++) ?strain[_shift(end, -i)]];

  return PeriodReport(
    span: span,
    from: from,
    to: to,
    partial: partial,
    now: now,
    before: before,
    recoveryDays: (green: green, yellow: yellow, red: red),
    targetDays: inTarget,
    targetOf: both,
    fatigue: strainMean(7),
    // A fitness from a fortnight is not a fitness.
    fitness: fitnessDays.length < 14 ? null : strainMean(42),
    best: best,
    worst: worst,
  );
}

/// Every period of [span] from the one holding [first] to the one holding
/// [today], newest first.
List<(String, String)> reportPeriods(ReportSpan span, String first, String today) {
  final out = <(String, String)>[];
  var p = periodOf(span, today);
  final stop = periodOf(span, first).$1;
  for (var i = 0; i < 520 && p.$1.compareTo(stop) >= 0; i++) {
    out.add(p);
    p = periodBefore(span, p.$1);
  }
  return out;
}

/// The mean recovery of the period [from]–[to], for the list's rings.
double? meanOver(Map<String, double> m, String from, String to) {
  final v = [for (final d in reportDays(from, to)) ?m[d]];
  return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
}
