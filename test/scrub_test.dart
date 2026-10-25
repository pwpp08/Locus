// The scrub gesture and its geometry. The chart paints; these pin the part a
// finger depends on: which point is under it, and that the guide and the
// painted bar agree about where that point is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  const plot = Rect.fromLTWH(10, 0, 80, 10);

  test('a bar is the one whose slot the finger is in, edges clamp', () {
    expect(scrubIndexAt(-5, plot, 4, slots: true), 0);
    expect(scrubIndexAt(12, plot, 4, slots: true), 0);
    expect(scrubIndexAt(31, plot, 4, slots: true), 1);
    expect(scrubIndexAt(999, plot, 4, slots: true), 3);
  });

  test('a line point is the nearest one, edge to edge', () {
    expect(scrubIndexAt(10, plot, 11, slots: false), 0);
    expect(scrubIndexAt(50, plot, 11, slots: false), 5);
    expect(scrubIndexAt(90, plot, 11, slots: false), 10);
  });

  test('the guide is drawn through the bar the finger reads', () {
    for (var i = 0; i < 4; i++) {
      final x = scrubXOf(i, plot, 4, slots: true);
      expect(scrubIndexAt(x, plot, 4, slots: true), i);
    }
  });

  testWidgets('dragging reports each bar in turn, and lifting reports rest',
      (t) async {
    final seen = <int?>[];
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: ScrubColumns(
            values: const [1, 2, 3, 4],
            xLabels: const ['a', 'b', 'c', 'd'],
            lo: 0,
            hi: 4,
            ticks: const [0, 2, 4],
            tickText: (v) => v.toStringAsFixed(0),
            color: Colors.blue,
            onScrub: seen.add,
            height: 200,
          ),
        ),
      ),
    ));
    final box = t.getRect(find.byType(ScrubColumns));
    // The plot starts after the 40 px gutter and fills the rest: 70 px a bar.
    final start = Offset(box.left + 40 + 35, box.center.dy);
    final g = await t.startGesture(start);
    await t.pump();
    await g.moveBy(const Offset(70, 0));
    await t.pump();
    await g.moveBy(const Offset(70, 0));
    await t.pump();
    await g.moveBy(const Offset(70, 0));
    await t.pump();
    await g.up();
    await t.pump();
    expect(seen, [0, 1, 2, 3, null]);
  });

  testWidgets('a vertical swipe gives the chart up to the list', (t) async {
    final seen = <int?>[];
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: ScrubColumns(
            values: const [1, 2],
            xLabels: const ['a', 'b'],
            lo: 0,
            hi: 2,
            ticks: const [0, 2],
            tickText: (v) => v.toStringAsFixed(0),
            color: Colors.blue,
            onScrub: seen.add,
            height: 200,
          ),
        ),
      ),
    ));
    final box = t.getRect(find.byType(ScrubColumns));
    final g = await t.startGesture(Offset(box.center.dx, box.center.dy));
    await t.pump();
    await g.moveBy(const Offset(0, 30));
    await t.pump();
    expect(seen, [0, null]);
  });
}
