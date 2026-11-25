// zone_alert.dart — PURE policy: has the live HR zone just crossed into or
// out of the user's chosen target zone, and has it stayed on the new side
// long enough to be a real crossing rather than a blip at the boundary?
//
// Fed once per 1 Hz workout tick, same cadence as [WorkoutIdleWatch]. A raw
// `zone == target` check would fire on every tick the HR sits right on a zone
// edge — one PPG-noisy second putting you at 149 vs 151 bpm is not a crossing,
// it's jitter, and buzzing the band for every jitter is worse than the alert
// not existing. [onTick] only reports a crossing once the OTHER side has held
// for [debounce], and it reports each direction once, not once per tick.

/// Tracks one live session's position relative to [targetZone] (1..5, the
/// same numbering as [AppState.liveZone]) and decides when a debounced
/// crossing alert should fire.
class ZoneCrossingAlert {
  ZoneCrossingAlert({
    required this.targetZone,
    this.debounce = const Duration(seconds: 5),
  });

  final int targetZone;

  /// How long HR must sit on the other side of the boundary before the
  /// crossing counts. Five seconds absorbs a single noisy PPG sample without
  /// masking a real effort change — the same order of magnitude as the
  /// rolling-median peak smoothing already applied to `maxHrSeen`.
  final Duration debounce;

  /// Whether the session is confirmed inside the target zone right now, or
  /// null before the first tick has established a baseline (which never
  /// fires — there is nothing to cross yet).
  bool? _confirmedInside;

  bool? _pendingInside;
  DateTime? _pendingSince;

  /// Feed one tick. [zone] is this second's zone 0..5 ([AppState]'s
  /// `_zoneFor`, not the null-outside-zone `liveZone` getter — zone 0 is a
  /// perfectly good "not the target" for this check). Returns true exactly
  /// when the debounced side has just flipped, i.e. buzz now.
  bool onTick(DateTime now, int zone) {
    final inside = zone == targetZone;
    final confirmed = _confirmedInside;
    if (confirmed == null) {
      // First reading of the session: this establishes where we started,
      // never fires (nothing has been "crossed" yet).
      _confirmedInside = inside;
      return false;
    }
    if (inside == confirmed) {
      // Back on the confirmed side — whatever pending flip was building
      // dissolves rather than fire late on a side we already reported.
      _pendingInside = null;
      _pendingSince = null;
      return false;
    }
    if (_pendingInside != inside) {
      // Just stepped to the other side — start the debounce clock.
      _pendingInside = inside;
      _pendingSince = now;
      return false;
    }
    if (now.difference(_pendingSince!) < debounce) return false;
    // Held long enough — confirm the flip and fire once.
    _confirmedInside = inside;
    _pendingInside = null;
    _pendingSince = null;
    return true;
  }
}

/// A ceiling on the live zone, set per workout on Start Activity: buzz when the
/// heart rate goes ABOVE [limitZone] (1..4), and again every [repeat] while it
/// stays above, so it is felt until the effort eases. The other alert
/// ([ZoneCrossingAlert]) is about crossing into or out of one zone; this one
/// is a limit, and says nothing on the way back down.
///
/// Fed once per 1 Hz workout tick. [debounce] keeps one noisy second at a zone
/// edge from buzzing. Zone 0 (no reading, or no zone set at all) is never
/// above anything.
class ZoneLimitAlert {
  ZoneLimitAlert({
    required this.limitZone,
    this.debounce = const Duration(seconds: 5),
    this.repeat = const Duration(seconds: 30),
  });

  final int limitZone;
  final Duration debounce;
  final Duration repeat;

  DateTime? _aboveSince;
  DateTime? _lastBuzz;

  /// True when the band should buzz now.
  bool onTick(DateTime now, int zone) {
    if (zone <= limitZone) {
      _aboveSince = null;
      _lastBuzz = null;
      return false;
    }
    _aboveSince ??= now;
    if (now.difference(_aboveSince!) < debounce) return false;
    final last = _lastBuzz;
    if (last != null && now.difference(last) < repeat) return false;
    _lastBuzz = now;
    return true;
  }

  /// The zone a stored limit means ('' or out of range is none).
  static int? parse(String stored) {
    final z = int.tryParse(stored);
    return z == null || z < 1 || z > 4 ? null : z;
  }
}
