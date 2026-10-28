// TREND VIEW — My Dashboard's metrics: one row each on Home (the latest value
// against your last-7-days average), and behind each row a week, a month or
// six months of days as bars, with the average drawn across them.
//
// Every number is read, never modelled here:
//   * most metrics are a `metric_series` key, through `getChart`;
//   * heart-rate zones, mean heart rate and time in bed are day-bundle fields
//     (`LocalDb.dayTrendFigures`);
//   * strength time and volume load come off saved sessions and their sets;
//   * sleep consistency is the regularity index's own per-night pairs;
//   * sleep performance, hours vs. needed and the restorative pair are exact
//     arithmetic on two stored series of the same night.
// A metric this app does not produce (VO₂ max) says so instead of drawing.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../compute/profile.dart' show Profile;
import '../../compute/vo2max_estimate.dart';
import '../../state/prefs.dart';
import '../activity/catalogue.dart' show Track, activityByName;
import '../ui2.dart';
import 'home_screen.dart'
    show
        envValue,
        monthShortName,
        pad,
        pointsOf,
        recoveryColor,
        repoOf,
        thousands,
        weekdayShortName;
import 'sleep_planner.dart' show hMm;

enum TrendGroup { strain, recovery, sleep }

enum TrendFmt { decimal1, integer, grouped, percent, hmm }

/// What a metric can show for a single day, below the daily figure.
enum TrendIntraday {
  /// Only a daily figure: the Day view is not offered.
  none,

  /// A value per minute, drawn as a line.
  line,

  /// A value per hour: bars, or a line through the hours for a metric that
  /// is a line ([TrendMetric.line]).
  hourly,
}

/// How a metric is drawn over a week or a month.
enum TrendKind {
  /// A column per day (or a line, when [TrendMetric.line] is set).
  columns,

  /// A floating bar per night from bed to wake, on a clock.
  floating,

  /// Columns stacked from layers (the zones, deep and REM).
  stacked,

  /// Two lines on one scale (sleep need against sleep achieved).
  dual,
}

/// One metric Trend View can chart.
class TrendMetric {
  final String id;
  final String title;
  final TrendGroup group;
  final IconData icon;
  final TrendFmt fmt;

  /// What the number is measured in, written after it. Null when it has none
  /// (a strain, a step count) or already carries it (a percentage).
  final String? unit;

  /// Which way is good: true up, false down, null neither (the arrow is then
  /// drawn in plain ink, a direction without a verdict).
  final bool? higherBetter;

  /// Summed over a week rather than averaged — Home shows the 7-day TOTAL.
  final bool weekly;

  /// A day with nothing logged is a real zero (strength), not a missing day.
  final bool zeroFill;

  /// Values can be negative (a shortfall), so the chart has a zero line.
  final bool signed;

  /// The scale's own ceiling, when it has one (strain 21, percentages 100).
  final double? axisMax;

  /// Drawn as a line through the days rather than a column per day.
  final bool line;

  /// The shape of the chart over a week or a month.
  final TrendKind kind;

  /// What the Day view shows, if anything.
  final TrendIntraday intraday;

  /// The Day view's value is the last point of a running total (strain), not
  /// an average or a sum of the points.
  final bool cumulative;

  /// Non-null: this app does not produce the metric, and this is why.
  final String? absent;

  const TrendMetric(
    this.id,
    this.title,
    this.group,
    this.icon,
    this.fmt, {
    this.unit,
    this.higherBetter,
    this.weekly = false,
    this.zeroFill = false,
    this.signed = false,
    this.axisMax,
    this.line = false,
    this.kind = TrendKind.columns,
    this.intraday = TrendIntraday.none,
    this.cumulative = false,
    this.absent,
  });
}

/// Every metric, in the order the picker lists them.
const kTrendCatalogue = <TrendMetric>[
  TrendMetric('strain', 'Day strain', TrendGroup.strain, LucideIcons.dumbbell,
      TrendFmt.decimal1,
      axisMax: 21, intraday: TrendIntraday.line, cumulative: true),
  TrendMetric('steps', 'Steps (beta)', TrendGroup.strain,
      LucideIcons.footprints, TrendFmt.grouped,
      higherBetter: true, intraday: TrendIntraday.hourly),
  TrendMetric('zones_13', 'Heart rate zones 1-3', TrendGroup.strain,
      LucideIcons.heartPulse, TrendFmt.hmm,
      unit: 'hr',
      higherBetter: true,
      weekly: true,
      kind: TrendKind.stacked),
  TrendMetric('zones_45', 'Heart rate zones 4-5', TrendGroup.strain,
      LucideIcons.heart, TrendFmt.hmm,
      unit: 'hr',
      higherBetter: true,
      weekly: true,
      kind: TrendKind.stacked),
  TrendMetric('zones_all', 'Heart rate zones all', TrendGroup.strain,
      LucideIcons.timer, TrendFmt.hmm,
      unit: 'hr',
      higherBetter: true,
      weekly: true,
      kind: TrendKind.stacked),
  TrendMetric('strength_time', 'Strength activity time', TrendGroup.strain,
      LucideIcons.dumbbell, TrendFmt.hmm,
      unit: 'hr', higherBetter: true, weekly: true, zeroFill: true),
  TrendMetric('volume_load', 'Total volume load', TrendGroup.strain,
      LucideIcons.weight, TrendFmt.grouped,
      unit: 'kg', higherBetter: true, weekly: true, zeroFill: true),
  TrendMetric('avg_hr', 'Average heart rate', TrendGroup.strain,
      LucideIcons.heartPulse, TrendFmt.integer,
      unit: 'bpm', line: true, intraday: TrendIntraday.line),
  TrendMetric('calories', 'Calories', TrendGroup.strain, LucideIcons.flame,
      TrendFmt.grouped,
      unit: 'cal', intraday: TrendIntraday.hourly),
  TrendMetric('vo2max', 'VO₂ max', TrendGroup.strain, LucideIcons.wind,
      TrendFmt.decimal1,
      unit: 'mL/kg/min', higherBetter: true, line: true),
  TrendMetric('recovery', 'Recovery', TrendGroup.recovery,
      LucideIcons.batteryCharging, TrendFmt.percent,
      higherBetter: true, axisMax: 100),
  TrendMetric('hrv', 'Heart rate variability', TrendGroup.recovery,
      LucideIcons.activity, TrendFmt.integer,
      unit: 'ms',
      higherBetter: true,
      line: true,
      intraday: TrendIntraday.hourly),
  TrendMetric('resting_hr', 'Resting heart rate', TrendGroup.recovery,
      LucideIcons.heartHandshake, TrendFmt.integer,
      unit: 'bpm', higherBetter: false, line: true),
  TrendMetric('resp_rate', 'Respiratory rate', TrendGroup.recovery,
      LucideIcons.wind, TrendFmt.decimal1,
      unit: 'rpm', line: true),
  TrendMetric('sleep_perf', 'Sleep performance', TrendGroup.sleep,
      LucideIcons.moon, TrendFmt.percent, higherBetter: true, axisMax: 100),
  TrendMetric('time_in_bed', 'Time in bed', TrendGroup.sleep,
      LucideIcons.bedDouble, TrendFmt.hmm,
      unit: 'hr', kind: TrendKind.floating),
  TrendMetric('hvn_hours', 'Hours vs. needed (hours)', TrendGroup.sleep,
      LucideIcons.clock3, TrendFmt.hmm,
      unit: 'hr', higherBetter: true, signed: true, kind: TrendKind.dual),
  TrendMetric('hvn_pct', 'Hours vs. needed (%)', TrendGroup.sleep,
      LucideIcons.clock3, TrendFmt.percent, higherBetter: true),
  TrendMetric('consistency', 'Sleep consistency', TrendGroup.sleep,
      LucideIcons.repeat, TrendFmt.percent,
      higherBetter: true, axisMax: 100, kind: TrendKind.floating),
  TrendMetric('restorative_pct', 'Restorative sleep (%)', TrendGroup.sleep,
      LucideIcons.moonStar, TrendFmt.percent,
      higherBetter: true, kind: TrendKind.stacked),
  TrendMetric('restorative_hours', 'Restorative sleep (hours)',
      TrendGroup.sleep, LucideIcons.moonStar, TrendFmt.hmm,
      unit: 'hr', higherBetter: true, kind: TrendKind.stacked),
  TrendMetric('efficiency', 'Sleep efficiency', TrendGroup.sleep,
      LucideIcons.gauge, TrendFmt.percent, higherBetter: true, axisMax: 100),
  TrendMetric('sleep_debt', 'Sleep debt', TrendGroup.sleep,
      LucideIcons.hourglass, TrendFmt.hmm,
      unit: 'hr', higherBetter: false, signed: true),
];

TrendMetric? trendMetricOf(String id) {
  for (final m in kTrendCatalogue) {
    if (m.id == id) return m;
  }
  return null;
}

/// My Dashboard's one tile that is not a metric: the week's strain and
/// recovery on one chart.
const kStrainRecoveryTile = 'strain_recovery';

/// What My Dashboard shows until the user customizes it.
const kDashboardDefault = [
  kStrainRecoveryTile, 'hrv', 'resting_hr', 'steps', 'zones_13', 'zones_45',
  'sleep_perf',
];

/// The saved tile order, unknown keys dropped. Unset is the default set.
List<String> dashboardTilesOf() {
  final raw = Prefs.getString(Prefs.dashboardTiles, '');
  if (raw.isEmpty) return kDashboardDefault;
  final saved = [
    for (final k in raw.split(','))
      if (k == kStrainRecoveryTile || trendMetricOf(k) != null) k,
  ];
  // The chart used to sit above the dashboard whatever was chosen: a list saved
  // before it was a tile keeps it, first, until the user decides.
  return !saved.contains(kStrainRecoveryTile) &&
          !Prefs.getBool(Prefs.dashboardChartChosen, false)
      ? [kStrainRecoveryTile, ...saved]
      : saved;
}

/// The metrics Trend View lists: the ones switched on in My Dashboard. Null
/// while the dashboard has never been customized, which lists them all.
Set<String>? dashboardMetricsOf() =>
    Prefs.getString(Prefs.dashboardTiles, '').isEmpty
        ? null
        : {...dashboardTilesOf()};

String trendGroupName(TrendGroup g) => switch (g) {
      TrendGroup.strain => 'Strain',
      TrendGroup.recovery => 'Recovery',
      TrendGroup.sleep => 'Sleep',
    };

/// A value as the metric writes it. `--` for none.
String trendFormat(TrendMetric m, double? v, {bool sign = false}) {
  if (v == null || !v.isFinite) return '--';
  final s = sign && v > 0 ? '+' : '';
  return switch (m.fmt) {
    TrendFmt.decimal1 => '$s${v.toStringAsFixed(1)}',
    TrendFmt.integer => '$s${v.round()}',
    TrendFmt.grouped => '$s${thousands(v)}',
    TrendFmt.percent => '$s${v.round()}%',
    TrendFmt.hmm => hMm(v.round(), sign: sign),
  };
}

double? _mean(Iterable<double> xs) {
  var n = 0;
  var sum = 0.0;
  for (final x in xs) {
    n++;
    sum += x;
  }
  return n == 0 ? null : sum / n;
}

String _dayOfEpoch(int t) =>
    dayLabelOf(DateTime.fromMillisecondsSinceEpoch(t * 1000));

DateTime _dateOf(String day) => DateTime.parse(day);

/// [day] moved by [n] calendar days — by calendar, so a DST day is one day.
String shiftDay(String day, int n) {
  final d = _dateOf(day);
  return dayLabelOf(DateTime(d.year, d.month, d.day + n));
}

/// Reads each metric's daily values. One loader per screen load: the shared
/// reads (the day figures, sessions, the series behind several metrics) are
/// made once however many metrics ask.
class TrendLoader {
  final LocalRepository? repo;
  TrendLoader(this.repo);

  final _series = <String, Future<Map<String, double>>>{};
  Future<List<Map<String, Object?>>>? _figures;
  Future<List<Map<String, Object?>>>? _strength;
  Future<Map<String, double>>? _sri;
  Future<Vo2Result>? _vo2;

  /// VO₂ max, as far as the data goes (see `compute/vo2max_estimate.dart`).
  /// Read once however many charts ask.
  Future<Vo2Result> vo2max() => _vo2 ??= () async {
        final r = repo;
        final today = todayLabel();
        if (r == null) return const Vo2Result(why: 'No data to read yet.');
        try {
          final p = Profile.fromMap(await r.getProfile());
          final first = await firstDay() ?? today;
          final t = DateTime.parse(today);
          final since = DateTime(t.year, t.month, t.day - (kVo2RunWindow + 30))
                  .millisecondsSinceEpoch ~/
              1000;
          final runs = <Vo2Run>[];
          for (final s in await LocalDb.sessionVo2maxEstimates(since)) {
            // The figure behind it is a walking and running equation, and the
            // reading wants a real outing: a run of a quarter of an hour.
            final type = (s['type'] as String?)?.toLowerCase();
            final a = (s['start_ts'] as num?)?.toInt();
            final b = (s['end_ts'] as num?)?.toInt();
            final v = (s['vo2max_estimate'] as num?)?.toDouble();
            if ((type != 'running' && type != 'trail running') ||
                a == null ||
                b == null ||
                v == null ||
                b - a < 15 * 60) {
              continue;
            }
            runs.add((
              day: dayLabelOf(DateTime.fromMillisecondsSinceEpoch(a * 1000)),
              v: v
            ));
          }
          return estimateVo2max(
            today: today,
            firstDay: first,
            profile: (
              age: p.ageYears,
              sex: p.sex,
              weightKg: p.weightKg,
              heightCm: p.heightCm
            ),
            recovery: await _chart('recovery'),
            moderate: await _zones(const [2, 3]),
            vigorous: await _zones(const [4, 5]),
            runs: runs,
            lab: readVo2Lab(),
          );
        } catch (_) {
          return const Vo2Result(why: 'The estimate could not be read.');
        }
      }();

