// The More tab is eight doors: My profile, Reports, Community, Device
// settings, Heart rate zones, Notifications, Your data and Settings. Every setting is behind
// exactly one of them; two doors to one thing is how people end up unsure
// which is the real one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/ui2/profile/device_settings.dart';
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

  testWidgets('the More tab is eight doors, each opening its own page',
      (t) async {
    final taps = <String>[];
    await pump(
      t,
      ProfileHomeView(
        tab: true,
        onProfile: () => taps.add('profile'),
        onReports: () => taps.add('reports'),
        onCommunity: () => taps.add('community'),
        onDevice: () => taps.add('device'),
        onZones: () => taps.add('zones'),
        onNotifications: () => taps.add('notifications'),
        onData: () => taps.add('data'),
        onSettings: () => taps.add('settings'),
      ),
    );
    const rows = [
      'MY PROFILE',
      'REPORTS',
      'COMMUNITY',
      'DEVICE SETTINGS',
      'HEART RATE ZONES',
      'NOTIFICATIONS',
      'YOUR DATA',
      'SETTINGS',
    ];
    for (final row in rows) {
      await t.ensureVisible(find.text(row));
      await t.tap(find.text(row));
      await t.pump();
    }
    expect(taps, [
      'profile',
      'reports',
      'community',
      'device',
      'zones',
      'notifications',
      'data',
      'settings'
    ]);
    // Nothing else: every setting is behind one of the eight.
    expect(find.byType(MoreRow), findsNWidgets(rows.length));
  });

  testWidgets('Settings holds the app, and none of what moved out', (t) async {
    await pump(
        t, MoreSettingsView(version: '0.11.4', devMode: false, onUpdates: () {}));
    for (final gone in [
      'APPEARANCE',
      'STEPS',
      'ALARM',
      'HEART RATE ZONES',
      'DOUBLE-TAP',
      'MANAGE NOTIFICATIONS',
      'IMPORT WHOOP DATA',
      'EXPORT AND BACKUP',
      'LOCUS ACCOUNT',
      'STORAGE',
    ]) {
      expect(find.text(gone), findsNothing, reason: '$gone is not in Settings');
    }
    for (final kept in [
      'UNITS',
      'TIME FORMAT',
      'APP UPDATES',
      'TASKER AND SHORTCUTS',
      'MODEL AND KEY',
    ]) {
      expect(find.text(kept), findsWidgets, reason: '$kept is in Settings');
    }
    // A choice is a dropdown now, not a row of segments.
    expect(find.byType(RangeSegments), findsNothing);
    expect(find.byType(SetDropdown), findsNWidgets(2));
  });

  testWidgets('a dropdown row opens its menu and reports the pick', (t) async {
    int? picked;
    await pump(
      t,
      Builder(
        builder: (c) => settingsGroup(c, '', [
          SetDropdown(LucideIcons.ruler, 'Units', const ['Metric', 'Imperial'],
              0, onChanged: (i) => picked = i),
        ]),
      ),
    );
    await t.tap(find.text('UNITS'));
    await t.pumpAndSettle();
    await t.tap(find.text('Imperial').last);
    await t.pumpAndSettle();
    expect(picked, 1);
  });

  testWidgets('Your data holds what comes in and what goes out', (t) async {
    await pump(t, const YourDataView(storage: '1.4 GB'));
    for (final row in [
      'IMPORT WHOOP DATA',
      'WRITE TO HEALTH CONNECT',
      'EXPORT AND BACKUP',
      'LOCUS ACCOUNT',
      'STORAGE',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
  });

  testWidgets('the HR zone alert lives in Notifications, its zone under it',
      (t) async {
    await pump(t, const NotificationSettingsView(prefs: NotificationPrefs()));
    await t.ensureVisible(find.text('HR ZONE ALERT'));
    expect(find.text('TARGET ZONE'), findsNothing, reason: 'only while on');
    await pump(
        t,
        const NotificationSettingsView(
            prefs: NotificationPrefs(), zoneAlert: true, zoneAlertTarget: 4));
    await t.ensureVisible(find.text('TARGET ZONE'));
    expect(find.text('Zone 4'), findsOneWidget);
  });

  testWidgets('device settings: status, then what can be done to the band',
      (t) async {
    await pump(
        t,
        DeviceSettingsView(
            connected: true,
            name: "Vince's band",
            battery: 36,
            heartRate: 62,
            model: 'WHOOP 4.0',
            serial: '4C2619854',
            onRename: () {}));
    expect(find.text('CONNECTED TO'), findsOneWidget);
    // The live heart rate where the reference has its broadcast switch.
    expect(find.text('HEART RATE NOW'), findsOneWidget);
    expect(find.text('62'), findsOneWidget);
    expect(find.text("VINCE'S BAND"), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Rename the band')), findsOneWidget);
    await t.tap(find.text('ADVANCED'));
    await t.pumpAndSettle();
    expect(find.text('4C2619854'), findsOneWidget);
    expect(find.text('FIRMWARE'), findsNothing, reason: 'never reported');
    for (final row in ['PAIR ANOTHER BAND', 'UNPAIR BAND', 'DOUBLE-TAP']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
  });

  testWidgets('no fresh heart rate: no number, and the reason', (t) async {
    await pump(t, const DeviceSettingsView(connected: false));
    expect(find.text('HEART RATE NOW'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(3),
        reason: 'sync time, battery and heart rate');
    expect(find.text('CONNECT THE BAND TO SEE IT'), findsOneWidget);
  });
}
