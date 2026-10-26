// The window editor: a sleep, nap or activity set on the heart rate around
// it. Its limits, and that it hands back the window the lines were set to.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/window_editor.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  final now = DateTime(2026, 10, 26, 12);

  test('each kind keeps to its own length, and to the past', () {
    final night = (DateTime(2026, 10, 26, 1), DateTime(2026, 10, 26, 10, 15));
    expect(windowProblem(WindowKind.sleep, night.$1, night.$2, now), isNull);
    // Nine hours is a sleep, not a nap: the nap editor refused this one.
    expect(windowProblem(WindowKind.nap, night.$1, night.$2, now), isNotNull);
    expect(
        windowProblem(WindowKind.sleep, DateTime(2026, 10, 26, 9),
            DateTime(2026, 10, 26, 9, 20), now),
        isNotNull);
    expect(
        windowProblem(WindowKind.sleep, DateTime(2026, 10, 26, 6),
            DateTime(2026, 10, 26, 13), now),
        'The end has not happened yet.');
    expect(
        windowProblem(WindowKind.sleep, night.$2, night.$1, now),
        'The end has to come after the start.');
  });

  testWidgets('a drag moves the nearer line, and save hands the window back',
      (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final start = DateTime(2026, 10, 26, 1);
    final end = DateTime(2026, 10, 26, 9);
    Future<List<HrPoint>> hr(int from, int to) async => [
          for (var s = from; s < to; s += 60) (t: s, v: 60.0),
        ];
    (DateTime, DateTime)? got;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: Pressable(
              onTap: () async => got = await Navigator.of(c).push(
                  MaterialPageRoute(
                      builder: (_) => WindowEditor(
                          kind: WindowKind.sleep,
                          title: 'Set sleep',
                          start: start,
                          end: end,
                          save: 'Save sleep',
                          hr: hr,
                          now: now))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(WindowChart), findsOneWidget);
    expect(find.text('No heart rate in this stretch'), findsNothing);

    // Nine tenths along the chart is nearer the end than the start: the end
    // follows the finger, the start stays.
    final chart = t.getRect(find.byType(WindowChart));
    await t.tapAt(Offset(chart.left + chart.width * .9, chart.center.dy));
    await t.pumpAndSettle();
    await t.tap(find.text('Save sleep'));
    await t.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.$1, start);
    expect(got!.$2.isAfter(end), isTrue);
    expect(got!.$2.minute % 5, 0);
  });
}
