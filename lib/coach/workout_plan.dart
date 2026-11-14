// A workout the coach proposed and the person committed to: what sport, how
// long, and the minutes it means to spend in each heart-rate zone.
//
// The model chooses the zones; the app prices them. The estimated strain is
// the same formula a recorded workout is scored with (`peakStrain`), fed each
// zone's minutes at the middle of THIS person's band for that zone. Missing
// zones, resting heart rate or ceiling: no estimate, never a stand-in.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../compute/strain_peak.dart';
import '../compute/whoop_scores.dart';
import '../state/prefs.dart';
import 'coach_actions.dart';

class WorkoutPlan {
  /// The local day it is planned for, `YYYY-MM-DD`.
  final String date;
  final String sport;
  final int durationMin;

  /// Minutes in zones 1 to 5.
  final List<double> zoneMin;

  /// The app's estimate on the 0-21 scale, or null when it cannot price it.
  final double? strain;

  const WorkoutPlan({
    required this.date,
    required this.sport,
    required this.durationMin,
    required this.zoneMin,
    this.strain,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'sport': sport,
        'duration_min': durationMin,
        'zone_min': zoneMin,
        'strain': strain,
      };

  static WorkoutPlan? fromJson(Object? j) {
    if (j is! Map) return null;
    final zones = j['zone_min'];
    final sport = j['sport']?.toString() ?? '';
    final date = j['date']?.toString() ?? '';
    final minutes = (j['duration_min'] as num?)?.toInt();
    if (zones is! List || sport.isEmpty || date.isEmpty || minutes == null) {
      return null;
    }
    return WorkoutPlan(
      date: date,
      sport: sport,
      durationMin: minutes,
      zoneMin: [for (final z in zones) (z as num?)?.toDouble() ?? 0],
      strain: (j['strain'] as num?)?.toDouble(),
    );
  }

  /// The same workout, whatever day it is for.
  bool sameAs(WorkoutPlan o) =>
      o.date == date &&
      o.sport == sport &&
      o.durationMin == durationMin &&
      listEquals(o.zoneMin, zoneMin);

  /// One option from the model, checked. Throws [CoachActionError] with what
  /// to fix, which goes back to the model.
  static WorkoutPlan parse(
    Object? raw, {
    required String date,
    double? Function(List<double> zoneMin, String sport)? priceWith,
  }) {
    if (raw is! Map) {
      throw CoachActionError('Each option is an object.');
    }
    final sport = CoachActions.str(raw['sport']);
    if (sport.isEmpty || sport.length > 40) {
      throw CoachActionError('Each option needs a sport, in a few words.');
    }
    final zones = raw['zone_minutes'];
    if (zones is! List || zones.isEmpty || zones.length > 5) {
      throw CoachActionError(
          'zone_minutes is a list of up to five numbers, zones 1 to 5.');
    }
    final mins = <double>[
      for (final z in zones) CoachActions.num_(z) ?? -1,
      for (var i = zones.length; i < 5; i++) 0,
    ];
    if (mins.any((m) => m < 0)) {
      throw CoachActionError('Zone minutes must be numbers of 0 or more.');
    }
    final total = mins.fold<double>(0, (a, b) => a + b);
    if (total < 5 || total > 300) {
      throw CoachActionError(
          'A workout is 5 to 300 minutes across its zones.');
    }
    final said = CoachActions.num_(raw['duration_min']);
    if (said != null && (said - total).abs() > 2) {
      throw CoachActionError('duration_min ($said) must equal the sum of '
          'zone_minutes ($total).');
    }
    return WorkoutPlan(
      date: date,
      sport: sport,
      durationMin: total.round(),
      zoneMin: mins,
      strain: priceWith?.call(mins, sport),
    );
  }
}

/// Estimated strain of [zoneMin] minutes in zones 1-5 whose bands are
/// [zones] (lower and upper bpm), through the formula a recorded workout is
/// scored with. Null when an anchor is missing.
double? plannedStrain(
  List<double> zoneMin, {
  required List<(double, double)> zones,
  required double? restingHr,
  required double? maxHr,
  String? sport,
}) {
  if (zones.length != 5 || restingHr == null || maxHr == null) return null;
  final perMin = <double>[
    for (var z = 0; z < 5; z++)
      for (var m = 0; m < zoneMin[z].round(); m++)
        (zones[z].$1 + zones[z].$2) / 2,
  ];
  final heart = peakStrain(perMin, restingHr: restingHr, maxHr: maxHr);
  final type = sport?.toLowerCase().replaceAll(' ', '_');
  if (heart == null || !kWhoopMuscularTypes.contains(type)) return heart;
  return whoopStrainFromLoad(whoopLoadForStrain(heart) +
      whoopMuscularLoad(perMin.length.toDouble()));
}

/// The one committed plan, kept in prefs.
class WorkoutPlanStore {
  WorkoutPlanStore._();

  static const key = 'coach.workout_plan';

  /// Ticks when the plan is saved or cleared, so Home can redraw.
  static final changed = ValueNotifier<int>(0);

  static WorkoutPlan? get current {
    try {
      return WorkoutPlan.fromJson(jsonDecode(Prefs.getString(key, '')));
    } catch (_) {
      return null;
    }
  }

  /// The plan for [date], if the committed one is for that day.
  static WorkoutPlan? forDay(String date) {
    final p = current;
    return p != null && p.date == date ? p : null;
  }

  static void save(WorkoutPlan plan) {
    Prefs.setString(key, jsonEncode(plan.toJson()));
    changed.value++;
  }

  static void clear() {
    Prefs.setString(key, '');
    changed.value++;
  }
}
