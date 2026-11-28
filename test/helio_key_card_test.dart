// The Helio strap's pairing screen: the guide, the key card and the one way a
// key gets typed in. Rendered at a large text scale as well, because a card of
// buttons is where a layout fault would hide.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart';
import 'package:openstrap_edge/ui2/profile/helio_key.dart';
import 'package:openstrap_edge/ui2/profile/pair_sensor.dart';
import 'package:openstrap_edge/ui2/profile/setup_guide.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Future<void> _pump(WidgetTester t, {double scale = 1}) async {
  t.view.physicalSize = Size(390 * 3, 9000 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: MaterialApp(
      theme: buildTheme(),
      home: PairSensorView(
        entryLabel: kHelio.label,
        adapterId: kHelio.id,
        extra: const HelioKeyCard(),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // An empty keychain: every read answers null.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
  });

  test('the strap has a setup guide, and it says the Zepp app must be closed', () {
    final g = setupGuideFor(kHelio.id)!;
    final text = g.paths.expand((p) => p.steps).join(' ');
    expect(text, contains('Force stop'));
    expect(text, contains('email and password'));
    expect(g.lacks, contains('Experimental'));
  });

  for (final scale in [1.0, 3.1]) {
    testWidgets('the key card renders with no key yet at ${scale}x', (t) async {
      await _pump(t, scale: scale);
      expect(layoutFaults(t), isEmpty);
      expect(find.text('No key yet.'), findsOneWidget);
      expect(find.text('SIGN IN TO ZEPP'), findsOneWidget);
      expect(find.text('ENTER IT'), findsOneWidget);
    });
  }

  testWidgets('a key typed wrongly is refused in words', (t) async {
    await _pump(t);
    await t.tap(find.text('ENTER IT'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'not a key');
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();
    expect(find.text('That is not 32 hex characters.'), findsOneWidget);
  });
}

/// Layout exceptions the framework caught while pumping.
List<Object> layoutFaults(WidgetTester t) {
  final out = <Object>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    out.add(e!);
  }
  return out;
}
