// The mark is the traced artwork; the pen that writes it must, by the end,
// have laid ink over all of it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  test('the outline sits inside the source frame and the route inside it',
      () {
    final b = locusOutlinePath().getBounds();
    expect(b.left, greaterThan(0));
    expect(b.right, lessThan(1000));
    expect(kLocusRoute.length % 3, 0);
    final outline = locusOutlinePath();
    // Every pen sample lies on the stroke (the counters are holes).
    var inside = 0;
    for (var k = 0; k < kLocusRoute.length; k += 3) {
      if (outline.contains(Offset(kLocusRoute[k], kLocusRoute[k + 1]))) {
        inside++;
      }
    }
    expect(inside, greaterThan(kLocusRoute.length ~/ 3 * .95));
  });

  testWidgets('written once, it lands and says so', (t) async {
    var drawn = false;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: LocusMark(animate: true, onDrawn: () => drawn = true),
    ));
    expect(drawn, isFalse);
    await t.pump(Motion.logo);
    expect(drawn, isTrue);
  });
}
