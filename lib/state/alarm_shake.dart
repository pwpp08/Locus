// alarm_shake.dart — "shake your wrist to stop the alarm", the pure half.
//
// The band's wake alarm runs on the band and already stops on a DOUBLE TAP
// (HAPTICS_TERMINATED reason `user_double_tap`). Shake-to-stop is the phone's
// addition: while an alarm window is open the app holds the live 100 Hz motion
// stream, feeds every |a| sample here, and sends STOP_HAPTICS when this says
// the wrist was shaken. It only works while the phone is connected to the band
// at alarm time; the double tap works either way.
//
// WHAT COUNTS AS A SHAKE. Several sharp jolts close together: [kShakeJolts]
// separate excursions of |a| more than [kShakeJoltG] (as a fraction of the
// resting level) away from rest inside [kShakeWindowMs]. Rest is LEARNED from
// the stream rather than assumed to be 1 g: a band whose scale reads rest as
// 0.5 g or 2 g sat permanently on one side of a fixed 1 g band, saw one
// endless jolt, and never fired. Rolling over in bed is one slow excursion, not four sharp
// ones, and the buzz itself moves the accelerometer by a fraction of a g.

import 'dart:math' as math;

/// How far from rest a sample must be to count as a jolt, as a fraction of
/// the resting level (0.45 g on a band that reads rest as 1 g).
const double kShakeJoltG = 0.45;

/// How far the acceleration VECTOR must swing inside [kShakeSwingSamples] to
/// count as a jolt, in resting units. A flick of the wrist mostly ROTATES
/// gravity: |a| hardly moves while the direction whips round, so a detector
/// reading |a| alone never saw the shake people actually do in bed.
const double kShakeSwingG = 0.7;

/// The swing has to settle under this before the next one counts.
const double kShakeSwingRearmG = 0.35;

/// 50 ms at 100 Hz: fast enough to leave a slow roll-over and the buzz out.
const int kShakeSwingSamples = 5;

/// How fast the resting level follows the stream, per sample: about a five
/// second time constant at 100 Hz, so a shake barely moves it.
const double kShakeRestAlpha = 0.002;

/// How many separate jolts make a shake.
const int kShakeJolts = 3;

/// The window those jolts must fall inside (ms).
const int kShakeWindowMs = 2000;

/// A new jolt must start at least this long after the previous one began, so
/// one long excursion is not counted as several (ms).
const int kShakeMinGapMs = 80;

/// The live stream's sample period (100 Hz).
const int kShakeSamplePeriodMs = 10;

/// The motion watch opens this long before the armed alarm time…
const Duration kAlarmShakeLead = Duration(seconds: 20);

/// …and closes this long after it — past the longest buzz a pattern asks for.
const Duration kAlarmShakeTail = Duration(seconds: 150);

class AlarmShakeDetector {
  final List<int> _joltsMs = [];

  /// Which side of the 1 g band the last sample sat on: 1 above, -1 below,
  /// 0 inside it.
  int _side = 0;

  /// The learned resting |a|, seeded from the first frame.
  double? _rest;
  double? get rest => _rest;

  /// The largest |a| − rest seen since the last reset, in resting units.
  double peak = 0;

  /// The last sample's time, so frames that arrive in a burst (BLE batches
  /// them) still read as consecutive samples rather than the same ones again.
  int? _lastMs;

  /// The last [kShakeSwingSamples] vectors (g), oldest first.
  final List<(double, double, double)> _recent = [];
  bool _swinging = false;

  void reset() {
    _recent.clear();
    _swinging = false;
    _joltsMs.clear();
    _side = 0;
    _lastMs = null;
    _rest = null;
    peak = 0;
  }

  /// Feed one live frame of |a| samples (g) that arrived at [nowMs]. The
  /// samples are taken as evenly spaced at [kShakeSamplePeriodMs], ending at
  /// [nowMs]. Returns true when the jolts seen so far make a shake; the
  /// detector resets itself then, so one shake fires once.
  ///
  /// A jolt starts when |a| leaves the band around 1 g, or crosses straight
  /// from one side of it to the other: a hard shake swings from well over
  /// 1.45 g to well under 0.55 g between two samples and never lands inside
  /// the band, and counting only exits from it saw that as one long jolt.
  ///
  /// [xs], [ys], [zs] are the frame's axes in the band's raw units, when it
  /// has them; each sample is scaled to g by its own magnitude.
  bool add(
    List<double> mags,
    int nowMs, {
    List<double>? xs,
    List<double>? ys,
    List<double>? zs,
  }) {
    final axes = xs != null &&
        ys != null &&
        zs != null &&
        xs.length == mags.length &&
        ys.length == mags.length &&
        zs.length == mags.length;
    final n = mags.length;
    if (n == 0) return false;
    _rest ??= (mags.reduce((a, b) => a + b) / n).clamp(0.25, 4.0);
    for (var i = 0; i < n; i++) {
      var t = nowMs - (n - 1 - i) * kShakeSamplePeriodMs;
      final last = _lastMs;
      if (last != null && t <= last) t = last + kShakeSamplePeriodMs;
      _lastMs = t;
      final rest = _rest!;
      final d = (mags[i] - rest) / rest;
      if (d.abs() > peak) peak = d.abs();
      _rest = rest + (mags[i] - rest) * kShakeRestAlpha;
      final side = d > kShakeJoltG ? 1 : (d < -kShakeJoltG ? -1 : 0);
      if (side != 0 && side != _side) {
        if (_joltsMs.isEmpty || t - _joltsMs.last >= kShakeMinGapMs) {
          _joltsMs.add(t);
        }
      }
      _side = side;
      if (axes) {
        final x = xs[i], y = ys[i], z = zs[i];
        final norm = math.sqrt(x * x + y * y + z * z);
        final k = norm > 0 ? mags[i] / norm : 0.0;
        final v = (x * k, y * k, z * k);
        if (_recent.length == kShakeSwingSamples) {
          final o = _recent.removeAt(0);
          final dx = v.$1 - o.$1, dy = v.$2 - o.$2, dz = v.$3 - o.$3;
          final swing = math.sqrt(dx * dx + dy * dy + dz * dz) / rest;
          if (swing > peak) peak = swing;
          if (swing > kShakeSwingG && !_swinging) {
            _swinging = true;
            if (_joltsMs.isEmpty || t - _joltsMs.last >= kShakeMinGapMs) {
              _joltsMs.add(t);
            }
          } else if (swing < kShakeSwingRearmG) {
            _swinging = false;
          }
        }
        _recent.add(v);
      }
      while (_joltsMs.isNotEmpty && t - _joltsMs.first > kShakeWindowMs) {
        _joltsMs.removeAt(0);
      }
      if (_joltsMs.length >= kShakeJolts) {
        _joltsMs.clear();
        _side = 0;
        return true;
      }
    }
    return false;
  }
}
