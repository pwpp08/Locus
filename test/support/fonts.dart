// The app's type families for widget tests.
//
// `F` sets every style in D-DIN digits first and Figtree after it
// (assets/fonts). The test harness knows no family it is not handed, so
// without this every glyph measures as the harness's block font and a layout
// test is measuring the wrong text. Manrope is Figtree's Cyrillic fallback.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:openstrap_edge/ui2/theme.dart';

Future<void> loadAppFonts() async {
  for (final (family, dir) in [
    (F.family, 'assets/fonts/Figtree'),
    (F.numerals, 'assets/fonts/DDINNums'),
    (F.headline, 'assets/fonts/Montserrat'),
    ('Manrope', 'assets/fonts/Manrope'),
  ]) {
    final loader = FontLoader(family);
    for (final f in Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))) {
      loader.addFont(f
          .readAsBytes()
          .then((b) => ByteData.sublistView(Uint8List.fromList(b))));
    }
    await loader.load();
  }
}
