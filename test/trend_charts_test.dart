// How Trend View draws what it reads: which metrics have a Day view, how a
// weekly metric's month is cut, what touching a stacked column says, six
// months as months, and a minute chart that two fingers zoom.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/trend_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

const _today = '2026-08-16';

Map<String, double> _days(double Function(int i) f, {int n = 200}) =>
    {for (var i = 0; i < n; i++) shiftDay(_today, -i): f(i)};

class _Loader extends TrendLoader {
  final Map<String, Map<String, double>> data;
  final Map<String, TrendIntra> intra;
  final Map<String, List<Map<String, double>>> layered;
  final Map<String, ({double bed, double wake})> spans;
  final TrendSleep? sleep;
  _Loader(this.data,
      {this.intra = const {},
      this.layered = const {},
      this.spans = const {},
      this.sleep})
      : super(null);

  @override
  Future<Map<String, double>> daily(TrendMetric m) async => data[m.id] ?? {};
  @override
  Future<String?> firstDay() async => null;
  @override
  Future<List<Map<String, double>>> layers(TrendMetric m) async =>
      layered[m.id] ?? const [];
  @override
  Future<Map<String, ({double bed, double wake})>> sleepSpans() async => spans;
  @override
  Future<TrendIntra?> intraday(TrendMetric m, String day) async => intra[m.id];
  @override
  Future<TrendSleep?> sleepHrv(String day) async => sleep;
}

