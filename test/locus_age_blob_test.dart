import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/locus_age.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  testWidgets('a finger on the blob plays with it and does not scroll the page',
      (t) async {
    t.view.physicalSize = const Size(390 * 2, 480 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const LocusAgeScreen(page: true, today: '2026-11-10'),
    ));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // A short phone, so the empty page still has somewhere to scroll.
    double offset() =>
        t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

    // The blob's centre at rest: half the width, 209 below the top inset.
    await t.dragFrom(const Offset(195, 209), const Offset(0, -200));
    await t.pump(const Duration(milliseconds: 100));
    expect(offset(), 0, reason: 'the blob kept the finger');

    // Below the blob the page scrolls as before.
    await t.dragFrom(const Offset(195, 440), const Offset(0, -200));
    await t.pump(const Duration(milliseconds: 100));
    expect(offset(), greaterThan(0));
  });
}
