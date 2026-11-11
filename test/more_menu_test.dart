// The More tab has to reach Settings, the updater and the band buzzes, and
// every one of them has to be in exactly ONE place: here or in Settings, never
// both. They were once in both, which left people unsure which was the real one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(390 * 3, 3200 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: w),
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
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('APP UPDATES'), findsOneWidget);
    expect(find.text('CHECK AUTOMATICALLY'), findsOneWidget);
    expect(find.text('BAND BUZZES'), findsOneWidget);

    for (final row in ['SETTINGS', 'APP UPDATES', 'BAND BUZZES']) {
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
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('BAND BUZZES'), findsNothing);
  });

  testWidgets('what lives on More is not repeated in Settings', (t) async {
    await pump(t, const MoreSettingsView(version: '0.11.4', devMode: false));
    for (final moved in [
      'ALARM',
      'CLOUD ACCOUNT',
      'EXPORT AND BACKUP',
      'COMPARE WITH WATCH',
      'CHECK FOR UPDATES',
      'CHECK AUTOMATICALLY',
    ]) {
      expect(find.text(moved), findsNothing, reason: '$moved moved to More');
    }
    // Settings keeps what is a preference, not a destination.
    expect(find.text('UNITS'), findsOneWidget);
    expect(find.text('HEART RATE ZONES'), findsOneWidget);
  });
}