  Future<Map<String, double>> _chart(String key) =>
      _series[key] ??= () async {
        final r = repo;
        if (r == null) return <String, double>{};
        try {
          return {
            for (final p in pointsOf(await r.getChart(key))) _dayOfEpoch(p.t): p.v,
          };
        } catch (_) {
          return <String, double>{};
        }
      }();

  Future<List<Map<String, Object?>>> _figuresRows() => _figures ??= () async {
        try {
          return await LocalDb.dayTrendFigures();
        } catch (_) {
          return const <Map<String, Object?>>[];
        }
      }();

  Future<List<Map<String, Object?>>> _strengthRows() => _strength ??= () async {
        try {
          return await LocalDb.sessionStrengthTotals();
        } catch (_) {
          return const <Map<String, Object?>>[];
        }
      }();

  /// The first day this install has any derived result for: where a
  /// zero-filled metric's zeros start. Before it there is no "nothing logged",
  /// only "not using the app yet".
  Future<String?> firstDay() async {
    final rows = await _figuresRows();
    return rows.isEmpty ? null : rows.first['day'] as String?;
  }

  Future<Map<String, double>> _zones(List<int> which) async {
    final out = <String, double>{};
    for (final r in await _figuresRows()) {
      final raw = r['zones'];
      if (raw is! String) continue;
      Object? z;
      try {
        z = jsonDecode(raw);
      } catch (_) {
        continue;
      }
      if (z is! Map || z.isEmpty) continue;
      var sum = 0.0;
      var any = false;
      for (final i in which) {
        final v = z['z$i'];
        if (v is num) {
          sum += v;
          any = true;
        }
      }
      if (any) out[r['day'] as String] = sum;
    }
    return out;
  }

  /// The minutes in each of [which] zones, per day, one entry per zone in the
  /// order given. A day with any of them missing is left out rather than
  /// zero-filled: a stack with a silent gap would read as a short day.
  Future<Map<String, List<double>>> zoneStack(List<int> which) async {
    final out = <String, List<double>>{};
    for (final r in await _figuresRows()) {
      final raw = r['zones'];
      if (raw is! String) continue;
      Object? z;
      try {
        z = jsonDecode(raw);
      } catch (_) {
        continue;
      }
      if (z is! Map || z.isEmpty) continue;
      final vals = [for (final i in which) z['z$i']];
      if (vals.every((v) => v is num)) {
        out[r['day'] as String] = [for (final v in vals) (v as num).toDouble()];
      }
    }
    return out;
  }

  Future<Map<String, double>> _figure(String col, {double scale = 1}) async => {
        for (final r in await _figuresRows())
          if (r[col] is num) r['day'] as String: (r[col] as num) * scale,
      };

  Future<Map<String, double>> _strengthBy(bool volume) async {
    final out = <String, double>{};
    for (final r in await _strengthRows()) {
      final start = r['start_ts'];
      if (start is! num) continue;
      final sets = (r['sets'] as num?) ?? 0;
      final strength =
          sets > 0 || activityByName(r['type']?.toString())?.track == Track.sets;
      if (!strength) continue;
      final double? v;
      if (volume) {
        v = (r['volume_kg'] as num?)?.toDouble();
      } else {
        final mins = (r['duration_min'] as num?) ??
            (r['end_ts'] is num ? ((r['end_ts'] as num) - start) / 60 : null);
        v = mins?.toDouble();
      }
      if (v == null) continue;
      final day = _dayOfEpoch(start.toInt());
      out[day] = (out[day] ?? 0) + v;
    }
    return out;
  }

  Future<Map<String, double>> _consistency() => _sri ??= () async {
        final r = repo;
        if (r == null) return <String, double>{};
        try {
          final pairs = envValue((await r.getInsights())['regularity'])?['pairs'];
          return {
            if (pairs is List)
              for (final p in pairs.whereType<Map>())
                if (p['date'] is String && p['sri'] is num)
                  p['date'] as String: (p['sri'] as num).toDouble(),
          };
        } catch (_) {
          return <String, double>{};
        }
      }();

  /// Two series of the same night, combined day by day where both exist.
  Future<Map<String, double>> _pair(String a, String b,
      double? Function(double a, double b) f) async {
    final x = await _chart(a);
    final y = await _chart(b);
    return {
      for (final e in x.entries)
        if (y[e.key] != null)
          e.key: ?f(e.value, y[e.key]!),
    };
  }

  /// One day's own shape: a value per minute (a line, 1440 slots) or per hour
  /// (bars, 24 slots), null where nothing was recorded. Null when this metric
  /// has no Day view or the day holds nothing for it.
  ///
  /// Each series is read from the day's stored bundle, so a past day shows the
  /// same figures today did. A bundle served in place of the day asked for
  /// (the latest settled one, while today is still deriving) is never drawn
  /// under the wrong date: points are bucketed by their OWN local day.
  Future<TrendIntra?> intraday(TrendMetric m, String day) async {
    final r = repo;
    if (r == null || m.intraday == TrendIntraday.none) return null;
    try {
      final List<double?> values;
      final bool hourly;
      switch (m.id) {
        case 'strain':
          hourly = false;
          values = _perMinute((await r.getDayStrain(day))['curve'], day);
        case 'avg_hr':
          hourly = false;
          values = _perMinute((await _timeline(r, day))['hr'], day);
        case 'hrv':
          // Minute readings are noisy: an hour's value is the mean of its own.
          hourly = true;
          values = _meanPerHour(
              _perMinute((await _timeline(r, day))['hrv'], day));
        case 'calories':
          hourly = true;
          values = _caloriesPerHour(await r.getDayStrain(day), day);
        case 'steps':
          hourly = true;
          values = _stepsPerHour((await r.getDaySteps(day))['spans'], day);
        default:
          return null;
      }
      if (!values.any((v) => v != null)) return null;
      return (values: values, hourly: hourly, day: day);
    } catch (_) {
      return null;
    }
  }

  final _timelines = <String, Future<Map<String, dynamic>>>{};

  /// A day's timeline, read once however many charts ask.
  Future<Map<String, dynamic>> _timeline(LocalRepository r, String day) =>
      _timelines[day] ??= r.getDayTimeline(day);

  /// The night that ended on [day], as minutes of that day, with the mean of
  /// the HRV readings taken inside it. The day's own readings (walking about,
  /// working, training) are noisier and say little about recovery, so they are
  /// drawn but never counted. Null with no night on record for the day.
  Future<TrendSleep?> sleepHrv(String day) async {
    final r = repo;
    if (r == null) return null;
    try {
      final tl = await _timeline(r, day);
      final w = (tl['sleep'] as List?)?.whereType<Map>().firstOrNull;
      final on = w?['onset_ts'], off = w?['wake_ts'];
      if (on is! num || off is! num || off <= on) return null;
      int minuteOf(num ts) {
        final t = DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000);
        final d = dayLabelOf(t);
        if (d.compareTo(day) < 0) return 0;
        if (d.compareTo(day) > 0) return 1440;
        return t.hour * 60 + t.minute;
      }

      final from = minuteOf(on), to = minuteOf(off);
      if (to <= from) return null;
      final minutes = _perMinute(tl['hrv'], day);
      return (
        from: from,
        to: to,
        mean: _mean([for (var m = from; m < to; m++) ?minutes[m]]),
      );
    } catch (_) {
      return null;
    }
  }

  /// `[{t: epoch s, v}]` onto the 1440 minutes of [day]; points from any other
  /// local day are left out.
  static List<double?> _perMinute(Object? raw, String day) {
    final out = List<double?>.filled(1440, null);
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is! Map || e['t'] is! num || e['v'] is! num) continue;
      final t = DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt() * 1000);
      if (dayLabelOf(t) != day) continue;
      out[t.hour * 60 + t.minute] = (e['v'] as num).toDouble();
    }
    return out;
  }

  /// Step spans (`start_ts`, `end_ts`, `steps`) spread over the hours they
  /// cover, in proportion to the time in each.
  static List<double?> _stepsPerHour(Object? raw, String day) {
    final out = List<double?>.filled(24, null);
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is! Map || e['start_ts'] is! num || e['steps'] is! num) continue;
      final steps = (e['steps'] as num).toDouble();
      final a = DateTime.fromMillisecondsSinceEpoch((e['start_ts'] as num).toInt() * 1000);
      final bTs = e['end_ts'] is num ? (e['end_ts'] as num).toInt() : (e['start_ts'] as num).toInt();
      final b = DateTime.fromMillisecondsSinceEpoch(bTs * 1000);
      if (dayLabelOf(a) != day) continue;
      final total = b.difference(a).inSeconds;
      if (total <= 0) {
        out[a.hour] = (out[a.hour] ?? 0) + steps;
        continue;
      }
      var cursor = a;
      while (cursor.isBefore(b)) {
        final next = DateTime(cursor.year, cursor.month, cursor.day, cursor.hour + 1);
        final end = next.isBefore(b) ? next : b;
        if (dayLabelOf(cursor) == day) {
          out[cursor.hour] = (out[cursor.hour] ?? 0) +
              steps * end.difference(cursor).inSeconds / total;
        }
        cursor = end;
      }
    }
    return out;
  }

  /// The mean of each hour's minutes that have a reading; an hour with none
  /// stays null.
  static List<double?> _meanPerHour(List<double?> minutes) => [
        for (var h = 0; h < 24; h++)
          _mean([for (var m = h * 60; m < h * 60 + 60; m++) ?minutes[m]]),
      ];

  /// The day's calories shared out over its hours in proportion to the strain
  /// each hour added: both come from the same heart-rate trace, so the hours add
  /// back up to the day's own total. Null when the day has no total, or no
  /// strain was gained to share it by.
  static List<double?> _caloriesPerHour(Map<String, dynamic> strain, String day) {
    final out = List<double?>.filled(24, null);
    final total = strain['calories'];
    if (total is! num || total <= 0) return out;
    final curve = _perMinute(strain['curve'], day);
    // The curve is a running total: an hour's gain is how far it rose in it.
    double? last = 0;
    final gain = List<double>.filled(24, 0);
    for (var m = 0; m < 1440; m++) {
      final v = curve[m];
      if (v == null) continue;
      gain[m ~/ 60] += math.max(0, v - (last ?? 0));
      last = v;
    }
    final sum = gain.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return out;
    for (var h = 0; h < 24; h++) {
      if (gain[h] > 0) out[h] = total * gain[h] / sum;
    }
    return out;
  }

  /// Each night as bed and wake, in minutes after noon (so a night runs
  /// without breaking at midnight), under the local day it ended on. Waking can
  /// pass 1440: that is the next morning.
  Future<Map<String, ({double bed, double wake})>> sleepSpans() async {
    final r = repo;
    if (r == null) return const {};
    try {
      final out = <String, ({double bed, double wake})>{};
      for (final w in await r.sleepWindows(days: 400)) {
        final on = w['onset_ts'], off = w['wake_ts'];
        if (on is! num || off is! num || off <= on) continue;
        final a = DateTime.fromMillisecondsSinceEpoch(on.toInt() * 1000);
        final bed = ((a.hour * 60 + a.minute) - 720) % 1440;
        out[dayLabelOf(DateTime.fromMillisecondsSinceEpoch(off.toInt() * 1000))] = (
          bed: bed.toDouble(),
          wake: bed + (off - on) / 60,
        );
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// The series a stacked or paired chart is made of, bottom layer first: the
  /// zones in order, REM under deep, sleep need then sleep achieved.
  Future<List<Map<String, double>>> layers(TrendMetric m) async {
    switch (m.id) {
      case 'zones_13':
        return _zoneLayers(const [1, 2, 3]);
      case 'zones_45':
        return _zoneLayers(const [4, 5]);
      case 'zones_all':
        return _zoneLayers(const [1, 2, 3, 4, 5]);
      case 'restorative_hours':
        final deep = await _chart('deep_min');
        final rem = await _chart('rem_min');
        final both = [for (final d in deep.keys) if (rem.containsKey(d)) d];
        return [
          {for (final d in both) d: rem[d]!},
          {for (final d in both) d: deep[d]!},
        ];
      case 'restorative_pct':
        final deep = await _chart('deep_min');
        final rem = await _chart('rem_min');
        final tst = await _chart('tst_min');
        final all = [
          for (final d in tst.keys)
            if (deep.containsKey(d) && rem.containsKey(d) && (tst[d] ?? 0) > 0)
              d
        ];
        return [
          {for (final d in all) d: (rem[d]! / tst[d]!) * 100.0},
          {for (final d in all) d: (deep[d]! / tst[d]!) * 100.0},
        ];
      case 'hvn_hours':
        return [await _chart('sleep_need_min'), await _chart('tst_min')];
      default:
        return const [];
    }
  }

  Future<List<Map<String, double>>> _zoneLayers(List<int> which) async {
    final stack = await zoneStack(which);
    return [
      for (var k = 0; k < which.length; k++)
        {for (final e in stack.entries) e.key: e.value[k]},
    ];
  }

  /// [m]'s value per local day.
  Future<Map<String, double>> daily(TrendMetric m) async {
    switch (m.id) {
      case 'strain' || 'steps' || 'calories' || 'recovery' || 'hrv' ||
            'resting_hr' || 'resp_rate' || 'efficiency':
        return _chart(m.id);
      case 'sleep_debt':
        // A surplus is no debt: never below nothing.
        return {
          for (final e in (await _chart('sleep_debt_min')).entries)
            e.key: e.value < 0 ? 0.0 : e.value,
        };
      case 'vo2max':
        return (await vo2max()).byDay;
      case 'zones_13':
        return _zones(const [1, 2, 3]);
      case 'zones_45':
        return _zones(const [4, 5]);
      case 'zones_all':
        return _zones(const [1, 2, 3, 4, 5]);
      case 'strength_time':
        return _strengthBy(false);
      case 'volume_load':
        return _strengthBy(true);
      case 'avg_hr':
        return _figure('hr_avg');
      case 'time_in_bed':
        return _figure('spt_sec', scale: 1 / 60);
      case 'consistency':
        return _consistency();
      // Performance is hours against need, capped at 100 — the same ratio the
      // Sleep dial draws. Hours vs. needed (%) is that ratio uncapped.
      case 'sleep_perf':
        return _pair('tst_min', 'sleep_need_min',
            (t, n) => n <= 0 ? null : (t / n * 100).clamp(0, 100).toDouble());
      case 'hvn_pct':
        return _pair(
            'tst_min', 'sleep_need_min', (t, n) => n <= 0 ? null : t / n * 100);
      case 'hvn_hours':
        return _pair('tst_min', 'sleep_need_min', (t, n) => t - n);
      case 'restorative_hours':
        return _pair('deep_min', 'rem_min', (d, r) => d + r);
      case 'restorative_pct':
        final restorative = await _pair('deep_min', 'rem_min', (d, r) => d + r);
        final tst = await _chart('tst_min');
        return {
          for (final e in restorative.entries)
            if ((tst[e.key] ?? 0) > 0) e.key: e.value / tst[e.key]! * 100,
        };
      default:
        return const {};
    }
  }
}

/// What a Home row shows: the latest value, and what it is held against.
({double? value, double? against}) trendHeadline(
    TrendMetric m, Map<String, double> daily,
    {required String today, String? firstDay}) {
  double? valueOn(String d) => daily[d] ??
      (m.zeroFill && firstDay != null && d.compareTo(firstDay) >= 0 ? 0 : null);
  if (m.weekly) {
    // This week's total against last week's.
    double? total(int from) {
      var any = false;
      var sum = 0.0;
      for (var i = from; i < from + 7; i++) {
        final v = valueOn(shiftDay(today, -i));
        if (v != null) {
          any = true;
          sum += v;
        }
      }
      return any ? sum : null;
    }

    return (value: total(0), against: total(7));
  }
  // The newest value within the week, against the seven days before it.
  for (var i = 0; i < 7; i++) {
    final d = shiftDay(today, -i);
    final v = daily[d];
    if (v == null) continue;
    return (
      value: v,
      against: _mean([
        for (var j = 1; j <= 7; j++)
          ?daily[shiftDay(d, -j)],
      ]),
    );
  }
  return (
    value: null,
    against: _mean([
      for (var j = 0; j < 7; j++)
        ?daily[shiftDay(today, -j)],
    ]),
  );
}

Color? _directionColor(TrendMetric m, double? value, double? against) {
  if (value == null || against == null || value == against) return null;
  final up = value > against;
  if (m.higherBetter == null) return C.n400;
  return up == m.higherBetter! ? C.optimal : C.poor;
}

/// MY DASHBOARD on Home: one wide row per chosen metric — the value, a small
/// arrow against the comparison, and the comparison under it. No chart: the
/// chart is one tap away.
class DashboardRows extends StatelessWidget {
  final List<String> ids;
  final Map<String, Map<String, double>> daily;
  final String today;
  final String? firstDay;
  final ValueChanged<String> onOpen;

  /// Tiles that are not a metric's row, by id: drawn in their place in [ids].
  final Map<String, Widget> tiles;

  const DashboardRows({
    super.key,
    required this.ids,
    required this.daily,
    required this.today,
    this.firstDay,
    required this.onOpen,
    this.tiles = const {},
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final shown = [
      for (final id in ids)
        if (tiles[id] != null)
          tiles[id]!
        else if (trendMetricOf(id) case final m?)
          _row(c, p, m),
    ];
    if (shown.isEmpty) {
      return Surface(
        child: Text('No metrics on your dashboard. Tap Customize to add some.',
            style: F.body.copyWith(color: p.ink3)),
      );
    }
    return Column(children: [
      for (var i = 0; i < shown.length; i++) ...[
        if (i > 0) const SizedBox(height: S.x2),
        shown[i],
      ],
    ]);
  }

  static const _triangle = S.x2;

  Widget _row(BuildContext c, P p, TrendMetric m) {
    final h = trendHeadline(m, daily[m.id] ?? const {},
        today: today, firstDay: firstDay);
    final dir = _directionColor(m, h.value, h.against);
    final title = m.title;
    return Surface(
      onTap: () => onOpen(m.id),
      semanticLabel: '$title. ${trendFormat(m, h.value)}'
          '${h.against == null ? '' : ', against ${trendFormat(m, h.against)}'}',
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2 + S.half),
      child: Row(children: [
        Icon(m.icon, size: I.md, color: p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child: Text(title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: F.caps.copyWith(color: p.ink)),
        ),
        const SizedBox(width: S.x2),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(m.absent != null ? '--' : trendFormat(m, h.value),
                style: F.n24.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
            // A number with no arrow beside it ends at the middle of where the
            // arrows sit, so the figures of every card line up on one edge.
            if (dir != null) ...[
              const SizedBox(width: S.x2),
              DeltaTriangle(
                  up: h.value! > h.against!, color: dir, size: _triangle),
            ] else
              const SizedBox(width: _triangle / 2),
          ]),
          if (h.against != null && m.absent == null)
            Padding(
              padding: EdgeInsets.only(
                  right: dir == null ? _triangle / 2 : _triangle + S.x2),
              child: Text(trendFormat(m, h.against),
                  style: F.num(F.cap).copyWith(color: p.ink3, fontWeight: FontWeight.w600)),
            ),
        ]),
      ]),
    );
  }
}

