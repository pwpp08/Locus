// The floating AI button is the user's: on or off, its size, its spot. Its
// sheet draws, and the (+) menu opens from a button on the left.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/state/ai_button_prefs.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/screens/coach.dart';
import 'package:openstrap_edge/ui2/screens/plus_menu.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Prefs.ensureLoaded();
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
  });

  Future<void> shell(WidgetTester t, {void Function(BuildContext)? onAi}) =>
      t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: AppShell(
          builder: (_, d) => Center(child: Text('screen ${d.label}')),
          onAi: onAi,
        ),
      ));

  Finder orb() => find.bySemanticsLabel('Ask the AI coach');

  testWidgets('it is there, it opens the coach, and it can be turned off',
      (t) async {
    var opened = 0;
    await shell(t, onAi: (_) => opened++);
    expect(orb(), findsOneWidget);
    await t.tap(orb());
    expect(opened, 1);

    AiButtonPrefs.setOn(false);
    await t.pump();
    expect(orb(), findsNothing);
    AiButtonPrefs.setOn(true);
    await t.pump();
    expect(orb(), findsOneWidget);
  });

  testWidgets('no coach to ask, no button', (t) async {
    await shell(t);
    expect(orb(), findsNothing);
  });

  testWidgets('its size and spot follow the settings', (t) async {
    await shell(t, onAi: (_) {});
    final width = t.view.physicalSize.width / t.view.devicePixelRatio;
    double side() => t.getSize(find.byType(AiOrb)).width;
    expect(side(), AiButtonPrefs.sides[1]);
    expect(t.getCenter(find.byType(AiOrb)).dx, greaterThan(width / 2));

    AiButtonPrefs.setIndex(AiButtonPrefs.kSize, 2);
    AiButtonPrefs.setIndex(
        AiButtonPrefs.kSpot, AiButtonSpot.middleLeft.index);
    await t.pump();
    expect(side(), AiButtonPrefs.sides[2]);
    expect(t.getCenter(find.byType(AiOrb)).dx, lessThan(width / 2));
    expect(find.byType(AiOrb), findsOneWidget);
  });

  testWidgets('the sheet draws, with its way into past chats', (t) async {
    await t.pumpWidget(ChangeNotifierProvider<CoachConfig>(
      create: (_) => CoachConfig(),
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(body: CoachScreen(sheet: true)),
      ),
    ));
    await t.pump();
    expect(find.text('Chats'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a menu on a left-hand button opens rightward and hands back',
      (t) async {
    String? got;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Builder(
        builder: (c) => Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: TextButtonish(onTap: () async {
              got = await showAnchoredMenu<String>(
                  c,
                  const Rect.fromLTWH(8, 500, 44, 44),
                  [('img', Icons.image, 'Upload image')]);
            }),
          ),
        ),
      ),
    ));
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
    final row = find.text('UPLOAD IMAGE');
    expect(t.getTopLeft(row).dx, lessThan(200));
    await t.tap(row);
    await t.pumpAndSettle();
    expect(got, 'img');
  });

  test('a long file is cut and says so; a picture without a type is a JPEG',
      () {
    expect(clipFileText('short'), 'short');
    final long = clipFileText('x' * 60010);
    expect(long, startsWith('x' * 60000));
    expect(long, contains('10 more characters, was left out'));
    expect(imageMimeFor('a.PNG'), 'image/png');
    expect(imageMimeFor('scaled_123'), 'image/jpeg');
  });
}

/// A plain tap target for the menu test.
class TextButtonish extends StatelessWidget {
  final VoidCallback onTap;
  const TextButtonish({super.key, required this.onTap});

  @override
  Widget build(BuildContext c) => SizedBox(
        key: const Key('open'),
        width: 44,
        height: 44,
        child: Material(child: InkWell(onTap: onTap)),
      );
}
