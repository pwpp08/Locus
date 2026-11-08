// The shared trend reading on the screens that use it: the verdict header,
// the usual-range band and its abstention, press-and-hold on a card, recovery
// bars in their ring colour, and the overnight chart's cursor linked to the
// stage chart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

int _noon(int daysAgo) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - daysAgo, 12).millisecondsSinceEpoch ~/
      1000;
}

Future<void> _host(WidgetTester t, Widget w,
    {double height = 900, bool screen = false}) async {
  t.view.physicalSize = Size(390 * 3, height * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: screen ? w : Scaffold(body: SingleChildScrollView(child: w)),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('TrendCard with a usual range', () {
    Widget card() => TrendCard(
          'Resting heart rate',
          '58',
          'bpm',
          '',
          'as of today',
          const [55, 54, 56, 55, 58],
          C.red,
          band: const UsualRange(53, 57),
          latest: 58,
          higherBetter: false,
          format: (v) => v.round().toString(),
          dayOf: (i) => 'Day $i',
        );

    testWidgets('says the word, the arrow and the difference from usual',
        (t) async {
      final handle = t.ensureSemantics();
      await _host(t, card());
      expect(find.text('Above usual'), findsOneWidget);
      expect(find.text('· +3 bpm from your usual 55 bpm'), findsOneWidget);
      final label = t.getSemantics(find.byType(TrendCard)).label;
      expect(label, contains('Above usual, +3 bpm from your usual 55 bpm'));
      handle.dispose();
    });

    testWidgets('press and hold reads the day under the finger, and lets go',
        (t) async {
      await _host(t, card());
      final plot = find.byType(Scrubber);
      final g = await t.startGesture(t.getBottomRight(plot) - const Offset(2, 2));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Day 4 · 58 bpm'), findsOneWidget);
      await g.up();
      await t.pump();
      expect(find.text('as of today'), findsOneWidget);
    });

    testWidgets('a tap is still the door, not a reading', (t) async {
      var opened = 0;
      await _host(
          t,
          TrendCard('HRV', '48', 'ms', '', '', const [50, 48], C.green,
              band: const UsualRange(45, 55),
              latest: 48,
              dayOf: (i) => 'Day $i',
              onTap: () => opened++));
      await t.tap(find.byType(Scrubber));
      await t.pumpAndSettle();
      expect(opened, 1);
      expect(find.textContaining('Day '), findsNothing);
    });
  });

  testWidgets('a chart frame draws and speaks the usual range', (t) async {
    final handle = t.ensureSemantics();
    const axis = AxisSpec(min: 40, max: 70, format: axisInt);
    await _host(
      t,
      const ChartFrame(
        title: 'Resting heart rate',
        unit: 'bpm',
        yAxis: axis,
        band: UsualRange(52, 58),
        series: [55, 56],
        child: SizedBox.expand(),
      ),
    );
    expect(find.byType(BandLayer), findsOneWidget);
    expect(t.getSemantics(find.byType(ChartFrame)).label,
        contains('Usual range 52–58'));
    handle.dispose();
  });

  group('MetricDetail verdict', () {
    MetricData hrv({Map<String, dynamic>? baselines}) => MetricData(
          daysAvailable: 30,
          series: [
            for (var i = 20; i >= 1; i--) (t: _noon(i), v: 55.0),
            (t: _noon(0), v: 48.0),
          ],
          baselines: baselines,
        );

    Future<void> pump(WidgetTester t, MetricData d) async {
      t.view.physicalSize = const Size(390 * 3, 1600 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: MetricDetail('hrv', data: d)),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('HRV is judged against the pipeline baseline', (t) async {
      await pump(
          t,
          hrv(baselines: const {
            'hrv': {'baseline': 54, 'spread': 2, 'n_valid': 20},
          }));
      expect(find.text('Below usual'), findsOneWidget);
      expect(find.text('· −6 ms from your usual 54 ms'), findsOneWidget);
      await t.tap(find.text('30 DAYS'));
      await t.pumpAndSettle();
      expect(find.byType(BandLayer), findsOneWidget);
    });

    testWidgets('no pipeline baseline is no band, never one made up from the '
        'chart', (t) async {
      await pump(t, hrv());
      expect(find.text('Below usual'), findsNothing);
      await t.tap(find.text('30 DAYS'));
      await t.pumpAndSettle();
      expect(find.byType(BandLayer), findsNothing);
    });
  });

}