enum TrendRange { day, week, month, sixMonths }

/// How many days one step back moves the window. A weekly metric's month is
/// four whole weeks (a bar per week); anything else's is thirty days.
int trendWindowDays(TrendMetric m, TrendRange r) =>
    r == TrendRange.month && m.weekly ? 28 : r.days;

extension on TrendRange {
  int get days => switch (this) {
        TrendRange.day => 1,
        TrendRange.week => 7,
        TrendRange.month => 30,
        TrendRange.sixMonths => 182,
      };
  String get word => switch (this) {
        TrendRange.day => 'day',
        TrendRange.week => 'week',
        TrendRange.month => 'month',
        TrendRange.sixMonths => '6 months',
      };
}

/// One bar: the days it covers and its value.
typedef TrendBar = ({String from, String to, double? v});

/// The bars for a window ending [end] — days for a week or a month, weeks for
/// six months (summed for a weekly metric, averaged otherwise).
///
/// [skip] leaves one day out entirely (today, for an average).
List<TrendBar> trendBars(TrendMetric m, Map<String, double> daily,
    TrendRange range, String end, {String? firstDay, String? skip}) {
  double? on(String d) => d == skip
      ? null
      : daily[d] ??
          (m.zeroFill && firstDay != null && d.compareTo(firstDay) >= 0 &&
                  d.compareTo(end) <= 0
              ? 0
              : null);
  if (range == TrendRange.week || range == TrendRange.day ||
      (range == TrendRange.month && !m.weekly)) {
    return [
      for (var i = range.days - 1; i >= 0; i--)
        (from: shiftDay(end, -i), to: shiftDay(end, -i), v: on(shiftDay(end, -i))),
    ];
  }
  // A bar per week: four of them for a month, twenty-six for six months.
  return [
    for (var w = range == TrendRange.month ? 3 : 25; w >= 0; w--)
      () {
        final last = shiftDay(end, -w * 7);
        final vs = [
          for (var i = 6; i >= 0; i--)
            ?on(shiftDay(last, -i)),
        ];
        final double? v = vs.isEmpty
            ? null
            : m.weekly
                ? vs.fold<double>(0, (a, b) => a + b)
                : _mean(vs);
        return (from: shiftDay(last, -6), to: last, v: v);
      }(),
  ];
}

/// The mean of the bars that have a value. Build them with `skip: today` —
/// a day still in progress is not part of an average.
double? trendAverage(List<TrendBar> bars) => _mean([for (final b in bars) ?b.v]);

/// A day's own shape: [values] per minute (1440) or per hour (24), for [day].
typedef TrendIntra = ({List<double?> values, bool hourly, String day});

/// A night inside a day, in minutes of it, and what the HRV read across it.
typedef TrendSleep = ({int from, int to, double? mean});

/// What a Day view is summarised by: the last point of a running total, the sum
/// of an hourly count, or the mean of a series. Null when nothing was recorded.
double? trendDayValue(TrendMetric m, TrendIntra i) {
  final vs = [for (final v in i.values) ?v];
  if (vs.isEmpty) return null;
  if (m.cumulative) return vs.last;
  if (i.hourly && !m.line) return vs.fold<double>(0, (a, b) => a + b);
  return vs.fold<double>(0, (a, b) => a + b) / vs.length;
}

/// The range [daily] sat in over the 28 days before [windowStart]: its mean
/// give or take one standard deviation. Null with fewer than 7 days to go on,
/// because a band drawn from three days says nothing about what is typical.
({double lo, double hi})? trendTypical(Map<String, double> daily, String windowStart) {
  final vs = [
    for (var i = 1; i <= 28; i++) ?daily[shiftDay(windowStart, -i)],
  ];
  if (vs.length < 7) return null;
  final mean = vs.fold<double>(0, (a, b) => a + b) / vs.length;
  final varc = vs.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) / vs.length;
  final sd = math.sqrt(varc);
  return (lo: mean - sd, hi: mean + sd);
}


class TrendViewScreen extends StatefulWidget {
  final String initial;

  /// Injected by tests; production builds its own.
  final TrendLoader? loader;
  final String? today;

  /// The day the Day view opens on, when it is not today. Opening on a past
  /// day starts on the week instead: a past day keeps its shape, but the week
  /// is what is usually wanted from one.
  final String? day;

  const TrendViewScreen(
      {super.key, required this.initial, this.loader, this.today, this.day});

  @override
  State<TrendViewScreen> createState() => _TrendViewScreenState();
}

class _TrendViewScreenState extends State<TrendViewScreen> {
  late TrendMetric _m = trendMetricOf(widget.initial) ?? kTrendCatalogue.first;
  late TrendRange _range;

  /// True until the user picks a range. Only then may the screen fall back to
  /// the week by itself, when the Day view has nothing to draw.
  bool _auto = true;

  /// Days behind the opening day (Day view), or windows behind today.
  int _back = 0;

  /// The point under a finger. Null at rest, so the readout shows the average.
  int? _selected;
  bool _picking = false;
  final _page = ScrollController();

  /// The part of the day a minute chart shows, in minutes, after pinching.
  double _zoomFrom = 0, _zoomTo = 1440;
  double _zoom0From = 0, _zoom0To = 1440;
  bool get _zoomed => _zoomTo - _zoomFrom < 1439;

  int get _win => trendWindowDays(_m, _range);

  TrendLoader? _loader;
  Map<String, double>? _daily;
  String? _firstDay;
  TrendIntra? _intra;
  String? _intraKey;

  /// The night shaded on the HRV day chart, and what its readings average.
  TrendSleep? _sleep;

  /// The layers behind a stacked or paired chart, and the nights behind a
  /// floating one.
  List<Map<String, double>>? _layers;
  Map<String, ({double bed, double wake})>? _spans;

  String get _today => widget.today ?? todayLabel();
  String get _openDay => widget.day ?? _today;
  String get _dayShown => shiftDay(_openDay, -_back);
  String get _intraWant => '${_m.id}|$_dayShown';
  bool get _hasDay => _m.intraday != TrendIntraday.none;

  List<TrendRange> get _ranges => [
        if (_hasDay) TrendRange.day,
        TrendRange.week,
        TrendRange.month,
        TrendRange.sixMonths,
      ];

  @override
  void initState() {
    super.initState();
    // Every chart opens on the day when it has one and the day is today.
    _range = _hasDay && _openDay == _today ? TrendRange.day : TrendRange.week;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loader = _loader ??= widget.loader ?? TrendLoader(repoOf(context));
    final m = _m;
    final daily = await loader.daily(m);
    final first = await loader.firstDay();
    final layers = m.kind == TrendKind.stacked || m.kind == TrendKind.dual
        ? await loader.layers(m)
        : null;
    final spans = m.kind == TrendKind.floating ? await loader.sleepSpans() : null;
    if (!mounted || m != _m) return;
    setState(() {
      _daily = daily;
      _firstDay = first;
      _layers = layers;
      _spans = spans;
    });
    if (_range == TrendRange.day) await _loadIntra();
  }

  Future<void> _loadIntra() async {
    final loader = _loader;
    if (loader == null) return;
    final m = _m;
    final want = _intraWant;
    final day = _dayShown;
    final r = await loader.intraday(m, day);
    final sleep = m.id == 'hrv' && r != null ? await loader.sleepHrv(day) : null;
    if (!mounted || want != _intraWant) return;
    setState(() {
      _intra = r;
      _sleep = sleep;
      _intraKey = want;
      // Nothing to draw for today and the user has not chosen: the week is
      // the useful default, not an empty chart.
      if (_auto && r == null) {
        _range = TrendRange.week;
        _back = 0;
      }
    });
  }

  void _resetZoom() {
    _zoomFrom = 0;
    _zoomTo = 1440;
  }

