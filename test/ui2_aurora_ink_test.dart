// Text on an aurora field clears 4.5:1 against the field's brightest point.
//
// `P.aurora` is solved for the page ink ONLY. The muted inks measure 1.6–2.6:1
// on a dark peak, and the first aurora tiles shipped their labels in ink2 and
// their units in ink3 — legible in light, 2:1 in dark, and nothing failed,
// because the contrast sweep measures tokens, not what a widget picked. This
// measures what the widgets actually painted.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

const _aa = 4.5;

void main() {
  // The one aurora left in the app: the Total sleep hero, lavender, with the
  // words it carries (the sleep screen builds it the same way).
  final cases = <String, (Color, Widget)>{
    'Total sleep hero': (
      C.lavender,
      Builder(builder: (c) {
        final p = P.of(c);
        return AuroraTile(
          hue: C.lavender,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total sleep', style: F.cap.copyWith(color: p.ink)),
            Text('9h 03m', style: F.n64.copyWith(color: p.ink)),
            Text('23:18 → 09:34', style: F.body.copyWith(color: p.ink)),
          ]),
        );
      }),
    ),
  };

  for (final b in Brightness.values) {
    for (final e in cases.entries) {
      testWidgets('${e.key} · ${b.name}: every word clears AA on the peak',
          (t) async {
        final (hue, widget) = e.value;
        await t.pumpWidget(MaterialApp(
          theme: buildTheme(b),
          home: Scaffold(body: SingleChildScrollView(child: widget)),
        ));
        final p = P(b == Brightness.dark);
        final peak = p.aurora(hue);
        final texts = t.widgetList<Text>(find.descendant(
            of: find.byType(AuroraTile), matching: find.byType(Text)));
        expect(texts, isNotEmpty);
        for (final text in texts) {
          final ink = text.style?.color;
          expect(ink, isNotNull, reason: '"${text.data}" has no colour');
          final r = P.contrast(ink!, peak);
          expect(r, greaterThanOrEqualTo(_aa),
              reason: '"${text.data}" measures ${r.toStringAsFixed(2)}:1 on '
                  'the aurora peak in ${b.name}. Only p.ink is solved there.');
        }
      });
    }
  }
}
