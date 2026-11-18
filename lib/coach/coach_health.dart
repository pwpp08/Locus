// What the Health tab shows, for the coach: Locus Age and its Pace of Aging
// with every contributor, VO2 max, the Health Monitor's overnight vitals
// against their usual ranges, and today's stress.
//
// Read through the same loaders the screens use, so the coach and the app
// never disagree about a number. Anything a screen would show as "--" is null
// here, with the reason when there is one.

import '../compute/stress_monitor.dart' show stressLevel;
import '../compute/whoop_age.dart' show WhoopAgeResult, kWhoopAgeUnlockRecoveries;
import '../data/day_label.dart';
import '../data/local_repository.dart';
import '../ui2/screens/health_monitor.dart' show healthMonitorReadings;
import '../ui2/screens/locus_age.dart' show finishedSaturdays;
import '../ui2/screens/stress_monitor.dart' show StressSource;
import '../ui2/screens/trend_view.dart' show TrendLoader;

double? _r(double? v, [int places = 1]) =>
    v == null ? null : double.parse(v.toStringAsFixed(places));

/// One Locus Age reading as plain values.
Map<String, Object?> _age(WhoopAgeResult r) {
  final age = r.whoopAge, real = r.age;
  return {
    'locus_age': _r(age),
    'actual_age': _r(real),
    'years_vs_actual_age':
        age == null || real == null ? null : _r(age - real),
    'pace_of_aging': _r(r.pace, 2),
    if (r.why != null) 'why_none': switch (r.why!) {
      'needs_age' => 'no birth date in the profile',
      'under_18' => 'Locus Age is for adults only',
      final w when w.contains('have=') =>
        'still unlocking: needs $kWhoopAgeUnlockRecoveries recoveries '
            '(${RegExp(r'have=(\d+)').firstMatch(w)?.group(1) ?? '?'} so far)',
      final w => w,
    },
  };
}

/// The whole Health tab, as one JSON-able map.
Future<Map<String, Object?>> coachHealth(LocalRepository repo) async {
  final today = todayLabel();
  final loader = TrendLoader(repo);
  final out = <String, Object?>{'day': today};

  try {
    final now = await loader.whoopAge(asOf: today);
    final lastWeek = finishedSaturdays(today, 1);
    final before = lastWeek.isEmpty
        ? null
        : await loader.whoopAge(asOf: lastWeek.first);
    out['locus_age'] = {
      ..._age(now),
      'last_finished_week': before == null ? null : _age(before),
      'about': 'Locus Age is how old their sleep, activity and fitness make '
          'them, from the last six months. Pace of Aging is years of Locus '
          'Age gained per calendar year over the last 30 days: 1.0 is one '
          'year per year, under 1 slower, over 1 faster. Each contributor '
          'gives its six-month average, its last-30-day average, the target '
          'and the years it adds (+) or takes off (-).',
      'contributors': {
        for (final e in now.parts.entries)
          e.key: {
            'six_month_avg': _r(e.value.value),
            'last_30_days_avg': _r(now.recent[e.key]?.value),
            'target': _r(e.value.target),
            'years': _r(e.value.years, 2),
            'years_last_30_days': _r(now.recent[e.key]?.years, 2),
          },
      },
    };
  } catch (_) {
    out['locus_age'] = null;
  }

  try {
    final v = await loader.vo2max();
    final days = v.byDay.keys.toList()..sort();
    out['vo2max'] = {
      'value': days.isEmpty ? null : _r(v.byDay[days.last]),
      'as_of': days.isEmpty ? null : days.last,
      'unit': 'mL/kg/min',
      'source': v.source?.name,
      if (v.why != null) 'why_none': v.why,
    };
  } catch (_) {
    out['vo2max'] = null;
  }

  try {
    out['health_monitor'] = await healthMonitorReadings(repo);
  } catch (_) {
    out['health_monitor'] = null;
  }

  try {
    final d = await StressSource(repo).load(today);
    final last = d.last;
    final score = last == null ? null : d.scores[last];
    out['stress_today'] = d.baseline == null
        ? {
            'state': 'calibrating',
            'usable_days': d.usableDays,
          }
        : {
            'score_now': _r(score),
            'level_now': score == null ? null : stressLevel(score).name,
            'at_minute_of_day': last,
            'scale': '0 calm to 3 highest; under 1 low, 1-2 medium, 2+ high',
            'minutes': {
              'low': d.minutes.low,
              'medium': d.minutes.medium,
              'high': d.minutes.high,
            },
            'typical_day_minutes': d.typical == null
                ? null
                : {
                    'low': d.typical!.low.round(),
                    'medium': d.typical!.medium.round(),
                    'high': d.typical!.high.round(),
                  },
          };
  } catch (_) {
    out['stress_today'] = null;
  }
  return out;
}