  void _pinch(PinchPhase phase, double scale, double focal, double pan) {
    if (phase == PinchPhase.start) {
      _zoom0From = _zoomFrom;
      _zoom0To = _zoomTo;
      return;
    }
    if (phase == PinchPhase.end) return;
    final span0 = _zoom0To - _zoom0From;
    final span = (span0 / scale.clamp(.05, 60)).clamp(30.0, 1440.0).toDouble();
    // The minute under the fingers stays under them, and follows them sideways.
    final under = _zoom0From + focal * span0;
    final from = (under - (focal + pan) * span).clamp(0.0, 1440 - span).toDouble();
    setState(() {
      _zoomFrom = from;
      _zoomTo = from + span;
      _selected = null;
    });
  }

  /// A lab result was entered or cleared: read the estimate again from scratch.
  void _vo2Changed() {
    if (widget.loader == null) _loader = TrendLoader(repoOf(context));
    _loader?._vo2 = null;
    _load();
  }

  void _pick(TrendMetric m) {
    // The new chart opens at its top, not where the list was left: the page is
    // keyed by its metric, so a new metric is a new page.
    setState(() {
      _m = m;
      _picking = false;
      _resetZoom();
      _daily = null;
      _selected = null;
      _intra = null;
      _intraKey = null;
      _layers = null;
      _spans = null;
      if (_range == TrendRange.day && !_hasDay) _range = TrendRange.week;
    });
    _load();
  }

  void _setRange(TrendRange r) {
    setState(() {
      _range = r;
      _back = 0;
      _resetZoom();
      _selected = null;
      _auto = false;
    });
    if (r == TrendRange.day) _loadIntra();
  }

  void _stepBack(int by) {
    setState(() {
      _back += by;
      _resetZoom();
      _selected = null;
      _auto = false;
    });
    if (_range == TrendRange.day) _loadIntra();
  }

  String _shortDate(String day, AppLocalizations? l) {
    final t = _dateOf(day);
    return '${monthShortName(t.month, l)} ${t.day}';
  }

  String _longDate(String day, AppLocalizations? l) {
    final t = _dateOf(day);
    return '${weekdayShortName(t.weekday, l)}, ${monthShortName(t.month, l)} '
        '${t.day}, ${t.year}';
  }

  String _dayName(String day, AppLocalizations? l) {
    final t = _dateOf(day);
    return '${weekdayShortName(t.weekday, l)}, ${monthShortName(t.month, l)} ${t.day}';
  }

  /// The readout's caption for a bar: its date, or its week's dates.
  String _caption(TrendBar b, AppLocalizations? l) => b.from == b.to
      ? _longDate(b.from, l)
      : '${_shortDate(b.from, l)} - ${_longDate(b.to, l)}';

  String _clock(int minuteOfDay) =>
      '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

  /// Minutes after noon as the clock reads them.
  String _clockAfterNoon(double t) {
    final m = (t.round() + 720) % 1440;
    return _clock(m);
  }

  ({double lo, double hi, List<double> ticks}) _axisFor(
          TrendMetric m, List<double> vs, {required bool line}) =>
      trendAxis(m, vs, line: line);

  String _tickText(TrendMetric m, double t) {
    if (m.fmt == TrendFmt.hmm) {
      final h = t ~/ 60, mi = (t.abs() % 60).round();
      return mi == 0 ? '${h}h' : '$h:${mi.toString().padLeft(2, '0')}';
    }
    if (m.fmt == TrendFmt.decimal1 && t % 1 != 0) return t.toStringAsFixed(1);
    if (t.abs() >= 1000) {
      return '${(t / 1000).toStringAsFixed(t % 1000 == 0 ? 0 : 1)}k';
    }
    return '${t.round()}';
  }

  /// The label under each bar. A week names its days, a month marks every
  /// seventh day counting back from today, six months names each new month.
  String _xLabel(int i, List<TrendBar> bars, AppLocalizations? l) {
    final d = _dateOf(bars[i].to);
    return switch (_range) {
      TrendRange.day => '',
      TrendRange.week => '${weekdayShortName(d.weekday, l)}\n${d.day}',
      TrendRange.month when _m.weekly => () {
          final a = _dateOf(bars[i].from);
          return a.month == d.month
              ? '${monthShortName(a.month, l)} ${a.day} - ${d.day}'
              : '${monthShortName(a.month, l)} ${a.day} - ${monthShortName(d.month, l)} ${d.day}';
        }(),
      TrendRange.month => (bars.length - 1 - i) % 7 == 0
          ? '${monthShortName(d.month, l)}\n${d.day}'
          : '',
      TrendRange.sixMonths => i == 0 ||
              _dateOf(bars[i].from).month != _dateOf(bars[i - 1].from).month
          ? monthShortName(_dateOf(bars[i].from).month, l)
          : '',
    };
  }

  /// A weekly metric reads as a total: this week's over its seven days, a
  /// month's as the average week in it, six months as the average of its weeks.
  double? _weeklyTotal(TrendMetric m, Map<String, double> daily, String end) {
    final vs = [
      for (final b in trendBars(m, daily, _range, end, firstDay: _firstDay)) ?b.v
    ];
    if (vs.isEmpty) return null;
    final sum = vs.fold<double>(0, (a, b) => a + b);
    // A week is one total; a month or six months are the average week in them.
    return _range == TrendRange.week ? sum : sum / vs.length;
  }

  static const _zoneColours = [
    C.refZone1,
    C.refZone2,
    C.refZone3,
    C.refZone4,
    C.refZone5,
  ];

  List<String> _layerNames(TrendMetric m) => switch (m.id) {
        'zones_13' => const ['Zone 1', 'Zone 2', 'Zone 3'],
        'zones_45' => const ['Zone 4', 'Zone 5'],
        'zones_all' => const ['Zone 1', 'Zone 2', 'Zone 3', 'Zone 4', 'Zone 5'],
        _ => const ['REM', 'SWS (Deep)'],
      };

  List<Color> _layerColours(TrendMetric m) => switch (m.id) {
        'zones_13' => _zoneColours.sublist(0, 3),
        'zones_45' => _zoneColours.sublist(3, 5),
        'zones_all' => _zoneColours,
        // REM under deep, as the layers come.
        _ => const [C.trendRem, C.trendSws],
      };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final m = _m;
    final isDay = _range == TrendRange.day;
    final daily = _daily ?? const <String, double>{};
    final end = shiftDay(_today, -_back * _win);
    final monthly = _monthlyStyle(m);
    final bars = isDay
        ? const <TrendBar>[]
        : trendBars(m, daily, _range, end, firstDay: _firstDay);

    // The headline: an average, or a total for a weekly metric.
    double? avg, prev, lineAvg;
    var leavesOutToday = false;
    if (!isDay) {
      final skipped = trendAverage(trendBars(m, daily, _range, end,
          firstDay: _firstDay, skip: _today));
      lineAvg = skipped ?? trendAverage(bars);
      if (m.weekly) {
        avg = _weeklyTotal(m, daily, end);
        prev = _weeklyTotal(m, daily, shiftDay(end, -_win));
      } else {
        prev = trendAverage(trendBars(m, daily, _range,
            shiftDay(end, -_win), firstDay: _firstDay));
        // Today is left out while it is still being lived; with nothing else
        // to average, today is the average.
        avg = lineAvg;
        leavesOutToday = skipped != null && _back == 0;
      }
    }
    final band = isDay || !m.line || _range == TrendRange.sixMonths || bars.isEmpty
        ? null
        : trendTypical(daily, bars.first.from);

    final intra = _intraKey == _intraWant ? _intra : null;
    final intraLoading = isDay && _intraKey != _intraWant;
    // HRV counts only the night's readings; every other metric its whole day.
    final dayValue = intra == null
        ? null
        : m.id == 'hrv'
            ? _sleep?.mean
            : trendDayValue(m, intra);

    final monthBars = monthly ? _monthBars(m, daily, end) : null;
    final sel = isDay || _selected == null
        ? null
        : monthly
            ? monthBars!.barAt(_selected!)
            : _selected! < bars.length
                ? bars[_selected!]
                : null;
    final dayTouched = isDay && intra != null && _selected != null;
    final dayPoint = dayTouched && _selected! < intra.values.length
        ? intra.values[_selected!]
        : null;

    // The layers behind a stacked or paired chart, as bars over the window.
    final layerBars = _layers == null
        ? null
        : [
            for (final lm in _layers!)
              trendBars(m, lm, _range, end, firstDay: _firstDay),
          ];

    String caption;
    String value;
    if (isDay) {
      if (dayTouched) {
        final i = _selected!;
        caption = intra.hourly
            ? '${_clock(i * 60)} - ${_clock((i + 1) * 60 % 1440 == 0 ? 1439 : (i + 1) * 60)}'
            : _clock(i);
        value = trendFormat(m, dayPoint);
      } else {
        caption = m.cumulative || ((intra?.hourly ?? false) && !m.line)
            ? 'Total'
            : 'Average';
        value = trendFormat(m, dayValue);
      }
    } else if (sel != null) {
      caption = _caption(sel, l);
      value = trendFormat(m, sel.v);
    } else {
      caption = m.weekly
          ? (_range == TrendRange.week ? 'Weekly total' : 'Avg. weekly total')
          : 'Average';
      value = trendFormat(m, avg);
    }

    final chip = !isDay && sel == null && avg != null && prev != null &&
            !(monthly && _range == TrendRange.sixMonths)
        ? _DeltaChip(m: m, avg: avg, prev: prev, range: _range)
        : null;

    final labels = [
      for (final r in _ranges)
        switch (r) {
          TrendRange.day => 'D',
          TrendRange.week => 'W',
          TrendRange.month => 'M',
          TrendRange.sixMonths => '6M',
        }
    ];

