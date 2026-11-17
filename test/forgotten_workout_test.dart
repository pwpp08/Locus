// A strength session left running for hours (a forgotten Stop) must not score
// its idle time as training, and Stop must be able to end it where the user
// actually stopped moving.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/manual_session.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/whoop_scores.dart';
import 'package:openstrap_edge/state/workout_idle.dart';

void main() {
  test('muscular load stops growing past the cap', () {
    expect(whoopMuscularLoad(30), closeTo(.0773 * 900, 1e-9));
    expect(whoopMuscularLoad(414), whoopMuscularLoad(kWhoopMuscularMaxMin));
  });

  test('only minutes over the strain floor count as working', () {
    // Resting 57, max 202: the floor sits near 82 bpm.
    final hr = [for (var i = 0; i < 30; i++) 120.0, for (var i = 0; i < 300; i++) 75.0];
    expect(whoopActiveMinutes(hr, restingHr: 57, maxHr: 202), 30);
  });

  test('seven idle hours after a lift do not reach 21', () {
    const profile = Profile(sex: 'male');
    final lift = [for (var i = 0; i < 40; i++) 125.0];
    final forgotten = [...lift, for (var i = 0; i < 374; i++) 76.0];
    double? score(List<double> hr) => strainFromPerMinuteHr(hr,
        profile: profile,
        restingHr: 57,
        hrMax: 202,
        quietHrr: .2,
        type: 'weight_training');
    final a = score(lift)!;
    final b = score(forgotten)!;
    expect(b, lessThan(21));
    // The idle tail adds nothing to the muscular part.
    expect(b - a, lessThan(.5));
  });

  test('the day path uses the zone minutes, not the wall clock', () {
    final s = [
      {
        'status': 'done',
        'type': 'weight_training',
        'start_ts': 0,
        'end_ts': 7 * 3600,
        'zone_min_json': '[20,15,5,0,0]',
      },
    ];
    final withSplit = DerivationEngine.strainFlooredAtSessions(5, s)!;
    final wall = DerivationEngine.strainFlooredAtSessions(5, [
      {...s.first, 'zone_min_json': '[]'},
    ])!;
    expect(withSplit, lessThan(wall));
    expect(wall, lessThan(21));
  });

  test('quietSince reports the start of a long quiet stretch only', () {
    final start = DateTime(2026, 11, 16, 14, 56);
    final w = WorkoutIdleWatch(startedAt: start);
    final active = start.add(const Duration(minutes: 60));
    w.onTick(active, hr: 130, gate: 100);
    expect(w.quietSince(active.add(const Duration(minutes: 10))), isNull);
    expect(w.quietSince(active.add(const Duration(hours: 5))), active);
  });
}
