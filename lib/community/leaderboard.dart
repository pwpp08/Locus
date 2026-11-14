// The leaderboard's arithmetic: pure, so the rules can be tested without a
// server. Each member's figure is the mean of the days they shared in the
// window; a member with none is not on the board at all (never ranked as 0).

/// What the board ranks.
enum BoardMetric { recovery, strain, sleep, combined }

/// The window it ranks over: today, the last 7 days, the last 30.
enum BoardRange { today, week, month }

extension BoardRangeDays on BoardRange {
  int get days => switch (this) {
        BoardRange.today => 1,
        BoardRange.week => 7,
        BoardRange.month => 30,
      };
}

/// One member's numbers for one day, as the server hands them back. A null is
/// a metric they do not share, or did not record that day.
class DayScore {
  final String userId;
  final DateTime day;
  final double? recovery, strain, sleepMin;
  const DayScore(this.userId, this.day,
      {this.recovery, this.strain, this.sleepMin});

  factory DayScore.fromJson(Map<String, dynamic> j) => DayScore(
        j['user_id'] as String,
        DateTime.parse(j['day'] as String),
        recovery: (j['recovery'] as num?)?.toDouble(),
        strain: (j['strain'] as num?)?.toDouble(),
        sleepMin: (j['sleep_min'] as num?)?.toDouble(),
      );

  /// A day's combined score, 0-100: the mean of the parts it has. Recovery
  /// is already 0-100; strain is out of 21; sleep is against eight hours.
  /// Null with no part at all.
  double? get combined {
    final parts = [
      ?recovery,
      if (strain != null) strain! / 21 * 100,
      if (sleepMin != null) (sleepMin! / 480).clamp(0.0, 1.0) * 100,
    ];
    if (parts.isEmpty) return null;
    return parts.reduce((a, b) => a + b) / parts.length;
  }

  double? value(BoardMetric m) => switch (m) {
        BoardMetric.recovery => recovery,
        BoardMetric.strain => strain,
        BoardMetric.sleep => sleepMin,
        BoardMetric.combined => combined,
      };
}

/// A place on the board.
class BoardRow {
  final String userId;
  final double value;

  /// Days that went into [value].
  final int days;
  const BoardRow(this.userId, this.value, this.days);
}

/// The board for [metric] over the [range] ending on [today] (a local date),
/// best first; a tie goes to whoever shared more days. Only a user's days
/// inside the window with a value for [metric] count.
List<BoardRow> rankBoard(
  List<DayScore> scores,
  BoardMetric metric,
  BoardRange range,
  DateTime today,
) {
  final last = DateTime(today.year, today.month, today.day);
  final first = DateTime(last.year, last.month, last.day - (range.days - 1));
  final sums = <String, (double, int)>{};
  for (final s in scores) {
    final d = DateTime(s.day.year, s.day.month, s.day.day);
    if (d.isBefore(first) || d.isAfter(last)) continue;
    final v = s.value(metric);
    if (v == null) continue;
    final (sum, n) = sums[s.userId] ?? (0.0, 0);
    sums[s.userId] = (sum + v, n + 1);
  }
  final rows = [
    for (final e in sums.entries) BoardRow(e.key, e.value.$1 / e.value.$2, e.value.$2),
  ];
  rows.sort((a, b) {
    final byValue = b.value.compareTo(a.value);
    return byValue != 0 ? byValue : b.days.compareTo(a.days);
  });
  return rows;
}

/// [value] as the board writes it.
String boardValue(BoardMetric m, double value) => switch (m) {
      BoardMetric.recovery => '${value.round()}%',
      BoardMetric.strain => value.toStringAsFixed(1),
      BoardMetric.sleep => _hm(value.round()),
      BoardMetric.combined => '${value.round()}',
    };

/// Initials for an avatar: the first letters of the first two words.
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = [for (final w in words.take(2)) String.fromCharCode(w.runes.first)];
  return letters.isEmpty ? '?' : letters.join().toUpperCase();
}

String _hm(int minutes) =>
    '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
