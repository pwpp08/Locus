// Weekly and monthly reports: periods are Monday weeks and calendar months, a
// running period leaves today's unfinished strain out, every figure comes off
// stored days only, and the journal's effects carry a 90% interval.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/behavior_impact.dart';
import 'package:openstrap_edge/compute/period_report.dart';

void main() {
  test('weeks run Monday to Sunday, months the calendar month', () {
    expect(periodOf(ReportSpan.week, '2026-11-05'), ('2026-11-02', '2026-11-08'));
    expect(periodOf(ReportSpan.week, '2026-11-02'), ('2026-11-02', '2026-11-08'));
    expect(periodOf(ReportSpan.week, '2026-11-08'), ('2026-11-02', '2026-11-08'));
    expect(periodOf(ReportSpan.month, '2026-02-14'), ('2026-02-01', '2026-02-28'));
    expect(periodBefore(ReportSpan.month, '2026-01-01'), ('2025-12-01', '2025-12-31'));
    expect(reportPeriods(ReportSpan.week, '2026-10-20', '2026-11-05'), [
      ('2026-11-02', '2026-11-08'),
      ('2026-10-26', '2026-11-01'),
      ('2026-10-19', '2026-10-25'),
    ]);
  });

  test('a running week: counts, today out of strain, best and worst', () {
    const today = '2026-11-05';
    final r = periodReport(
      span: ReportSpan.week,
      day: today,
      today: today,
      series: {
        'recovery': {
          '2026-11-02': 80, '2026-11-03': 40, '2026-11-04': 20, '2026-11-05': 70,
          // Last week, for the comparison.
          '2026-10-27': 50, '2026-10-28': 60,
        },
        'strain': {
          '2026-11-02': 14, '2026-11-03': 9, '2026-11-04': 4,
          '2026-11-05': 2, // still running
        },
      },
    );
    expect(r.partial, isTrue);
    expect(r.recoveryDays, (green: 2, yellow: 1, red: 1));
    expect(r.now[ReportMetric.recovery], 52.5);
    expect(r.before[ReportMetric.recovery], 55);
    expect(r.now[ReportMetric.strain], 9);
    expect(r.now[ReportMetric.hrv], isNull);
    expect(r.best!.day, '2026-11-02');
    expect(r.best!.strain, 14);
    expect(r.worst!.day, '2026-11-04');
    // Today's strain does not count against its target yet.
    expect(r.targetOf, 3);
    // 80 → 13.2 ± 4: 14 is in; 40 → 9.6 ± 4: 9 is in; 20 → 7.8 ± 4: 4 is in.
    expect(r.targetDays, 3);
    // Two weeks of strain are not enough for a fitness.
    expect(r.fitness, isNull);
    expect(r.balanceRatio, isNull);
    expect(r.summary, startsWith('A steady week: 2 green days'));
  });

  test('nothing stored, nothing shown', () {
    final r = periodReport(
        span: ReportSpan.month, day: '2026-06-10', today: '2026-11-05', series: const {});
    expect(r.isEmpty, isTrue);
    expect(r.partial, isFalse);
    expect(r.best, isNull);
    expect(r.summary, 'This month.');
  });

  test('the impact interval is the two means apart, 1.645 standard errors wide', () {
    final out = {
      for (var i = 0; i < 10; i++) 'y$i': 60.0 + (i.isEven ? 4 : -4),
      for (var i = 0; i < 10; i++) 'n$i': 50.0 + (i.isEven ? 4 : -4),
    };
    final b = impactOf(BehaviorKind.journalTag, 'Tag', out,
        yes: [for (var i = 0; i < 10; i++) 'y$i'],
        no: [for (var i = 0; i < 10; i++) 'n$i']);
    expect(b.impact, 10);
    // Each side: variance 16·10/9, over 10 days.
    final se = b.se!;
    expect(se, closeTo(1.8856, 1e-3));
    expect(b.ci90!.lo, closeTo(10 - 1.645 * se, 1e-9));
    expect(b.ci90!.hi, closeTo(10 + 1.645 * se, 1e-9));
    final locked = impactOf(BehaviorKind.journalTag, 'Tag', out,
        yes: const ['y0'], no: const ['n0']);
    expect(locked.ci90, isNull);
  });
}
