// workout_alerts.dart — the band's buzzes a running session owes the person:
// the strain target reached, and a countdown (sauna, cold plunge, meditation…)
// nearly up and up. Each fires once per session. Pure: the controller feeds it
// the clock and the strain once a second and plays what it returns.

/// What to buzz this second.
enum WorkoutBuzz {
  /// The session's strain reached the target set on Start Activity.
  strainGoal,

  /// A minute of the countdown left.
  timerWarning,

  /// The countdown is over.
  timerDone,
}

/// The activities a countdown makes sense for, and the minutes it starts on.
/// Zero: offered, but off until the person sets it.
const Map<String, int> kTimerDefaults = {
  'sauna': 15,
  'cold_plunge': 3,
  'meditation': 10,
  'breathwork': 5,
  'stretching': 0,
  'yoga': 0,
  'mobility': 0,
};

/// The lengths the start screen offers, in minutes; 0 is off.
const List<int> kTimerChoices = [0, 3, 5, 10, 15, 20, 30, 45];

class WorkoutAlerts {
  /// The strain to buzz at; null for none.
  final double? strainGoal;

  /// The countdown length in seconds; null for none.
  final int? timerSec;

  bool _strainDone, _warnDone, _timerDone;

  /// [resumed] with the session's present [elapsedSec] and [strain]: a session
  /// reopened after a relaunch does not buzz again for what already passed.
  WorkoutAlerts({
    this.strainGoal,
    this.timerSec,
    bool resumed = false,
    int elapsedSec = 0,
    double? strain,
  })  : _strainDone = resumed &&
            strainGoal != null &&
            strain != null &&
            strain >= strainGoal,
        _warnDone = resumed && timerSec != null && elapsedSec >= timerSec - 60,
        _timerDone = resumed && timerSec != null && elapsedSec >= timerSec;

  /// The warning only makes sense on a countdown long enough to have one.
  bool get _warns => timerSec != null && timerSec! >= 3 * 60;

  /// At most one buzz a tick; the most important wins and the rest wait.
  WorkoutBuzz? onTick({required int elapsedSec, double? strain}) {
    final t = timerSec;
    if (t != null && !_timerDone && elapsedSec >= t) {
      _timerDone = true;
      _warnDone = true;
      return WorkoutBuzz.timerDone;
    }
    final g = strainGoal;
    if (g != null && !_strainDone && strain != null && strain >= g) {
      _strainDone = true;
      return WorkoutBuzz.strainGoal;
    }
    if (_warns && !_warnDone && elapsedSec >= t! - 60) {
      _warnDone = true;
      return WorkoutBuzz.timerWarning;
    }
    return null;
  }

  /// How many buzzes, and long or short, for each.
  static (int count, bool long) pattern(WorkoutBuzz b) => switch (b) {
        WorkoutBuzz.strainGoal => (2, true),
        WorkoutBuzz.timerWarning => (1, false),
        WorkoutBuzz.timerDone => (3, true),
      };

  /// The countdown a start screen set for [type]: 'type|minutes' in Prefs, so
  /// a value left by another activity's start never applies to this one.
  static int? timerFor(String stored, String type) {
    final parts = stored.split('|');
    if (parts.length != 2 || parts[0] != type.toLowerCase()) return null;
    final m = int.tryParse(parts[1]);
    return m == null || m <= 0 ? null : m * 60;
  }
}
