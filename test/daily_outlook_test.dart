// Under the My Day title: a coach button and a Daily Outlook card. And the
// coach screen's own header, which is no longer the shared nav bar.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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

  testWidgets('the outlook strip is one full-width strip that opens the '
      'outlook', (t) async {
    final taps = <String>[];
    await pump(
      t,
      DailyOutlookRow(evening: false, onOutlook: () => taps.add('outlook')),
    );
    expect(find.text('Daily Outlook'), findsOneWidget);
    expect(find.byType(AiOrb), findsNothing, reason: 'no coloured circle');
    final strip = t.getSize(find.byType(DailyOutlookRow));
    expect(strip.width, closeTo(390, 1), reason: 'as wide as the row');
    await t.tap(find.text('Daily Outlook'));
    expect(taps, ['outlook']);
  });

  testWidgets('the strip carries the first name, at the reference proportions',
      (t) async {
    await pump(
      t,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DailyOutlookRow(
            name: 'Greg Smith', evening: false, onOutlook: () {}),
      ),
    );
    final text = find.text("Greg's Daily Outlook");
    expect(text, findsOneWidget);
    // The reference: the strip 44 tall, the words about 2.8 strip-heights
    // long, starting about 37 in.
    final strip = t.getRect(find.byType(DailyOutlookRow));
    expect(strip.height, 44 + 12, reason: 'the strip and its gap under it');
    final words = t.getRect(text);
    expect(words.left - strip.left, closeTo(37, 2));
    final ink = (t.renderObject(text) as RenderParagraph)
        .getMaxIntrinsicWidth(double.infinity);
    expect(ink, closeTo(124, 8));
    expect(t.takeException(), isNull);
  });

  testWidgets('the coach screen header: the name, the model tag (here: not set up) and History',
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
    expect(find.text('Not set up'), findsOneWidget);
    expect(find.bySemanticsLabel('Chats and AI settings'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
