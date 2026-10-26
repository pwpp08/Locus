// Edit Activity: the sheet a saved session's Edit opens. It is Add Activity's
// own form, on the session: its activity and its times, and SAVE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/screens/add_activity.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('it opens on the session, and offers no sleep tab', (t) async {
    t.view.physicalSize = const Size(411 * 2, 890 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => openEditActivity(
                c,
                (
                  id: 'x',
                  activity: activityByName('Cycling')!,
                  start: DateTime(2025, 4, 25, 7, 22),
                  end: DateTime(2025, 4, 25, 7, 32),
                ),
                now: DateTime(2025, 4, 26)),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('EDIT ACTIVITY'), findsOneWidget);
    expect(find.text('CYCLING'), findsOneWidget);
    expect(find.text('Start Time'), findsOneWidget);
    expect(find.text('End Time'), findsOneWidget);
    expect(find.text('Apr 25'), findsNWidgets(2));
    expect(find.text('7:22'), findsOneWidget);
    expect(find.text('7:32'), findsOneWidget);
    expect(find.text('SAVE'), findsOneWidget);

    // The row opens the list, which has no way to start a sleep from here.
    await t.tap(find.text('CYCLING'));
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('SELECT YOUR ACTIVITY'), findsOneWidget);
    expect(find.text('SLEEP'), findsNothing);
  });
}
