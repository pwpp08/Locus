// When you got into bed, for sleep-onset latency on a night the detector
// found by itself.
//
// The detector's window opens once the wrist is already lying still with a
// sleep-ish heart rate (`_classifyStill`), so "window start → first sleep"
// reads near zero on an automatic night: the tossing before it is outside the
// window. Latency has to be measured from the lie-down instead.
//
// The lie-down is read off the wrist: walking back from the window's start,
// the run of quiet minutes before it (a little turning over is allowed; being
// up and about is not) ends at the last minute the wrist was clearly active.
// That minute's end is when you settled. Abstains, rather than guess, when
//   * no clearly active minute is found in the look-back (an evening on the
//     sofa runs straight into the night: there is no lie-down to see),
//   * any minute of the run is unmeasured (off the wrist, a sync gap), or
//   * the run is longer than [kMaxLatencySec] (you were resting, not trying
//     to sleep).
// A user-set or confirmed window keeps its own start: the person said when
// they went to bed.

/// How far before the window the lie-down is looked for.
const int kBedLookbackSec = 90 * 60;

/// The longest latency reported; anything longer is rest, not falling asleep.
const int kMaxLatencySec = 60 * 60;

/// A minute with at least this share of its seconds turning the wrist is
/// being up and about (`compute/movement.dart`'s measure).
const double kActiveMoveShare = .40;

/// The lie-down: the end of the last clearly active minute in the
/// [kBedLookbackSec] before [onsetSec], when every minute from there to the
/// onset was measured. Epoch seconds, or null.
///
/// [perMinute] is `movementBuckets(…, bucketSec: 60)`: `t` a minute's start,
/// `v` its moving share; a minute it does not carry was not measured.
int? bedTimeBefore(int onsetSec, List<({int t, double v})> perMinute) {
  if (onsetSec <= 0) return null;
  final share = {for (final b in perMinute) b.t ~/ 60: b.v};
  final first = (onsetSec - kBedLookbackSec) ~/ 60;
  // The minute the window opens in is the sleeper's, not the lead-in's.
  for (var m = onsetSec ~/ 60 - 1; m >= first; m--) {
    final v = share[m];
    if (v == null) return null;
    if (v >= kActiveMoveShare) {
      final bed = (m + 1) * 60;
      return onsetSec - bed > kMaxLatencySec ? null : bed;
    }
  }
  return null;
}
