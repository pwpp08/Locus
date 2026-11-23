import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/workout_alerts.dart';

void main() {
  test('the strain target buzzes once, when reached', () {
    final a = WorkoutAlerts(strainGoal: 10);
    expect(a.onTick(elapsedSec: 60, strain: 9.9), isNull);
    expect(a.onTick(elapsedSec: 61, strain: 10), WorkoutBuzz.strainGoal);
    expect(a.onTick(elapsedSec: 62, strain: 11), isNull);
  });

  test('no strain, no buzz', () {
    final a = WorkoutAlerts(strainGoal: 10);
    expect(a.onTick(elapsedSec: 600), isNull);
  });

  test('a countdown warns a minute before and buzzes at the end', () {
    final a = WorkoutAlerts(timerSec: 15 * 60);
    expect(a.onTick(elapsedSec: 14 * 60 - 1), isNull);
    expect(a.onTick(elapsedSec: 14 * 60), WorkoutBuzz.timerWarning);
    expect(a.onTick(elapsedSec: 14 * 60 + 1), isNull);
    expect(a.onTick(elapsedSec: 15 * 60), WorkoutBuzz.timerDone);
    expect(a.onTick(elapsedSec: 15 * 60 + 1), isNull);
  });

  test('a short countdown has no warning', () {
    final a = WorkoutAlerts(timerSec: 120);
    expect(a.onTick(elapsedSec: 60), isNull);
    expect(a.onTick(elapsedSec: 120), WorkoutBuzz.timerDone);
  });

  test('a resumed session does not buzz again for what passed', () {
    final a = WorkoutAlerts(
        strainGoal: 8, timerSec: 600, resumed: true, elapsedSec: 700, strain: 9);
    expect(a.onTick(elapsedSec: 701, strain: 9.5), isNull);
  });

  test('a countdown only applies to the activity it was set for', () {
    expect(WorkoutAlerts.timerFor('sauna|15', 'sauna'), 900);
    expect(WorkoutAlerts.timerFor('sauna|15', 'running'), isNull);
    expect(WorkoutAlerts.timerFor('', 'sauna'), isNull);
    expect(WorkoutAlerts.timerFor('sauna|0', 'sauna'), isNull);
  });
}
