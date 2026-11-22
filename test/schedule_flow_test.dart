// CREATE SCHEDULE: days, then the alarm mode, then the wake time, and what it
// hands back. A schedule with no alarm only says when you wake: it is never
// armed, and the planner still plans to it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/alarm_item.dart';
import 'package:openstrap_edge/state/alarm_mode.dart';
import 'package:openstrap_edge/ui2/profile/schedule_flow.dart';
import 'package:openstrap_edge/ui2/screens/sleep_planner.dart'
    show scheduledWakeMin;
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

Future<AlarmItem?> _run(WidgetTester t,
    Future<void> Function(WidgetTester) steps) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  AlarmItem? got;
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: Builder(
        builder: (c) => TextButton(
          onPressed: () async => got = await AppSheet.open<AlarmItem>(c,
              bare: true,
              scroll: true,
              builder: (_) => const ScheduleFlowSheet()),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  await steps(t);
  await t.pumpAndSettle();
  return got;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('days, a mode and a time make a schedule', (t) async {
    final item = await _run(t, (t) async {
      // NEXT does nothing until a day is chosen.
      await t.tap(find.text('NEXT'));
      await t.pumpAndSettle();
      expect(find.text('SELECT DAYS WITH REPEAT WAKE TIMES'), findsOneWidget);
      await t.tap(find.text('M'));
      await t.tap(find.text('F'));
      await t.pumpAndSettle();
      await t.tap(find.text('NEXT'));
      await t.pumpAndSettle();
      await t.tap(find.text('SLEEP GOAL'));
      await t.pumpAndSettle();
      expect(find.text('SET YOUR WAKE TIME'), findsOneWidget);
      await t.tap(find.text('SAVE'));
    });
    expect(item, isNotNull);
    expect(item!.days, {1, 5});
    expect(item.mode, AlarmMode.sleepGoal);
    expect(item.ring, isTrue);
    expect((item.hour, item.minute), (7, 0));
  });

  testWidgets("no alarm saves a wake time that never rings", (t) async {
    final item = await _run(t, (t) async {
      await t.tap(find.text('T').first);
      await t.pumpAndSettle();
      await t.tap(find.text('NEXT'));
      await t.pumpAndSettle();
      await t.tap(find.text("DON'T USE AN ALARM"));
      await t.pumpAndSettle();
      await t.tap(find.text('SAVE'));
    });
    expect(item!.ring, isFalse);
    // Never armed: it has no next ring...
    expect(item.nextOccurrence(DateTime(2026, 11, 23, 22)), isNull);
    // ...but the planner wakes you at it (Tuesday 24 Nov, planned the
    // evening before), and it survives a round trip through storage.
    expect(scheduledWakeMin([item], DateTime(2026, 11, 23, 22)), 7 * 60);
    final back = AlarmItem.decodeList(AlarmItem.encodeList([item])).single;
    expect(back.ring, isFalse);
  });
}
