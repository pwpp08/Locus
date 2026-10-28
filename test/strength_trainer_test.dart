// The plus menu and the strength trainer: the four doors, the two tabs, the
// volume chart and its switch, the records list, the workouts list, and the
// workout editor's table of sets.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/strength_stats.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/strength_store.dart';
import 'package:openstrap_edge/ui2/screens/plus_menu.dart';
import 'package:openstrap_edge/ui2/screens/strength_record.dart';
import 'package:openstrap_edge/ui2/screens/strength_trainer.dart';
import 'package:openstrap_edge/ui2/screens/strength_workout.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: buildTheme(Brightness.dark), home: home);

int _daysAgo(int n) {
  final d = DateTime.now();
  return DateTime(d.year, d.month, d.day - n, 10).millisecondsSinceEpoch ~/ 1000;
}

LoggedRow _set(String s, String k, int reps, double? kg, int ts) =>
    (session: s, key: k, reps: reps, kg: kg, ts: ts);

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the plus menu offers four doors and hands one back', (t) async {
    t.view.physicalSize = const Size(411 * 2, 890 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    PlusChoice? got;
    await t.pumpWidget(_app(Scaffold(
      body: Builder(
        builder: (c) => Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 400, right: 20),
            child: PlusButton(
              onTap: () async => got = await showPlusMenu(
                  c, const Rect.fromLTWH(347, 400, 44, 44)),
            ),
          ),
        ),
      ),
    )));
    await t.tap(find.byType(PlusButton));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('START ACTIVITY'), findsOneWidget);
    expect(find.text('ADD ACTIVITY'), findsOneWidget);
    expect(find.text('STRENGTH TRAINER'), findsOneWidget);
    expect(find.text('ADD TO MY JOURNAL'), findsOneWidget);
    // The button is a cross while it is open.
    expect(find.bySemanticsLabel('Close the menu'), findsWidgets);
    await t.tap(find.text('STRENGTH TRAINER'));
    await t.pumpAndSettle();
    expect(got, PlusChoice.strength);
  });

  testWidgets('progress: volume, its switch, and the records', (t) async {
    t.view.physicalSize = const Size(411 * 2, 1800 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final rows = [
      _set('a', 'bench_press', 10, 100, _daysAgo(0)), // 1,000 this week
      _set('a', 'bench_press', 8, 80, _daysAgo(0)), //     640
      _set('b', 'bench_press', 5, 90, _daysAgo(40)),
      _set('a', 'fx:Pullups', 6, null, _daysAgo(0)),
    ];
    await t.pumpWidget(_app(StrengthTrainerScreen(
      data: (rows: rows, typed: const [], workouts: const []),
    )));
    await t.pump();
    expect(find.text('STRENGTH TRAINER'), findsOneWidget);
    expect(find.text('PROGRESS'), findsOneWidget);
    expect(find.text('MY WORKOUTS'), findsOneWidget);
    // No third tab.
    expect(find.textContaining('WORKOUTS'), findsNWidgets(1));
    expect(find.text('Total Volume Load'), findsOneWidget);
    expect(find.text('AVG VOLUME LOAD'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('6M'), findsOneWidget);
    // The month shows weeks; one has 1,640 kg, so the mean is over the ones
    // that have a figure: just that one.
    expect(find.text('1,640'), findsOneWidget);
    await t.tap(find.text('W'));
    await t.pump();
    expect(find.text('1,640'), findsOneWidget,
        reason: 'the week has one day with sets, 1,640 kg');
    await t.tap(find.text('6M'));
    await t.pump();
    expect(find.text('AVG VOLUME LOAD'), findsOneWidget);

    // Records, from the logged sets: a load, and reps for the bodyweight lift.
    await t.scrollUntilVisible(find.text('Personal Records'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Personal Records'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('kg'), findsWidgets);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('reps'), findsOneWidget);
  });

  testWidgets('my workouts: start, build, and the list', (t) async {
    t.view.physicalSize = const Size(411 * 2, 1800 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final w = StrengthWorkout.fresh('Push', const [
      PlannedExercise('bench_press', [PlannedSet(8, 60)]),
    ]);
    await t.pumpWidget(_app(StrengthTrainerScreen(
      tab: 1,
      data: (rows: const [], typed: const [], workouts: [w]),
    )));
    await t.pump();
    expect(find.text('Start a Workout'), findsOneWidget);
    expect(find.text('QUICK START'), findsOneWidget);
    expect(find.text('My Workouts'), findsOneWidget);
    expect(find.text('Generate with AI'), findsOneWidget);
    expect(find.text('GET STARTED'), findsOneWidget);
    expect(find.text('BUILD A WORKOUT'), findsOneWidget);
    expect(find.text('PUSH'), findsOneWidget);
  });

  testWidgets('the editor: open a card, add a set, edit a load', (t) async {
    t.view.physicalSize = const Size(411 * 2, 1800 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final w = StrengthWorkout.fresh('Push', const [
      PlannedExercise('bench_press', [PlannedSet(8, 60), PlannedSet(8, 60)]),
      PlannedExercise('incline_db_press', [PlannedSet(10, 20)]),
    ]);
    await t.pumpWidget(_app(StrengthWorkoutScreen(workout: w)));
    await t.pump();
    expect(find.text('PUSH'), findsOneWidget);
    expect(find.text('2 Sets'), findsOneWidget);
    expect(find.text('1 Set'), findsOneWidget);
    expect(find.text('ADD EXERCISE'), findsOneWidget);
    expect(find.text('START WORKOUT'), findsOneWidget);
    expect(find.text('REPS'), findsNothing);

    await t.tap(find.text('Bench press'));
    await t.pump();
    expect(find.text('REPS'), findsOneWidget);
    expect(find.text('WEIGHT (kg)'), findsOneWidget);
    expect(find.text('ADD SET'), findsOneWidget);

    await t.tap(find.text('ADD SET'));
    await t.pump();
    expect(find.text('3 Sets'), findsOneWidget);
    // A new set starts from the last one.
    expect(find.text('60'), findsNWidgets(3));

    await t.enterText(find.byType(TextFormField).at(1), '62.5');
    await t.pump();
    expect(find.text('62.5'), findsOneWidget);

    await t.tap(find.bySemanticsLabel('Remove set 3'));
    await t.pump();
    expect(find.text('2 Sets'), findsOneWidget);
  });

  testWidgets('a record: the figure, its progress, and the way to change it',
      (t) async {
    t.view.physicalSize = const Size(411 * 2, 1800 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final rows = [
      _set('a', 'bench_press', 8, 70, _daysAgo(30)),
      _set('b', 'bench_press', 8, 75, _daysAgo(20)),
      _set('c', 'bench_press', 5, 82.5, _daysAgo(2)),
    ];
    await t.pumpWidget(_app(StrengthRecordScreen(
      exerciseKey: 'bench_press',
      data: (rows: rows, typed: const []),
    )));
    await t.pump();
    await t.pump();
    expect(find.text('PERSONAL RECORD'), findsOneWidget);
    expect(find.text('82.5'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(find.byType(ScrubLine), findsOneWidget);
    expect(find.text('CHANGE THE RECORD'), findsOneWidget);
    expect(find.text('Remove the number I typed'), findsNothing);
  });

  testWidgets('a lift with one session draws no chart yet', (t) async {
    t.view.physicalSize = const Size(411 * 2, 1800 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(StrengthRecordScreen(
      exerciseKey: 'bench_press',
      data: (rows: [_set('a', 'bench_press', 8, 70, _daysAgo(3))], typed: const []),
    )));
    await t.pump();
    await t.pump();
    expect(find.byType(ScrubLine), findsNothing);
    expect(find.textContaining('two sessions'), findsOneWidget);
  });

  test('kilograms are grouped by thousands', () {
    expect(groupedKg(1846), '1,846');
    expect(groupedKg(950), '950');
    expect(groupedKg(1234567), '1,234,567');
    expect(todayLabel(), isNotEmpty);
  });
}
