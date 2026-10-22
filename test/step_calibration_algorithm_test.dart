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
      // Clamped to kStepFactorMax
      expect(profile.factor, kStepFactorMax);
    });

    test('factor clamping respects high range clamp', () {
      const profile = StepCalibrationProfile(
        deviceFamily: 'whoop',
        wearing: Wearing.wrist,
        factor: 25.0, // High factor due to throttled BLE / dropped packets
        nDays: 1,
        version: 1,
      );

      expect(profile.factor, 25.0);
      expect(applyStepCalibration(100, profile), (100 * kStepFactorMax).round());
    });

    test('handles 1000-step walk test calibration ratio', () {
      // During guided walk test: user took exactly 1000 steps, Whoop registered 600 steps
      const targetSteps = 1000;
      const recordedStrap = 600;

      final ratio = (targetSteps / recordedStrap).clamp(kStepFactorMin, kStepFactorMax);
      final profile = StepCalibrationProfile(
        deviceFamily: 'whoop',
        wearing: Wearing.wrist,
        factor: ratio,
        nDays: 1,
        version: 1,
      );

      expect(profile.factor, closeTo(1.67, 0.01));
      expect(applyStepCalibration(600, profile), 1000);
    });
  });
}
