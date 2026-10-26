// A workout's screen and the day's heart rate, from My Day.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/screens/day_heart.dart';
import 'package:openstrap_edge/ui2/screens/workout_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

WorkoutDetail _detail() {
  final start = DateTime(2026, 10, 26, 7, 21).millisecondsSinceEpoch ~/ 1000;
  final end = start + 640;
  final from = start - 60, to = end + 60;
  final hr = <({int t, double v})>[];
  for (var t = from; t <= to; t += 5) {
    final f = (t - start) / 640;
    final v = f < 0
        ? 85.0
        : f < .45
            ? 90 + 60 * math.sin(f * 3.4) + 4 * math.sin(t / 7)
            : f < .55
                ? 100 + 4 * math.sin(t / 5)
                : 150 + 5 * math.sin(t / 9);
    hr.add((t: t, v: v));
  }
  final lo = [112, 139, 152, 165, 178];
  int zoneOf(double v) {
    for (var i = 4; i >= 0; i--) {
      if (v >= lo[i]) return i;
    }
    return -1;
  }

  final sec = [0, 0, 0, 0, 0];
  final runs = <List<(int, int)>>[[], [], [], [], []];
  for (final e in hr) {
    if (e.t < start || e.t >= end) continue;
    final z = zoneOf(e.v);
    if (z < 0) continue;
    sec[z] += 5;
    final r = runs[z];
    if (r.isNotEmpty && e.t - r.last.$2 <= 5) {
      r[r.length - 1] = (r.last.$1, e.t + 5);
    } else {
      r.add((e.t, e.t + 5));
    }
  }
  final pts = [
    for (var i = 0; i < 40; i++)
      RoutePoint(
          seq: i,
          tsMs: (start + i * 16) * 1000,
          lat: 47.885 - i * .001 + .0003 * math.sin(i),
          lng: 17.26 + i * .0002,
          alt: 120 + (i % 10).toDouble()),
  ];
  return WorkoutDetail(
    id: 'x',
    type: 'Cycling',
    activity: activityByName('Cycling')!,
    start: start,
    end: end,
    strain: 5.6,
    calories: 79,
    avgHr: 129,
    maxHr: 157,
    hr: hr,
    from: from,
    to: to,
    zoneLo: lo,
    zoneSec: sec,
    zoneRuns: runs,
    avg: const SportAverage(
        strain: 6.9,
        calories: 115,
        avgHr: 139,
        maxHr: 167,
        durationSec: 713,
        typical: [(.15, .2), (.15, .3), (.3, .42), null, null]),
    route: WorkoutRoute(
        sessionId: 'x',
        points: pts,
        hr: const [],
        distanceMeters: 4430,
        movingSec: 640,
        splitsKm: const [],
        splitsMi: const []),
    count: 40,
  );
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('marks closer than the gap share one group, in order', () {
    final g = clusterMarks([100.0, 10.0, 30.0, 200.0, 215.0], (x) => x, gap: 40);
    expect(g, [
      [10.0, 30.0],
      [100.0],
      [200.0, 215.0],
    ]);
  });

  testWidgets('a zone lights its own stretches; an unreached one is inert',
      (t) async {
    t.view.physicalSize = const Size(390 * 2, 2600 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: WorkoutDetailScreen(session: const {}, data: _detail()),
    ));
    await t.pumpAndSettle();
    expect(find.text('5.6'), findsOneWidget);
    expect(find.text('ACTIVITY STRAIN'), findsOneWidget);
    expect(find.text('178+ BPM'), findsOneWidget);
    expect(find.text('ROUTE'), findsOneWidget);
    expect(find.text('4.43'), findsOneWidget);
    expect(find.text('10 more until your next milestone'), findsOneWidget);
    // Zone 3 opens; zone 5 was never reached and is not a door.
    expect(find.bySemanticsLabel(RegExp('^Zone 3')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Zone 5')), findsNothing);
    await t.tap(find.text('ZONE 3'));
    await t.pumpAndSettle();
    await t.tap(find.text('ZONE 3'));
    await t.pumpAndSettle();
  });

  testWidgets('a finger on the chart reads the minute; two fingers zoom it',
      (t) async {
    t.view.physicalSize = const Size(390 * 2, 2600 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: WorkoutDetailScreen(session: const {}, data: _detail()),
    ));
    await t.pumpAndSettle();
    final chart = find.byType(Scrubber).first;
    final c = t.getCenter(chart);

    // A touch swaps the strain for the reading under it, and lifting restores it.
    // (Two key figures carry a bpm of their own.)
    final unit = t.widgetList(find.text('bpm')).length;
    final g = await t.startGesture(c + const Offset(20, 0));
    await t.pump();
    expect(find.text('bpm'), findsNWidgets(unit + 1));
    expect(find.text('ACTIVITY STRAIN'), findsNothing);
    await g.up();
    await t.pump();
    expect(find.text('bpm'), findsNWidgets(unit));
    expect(find.text('ACTIVITY STRAIN'), findsOneWidget);

    // Spread two fingers: zoomed, with a way back.
    expect(find.text('RESET'), findsNothing);
    final a = await t.startGesture(c - const Offset(20, 0));
    final b = await t.startGesture(c + const Offset(20, 0), pointer: 8);
    await a.moveBy(const Offset(-60, 0));
    await b.moveBy(const Offset(60, 0));
    await a.up();
    await b.up();
    await t.pump();
    expect(find.text('RESET'), findsOneWidget);
    await t.tap(find.text('RESET'));
    await t.pump();
    expect(find.text('RESET'), findsNothing);
  });

  testWidgets('a workout with no route draws no map', (t) async {
    final d = _detail();
    final bare = WorkoutDetail(
        id: d.id,
        type: d.type,
        activity: d.activity,
        start: d.start,
        end: d.end,
        from: d.from,
        to: d.to);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: WorkoutDetailScreen(session: const {}, data: bare),
    ));
    await t.pumpAndSettle();
    expect(find.text('ROUTE'), findsNothing);
    expect(find.text('--'), findsWidgets);
  });

  testWidgets('activities too close together show as a count', (t) async {
    t.view.physicalSize = const Size(844 * 2, 390 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    int at(int h, int m) =>
        DateTime(2026, 10, 26, h, m).millisecondsSinceEpoch ~/ 1000;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: DayHeartScreen(
        day: '2026-10-26',
        sessions: [
          {'type': 'Running', 'start_ts': at(15, 30), 'end_ts': at(16, 50), 'strain': 13.6},
          {'type': 'Gardening', 'start_ts': at(16, 55), 'end_ts': at(17, 10), 'strain': 3.0},
          {'type': 'Cycling', 'start_ts': at(9, 0), 'end_ts': at(9, 30), 'strain': 6.8},
        ],
        strain: 18.5,
        hr: (a, b) async => const [],
        now: DateTime(2026, 10, 26, 23),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byType(MarkCount), findsOneWidget);
    expect(find.text('6.8'), findsOneWidget);
    expect(find.text('13.6'), findsNothing);
    expect(find.text('18.5'), findsOneWidget);
  });
}
