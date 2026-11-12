import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/movement_bouts.dart';

/// [minutes] of 1 Hz samples from [startSec], stepping at [spm].
({List<int> ts, List<int> steps}) walk(int startSec, int minutes, int spm,
    {int from = 0}) {
  final ts = <int>[], steps = <int>[];
  var c = from.toDouble();
  for (var i = 0; i < minutes * 60; i++) {
    ts.add(startSec + i);
    steps.add(c.floor() % 65536);
    c += spm / 60;
  }
  return (ts: ts, steps: steps);
}

void main() {
  final t0 = DateTime(2026, 11, 4, 7, 40).millisecondsSinceEpoch ~/ 1000;

  test('a 20-minute walk at 110 spm is one walking bout', () {
    final w = walk(t0, 20, 110);
    final b = detectMovementBouts(tsSec: w.ts, stepCount: w.steps);
    expect(b, hasLength(1));
    expect(b.single.sport, 'walking');
    expect(b.single.minutes, closeTo(20, 1));
    expect(b.single.cadenceSpm, closeTo(110, 6));
  });

  test('a fast cadence is a run; the counter wrapping is not a reset', () {
    final w = walk(t0, 20, 160, from: 65000);
    final b = detectMovementBouts(tsSec: w.ts, stepCount: w.steps);
    expect(b.single.sport, 'running');
  });

  test('fourteen minutes proposes nothing; sixteen is a walk', () {
    final w = walk(t0, 14, 110);
    expect(detectMovementBouts(tsSec: w.ts, stepCount: w.steps), isEmpty);
    final long = walk(t0, 16, 110);
    expect(detectMovementBouts(tsSec: long.ts, stepCount: long.steps),
        hasLength(1));
  });

  test("the band's counter puts the edges on the second", () {
    // Still until 07:40:17, walking to 08:00:41, still after.
    final ts = <int>[], steps = <int>[];
    var c = 500.0;
    for (var t = t0 - 120; t < t0 + 1500; t++) {
      ts.add(t);
      final walking = t >= t0 + 17 && t < t0 + 1241;
      if (walking) c += 110 / 60;
      steps.add(c.floor());
    }
    final b = detectMovementBouts(tsSec: ts, stepCount: steps).single;
    expect(b.startSec, closeTo(t0 + 17, 1));
    expect(b.endSec, closeTo(t0 + 1241, 1));
  });

  test("a gen4 band with no counter reads the phone's 5-minute slices", () {
    final g4 = walk(t0 - 600, 45, 110);
    final none = List.filled(g4.ts.length, -1);
    expect(detectMovementBouts(tsSec: g4.ts, stepCount: none), isEmpty,
        reason: 'no counter and no spans: no claim');
    // 07:40-08:00 walking at 110 spm, then a still slice.
    final spans = [
      for (var k = 0; k < 4; k++) [t0 + k * 300, t0 + (k + 1) * 300, 550],
      [t0 + 1200, t0 + 1500, 20],
    ];
    final coarse =
        detectMovementBouts(tsSec: g4.ts, stepCount: none, spans: spans);
    expect(coarse.single.startSec, t0, reason: 'no movement: slice edges');
    expect(coarse.single.endSec, t0 + 1200);
    expect(coarse.single.sport, 'walking');
    expect(coarse.single.steps, 2200);

    // The wrist swings from 07:42:10 to 07:59:30: that is the walk.
    double swing(int i) {
      final t = g4.ts[i];
      return t >= t0 + 130 && t < t0 + 1170 ? (i.isEven ? .3 : -.3) : 0;
    }

    final ax = [for (var i = 0; i < g4.ts.length; i++) swing(i)];
    final flat = List<double>.filled(g4.ts.length, 0);
    final b = detectMovementBouts(
            tsSec: g4.ts,
            stepCount: none,
            spans: spans,
            ax: ax,
            ay: flat,
            az: flat)
        .single;
    expect(b.startSec, closeTo(t0 + 130, 3));
    expect(b.endSec, closeTo(t0 + 1170, 3));
    // Under 15 minutes once its edges are known: no walk.
    final short = [
      for (var i = 0; i < g4.ts.length; i++)
        g4.ts[i] >= t0 + 260 && g4.ts[i] < t0 + 1100
            ? (i.isEven ? .3 : -.3)
            : 0.0,
    ];
    expect(
        detectMovementBouts(
            tsSec: g4.ts,
            stepCount: none,
            spans: spans,
            ax: short,
            ay: flat,
            az: flat),
        isEmpty);
  });

  test('an hour of steps spread over the hour is not an hour-long walk', () {
    // 4,500 steps in one hourly row: 75 spm on average, but nobody can say
    // when they were taken.
    final g4 = walk(t0, 60, 110);
    expect(
        detectMovementBouts(
            tsSec: g4.ts,
            stepCount: List.filled(g4.ts.length, -1),
            spans: [
              [t0, t0 + 3600, 4500],
            ]),
        isEmpty);
  });

  test('a logged session excludes its minutes', () {
    final w = walk(t0, 20, 110);
    expect(
        detectMovementBouts(
            tsSec: w.ts, stepCount: w.steps, excluded: [[t0, t0 + 1200]]),
        isEmpty);
  });

  test('habits rename a bout and say when it is usually done', () {
    // Five weekday "Hiking" logs at 7:40 local (built from the calendar, so
    // the October clock change does not move them) at ~100 spm.
    int at(int weeksBack) =>
        DateTime(2026, 11, 4 - 7 * weeksBack, 7, 40).millisecondsSinceEpoch ~/
        1000;
    final kept = [
      for (var i = 1; i <= 5; i++)
        HabitSession('hiking', at(i), at(i) + 1800, cadenceSpm: 100),
    ];
    final h = ActivityHabits.fromSessions(kept);
    final w = walk(t0, 20, 102);
    final bout = detectMovementBouts(tsSec: w.ts, stepCount: w.steps).single;
    expect(h.name(bout), 'hiking');
    expect(h.usual('Hiking'), 'Usually weekdays around 7:40');
    // A much faster bout does not fit the hike.
    final r = walk(t0, 20, 165);
    expect(h.name(detectMovementBouts(tsSec: r.ts, stepCount: r.steps).single),
        'running');
  });
}
