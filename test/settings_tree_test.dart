// The settings tree: App settings is one door per subject, each door opens a
// page that holds what it names, and the privacy page says only what the
// build does.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/live/live_activity.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/settings_tree.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
  });

  Future<void> pump(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(393 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState()),
        ChangeNotifierProvider<CoachConfig>.value(value: CoachConfig()),
      ],
      child: MaterialApp(theme: buildTheme(), home: page),
    ));
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('App settings is one door per subject', (t) async {
    await pump(t, const AppSettings());
    for (final row in [
      'ACTIVITY SETTINGS',
      'AI SETTINGS',
      'DATA EXPORT',
      'INTEGRATIONS',
      'NOTIFICATIONS',
      'UNITS AND TIME',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
  });

  testWidgets('Activity settings holds detection, zones and the live card',
      (t) async {
    await pump(t, const ActivitySettings());
    for (final row in [
      'ACTIVITY DETECTION',
      'HEART RATE SETTINGS',
      'LIVE ACTIVITY',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
  });

  testWidgets('AI settings: the chat, then the provider at the foot',
      (t) async {
    await pump(t, const AiSettings());
    for (final row in [
      'MEMORY',
      'ANSWER LENGTH',
      'TONE',
      'EMOJIS',
      'OUTLOOK LENGTH',
      'PROVIDER AND MODEL',
    ]) {
      expect(find.text(row), findsWidgets, reason: row);
    }
    final tone = t.getTopLeft(find.text('TONE')).dy;
    final provider = t.getTopLeft(find.text('PROVIDER AND MODEL')).dy;
    expect(provider, greaterThan(tone), reason: 'provider is last');
    // Not set up: it says so rather than naming a model.
    expect(find.textContaining('Not set up'), findsOneWidget);
  });

  testWidgets('Integrations holds what comes in, Data export does not',
      (t) async {
    await pump(t, const IntegrationsSettings());
    expect(find.text('IMPORT WHOOP DATA'), findsOneWidget);
    expect(find.text('TASKER AND SHORTCUTS'), findsOneWidget);
  });

  testWidgets('Privacy: two switches, then plain facts', (t) async {
    await pump(t, const PrivacySettings());
    expect(find.text('CRASH REPORTS'), findsOneWidget);
    for (final f in kPrivacyFacts) {
      expect(find.text(f.$2.toUpperCase()), findsOneWidget, reason: f.$2);
    }
    // Nothing on it names another company or product.
    for (final f in kPrivacyFacts) {
      expect('${f.$2} ${f.$3}'.toLowerCase().contains('whoop'), isFalse,
          reason: f.$2);
    }
  });

  testWidgets('the live activity card has its own switches', (t) async {
    await pump(t, const LiveActivitySettings());
    expect(LiveActivity.enabled, isTrue, reason: 'on by default');
    await t.tap(find.byType(AppSwitch).first);
    await t.pump();
    expect(LiveActivity.enabled, isFalse);
    // The chip is the card's: it does nothing while the card is off.
    await t.tap(find.byType(AppSwitch).last);
    await t.pump();
    expect(LiveActivity.chip, isTrue);
  });
}
