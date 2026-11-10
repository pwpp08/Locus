// The two gen4 v24 fields kept raw for research sit at inner[72] (i16 LE) and
// inner[82] (u8). The tail they are read from starts at inner[13], so an
// off-by-one here would quietly record a neighbouring field instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/models.dart' show gen4ResearchFields;

/// A v24 tail (inner[13..99]) with [word] at inner[72] and [byte] at inner[82].
String tail({required int word, required int byte}) {
  final b = List<int>.filled(100 - 13, 0xAA);
  final u = word & 0xFFFF;
  b[72 - 13] = u & 0xFF;
  b[73 - 13] = u >> 8;
  b[82 - 13] = byte;
  return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  test('reads the word at inner[72] and the byte at inner[82] of a v24 record',
      () {
    final f = gen4ResearchFields(24, tail(word: 337, byte: 97));
    expect(f.word72, 337); // 33.7 °C, if the firmware trace holds
    expect(f.byte82, 97);
  });

  test('the word is signed', () {
    expect(gen4ResearchFields(24, tail(word: -12, byte: 0)).word72, -12);
  });

  test('anything but v24, or a short tail, gives nothing', () {
    expect(gen4ResearchFields(12, tail(word: 337, byte: 97)),
        (word72: null, byte82: null));
    expect(gen4ResearchFields(24, 'aabb'), (word72: null, byte82: null));
  });
}
