import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/hr_max.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/health/watch_compare.dart';

void main() {
  group('manual max heart rate', () {
    test('replaces the age estimate when set', () {
      expect(estimatedMaxHr(30, 'gen4'), closeTo(187, 0.01));
      expect(estimatedMaxHr(30, 'gen4', manualMaxHr: 201), 201);
      // No age needed when the user knows their max.
      expect(estimatedMaxHr(null, null, manualMaxHr: 195), 195);
    });

    test('out-of-range values are ignored, never clamped', () {
      expect(estimatedMaxHr(30, 'gen4', manualMaxHr: 60), closeTo(187, 0.01));
      expect(manualMaxHrFromProfile({'max_hr': 400}), isNull);
      expect(manualMaxHrFromProfile({'max_hr': 'abc'}), isNull);
      expect(manualMaxHrFromProfile({'max_hr': 190}), 190);
      expect(manualMaxHrFromProfile(null), isNull);
    });

    test('zones band off it, but manual zone edges still win', () {
      final z = trainingZones(age: 30, deviceFamily: 'gen4', manualMaxHr: 200)!;
      expect(z.source, 'user_max');
      expect(z.maxHr, 200);
      // Beats a measured ceiling too.
      final z2 = trainingZones(
          age: 30,
          deviceFamily: 'gen4',
          observedCeilingBpm: 192,
          manualMaxHr: 200)!;
      expect(z2.source, 'user_max');
      final m = trainingZones(
          age: 30,
          manualMaxHr: 200,
          manualZoneLowerBpm: const [100, 120, 140, 160, 180])!;
      expect(m.source, 'manual');
    });

    test('survives the Profile round trip into the day derive', () {
      final p = Profile.fromMap({'age': 30, 'max_hr': 199});
      expect(p.maxHrManual, 199);
      expect(p.toMap()['max_hr'], 199);
      expect(Profile.fromMap({'age': 30}).toMap().containsKey('max_hr'),
          isFalse);
    });
  });

  group('HrAgreement', () {
    test('pairs minutes and reports watch − band', () {
      final band = [for (var m = 0; m < 30; m++) (m * 60, 60.0 + m)];
      final watch = [for (var m = 0; m < 30; m++) (m * 60 + 20, 62.0 + m)];
      final a = HrAgreement.of(band, watch)!;
      expect(a.pairedMinutes, 30);
      expect(a.meanDiff, closeTo(2, 1e-9));
      expect(a.meanAbsDiff, closeTo(2, 1e-9));
      expect(a.r, closeTo(1, 1e-9));
    });

    test('abstains on too few shared minutes', () {
      final band = [for (var m = 0; m < 30; m++) (m * 60, 60.0)];
      final watch = [(0, 61.0), (600, 62.0)];
      expect(HrAgreement.of(band, watch), isNull);
    });
  });
}
