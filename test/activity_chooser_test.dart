// SELECT YOUR ACTIVITY: the one list every place that names an activity
// opens. A sleep and a nap lead All where a sleep makes sense, and are left
// out where it does not (correcting a recorded session's type).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/add_activity.dart';
import 'package:openstrap_edge/ui2/screens/window_editor.dart' show WindowKind;
import 'package:openstrap_edge/ui2/activity/catalogue.dart' show allActivities;
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<List<ActivityChoice>> pump(WidgetTester t, {bool sleep = true}) async {
    final picked = <ActivityChoice>[];
    t.view.physicalSize = const Size(390 * 3, 1400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: ActivityChooser(
          sleep: sleep,
          onPick: picked.add,
          onBack: () {},
        ),
      ),
    ));
    await t.pumpAndSettle();
    return picked;
  }

  testWidgets('Sleep and Nap lead the All list', (t) async {
    await pump(t);
    final sleep = t.getTopLeft(find.text('SLEEP').last).dy;
    final nap = t.getTopLeft(find.text('NAP')).dy;
    final ctx = t.element(find.byType(ActivityChooser));
    final names = [for (final a in allActivities) a.displayName(ctx)]..sort();
    final first = t.getTopLeft(find.text(names.first.toUpperCase())).dy;
    expect(sleep, lessThan(nap));
    expect(nap, lessThan(first), reason: 'above the A-Z list');
  });

  testWidgets('tapping the pinned Sleep returns a sleep, not an activity',
      (t) async {
    final picked = await pump(t);
    await t.tap(find.text('NAP'));
    await t.pump();
    expect(picked.single.sleep, WindowKind.nap);
    expect(picked.single.activity, isNull);
  });

  testWidgets('a search filters the pinned rows too', (t) async {
    await pump(t);
    await t.enterText(find.byType(TextField), 'nap');
    await t.pumpAndSettle();
    expect(find.text('NAP'), findsOneWidget);
    expect(find.text('SLEEP'), findsNWidgets(1),
        reason: 'only the tab is left: no Sleep row matches "nap"');
  });

  testWidgets('without sleep there is no Sleep tab and no pinned rows',
      (t) async {
    await pump(t, sleep: false);
    expect(find.text('NAP'), findsNothing);
    expect(find.text('SLEEP'), findsNothing);
    expect(find.text('ALL'), findsOneWidget);
  });
}
