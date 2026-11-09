// The energy reserve's arithmetic and the wrist-twist that |a| cannot see.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/energy_reserve.dart';
import 'package:openstrap_edge/state/alarm_shake.dart';

void main() {
  group('energy reserve', () {
    const midnight = 1000000;
    const wake = midnight + 7 * 3600;
    List<(int, double)> day(double bpm, {int mins = 240}) => [
      for (var i = 0; i < mins; i++) (wake + i * 60, bpm),
    ];

    test('no reading without every input', () {
      expect(
        energyReserve(
          hr: day(60),
          onsetTs: wake - 8 * 3600,
          wakeTs: wake,
          recovery: null,
          restingHr: 55,
          maxHr: 190,
          midnight: midnight,
        ),
        isNull,
      );
      expect(
        energyReserve(
          hr: const [],
          onsetTs: wake - 8 * 3600,
          wakeTs: wake,
          recovery: 60,
          restingHr: 55,
          maxHr: 190,
          midnight: midnight,
        ),
        isNull,
      );
    });

    EnergyReserve run(List<(int, double)> hr) => energyReserve(
      hr: hr,
      onsetTs: wake - 8 * 3600,
      wakeTs: wake,
      recovery: 60,
      restingHr: 55,
      maxHr: 190,
      midnight: midnight,
    )!;

    test('effort drains faster than rest and is listed', () {
      final rest = run(day(58));
      final hard = run(day(150, mins: 45));
      expect(hard.level, lessThan(rest.level));
      expect(hard.activities, hasLength(1));
      expect(rest.activities, isEmpty);
    });

    test('time off the wrist changes nothing', () {
      final r = run([
        (wake, 58),
        (wake + 60, 58),
        (wake + 6 * 3600, 58),
      ]);
      expect(r.drained, lessThan(1));
    });
  });

  group('wrist twist', () {
    // Gravity whipping back and forth at about 3 Hz: |a| stays exactly 1 g.
    (List<double>, List<double>, List<double>) twist(double start, int n) {
      final xs = <double>[], ys = <double>[];
      for (var i = 0; i < n; i++) {
        final a = math.sin(start + i * .2) * 1.4;
        xs.add(math.cos(a) * 4096);
        ys.add(math.sin(a) * 4096);
      }
      return (xs, ys, List.filled(n, 0.0));
    }

    test('a rotation with no change in |a| still stops the alarm', () {
      final d = AlarmShakeDetector();
      var fired = false;
      for (var f = 0; f < 15 && !fired; f++) {
        final (xs, ys, zs) = twist(f * 2.0, 10);
        fired = d.add(List.filled(10, 1.0), f * 100, xs: xs, ys: ys, zs: zs);
      }
      expect(fired, isTrue);
    });

    test('a slow roll-over does not', () {
      final d = AlarmShakeDetector();
      for (var f = 0; f < 40; f++) {
        final xs = <double>[], ys = <double>[];
        for (var i = 0; i < 10; i++) {
          final a = (f * 10 + i) * .004;
          xs.add(math.cos(a) * 4096);
          ys.add(math.sin(a) * 4096);
        }
        expect(
          d.add(List.filled(10, 1.0), f * 100, xs: xs, ys: ys,
              zs: List.filled(10, 0.0)),
          isFalse,
        );
      }
    });
  });
}
