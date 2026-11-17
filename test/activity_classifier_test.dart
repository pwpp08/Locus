// What a detected bout most likely was, and walk/run smoothing.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/activity_classifier.dart';
import 'package:openstrap_edge/compute/movement_bouts.dart';

/// A bout of [minutes] at [t0]: heart rate from [bpm], the wrist turning by
/// [move] each second (both functions of the second within the bout).
({List<int> ts, List<int> hr, List<double> ax, List<double> ay, List<double> az})
    _bout(int t0, int minutes, int Function(int s) bpm, double Function(int s) move) {
  final ts = <int>[], hr = <int>[];
  final ax = <double>[], ay = <double>[], az = <double>[];
  var angle = 0.0;
  for (var s = 0; s < minutes * 60; s++) {
    ts.add(t0 + s);
    hr.add(bpm(s));
    // Turn the unit gravity vector by about [move] each second.
    angle += move(s);
    ax.add(math.cos(angle));
    ay.add(math.sin(angle));
    az.add(0);
  }
  return (ts: ts, hr: hr, ax: ax, ay: ay, az: az);
}

int _sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

BoutFeatures _features(
  ({List<int> ts, List<int> hr, List<double> ax, List<double> ay, List<double> az}) b, {
  Map<int, int> steps = const {},
}) =>
    boutFeatures(
      tsSec: b.ts,
      hr: b.hr,
      startSec: b.ts.first,
      endSec: b.ts.last + 1,
      restingBpm: 55,
      maxBpm: 190,
      ax: b.ax,
      ay: b.ay,
      az: b.az,
      stepsPerMin: steps,
    )!;

void main() {
  final tuesday6pm = _sec(DateTime(2026, 11, 17, 18, 10));

  test('a steady cadence over 140 is a run', () {
    final b = _bout(tuesday6pm, 30, (_) => 160, (_) => .4);
    final steps = {for (var m = 0; m < 30; m++) tuesday6pm ~/ 60 + m: 165};
    expect(genericSport(_features(b, steps: steps)), 'running');
  });

  test('a still wrist under a steady raised heart rate is cycling', () {
    final b = _bout(tuesday6pm, 40, (s) => 140 + (s ~/ 60) % 3, (_) => .03);
    expect(genericSport(_features(b)), 'cycling');
  });

  test('sets and rests read as weight training', () {
    // Two minutes of work (heart up, wrist busy), two of rest.
    final b = _bout(
      tuesday6pm,
      40,
      (s) => (s ~/ 120).isEven ? 100 + (s % 120) ~/ 4 : 130 - (s % 120) ~/ 4,
      (s) => (s ~/ 120).isEven ? .6 : .02,
    );
    final f = _features(b);
    expect(f.swingsPer10Min, greaterThan(1.5));
    expect(genericSport(f), 'weight_training');
  });

  test('an unclear bout stays unnamed', () {
    final b = _bout(tuesday6pm, 30, (_) => 135, (_) => .4);
    expect(genericSport(_features(b)), kUnknownSport);
  });

  test('without enough heart rate there is nothing to describe', () {
    expect(
        boutFeatures(
            tsSec: const [1, 2, 3],
            hr: const [120, 120, 120],
            startSec: 1,
            endSec: 4,
            restingBpm: 55,
            maxBpm: 190),
        isNull);
  });

  group('their own sports', () {
    List<KeptSession> tennis({double? cadence}) => [
          for (final weeks in [1, 2, 3])
            KeptSession(
              'Tennis',
              tuesday6pm - weeks * 7 * 86400 - 600,
              tuesday6pm - weeks * 7 * 86400 + 60 * 60,
              hrrPeak: .62,
              cadenceSpm: cadence,
            ),
        ];

    test('a bout at their usual tennis time, as hard, is tennis', () {
      final b = _bout(tuesday6pm, 55, (s) => 120 + (s ~/ 90) % 20, (_) => .4);
      expect(classifyBout(_features(b), tennis()), 'tennis');
    });

    test('the same hour on a Saturday is not', () {
      final sat = _sec(DateTime(2026, 11, 21, 18, 10));
      final b = _bout(sat, 55, (s) => 120 + (s ~/ 90) % 20, (_) => .4);
      expect(classifyBout(_features(b), tennis()), kUnknownSport);
    });

    test('a run the steps prove stays a run, not their tennis', () {
      final b = _bout(tuesday6pm, 55, (_) => 150, (_) => .4);
      final steps = {for (var m = 0; m < 55; m++) tuesday6pm ~/ 60 + m: 165};
      expect(classifyBout(_features(b, steps: steps), tennis()), 'running');
    });

    test('one kept session is not yet a habit', () {
      final b = _bout(tuesday6pm, 55, (s) => 120 + (s ~/ 90) % 20, (_) => .4);
      expect(classifyBout(_features(b), tennis().take(1)), kUnknownSport);
    });
  });

  group('walk and run smoothing', () {
    const t0 = 1700000000 ~/ 60 * 60;
    Map<int, int> perMin(List<int> spm) =>
        {for (var i = 0; i < spm.length; i++) t0 ~/ 60 + i: spm[i]};
    MovementBout whole(int minutes) => MovementBout(
        startSec: t0, endSec: t0 + minutes * 60, steps: 0, sport: 'walking');

    test('a walk that turns into a run is two bouts', () {
      final spm = [...List.filled(20, 110), ...List.filled(15, 165)];
      final out = splitByGait(whole(35), perMin(spm));
      expect([for (final b in out) b.sport], ['walking', 'running']);
      expect(out.first.endSec, out.last.startSec);
      expect(out.last.minutes, 15);
      expect(out.last.steps, 15 * 165);
    });

    test('one fast minute does not break a walk', () {
      final spm = [...List.filled(12, 112), 158, ...List.filled(12, 108)];
      final out = splitByGait(whole(25), perMin(spm));
      expect(out, hasLength(1));
      expect(out.single.sport, 'walking');
    });

    test('a run with a short walk break stays a run', () {
      final spm = [
        ...List.filled(15, 165),
        ...List.filled(3, 115),
        ...List.filled(15, 162),
      ];
      final out = splitByGait(whole(33), perMin(spm));
      expect(out, hasLength(1));
      expect(out.single.sport, 'running');
    });
  });
}
