// The weekly and monthly reports: the list and a report pumped whole into a
// tall phone-width viewport, at 1x and 3.1x, so an overflow anywhere below the
// fold fails the pump; a period with nothing stored shows dashes, not zeros.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/behavior_impact.dart';
import 'package:openstrap_edge/compute/period_report.dart';
import 'package:openstrap_edge/ui2/screens/reports.dart';
import 'package:openstrap_edge/ui2/screens/trend_view.dart' show shiftDay;
import 'package:openstrap_edge/ui2/ui2.dart';

const _today = '2026-11-05';

Map<String, Map<String, double>> _series() {
  final out = <String, Map<String, double>>{};
  for (var i = 0; i < 70; i++) {
    final d = shiftDay(_today, -i);
    final w = (i * 37 % 23) / 23;
    (out['recovery'] ??= {})[d] = 25 + 70 * w;
    (out['strain'] ??= {})[d] = 5 + 12 * (1 - w);
    (out['sleep_performance'] ??= {})[d] = 60 + 35 * w;
    (out['tst_min'] ??= {})[d] = 340 + 100 * w;
    (out['sleep_consistency'] ??= {})[d] = 70 + 25 * w;
    (out['hrv'] ??= {})[d] = 45 + 20 * w;
    (out['resting_hr'] ??= {})[d] = 60 - 8 * w;
  }
  return out;
}

const _effects = [
  BehaviorImpact(
      kind: BehaviorKind.journalTag,
      title: 'Alcohol',
      yes: 20,
      no: 60,
      meanYes: 40,
      meanNo: 68,
      se: 3.3),
  BehaviorImpact(
      kind: BehaviorKind.journalTag,
      title: 'Meditation',
      yes: 27,
      no: 53,
      meanYes: 70,
      meanNo: 59,
      se: 3.6),
  // Not a journal entry: the report's card leaves it out.
  BehaviorImpact(
      kind: BehaviorKind.highStrain,
      title: '14+ Strain',
      yes: 9,
      no: 70,
      meanYes: 30,
      meanNo: 70,
      se: 4),
];

Future<void> _pump(WidgetTester t, Widget w, {double scale = 1}) async {
  t.view.physicalSize = Size(390 * 3, 4200 * 3 * scale);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: MaterialApp(theme: buildTheme(Brightness.dark), home: w),
  ));
  await t.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 3.1]) {
    testWidgets('the list at ${scale}x', (t) async {
      await _pump(t, ReportsScreen(series: _series(), today: _today),
          scale: scale);
      expect(find.text('Partial week'), findsOneWidget);
      expect(find.text('2 NOV - 8 NOV'), findsOneWidget);
      // Weeks file under the month they start in.
      expect(find.text('SEPTEMBER 2026'), findsOneWidget);
      await t.tap(find.text('MONTHLY'));
      await t.pumpAndSettle();
      expect(find.text('Partial month'), findsOneWidget);
    });

    testWidgets('a week at ${scale}x', (t) async {
      await _pump(
          t,
          ReportScreen(
              span: ReportSpan.week,
              day: '2026-10-26',
              series: _series(),
              today: _today,
              effects: _effects),
          scale: scale);
      expect(find.text('AVG RECOVERY'), findsOneWidget);
      expect(find.text('Alcohol'), findsOneWidget);
      expect(find.text('14+ Strain'), findsNothing);
      expect(find.text('BEST DAY'), findsOneWidget);
    });
  }

  testWidgets('a month with nothing stored shows dashes', (t) async {
    await _pump(
        t,
        const ReportScreen(
            span: ReportSpan.month,
            day: '2026-11-05',
            series: {},
            today: _today,
            effects: []));
    expect(find.text('Nothing was scored this month.'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
    expect(find.text('BEST DAY'), findsNothing);
  });
}
