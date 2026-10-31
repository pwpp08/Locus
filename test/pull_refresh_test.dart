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
