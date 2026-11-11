// The More tab is five doors: My profile, Reports, Device settings, Health
// settings and Settings. Every setting is behind exactly one of them; two
// doors to one thing is how people end up unsure which is the real one.

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

  testWidgets('the More tab is five doors, each opening its own page',
      (t) async {
    final taps = <String>[];
    await pump(
      t,
      ProfileHomeView(
        tab: true,
        onProfile: () => taps.add('profile'),
        onReports: () => taps.add('reports'),
        onDevice: () => taps.add('device'),
        onHealth: () => taps.add('health'),
        onSettings: () => taps.add('settings'),
      ),
    );
    const rows = [
      'MY PROFILE',
      'REPORTS',
      'DEVICE SETTINGS',
      'HEALTH SETTINGS',
      'SETTINGS',
    ];
    for (final row in rows) {
      await t.ensureVisible(find.text(row));
      await t.tap(find.text(row));
      await t.pump();
    }
    expect(taps, ['profile', 'reports', 'device', 'health', 'settings']);
    // Nothing else: every setting is behind one of the five.
    expect(find.byType(MoreRow), findsNWidgets(rows.length));
  });

  testWidgets('Settings holds the app, and none of what moved out', (t) async {
    await pump(
        t, MoreSettingsView(version: '0.11.4', devMode: false, onUpdates: () {}));
    for (final gone in [
      'APPEARANCE',
      'CYCLE TRACKING',
      'STEPS',
      'STEP COUNTER',
      'ALARM',
      'JOURNAL',
      'LOCUS AGE',
      'HEART RATE ZONES',
      'DOUBLE-TAP',
      'COMPARE WITH WATCH',
    ]) {
      expect(find.text(gone), findsNothing, reason: '$gone is not an app setting');
    }
    for (final kept in [
      'UNITS',
      'TIME FORMAT',
      'MANAGE NOTIFICATIONS',
      'APP UPDATES',
      'CHECK AUTOMATICALLY',
      'IMPORT WHOOP DATA',
      'TASKER AND SHORTCUTS',
      'MODEL AND KEY',
      'EXPORT AND BACKUP',
      'CLOUD ACCOUNT',
      'STORAGE',
    ]) {
      expect(find.text(kept), findsWidgets, reason: '$kept is in Settings');
    }
  });
}
