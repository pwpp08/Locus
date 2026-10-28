import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/nap_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

NapDetailData _fixture() {
  final start = DateTime(2025, 5, 7, 15, 12).millisecondsSinceEpoch ~/ 1000;
  final end = DateTime(2025, 5, 7, 17, 19).millisecondsSinceEpoch ~/ 1000;
  final from = start - 60;
  final to = end + 60;

  final hr = <({int t, double v})>[
    for (var t = from; t <= to; t += 30)
      (t: t, v: 62.0 + (t % 15)),
  ];

  final runs = [
    NapStageRun(start: start, end: start + 300, stage: SleepStage.awake),
    NapStageRun(start: start + 300, end: start + 1740, stage: SleepStage.light),
    NapStageRun(start: start + 1740, end: start + 3120, stage: SleepStage.deep),
    NapStageRun(start: start + 3120, end: start + 3420, stage: SleepStage.rem),
    NapStageRun(start: start + 3420, end: end, stage: SleepStage.awake),
  ];

  return NapDetailData(
    day: '2025-05-07',
    start: start,
    end: end,
    durationMin: 52,
    inBedMin: 127,
    efficiency: 41.0,
    wakeEventsPerHour: 0.9,
    respiratoryRate: 16.4,
    latencyMin: 0.0,
    source: 'manual',
    from: from,
    to: to,
    hr: hr,
    stageRuns: runs,
    stageSec: const {
      SleepStage.awake: 75 * 60,
      SleepStage.light: 24 * 60,
      SleepStage.deep: 23 * 60,
      SleepStage.rem: 5 * 60,
    },
    typicalStage: const {
      SleepStage.awake: (0.15, 0.40),
      SleepStage.light: (0.20, 0.45),
      SleepStage.deep: (0.20, 0.40),
      SleepStage.rem: (0.02, 0.15),
    },
    avgDurationMin: 55,
    avgRestorativeMin: 32,
    avgWakeEvents: 1.2,
    avgEfficiency: 53.0,
    avgRespRate: 16.5,
    avgLatency: 0.0,
  );
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('NapDetailScreen renders all core sections and 4 nap metric cards',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final d = _fixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: NapDetailScreen(
          nap: {
            'start': d.start,
            'end': d.end,
            'duration_min': d.durationMin,
            'source': 'manual',
          },
          data: d,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Header checks
    expect(find.text('NAP'), findsOneWidget);
    expect(find.textContaining('May 7, 2025'), findsOneWidget);

    // 2. Readout metrics
    expect(find.text('HOURS OF SLEEP'), findsOneWidget);
    expect(find.text('RESTORATIVE SLEEP'), findsOneWidget);
    expect(find.text('This nap reduced your sleep need by 52 minutes.'),
        findsOneWidget);

    // 3. Stage sections
    expect(find.text('TYPICAL RANGE'), findsOneWidget);
    expect(find.text('AWAKE'), findsOneWidget);
    expect(find.text('LIGHT'), findsOneWidget);
    expect(find.text('SWS (DEEP)'), findsOneWidget);
    expect(find.text('REM'), findsOneWidget);

    // 4. Nap Metrics section with the 4 cards on bottom
    expect(find.text('NAP METRICS'), findsOneWidget);
    expect(find.text('VS. 30 DAY RANGE'), findsOneWidget);

    // Wake Events card
    expect(find.text('WAKE EVENTS'), findsOneWidget);
    expect(find.text('0.9'), findsOneWidget);
    expect(find.text('per hour'), findsOneWidget);
    expect(find.text('low < 1.2 per hour'), findsOneWidget);

    // Efficiency card
    expect(find.text('EFFICIENCY'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('low < 53 %'), findsOneWidget);

    // Respiratory Rate card
    expect(find.text('RESPIRATORY RATE'), findsOneWidget);
    expect(find.text('16.4'), findsOneWidget);
    expect(find.text('rpm'), findsOneWidget);
    expect(find.text('low < 16.5 rpm'), findsOneWidget);

    // Latency card
    expect(find.text('LATENCY'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('within 0:00-0:00 min'), findsOneWidget);
  });

  testWidgets('NapDetailScreen more menu shows Edit, Delete, Convert to Sleep',
      (tester) async {
    final d = _fixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: NapDetailScreen(
          nap: {
            'start': d.start,
            'end': d.end,
            'duration_min': d.durationMin,
            'source': 'manual',
          },
          data: d,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap more button
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Nap'), findsOneWidget);
    expect(find.text('Delete Nap'), findsOneWidget);
    expect(find.text('Convert to Sleep'), findsOneWidget);
  });

  testWidgets('NapDetailScreen tapping stage highlights stage', (tester) async {
    final d = _fixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: NapDetailScreen(
          nap: {
            'start': d.start,
            'end': d.end,
            'duration_min': d.durationMin,
            'source': 'manual',
          },
          data: d,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap light stage card
    await tester.tap(find.text('LIGHT'));
    await tester.pumpAndSettle();

    // Tap again to toggle off
    await tester.tap(find.text('LIGHT'));
    await tester.pumpAndSettle();
  });
}
