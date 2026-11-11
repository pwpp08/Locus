// Today's projected strain: earlier days' load gains after now, averaged and
// added in load (not strain) on top of today's, and nothing without enough days.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/strain_projection.dart';
import 'package:openstrap_edge/compute/whoop_scores.dart';

/// A day that sits at [from] until minute [at], then at [to].
List<double?> _day(double from, int at, double to) =>
    [for (var m = 0; m < 1440; m++) m < at ? from : to];

void main() {
  test('the mean load gain goes on top of today, in load', () {
    final today = <double?>[
      for (var m = 0; m < 1440; m++) m <= 600 ? 8 : null,
    ];
    final before = [
      _day(4, 1000, 10),
      _day(6, 1000, 12),
      _day(5, 1200, 9),
    ];
    final p = projectStrain(today, 600, before)!;
    expect(p.length, 840);
    expect(p.first, closeTo(8, 1e-9));
    final gain = [
      whoopLoadForStrain(10) - whoopLoadForStrain(4),
      whoopLoadForStrain(12) - whoopLoadForStrain(6),
      whoopLoadForStrain(9) - whoopLoadForStrain(5),
    ].reduce((a, b) => a + b) / 3;
    expect(p.last,
        closeTo(whoopStrainFromLoad(whoopLoadForStrain(8) + gain), 1e-9));
    // Never below where today already is.
    expect(p.every((v) => v >= 8 - 1e-9), isTrue);
  });

  test('too few days, or no value now, says nothing', () {
    final today = <double?>[for (var m = 0; m < 1440; m++) 5];
    expect(projectStrain(today, 600, [_day(4, 900, 9), _day(4, 900, 9)]),
        isNull);
    expect(projectStrain([...today]..[600] = null, 600,
        [for (var i = 0; i < 3; i++) _day(4, 900, 9)]), isNull);
    expect(projectStrain(today, 1439,
        [for (var i = 0; i < 3; i++) _day(4, 900, 9)]), isNull);
  });
}
