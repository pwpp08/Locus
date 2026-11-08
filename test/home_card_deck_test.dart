// Home's deck of daily cards: a throw or the badge puts the top card away for
// the rest of the day, a short drag springs back, and the deck folds away
// when the last card goes.

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

const _cards = [
  DailyCard(
    DailyCardKind.firstRed,
    'First red in a while',
    'Recovery is 28%, your first red in 24 scored mornings. One low '
        'morning is a cue to go easy, not a trend.',
    bars: [72, 64, 58, 81, 77, 69, 28],
    barMax: 100,
    lit: C.recRed,
  ),
  DailyCard(
    DailyCardKind.hrvHigh,
    'HRV above your usual',
    'Last night\'s HRV of 68 ms was 19% above your 30-day average of 57 ms. '
        'Your body is handling its load well.',
  ),
  DailyCard(
    DailyCardKind.stepGoal,
    'Step goal reached',
    'You walked 11,240 steps yesterday, past your goal of 10,000.',
  ),
];

final _key = GlobalKey();

Widget _app({List<DailyCard> cards = _cards, String? day}) => MaterialApp(
  theme: buildTheme(Brightness.dark),
  home: Scaffold(
    backgroundColor: P(true).bg,
    body: RepaintBoundary(
      key: _key,
      child: ColoredBox(
        color: P(true).bg,
        child: ListView(
          padding: const EdgeInsets.all(S.x4),
          children: [
            DailyCardDeck(cards: cards, day: day ?? todayLabel()),
            const SizedBox(height: S.x3, key: ValueKey('below')),
          ],
        ),
      ),
    ),
  ),
);

Finder _shown(String title) => find.text(title).hitTestable();

void main() {
  setUpAll(loadAppFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    // Prefs keeps its first instance across tests; start each one clean.
    Prefs.setString(Prefs.dailyCardsDismissed, '');
  });

  testWidgets('a throw puts the top card away for the rest of the day', (
    t,
  ) async {
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app());
    expect(_shown('First red in a while'), findsOneWidget);
    expect(_shown('3'), findsOneWidget, reason: 'the badge counts the deck');

    await t.fling(_shown('First red in a while'), const Offset(160, 0), 1500);
    await t.pumpAndSettle();
    expect(find.text('First red in a while'), findsNothing);
    expect(_shown('HRV above your usual'), findsOneWidget);
    expect(_shown('2'), findsOneWidget);
    expect(
      Prefs.getString(Prefs.dailyCardsDismissed, ''),
      '${todayLabel()}|firstRed',
    );

    // Back on Home later the same day, it stays away.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_app());
    expect(find.text('First red in a while'), findsNothing);
    expect(_shown('HRV above your usual'), findsOneWidget);

    // Another day, the stale list is cleared and nothing is put away.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_app(day: '2099-01-01'));
    expect(_shown('First red in a while'), findsOneWidget);
    expect(Prefs.getString(Prefs.dailyCardsDismissed, ''), '');
  });

  testWidgets('a short, slow drag springs back', (t) async {
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app());
    final at = t.getTopLeft(_shown('First red in a while'));
    final g = await t.startGesture(t.getCenter(_shown('First red in a while')));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(8, 0));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(
      t.getTopLeft(find.text('First red in a while').last).dx,
      greaterThan(at.dx + 40),
      reason: 'the card follows the finger',
    );
    await t.pump(const Duration(milliseconds: 400));
    await g.up();
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(_shown('First red in a while')).dx,
      moreOrLessEquals(at.dx, epsilon: .5),
    );
    expect(Prefs.getString(Prefs.dailyCardsDismissed, ''), '');
  });

  testWidgets(
    'the badge puts the top card away; the deck folds after the last',
    (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(cards: [_cards[2]]));
      final below = t.getTopLeft(find.byKey(const ValueKey('below'))).dy;
      expect(below, greaterThan(S.x16));
      await t.tap(find.byIcon(LucideIcons.check).hitTestable());
      await t.pumpAndSettle();
      expect(find.text('Step goal reached'), findsNothing);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('below'))).dy,
        S.x4,
        reason: 'no cards, no deck: not even its gap',
      );
    },
  );

  testWidgets('reduced motion still puts a card away', (t) async {
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _app(),
      ),
    );
    await t.fling(_shown('First red in a while'), const Offset(-200, 0), 1500);
    await t.pumpAndSettle();
    expect(find.text('First red in a while'), findsNothing);
  });

  testWidgets('render the deck at phone width', (t) async {
    t.view.physicalSize = const Size(393 * 3, 300 * 3);
    // The icon font, so the badge's check is drawn and not a box.
    await t.runAsync(() async {
      final icons = FontLoader('packages/lucide_icons_flutter/Lucide300')
        ..addFont(
          rootBundle.load(
            'packages/lucide_icons_flutter/assets/'
            'build_font/LucideVariable-w300.ttf',
          ),
        );
      await icons.load();
    });
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app());
    Future<void> shoot(String name) async {
      final png = await t.runAsync(() async {
        final boundary =
            _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        return bytes!.buffer.asUint8List();
      });
      File('build/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!);
    }

    await shoot('daily_card_deck');
    // Mid-throw: the top card tilted off to the right, the next one rising.
    final g = await t.startGesture(t.getCenter(_shown('First red in a while')));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(12, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await shoot('daily_card_deck_swipe');
    await g.up();
    await t.pumpAndSettle();
  });
}
