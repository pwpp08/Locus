// Compare metrics: two weeks in their own chart shapes, a shared touch, a
// pager back through weeks, and a correlation only when enough days pair up.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/compare_metrics.dart';
import 'package:openstrap_edge/ui2/screens/trend_view.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

const _today = '2026-08-16';

Map<String, double> _days(double Function(int i) v, [int n = 40]) =>
    {for (var i = 0; i < n; i++) shiftDay(_today, -i): v(i)};

class _Loader extends TrendLoader {
  final Map<String, Map<String, double>> data;
  final Map<String, List<Map<String, double>>> layered;
  _Loader(this.data, {this.layered = const {}}) : super(null);

  @override
  Future<Map<String, double>> daily(TrendMetric m) async => data[m.id] ?? {};

  @override
  Future<List<Map<String, double>>> layers(TrendMetric m) async =>
      layered[m.id] ?? const [];

  @override
  Future<Map<String, ({double bed, double wake})>> sleepSpans() async =>
      const {};
}

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(390 * 3, 2400 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(body: SingleChildScrollView(child: w)),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
  });

  group('compareCorrelation', () {
    final days = [for (var i = 0; i < 20; i++) shiftDay(_today, -i)];
    test('opposite series read as moving in opposite directions', () {
      final a = {for (var i = 0; i < 20; i++) days[i]: 50.0 + i};
      final b = {for (var i = 0; i < 20; i++) days[i]: 70.0 - i * 2};
      final c = compareCorrelation(a, b, days: days)!;
      expect(c.r, closeTo(-1, 1e-9));
      expect(c.n, 20);
      expect(compareSentence('HRV', 'resting HR', c),
          contains('moved in opposite directions'));
    });

    test('too few paired days says nothing', () {
      final a = {for (var i = 0; i < 9; i++) days[i]: i.toDouble()};
      expect(compareCorrelation(a, a, days: days), isNull);
    });

    test('a flat series has no correlation', () {
      final a = {for (final d in days) d: 5.0};
      final b = {for (var i = 0; i < 20; i++) days[i]: i.toDouble()};
      expect(compareCorrelation(a, b, days: days), isNull);
    });
  });

  test('each metric keeps its own shape; zones stack in colour', () {
    final hrv = compareSeriesOf(
        trendMetricOf('hrv')!,
        (daily: _days((i) => 60.0 + i % 5), layers: null, spans: null),
        end: _today);
    expect(hrv.shape, CompareShape.line);
    final zones = compareSeriesOf(
        trendMetricOf('zones_13')!,
        (
          daily: _days((i) => 30.0),
          layers: [for (var z = 0; z < 3; z++) _days((i) => 10.0)],
          spans: null,
        ),
        end: _today);
    expect(zones.shape, CompareShape.stacked);
    expect(zones.layerColours, [C.refZone1, C.refZone2, C.refZone3]);
    expect(zones.values.last, 30);
  });

  test('two metrics of one colour family are told apart', () {
    expect(compareSecondColour(C.dialStrain, C.dialStrain),
        isNot(C.dialStrain));
    expect(compareSecondColour(C.dialStrain, C.optimal), C.optimal);
  });

  testWidgets('both metrics share one chart', (t) async {
    await _pump(
      t,
      CompareMetricsCard(
        loader: _Loader({
          'hrv': _days((i) => 60.0 + i % 5),
          'zones_13': _days((i) => 30.0 + i % 7 * 5),
        }, layered: {
          'zones_13': [for (var z = 0; z < 3; z++) _days((i) => 10.0)],
        }),
        today: _today,
        pair: ('hrv', 'zones_13'),
      ),
    );
    expect(find.text('COMPARE METRICS'), findsOneWidget);
    expect(find.byType(ScrubArea), findsOneWidget);
    expect(find.byType(ScrubLine), findsNothing);
    // Four weeks of both: the relationship is stated.
    expect(find.textContaining('Over these four weeks'), findsOneWidget);
  });

  testWidgets('a touch reads the day out for both', (t) async {
    await _pump(
      t,
      CompareMetricsCard(
        loader: _Loader({
          'hrv': _days((i) => 60.0 + i),
          'resting_hr': _days((i) => 50.0 + i),
        }),
        today: _today,
        pair: ('hrv', 'resting_hr'),
      ),
    );
    t.widget<ScrubArea>(find.byType(ScrubArea)).onScrub(3);
    await t.pump();
    expect(find.text('THU, AUG 13'), findsNWidgets(2));
  });

  testWidgets('the pager steps back a week and forward again', (t) async {
    await _pump(
      t,
      CompareMetricsCard(
        loader: _Loader({
          'hrv': _days((i) => 60.0),
          'resting_hr': _days((i) => 50.0),
        }),
        today: _today,
        pair: ('hrv', 'resting_hr'),
      ),
    );
    expect(find.text('AUG 10 - AUG 16'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Earlier'));
    await t.pumpAndSettle();
    expect(find.text('AUG 3 - AUG 9'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Later'));
    await t.pumpAndSettle();
    expect(find.text('AUG 10 - AUG 16'), findsOneWidget);
  });

  testWidgets('choosing the other slot\'s metric swaps the two', (t) async {
    await _pump(
      t,
      CompareMetricsCard(
        loader: _Loader({}),
        today: _today,
        pair: ('hrv', 'resting_hr'),
      ),
    );
    await t.tap(find.text('HRV').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Resting heart rate').last);
    await t.pumpAndSettle();
    expect(Prefs.getString(Prefs.comparePair, ''), 'resting_hr,hrv');
  });
}
