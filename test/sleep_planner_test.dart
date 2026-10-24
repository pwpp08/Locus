// The Sleep Planner adds nothing to the model: every number is read off the
// cross-day rollup's sleep coach, and the breakdown must add up to the need it
// explains.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/sleep_planner.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Map<String, dynamic> _insights({
  double needSec = 523 * 60,
  double bed = 21 * 60 + 4,
  double wake = 6 * 60 + 50,
  double? osdH = 8.5,
  int? strain = 12,
  int? nap = 20,
}) =>
    {
      'sleep_coach': {
        'need': {'value': {'need_sec': needSec}},
        'bedtime': {'value': {'bedtime_min_of_day': bed}},
        'wake': {'value': {'wake_min_of_day': wake}},
        'strain_bonus_min': strain,
        'nap_credit_min': nap,
      },
      'sleep_debt': {'value': {'osd_hours': osdH}},
    };

void main() {
  test('the parts add up to the need', () {
    final p = SleepPlan.of(_insights());
    expect(p.needMin, 523);
    expect(p.baselineMin, 510);
    expect(p.baselineMin! + p.strainMin! + p.debtMin! - p.napMin!, p.needMin);
    expect(p.debtMin, 21);
  });

  test('time in bed spans midnight, and awake is in bed less sleep', () {
    final p = SleepPlan.of(_insights());
    expect(p.inBedMin, 586); // 21:04 → 06:50
    expect(p.awakeMin, 63);
    expect(p.usualWakeMin, 410);
  });

  test('bedtime is the chosen wake less time in bed, across midnight', () {
    final p = SleepPlan.of(_insights());
    expect(p.bedtimeFor(5 * 60 + 50), 20 * 60 + 4);
    expect(p.bedtimeFor(null), isNull);
  });

  test('the baseline is clamped the way the pipeline clamps it', () {
    expect(SleepPlan.of(_insights(osdH: 5.6)).baselineMin, 420);
    expect(SleepPlan.of(_insights(osdH: 11)).baselineMin, 570);
  });

  test('no coach: every part is absent, never zero', () {
    final p = SleepPlan.of(const {});
    expect(p.needMin, isNull);
    expect(p.debtMin, isNull);
    expect(p.awakeMin, isNull);
    expect(p.bedtimeFor(420), isNull);
  });

  test('an unmeasured strain or nap stays a dash', () {
    final p = SleepPlan.of(_insights(strain: null, nap: null));
    expect(p.strainMin, isNull);
    expect(p.napMin, isNull);
    expect(hMm(p.strainMin, sign: true), '--');
  });

  test('hMm formats like the planner', () {
    expect(hMm(523), '8:43');
    expect(hMm(0, sign: true), '+0:00');
    expect(hMm(-5, sign: true), '−0:05');
  });

  testWidgets('the recommendation sheet shows the breakdown', (t) async {
    final plan = SleepPlan.of(_insights());
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
                onPressed: () => showSleepRecommendation(c, plan),
                child: const Text('open')),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('YOUR SLEEP RECOMMENDATION'), findsOneWidget);
    expect(find.text('9:46'), findsOneWidget);
    expect(find.text('+1:03'), findsOneWidget);
    expect(find.text('−0:20'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
