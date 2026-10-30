// The day strain line only climbs; Home's expanded cards draw Trend View's own
// chart shapes; a logged weight rolls in from the last one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/trend_view.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

const _today = '2026-08-16';

Map<String, double> _days(double Function(int i) v, [int n = 14]) =>
    {for (var i = 0; i < n; i++) shiftDay(_today, -i): v(i)};

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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('keptStrain', () {
    test('never falls, ends on the headline, and has no holes', () {
      final c = List<double?>.filled(1440, null);
      c[60] = 1.0;
      c[120] = 4.0;
      c[180] = 7.3; // the morning's peak…
      c[800] = 7.0; // …netted back by a quiet afternoon
      c[1000] = 6.5; // the headline
      final k = TrendLoader.keptStrain(c, through: 1440);
      for (var i = 1; i < k.length; i++) {
        expect(k[i]! >= k[i - 1]!, isTrue, reason: 'minute $i');
      }
      expect(k[0], 0);
      expect(k[120], 4.0);
      expect(k[180], 6.5); // what the rest of the day kept
      expect(k[1000], 6.5);
      expect(k[1439], 6.5); // a past day runs to midnight
    });

    test('today stops at the last reading', () {
      final c = List<double?>.filled(1440, null)..[300] = 2.0;
      final k = TrendLoader.keptStrain(c);
      expect(k[300], 2.0);
      expect(k[301], isNull);
    });
  });

  testWidgets('an expanded zones card stacks its zones in their colours',
      (t) async {
    final layers = [
      for (var z = 0; z < 3; z++) _days((i) => 10.0 + z),
    ];
    await _pump(
      t,
      ExpandedTrendCard(
        m: trendMetricOf('zones_13')!,
        today: _today,
        daily: _days((i) => 33.0),
        layers: layers,
        onOpen: () {},
      ),
    );
    final cols = t.widget<ScrubColumns>(find.byType(ScrubColumns));
    expect(cols.stacks, isNotNull);
    expect(cols.segmentColors, [C.refZone1, C.refZone2, C.refZone3]);
  });

  testWidgets('expanded hours vs. needed is need against achieved', (t) async {
    await _pump(
      t,
      ExpandedTrendCard(
        m: trendMetricOf('hvn_hours')!,
        today: _today,
        daily: _days((i) => i.isEven ? -40.0 : 30.0),
        layers: [_days((i) => 480.0), _days((i) => 450.0)],
        onOpen: () {},
      ),
    );
    expect(find.byType(ScrubPair), findsOneWidget);
    expect(find.byType(ScrubColumns), findsNothing);
  });

  testWidgets('expanded time in bed is nights on a clock', (t) async {
    await _pump(
      t,
      ExpandedTrendCard(
        m: trendMetricOf('time_in_bed')!,
        today: _today,
        daily: _days((i) => 480.0),
        spans: {
          for (var i = 0; i < 14; i++)
            shiftDay(_today, -i): (bed: 660.0, wake: 1140.0),
        },
        onOpen: () {},
      ),
    );
    expect(find.byType(ScrubRanges), findsOneWidget);
  });

  testWidgets('a weight rolls from the last one and lands on the new one',
      (t) async {
    var ticks = 0, done = 0;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: RollingNumber(
            from: 71.8,
            value: 72.4,
            style: F.n48,
            onTick: () => ticks++,
            onDone: () => done++,
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(done, 1);
    expect(ticks, greaterThan(0));
    expect(find.bySemanticsLabel('72.4'), findsOneWidget);
  });
}
