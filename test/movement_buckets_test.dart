// The one movement definition: the share of seconds in which the wrist
// turned more than 5°, per bucket. The day's stored 5-minute curve and the
// per-minute lanes under the nap and day charts all read it, so a minute that
// is "moving" in one place cannot be "still" in another.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/manual_session.dart';
import 'package:openstrap_edge/compute/movement.dart';
import 'package:openstrap_edge/compute/profile.dart';

/// A gravity vector tilted [deg] degrees off flat.
(double, double, double) _tilt(double deg) {
  final r = deg * 3.141592653589793 / 180;
  return (0.0, _sin(r), _cos(r));
}

double _sin(double x) {
  var t = x, s = x;
  for (var i = 1; i < 12; i++) {
    t *= -x * x / ((2 * i) * (2 * i + 1));
    s += t;
  }
  return s;
}

double _cos(double x) => _sin(x + 3.141592653589793 / 2);

void main() {
  test('a still minute reads 0, a turning one reads its share', () {
    final ts = <int>[], ax = <double>[], ay = <double>[], az = <double>[];
    // Minute 0: flat throughout. Minute 1: a 20° turn every other second.
    for (var s = 0; s < 120; s++) {
      final deg = s < 60 ? 0.0 : (s.isEven ? 0.0 : 20.0);
      final (x, y, z) = _tilt(deg);
      ts.add(6000 + s);
      ax.add(x);
      ay.add(y);
      az.add(z);
    }
    final m = movementBuckets(ts, ax, ay, az, bucketSec: 60);
    expect(m.length, 2);
    expect(m[0].t, 6000);
    expect(m[0].v, 0);
    // Second 60 is flat like second 59, so it did not turn; the other 59 of
    // minute 1 each turned against the second before.
    expect(m[1].t, 6060);
    expect(m[1].v, closeTo(59 / 60, .001));
  });

  test('seconds with no gravity vector are left out, not scored still', () {
    final ts = [0, 1, 2, 3];
    final (x, y, z) = _tilt(0);
    final m = movementBuckets(ts, [x, 0, 0, x], [y, 0, 0, y], [z, 0, 0, z],
        bucketSec: 60);
    // Pairs (0,1), (1,2), (2,3) each touch a zero vector: nothing is counted,
    // and a bucket with nothing counted is not emitted at all.
    expect(m, isEmpty);
  });

  test('a second two devices both logged is counted once', () {
    final (x, y, z) = _tilt(0);
    final row = {'rec_ts': 10, 'ax': x, 'ay': y, 'az': z};
    final m = movementPerMinuteOfRows([
      row,
      row,
      {'rec_ts': 11, 'ax': x, 'ay': y, 'az': z},
    ]);
    expect(m.single.v, 0);
  });

  group('the strain curve', () {
    const profile = Profile(ageYears: 30, sex: 'm', weightKg: 75);
    final perMin = [
      for (var i = 0; i < 40; i++)
        (t: 6000 + i * 60, v: i < 10 ? 95.0 : (i < 30 ? 155.0 : 120.0)),
    ];

    test('it ends at the session strain and never falls', () {
      final curve = strainCurveOf(perMin,
          profile: profile, restingHr: 55, hrMax: 190, quietHrr: .2);
      expect(curve.length, perMin.length);
      final whole = strainFromPerMinuteHr([for (final m in perMin) m.v],
          profile: profile, restingHr: 55, hrMax: 190, quietHrr: .2);
      expect(curve.last.v, closeTo(whole!, 1e-9));
      // Each point is the end of its minute.
      expect(curve.first.t, perMin.first.t + 60);
      for (var i = 1; i < curve.length; i++) {
        expect(curve[i].v, greaterThanOrEqualTo(curve[i - 1].v - 1e-9));
      }
    });

    test('a missing anchor is no curve, not one built on a default', () {
      expect(
          strainCurveOf(perMin,
              profile: profile, restingHr: null, hrMax: 190, quietHrr: .2),
          isEmpty);
    });

    test('a minute bucket keeps its start, and the plain series agrees', () {
      final ts = [120, 130, 185, 300];
      final bpm = [100, 110, 120, 90];
      final stamped = hrPerMinuteStamped(ts, bpm);
      expect([for (final m in stamped) m.t], [120, 180, 300]);
      expect(hrPerMinute(ts, bpm), [for (final m in stamped) m.v]);
    });
  });
}
