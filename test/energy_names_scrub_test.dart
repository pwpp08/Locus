// Energy reserve: each stretch of effort says which activity it was, and the
// chart reads a finger like the heart rate charts do.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/energy_reserve.dart';
import 'package:openstrap_edge/models/activity_suggestion.dart';
import 'package:openstrap_edge/ui2/screens/home/home_energy.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

const _midnight = 1760000000 ~/ 86400 * 86400;

EnergyReserve _reserve() => EnergyReserve(
      level: 55,
      wokeLevel: 80,
      wokeTs: _midnight + 7 * 3600,
      charged: 4,
      drained: 29,
      points: [
        for (var h = 7; h <= 15; h++)
          (_midnight + h * 3600, 80.0 - (h - 7) * 3),
      ],
      activities: [
        EnergyEvent(_midnight + 9 * 3600, -12),
        EnergyEvent(_midnight + 13 * 3600, -9),
        EnergyEvent(_midnight + 14 * 3600, -5),
      ],
    );

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an effort inside a session is named, with how it got there', () {
    final named = nameEnergyEvents(
      _reserve().activities,
      [
        {
          'type': 'running',
          'start_ts': _midnight + 9 * 3600 - 60,
          'end_ts': _midnight + 9 * 3600 + 1800,
          'source': 'manual',
        },
      ],
      [
        ActivitySuggestion(
          id: 'd1',
          kind: ActivityKind.workout,
          startTs: _midnight + 13 * 3600,
          endTs: _midnight + 13 * 3600 + 1200,
          revision: 1,
          details: const {'sport': 'cycling'},
        ),
      ],
    );
    expect(named[0].origin, 'Added later');
    expect(named[0].name, isNotNull);
    expect(named[1].origin, 'Found by your band');
    // Effort no activity explains stays unnamed rather than guessed.
    expect(named[2].name, isNull);
    expect(named[2].origin, isNull);
  });

  testWidgets('holding the chart reads the time and the reserve there',
      (t) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child:
              EnergyReserveCard(data: _reserve(), midnight: _midnight),
        ),
      ),
    ));
    await t.pumpAndSettle();
    final chart = find.byType(Scrubber);
    expect(chart, findsOneWidget);
    final box = t.getRect(chart);
    final g = await t.startGesture(Offset(box.left + box.width * .5,
        box.center.dy));
    await t.pump(const Duration(milliseconds: 50));
    await g.moveBy(const Offset(4, 0));
    await t.pump();
    // The readout is a percentage and a clock time while the finger is down.
    expect(find.textContaining('%'), findsWidgets);
    await g.up();
    await t.pump();
  });
}
