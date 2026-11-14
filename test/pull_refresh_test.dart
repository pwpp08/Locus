// The pull-down: the word LOCUS comes down gray as the page is pulled, and
// letting go past the line runs the refresh.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester t, Future<void> Function() onRefresh) =>
      t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: CustomScrollView(physics: kPullPhysics, slivers: [
            LocusPullRefresh(onRefresh: onRefresh),
            SliverList(
              delegate: SliverChildListDelegate([
                for (var i = 0; i < 20; i++)
                  SizedBox(height: 60, child: Text('row $i')),
              ]),
            ),
          ]),
        ),
      ));

  testWidgets('a long pull runs the refresh once, and waits for it',
      (t) async {
    var runs = 0;
    final done = Completer<void>();
    await pump(t, () {
      runs++;
      return done.future;
    });
    await t.drag(find.text('row 0'), const Offset(0, 300));
    await t.pump(const Duration(milliseconds: 100));
    expect(runs, 1);
    // Held open while it runs, even past the time the fill takes.
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(WordmarkFill), findsOneWidget);
    final sc = t.state<ScrollableState>(find.byType(Scrollable));
    expect(sc.position.pixels, 0, reason: 'held open at the gap, not at rest above it');
    done.complete();
    await t.pumpAndSettle();
    expect(runs, 1);
  });

  testWidgets('the white starts as soon as the pull is past the line',
      (t) async {
    await pump(t, () async {});
    final g = await t.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(0, 300)); // well past the line
    await t.pump(const Duration(milliseconds: 50)); // built, armed
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 300));
    double fill() => t.widget<WordmarkFill>(find.byType(WordmarkFill)).fill;
    expect(fill(), greaterThan(0), reason: 'filling under the finger');
    await g.up();
    // Let the refresh run out its hold, so nothing is left pending.
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  });

  testWidgets('a flick back up the page stops at the top: no word, no refresh',
      (t) async {
    var runs = 0;
    await pump(t, () async => runs++);
    final sc = t.state<ScrollableState>(find.byType(Scrollable));
    sc.position.jumpTo(400);
    await t.pump();
    // A short, fast flick: the finger itself never reaches the top.
    await t.fling(find.byType(CustomScrollView), const Offset(0, 120), 4000);
    var lowest = 0.0;
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 16));
      if (sc.position.pixels < lowest) lowest = sc.position.pixels;
    }
    await t.pumpAndSettle();
    expect(lowest, 0, reason: 'never carried past the top');
    expect(sc.position.pixels, 0);
    expect(runs, 0);
  });

  testWidgets('the word always goes back up, even if the work never ends',
      (t) async {
    await pump(t, () => Completer<void>().future); // never completes
    final rest = t.getTopLeft(find.text('row 0')).dy;
    await t.drag(find.text('row 0'), const Offset(0, 300));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.getTopLeft(find.text('row 0')).dy, greaterThan(rest),
        reason: 'held down while it runs');
    // Past the longest it will wait for the work itself.
    for (var i = 0; i < 120; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('row 0')).dy, rest,
        reason: 'back where it started: the word is hidden again');
  });

  testWidgets('a short pull does not refresh', (t) async {
    var runs = 0;
    await pump(t, () async => runs++);
    await t.drag(find.text('row 0'), const Offset(0, 40));
    await t.pumpAndSettle();
    expect(runs, 0);
  });

  testWidgets('the fill is more written the further along it is', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(
        body: Column(children: [
          WordmarkFill(fill: 0, base: Color(0xFF666666), ink: Color(0xFFFFFFFF)),
          WordmarkFill(fill: 1, base: Color(0xFF666666), ink: Color(0xFFFFFFFF)),
        ]),
      ),
    ));
    expect(find.byType(ShaderMask), findsOneWidget,
        reason: 'empty is just the gray word; only a started fill is masked');
  });
}