    final Widget readout;
    if (!isDay && m.kind == TrendKind.dual && layerBars != null) {
      // Sleep need and sleep achieved, each with its own change.
      double? la(int k, String e) => trendAverage(trendBars(m, _layers![k], _range, e, firstDay: _firstDay));
      final i = _selected;
      String at(int k) => trendFormat(m, i != null && i < bars.length ? layerBars[k][i].v : la(k, end));
      Widget? chipFor(int k) {
        if (i != null) return null;
        final a = la(k, end), b = la(k, shiftDay(end, -_win));
        return a == null || b == null
            ? null
            : _DeltaChip(m: m, avg: a, prev: b, range: _range, higherBetter: true);
      }

      readout = _MultiReadout(
        caption: i != null && i < bars.length ? _caption(bars[i], l) : null,
        rows: [
          (value: at(0), unit: 'hr', name: 'Avg. need', color: C.optimal, chip: chipFor(0)),
          (value: at(1), unit: 'hr', name: 'Avg. hours', color: C.dialSleep, chip: chipFor(1)),
        ],
        asAverage: i == null,
      );
    } else if (!isDay &&
        m.kind == TrendKind.stacked &&
        sel != null &&
        layerBars != null &&
        _selected! < layerBars.first.length) {
      // Touching a column splits its figure into the parts it is made of, the
      // top of the stack first: Zone 3 over Zone 2 over Zone 1.
      final i = _selected!;
      final names = _layerNames(m);
      final colours = _layerColours(m);
      readout = _MultiReadout(
        caption: _caption(sel, l),
        rows: [
          for (var k = layerBars.length - 1; k >= 0; k--)
            (
              value: trendFormat(m, layerBars[k][i].v),
              unit: 'hr',
              name: names[k],
              color: colours[k],
              chip: null
            ),
        ],
        asAverage: false,
      );
    } else {
      readout = ScrubReadout(
        caption: caption,
        value: value,
        unit: value == '--' ? null : m.unit,
        under: chip == null
            ? null
            : Padding(padding: const EdgeInsets.only(top: S.x2), child: chip),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
            key: ValueKey(m.id),
            controller: _page,
            padding: pad,
            children: [
          const NavBar('Trend View'),
          const SizedBox(height: S.x3),
          _MetricPill(
            m: m,
            open: _picking,
            onTap: () => setState(() => _picking = !_picking),
          ),
          if (_picking) ...[
            const SizedBox(height: S.x2),
            _Picker(current: m, onPick: _pick, allowed: dashboardMetricsOf()),
          ] else ...[
            const SizedBox(height: S.x6),
            if (m.absent != null)
              StatusCard('Not available', m.absent!,
                  fix: '', icon: LucideIcons.circleSlash)
            else ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: readout),
                const SizedBox(width: S.x3),
                _Segments(labels, _ranges.indexOf(_range),
                    (i) => _setRange(_ranges[i])),
              ]),
              const SizedBox(height: S.x3),
              Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _Step(LucideIcons.chevronLeft, 'Earlier', () => _stepBack(1)),
                  Text(
                    (isDay
                            ? _dayName(_dayShown, l)
                            : '${_shortDate(bars.first.from, l)} - '
                                '${_shortDate(end, l)}, ${(_dateOf(end).year % 100).toString().padLeft(2, '0')}')
                        .toUpperCase(),
                    style: F.over.copyWith(
                        color: p.ink, fontWeight: FontWeight.w700),
                  ),
                  _Step(LucideIcons.chevronRight, 'Later',
                      _back == 0 ? null : () => _stepBack(-1)),
                ]),
              ),
              const SizedBox(height: S.x4),
              Text(_sentence(m, avg, prev, band, dayValue, layerBars, l),
                  style: F.head.copyWith(color: p.ink, height: 1.3)),
              if (band != null)
                _legend(p, [(label: 'TYPICAL RANGE', color: p.ink.withValues(alpha: .12))]),
              if (isDay && m.id == 'hrv' && _sleep != null)
                _legend(p, [(label: 'SLEEP', color: C.dialSleep.withValues(alpha: .4))]),
              if (!isDay &&
                  (m.id == 'restorative_hours' || m.id == 'restorative_pct'))
                _legend(p, const [
                  (label: 'SWS (DEEP)', color: C.trendSws),
                  (label: 'REM', color: C.trendRem),
                ]),
              if (!isDay && m.id == 'consistency' && _range != TrendRange.sixMonths)
                Padding(
                  padding: const EdgeInsets.only(top: S.x5),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: S.x6,
                        child: CustomPaint(painter: _DashPainter(p.ink.withValues(alpha: .5))),
                      ),
                      const SizedBox(width: S.x3),
                      Text('Usual bed/waketime',
                          style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              const SizedBox(height: S.x6),
              if (isDay)
                intraLoading
                    ? const SizedBox(
                        height: S.x16 * 4,
                        child: Center(child: CircularProgressIndicator()))
                    : intra == null
                        ? SizedBox(
                            height: S.x16 * 3,
                            child: Center(
                              child: Text('Nothing recorded for this day.',
                                  style: F.cap.copyWith(color: p.ink3)),
                            ))
                        : _dayChart(m, intra)
              else if (_daily == null)
                const SizedBox(
                    height: S.x16 * 4,
                    child: Center(child: CircularProgressIndicator()))
              else
                _chartFor(m, bars, layerBars, lineAvg, band, l),
              if (leavesOutToday) ...[
                const SizedBox(height: S.x4),
                Row(children: [
                  Icon(LucideIcons.info, size: I.sm, color: p.ink3),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                        'Average does not include today (${_shortDate(_today, l)})',
                        style: F.cap.copyWith(color: p.ink3)),
                  ),
                ]),
              ],
              _allTimeRecordsCard(c, m, _daily, l),
              if (m.id == 'strain' && !isDay && _daily != null) ...[
                const SizedBox(height: S.x8),
                _StrainBreakdown(bars: bars),
              ],
              if (!isDay &&
                  layerBars != null &&
                  m.kind == TrendKind.stacked &&
                  m.id != 'restorative_hours' &&
                  m.id != 'restorative_pct') ...[
                const SizedBox(height: S.x4),
                Row(children: [
                  Icon(LucideIcons.info, size: I.sm, color: p.ink3),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text('Zone time is derived from your heart rate.',
                        style: F.cap.copyWith(color: p.ink3)),
                  ),
                ]),
                const SizedBox(height: S.x6),
                _ZoneBreakdown(
                  title: _range == TrendRange.week ? 'WEEKLY TOTAL' : 'AVG. WEEKLY TOTAL',
                  names: _layerNames(m),
                  colours: _layerColours(m),
                  minutes: [
                    for (final lb in layerBars)
                      _range == TrendRange.week
                          ? lb.fold<double>(0, (a, b) => a + (b.v ?? 0))
                          : _mean([for (final b in lb) ?b.v]) ?? 0,
                  ],
                ),
              ],
              // Where the VO₂ max figure came from, and a lab result to anchor it.
              if (m.id == 'vo2max' && _loader != null) ...[
                const SizedBox(height: S.x6),
                _Vo2Panel(loader: _loader!, onLab: _vo2Changed),
              ],
              // What the figure is, in a few plain sentences.
              if (trendAbout(m.id) != null) ...[
                const SizedBox(height: S.x8),
                _AboutCard(title: 'What is ${_aboutName(m)}?', body: trendAbout(m.id)!),
                const SizedBox(height: S.x6),
              ],
            ],
          ],
        ]),
      ),
    );
  }

  Widget _allTimeRecordsCard(
    BuildContext c,
    TrendMetric m,
    Map<String, double>? daily,
    AppLocalizations? l,
  ) {
    if (daily == null || daily.length < 2) return const SizedBox.shrink();
    if (m.id.contains('zone') ||
        m.kind == TrendKind.stacked ||
        m.kind == TrendKind.floating ||
        m.id == 'consistency') {
      return const SizedBox.shrink();
    }
    MapEntry<String, double>? maxEntry;
    MapEntry<String, double>? minEntry;
    for (final e in daily.entries) {
      if (e.value.isNaN || e.value.isInfinite) continue;
      if (maxEntry == null || e.value > maxEntry.value) maxEntry = e;
      if (minEntry == null || e.value < minEntry.value) minEntry = e;
    }
    if (maxEntry == null || minEntry == null) return const SizedBox.shrink();

    final p = P.of(c);
    final unitStr = (m.unit == null || m.unit!.isEmpty) ? '' : ' ${m.unit}';

    Widget cell({
      required String label,
      required MapEntry<String, double> entry,
      required bool isHigh,
    }) {
      final formattedVal = trendFormat(m, entry.value);
      final dateStr = _shortDate(entry.key, l);
      final color = isHigh ? C.trendRem : C.dialStrain;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
          decoration: BoxDecoration(
            color: Color.alphaBlend(p.ink.withValues(alpha: .04), p.card),
            borderRadius: R.rMd,
            border: Border.all(color: p.ink.withValues(alpha: .06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isHigh ? LucideIcons.arrowUpRight : LucideIcons.arrowDownRight,
                    size: I.sm,
                    color: color,
                  ),
                  const SizedBox(width: S.x1),
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: F.caps.copyWith(color: p.ink3, letterSpacing: .5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formattedVal,
                      style: F.n24.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (unitStr.isNotEmpty) ...[
                      const SizedBox(width: S.half),
                      Text(
                        unitStr.trim(),
                        style: F.cap.copyWith(
                          color: p.ink3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: S.x1),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  dateStr,
                  style: F.num(F.cap).copyWith(color: p.ink3),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: S.x6),
      child: Container(
        padding: const EdgeInsets.all(S.x4),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: R.rXl,
          border: Border.all(color: p.ink.withValues(alpha: .08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.trophy, size: I.sm, color: p.ink3),
                const SizedBox(width: S.x2),
                Text(
                  'ALL-TIME RECORDS',
                  style: F.caps.copyWith(
                    color: p.ink,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.x3),
            Row(
              children: [
                cell(label: 'All-Time High', entry: maxEntry, isHigh: true),
                const SizedBox(width: S.x3),
                cell(label: 'All-Time Low', entry: minEntry, isHigh: false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(P p, List<({String label, Color color})> items) => Padding(
        padding: const EdgeInsets.only(top: S.x5),
        child: Align(
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (i, it) in items.indexed) ...[
              if (i > 0) const SizedBox(width: S.x5),
              Container(
                width: S.x4,
                height: S.x4,
                decoration: BoxDecoration(color: it.color, borderRadius: R.rSm),
              ),
              const SizedBox(width: S.x3),
              Text(it.label,
                  style: F.caps.copyWith(color: p.ink)),
            ],
          ]),
        ),
      );

  static const _lineBlue = C.dialStrain;

  Color _colorOf(TrendMetric m) => m.line
      ? _lineBlue
      : switch (m.group) {
          TrendGroup.strain => C.dialStrain,
          TrendGroup.recovery => C.optimal,
          TrendGroup.sleep => C.dialSleep,
        };

  /// Where the labels go along the minutes of a zoomed day: the finest round
  /// step that leaves about five of them.
  static int _clockStep(int span) {
    for (final step in const [360, 240, 180, 120, 60, 30, 15, 10, 5, 2]) {
      if (span / step >= 3.2) return step;
    }
    return 1;
  }

  /// A day's own shape: a line per minute (which two fingers zoom), a line
  /// through the hours, or bars per hour.
  Widget _dayChart(TrendMetric m, TrendIntra intra) {
    if (intra.hourly) {
      final vs = [for (final v in intra.values) ?v];
      final axis = _axisFor(m, vs, line: m.line);
      final xs = [for (var h = 0; h < 24; h++) h % 6 == 0 ? '$h' : ''];
      if (m.line) {
        return ScrubLine(
          values: intra.values,
          xLabels: xs,
          lo: axis.lo,
          hi: axis.hi,
          ticks: axis.ticks,
          tickText: (t) => _tickText(m, t),
          avg: m.id == 'hrv' ? _sleep?.mean : trendDayValue(m, intra),
          color: _colorOf(m),
          markers: false,
          smooth: true,
          gap: 3,
          height: S.x16 * 4 + S.x8,
          // The night, shaded: the part of the day that is counted.
          paintUnder: m.id == 'hrv' && _sleep != null
              ? (canvas, plot, xOf, yOf) {
                  final s = _sleep!;
                  canvas.drawRRect(
                    RRect.fromRectAndRadius(
                        Rect.fromLTRB(
                            plot.left + plot.width * s.from / 1440,
                            plot.top,
                            plot.left + plot.width * s.to / 1440,
                            plot.bottom),
                        const Radius.circular(R.sm)),
                    Paint()..color = C.dialSleep.withValues(alpha: .16),
                  );
                }
              : null,
          // A small dot on each hour that has a value, so the hours read as
          // readings and not as one continuous trace.
          paintOver: (canvas, plot, xOf, yOf) {
            for (var h = 0; h < 24; h++) {
              final v = intra.values[h];
              if (v == null) continue;
              canvas.drawCircle(Offset(xOf(h), yOf(v)), 3, Paint()..color = _colorOf(m));
            }
          },
          onScrub: (i) => setState(() => _selected = i),
        );
      }
      return ScrubColumns(
        values: intra.values,
        xLabels: xs,
        lo: axis.lo,
        hi: axis.hi,
        ticks: axis.ticks,
        tickText: (t) => _tickText(m, t),
        color: _colorOf(m),
        height: S.x16 * 4 + S.x8,
        onScrub: (i) => setState(() => _selected = i),
      );
    }
    final from = _zoomFrom.floor().clamp(0, 1439), to = _zoomTo.ceil().clamp(from + 2, 1440);
    final window = intra.values.sublist(from, to);
    final seen = [for (final v in window) ?v];
    // The axis follows what is on screen, so zooming in re-scales it.
    final axis = _axisFor(
        m, seen.isEmpty ? [for (final v in intra.values) ?v] : seen,
        line: true);
    final step = _clockStep(to - from);
    const marks = {0: '00:00', 360: '06:00', 720: '12:00', 1080: '18:00', 1439: '24:00'};
    final mean = m.cumulative ? null : trendDayValue(m, intra);
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      // Always as tall as the button, so the chart does not jump when it
      // appears under a pinch.
      SizedBox(
        height: S.tap,
        child: Align(
          alignment: Alignment.centerRight,
          child: _zoomed
              ? TextAction('Reset zoom', () => setState(_resetZoom),
                  icon: LucideIcons.zoomOut)
              : null,
        ),
      ),
      ScrubLine(
        values: window,
        xLabels: [
          for (var i = 0; i < window.length; i++)
            _zoomed
                ? ((from + i) % step == 0 ? _clock(from + i) : '')
                : marks[i] ?? '',
        ],
        lo: axis.lo,
        hi: axis.hi,
        ticks: axis.ticks,
        tickText: (t) => _tickText(m, t),
        avg: mean,
        color: _colorOf(m),
        markers: false,
        slots: false,
        gap: 25,
        height: S.x16 * 4 + S.x8,
        onScrub: (i) => setState(() => _selected = i == null ? null : from + i),
        onPinch: _pinch,
      ),
    ]);
  }

  Widget _chartFor(TrendMetric m, List<TrendBar> bars, List<List<TrendBar>>? layerBars,
      double? avg, ({double lo, double hi})? band, AppLocalizations? l) {
    if (_monthlyStyle(m)) return _monthsChart(m, l);
    switch (m.kind) {
      case TrendKind.floating:
        return _floatingChart(m, bars, l);
      case TrendKind.dual:
        if (layerBars != null && layerBars.length == 2) return _dualChart(m, bars, layerBars, l);
        return _chart(m, bars, avg, band, l);
      case TrendKind.stacked:
        if (layerBars != null) return _stackedChart(m, bars, layerBars, avg, l);
        return _chart(m, bars, avg, band, l);
      case TrendKind.columns:
        return _chart(m, bars, avg, band, l);
    }
  }

  Widget _chart(TrendMetric m, List<TrendBar> bars, double? avg,
      ({double lo, double hi})? band, AppLocalizations? l) {
    final vs = [for (final b in bars) ?b.v];
    final axis = _axisFor(m, [...vs, if (band != null) ...[band.lo, band.hi]],
        line: m.line);
    final color = _colorOf(m);
    final week = _range == TrendRange.week;
    final xs = [for (var i = 0; i < bars.length; i++) _xLabel(i, bars, l)];
    if (m.line) {
      return ScrubLine(
        values: [for (final b in bars) b.v],
        xLabels: xs,
        valueLabels: week
            ? [for (final b in bars) b.v == null ? '' : trendFormat(m, b.v)]
            : const [],
        lo: axis.lo,
        hi: axis.hi,
        ticks: axis.ticks,
        tickText: (t) => _tickText(m, t),
        avg: avg,
        band: band,
        color: color,
        markers: week,
        gap: 1,
        height: S.x16 * 4 + S.x8,
        onScrub: (i) => setState(() => _selected = i),
      );
    }
    return ScrubColumns(
      values: [for (final b in bars) b.v],
      xLabels: xs,
      // A week's values sit over its bars; a month is too many to label.
      valueLabels:
          week ? [for (final b in bars) b.v == null ? '' : trendFormat(m, b.v)] : const [],
      lo: axis.lo,
      hi: axis.hi,
      ticks: axis.ticks,
      tickText: (t) => _tickText(m, t),
      avg: avg,
      marks: _monthMarks(m, bars, [for (final b in bars) b.v]),
      color: color,
      colorOf: m.id == 'recovery' ? (i, v) => recoveryColor(v) : null,
      height: S.x16 * 4 + S.x8,
      onScrub: (i) => setState(() => _selected = i),
    );
  }

  /// On six months, a white line at each month's average over the weekly
  /// columns it spans, the figure on it. Empty on any other range.
  List<ColumnMark> _monthMarks(TrendMetric m, List<TrendBar> bars, List<double?> totals) {
    if (_range != TrendRange.sixMonths) return const [];
    final out = <ColumnMark>[];
    var from = 0;
    for (var i = 1; i <= bars.length; i++) {
      if (i < bars.length &&
          _dateOf(bars[i].to).month == _dateOf(bars[i - 1].to).month) {
        continue;
      }
      final avg = _mean([for (var k = from; k < i; k++) ?totals[k]]);
      if (avg != null) {
        out.add((from: from, to: i - 1, v: avg, text: trendFormat(m, avg)));
      }
      from = i;
    }
    return out;
  }

  /// Columns stacked from the layers, each in its own colour.
  Widget _stackedChart(TrendMetric m, List<TrendBar> bars,
      List<List<TrendBar>> layerBars, double? avg, AppLocalizations? l) {
    final n = bars.length;
    final stacks = <List<double>?>[];
    final totals = <double?>[];
    for (var i = 0; i < n; i++) {
      final parts = [for (final lb in layerBars) lb[i].v];
      if (parts.every((v) => v == null)) {
        stacks.add(null);
        totals.add(null);
      } else {
        final ps = [for (final v in parts) v ?? 0];
        stacks.add(ps);
        totals.add(ps.fold<double>(0, (a, b) => a + b));
      }
    }
    final axis = _axisFor(m, [for (final t in totals) ?t], line: false);
    final week = _range == TrendRange.week;
    return ScrubColumns(
      values: totals,
      stacks: stacks,
      segmentColors: _layerColours(m),
      xLabels: [for (var i = 0; i < n; i++) _xLabel(i, bars, l)],
      valueLabels:
          week ? [for (final t in totals) t == null ? '' : trendFormat(m, t)] : const [],
      lo: axis.lo,
      hi: axis.hi,
      ticks: axis.ticks,
      tickText: (t) => _tickText(m, t),
      avg: avg,
      marks: _monthMarks(m, bars, totals),
      labelColor: P.of(context).ink,
      color: _colorOf(m),
      height: S.x16 * 4 + S.x8,
      onScrub: (i) => setState(() => _selected = i),
    );
  }

  /// Sleep need and sleep achieved, two lines on one scale from zero.
  Widget _dualChart(TrendMetric m, List<TrendBar> bars,
      List<List<TrendBar>> layerBars, AppLocalizations? l) {
    final a = [for (final b in layerBars[0]) b.v];
    final b2 = [for (final b in layerBars[1]) b.v];
    final axis = _axisFor(m, [for (final v in [...a, ...b2]) ?v], line: false);
    final week = _range == TrendRange.week;
    String lab(double? v) => v == null ? '' : trendFormat(m, v);
    return ScrubPair(
      a: a,
      b: b2,
      aLabels: week ? [for (final v in a) lab(v)] : const [],
      bLabels: week ? [for (final v in b2) lab(v)] : const [],
      xLabels: [for (var i = 0; i < bars.length; i++) _xLabel(i, bars, l)],
      lo: axis.lo,
      hi: axis.hi,
      ticks: axis.ticks,
      tickText: (t) => _tickText(m, t),
      colorA: C.optimal,
      colorB: C.dialSleep,
      height: S.x16 * 4 + S.x8,
      onScrub: (i) => setState(() => _selected = i),
    );
  }

  /// Six months of a daily figure, shown a month at a time: the days faint in
  /// the background, and a white line at each month's average.
  bool _monthlyStyle(TrendMetric m) =>
      _range == TrendRange.sixMonths &&
      m.absent == null &&
      (m.kind == TrendKind.floating || (m.kind == TrendKind.columns && !m.weekly));

  _MonthBars _monthBars(TrendMetric m, Map<String, double> daily, String end) {
    final days = [for (var i = 181; i >= 0; i--) shiftDay(end, -i)];
    final spans = <({int from, int to})>[];
    var start = 0;
    for (var i = 1; i <= days.length; i++) {
      if (i == days.length || _dateOf(days[i]).month != _dateOf(days[i - 1]).month) {
        spans.add((from: start, to: i - 1));
        start = i;
      }
    }
    // Today is still being lived: it is left out of an average.
    final avgs = [
      for (final sp in spans)
        _mean([
          for (var i = sp.from; i <= sp.to; i++)
            if (days[i] != _today) ?daily[days[i]],
        ]),
    ];
    return _MonthBars(days, spans, avgs);
  }

  Widget _monthsChart(TrendMetric m, AppLocalizations? l) {
    final daily = _daily ?? const <String, double>{};
    final end = shiftDay(_today, -_back * _win);
    final md = _monthBars(m, daily, end);
    final floating = m.kind == TrendKind.floating;
    final nights = _spans ?? const <String, ({double bed, double wake})>{};

    // The newest month with a figure wears the change on the one before it.
    int? last, before;
    for (var k = md.avgs.length - 1; k >= 0; k--) {
      if (md.avgs[k] == null) continue;
      if (last == null) {
        last = k;
      } else {
        before = k;
        break;
      }
    }
    String? note;
    Color? tone;
    if (last != null && before != null && md.avgs[before]! != 0) {
      final pct = ((md.avgs[last]! - md.avgs[before]!) / md.avgs[before]!.abs() * 100).round();
      if (pct != 0) {
        note = '${pct > 0 ? '+' : '-'}${pct.abs()}%';
        final good = m.higherBetter;
        tone = good == null ? null : ((pct > 0) == good ? C.optimal : C.strainDown);
      }
    }

    String name(int from) => monthShortName(_dateOf(md.days[from]).month, l);
    final marks = <MonthMark>[];
    for (var k = 0; k < md.spans.length; k++) {
      final sp = md.spans[k];
      final isLast = k == last;
      if (floating) {
        final ns = [
          for (var i = sp.from; i <= sp.to; i++) ?nights[md.days[i]],
        ];
        if (ns.isEmpty) {
          marks.add(MonthMark(from: sp.from, to: sp.to, label: name(sp.from)));
          continue;
        }
        final bed = ns.fold<double>(0, (a, n) => a + n.bed) / ns.length;
        final wake = ns.fold<double>(0, (a, n) => a + n.wake) / ns.length;
        marks.add(MonthMark(
            from: sp.from,
            to: sp.to,
            label: name(sp.from),
            value: bed,
            text: _clockAfterNoon(bed),
            value2: wake,
            text2: _clockAfterNoon(wake)));
      } else {
        final v = md.avgs[k];
        marks.add(MonthMark(
          from: sp.from,
          to: sp.to,
          label: name(sp.from),
          value: v,
          text: v == null ? '' : trendFormat(m, v),
          note: isLast ? note : null,
          tone: isLast ? tone : null,
        ));
      }
    }

    final color = _colorOf(m);
    final dayVals = [for (final d in md.days) daily[d]];
    String describe(int i) => _longDate(md.days[i], l);
    if (floating) {
      final ranges = [
        for (final d in md.days)
          nights[d] == null ? null : (from: nights[d]!.bed, to: nights[d]!.wake),
      ];
      final axis = _clockAxis(ranges);
      return ScrubMonths(
        days: dayVals,
        spans: ranges,
        months: marks,
        lo: axis.lo,
        hi: axis.hi,
        ticks: axis.ticks,
        tickText: _clockAfterNoon,
        down: true,
        color: color,
        height: S.x16 * 4 + S.x16,
        describe: describe,
        onScrub: (i) => setState(() => _selected = i),
      );
    }
    final axis = _axisFor(
        m, [for (final v in dayVals) ?v, for (final v in md.avgs) ?v], line: true);
    return ScrubMonths(
      days: dayVals,
      months: marks,
      lo: axis.lo,
      hi: axis.hi,
      ticks: axis.ticks,
      tickText: (t) => _tickText(m, t),
      color: color,
      height: S.x16 * 4 + S.x8,
      describe: describe,
      onScrub: (i) => setState(() => _selected = i),
    );
  }

  /// A clock on a four-hour grid from 19:00, grown to hold every night with
  /// room for the times written over and under its bar: 19:00 at the top,
  /// 11:00 at the bottom as a week usually sits, and further out when it
  /// does not.
  ({double lo, double hi, List<double> ticks}) _clockAxis(
      Iterable<({double from, double to})?> ranges) {
    const grid = 420.0, step = 240.0, room = 90.0;
    var lo = grid, hi = grid + step * 4;
    for (final r in ranges) {
      if (r == null) continue;
      while (r.from < lo + room) {
        lo -= step;
      }
      while (r.to > hi - room) {
        hi += step;
      }
    }
    return (lo: lo, hi: hi, ticks: [for (var t = lo; t <= hi + 1; t += step) t]);
  }

  /// Each night as a bar floating from bed to wake, on a clock.
  Widget _floatingChart(TrendMetric m, List<TrendBar> bars, AppLocalizations? l) {
    final spans = _spans ?? const <String, ({double bed, double wake})>{};
    final n = bars.length;
    ({double from, double to})? rangeOf(TrendBar b) {
      final days = <({double bed, double wake})>[];
      var d = b.from;
      while (d.compareTo(b.to) <= 0) {
        final s = spans[d];
        if (s != null) days.add(s);
        d = shiftDay(d, 1);
      }
      if (days.isEmpty) return null;
      final bed = days.fold<double>(0, (a, s) => a + s.bed) / days.length;
      final wake = days.fold<double>(0, (a, s) => a + s.wake) / days.length;
      return (from: bed, to: wake);
    }

    final ranges = [for (final b in bars) rangeOf(b)];
    // Usual: the mean of the seven nights before each, when there are three.
    List<({double bed, double wake})?>? usual;
    if (m.id == 'consistency') {
      usual = [
        for (final b in bars)
          () {
            final prior = <({double bed, double wake})>[
              for (var k = 1; k <= 7; k++) ?spans[shiftDay(b.to, -k)],
            ];
            if (prior.length < 3) return null;
            return (
              bed: prior.fold<double>(0, (a, s) => a + s.bed) / prior.length,
              wake: prior.fold<double>(0, (a, s) => a + s.wake) / prior.length,
            );
          }()
      ];
    }
    final axis = _clockAxis(ranges);
    final week = _range == TrendRange.week;
    final consistency = m.id == 'consistency';
    // A month names its average bed and wake times on the axis.
    final seen = [for (final r in ranges) ?r];
    final tags = week || seen.isEmpty
        ? const <({double at, String text})>[]
        : [
            for (final t in [
              seen.fold<double>(0, (a, r) => a + r.from) / seen.length,
              seen.fold<double>(0, (a, r) => a + r.to) / seen.length,
            ])
              (at: t, text: _clockAfterNoon(t)),
          ];
    return ScrubRanges(
      ranges: ranges,
      xLabels: [for (var i = 0; i < n; i++) _xLabel(i, bars, l)],
      lo: axis.lo,
      hi: axis.hi,
      ticks: axis.ticks,
      tickText: _clockAfterNoon,
      timeText: _clockAfterNoon,
      color: C.dialSleep,
      emphasis: consistency ? n - 1 : null,
      labelAll: !consistency && week,
      usual: usual,
      tags: tags,
      height: S.x16 * 4 + S.x16,
      onScrub: (i) => setState(() => _selected = i),
    );
  }

  static String _short(TrendMetric m) => switch (m.id) {
        'hrv' => 'HRV',
        'resting_hr' => 'resting heart rate',
        'resp_rate' => 'respiratory rate',
        _ => m.title,
      };

  /// What the figure is, in a clause: "your total time in HR zones 1-3".
  static String _total(TrendMetric m) => switch (m.id) {
        'zones_13' => 'time in HR zones 1-3',
        'zones_45' => 'time in HR zones 4-5',
        'zones_all' => 'time in HR zones',
        'strength_time' => 'strength activity time',
        _ => m.title.toLowerCase(),
      };

  String _sentence(TrendMetric m, double? avg, double? prev,
      ({double lo, double hi})? band, double? dayValue,
      List<List<TrendBar>>? layerBars, AppLocalizations? l) {
    if (_range == TrendRange.day) {
      if (dayValue == null) {
        return m.id == 'hrv'
            ? 'No heart rate variability from a night\'s sleep for this day.'
            : 'No ${m.title.toLowerCase()} recorded for this day.';
      }
      final when = _dayShown == _today ? 'today' : 'on ${_dayName(_dayShown, l)}';
      if (m.id == 'hrv') {
        return 'Your average heart rate variability asleep $when '
            '${_dayShown == _today ? 'is' : 'was'} ${trendFormat(m, dayValue)} ms.';
      }
      final title = m.title.toLowerCase();
      final agg = m.cumulative || title.startsWith('average')
          ? ''
          : ((_intra?.hourly ?? false) && !m.line)
              ? 'total '
              : 'average ';
      return 'Your $agg$title $when '
          '${_dayShown == _today ? 'is' : 'was'} ${trendFormat(m, dayValue)}'
          '${m.unit == null ? '' : ' ${m.unit}'}.';
    }
    final word = _range.word;
    if (m.kind == TrendKind.dual && layerBars != null && layerBars.length == 2) {
      final need = trendAverage(layerBars[0]), got = trendAverage(layerBars[1]);
      if (need != null && got != null) {
        return 'This $word you averaged ${trendFormat(m, got)} of sleep against '
            'a need of ${trendFormat(m, need)}.';
      }
    }
    if (avg == null) return 'No ${m.title} recorded this $word.';
    final shown = trendFormat(m, avg);
    if (band != null && _range == TrendRange.week) {
      final rel = avg < band.lo
          ? 'below'
          : avg > band.hi
              ? 'above'
              : 'within';
      return 'Your average ${_short(m)} during this 7-day period was $rel its '
          'typical range (${trendFormat(m, band.lo)} - ${trendFormat(m, band.hi)}) '
          'at the time.';
    }
    String rel(double a, double b) => trendFormat(m, a) == trendFormat(m, b)
        ? 'the same as'
        : a > b
            ? 'above'
            : 'below';
    if (_range == TrendRange.week && prev != null) {
      if (m.weekly) {
        return 'During this 7-day period, your total ${_total(m)} ($shown) was '
            '${rel(avg, prev)} your previous 7-day total of ${trendFormat(m, prev)}.';
      }
      if (m.group == TrendGroup.sleep) {
        return 'Your average ${m.title.toLowerCase()} ($shown) this week was '
            '${rel(avg, prev)} your previous 7-day average of ${trendFormat(m, prev)}.';
      }
      return 'During this 7-day period, your average ${m.title} ($shown) was '
          '${rel(avg, prev)} your average at the time (${trendFormat(m, prev)}).';
    }
    if (m.weekly) {
      return _range == TrendRange.week
          ? 'Your total ${_total(m)} this week is $shown. Keep wearing your '
              'band to see how this changes over time.'
          : 'Your average weekly total of ${_total(m)} over this '
              '${_range == TrendRange.month ? 'month' : '6-month period'} is $shown. '
              'Keep wearing your band to see how this changes over time.';
    }
    if (_range == TrendRange.sixMonths) {
      return 'During this 6-month period, your average ${_short(m)} has been '
          '$shown. Keep wearing your band to see how this changes over time.';
    }
    return 'Your average ${m.title} this $word is $shown. Keep wearing your '
        'band to see how this changes over time.';
  }
}

/// The round steps an axis may use, finest first: 1, 2, 2.5 and 5 at every
/// magnitude from a tenth to a hundred thousand.
final List<double> _niceSteps = [
  for (final mag in const [.1, 1, 10, 100, 1000, 10000, 100000])
    for (final f in const [1.0, 2.0, 2.5, 5.0]) f * mag,
];

/// The same, in minutes, for a duration: half-hours, hours, then multiples.
const List<double> _minuteSteps = [30, 60, 120, 180, 240, 360, 480, 720, 1440];

/// The axis, from the data: bounds that follow the values instead of a fixed
/// range, on the finest round step that needs no more than a handful of lines.
/// Columns start at zero; a line follows its own values, with a little room
/// either side. A scale with a ceiling of its own (strain 21, a percentage)
/// never goes past it, and at that ceiling is cut evenly (0 7 14 21).
({double lo, double hi, List<double> ticks}) trendAxis(
    TrendMetric m, List<double> vs, {required bool line}) {
  final cap = m.axisMax;
  if (vs.isEmpty) {
    final hi = cap ?? 1.0;
    return (lo: 0, hi: hi, ticks: [0, hi]);
  }
  final mn = vs.reduce(math.min), mx = vs.reduce(math.max);
  double lo, hi;
  if (!line) {
    lo = math.min(0.0, mn);
    hi = mx <= 0 ? 1.0 : mx;
  } else {
    final room = math.max((mx - mn) * .12, mx.abs() * .02 + .5);
    lo = mn - room;
    hi = mx + room;
    if (lo < 0 && !m.signed) lo = 0;
  }
  final maxIntervals = line ? 7 : 6;
  final steps = m.fmt == TrendFmt.hmm ? _minuteSteps : _niceSteps;
  var step = steps.last;
  for (final c in steps) {
    final n = (hi / c - 1e-9).ceil() - (lo / c + 1e-9).floor();
    if (n <= maxIntervals) {
      step = c;
      break;
    }
  }
  hi = (hi / step - 1e-9).ceil() * step;
  lo = (lo / step + 1e-9).floor() * step;
  if (hi <= lo) hi = lo + step;
  if (cap != null && hi >= cap - 1e-9) {
    final n = cap == 100 ? 4 : (cap % 3 == 0 ? 3 : 4);
    final s = cap / n;
    return (lo: 0, hi: cap, ticks: [for (var k = 0; k <= n; k++) s * k]);
  }
  return (
    lo: lo,
    hi: hi,
    ticks: [for (var t = lo; t <= hi + step / 1000; t += step) t],
  );
}

/// The range tabs: a short dark track with the chosen one lifted out of it.
/// Fixed in width, so a fourth tab (D) shares the same track instead of
/// widening it.
class _Segments extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;
  const _Segments(this.labels, this.index, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SizedBox(
      width: S.x16 * 2.8,
      height: S.tap,
      child: Container(
        padding: const EdgeInsets.all(S.x1),
        decoration: BoxDecoration(
          color: Color.alphaBlend(C.char.withValues(alpha: .5), p.bg),
          borderRadius: R.rXl,
        ),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Pressable(
                onTap: () => onTap(i),
                semanticLabel: 'Show ${labels[i]}',
                child: Container(
                  alignment: Alignment.center,
                  decoration: i == index
                      ? BoxDecoration(color: p.card, borderRadius: R.rLg)
                      : null,
                  child: Text(labels[i],
                      maxLines: 1,
                      style: F.caps.copyWith(
                          color: i == index ? p.ink : p.ink3)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Several figures, each in its own colour with its own name under it: sleep
/// need beside sleep achieved, deep beside REM.
class _MultiReadout extends StatelessWidget {
  /// A date over the lot, while a night is touched.
  final String? caption;
  final List<({String value, String unit, String name, Color color, Widget? chip})> rows;

  /// The names read as small captions of an average; false puts them as the
  /// kind of sleep a figure is.
  final bool asAverage;
  const _MultiReadout(
      {required this.caption, required this.rows, required this.asAverage});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (caption != null) ...[
        Text(caption!.toUpperCase(),
            style: F.over.copyWith(color: p.ink2)),
        const SizedBox(height: S.x1),
      ],
      for (final r in rows) ...[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(r.value,
                  style: F.n34.copyWith(color: r.color, fontWeight: FontWeight.w700)),
              if (r.value != '--') ...[
                const SizedBox(width: S.x1),
                Text(r.unit,
                    style: F.head.copyWith(color: r.color, fontWeight: FontWeight.w600)),
              ],
              if (r.chip != null) ...[const SizedBox(width: S.x3), r.chip!],
            ],
          ),
        ),
        const SizedBox(height: S.half),
        Text(r.name.toUpperCase(),
            style: F.over.copyWith(color: p.ink2)),
        const SizedBox(height: S.x2),
      ],
    ]);
  }
}

/// A short dashed stroke, for the legend of a dashed line.
class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var x = 0.0; x < size.width; x += S.x2 + S.half) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset(math.min(x + S.x1, size.width), size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// The window's time in each heart-rate zone: a stacked bar and a line per
/// zone with its time.
class _ZoneBreakdown extends StatelessWidget {
  final String title;
  final List<String> names;
  final List<Color> colours;
  final List<double> minutes;
  const _ZoneBreakdown({
    required this.title,
    required this.names,
    required this.colours,
    required this.minutes,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final total = minutes.fold<double>(0, (a, b) => a + b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [
        TextSpan(
            text: 'HR ZONES BREAKDOWN ',
            style: F.caps.copyWith(color: p.ink)),
        TextSpan(
            text: '($title)',
            style: F.caps.copyWith(color: p.ink3)),
      ])),
      const SizedBox(height: S.x4),
      if (total <= 0)
        Text('No zone time recorded in this window.',
            style: F.cap.copyWith(color: p.ink3))
      else ...[
        SizedBox(
          height: S.x3,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var k = 0; k < minutes.length; k++)
              if (minutes[k] > 0) ...[
                Expanded(
                  flex: math.max(1, (minutes[k] / total * 1000).round()),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colours[k],
                      borderRadius: BorderRadius.circular(R.sm / 3),
                    ),
                  ),
                ),
                const SizedBox(width: S.half),
              ],
          ]),
        ),
        const SizedBox(height: S.x4),
        for (var k = 0; k < minutes.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x3),
            child: Row(children: [
              Container(
                width: S.x3,
                height: S.x3,
                decoration: BoxDecoration(color: colours[k], borderRadius: R.rSm),
              ),
              const SizedBox(width: S.x3),
              SizedBox(
                width: S.x16 + S.x4,
                child: Text(hMm(minutes[k].round()),
                    style: F.n24.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Text(names[k], style: F.body.copyWith(color: p.ink2)),
              ),
            ]),
          ),
      ],
    ]);
  }
}

