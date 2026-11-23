// The leaderboard's arithmetic: pure, so the rules can be tested without a
// server. A member with no figure for the board in the window is not on it
// at all (never ranked as 0).
//
// Over a window, strain ranks by the best day in it (the reference's "20.6 —
// Cycling 20.5 on 21/09"), recovery and sleep by the mean of the days shared.

import '../state/duration_format.dart';

/// A team board.
enum BoardMetric { strain, recovery, sleep }

/// The window a board covers: one day, a Monday-to-Sunday week, a month.
enum BoardPeriod {
  day('DAILY'),
  week('MON - SUN'),
  month('MONTHLY');

  const BoardPeriod(this.label);
  final String label;

  /// The first and last local day of the window holding [anchor].
  (DateTime, DateTime) window(DateTime anchor) {
    final d = DateTime(anchor.year, anchor.month, anchor.day);
    return switch (this) {
      BoardPeriod.day => (d, d),
      BoardPeriod.week => (
          DateTime(d.year, d.month, d.day - (d.weekday - 1)),
          DateTime(d.year, d.month, d.day - (d.weekday - 1) + 6),
        ),
      BoardPeriod.month =>
        (DateTime(d.year, d.month, 1), DateTime(d.year, d.month + 1, 0)),
    };
  }
}

/// What a board is ordered by. Each metric has its own three (or two).
enum BoardSort {
  dayStrain('DAY STRAIN'),
  activity('ACTIVITY'),
  calories('CALORIES'),
  recovery('RECOVERY'),
  hrv('HRV'),
  rhr('RHR'),
  performance('PERFORMANCE'),
  hours('HOURS');

  const BoardSort(this.label);
  final String label;

  static List<BoardSort> of(BoardMetric m) => switch (m) {
        BoardMetric.strain => const [dayStrain, activity, calories],
        BoardMetric.recovery => const [recovery, hrv, rhr],
        BoardMetric.sleep => const [performance, hours],
      };
}

/// One member's numbers for one day, as the server hands them back. A null is
/// a figure the reader may not see, or that was not recorded that day.
class DayScore {
  final String userId;
  final DateTime day;
  final double? recovery, strain, sleepMin, sleepPerf, hrv, rhr, calories, hrMax;
  final double? locusAge;
  final DateTime? updatedAt;
  const DayScore(this.userId, this.day,
      {this.recovery,
      this.strain,
      this.sleepMin,
      this.sleepPerf,
      this.hrv,
      this.rhr,
      this.calories,
      this.hrMax,
      this.locusAge,
      this.updatedAt});

  factory DayScore.fromJson(Map<String, dynamic> j) {
    double? n(String k) => (j[k] as num?)?.toDouble();
    return DayScore(
      j['user_id'] as String,
      DateTime.parse(j['day'] as String),
      recovery: n('recovery'),
      strain: n('strain'),
      sleepMin: n('sleep_min'),
      sleepPerf: n('sleep_perf'),
      hrv: n('hrv'),
      rhr: n('rhr'),
      calories: n('calories'),
      hrMax: n('hr_max'),
      locusAge: n('locus_age'),
      updatedAt: DateTime.tryParse('${j['updated_at']}')?.toLocal(),
    );
  }

  /// The figure a board headlines.
  double? headline(BoardMetric m) => switch (m) {
        BoardMetric.strain => strain,
        BoardMetric.recovery => recovery,
        BoardMetric.sleep => sleepPerf,
      };
}

/// A workout on a board: whose, what, how hard, which day.
class BoardActivity {
  final String userId, kind;
  final DateTime day;
  final double? strain, calories;
  const BoardActivity(this.userId, this.day, this.kind,
      {this.strain, this.calories});
}

/// A place on the board.
class BoardRow {
  final String userId;

  /// The board's figure: best day strain, mean recovery, mean sleep %.
  final double headline;

  /// What the board is ordered by; null when the member has the headline
  /// but not this (ranked after those who have it).
  final double? sortValue;

  /// Days with a figure in the window.
  final int days;

  /// The window's workouts, hardest first.
  final List<BoardActivity> activities;

  /// Calories over the window; null when none were shared.
  final double? calories;

  /// Means over the window, for the recovery and sleep lines.
  final double? hrv, rhr, sleepMin;

  const BoardRow(
    this.userId,
    this.headline, {
    this.sortValue,
    this.days = 1,
    this.activities = const [],
    this.calories,
    this.hrv,
    this.rhr,
    this.sleepMin,
  });
}

double? _mean(Iterable<double?> v) {
  final x = [for (final e in v) ?e];
  return x.isEmpty ? null : x.reduce((a, b) => a + b) / x.length;
}

