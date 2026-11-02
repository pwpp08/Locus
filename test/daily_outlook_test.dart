// Under the My Day title: a coach button and a Daily Outlook card. And the
// coach screen's own header, which is no longer the shared nav bar.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/ui2/screens/coach.dart';
import 'package:openstrap_edge/ui2/screens/home/home_my_day.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: w),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('the outlook row opens the briefing, the orb opens the coach',
      (t) async {
    final taps = <String>[];
    await pump(
      t,
      DailyOutlookRow(
        evening: false,
        onCoach: () => taps.add('coach'),
        onOutlook: () => taps.add('outlook'),
      ),
    );
    expect(find.text('Daily Outlook'), findsOneWidget);
    await t.tap(find.text('Daily Outlook'));
    await t.tap(find.bySemanticsLabel('Ask the coach'));
    expect(taps, ['outlook', 'coach']);
  });

  testWidgets('the coach screen has its own header: the coach, and that it is not set up',
      (t) async {
    final config = CoachConfig();
    addTearDown(config.dispose);
    await pump(
      t,
      ChangeNotifierProvider<CoachConfig>.value(
        value: config,
        child: const CoachScreen(),
      ),
    );
    expect(find.text('Coach'), findsOneWidget);
    expect(find.text('Not set up'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
