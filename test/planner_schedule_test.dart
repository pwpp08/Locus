// The Sleep Planner, My Schedule, the alarm-mode sheet and the recovery
// calendar: what each shows and what a tap on it does.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/models/alarm_item.dart';
import 'package:openstrap_edge/state/alarm_mode.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';
import 'package:openstrap_edge/ui2/screens/alarm_mode_sheet.dart';
import 'package:openstrap_edge/ui2/screens/recovery_calendar.dart';
import 'package:openstrap_edge/ui2/screens/sleep_planner.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> settle(WidgetTester t, {int n = 10}) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
  }

  void tall(WidgetTester t) {
    t.view.physicalSize = const Size(390 * 2, 1000 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
  }

  group('the wake time the planner plans to', () {
    // A Monday, 20:00: the next wake day is Tuesday.
    final now = DateTime(2026, 8, 17, 20);
    const weekdays = AlarmItem(
        id: 'a', hour: 6, minute: 17, days: {1, 2, 3, 4, 5});

    test('a schedule that covers tomorrow gives its time', () {
      expect(scheduledWakeMin([weekdays], now), 6 * 60 + 17);
    });

    test('before midday it is today\'s', () {
      expect(scheduledWakeMin([weekdays], DateTime(2026, 8, 17, 7)), 6 * 60 + 17);
      // A Sunday morning is not covered.
      expect(scheduledWakeMin([weekdays], DateTime(2026, 8, 16, 7)), isNull);
    });

    test('an unscheduled day falls back to the usual wake time, alarm off', () {
      // Friday night: tomorrow is Saturday.
      expect(scheduledWakeMin([weekdays], DateTime(2026, 8, 21, 20)), isNull);
      SharedPreferences.setMockInitialValues({});
      return Prefs.ensureLoaded().then((_) {
        const plan = SleepPlan(usualWakeMin: 7 * 60 + 5, inBedMin: 510);
        expect(
            plannedWakeMin(plan, null,
                items: [weekdays], now: DateTime(2026, 8, 21, 20)),
            7 * 60 + 5);
        expect(plannedWakeMin(plan, null, items: [weekdays], now: now),
            6 * 60 + 17);
      });
    });

    test('a disabled alarm does not count', () {
      expect(
          scheduledWakeMin([weekdays.copyWith(enabled: false)], now), isNull);
    });
  });

  testWidgets('the mode sheet returns the mode tapped', (t) async {
    tall(t);
    AlarmMode? picked;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
              onPressed: () async => picked = await openAlarmModeSheet(c),
              child: const Text('open')),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await settle(t);
    expect(find.text('Choose your alarm mode'), findsOneWidget);
    expect(find.text('EXACT TIME'), findsOneWidget);
    expect(find.text('SLEEP GOAL'), findsOneWidget);
    expect(find.text('IN THE GREEN'), findsOneWidget);
    await t.tap(find.text('IN THE GREEN'));
    await settle(t);
    expect(picked, AlarmMode.inTheGreen);
  });

  testWidgets('the calendar colours days by recovery and opens a day',
      (t) async {
    tall(t);
    final today = DateTime(2026, 8, 17);
    String id(int d) => dayLabelOf(DateTime(2026, 8, d));
    String? picked;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
              onPressed: () async => picked = await openRecoveryCalendar(c,
                  today: dayLabelOf(today),
                  selected: dayLabelOf(today),
                  recovery: {id(3): 20, id(4): 50, id(5): 90},
                  days: {id(3), id(4), id(5), id(17)}),
              child: const Text('open')),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await settle(t);
    expect(find.text('AUGUST 2026'), findsOneWidget);
    Color colourOf(String day) =>
        t.widget<Text>(find.text(day).first).style!.color!;
    expect(colourOf('3'), C.recRed);
    expect(colourOf('4'), C.recYellow);
    expect(colourOf('5'), C.recGreen);
    // A day with no score is grey, and cannot be opened.
    expect(colourOf('6'), isNot(C.recGreen));
    await t.tap(find.text('6'));
    await settle(t);
    expect(picked, isNull);
    expect(find.text('AUGUST 2026'), findsOneWidget);
    await t.tap(find.text('5'));
    await settle(t);
    expect(picked, id(5));
  });

  testWidgets('My Schedule lists the alarms, their mode, and unscheduled days',
      (t) async {
    tall(t);
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.alarmManager.debugSetAlarms(const [
      AlarmItem(
          id: 'a',
          hour: 6,
          minute: 17,
          days: {1, 2, 3, 4, 5},
          mode: AlarmMode.sleepGoal),
    ]);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: ChangeNotifierProvider<AppState>.value(
          value: app, child: const AlarmScreen()),
    ));
    await settle(t);
    expect(find.text('MY SCHEDULE'), findsOneWidget);
    expect(find.text('MON'), findsOneWidget);
    expect(find.text('FRI'), findsOneWidget);
    expect(find.text('SAT'), findsNothing);
    expect(find.text('SLEEP GOAL'), findsOneWidget);
    expect(find.text('CREATE SCHEDULE'), findsOneWidget);
    expect(find.text('You have unscheduled days'), findsOneWidget);

    // Covering every day takes the warning away.
    app.alarmManager.debugSetAlarms(const [
      AlarmItem(id: 'a', hour: 6, minute: 17, days: {1, 2, 3, 4, 5, 6, 7}),
    ]);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: ChangeNotifierProvider<AppState>.value(
          value: app, child: const AlarmScreen()),
    ));
    await settle(t);
    expect(find.text('You have unscheduled days'), findsNothing);
  });

  testWidgets('the planner shows the night, and says when it cannot plan',
      (t) async {
    tall(t);
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: ChangeNotifierProvider<AppState>.value(
          value: app, child: const SleepPlannerScreen()),
    ));
    await settle(t);
    expect(find.text('SLEEP PLANNER'), findsOneWidget);
    expect(find.text('SUGGESTED\nTIME TO BED'), findsOneWidget);
    expect(find.text('YOUR\nWAKE TIME'), findsOneWidget);
    expect(find.text('TIME IN BED'), findsOneWidget);
    expect(find.text('OPTIMAL'), findsOneWidget);
    expect(find.text('ALARM SET TO'), findsOneWidget);
    expect(find.text('WAKE TIME SET TO'), findsOneWidget);
    // No sleep need on record: no invented times, dashes.
    expect(find.text('OFF'), findsWidgets);
    expect(find.textContaining('learn your sleep need'), findsOneWidget);
  });
}
