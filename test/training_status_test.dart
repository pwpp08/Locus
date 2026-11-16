import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/training_status.dart';

void main() {
  const base = (mean: 60.0, sd: 8.0);
  TrainingStatus? of(double a, double c,
          {int days = 28, double? weekAgo, double? hrv7}) =>
      trainingStatus(
        acute: a,
        chronic: c,
        days: days,
        ratioWeekAgo: weekAgo,
        hrv7: hrv7,
        hrvBase: hrv7 == null ? null : base,
      ).status;

  test('no status without a load ratio or three weeks of strain', () {
    expect(
        trainingStatus(acute: null, chronic: 10, days: 28).status, isNull);
    expect(trainingStatus(acute: 10, chronic: 0, days: 28).status, isNull);
    expect(of(10, 10, days: kStatusMinDays - 1), isNull);
    expect(of(10, 10, days: kStatusMinDays), TrainingStatus.maintaining);
  });

  test('the load ratio picks the band', () {
    expect(of(7, 10), TrainingStatus.detraining);
    expect(of(9, 10), TrainingStatus.maintaining);
    expect(of(12, 10), TrainingStatus.productive);
    expect(of(14, 10), TrainingStatus.overreaching);
  });

  test('easing off after a week above the norm is recovering', () {
    expect(of(7, 10, weekAgo: 1.2), TrainingStatus.recovering);
    expect(of(7, 10, weekAgo: .9), TrainingStatus.detraining);
  });

  test('a suppressed HRV turns building into holding or too much', () {
    expect(of(10.5, 10, hrv7: 50), TrainingStatus.maintaining);
    expect(of(12, 10, hrv7: 50), TrainingStatus.overreaching);
    expect(of(12, 10, hrv7: 61), TrainingStatus.productive);
  });

  test('HRV is optional and never invented', () {
    final r = trainingStatus(acute: 12, chronic: 10, days: 28);
    expect(r.hrvZ, isNull);
    expect(r.status, TrainingStatus.productive);
    expect(r.ratio, closeTo(1.2, 1e-9));
  });
}
