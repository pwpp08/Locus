// A nap is drawn from what was measured: its window, the minutes asleep in
// it, the heart rate and the wrist's movement. The pipeline stores no nap
// stages, so none are drawn — this screen used to script a 40 % deep / 10 %
// REM split, invent a 16.4 rpm breathing rate and print "within 0:00-0:00 min"
// ranges nothing had computed. These tests pin that none of it comes back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/nap_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

final _start = DateTime(2025, 5, 7, 14, 0).millisecondsSinceEpoch ~/ 1000;
final _end = _start + 62 * 60;

NapDetailData _fixture({
  int? asleep = 52,
  bool movement = true,
  bool hr = true,
}) =>
    NapDetailData(
      day: '2025-05-07',
      start: _start,
      end: _end,
      asleepMin: asleep,
      source: 'manual',
      from: _start - 300,
      to: _end + 300,
      hr: hr
          ? [for (var t = _start - 300; t <= _end + 300; t += 60) (t: t, v: 58.0 + (t ~/ 60) % 7)]
          : const [],
      avgHr: hr ? 61 : null,
      lowHr: hr ? 55 : null,
      movement: movement
          ? [for (var t = _start; t < _end; t += 60) (t: t, span: 60, v: (t ~/ 60) % 5 / 10)]
          : const [],
    );

Future<void> _pump(WidgetTester t, NapDetailData d) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: NapDetailScreen(
      nap: {'start': d.start, 'end': d.end, 'duration_min': d.asleepMin},
      data: d,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the window, the time asleep and the measured statistics',
      (t) async {
    await _pump(t, _fixture());
    expect(find.text('NAP'), findsOneWidget);
    expect(find.textContaining('May 7, 2025'), findsOneWidget);
    expect(find.text('0:52'), findsWidgets);
    expect(find.text('TIME ASLEEP'), findsOneWidget);
    expect(find.text('KEY STATISTICS'), findsOneWidget);
    expect(find.text('IN BED'), findsOneWidget);
    expect(find.text('1:02'), findsOneWidget);
    expect(find.text('AVG HR'), findsOneWidget);
    expect(find.text('61'), findsOneWidget);
    expect(find.text('LOWEST HR'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
    expect(find.text('MOVING'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('nothing the pipeline does not measure is drawn', (t) async {
    await _pump(t, _fixture());
    for (final gone in [
      'LIGHT', 'SWS (DEEP)', 'REM', 'RESTORATIVE SLEEP', 'TYPICAL RANGE',
      'WAKE EVENTS', 'EFFICIENCY', 'RESPIRATORY RATE', 'LATENCY',
      'VS. 30 DAY RANGE',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    // The raw nap minutes are not the reduction the sleep coach takes.
    expect(find.textContaining('reduced your sleep need'), findsNothing);
  });

  testWidgets('absent figures are a dash, never a stand-in', (t) async {
    await _pump(t, _fixture(asleep: null, hr: false, movement: false));
    // Time asleep (hero and card), avg HR and lowest HR.
    expect(find.text('--'), findsNWidgets(4));
    // No movement measured: no "moving" figure built from nothing.
    expect(find.text('MOVING'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a finger reads the heart rate and the movement under it',
      (t) async {
    await _pump(t, _fixture());
    final chart = find.byType(Scrubber);
    await t.startGesture(t.getCenter(chart));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('bpm'), findsWidgets);
    expect(find.text('moving'), findsOneWidget);
  });

  testWidgets('the more menu shows Edit, Delete, Convert to Sleep',
      (t) async {
    await _pump(t, _fixture());
    await t.tap(find.bySemanticsLabel('More'));
    await t.pumpAndSettle();
    expect(find.text('EDIT NAP'), findsOneWidget);
    expect(find.text('DELETE NAP'), findsOneWidget);
    expect(find.text('CONVERT TO SLEEP'), findsOneWidget);
  });
}
