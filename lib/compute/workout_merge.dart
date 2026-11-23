// workout_merge.dart — one workout, not three.
//
// The heart-rate detector ends a bout when the heart rate falls under its
// floor, so a lifting session with five-minute rests, or a run done as
// intervals, came out as several workouts minutes apart. Bouts whose gap is
// at most [kWorkoutMergeGapSec] are one workout: the first start, the last
// end, the duration-weighted mean heart rate, the highest peak. A logged
// session sitting in the gap keeps them apart.
//
// Pure and isolate-safe.

import 'package:openstrap_analytics/onehz.dart' as ana;

/// The longest break (seconds) inside one workout.
const int kWorkoutMergeGapSec = 15 * 60;

List<ana.DetectedWorkout> mergeCloseBouts(
  List<ana.DetectedWorkout> bouts, {
  int gapSec = kWorkoutMergeGapSec,
  List<List<int>> keepApart = const [],
}) {
  if (bouts.length < 2) return bouts;
  final sorted = [...bouts]..sort((a, b) => a.startSec.compareTo(b.startSec));
  bool blocked(int from, int to) =>
      keepApart.any((s) => s[0] < to && s[1] > from);
  final out = <ana.DetectedWorkout>[sorted.first];
  // Heart-beat-seconds of each merged workout, so the mean is exact rather
  // than a mean of rounded means.
  final beats = <double>[
    sorted.first.avgBpm * (sorted.first.endSec - sorted.first.startSec) * 1.0,
  ];
  final secs = <int>[sorted.first.endSec - sorted.first.startSec];
  for (final b in sorted.skip(1)) {
    final last = out.last;
    final gap = b.startSec - last.endSec;
    final len = b.endSec - b.startSec;
    if (gap > gapSec || blocked(last.endSec, b.startSec)) {
      out.add(b);
      beats.add(b.avgBpm * len * 1.0);
      secs.add(len);
      continue;
    }
    beats.last += b.avgBpm * len;
    secs.last += len;
    final end = b.endSec > last.endSec ? b.endSec : last.endSec;
    out[out.length - 1] = ana.DetectedWorkout(
      startSec: last.startSec,
      endSec: end,
      avgBpm: secs.last <= 0 ? last.avgBpm : (beats.last / secs.last).round(),
      peakBpm: b.peakBpm > last.peakBpm ? b.peakBpm : last.peakBpm,
      durationMin: (end - last.startSec) ~/ 60,
      sport: last.sport,
    );
  }
  return out;
}
