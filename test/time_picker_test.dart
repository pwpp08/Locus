// Picking a time: two columns, hours and minutes, that scroll up and down.
// No clock face, and the user's 12/24-hour choice decides how hours read.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/clock_format.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  tearDown(ClockFormatController.debugReset);

  /// Opens the picker from a button and returns what it eventually answers.
  Future<Future<TimeOfDay?> Function()> open(
      WidgetTester t, TimeOfDay initial) async {
    TimeOfDay? answer;
    var closed = false;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () async {
              answer = await pickTime(c, initial: initial, title: 'Alarm time');
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return () async => closed ? answer : null;
  }

  void jump(WidgetTester t, int wheel, int item) {
    final w = t.widget<ListWheelScrollView>(
        find.byType(ListWheelScrollView).at(wheel));
    (w.controller as FixedExtentScrollController).jumpToItem(item);
  }

  testWidgets('opens on the given time and answers with it', (t) async {
    ClockFormatController.seed(ClockFormat.h24);
    final result = await open(t, const TimeOfDay(hour: 6, minute: 45));
    expect(find.text('ALARM TIME'), findsNothing,
        reason: 'the title is a sentence, not caps');
    expect(find.text('Alarm time'), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    await t.tap(find.text('SET TIME'));
    await t.pumpAndSettle();
    expect(await result(), const TimeOfDay(hour: 6, minute: 45));
  });

  testWidgets('each column can be moved on its own', (t) async {
    ClockFormatController.seed(ClockFormat.h24);
    final result = await open(t, const TimeOfDay(hour: 6, minute: 45));
    jump(t, 0, 22);
    await t.pumpAndSettle();
    await t.tap(find.text('SET TIME'));
    await t.pumpAndSettle();
    expect(await result(), const TimeOfDay(hour: 22, minute: 45));
  });

  testWidgets('both columns, and the two together', (t) async {
    ClockFormatController.seed(ClockFormat.h24);
    final result = await open(t, const TimeOfDay(hour: 6, minute: 45));
    jump(t, 0, 7);
    jump(t, 1, 15);
    await t.pumpAndSettle();
    await t.tap(find.text('SET TIME'));
    await t.pumpAndSettle();
    expect(await result(), const TimeOfDay(hour: 7, minute: 15));
  });

  testWidgets('a wheel loops: one past 23 is 00', (t) async {
    ClockFormatController.seed(ClockFormat.h24);
    final result = await open(t, const TimeOfDay(hour: 23, minute: 5));
    jump(t, 0, 24);
    await t.pumpAndSettle();
    await t.tap(find.text('SET TIME'));
    await t.pumpAndSettle();
    expect(await result(), const TimeOfDay(hour: 0, minute: 5));
  });

  testWidgets('a 12-hour clock reads hours as 7 AM / 1 PM, still two columns',
      (t) async {
    ClockFormatController.seed(ClockFormat.h12);
    await open(t, const TimeOfDay(hour: 13, minute: 0));
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    expect(find.text('1 PM'), findsOneWidget);
  });

  testWidgets('swiping the sheet away answers nothing', (t) async {
    ClockFormatController.seed(ClockFormat.h24);
    final result = await open(t, const TimeOfDay(hour: 6, minute: 45));
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.byType(ListWheelScrollView), findsNothing);
    expect(await result(), isNull);
  });
}
