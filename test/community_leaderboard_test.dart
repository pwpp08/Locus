// The leaderboard ranks what members shared over the window, and leaves out
// whoever has nothing there rather than ranking them at zero.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/community/leaderboard.dart';

void main() {
  final today = DateTime(2026, 11, 14); // a Saturday
  DateTime ago(int n) => DateTime(2026, 11, 14 - n);

  final scores = [
    DayScore('ana', ago(0), recovery: 80, strain: 10.5, sleepPerf: 90, hrv: 60, rhr: 50),
    DayScore('ana', ago(3), recovery: 40, strain: 16),
    DayScore('ben', ago(0), recovery: 70, strain: 12, hrv: 90, rhr: 44),
    DayScore('ben', ago(1), recovery: 90),
    DayScore('cy', ago(10), recovery: 99), // outside the week
    DayScore('dee', ago(0)), // shares nothing today
  ];

  test('windows: a day, Monday to Sunday, the calendar month', () {
    expect(BoardPeriod.day.window(today), (today, today));
    expect(BoardPeriod.week.window(today),
        (DateTime(2026, 11, 9), DateTime(2026, 11, 15)));
    expect(BoardPeriod.month.window(today),
        (DateTime(2026, 11, 1), DateTime(2026, 11, 30)));
  });

  test('today: only today counts; no figure, no place', () {
    final b = rankBoard(scores, BoardMetric.recovery, today, today);
    expect([for (final r in b) r.userId], ['ana', 'ben']);
    expect(b.first.headline, 80);
  });

  test('over a week recovery is the mean, strain the best day', () {
    final (from, to) = BoardPeriod.week.window(today);
    final rec = rankBoard(scores, BoardMetric.recovery, from, to);
    expect([for (final r in rec) (r.userId, r.headline, r.days)], [
      ('ben', 80.0, 2),
      ('ana', 60.0, 2),
    ]);
    final str = rankBoard(scores, BoardMetric.strain, from, to);
    expect([for (final r in str) (r.userId, r.headline)], [('ana', 16.0), ('ben', 12.0)]);
  });

  test('sorts: HRV high first, RHR low first, activity by the hardest one', () {
    final hrv = rankBoard(scores, BoardMetric.recovery, today, today, sort: BoardSort.hrv);
    expect(hrv.first.userId, 'ben');
    final rhr = rankBoard(scores, BoardMetric.recovery, today, today, sort: BoardSort.rhr);
    expect(rhr.first.userId, 'ben');
    final act = rankBoard(scores, BoardMetric.strain, today, today,
        sort: BoardSort.activity,
        activities: [
          BoardActivity('ana', today, 'Running', strain: 9),
          BoardActivity('ben', today, 'Yoga', strain: 4),
        ]);
    expect([for (final r in act) r.userId], ['ana', 'ben']);
  });

  test('a member with the headline but not the sort goes last', () {
    final b = rankBoard([
      DayScore('one', today, recovery: 90),
      DayScore('two', today, recovery: 50, hrv: 70),
    ], BoardMetric.recovery, today, today, sort: BoardSort.hrv);
    expect([for (final r in b) r.userId], ['two', 'one']);
  });

  test('a tie goes to whoever shared more days', () {
    final b = rankBoard([
      DayScore('one', ago(0), recovery: 50),
      DayScore('two', ago(0), recovery: 50),
      DayScore('two', ago(1), recovery: 50),
    ], BoardMetric.recovery, ago(6), today);
    expect(b.first.userId, 'two');
  });

  test('numbers as the board writes them', () {
    expect(boardValue(BoardMetric.strain, 9.04), '9.0');
    expect(boardValue(BoardMetric.recovery, 66.6), '67%');
    expect(hoursClock(469), '7:49');
    expect(ordinal(1391), '1,391st');
    expect(ordinal(12), '12th');
    expect(ordinal(905), '905th');
    expect(groupThousands(65866, compact: true), '65.9K');
    expect(initialsOf('ana maria lopez'), 'AM');
    expect(initialsOf('  '), '?');
  });
}
