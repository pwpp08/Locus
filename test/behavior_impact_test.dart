// A behavior's impact is two means from the user's own days, and nothing at all
// until each side has enough of them.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/behavior_impact.dart';

String _d(int i) => '2026-05-${(i + 1).toString().padLeft(2, '0')}';
String _before(String d) => _d(int.parse(d.substring(8)) - 2);

void main() {
  test('the impact is the difference of the two means', () {
    final out = {for (var i = 0; i < 12; i++) _d(i): i < 6 ? 70.0 : 60.0};
    final b = impactOf(BehaviorKind.highStrain, 'x', out,
        yes: [for (var i = 0; i < 6; i++) _d(i)],
        no: [for (var i = 6; i < 12; i++) _d(i)]);
    expect(b.impact, 10);
    expect((b.yes, b.no), (6, 6));
  });

  test('under five days on a side says nothing, however big the gap', () {
    final out = {for (var i = 0; i < 12; i++) _d(i): i < 4 ? 99.0 : 10.0};
    final b = impactOf(BehaviorKind.highStrain, 'x', out,
        yes: [for (var i = 0; i < 4; i++) _d(i)],
        no: [for (var i = 4; i < 12; i++) _d(i)]);
    expect(b.impact, isNull);
    expect((b.yes, b.no), (4, 8));
  });

  test('a day with no Recovery counts for neither side', () {
    final b = impactOf(BehaviorKind.highStrain, 'x', {_d(0): 50},
        yes: [_d(0), _d(1)], no: [_d(2)]);
    expect((b.yes, b.no), (1, 0));
  });

  test('a day with no value is not a no', () {
    final s = splitDays([_d(0), _d(1), _d(2)],
        (d) => d == _d(1) ? null : 20.0, (v) => v >= 14);
    expect(s.yes, [_d(0), _d(2)]);
    expect(s.no, isEmpty);
  });

  test('strain belongs to the day before the Recovery it is compared with', () {
    final days = [for (var i = 1; i < 13; i++) _d(i)];
    // Hard on the odd days: the mornings after are the even ones.
    final strain = {for (var i = 0; i < 13; i++) _d(i): i.isOdd ? 16.0 : 8.0};
    final recovery = {for (var i = 0; i < 13; i++) _d(i): i.isEven ? 40.0 : 80.0};
    final all = autoBehaviors(
      days: days,
      recovery: recovery,
      sleepPerformance: const {},
      bed: const {},
      wake: const {},
      strain: strain,
      highStressPct: const {},
      earlyWorkoutDays: const {},
      dayBefore: _before,
    );
    final hard = all.firstWhere((b) => b.kind == BehaviorKind.highStrain);
    expect(hard.impact, -40);
  });

  test('a tag lands on the morning its lag says, and unlogged days are out', () {
    final logged = {for (var i = 0; i < 12; i++) _d(i): i < 6 ? {'alcohol'} : <String>{'walk'}};
    // Mornings after an alcohol day are low.
    final recovery = {for (var i = 0; i < 14; i++) _d(i): i >= 1 && i <= 6 ? 40.0 : 70.0};
    String shift(String d, int by) => _d(int.parse(d.substring(8)) - 1 + by);
    final tags = tagBehaviors(
      logged: logged,
      recovery: recovery,
      lagOf: (t) => t == 'alcohol' ? 1 : 0,
      shift: shift,
    );
    final alcohol = tags.firstWhere((b) => b.title == 'Alcohol');
    expect((alcohol.yes, alcohol.no), (6, 6));
    expect(alcohol.impact, -30);
  });

  test('ranked runs best to worst; locked keeps the rest', () {
    final all = [
      const BehaviorImpact(kind: BehaviorKind.highStrain, title: 'a', yes: 9, no: 9, meanYes: 50, meanNo: 53),
      const BehaviorImpact(kind: BehaviorKind.earlyWorkout, title: 'b', yes: 9, no: 9, meanYes: 58, meanNo: 53),
      const BehaviorImpact(kind: BehaviorKind.journalTag, title: 'c', yes: 1, no: 1),
      const BehaviorImpact(kind: BehaviorKind.journalTag, title: 'd', yes: 4, no: 4),
    ];
    expect([for (final b in rankedOf(all)) b.title], ['b', 'a']);
    expect([for (final b in lockedOf(all)) b.title], ['d', 'c']);
  });
}
