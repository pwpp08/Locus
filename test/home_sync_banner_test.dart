// Home's sync bar: which state it is in, and that "Caught up" is a moment
// after a catch-up, not a permanent fixture of the page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/home/home_header.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Widget _app(SyncBarState s) => MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: HomeSyncBanner(state: s, syncedTo: '5:09 PM'),
      ),
    );

void main() {
  test('syncing is catching up; fresh data is caught up; old data is behind',
      () {
    final now = DateTime(2026, 11, 11, 18);
    expect(
        syncBarStateOf(syncing: true, at: now, now: now), SyncBarState.catchingUp);
    expect(
        syncBarStateOf(
            syncing: false,
            at: now.subtract(const Duration(minutes: 10)),
            now: now),
        SyncBarState.caughtUp);
    expect(
        syncBarStateOf(
            syncing: false,
            at: now.subtract(const Duration(hours: 3)),
            now: now),
        SyncBarState.behind);
  });

  testWidgets('opening Home on current data shows no bar', (t) async {
    await t.pumpWidget(_app(SyncBarState.caughtUp));
    expect(find.byType(HomeSyncBar), findsNothing);
  });

  testWidgets('not up to date stays, so it can be tapped', (t) async {
    await t.pumpWidget(_app(SyncBarState.behind));
    await t.pump(kCaughtUpShown * 2);
    expect(find.text('DATA NOT UP TO DATE'), findsOneWidget);
  });

  testWidgets('caught up shows once the catch-up lands, then folds away',
      (t) async {
    await t.pumpWidget(_app(SyncBarState.catchingUp));
    expect(find.text('DATA CATCHING UP'), findsOneWidget);
    await t.pumpWidget(_app(SyncBarState.caughtUp));
    expect(find.text('DATA CAUGHT UP'), findsOneWidget);
    await t.pump(kCaughtUpShown);
    await t.pump(Motion.slow);
    expect(find.byType(HomeSyncBar), findsNothing);
  });
}
