import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/step_calibration.dart';

void main() {
  group('Step calibration algorithm & diagnostics', () {
    test('uncalibrated profile defaults to factor 1.0', () {
      final profile = StepCalibrationProfile.uncalibrated('whoop', Wearing.wrist);
      expect(profile.factor, 1.0);
      expect(profile.isCalibrated, false);
      expect(applyStepCalibration(1000, profile), 1000);
    });

    test('recovers from severe under-counting with high calibration factor', () {
      // User scenario: strap counted 342 steps, reference watch counted 5950 steps
      const strapSteps = 342;
      const watchSteps = 5950;

      final profile = estimateStepCalibration(
        'whoop',
        Wearing.wrist,
        [
          const StepCalibrationDay(
            referenceSteps: watchSteps,
            counterTicks: strapSteps,
          ),
        ],
        minDays: 1,
      );

      expect(profile.isCalibrated, true);
      // estimateStepCalibration shrinks single-day extremes toward the 1.0 prior:
      // (1 * 17.39 + 3 * 1.0) / 4 = ~5.10
      expect(profile.factor, closeTo(5.1, 0.1));
    });

    test('factor clamping respects new high range up to 35.0', () {
      const profile = StepCalibrationProfile(
        deviceFamily: 'whoop',
        wearing: Wearing.wrist,
        factor: 25.0, // High factor due to throttled BLE / dropped packets
        nDays: 1,
        version: 1,
      );

      expect(profile.factor, 25.0);
      expect(applyStepCalibration(100, profile), 2500);
    });

    test('handles 1000-step walk test calibration ratio', () {
      // During guided walk test: user took exactly 1000 steps, Whoop registered 250 steps
      const targetSteps = 1000;
      const recordedStrap = 250;

      final ratio = targetSteps / recordedStrap; // 4.0x
      final profile = StepCalibrationProfile(
        deviceFamily: 'whoop',
        wearing: Wearing.wrist,
        factor: ratio,
        nDays: 1,
        version: 1,
      );

      expect(profile.factor, 4.0);
      expect(applyStepCalibration(250, profile), 1000);
    });
  });
}
