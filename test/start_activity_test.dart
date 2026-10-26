// Start Activity: the pulse, the strain target (swiped up, set by dragging round
// a dial), and a sleep or a nap started by hand. And the dial and the handle
// they are built from.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/start_activity.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: buildTheme(Brightness.dark), home: home);

void main() {
  setUpAll(loadAppFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
  });

  test('a strain reads as the band it sits in', () {
    expect(strainLevelOf(8.5), 'light');
    expect(strainLevelOf(10.0), 'light');
    expect(strainLevelOf(12), 'moderate');
    expect(strainLevelOf(16), 'strenuous');
    expect(strainLevelOf(19), 'all-out');
  });

  testWidgets('a dial reads the angle of the finger, from twelve o\'clock, clockwise',
      (t) async {
    final seen = <double>[];
    await t.pumpWidget(_app(Scaffold(
      body: Center(
        child: DialScrubber(
          value: null,
          onChanged: seen.add,
          label: 'Dial',
          describe: (f) => '$f',
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    )));
    final c = t.getCenter(find.byType(DialScrubber));
    // Three o'clock is a quarter turn.
    final g = await t.startGesture(c + const Offset(90, 0));
    expect(seen.last, closeTo(.25, .01));
    // Round to six, then nine.
    await g.moveTo(c + const Offset(0, 90));
    expect(seen.last, closeTo(.5, .01));
    await g.moveTo(c + const Offset(-90, 0));
    expect(seen.last, closeTo(.75, .01));
    // Carried past twelve it stays at the end: no jump back to nothing.
    await g.moveTo(c + const Offset(10, -90));
    expect(seen.last, 1.0);
    await g.up();
  });

  testWidgets('a touch in the middle of the dial is not a drag', (t) async {
    final seen = <double>[];
    await t.pumpWidget(_app(Scaffold(
      body: Center(
        child: DialScrubber(
          value: null,
          onChanged: seen.add,
          label: 'Dial',
          describe: (f) => '$f',
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    )));
    final g = await t.startGesture(t.getCenter(find.byType(DialScrubber)));
    await g.moveBy(const Offset(40, 0));
    await g.up();
    expect(seen, isEmpty);
  });

  testWidgets('the handle opens on a swipe up and on a tap', (t) async {
    final log = <String>[];
    await t.pumpWidget(_app(Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SwipeHandle(
          onSwipe: (up) => log.add(up ? 'up' : 'down'),
          onTap: () => log.add('tap'),
          semanticLabel: 'Handle',
          child: const SizedBox(width: 200, height: 80),
        ),
      ),
    )));
    await t.drag(find.byType(SwipeHandle), const Offset(0, -60));
    await t.drag(find.byType(SwipeHandle), const Offset(0, 60));
    await t.tap(find.byType(SwipeHandle));
    expect(log, ['up', 'down', 'tap']);
  });

  testWidgets('start: the pulse beats, the dock opens, the dial sets a target',
      (t) async {
    t.view.physicalSize = const Size(411 * 2, 890 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const StartActivityScreen()));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('RUNNING'), findsNothing);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('TRACK ROUTE'), findsOneWidget);
    expect(find.text('START ACTIVITY'), findsOneWidget);
    expect(find.text('STRAIN TARGET'), findsOneWidget);
    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);

    // Swiped up, the dock opens on the dial.
    await t.drag(find.text('STRAIN TARGET'), const Offset(0, -80));
    // The pulse never settles, so the dock's slide is pumped by hand.
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('ACTIVITY STRAIN'), findsOneWidget);
    expect(find.text('SET GOAL'), findsOneWidget);

    // A finger on the ring at three o'clock is a quarter of the scale.
    final dial = find.byType(DialScrubber);
    expect(t.getCenter(dial).dy, lessThan(890));
    final c = t.getCenter(dial);
    final r = t.getSize(dial).width / 2;
    final g = await t.startGesture(c + Offset(r - 8, 0));
    await g.up();
    await t.pump();
    final set = Prefs.getString(Prefs.activityStrainTarget, '');
    expect(['5.2', '5.3'], contains(set));
    expect(find.text(set), findsWidgets);
    expect(find.text('LIGHT'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
    expect(find.textContaining('light cardiovascular exertion'), findsOneWidget);
  });

  testWidgets('a nap is started by hand and the screen reopens on it', (t) async {
    t.view.physicalSize = const Size(411 * 2, 890 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final since = DateTime.now().subtract(const Duration(minutes: 12));
    Prefs.setString(Prefs.restPending, 'nap|${since.millisecondsSinceEpoch}');
    await t.pumpWidget(_app(const StartActivityScreen()));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Nap'), findsOneWidget);
    expect(find.text('END NAP'), findsOneWidget);
    expect(find.text('DISCARD'), findsOneWidget);
    expect(find.textContaining('0:12:'), findsOneWidget);
    // No workout controls on a rest.
    expect(find.text('STRAIN TARGET'), findsNothing);
    expect(find.text('TRACK ROUTE'), findsNothing);
    await t.tap(find.text('DISCARD'));
    await t.pump();
    expect(Prefs.getString(Prefs.restPending, ''), '');
    expect(find.text('START NAP'), findsOneWidget);
  });
}
