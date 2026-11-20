// The phone's step count, corrected toward the user's other watch: one factor
// learned from the days both counted properly.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/step_calibration.dart';
import 'package:openstrap_edge/health/watch_step_reference.dart';

void main() {
  test('a phone that counts 1.1x the watch learns a factor under one', () {
    final p = estimatePhoneStepReference([
      for (var i = 0; i < 14; i++) (watch: 10000, phone: 11000),
    ]);
    expect(p.isCalibrated, isTrue);
    expect(p.deviceFamily, kPhoneStepRefFamily);
    // 14 days of 0.909 shrunk toward 1 by three pseudo-days.
    expect(p.factor, closeTo((14 * 10000 / 11000 + 3) / 17, 1e-9));
    expect(p.factor, lessThan(1));
  });

  test('under three good days nothing is learned', () {
    final p = estimatePhoneStepReference([
      (watch: 10000, phone: 11000),
      (watch: 9000, phone: 9900),
    ]);
    expect(p.isCalibrated, isFalse);
    expect(p.factor, 1);
  });

  test('a day one of them half-missed is left out', () {
    expect(stepRefDayAdmissible((watch: 10000, phone: 11000)), isTrue);
    expect(stepRefDayAdmissible((watch: 400, phone: 9000)), isFalse,
        reason: 'the watch was on the charger');
    expect(stepRefDayAdmissible((watch: 12000, phone: 3000)), isFalse,
        reason: 'the phone sat in a drawer');
  });

  test('the factor stays inside its band', () {
    final p = estimatePhoneStepReference([
      for (var i = 0; i < 60; i++) (watch: 6000, phone: 10000),
    ]);
    expect(p.factor, greaterThanOrEqualTo(kPhoneRefFactorMin));
  });
}
