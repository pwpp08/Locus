import 'package:openstrap_edge/compute/whoop_age.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:flutter_test/flutter_test.dart';

const today = '2026-11-07';

Map<String, double> daily(double v, {int days = 182}) {
  final t = DateTime.parse(today);
  return {
    for (var i = 0; i < days; i++)
      dayLabelOf(DateTime(t.year, t.month, t.day - i)): v,
  };
}

WhoopAgeResult person({
  required double sleepH,
  required double consistency,
  required double steps,
  required double z13Week,
  required double z45Week,
  required double strengthWeek,
  required double rhr,
  required double vo2,
  String sex = 'm',
}) =>
    whoopAge(
      today: today,
      age: 30,
      sex: sex,
      recovery: daily(60),
      sleepMin: daily(sleepH * 60),
      consistency: daily(consistency),
      steps: daily(steps),
      zones13Min: daily(z13Week / 7),
      zones45Min: daily(z45Week / 7),
      strengthMin: daily(strengthWeek / 7),
      restingHr: daily(rhr),
      vo2max: daily(vo2),
    );

void main() {
  test('Table 2: a typical WHOOP member aged 30 reads about −1.6 years', () {
    final r = person(
        sleepH: 7.3, consistency: 75, steps: 9500, z13Week: 200,
        z45Week: 40, strengthWeek: 80, rhr: 56, vo2: 48);
    expect(r.whoopAge! - 30, closeTo(-1.6, 1.0));
    expect(r.pace, closeTo(1.0, 1e-9)); // steady habits age one year a year
  });

  test('Table 2: a typical US adult aged 30 reads about +6 years', () {
    final r = person(
        sleepH: 6.8, consistency: 60, steps: 4500, z13Week: 60,
        z45Week: 5, strengthWeek: 20, rhr: 72, vo2: 38);
    expect(r.whoopAge! - 30, closeTo(6, 1.5));
  });

  test('a better last month slows the pace', () {
    final steps = daily(4000)..addAll(daily(10000, days: 30));
    final r = whoopAge(
        today: today, age: 30, sex: 'm', recovery: daily(60), steps: steps);
    expect(r.pace, lessThan(1));
    expect(r.pace, greaterThanOrEqualTo(-1));
  });

  test('abstains without age, under 18, or before 21 recoveries', () {
    expect(whoopAge(today: today, age: null, sex: null, recovery: daily(60)).why,
        'needs_age');
    expect(whoopAge(today: today, age: 17, sex: null, recovery: daily(60)).why,
        'under_18');
    expect(
        whoopAge(today: today, age: 30, sex: null, recovery: daily(60, days: 20))
            .why,
        'needs_recoveries:have=20,need=21');
  });

  test('VO₂max target table', () {
    expect(whoopVo2Target(22, 'm'), 46);
    expect(whoopVo2Target(47, 'f'), 32);
    expect(whoopVo2Target(100, 'm'), 21);
  });
}
