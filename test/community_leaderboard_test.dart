// The leaderboard ranks what members shared, over the window, and leaves out
// whoever shared nothing there rather than ranking them at zero.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/community/leaderboard.dart';

void main() {
  final today = DateTime(2026, 11, 14);
  DateTime ago(int n) => DateTime(2026, 11, 14 - n);

  final scores = [
    DayScore('ana', ago(0), recovery: 80, strain: 10.5, sleepMin: 450),
    DayScore('ana', ago(3), recovery: 40),
    DayScore('ben', ago(0), recovery: 70),
    DayScore('ben', ago(1), recovery: 90),
    DayScore('cy', ago(10), recovery: 99), // outside the week
    DayScore('dee', ago(0)), // shares nothing
  ];

  test('today: only today counts', () {
    final b = rankBoard(scores, BoardMetric.recovery, BoardRange.today, today);
    expect([for (final r in b) r.userId], ['ana', 'ben']);
    expect(b.first.value, 80);
  });

  test('the week averages the days each member shared', () {
    final b = rankBoard(scores, BoardMetric.recovery, BoardRange.week, today);
    expect([for (final r in b) (r.userId, r.value, r.days)], [
      ('ben', 80.0, 2),
      ('ana', 60.0, 2),
    ]);
  });

  test('the month reaches back to the older day; no one ranks at zero', () {
    final b = rankBoard(scores, BoardMetric.recovery, BoardRange.month, today);
    expect(b.first.userId, 'cy');
    expect(b.any((r) => r.userId == 'dee'), isFalse);
  });

  test('combined is the mean of the parts a day has', () {
    const strain = 10.5 / 21 * 100;
    const sleep = 450 / 480 * 100;
    expect(scores.first.combined, closeTo((80 + strain + sleep) / 3, 1e-9));
    expect(scores[1].combined, 40);
    expect(scores.last.combined, isNull);
  });

  test('a tie goes to whoever shared more days', () {
    final b = rankBoard([
      DayScore('one', ago(0), recovery: 50),
      DayScore('two', ago(0), recovery: 50),
      DayScore('two', ago(1), recovery: 50),
    ], BoardMetric.recovery, BoardRange.week, today);
    expect(b.first.userId, 'two');
  });

  test('values and initials as the board writes them', () {
    expect(boardValue(BoardMetric.sleep, 479.6), '8:00');
    expect(boardValue(BoardMetric.strain, 9.04), '9.0');
    expect(boardValue(BoardMetric.recovery, 66.6), '67%');
    expect(initialsOf('ana maria lopez'), 'AM');
    expect(initialsOf('  '), '?');
  });
}
