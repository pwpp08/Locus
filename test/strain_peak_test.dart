// Strain is effort earned: once a level is reached the day keeps it. The
// analytics curve is net of recovery and can fall; the edge keeps its peak.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/strain_peak.dart';

void main() {
  // The analytics' own worked example of a falling net curve: 120 min at
  // 0.30 HRR, 45 min at 145 bpm, then 735 min at 0.10 HRR (RHR 50, HRmax 187,
  // quiet level 0.20) reads 10.74 after the run and 9.38 at the day's end.
  final hr = [
    for (var i = 0; i < 120; i++) 50 + .30 * 137,
    for (var i = 0; i < 45; i++) 145.0,
    for (var i = 0; i < 735; i++) 50 + .10 * 137,
  ];

  test('the kept curve never falls and ends on its own peak', () {
    final c = keptStrainCurve(hr,
        restingHr: 50, maxHr: 187, quietHrr: .20, sex: ana.Sex.male)!;
    for (var i = 1; i < c.length; i++) {
      expect(c[i], greaterThanOrEqualTo(c[i - 1]));
    }
    final peak = peakStrain(hr,
        restingHr: 50, maxHr: 187, quietHrr: .20, sex: ana.Sex.male)!;
    expect(peak, c.last);
    final raw = ana.strainCurveFromSeries(hr,
        restingHr: 50, maxHr: 187, quietHrr: .20, sex: ana.Sex.male)!;
    expect(peak, raw.reduce((a, b) => a > b ? a : b));
    expect(raw.last, lessThan(peak), reason: 'the net curve did fall');
  });

  test('no curve, no strain — never a zero', () {
    expect(
        peakStrain(const [],
            restingHr: null, maxHr: null, quietHrr: null, sex: ana.Sex.male),
        isNull);
  });
}
