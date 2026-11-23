import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/workout_merge.dart';

ana.DetectedWorkout _b(int startMin, int endMin, int avg, int peak) =>
    ana.DetectedWorkout(
      startSec: startMin * 60,
      endSec: endMin * 60,
      avgBpm: avg,
      peakBpm: peak,
      durationMin: endMin - startMin,
      sport: 'weightlifting',
    );

void main() {
  test('lifting with five-minute rests is one workout', () {
    // The user's day: 15:54-16:18, 16:23-16:38, 16:44-16:57.
    final m = mergeCloseBouts([_b(954, 978, 120, 150), _b(983, 998, 110, 140),
        _b(1004, 1017, 130, 160)]);
    expect(m, hasLength(1));
    expect(m.single.startSec, 954 * 60);
    expect(m.single.endSec, 1017 * 60);
    expect(m.single.durationMin, 63);
    expect(m.single.peakBpm, 160);
    // Weighted by duration: (120*24 + 110*15 + 130*13) / 52.
    expect(m.single.avgBpm, ((120 * 24 + 110 * 15 + 130 * 13) / 52).round());
  });

  test('a session an hour later stays its own', () {
    final m = mergeCloseBouts([_b(600, 630, 120, 150), _b(700, 730, 120, 150)]);
    expect(m, hasLength(2));
  });

  test('exactly fifteen minutes apart merges; sixteen does not', () {
    expect(mergeCloseBouts([_b(0, 10, 100, 120), _b(25, 35, 100, 120)]), hasLength(1));
    expect(mergeCloseBouts([_b(0, 10, 100, 120), _b(26, 36, 100, 120)]), hasLength(2));
  });

  test('a logged session in the gap keeps them apart', () {
    final m = mergeCloseBouts([_b(0, 10, 100, 120), _b(20, 30, 100, 120)],
        keepApart: [[12 * 60, 18 * 60]]);
    expect(m, hasLength(2));
  });

  test('order in does not matter', () {
    final m = mergeCloseBouts([_b(20, 30, 100, 120), _b(0, 10, 100, 120)]);
    expect(m.single.startSec, 0);
  });
}
