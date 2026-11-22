// The More tab is laid out as the reference's settings: Reports and
// Community, then ACCOUNT & SETTINGS (My account, Device settings, App
// settings, Privacy settings) and SUPPORT (Help, First week, About). Every
// setting is behind exactly one door; two doors to one thing is how people
// end up unsure which is the real one.

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
      theme: buildTheme(),
      home: Scaffold(body: w),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('the More tab is the reference tree, each door its own page',
      (t) async {
    final taps = <String>[];
    await pump(
      t,
      ProfileHomeView(
        tab: true,
        version: '0.9.26 (57)',
        onReports: () => taps.add('reports'),
        onCommunity: () => taps.add('community'),
        onAccount: () => taps.add('account'),
        onDevice: () => taps.add('device'),
        onAppSettings: () => taps.add('app'),
        onPrivacy: () => taps.add('privacy'),
        onReport: () => taps.add('report'),
        onFirstWeek: () => taps.add('first week'),
        onAbout: () => taps.add('about'),
        onReset: () => taps.add('reset'),
      ),
    );
    const rows = [
      'REPORTS',
      'COMMUNITY',
      'MY ACCOUNT',
      'DEVICE SETTINGS',
      'APP SETTINGS',
      'PRIVACY SETTINGS',
      'REPORT AN ISSUE',
      'FIRST WEEK WITH LOCUS',
      'ABOUT',
      'RESET ALL DATA',
    ];
    for (final row in rows) {
      await t.ensureVisible(find.text(row));
      await t.tap(find.text(row));
      await t.pump();
    }
    expect(taps, [
      'reports',
      'community',
      'account',
      'device',
      'app',
      'privacy',
      'report',
      'first week',
      'about',
      'reset',
    ]);
    expect(find.text('ACCOUNT & SETTINGS'), findsOneWidget);
    expect(find.text('SUPPORT'), findsOneWidget);
    expect(find.text('APP VERSION: 0.9.26 (BUILD 57)'), findsOneWidget);
    // Nothing else: every setting is behind one of the nine.
    expect(find.byType(MoreRow), findsNWidgets(rows.length - 1));
  });

  testWidgets('About holds the build, and none of what moved out', (t) async {
    await pump(t, AboutView(version: '0.11.4', onUpdates: () {}));
    for (final gone in [
      'UNITS',
      'TIME FORMAT',
      'TASKER AND SHORTCUTS',
      'MODEL AND KEY',
      'CRASH REPORTS',
      'IMPORT WHOOP DATA',
    ]) {
      expect(find.text(gone), findsNothing, reason: '$gone is not in About');
    }
    for (final kept in [
      'APP UPDATES',
      'CHECK AUTOMATICALLY',
      'NOTICES AND LICENCES',
      'VERSION',
    ]) {
      expect(find.text(kept), findsWidgets, reason: '$kept is in About');
    }
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

  testWidgets('Data export holds what goes out, and nothing coming in',
      (t) async {
    await pump(t, const YourDataView(storage: '1.4 GB'));
    expect(find.text('EXPORT AND BACKUP'), findsOneWidget);
    expect(find.text('STORAGE'), findsOneWidget);
    expect(find.text('1.4 GB'), findsOneWidget);
    expect(find.text('IMPORT WHOOP DATA'), findsNothing,
        reason: 'what comes in is Integrations');
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
