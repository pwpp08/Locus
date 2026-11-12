// The first two weeks: what each metric needs, how far along it is, and the
// two screens that show it, at a real phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart'
    show readinessCompositeMinBaseline;
import 'package:openstrap_edge/ui2/onboarding/what_to_expect.dart';
import 'package:openstrap_edge/ui2/screens/calibration.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(375 * 3, 812 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  test('a count that has caught up never reads as unlocked', () {
    // Fourteen nights on record, but recovery still abstains (a thin
    // baseline): thirteen of fourteen segments, one to go.
    final r = Calibration.of(days: 20, baselineNights: 14).milestones[3];
    expect(r.title, 'Recovery');
    expect(r.done, isFalse);
    expect(r.filled, r.need - 1);
    expect(r.left, 1);
    expect(r.toGo, 'Wear the band to sleep for 1 more night to calibrate');
  });

  test('scored metrics are unlocked, and so is the timeline once all are', () {
    final first = Calibration.of(days: 1);
    expect(first.nights, 1);
    expect([for (final m in first.milestones) m.done],
        [true, false, false, false, false]);
    expect(first.complete, isFalse);
    final done = Calibration.of(
        days: 30, strain: true, stress: true, recovery: true, health: true);
    expect(done.nights, 30);
    expect(done.complete, isTrue);
  });

  test('the stress monitor counts its own usable days when it has them', () {
    final s = Calibration.of(days: 6, stress: false, stressDays: 1)
        .milestones[2];
    expect(s.done, isFalse);
    expect(s.filled, 1);
    expect(s.toGo, 'Wear the band for 2 more days to calibrate');
  });

  testWidgets('the milestones screen fits a phone and opens what is unlocked',
      (t) async {
    phone(t);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: MilestonesScreen(Calibration.of(days: 1)),
    ));
    await t.pump();
    expect(find.text('YOUR FIRST TWO WEEKS'), findsOneWidget);
    expect(find.text('SLEEPS LOGGED 1/$readinessCompositeMinBaseline'),
        findsOneWidget);
    for (var n = 1; n <= readinessCompositeMinBaseline; n++) {
      expect(find.text('$n'), findsWidgets);
    }
    expect(find.text('VIEW DETAILS'), findsOneWidget, reason: 'only sleep');
    await t.scrollUntilVisible(find.text('Health monitor'), 200);
    expect(find.text('Log $readinessCompositeMinBaseline sleeps to unlock'),
        findsNWidgets(2));
    expect(t.takeException(), isNull);
  });

  testWidgets('what to expect draws the wheel and finishes', (t) async {
    phone(t);
    var finished = false;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: WhatToExpectScreen(onFinish: () => finished = true),
    ));
    await t.pump();
    expect(find.text('What to expect next'), findsOneWidget);
    expect(find.text('$readinessCompositeMinBaseline'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Finish'));
    expect(finished, isTrue);
    expect(t.takeException(), isNull);
  });
}
