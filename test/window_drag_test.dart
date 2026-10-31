// A possible nap's chart: its start and end lines move under a finger, any
// other drag pans, two fingers zoom, and there are no handles to drag a zoom.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/window_editor.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

const _start = 1787157000, _end = 1787160600; // an hour

Future<List<HrPoint>> _hr(int a, int b) async => [
      for (var t = a; t < b; t += 60) (t: t, v: 60.0 + (t ~/ 60) % 7),
    ];

void main() {
  setUpAll(loadAppFonts);

  Future<List<(int, int)>> pump(WidgetTester t, {bool editable = true}) async {
    final moves = <(int, int)>[];
    t.view.physicalSize = const Size(390 * 2, 600 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: WindowPreview(
            start: _start,
            end: _end,
            kind: WindowKind.nap,
            hr: _hr,
            zoomable: true,
            height: 160,
            onChanged: editable ? (a, b) => moves.add((a, b)) : null,
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    return moves;
  }

  // The view opens with a third of the window's length either side.
  Offset at(WidgetTester t, double frac) {
    final r = t.getRect(find.byType(WindowChart));
    return Offset(r.left + r.width * frac, r.center.dy);
  }

  testWidgets('a finger on the start line moves the start, not the end',
      (t) async {
    final moves = await pump(t);
    // pad = max(1h, dur/3) = 1h: the view is 3h wide, the start a third in.
    await t.dragFrom(at(t, 1 / 3), const Offset(40, 0));
    await t.pump();
    expect(moves, isNotEmpty);
    expect(moves.last.$1, greaterThan(_start));
    expect(moves.last.$2, _end);
  });

  testWidgets('a finger on the end line moves the end', (t) async {
    final moves = await pump(t);
    await t.dragFrom(at(t, 2 / 3), const Offset(-30, 0));
    await t.pump();
    expect(moves.last.$1, _start);
    expect(moves.last.$2, lessThan(_end));
  });

  testWidgets('a drag away from both lines pans and leaves the window alone',
      (t) async {
    final moves = await pump(t);
    await t.dragFrom(at(t, .9), const Offset(-60, 0));
    await t.pump();
    expect(moves, isEmpty);
  });

  testWidgets('a read-only card pans too, and never edits', (t) async {
    final moves = await pump(t, editable: false);
    await t.dragFrom(at(t, 1 / 3), const Offset(40, 0));
    await t.pump();
    expect(moves, isEmpty);
  });

  testWidgets('no range bar, no handle hint', (t) async {
    await pump(t);
    expect(find.byType(RangeSlider), findsNothing);
    expect(find.textContaining('handles'), findsNothing);
    expect(find.text('HEART RATE'), findsOneWidget);
  });
}
