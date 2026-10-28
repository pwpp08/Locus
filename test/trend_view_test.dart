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
  final Map<String, TrendIntra> intra;
  final Map<String, List<Map<String, double>>> layered;
  final Map<String, ({double bed, double wake})> spans;
  _Loader(this.data,
      {this.intra = const {}, this.layered = const {}, this.spans = const {}})
      : super(null);

  @override
  Future<List<Map<String, double>>> layers(TrendMetric m) async =>
      layered[m.id] ?? const [];

  @override
  Future<Map<String, ({double bed, double wake})>> sleepSpans() async => spans;

  @override
  Future<Map<String, double>> daily(TrendMetric m) async => data[m.id] ?? {};

  @override
  Future<String?> firstDay() async => null;

  @override
  Future<TrendIntra?> intraday(TrendMetric m, String day) async => intra[m.id];
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

    // Drag a finger onto the newest bar: its value is read out big, and its
    // date is the caption above it.
    final box = t.getRect(find.byType(ScrubColumns));
    final drag = await t.startGesture(Offset(box.right - 6, box.center.dy));
    await t.pump();
    expect(find.text('15.0'), findsOneWidget);
    expect(find.text('SUN, AUG 16, 2026'), findsOneWidget);
    await drag.up();
    await t.pump();
    expect(find.text('12.0'), findsOneWidget, reason: 'lifting returns to the average');

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

  test('the axis follows the data and never passes the scale\'s own ceiling', () {
    final strain = trendMetricOf('strain')!;
    // A hard week: strain tops out at 17.6, and the axis must not run to 30.
    final hard = trendAxis(strain, [10, 17.6, 6.5], line: false);
    expect(hard.hi, lessThanOrEqualTo(21));
    expect(hard.lo, 0);
    // A light week gets a short axis, not a fixed 21.
    final light = trendAxis(strain, [2.0, 3.5, 4.0], line: false);
    expect(light.hi, lessThan(10));
    // Reaching the top of the scale divides it evenly: 0 7 14 21.
    expect(trendAxis(strain, [21.0, 3.0], line: false).ticks, [0, 7, 14, 21]);
    expect(trendAxis(trendMetricOf('recovery')!, [99.0], line: false).ticks,
        [0, 25, 50, 75, 100]);
    // A line follows its own values instead of starting at zero.
    final hrv = trendAxis(trendMetricOf('hrv')!, [76.0, 98, 114], line: true);
    expect(hrv.lo, greaterThan(0));
    expect(hrv.lo, lessThanOrEqualTo(76));
    expect(hrv.hi, greaterThanOrEqualTo(114));
    // Nothing to draw is still an axis.
    expect(trendAxis(strain, const [], line: false).hi, 21);
  });

  test('a typical range needs a week of history, and is the mean give or take one SD', () {
    final d = {for (var i = 1; i <= 10; i++) shiftDay(_today, -i): i.isEven ? 90.0 : 110.0};
    final b = trendTypical(d, _today)!;
    expect(b.lo, closeTo(90, 1e-9));
    expect(b.hi, closeTo(110, 1e-9));
    expect(trendTypical({shiftDay(_today, -1): 80}, _today), isNull);
  });

  test('a day is summed, averaged or read at its last point, as the metric says', () {
    TrendIntra mk(List<double?> v, {bool hourly = false}) =>
        (values: v, hourly: hourly, day: _today);
    expect(trendDayValue(trendMetricOf('strain')!, mk([1, 4, null, 9.5])), 9.5);
    expect(trendDayValue(trendMetricOf('steps')!, mk([100, null, 250], hourly: true)), 350);
    expect(trendDayValue(trendMetricOf('avg_hr')!, mk([60, 80, null])), 70);
    expect(trendDayValue(trendMetricOf('avg_hr')!, mk([null, null])), isNull);
  });

  testWidgets('a line metric shows its unit and the change against the week before',
      (t) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: TrendViewScreen(
        initial: 'hrv',
        today: _today,
        loader: _Loader({
          // This week 100, the week before 80: up 25 %.
          'hrv': {
            for (var i = 0; i < 7; i++) shiftDay(_today, -i): 100.0,
            for (var i = 7; i < 14; i++) shiftDay(_today, -i): 80.0,
          },
        }),
      ),
    ));
    await t.pump();
    await t.pump();
    // No minute data to open on, so the week is what it opens on.
    expect(find.text('100'), findsOneWidget);
    expect(find.text('ms'), findsOneWidget);
    expect(find.text('25% vs. prior week'), findsOneWidget);
    expect(find.byType(ScrubLine), findsOneWidget);
  });

  testWidgets('a chart with a day opens on it, and reads out the minute under the finger',
      (t) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final minutes = List<double?>.filled(1440, null);
    for (var i = 8 * 60; i < 20 * 60; i++) {
      minutes[i] = 60.0 + (i % 40);
    }
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: TrendViewScreen(
        initial: 'avg_hr',
        today: _today,
        loader: _Loader(const {},
            intra: {'avg_hr': (values: minutes, hourly: false, day: _today)}),
      ),
    ));
    await t.pump();
    await t.pump();
    await t.pump();
    // D is offered, and it is where the chart opened.
    expect(find.text('D'), findsOneWidget);
    expect(find.text('bpm'), findsOneWidget);
    final box = t.getRect(find.byType(ScrubLine));
    final g = await t.startGesture(Offset(box.right - 4, box.center.dy));
    await t.pump();
    // The right edge of the plot is the last minute of the day.
    expect(find.text('23:59'), findsOneWidget);
    await g.up();
    await t.pump();
    expect(find.text('AVERAGE'), findsOneWidget);
  });

  testWidgets('a metric with no day view offers only W, M and 6M', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: TrendViewScreen(
          initial: 'recovery', today: _today, loader: _Loader(const {})),
    ));
    await t.pump();
    await t.pump();
    expect(find.text('D'), findsNothing);
    expect(find.text('W'), findsOneWidget);
  });

  Future<void> pumpTrend(WidgetTester t, String id, _Loader loader) async {
    t.view.physicalSize = const Size(390 * 3, 2800 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: TrendViewScreen(initial: id, today: _today, loader: loader),
    ));
    await t.pump();
    await t.pump();
    await t.pump();
  }

  testWidgets('a weekly metric reads as a total, with its zones broken down',
      (t) async {
    // Ten minutes a day in each of zones 1-3, this week and the one before.
    Map<String, double> days(double v) => {
          for (var i = 0; i < 7; i++) shiftDay(_today, -i): v,
        };
    final week = days(30), before = {
      for (var i = 7; i < 14; i++) shiftDay(_today, -i): 15.0
    };
    Map<String, double> layer(double v) => {...days(v), for (final e in before.entries) e.key: v / 2};
    await pumpTrend(
        t,
        'zones_13',
        _Loader({'zones_13': {...week, ...before}},
            layered: {'zones_13': [layer(10), layer(10), layer(10)]}));
    // 7 days × 30 minutes: 3:30. The week before was half that: up 100 %.
    expect(find.text('3:30'), findsOneWidget);
    expect(find.text('WEEKLY TOTAL'), findsWidgets);
    expect(find.text('100% vs. prior week'), findsOneWidget);
    expect(find.textContaining('your previous 7-day total of 1:45'), findsOneWidget);
    // And the breakdown under the chart, a line per zone: 7 × 10 = 1:10 each.
    expect(find.textContaining('HR ZONES BREAKDOWN'), findsOneWidget);
    expect(find.text('Zone 1'), findsOneWidget);
    expect(find.text('Zone 3'), findsOneWidget);
    expect(find.text('1:10'), findsNWidgets(3));
  });

  testWidgets('touching a night of restorative sleep splits it into deep and REM',
      (t) async {
    Map<String, double> days(double v) => {
          for (var i = 0; i < 7; i++) shiftDay(_today, -i): v,
        };
    await pumpTrend(
        t,
        'restorative_hours',
        _Loader({'restorative_hours': days(240)},
            layered: {'restorative_hours': [days(100), days(140)]}));
    expect(find.text('SWS (DEEP)'), findsOneWidget, reason: 'the legend');
    final box = t.getRect(find.byType(ScrubColumns));
    final g = await t.startGesture(Offset(box.right - 4, box.center.dy));
    await t.pump();
    // The newest night: 140 minutes of deep, 100 of REM.
    expect(find.text('2:20'), findsOneWidget);
    expect(find.text('1:40'), findsOneWidget);
    expect(find.text('REM'), findsWidgets);
    await g.up();
    await t.pump();
    expect(find.text('4:00'), findsOneWidget);
  });

  testWidgets('time in bed floats each night from bed to wake on a clock',
      (t) async {
    final spans = {
      for (var i = 0; i < 7; i++)
        shiftDay(_today, -i): (bed: 640.0 + i, wake: 1110.0 + i),
    };
    await pumpTrend(
        t,
        'time_in_bed',
        _Loader({
          'time_in_bed': {for (var i = 0; i < 7; i++) shiftDay(_today, -i): 470.0},
        }, spans: spans));
    expect(find.byType(ScrubRanges), findsOneWidget);
    expect(find.text('7:50'), findsOneWidget);
    expect(find.text('hr'), findsOneWidget);
  });

  testWidgets('hours against need are two lines, each with its own average',
      (t) async {
    Map<String, double> days(double v) => {
          for (var i = 0; i < 7; i++) shiftDay(_today, -i): v,
        };
    await pumpTrend(
        t,
        'hvn_hours',
        _Loader({'hvn_hours': days(-120)}, layered: {
          'hvn_hours': [days(600), days(480)],
        }));
    expect(find.byType(ScrubPair), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('8:00'), findsOneWidget);
    expect(find.text('AVG. NEED'), findsOneWidget);
    expect(find.text('AVG. HOURS'), findsOneWidget);
  });

  testWidgets('the range tabs keep their width with or without a Day tab',
      (t) async {
    Future<double> widthWith(String id) async {
      await pumpTrend(t, id, _Loader(const {}));
      final seg = find.ancestor(of: find.text('W'), matching: find.byType(SizedBox));
      return t.getSize(seg.first).width;
    }

    final withDay = await widthWith('avg_hr');
    final withoutDay = await widthWith('recovery');
    expect(withDay, withoutDay);
    expect(withDay, lessThan(190));
    expect(t.takeException(), isNull);
  });

  testWidgets('VO2 max says why it has no figure, and offers a lab anchor',
      (t) async {
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: TrendViewScreen(
          initial: 'vo2max', today: _today, loader: _Loader(const {})),
    ));
    await t.pump();
    await t.pump();
    await t.pump();
    expect(find.text('NOT ENOUGH YET'), findsOneWidget);
    expect(find.text('ENTER A LAB RESULT'), findsOneWidget);
    // It is a chart like any other now, not a refusal.
    expect(find.text('Not available'), findsNothing);
  });
}
