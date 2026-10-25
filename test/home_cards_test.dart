// Home's first-weeks card can be swiped away until tomorrow, and the Add
// activity sheet will not save until an activity has been chosen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/add_activity.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('swiping the first-weeks card away keeps it away for the day',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    Widget app() => MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: Builder(
                builder: (c) => firstWeekCard(c, days: 3, strainScored: false)),
          ),
        );
    await t.pumpWidget(app());
    expect(find.text('Your first weeks'), findsOneWidget);
    await t.drag(find.text('Your first weeks'), const Offset(500, 0));
    await t.pumpAndSettle();
    expect(find.text('Your first weeks'), findsNothing);
    expect(Prefs.getString(Prefs.firstWeeksDismissedOn, ''), todayLabel());
    // Back on the screen later the same day, it is still gone.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app());
    expect(find.text('Your first weeks'), findsNothing);
    // Another day, it is back.
    Prefs.setString(Prefs.firstWeeksDismissedOn, '2000-01-01');
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app());
    expect(find.text('Your first weeks'), findsOneWidget);
  });

  testWidgets('the add-activity sheet names an activity before it saves',
      (t) async {
    t.view.physicalSize = const Size(411 * 3, 890 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
            builder: (c) => TextButton(
                onPressed: () => openAddActivity(c), child: const Text('open'))),
      ),
    ));
    await t.tap(find.text('open'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('ADD ACTIVITY'), findsOneWidget);
    expect(find.text('SELECT ACTIVITY'), findsOneWidget);
    expect(find.text('SAVE'), findsOneWidget);
    // Choose one: the list opens, a row is tapped, the form says which.
    await t.tap(find.text('SELECT ACTIVITY'));
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('SELECT YOUR ACTIVITY'), findsOneWidget);
    await t.tap(find.text('RECOVERY'));
    await t.pump();
    expect(find.text('MEDITATION'), findsOneWidget);
    expect(find.text('RUNNING'), findsNothing);
    await t.tap(find.text('MEDITATION'));
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('ADD ACTIVITY'), findsOneWidget);
    expect(find.text('MEDITATION'), findsOneWidget);
    expect(find.text('SELECT ACTIVITY'), findsNothing);
  });
}
