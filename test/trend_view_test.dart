// Trend View and My Dashboard read; they do not model. What is pinned here is
// the arithmetic they do on what they read: the 7-day comparison, today left
// out of an average, weekly totals, zero-filled strength days that start only
// once the app has data, and the sleep-coach figures saved for a history.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/crossday_pipeline.dart'
    show sleepCoachDaySeries;
import 'package:openstrap_edge/ui2/screens/trend_view.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

const _today = '2026-08-16';

Map<String, double> _days(List<double> newestFirst) => {
      for (var i = 0; i < newestFirst.length; i++)
        shiftDay(_today, -i): newestFirst[i],
    };

class _Loader extends TrendLoader {
  final Map<String, Map<String, double>> data;
  _Loader(this.data) : super(null);

  @override
  Future<Map<String, double>> daily(TrendMetric m) async => data[m.id] ?? {};

  @override
  Future<String?> firstDay() async => null;
}

void main() {
  final hrv = trendMetricOf('hrv')!;
  final zones = trendMetricOf('zones_13')!;
  final strength = trendMetricOf('strength_time')!;

  test('a daily row is the newest value against the 7 days before it', () {
    final h = trendHeadline(hrv, _days([70, 60, 60, 60, 60, 60, 60, 60]),
        today: _today);
    expect(h.value, 70);
    expect(h.against, 60);
  });

  test('a missing today falls back to the newest day this week', () {
    final d = _days([0, 55, 50])..remove(_today);
    final h = trendHeadline(hrv, d, today: _today);
    expect(h.value, 55);
    expect(h.against, 50);
  });

  test('nothing this week is a dash, not a zero', () {
    final h = trendHeadline(hrv, const {}, today: _today);
    expect(h.value, isNull);
    expect(trendFormat(hrv, h.value), '--');
  });

  test('a weekly row is this week\'s total against last week\'s', () {
    final d = _days([for (var i = 0; i < 14; i++) i < 7 ? 10 : 20]);
    final h = trendHeadline(zones, d, today: _today);
    expect(h.value, 70);
    expect(h.against, 140);
    expect(trendFormat(zones, h.value), '1:10');
  });

  test('strength zeros begin on the first day the app has data', () {
    final first = shiftDay(_today, -3);
    final d = {shiftDay(_today, -1): 45.0};
    final h = trendHeadline(strength, d, today: _today, firstDay: first);
    expect(h.value, 45);
    // Last week was before the app existed: unknown, not zero.
    expect(h.against, isNull);
  });

  test('an average leaves today out', () {
    final d = _days([100, 10, 20]);
    final bars = trendBars(hrv, d, TrendRange.week, _today, skip: _today);
    expect(trendAverage(bars), 15);
    // The bar is still drawn.
    expect(trendBars(hrv, d, TrendRange.week, _today).last.v, 100);
  });

  test('six months is 26 weekly bars, summed for a weekly metric', () {
    final d = _days([for (var i = 0; i < 14; i++) 10]);
    final bars = trendBars(zones, d, TrendRange.sixMonths, _today);
    expect(bars, hasLength(26));
    expect(bars.last.v, 70);
    expect(bars.first.v, isNull);
    final avgBars = trendBars(hrv, _days([for (var i = 0; i < 7; i++) 50]),
        TrendRange.sixMonths, _today);
    expect(avgBars.last.v, 50);
  });

  test('signed hours format with their sign', () {
    final m = trendMetricOf('hvn_hours')!;
    expect(trendFormat(m, -72), '−1:12');
    expect(trendFormat(m, 30, sign: true), '+0:30');
  });

  test('the sleep coach saves need and debt, absent as null', () {
    expect(
      sleepCoachDaySeries({
        'sleep_coach': {
          'need': {'value': {'need_sec': 31380}},
        },
        'sleep_debt': {'value': {'debt_hours': 0.5}},
      }),
      {'sleep_need_min': 523, 'sleep_debt_min': 30},
    );
    expect(sleepCoachDaySeries(const {}),
        {'sleep_need_min': null, 'sleep_debt_min': null});
  });

  testWidgets('trend view: average, a tapped bar, and the picker',
      (t) async {
    // Tall enough for the whole picker list.
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final h = t.ensureSemantics();
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: TrendViewScreen(
        initial: 'strain',
        today: _today,
        loader: _Loader({
          'strain': _days([15, 10, 12, 14]),
          'sleep_debt': _days([-20, 40]),
        }),
      ),
    ));
    await t.pump();
    await t.pump();
    expect(find.text('DAY STRAIN'), findsOneWidget);
    expect(find.text('12.0'), findsOneWidget); // (10+12+14)/3, today left out
    expect(find.textContaining('Average does not include today'), findsOneWidget);

    await t.tap(find.bySemanticsLabel(RegExp(r'^Aug 16: 15\.0$')));
    await t.pump();
    expect(find.text('Aug 16: 15.0'), findsOneWidget);

    await t.tap(find.text('DAY STRAIN'));
    await t.pump();
    expect(find.text('RECOVERY'), findsWidgets);
    await t.tap(find.text('SLEEP DEBT'));
    await t.pump();
    await t.pump();
    expect(find.text('SLEEP DEBT'), findsOneWidget);
    expect(find.text('0:40'), findsOneWidget);
    expect(t.takeException(), isNull);
    h.dispose();
  });

  testWidgets('VO2 max says why it is empty instead of drawing', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: TrendViewScreen(
          initial: 'vo2max', today: _today, loader: _Loader(const {})),
    ));
    await t.pump();
    await t.pump();
    expect(find.textContaining('does not estimate VO₂ max'), findsOneWidget);
  });
}
