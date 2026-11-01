// The food camera. The plugin itself needs a phone, so this pins what does not:
// a still is shrunk to something small and upright, the sheet says plainly when
// there is no camera, and the sheet offers the right buttons for where it was
// opened from.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openstrap_edge/ui2/screens/food_camera.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  // The test host has no camera plugin; say there are none.
  setUp(() => foodCameraList = () async => const []);

  group('shrinkPhoto', () {
    Uint8List jpeg(int w, int h) =>
        Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h), quality: 90));

    test('a wide still keeps its shape and loses its size', () {
      final out = img.decodeJpg(shrinkPhoto(jpeg(3000, 2000)))!;
      expect(out.width, kFoodPhotoEdge);
      expect(out.height, closeTo(kFoodPhotoEdge * 2 / 3, 1));
    });

    test('a tall still is limited on its tall side', () {
      final out = img.decodeJpg(shrinkPhoto(jpeg(1500, 3000)))!;
      expect(out.height, kFoodPhotoEdge);
      expect(out.width, closeTo(kFoodPhotoEdge / 2, 1));
    });

    test('a small picture is not blown up', () {
      final out = img.decodeJpg(shrinkPhoto(jpeg(400, 300)))!;
      expect([out.width, out.height], [400, 300]);
    });

    test('bytes that are not a picture come back untouched', () {
      final junk = Uint8List.fromList([1, 2, 3]);
      expect(shrinkPhoto(junk), junk);
    });
  });

  group('the sheet', () {
    Future<void> open(WidgetTester t, {required bool barcodes}) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => openFoodCamera(c, barcodes: barcodes),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('no camera on this device is said plainly, with the gallery as '
        'the way out', (t) async {
      await open(t, barcodes: true);
      expect(find.text('The camera did not start'), findsOneWidget);
      expect(find.text('CHOOSE FROM THE GALLERY'), findsOneWidget);
    });

    testWidgets('from the log sheet it offers gallery, shutter and live scan',
        (t) async {
      await open(t, barcodes: true);
      expect(find.bySemanticsLabel('Take a picture'), findsOneWidget);
      expect(find.bySemanticsLabel('Choose from the gallery'), findsWidgets);
      expect(find.bySemanticsLabel('Scan a barcode live'), findsOneWidget);
    });

    testWidgets('from the AI sheet it is photo only: no barcode button',
        (t) async {
      await open(t, barcodes: false);
      expect(find.bySemanticsLabel('Take a picture'), findsOneWidget);
      expect(find.bySemanticsLabel('Scan a barcode live'), findsNothing);
    });

    testWidgets('the live-scan button answers with the scan shot', (t) async {
      FoodShot? got;
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () async => got = await openFoodCamera(c),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Scan a barcode live'));
      await t.pumpAndSettle();
      expect(got?.kind, FoodShotKind.scan);
    });
  });
}
