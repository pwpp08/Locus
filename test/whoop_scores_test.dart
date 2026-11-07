// WHOOP-parity scores pinned to the numbers WHOOP itself publishes, and to the
// fits they come from (docs/proposals/whoop-parity-research.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/strain_peak.dart';
import 'package:openstrap_edge/compute/whoop_scores.dart';

void main() {
  group('recovery', () {
    // Fourteen nights around 60 ms / 50 bpm / 15 rpm.
    final hrv = [for (var i = 0; i < 14; i++) 55.0 + (i % 5) * 2.5];
    final rhr = [for (var i = 0; i < 14; i++) 48.0 + (i % 5)];
    final resp = [for (var i = 0; i < 14; i++) 14.6 + (i % 5) * .2];

    double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

    test('a night at baseline reads 67.5 %', () {
      final r = whoopRecovery(
          hrvMs: mean(hrv), hrvHistoryMs: hrv, rhr: mean(rhr),
          rhrHistory: rhr, resp: mean(resp), respHistory: resp);
      expect(r.value!.score, closeTo(67.5, 0.1));
    });

    test('higher HRV and lower RHR score higher', () {
      double s(double h, double r) => whoopRecovery(
              hrvMs: h, hrvHistoryMs: hrv, rhr: r, rhrHistory: rhr,
              resp: 15, respHistory: resp)
          .value!
          .score;
      expect(s(70, 50), greaterThan(s(60, 50)));
      expect(s(60, 46), greaterThan(s(60, 54)));
      expect(s(45, 50), lessThan(kWhoopRecoveryRedBelow + 20));
    });

    test('no HRV, or under five nights of it: absent, never partial', () {
      expect(
          whoopRecovery(hrvMs: null, hrvHistoryMs: hrv, rhr: 50,
                  rhrHistory: rhr, resp: 15, respHistory: resp)
              .present,
          isFalse);
      final short = whoopRecovery(hrvMs: 60, hrvHistoryMs: hrv.sublist(0, 4),
          rhr: 50, rhrHistory: rhr, resp: 15, respHistory: resp);
      expect(short.present, isFalse);
      expect(short.note, 'need_baseline:have=4,need=5');
    });
  });

  group('strain', () {
    const rhr = 50.0, max = 190.0;
    double hourAt(double x) => peakStrain(
        [for (var i = 0; i < 60; i++) rhr + x * (max - rhr)],
        restingHr: rhr, maxHr: max)!;

    test("WHOOP's own examples: an hour walking ≈ 6.5, running ≈ 12", () {
      expect(hourAt(.35), closeTo(6.5, 0.6));
      expect(hourAt(.60), closeTo(12.0, 1.0));
    });

    test('sitting is free, the curve never falls, and it caps at 21', () {
      expect(hourAt(.15), 0);
      final c = keptStrainCurve(
          [for (var i = 0; i < 300; i++) i < 100 ? 170.0 : 60.0],
          restingHr: rhr, maxHr: max)!;
      for (var i = 1; i < c.length; i++) {
        expect(c[i], greaterThanOrEqualTo(c[i - 1]));
      }
      expect(whoopStrainFromLoad(1e9), 21);
      expect(whoopLoadForStrain(whoopStrainFromLoad(500)), closeTo(500, 1e-6));
    });

    test('no anchors, no strain — never a zero', () {
      expect(peakStrain(const [], restingHr: null, maxHr: null), isNull);
      expect(peakStrain(const [120], restingHr: 60, maxHr: 60), isNull);
    });
  });

  group('sleep', () {
    test("strain's sleep need matches WHOOP's readouts", () {
      // WHOOP prints whole minutes, and the two app Strains were "about".
      expect(whoopStrainSleepMin(15), closeTo(37, 1)); // WHOOP's example
      expect(whoopStrainSleepMin(10.2), closeTo(12, 1));
      expect(whoopStrainSleepMin(11.1), closeTo(16, 1));
    });

    test('debt is half of last night\'s shortfall, one night deep', () {
      final c = whoopSleepNeeds(
        baselineMin: 480,
        nights: const [
          (tstMin: 380, priorStrain: null, priorNapMin: null), // 100 short
          (tstMin: null, priorStrain: null, priorNapMin: null), // skipped
        ],
        todayStrain: null,
        todayNapMin: 30,
      );
      expect(c[0].needMin, 480);
      expect(c[1].debtMin, 50);
      // Tonight: the debt still comes from the last night WITH sleep.
      expect(c.last.debtMin, 50);
      expect(c.last.needMin, 480 + 50 - 30);
    });

    test('consistency: identical nights 100, needs three', () {
      const n = (onset: 23 * 60.0 + 30, wake: 23 * 60.0 + 30 + 480);
      expect(whoopSleepConsistency([n, n]), isNull);
      expect(whoopSleepConsistency([n, n, n, n]), closeTo(100, 1e-9));
      const late = (onset: 25 * 60.0 + 30, wake: 25 * 60.0 + 30 + 480);
      expect(whoopSleepConsistency([n, n, late]), lessThan(60));
    });

    test('performance is the fitted blend, without restorative sleep', () {
      expect(
          whoopSleepPerformance(
              tstMin: 480, needMin: 480, efficiencyPct: 90, consistencyPct: 80),
          closeTo(0.272 * 100 + 0.327 * 80 + 0.368 * 90, 1e-9));
      expect(
          whoopSleepPerformance(tstMin: 480, needMin: 480, efficiencyPct: null),
          isNull);
    });
  });

  group('health monitor', () {
    final prior = [for (var i = 0; i < 30; i++) 50.0 + i % 5]; // 50..54, sd ≈ 1.4
    test('typical range is the middle half of the last 30 nights', () {
      final r = whoopMonitorReading(52, prior, harmfulUp: true)!;
      expect(r.lo, 51);
      expect(r.hi, 53);
      expect(r.flagged, isFalse);
    });
    test('only the harmful side, far out, is flagged', () {
      expect(whoopMonitorReading(54.5, prior, harmfulUp: true)!.flagged, isFalse);
      expect(whoopMonitorReading(55.5, prior, harmfulUp: true)!.flagged, isTrue);
      expect(whoopMonitorReading(40, prior, harmfulUp: true)!.flagged, isFalse);
      expect(whoopMonitorReading(40, prior, harmfulUp: false)!.flagged, isTrue);
    });
    test('abstains under 14 nights', () {
      expect(whoopMonitorReading(52, prior.sublist(0, 13), harmfulUp: true),
          isNull);
    });
  });

  group('strain target', () {
    test("WHOOP's example: recovery 70% → 8.3–16.3, optimal 12.3", () {
      final t = whoopStrainTarget(70)!;
      expect(t.optimal, closeTo(12.3, 1e-9));
      expect(t.lo, closeTo(8.3, 1e-9));
      expect(t.hi, closeTo(16.3, 1e-9));
    });
    test('stays on the 0–21 scale and abstains without recovery', () {
      expect(whoopStrainTarget(0)!.lo, 2);
      expect(whoopStrainTarget(100)!.hi, 19);
      expect(whoopStrainTarget(null), isNull);
    });
  });
}
