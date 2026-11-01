// The More tab has to reach Settings, the updater and the band buzzes. Settings
// was once reachable from nowhere on it, which stranded everything inside it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester t, ProfileHomeView v) async {
    t.view.physicalSize = const Size(390 * 3, 2600 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: v),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('Settings, updates and band buzzes are on the More tab',
      (t) async {
    final taps = <String>[];
    await pump(
      t,
      ProfileHomeView(
        tab: true,
        onSettings: () => taps.add('settings'),
        onUpdates: () => taps.add('updates'),
        onBuzz: () => taps.add('buzz'),
      ),
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('App updates'), findsOneWidget);
    expect(find.text('Band buzzes'), findsOneWidget);

    for (final row in ['Settings', 'App updates', 'Band buzzes']) {
      await t.ensureVisible(find.text(row));
      await t.tap(find.text(row));
      await t.pump();
    }
    expect(taps, ['settings', 'updates', 'buzz']);
  });

  testWidgets('a phone that cannot read other apps’ notifications has no '
      'band-buzz row', (t) async {
    await pump(
      t,
      ProfileHomeView(tab: true, onSettings: () {}, onUpdates: () {}),
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Band buzzes'), findsNothing);
  });
}