void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester t, String id, _Loader loader) async {
    t.view.physicalSize = const Size(390 * 3, 2800 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: TrendViewScreen(key: UniqueKey(), initial: id, today: _today, loader: loader),
    ));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tab(WidgetTester t, String label) async {
    await t.tap(find.text(label));
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  test('a weekly metric\'s month is four whole weeks, a bar each', () {
    final zones = trendMetricOf('zones_13')!;
    final bars = trendBars(zones, _days((i) => 10), TrendRange.month, _today);
    expect(bars, hasLength(4));
    expect(bars.map((b) => b.v), everyElement(70));
    expect(bars.last.to, _today);
    expect(bars.first.from, shiftDay(_today, -27));
    expect(trendWindowDays(zones, TrendRange.month), 28);
    // Anything else keeps its thirty days.
    final hrv = trendMetricOf('hrv')!;
    expect(trendBars(hrv, _days((i) => 50), TrendRange.month, _today), hasLength(30));
    expect(trendWindowDays(hrv, TrendRange.month), 30);
  });

  testWidgets('the zone charts have no Day view and calories has one',
      (t) async {
    await pump(t, 'zones_13', _Loader({'zones_13': _days((i) => 30)}));
    expect(find.text('D'), findsNothing);
    expect(find.text('W'), findsOneWidget);

    await pump(
        t,
        'calories',
        _Loader({'calories': _days((i) => 2000)}, intra: {
          'calories': (
            values: <double?>[for (var h = 0; h < 24; h++) h < 18 ? 100.0 : null],
            hourly: true,
            day: _today
          ),
        }));
    expect(find.text('D'), findsOneWidget);
    // Opens on the day, whose hours add up to its figure.
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('1,800'), findsWidgets);
  });

  testWidgets('a month of zones is four weeks, and a touch splits one by zone',
      (t) async {
    final week = _days((i) => 10);
    await pump(
        t,
        'zones_13',
        _Loader({'zones_13': _days((i) => 30)},
            layered: {'zones_13': [week, week, week]}));
    await tab(t, 'M');
    // Four weeks, each named by its dates.
    expect(t.widget<ScrubColumns>(find.byType(ScrubColumns)).xLabels,
        ['Jul 20 - 26', 'Jul 27 - Aug 2', 'Aug 3 - 9', 'Aug 10 - 16']);
    final box = t.getRect(find.byType(ScrubColumns));
    final g = await t.startGesture(Offset(box.right - 20, box.center.dy));
    await t.pump();
    // The week's 7 x 10 minutes in each zone, the top zone first.
    // Three in the readout, and the same three in the breakdown under the
    // chart (every week is alike here, so the average week is this one).
    expect(find.text('1:10'), findsNWidgets(6));
    expect(find.text('ZONE 3'), findsOneWidget);
    expect(find.text('ZONE 1'), findsOneWidget);
    await g.up();
  });

  testWidgets('six months of a daily metric is drawn a month at a time',
      (t) async {
    // 60 until the last month, 54 in it: down 10 %, and down is good for RHR.
    final d = _days((i) => i < 16 ? 54 : 60);
    await pump(t, 'resting_hr', _Loader({'resting_hr': d}));
    await tab(t, '6M');
    expect(find.byType(ScrubMonths), findsOneWidget);
    expect(find.byType(ScrubColumns), findsNothing);
    final marks = t.widget<ScrubMonths>(find.byType(ScrubMonths)).months;
    expect(marks.last.note, '-10%');
    expect(marks.last.tone, C.optimal);
    expect(marks.first.note, isNull);
    // A touch reads out the month under the finger.
    final box = t.getRect(find.byType(ScrubMonths));
    final g = await t.startGesture(Offset(box.left + box.width * .5, box.center.dy));
    await t.pump();
    expect(find.text('60'), findsWidgets);
    await g.up();
  });

  testWidgets('a month of nights marks the average bed and wake times',
      (t) async {
    final spans = {
      for (var i = 0; i < 60; i++)
        shiftDay(_today, -i): (bed: 600.0, wake: 1080.0),
    };
    await pump(t, 'time_in_bed',
        _Loader({'time_in_bed': _days((i) => 480)}, spans: spans));
    await tab(t, 'M');
    final w = t.widget<ScrubRanges>(find.byType(ScrubRanges));
    expect(w.tags.map((e) => e.text), ['22:00', '06:00']);
    // The axis leaves room over and under the bars for their times.
    expect(w.ranges.whereType<Object>(), isNotEmpty);
    await tab(t, '6M');
    expect(find.byType(ScrubMonths), findsOneWidget);
    expect(t.widget<ScrubMonths>(find.byType(ScrubMonths)).down, isTrue);
  });

  testWidgets('hours of HRV are a line, and only the night is averaged',
      (t) async {
    final intra = {
      'hrv': (
        values: <double?>[for (var h = 0; h < 24; h++) h < 12 ? 40.0 + h : null],
        hourly: true,
        day: _today
      ),
    };
    await pump(
        t,
        'hrv',
        _Loader({'hrv': _days((i) => 60)},
            intra: intra, sleep: (from: 0, to: 420, mean: 63.4)));
    expect(find.byType(ScrubLine), findsOneWidget);
    expect(find.text('AVERAGE'), findsWidgets);
    // The night's mean, not the 45.5 the whole day's hours would give.
    expect(find.text('63'), findsWidgets);
    expect(find.text('SLEEP'), findsOneWidget);

    // With no night on record there is no average to give.
    await pump(t, 'hrv', _Loader({'hrv': _days((i) => 60)}, intra: intra));
    expect(find.text('63'), findsNothing);
    expect(find.text('46'), findsNothing);
    expect(find.text('--'), findsWidgets);
    expect(find.text('SLEEP'), findsNothing);
  });

  testWidgets('a six-month weekly chart marks the average of each month',
      (t) async {
    final week = _days((i) => 10);
    await pump(
        t,
        'zones_13',
        _Loader({'zones_13': _days((i) => 30)}, layered: {
          'zones_13': [week, week, week]
        }));
    await tab(t, '6M');
    final marks = t.widget<ScrubColumns>(find.byType(ScrubColumns)).marks;
    expect(marks, isNotEmpty);
    // Every week holds 7 x 3 x 10 minutes, so each month averages 3:30.
    expect(marks.map((m) => m.text).toSet(), {'3:30'});
  });

  test('the picker lists what My Dashboard shows', () {
    SharedPreferences.setMockInitialValues({});
    // Never customized: the default tiles, and every metric listed.
    return Prefs.ensureLoaded().then((_) {
      expect(dashboardMetricsOf(), isNull);
      expect(dashboardTilesOf().first, kStrainRecoveryTile);
      // A list saved before the chart was a tile keeps the chart, first.
      Prefs.setString(Prefs.dashboardTiles, 'hrv,steps');
      expect(dashboardTilesOf(), [kStrainRecoveryTile, 'hrv', 'steps']);
      // Once the user has chosen, a tile that is off stays off.
      Prefs.setBool(Prefs.dashboardChartChosen, true);
      expect(dashboardTilesOf(), ['hrv', 'steps']);
      expect(dashboardMetricsOf(), {'hrv', 'steps'});
    });
  });

  testWidgets('two fingers zoom a minute chart, and reset puts the day back',
      (t) async {
    await pump(
        t,
        'avg_hr',
        _Loader({'avg_hr': _days((i) => 66)}, intra: {
          'avg_hr': (
            values: <double?>[
              for (var i = 0; i < 1440; i++)
                i < 1000 ? 65 + 15 * math.sin(i / 37) : null
            ],
            hourly: false,
            day: _today
          ),
        }));
    expect(find.text('Reset zoom'), findsNothing);
    final c = t.getRect(find.byType(ScrubLine)).center;
    final a = await t.startGesture(c - const Offset(20, 0), pointer: 21);
    final b = await t.startGesture(c + const Offset(20, 0), pointer: 22);
    await a.moveTo(c - const Offset(80, 0));
    await b.moveTo(c + const Offset(80, 0));
    await a.up();
    await b.up();
    await t.pump();
    expect(find.text('Reset zoom'), findsOneWidget);
    // Zoomed in, the labels are by the hour.
    await t.tap(find.text('Reset zoom'));
    await t.pump();
    expect(find.text('Reset zoom'), findsNothing);
  });
}
