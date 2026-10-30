// My Dashboard: each metric is a slim row or, if the user chooses, its week
// in full — Trend View's W range on Home, with no range switch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/home/home_dashboard_editor.dart';
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

  testWidgets('a chosen metric is drawn as its week; the rest stay rows',
      (t) async {
    String? opened;
    await _pump(
      t,
      DashboardRows(
        ids: const ['hrv', 'resting_hr'],
        expanded: const {'hrv'},
        today: _today,
        daily: {
          'hrv': _days((i) => 60.0 + i),
          'resting_hr': _days((i) => 54.0),
        },
        onOpen: (k) => opened = k,
      ),
    );
    expect(find.byType(ExpandedTrendCard), findsOneWidget);
    expect(find.text('HEART RATE VARIABILITY'), findsOneWidget);
    expect(find.byType(ScrubLine), findsOneWidget);
    // Always this week: no range switch on Home.
    expect(find.byType(RangeSegments), findsNothing);
    expect(find.text('AVERAGE'), findsOneWidget);
    // Its header is the door into Trend View.
    await t.tap(find.text('HEART RATE VARIABILITY'));
    expect(opened, 'hrv');
  });

  testWidgets('a weekly metric reads as the week\'s total', (t) async {
    await _pump(
      t,
      ExpandedTrendCard(
        m: trendMetricOf('zones_13')!,
        today: _today,
        daily: _days((i) => 30.0),
        onOpen: () {},
      ),
    );
    // 7 × 30 minutes; the week before was the same, so no change to show.
    expect(find.text('WEEKLY TOTAL'), findsOneWidget);
    expect(find.text('3:30'), findsOneWidget);
    expect(find.byType(ScrubColumns), findsOneWidget);
  });

  testWidgets('the editor saves which metrics are expanded', (t) async {
    DashboardChoice? got;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                got = await Navigator.of(c).push<DashboardChoice>(
                  MaterialPageRoute(
                    builder: (_) => const Scaffold(
                      body: HomeDashboardEditor(
                          selected: ['strain_recovery', 'hrv', 'steps']),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel(
        RegExp('Heart rate variability shown as a row')));
    await t.pump();
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();
    expect(got?.tiles, ['strain_recovery', 'hrv', 'steps']);
    expect(got?.expanded, {'hrv'});
  });
}
