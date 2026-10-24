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
// separate excursions of |a| more than [kShakeJoltG] away from 1 g inside
// [kShakeWindowMs]. Rolling over in bed is one slow excursion, not four sharp
// ones, and the buzz itself moves the accelerometer by a fraction of a g.

/// How far from 1 g a sample must be to count as a jolt (g). 1.2 (|a| above
/// 2.2 g, four times over) was more than a half-asleep wrist delivers.
const double kShakeJoltG = 0.8;

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
  bool _above = false;

  void reset() {
    _joltsMs.clear();
    _above = false;
  }

  /// Feed one live frame of |a| samples (g) that arrived at [nowMs]. The
  /// samples are taken as evenly spaced at [kShakeSamplePeriodMs], ending at
  /// [nowMs]. Returns true when the jolts seen so far make a shake; the
  /// detector resets itself then, so one shake fires once.
  bool add(List<double> mags, int nowMs) {
    final n = mags.length;
    for (var i = 0; i < n; i++) {
      final t = nowMs - (n - 1 - i) * kShakeSamplePeriodMs;
      final jolt = (mags[i] - 1.0).abs() > kShakeJoltG;
      if (jolt && !_above) {
        if (_joltsMs.isEmpty || t - _joltsMs.last >= kShakeMinGapMs) {
          _joltsMs.add(t);
        }
      }
      _above = jolt;
      while (_joltsMs.isNotEmpty && t - _joltsMs.first > kShakeWindowMs) {
        _joltsMs.removeAt(0);
      }
      if (_joltsMs.length >= kShakeJolts) {
        reset();
        return true;
      }
    }
    return false;
  }
}