/// The metric the screen is about, as a full-width pill. Tapping it opens the
/// list of every metric.
class _MetricPill extends StatelessWidget {
  final TrendMetric m;
  final bool open;
  final VoidCallback onTap;
  const _MetricPill({required this.m, required this.open, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Metric: ${m.title}. Change',
      child: Container(
        height: S.x16,
        padding: const EdgeInsets.symmetric(horizontal: S.x5),
        decoration: BoxDecoration(
          color: Color.alphaBlend(p.ink.withValues(alpha: .12), p.card2),
          borderRadius: R.rLg,
        ),
        child: Row(children: [
          Icon(m.icon, size: I.xl, color: p.ink),
          const SizedBox(width: S.x5),
          Expanded(
            child: Text(m.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.caps.copyWith(
                    color: p.ink, fontWeight: FontWeight.w700)),
          ),
          Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: I.lg, color: p.ink),
        ]),
      ),
    );
  }
}

/// How many days of the period fell in each strain band, as a stacked bar and
/// a count per band. Days with no strain are not in any band.
class _StrainBreakdown extends StatelessWidget {
  final List<TrendBar> bars;
  const _StrainBreakdown({required this.bars});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final vs = [for (final b in bars) ?b.v];
    var allOut = 0, strenuous = 0, moderate = 0, light = 0;
    for (final v in vs) {
      if (v > 18) {
        allOut++;
      } else if (v > 14) {
        strenuous++;
      } else if (v > 10) {
        moderate++;
      } else {
        light++;
      }
    }
    final bands = [
      (allOut, 'All Out (>18.0)', C.dialStrain),
      (strenuous, 'Strenuous (14.1-18.0)', C.strainStrenuous),
      (moderate, 'Moderate (10.1-14.0)', C.strainModerate),
      (light, 'Light (0.0-10.0)', C.strainLight),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [
        TextSpan(
            text: 'STRAIN BREAKDOWN ',
            style: F.caps.copyWith(color: p.ink)),
        TextSpan(
            text: '(DAYS)',
            style: F.caps.copyWith(color: p.ink3)),
      ])),
      const SizedBox(height: S.x4),
      if (vs.isEmpty)
        Text('No strain recorded this period.',
            style: F.cap.copyWith(color: p.ink3))
      else ...[
        SizedBox(
          height: S.x3,
          child: Row(children: [
            for (final b in bands)
              if (b.$1 > 0) ...[
                Expanded(
                  flex: b.$1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: b.$3,
                      borderRadius: R.rSm,
                    ),
                  ),
                ),
                const SizedBox(width: S.half),
              ],
          ]),
        ),
        const SizedBox(height: S.x4),
        for (final b in bands)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x3),
            child: Row(children: [
              Container(
                width: S.x3,
                height: S.x3,
                decoration: BoxDecoration(color: b.$3, borderRadius: R.rSm),
              ),
              const SizedBox(width: S.x3),
              SizedBox(
                width: S.x12,
                child: Text('${b.$1}x',
                    style: F.n24.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Text(b.$2,
                    style: F.body.copyWith(color: p.ink2)),
              ),
            ]),
          ),
      ],
    ]);
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Step(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: S.x8,
        height: S.tap,
        child: Icon(icon, size: I.md, color: onTap == null ? p.track : p.ink),
      ),
    );
  }
}

