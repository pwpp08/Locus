// The live workout's notification: on Android the card on the lock screen and
// in the shade, promoted to a Live Update (the status bar chip) on Android 16
// and up. The native side is LiveActivityNotifier.kt. Where no native side
// answers, every call is a no-op (MissingPluginException, swallowed).

import 'package:flutter/services.dart';

import '../state/prefs.dart';

class LiveActivity {
  static const MethodChannel _ch = MethodChannel('openstrap/live_activity');
  static bool _active = false;

  static bool get isActive => _active;

  static const _kOn = 'live_activity.on';
  static const _kChip = 'live_activity.chip';

  /// The card at all. On by default: a workout is what the lock screen is
  /// for while it runs.
  static bool get enabled => Prefs.getBool(_kOn, true);
  static set enabled(bool v) => Prefs.setBool(_kOn, v);

  /// Android 16+: a promoted Live Update with its status bar chip, in place
  /// of the drawn card. The system draws it, so the two cannot be one.
  static bool get chip => Prefs.getBool(_kChip, true);
  static set chip(bool v) => Prefs.setBool(_kChip, v);

  /// Start the activity for a session. [startedAt] drives the live timer.
  static Future<void> start({
    required DateTime startedAt,
    required int targetKcal,
    required int maxHr,
    required int rhr,
    String name = 'Live session',
  }) async {
    if (!enabled) return;
    try {
      await _ch.invokeMethod('start', {
        'name': name,
        'startedAtMs': startedAt.millisecondsSinceEpoch,
        'targetKcal': targetKcal,
        'maxHr': maxHr,
        'rhr': rhr,
        'promote': chip,
        'imperial': Prefs.getString('units_system', '') == 'imperial',
      });
      _active = true;
    } catch (_) {/* no native side */}
  }

  /// Push a new frame. Caller should throttle (~every 3–5s).
  ///
  /// [strain], [calories], [distanceKm] and [paceSecPerKm] are NULLABLE and
  /// pass through as null when unmeasured: the card shows "–", never a
  /// confident 0, and [hr] is null while no heart rate is arriving. [zonePos] places the heart rate on the zone track, 0..6
  /// (zone n's segment spans n to n + 1).
  static Future<void> update({
    required int? hr,
    required int zone,
    required double zonePos,
    required double? strain,
    required int? calories,
    required int maxHr,
    required int rhr,
    double? distanceKm,
    double? paceSecPerKm,
    int? elapsedSec,
    bool paused = false,
  }) async {
    if (!_active) return;
    try {
      await _ch.invokeMethod('update', {
        'hr': hr, 'zone': zone, 'zonePos': zonePos,
        'strain': strain, 'calories': calories,
        'maxHr': maxHr, 'rhr': rhr,
        'distanceKm': distanceKm, 'paceSecPerKm': paceSecPerKm,
        'elapsedSec': elapsedSec, 'paused': paused,
      });
    } catch (_) {}
  }

  static Future<void> end() async {
    try {
      await _ch.invokeMethod('end');
    } catch (_) {}
    _active = false;
  }
}