double? _max(Iterable<double?> v) {
  final x = [for (final e in v) ?e];
  return x.isEmpty ? null : x.reduce((a, b) => a > b ? a : b);
}

double? _sum(Iterable<double?> v) {
  final x = [for (final e in v) ?e];
  return x.isEmpty ? null : x.reduce((a, b) => a + b);
}

/// The board for [metric] over [from]–[to] (local days, inclusive), ordered
/// by [sort], best first. Ties go to whoever has more days in the window.
List<BoardRow> rankBoard(
  List<DayScore> scores,
  BoardMetric metric,
  DateTime from,
  DateTime to, {
  BoardSort? sort,
  List<BoardActivity> activities = const [],
}) {
  final first = DateTime(from.year, from.month, from.day);
  final last = DateTime(to.year, to.month, to.day);
  bool inside(DateTime d) {
    final x = DateTime(d.year, d.month, d.day);
    return !x.isBefore(first) && !x.isAfter(last);
  }

  final by = <String, List<DayScore>>{};
  for (final s in scores) {
    if (inside(s.day)) (by[s.userId] ??= []).add(s);
  }
  final acts = <String, List<BoardActivity>>{};
  for (final a in activities) {
    if (inside(a.day)) (acts[a.userId] ??= []).add(a);
  }
  final order = sort ?? BoardSort.of(metric).first;
  final rows = <BoardRow>[];
  for (final e in by.entries) {
    final days = e.value;
    final heads = [for (final d in days) ?d.headline(metric)];
    if (heads.isEmpty) continue;
    final headline = metric == BoardMetric.strain
        ? heads.reduce((a, b) => a > b ? a : b)
        : heads.reduce((a, b) => a + b) / heads.length;
    final mine = [...?acts[e.key]]
      ..sort((a, b) => (b.strain ?? -1).compareTo(a.strain ?? -1));
    final calories = _sum(days.map((d) => d.calories));
    final hrv = _mean(days.map((d) => d.hrv)), rhr = _mean(days.map((d) => d.rhr));
    final sleepMin = _mean(days.map((d) => d.sleepMin));
    final sortValue = switch (order) {
      BoardSort.dayStrain ||
      BoardSort.recovery ||
      BoardSort.performance =>
        headline,
      BoardSort.activity => _max(mine.map((a) => a.strain)),
      BoardSort.calories => calories,
      BoardSort.hrv => hrv,
      // Lower is better: ranked on its negative.
      BoardSort.rhr => rhr == null ? null : -rhr,
      BoardSort.hours => sleepMin,
    };
    rows.add(BoardRow(e.key, headline,
        sortValue: sortValue,
        days: heads.length,
        activities: mine,
        calories: calories,
        hrv: hrv,
        rhr: rhr,
        sleepMin: sleepMin));
  }
  rows.sort((a, b) {
    final av = a.sortValue, bv = b.sortValue;
    if (av == null || bv == null) {
      if (av != bv) return av == null ? 1 : -1;
    } else {
      final c = bv.compareTo(av);
      if (c != 0) return c;
    }
    final h = b.headline.compareTo(a.headline);
    return h != 0 ? h : b.days.compareTo(a.days);
  });
  return rows;
}

/// The mean of a board's headlines: its "4.1 avg". Null when empty.
double? boardAverage(List<BoardRow> rows) => _mean(rows.map((r) => r.headline));

/// [value] as the board writes it.
String boardValue(BoardMetric m, double value) => switch (m) {
      BoardMetric.recovery || BoardMetric.sleep => '${value.round()}%',
      BoardMetric.strain => value.toStringAsFixed(1),
    };

/// 7:49 for a night of 469 minutes.
String hoursClock(double minutes) {
  final m = minutes.round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

/// "1st", "2nd", "3rd", "11th", "1,391st".
String ordinal(int n) {
  final t = n % 100, u = n % 10;
  final suffix = t >= 11 && t <= 13
      ? 'th'
      : switch (u) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '${groupThousands(n)}$suffix';
}

/// 65,866 → "65,866"; with [compact], 65,866 → "65.9K".
String groupThousands(int n, {bool compact = false}) {
  if (compact && n >= 10000) {
    return n >= 1000000
        ? '${(n / 1e6).toStringAsFixed(1)}M'
        : '${(n / 1e3).toStringAsFixed(1)}K';
  }
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// Initials for an avatar: the first letters of the first two words.
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = [for (final w in words.take(2)) String.fromCharCode(w.runes.first)];
  return letters.isEmpty ? '?' : letters.join().toUpperCase();
}

/// A night's length as the app writes durations elsewhere.
String sleepText(double minutes) => durationText(minutes.round());
