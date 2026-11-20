// The pull: past the line and let go, the refresh starts and the page springs
// straight back; nothing is drawn in the gap.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester t, Future<void> Function() onRefresh) =>
      t.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: CustomScrollView(physics: kPullPhysics, slivers: [
            PullToRefresh(onRefresh: onRefresh),
            SliverList(
              delegate: SliverChildListDelegate([
                for (var i = 0; i < 20; i++)
                  SizedBox(height: 60, child: Text('row $i')),
              ]),
            ),
          ]),
        ),
      ));

  testWidgets('a long pull runs the refresh once and does not wait for it',
      (t) async {
    var runs = 0;
    await pump(t, () {
      runs++;
      return Completer<void>().future; // never completes
    });
    final rest = t.getTopLeft(find.text('row 0')).dy;
    await t.drag(find.text('row 0'), const Offset(0, 300));
    await t.pumpAndSettle();
    expect(runs, 1);
    expect(t.getTopLeft(find.text('row 0')).dy, rest,
        reason: 'back at rest while the work runs on');
    expect(find.byType(WordmarkFill), findsNothing);
  });

  testWidgets('a flick back up the page stops at the top: no refresh',
      (t) async {
    var runs = 0;
    await pump(t, () async => runs++);
    final sc = t.state<ScrollableState>(find.byType(Scrollable));
    sc.position.jumpTo(400);
    await t.pump();
    await t.fling(find.byType(CustomScrollView), const Offset(0, 120), 4000);
    var lowest = 0.0;
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 16));
      if (sc.position.pixels < lowest) lowest = sc.position.pixels;
    }
    await t.pumpAndSettle();
    expect(lowest, 0, reason: 'never carried past the top');
    expect(runs, 0);
  });

  testWidgets('a short pull does not refresh', (t) async {
    var runs = 0;
    await pump(t, () async => runs++);
    await t.drag(find.text('row 0'), const Offset(0, 40));
    await t.pumpAndSettle();
    expect(runs, 0);
  });
}
