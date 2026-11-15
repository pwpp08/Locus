// dayEnergy: the minutes under the heart-rate gate are priced, without a
// cliff and without paying a still wrist for a raised pulse.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/day_energy.dart';

const _profile = ana.WorkoutUserProfile(
    weightKg: 75, heightCm: 180, age: 30, sex: 'male');
const _hrmax = 190.0, _rhr = 55.0;
// 55 + 0.40 × 135.
const _gate = 109.0;

double _active(List<double> hr, {List<double?>? cad, List<double?>? move}) =>
    dayEnergy(hr,
            profile: _profile,
            hrmax: _hrmax,
            restingHr: _rhr,
            cadenceSpmPerMin: cad,
            moveSharePerMin: move)!
        .active;

void main() {
  test('over the gate it is the package arithmetic, to the calorie', () {
    final hr = [for (var i = 0; i < 120; i++) 120.0 + i % 30];
    final ours = dayEnergy(hr,
        profile: _profile, hrmax: _hrmax, restingHr: _rhr)!;
    final theirs = ana.Calories.dailyEnergy(hr,
        profile: _profile, hrmax: _hrmax, restingHr: _rhr)!;
    expect(ours.active, closeTo(theirs.active, 1e-9));
    expect(ours.basal, closeTo(theirs.basal, 1e-9));
  });

  test('a still wrist under the gate earns nothing, however fast the pulse',
      () {
    final hr = List.filled(240, 100.0);
    expect(_active(hr, move: List.filled(240, 0.0)), 0);
    expect(_active(hr), 0, reason: 'nothing measured the wrist');
  });

  test('a moving wrist under the gate earns, more as the pulse rises', () {
    double at(double bpm) =>
        _active(List.filled(60, bpm), move: List.filled(60, .5));
    expect(at(_rhr), 0);
    expect(at(80), greaterThan(0));
    expect(at(100), greaterThan(at(80)));
    // Never more than 3 METs: two basal minutes of surplus a minute.
    final basalPerMin =
        ana.Calories.mifflinBmrKcalDay(75, 180, 30, 'male') / 1440;
    expect(at(_gate - .01), lessThanOrEqualTo(60 * 2 * basalPerMin + 1e-9));
  });

  test('slow walking is priced, and meets the package at 100 steps a minute',
      () {
    double cad(double spm) =>
        _active(List.filled(60, 90.0), cad: List.filled(60, spm));
    expect(cad(5), 0, reason: 'a few steps is not walking');
    expect(cad(60), greaterThan(0));
    expect(cad(99.9), closeTo(cad(100), 1));
    final theirs = ana.Calories.dailyEnergy(List.filled(60, 90.0),
        profile: _profile,
        hrmax: _hrmax,
        restingHr: _rhr,
        cadenceSpmPerMin: List.filled(60, 110.0))!;
    expect(cad(110), closeTo(theirs.active, 1e-9));
  });

  test('a minute takes the larger price, never both', () {
    final hr = List.filled(60, 100.0);
    final both = _active(hr, cad: List.filled(60, 80.0), move: List.filled(60, 1.0));
    final cadOnly = _active(hr, cad: List.filled(60, 80.0));
    final moveOnly = _active(hr, move: List.filled(60, 1.0));
    expect(both, closeTo(cadOnly > moveOnly ? cadOnly : moveOnly, 1e-9));
  });

  test('no cliff at the gate for a walk: rising heart rate never lowers it',
      () {
    var last = 0.0;
    for (var bpm = 60.0; bpm <= 140; bpm += 1) {
      final v = _active([bpm], cad: [90.0], move: [.6]);
      expect(v, greaterThanOrEqualTo(last - 1e-9), reason: '$bpm bpm');
      last = v;
    }
  });

  test('no gate, no figure', () {
    expect(
        dayEnergy([100], profile: _profile, hrmax: 50, restingHr: _rhr),
        isNull);
  });
}
