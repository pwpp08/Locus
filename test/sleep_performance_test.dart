import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/sleep_performance.dart';

void main() {
  group('computeAdjustedSleepPerformance', () {
    test('returns 0 when need or tst is 0 or negative', () {
      expect(computeAdjustedSleepPerformance(tstMin: 0, needMin: 480), 0.0);
      expect(computeAdjustedSleepPerformance(tstMin: 480, needMin: 0), 0.0);
      expect(computeAdjustedSleepPerformance(tstMin: -10, needMin: 480), 0.0);
    });

    test('falls back to pure duration when efficiency and stages are missing', () {
      final score = computeAdjustedSleepPerformance(tstMin: 360, needMin: 480);
      expect(score, closeTo(75.0, 0.1));
    });

    test('caps pure duration at 100', () {
      final score = computeAdjustedSleepPerformance(tstMin: 600, needMin: 480);
      expect(score, 100.0);
    });

    test('adjusts downwards when efficiency is low even if duration is 100%', () {
      // 100% duration, but poor efficiency (70%) and poor restorative (20%)
      final score = computeAdjustedSleepPerformance(
        tstMin: 480,
        needMin: 480,
        efficiencyPct: 70.0,
        remMin: 48,
        deepMin: 48, // restorative ratio = 96 / 480 = 0.20 (50% of optimal 0.40)
      );
      // DurationScore = 100 (65%)
      // EffScore = (70/90)*100 = 77.78 (20%)
      // RestorativeScore = (0.20/0.40)*100 = 50.0 (15%)
      // Total = 65 + 15.56 + 7.5 = 88.06%
      expect(score, lessThan(90.0));
      expect(score, greaterThan(80.0));
    });

    test('gives 100% when duration, efficiency (>=90%) and restorative (>=40%) are optimal', () {
      final score = computeAdjustedSleepPerformance(
        tstMin: 480,
        needMin: 480,
        efficiencyPct: 92.0,
        remMin: 100,
        deepMin: 100, // restorative ratio = 200 / 480 = 41.7% > 40%
      );
      expect(score, 100.0);
    });

    test('handles 0..1 scale efficiency correctly', () {
      final scoreWithPct = computeAdjustedSleepPerformance(
        tstMin: 480,
        needMin: 480,
        efficiencyPct: 85.0,
      );
      final scoreWithDec = computeAdjustedSleepPerformance(
        tstMin: 480,
        needMin: 480,
        efficiencyPct: 0.85,
      );
      expect(scoreWithDec, closeTo(scoreWithPct, 0.001));
    });
  });
}
