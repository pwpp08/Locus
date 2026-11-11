// Training readiness: each factor comes off a stored input, a missing input
// is left out rather than filled in, and the weakest factor holds the score
// back.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/training_readiness.dart';
import 'package:openstrap_edge/ui2/screens/training_readiness_card.dart'
    show recoveryTimeText;

void main() {
  test('too few factors, no score', () {
    final r = trainingReadiness(sleepPerf: 90, recovery: 80, sleep3: [85]);
    expect(r.score, isNull);
    expect(r.factors.keys, hasLength(3));
  });

  test('all good reads high, and the sentence has nothing to blame', () {
    final r = trainingReadiness(
      sleepPerf: 92,
      recovery: 88,
      sleep3: [90, 85, 88],
      stress3: [.6, .7, .8],
      acute: 50,
      chronic: 48,
      hrv7: 60,
      hrvBase: (mean: 58, sd: 6),
      sessions: const [],
      now: 0,
    );
    expect(r.score, greaterThanOrEqualTo(75));
    expect(r.weakest, isNull);
    expect(r.factors[ReadinessFactor.recoveryTime], 100);
  });

  test('one poor factor pulls the score below the mean, and is named', () {
    final good = {
      'sleepPerf': 90.0,
      'recovery': 90.0,
    };
    final r = trainingReadiness(
      sleepPerf: good['sleepPerf'],
      recovery: good['recovery'],
      sleep3: [90, 90, 90],
      acute: 90,
      chronic: 50, // ratio 1.8
    );
    final mean = r.factors.values.reduce((a, b) => a + b) / r.factors.length;
    expect(r.score, lessThan(mean));
    expect(r.weakest, ReadinessFactor.load);
  });

  test('recovery time: the longest still owed wins, and it runs down', () {
    const end = 1000000;
    final hard = [(end, 15.0)]; // 45 h
    expect(recoveryHoursLeft(hard, end), closeTo(45, .01));
    expect(recoveryHoursLeft(hard, end + 40 * 3600), closeTo(5, .01));
    expect(recoveryHoursLeft(hard, end + 50 * 3600), 0);
    expect(
        recoveryHoursLeft([(end, 15.0), (end + 3600, 8.0)], end + 3600),
        closeTo(44, .01));
    expect(recoveryTimeText(3.5), '3 h 30 min');
    expect(recoveryTimeText(.75), '45 min');
    expect(recoveryTimeText(2), '2 h');
  });

  test('HRV inside its range is balanced, under it costs', () {
    TrainingReadiness at(double hrv) =>
        trainingReadiness(hrv7: hrv, hrvBase: (mean: 60, sd: 5));
    expect(at(57).factors[ReadinessFactor.hrv], 100);
    expect(at(50).factors[ReadinessFactor.hrv], 50);
  });
}