/// The change against the window before, as a percentage: green when it is the
/// way this metric wants to go, orange when it is not, plain when neither way
/// is better. Only drawn when both windows have an average.
class _DeltaChip extends StatelessWidget {
  final TrendMetric m;
  final double avg, prev;
  final TrendRange range;

  /// Overrides the metric's own idea of which way is good, for a figure that
  /// is one of two on a screen (sleep need rises, and it is shown in green).
  final bool? higherBetter;
  const _DeltaChip({
    required this.m,
    required this.avg,
    required this.prev,
    required this.range,
    this.higherBetter,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final diff = avg - prev;
    // A signed measure (a shortfall in hours) has no meaningful percentage:
    // its change is stated in its own units.
    final String text;
    if (m.signed || prev == 0) {
      text = trendFormat(m, diff.abs());
    } else {
      text = '${(diff / prev.abs() * 100).abs().round()}%';
    }
    final flat = text == '0%' || (m.signed && trendFormat(m, diff.abs()) == trendFormat(m, 0));
    final up = diff > 0;
    final good = higherBetter ?? m.higherBetter;
    final better = flat || good == null ? null : up == good;
    final tone = better == null ? p.ink2 : (better ? C.optimal : C.strainDown);
    final past = switch (range) {
      TrendRange.day => 'prior day',
      TrendRange.week => 'prior week',
      TrendRange.month => 'prior month',
      TrendRange.sixMonths => 'prior 6 months',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
      decoration: BoxDecoration(
        color: better == null ? p.card2 : tone.withValues(alpha: .18),
        borderRadius: R.rSm,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!flat) ...[
          CustomPaint(
            size: const Size(S.x3, S.x2 + S.half),
            painter: _TrianglePainter(color: tone, up: up),
          ),
          const SizedBox(width: S.x2),
        ],
        Flexible(
          child: Text('$text vs. $past',
              style: F.cap.copyWith(color: tone, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// The solid triangle in a delta chip.
class _TrianglePainter extends CustomPainter {
  final Color color;
  final bool up;
  _TrianglePainter({required this.color, required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    final path = up
        ? (Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..close())
        : (Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close());
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color || old.up != up;
}

/// The dropdown: every metric, under its group's heading.
class _Picker extends StatelessWidget {
  final TrendMetric current;
  final ValueChanged<TrendMetric> onPick;

  /// The metrics switched on in My Dashboard (null: all of them). The one on
  /// screen is always listed, so the picker never loses its own place.
  final Set<String>? allowed;
  const _Picker({required this.current, required this.onPick, this.allowed});

  bool _listed(TrendMetric m) =>
      allowed == null || allowed!.contains(m.id) || m == current;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final g in TrendGroup.values)
          if (kTrendCatalogue.any((m) => m.group == g && _listed(m))) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x2),
            child: Row(children: [
              Text(trendGroupName(g).toUpperCase(),
                  style: F.over.copyWith(
                      color: p.ink2, fontWeight: FontWeight.w700)),
              const SizedBox(width: S.x3),
              Expanded(child: Container(height: S.half / 2, color: p.line)),
            ]),
          ),
          for (final m in kTrendCatalogue)
            if (m.group == g && _listed(m))
              Pressable(
                onTap: () => onPick(m),
                semanticLabel: m.title,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: S.x2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x4),
                  decoration: BoxDecoration(
                    color: m == current ? p.card2 : null,
                    borderRadius: R.rLg,
                  ),
                  child: Row(children: [
                    Icon(m.icon, size: I.lg, color: p.ink2),
                    const SizedBox(width: S.x4),
                    Expanded(
                      child: Text(m.title.toUpperCase(),
                          style: F.caps.copyWith(color: p.ink)),
                    ),
                  ]),
                ),
              ),
        ],
      ]),
    );
  }
}

