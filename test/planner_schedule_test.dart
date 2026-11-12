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

    test('the first alarm is the wake time, over one typed in the planner',
        () async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      setTypedWakeMin(8 * 60, now);
      addTearDown(() => setTypedWakeMin(null, now));
      const plan = SleepPlan(usualWakeMin: 7 * 60 + 5, inBedMin: 510);
      const later = AlarmItem(id: 'b', hour: 6, minute: 45, days: {1, 2, 3, 4, 5});
      // Two alarms tomorrow: the earlier one wins.
      expect(plannedWakeMin(plan, null, items: [later, weekdays], now: now),
          6 * 60 + 17);
      expect(firstAlarmWakeMin(null, items: [later, weekdays], now: now),
          6 * 60 + 17);
      // No schedule, but the band has one armed: that is the wake time.
      final armed = (DateTime(2026, 8, 18, 5, 50), AlarmArmState.confirmed);
      expect(plannedWakeMin(plan, armed, items: const [], now: now), 5 * 60 + 50);
      // No alarm at all: the typed one stands.
      expect(plannedWakeMin(plan, null, items: const [], now: now), 8 * 60);
      // ...for that morning only. The next night it is your usual one again.
      expect(
          plannedWakeMin(plan, null,
              items: const [], now: now.add(const Duration(days: 1))),
          7 * 60 + 5);
    });

    test('a skipped morning plans to your consistent times, not the alarm',
        () async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      const plan = SleepPlan(
          usualWakeMin: 7 * 60 + 5, habitWakeMin: 6 * 60 + 40, inBedMin: 510);
      // Tuesday's ring skipped; the band already holds Wednesday's.
      final skipped = weekdays.copyWith(skipDay: '2026-08-18');
      final armed = (DateTime(2026, 8, 19, 6, 17), AlarmArmState.confirmed);
      expect(scheduledWakeMin([skipped], now), isNull);
      expect(wakeDaySkipped([skipped], now), isTrue);
      expect(firstAlarmWakeMin(armed, items: [skipped], now: now), isNull);
      expect(plannedWakeMin(plan, armed, items: [skipped], now: now),
          6 * 60 + 40);
      // A band alarm for a later morning is not this night's either.
      expect(armedWakeMin(armed, now), isNull);
      // Wednesday night it rings again.
      final wed = DateTime(2026, 8, 18, 20);
      expect(plannedWakeMin(plan, armed, items: [skipped], now: wed),
          6 * 60 + 17);
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

    // The timeline slides under a finger, a little, and springs back to the
    // time in bed centred.
    final home = t.getCenter(find.text('TIME IN BED'));
    final g = await t.startGesture(home);
    await g.moveBy(const Offset(400, 0));
    await t.pump();
    final pulled = t.getCenter(find.text('TIME IN BED')).dx - home.dx;
    expect(pulled, greaterThan(0));
    expect(pulled, lessThanOrEqualTo(S.x16), reason: 'it gives, then stops');
    await g.up();
    await t.pumpAndSettle();
    expect(t.getCenter(find.text('TIME IN BED')).dx, closeTo(home.dx, .5));
  });
}
