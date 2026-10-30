// MOVEMENT — the share of seconds in a bucket in which the wrist turned.
//
// ONE DEFINITION. The day's stored 5-minute `activity_curve` (derivation
// engine), the per-minute lane under the nap chart and the per-minute lane
// under the day's heart rate all call this, so a minute that reads "moving"
// in one place cannot read "still" in another. A second is counted when the
// wrist's tilt changed by more than 5° since the second before — the same
// basis as active minutes. Absent accelerometer data is not stillness: a pair
// of seconds without a plausible gravity vector is left out of the count
// rather than scored as no movement.

import 'package:openstrap_analytics/onehz.dart' as ana;

import 'substrate.dart' show accelPlausible;

/// The wrist-turn threshold, degrees per second.
const double kMovementTurnDeg = 5.0;

/// Moving share per [bucketSec] bucket, oldest first: `t` is the bucket's
/// start (epoch seconds, a multiple of [bucketSec]), `v` the share 0…1 of its
/// counted seconds in which the wrist turned. A bucket with no counted second
/// is not emitted — no data is not "still".
///
/// [tsSec], [ax], [ay], [az] are parallel, ascending by time.
List<({int t, double v})> movementBuckets(
  List<int> tsSec,
  List<double> ax,
  List<double> ay,
  List<double> az, {
  required int bucketSec,
}) {
  final n = tsSec.length;
  if (n < 2 || ax.length != n || ay.length != n || az.length != n) {
    return const [];
  }
  final ang = [for (var i = 0; i < n; i++) ana.zAngle(ax[i], ay[i], az[i])];
  final move = <int, int>{}, tot = <int, int>{};
  for (var i = 1; i < n; i++) {
    if (!accelPlausible(ax[i], ay[i], az[i]) ||
        !accelPlausible(ax[i - 1], ay[i - 1], az[i - 1])) {
      continue;
    }
    final b = tsSec[i] ~/ bucketSec;
    tot[b] = (tot[b] ?? 0) + 1;
    if ((ang[i] - ang[i - 1]).abs() > kMovementTurnDeg) {
      move[b] = (move[b] ?? 0) + 1;
    }
  }
  final keys = tot.keys.toList()..sort();
  return [
    for (final b in keys) (t: b * bucketSec, v: (move[b] ?? 0) / tot[b]!),
  ];
}

/// [rows] as `decoded_onehz` hands them back (`rec_ts`, `ax`, `ay`, `az`),
/// bucketed per minute. Pure and sendable, so a whole day can be bucketed off
/// the UI isolate with `Isolate.run`.
List<({int t, double v})> movementPerMinuteOfRows(
    List<Map<String, Object?>> rows) {
  final ts = <int>[];
  final ax = <double>[], ay = <double>[], az = <double>[];
  int? last;
  for (final r in rows) {
    final t = (r['rec_ts'] as num?)?.toInt();
    final x = (r['ax'] as num?)?.toDouble();
    final y = (r['ay'] as num?)?.toDouble();
    final z = (r['az'] as num?)?.toDouble();
    // One reading a second: a second two devices both logged is counted once.
    if (t == null || x == null || y == null || z == null || t == last) continue;
    last = t;
    ts.add(t);
    ax.add(x);
    ay.add(y);
    az.add(z);
  }
  return movementBuckets(ts, ax, ay, az, bucketSec: 60);
}