/// The months of a six-month window, for [TrendViewScreen]: their day spans and
/// the average of each.
class _MonthBars {
  /// The window's days, oldest first.
  final List<String> days;
  final List<({int from, int to})> spans;
  final List<double?> avgs;
  const _MonthBars(this.days, this.spans, this.avgs);

  /// The month holding day [i], as a bar over its days.
  TrendBar? barAt(int i) {
    for (var k = 0; k < spans.length; k++) {
      if (i >= spans[k].from && i <= spans[k].to) {
        return (from: days[spans[k].from], to: days[spans[k].to], v: avgs[k]);
      }
    }
    return null;
  }
}

String _aboutName(TrendMetric m) => switch (m.id) {
      'hrv' => 'Heart Rate Variability',
      'avg_hr' => 'Average Heart Rate',
      _ => m.title.replaceAll(RegExp(r' \(.*\)'), ''),
    };

/// A short explanation of what a metric is and how to read it, written for this
/// app's own measure of it. Null for a metric with nothing to explain.
String? trendAbout(String id) => _about[id];

const _about = <String, String>{
  'vo2max':
      'VO₂ max is the most oxygen your body can use in hard, sustained effort, '
          'in millilitres per kilo of body weight a minute. It is the size of '
          'your aerobic engine, and one of the strongest single predictors of '
          'how well you perform and how long you stay healthy.\n\n'
          'Locus '
          'estimates it in three steps, as sharp as your data allows: from your '
          'profile and weekly heart-rate zones; from the pace and heart rate '
          'of your outdoor runs; or anchored to a lab test you enter. It moves '
          'weekly. A rising line means your fitness is building, a falling one '
          'detraining or illness; the level is an estimate, the direction is '
          'what to watch.',
  'strain':
      'Day strain scores how much cardiovascular load the day put on your body, '
          'from 0 to 21. It builds from the time your heart rate spends above its '
          'resting level, with harder minutes counting for more. Under 10 is '
          'light, 10 to 13.9 moderate, 14 to 17.9 strenuous, and 18 or more is '
          'all out.\n\nThe scale is logarithmic: the last few points cost far '
          'more effort than the first.',
  'steps':
      'Steps counts the steps your band detected through the day. It is a beta '
          'estimate read from wrist movement, so carrying a bag, pushing a '
          'stroller or a rough car ride can nudge it. A guided walk in settings '
          'calibrates it to your stride.',
  'zones_13':
      'Heart rate zones 1 to 3 are the easy to steady efforts: a gentle pulse, '
          'an aerobic pace you could hold a conversation at, and a hard but '
          'sustainable effort. This adds up the time you spend in them each day. '
          'Most of your endurance is built here.\n\nZones are set from your '
          'resting and maximum heart rate.',
  'zones_45':
      'Heart rate zones 4 and 5 are the hard efforts: threshold work and '
          'near-maximal effort. Time here is costly, so it is usually counted in '
          'minutes and needs recovery afterwards.\n\nZones are set from your '
          'resting and maximum heart rate.',
  'zones_all':
      'All five heart rate zones together, from a gentle pulse in zone 1 to '
          'near-maximal effort in zone 5, added up for each day. The breakdown '
          'shows how that time was split.',
  'strength_time':
      'Strength activity time is the time you logged in strength sessions: '
          'workouts where you recorded sets. A day with none counts as zero '
          'once you have been using the app.',
  'volume_load':
      'Total volume load is the weight you moved: reps times load, added up over '
          'every set that has a load. Sets without a weight, such as bodyweight '
          'work, are left out, so it can read lower than the session felt.',
  'avg_hr':
      'Average heart rate is the mean of your heart rate over the day. It moves '
          'with activity, caffeine, stress, heat and hydration, and a lower '
          'average for the same routine generally goes with better fitness.\n\n'
          'Pinch the day chart to zoom into a stretch of it.',
  'calories':
      'Calories is the energy your body used, estimated from your heart rate '
          'through the day together with your age, weight, height and sex. '
          'Heart-rate estimates are best in steady activity and rougher at rest.'
          '\n\nThe hourly view shares the day\'s total across its hours in '
          'proportion to how hard your heart worked in each.',
  'recovery':
      'Recovery says how ready your body is to take on strain today. It is built '
          'each morning from your overnight heart rate variability, resting heart '
          'rate, respiratory rate and sleep, each held against your own recent '
          'baseline. Green is 67% and above, yellow 34 to 66%, red below that.',
  'hrv':
      'Heart rate variability is how much the time between heartbeats varies. A '
          'higher number generally means your nervous system is well recovered '
          'and adaptable, but what is normal differs a lot between people, so '
          'compare it with your own baseline.\n\nIt is read overnight, when it is '
          'steadiest. Stress, alcohol, illness and hard training push it down. '
          'The day view draws each hour, and shades your sleep: only the '
          'readings taken asleep count towards the average.',
  'resting_hr':
      'Resting heart rate is the lowest level your heart settles at, measured '
          'while you sleep. It tends to fall as fitness improves and rise with '
          'illness, dehydration, alcohol, stress or too little recovery. A '
          'change of a few beats from your own baseline is worth noticing.',
  'resp_rate':
      'Respiratory rate is how many breaths you take a minute while asleep. For '
          'most healthy adults it is steady, around 12 to 20. A sustained rise '
          'above your own baseline can be an early sign of illness or heavy '
          'fatigue.',
  'sleep_perf':
      'Sleep performance compares the sleep you got with the sleep your body '
          'needed that night, capped at 100%. Your need comes from your baseline, '
          'the strain you took on, any sleep debt carried and naps.',
  'time_in_bed':
      'Time in bed is the span from when you settled to sleep to when you woke. '
          'It includes short wakeful moments, so it runs longer than the hours '
          'you actually slept.\n\nEach bar floats between your bedtime (top) and '
          'wake time (bottom), on a clock that runs from evening to morning.',
  'hvn_hours':
      'Hours vs. needed compares the hours you slept with the hours your body '
          'asked for. The green line is what you needed, the blue what you got. '
          'While the blue sits under the green you are adding to your sleep '
          'debt.',
  'hvn_pct':
      'Hours vs. needed as a percentage is the sleep you got divided by the '
          'sleep you needed. 100% means you met your need; above it you got more '
          'than you asked for, below it you fell short.',
  'consistency':
      'Sleep consistency measures how regular your bed and wake times are from '
          'night to night: 100% would be the same times every day. The dashed '
          'lines mark your usual bed and wake times.\n\nRegular timing steadies '
          'your body clock and is linked with better sleep.',
  'restorative_pct':
      'Restorative sleep is time in deep (slow-wave) sleep and REM sleep, the '
          'stages in which the body repairs itself and the brain consolidates '
          'memory and mood. This is that time as a share of the night\'s sleep.',
  'restorative_hours':
      'Restorative sleep is time in deep (slow-wave) sleep and REM sleep, the '
          'stages in which the body repairs itself and the brain consolidates '
          'memory and mood. Each column stacks deep sleep and REM; touch one to '
          'see them apart.',
  'efficiency':
      'Sleep efficiency is the share of the time you spent in bed that you were '
          'actually asleep. A few restless minutes are normal; 85% or more is '
          'generally considered good.',
  'sleep_debt':
      'Sleep debt is the accumulated gap between the sleep you needed and the '
          'sleep you got over recent nights. Under 30 to 45 minutes is optimal. '
          'Higher levels can cost energy, mood, concentration and immune '
          'strength.\n\nExtra sleep and short naps of 20 to 30 minutes help repay '
          'it, though it can take several nights.',
};

/// The card of plain explanation under a chart.
class _AboutCard extends StatelessWidget {
  final String title, body;
  const _AboutCard({required this.title, required this.body});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(S.x5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(p.ink.withValues(alpha: .035), p.card),
        borderRadius: R.rXl,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: F.head.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: S.x4),
        Text(body,
            style: F.body.copyWith(
                color: p.ink2, fontWeight: FontWeight.w500, height: 1.45)),
      ]),
    );
  }
}


/// The lab result the person entered, or null.
Vo2Lab? readVo2Lab() {
  final raw = Prefs.getString(Prefs.vo2maxLab, '');
  final i = raw.indexOf('|');
  if (i < 0) return null;
  final v = double.tryParse(raw.substring(i + 1));
  final day = raw.substring(0, i);
  if (v == null || DateTime.tryParse(day) == null) return null;
  return (day: day, value: v);
}

void saveVo2Lab(String day, double value) =>
    Prefs.setString(Prefs.vo2maxLab, '$day|$value');

void clearVo2Lab() => Prefs.setString(Prefs.vo2maxLab, '');

/// Under the VO₂ max chart: which of the three estimates the figure is, why
/// there is none when there is none, and the way to anchor it to a lab test.
class _Vo2Panel extends StatelessWidget {
  final TrendLoader loader;
  final VoidCallback onLab;
  const _Vo2Panel({required this.loader, required this.onLab});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final lab = readVo2Lab();
    return FutureBuilder<Vo2Result>(
      future: loader.vo2max(),
      builder: (c, snap) {
        final r = snap.data;
        if (r == null) return const SizedBox.shrink();
        final (title, body) = switch (r.source) {
          Vo2Source.lab => (
              'Anchored to your lab test',
              'Your result of ${lab?.value.toStringAsFixed(1)} sets the level. '
                  'The trend follows what the strap sees: your activity, your '
                  'runs and your profile.'
            ),
          Vo2Source.gps => (
              'From your outdoor runs',
              'The middle of your last few runs of 15 minutes or more: the '
                  'pace you held and what it cost your heart. It updates '
                  'weekly, and each run is good to roughly 10-15 %.'
            ),
          Vo2Source.passive => (
              'Passive estimate',
              'From your age, sex, height and weight and how much hard and '
                  'moderate heart-rate time you log each week. It is good to '
                  'about 5 mL/kg/min: follow the direction, not the decimal. '
                  'A run outdoors, or a lab test, sharpens it.'
            ),
          null => (
              'Not enough yet',
              r.why ?? 'Nothing to estimate from yet.',
            ),
        };
        return Container(
          padding: const EdgeInsets.all(S.x5),
          decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(),
                style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
            const SizedBox(height: S.x2),
            Text(body, style: F.cap.copyWith(color: p.ink2, height: 1.4)),
            if (r.source != null && r.why != null) ...[
              const SizedBox(height: S.x2),
              Text(r.why!, style: F.cap.copyWith(color: p.ink3, height: 1.4)),
            ],
            const SizedBox(height: S.x4),
            Wrap(spacing: S.x5, children: [
              TextAction(
                  lab == null ? 'Enter a lab result' : 'Change the lab result',
                  () async {
                final done = await _askLab(c, lab);
                if (done) onLab();
              }),
              if (lab != null)
                TextAction('Remove it', () {
                  clearVo2Lab();
                  onLab();
                }),
            ]),
          ]),
        );
      },
    );
  }
}

/// Asks for a gas-exchange VO₂ max and the day it was taken. True when saved.
Future<bool> _askLab(BuildContext c, Vo2Lab? current) async {
  final r = await AppSheet.show<bool>(
    c,
    title: 'Lab VO₂ max',
    child: _LabForm(current: current),
  );
  return r == true;
}

class _LabForm extends StatefulWidget {
  final Vo2Lab? current;
  const _LabForm({this.current});

  @override
  State<_LabForm> createState() => _LabFormState();
}

class _LabFormState extends State<_LabForm> {
  late String _day = widget.current?.day ?? todayLabel();
  late String _text = widget.current?.value.toStringAsFixed(1) ?? '';

  double? get _value {
    final v = double.tryParse(_text.replaceAll(',', '.'));
    // A person's VO₂ max in mL/kg/min: nothing outside 10-90 is one.
    return v != null && v >= 10 && v <= 90 ? v : null;
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
          'The result of a test with a gas-exchange mask, in mL/kg/min. It '
          'becomes the anchor: the estimate keeps its trend and takes your '
          'level.',
          style: F.body.copyWith(color: p.ink2, height: 1.4)),
      const SizedBox(height: S.x4),
      AppField(
        label: 'VO₂ max (mL/kg/min)',
        initialValue: _text,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (v) => setState(() => _text = v),
        autofocus: true,
      ),
      const SizedBox(height: S.x3),
      TextAction('Taken on $_day', () async {
        final d = await showDatePicker(
          context: c,
          initialDate: DateTime.parse(_day),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (d != null) setState(() => _day = dayLabelOf(d));
      }),
      const SizedBox(height: S.x5),
      BigButton('Save', onTap: _value == null
          ? null
          : () {
              saveVo2Lab(_day, _value!);
              Navigator.of(c).pop(true);
            }),
    ]);
  }
}
