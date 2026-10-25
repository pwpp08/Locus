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
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
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

  /// A value per hour, drawn as bars.
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
      kind: TrendKind.stacked,
      intraday: TrendIntraday.hourly),
  TrendMetric('zones_45', 'Heart rate zones 4-5', TrendGroup.strain,
      LucideIcons.heart, TrendFmt.hmm,
      unit: 'hr',
      higherBetter: true,
      weekly: true,
      kind: TrendKind.stacked,
      intraday: TrendIntraday.hourly),
  TrendMetric('zones_all', 'Heart rate zones all', TrendGroup.strain,
      LucideIcons.timer, TrendFmt.hmm,
      unit: 'hr',
      higherBetter: true,
      weekly: true,
      kind: TrendKind.stacked,
      intraday: TrendIntraday.hourly),
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
      unit: 'cal'),
  TrendMetric('vo2max', 'VO₂ max', TrendGroup.strain, LucideIcons.wind,
      TrendFmt.integer,
      higherBetter: true,
      absent: 'Locus does not estimate VO₂ max. A wrist estimate is resting '
          'heart rate with a different unit on it, so there is no honest '
          'number to show.'),
  TrendMetric('recovery', 'Recovery', TrendGroup.recovery,
      LucideIcons.batteryCharging, TrendFmt.percent,
      higherBetter: true, axisMax: 100),
  TrendMetric('hrv', 'Heart rate variability', TrendGroup.recovery,
      LucideIcons.activity, TrendFmt.integer,
      unit: 'ms',
      higherBetter: true,
      line: true,
      intraday: TrendIntraday.line),
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
      LucideIcons.sparkles, TrendFmt.percent, higherBetter: true),
  TrendMetric('restorative_hours', 'Restorative sleep (hours)',
      TrendGroup.sleep, LucideIcons.sparkles, TrendFmt.hmm,
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
          values = _perMinute((await r.getDayTimeline(day))['hr'], day);
        case 'hrv':
          hourly = false;
          values = _perMinute((await r.getDayTimeline(day))['hrv'], day);
        case 'steps':
          hourly = true;
          values = _stepsPerHour((await r.getDaySteps(day))['spans'], day);
        case 'zones_13' || 'zones_45' || 'zones_all':
          hourly = true;
          final which = switch (m.id) {
            'zones_13' => const [1, 2, 3],
            'zones_45' => const [4, 5],
            _ => const [1, 2, 3, 4, 5],
          };
          values =
              _zoneMinutesPerHour((await r.getDayStrain(day))['zone_timeline'], day, which);
        default:
          return null;
      }
      if (!values.any((v) => v != null)) return null;
      return (values: values, hourly: hourly, day: day);
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

  /// `[{t, z}]`, one entry per waking minute, as minutes spent in [which]
  /// zones per hour. An hour with no entry at all stays null.
  static List<double?> _zoneMinutesPerHour(Object? raw, String day, List<int> which) {
    final out = List<double?>.filled(24, null);
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is! Map || e['t'] is! num || e['z'] is! num) continue;
      final t = DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt() * 1000);
      if (dayLabelOf(t) != day) continue;
      out[t.hour] = (out[t.hour] ?? 0) + (which.contains((e['z'] as num).toInt()) ? 1 : 0);
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
        return _chart('sleep_debt_min');
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

  const DashboardRows({
    super.key,
    required this.ids,
    required this.daily,
    required this.today,
    this.firstDay,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final metrics = [for (final id in ids) ?trendMetricOf(id)];
    if (metrics.isEmpty) {
      return Surface(
        child: Text('No metrics on your dashboard. Tap Customize to add some.',
            style: F.body.copyWith(color: p.ink3)),
      );
    }
    return Column(children: [
      for (var i = 0; i < metrics.length; i++) ...[
        if (i > 0) const SizedBox(height: S.x3),
        _row(c, p, metrics[i]),
      ],
    ]);
  }

  Widget _row(BuildContext c, P p, TrendMetric m) {
    final h = trendHeadline(m, daily[m.id] ?? const {},
        today: today, firstDay: firstDay);
    final dir = _directionColor(m, h.value, h.against);
    final title = m.weekly ? '${m.title} (weekly)' : m.title;
    return Surface(
      onTap: () => onOpen(m.id),
      semanticLabel: '$title. ${trendFormat(m, h.value)}'
          '${h.against == null ? '' : ', against ${trendFormat(m, h.against)}'}',
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x4),
      child: Row(children: [
        Icon(m.icon, size: I.md, color: p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child: Text(title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: F.caps.copyWith(color: p.ink, letterSpacing: .8)),
        ),
        const SizedBox(width: S.x2),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(m.absent != null ? '--' : trendFormat(m, h.value),
                style: F.n24.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
            const SizedBox(width: S.x1),
            SizedBox(
              width: I.md,
              child: dir == null
                  ? null
                  : Icon(
                      h.value! > h.against!
                          ? Icons.arrow_drop_up
                          : Icons.arrow_drop_down,
                      size: I.md,
                      color: dir,
                    ),
            ),
          ]),
          if (h.against != null && m.absent == null)
            Padding(
              padding: const EdgeInsets.only(right: I.md + S.x1),
              child: Text(trendFormat(m, h.against),
                  style: F.cap.copyWith(color: p.ink3, fontWeight: FontWeight.w600)),
            ),
        ]),
      ]),
    );
  }
}

enum TrendRange { day, week, month, sixMonths }

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
  if (range != TrendRange.sixMonths) {
    return [
      for (var i = range.days - 1; i >= 0; i--)
        (from: shiftDay(end, -i), to: shiftDay(end, -i), v: on(shiftDay(end, -i))),
    ];
  }
  return [
    for (var w = 25; w >= 0; w--)
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

/// What a Day view is summarised by: the last point of a running total, the sum
/// of an hourly count, or the mean of a series. Null when nothing was recorded.
double? trendDayValue(TrendMetric m, TrendIntra i) {
  final vs = [for (final v in i.values) ?v];
  if (vs.isEmpty) return null;
  if (m.cumulative) return vs.last;
  if (i.hourly) return vs.fold<double>(0, (a, b) => a + b);
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

  TrendLoader? _loader;
  Map<String, double>? _daily;
  String? _firstDay;
  TrendIntra? _intra;
  String? _intraKey;

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
    if (!mounted || want != _intraWant) return;
    setState(() {
      _intra = r;
      _intraKey = want;
      // Nothing to draw for today and the user has not chosen: the week is
      // the useful default, not an empty chart.
      if (_auto && r == null) {
        _range = TrendRange.week;
        _back = 0;
      }
    });
  }

  void _pick(TrendMetric m) {
    setState(() {
      _m = m;
      _picking = false;
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
      _selected = null;
      _auto = false;
    });
    if (r == TrendRange.day) _loadIntra();
  }

  void _stepBack(int by) {
    setState(() {
      _back += by;
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
    return switch (_range) {
      TrendRange.week => sum,
      TrendRange.month => sum / vs.length * 7,
      _ => sum / vs.length,
    };
  }

  static const _zoneColours = [
    C.refZone1,
    C.refZone2,
    C.refZone3,
    C.refZone4,
    C.refZone5,
  ];

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
    final end = shiftDay(_today, -_back * _range.days);
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
        prev = _weeklyTotal(m, daily, shiftDay(end, -_range.days));
      } else {
        prev = trendAverage(trendBars(m, daily, _range,
            shiftDay(end, -_range.days), firstDay: _firstDay));
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
    final dayValue = intra == null ? null : trendDayValue(m, intra);

    final sel = !isDay && _selected != null && _selected! < bars.length
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
        caption = m.cumulative || (intra?.hourly ?? false) ? 'Total' : 'Average';
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

    final chip = !isDay && sel == null && avg != null && prev != null
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
        final a = la(k, end), b = la(k, shiftDay(end, -_range.days));
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
        m.id == 'restorative_hours' &&
        sel != null &&
        layerBars != null) {
      // Touching a night splits the figure into its two kinds of sleep.
      final i = _selected!;
      readout = _MultiReadout(
        caption: _caption(sel, l),
        rows: [
          (value: trendFormat(m, layerBars[1][i].v), unit: 'hr', name: 'SWS (Deep)', color: C.trendSws, chip: null),
          (value: trendFormat(m, layerBars[0][i].v), unit: 'hr', name: 'REM', color: C.trendRem, chip: null),
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
        child: ListView(padding: pad, children: [
          const NavBar('Trend View'),
          const SizedBox(height: S.x3),
          _MetricPill(
            m: m,
            open: _picking,
            onTap: () => setState(() => _picking = !_picking),
          ),
          if (_picking) ...[
            const SizedBox(height: S.x2),
            _Picker(current: m, onPick: _pick),
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
                        color: p.ink, fontWeight: FontWeight.w700, letterSpacing: .7),
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
              if (!isDay && m.id == 'restorative_hours')
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
              if (m.id == 'strain' && !isDay && _daily != null) ...[
                const SizedBox(height: S.x8),
                _StrainBreakdown(bars: bars),
              ],
              if (!isDay &&
                  layerBars != null &&
                  m.kind == TrendKind.stacked &&
                  m.id != 'restorative_hours') ...[
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
                  title: switch (_range) {
                    TrendRange.week => 'WEEKLY TOTAL',
                    TrendRange.month => 'MONTHLY TOTAL',
                    _ => '6 MONTH TOTAL',
                  },
                  names: [
                    for (var k = 0; k < layerBars.length; k++)
                      'Zone ${m.id == 'zones_45' ? k + 4 : k + 1}',
                  ],
                  colours: _layerColours(m),
                  minutes: [
                    for (final lb in layerBars)
                      lb.fold<double>(0, (a, b) => a + (b.v ?? 0)),
                  ],
                ),
              ],
            ],
          ],
        ]),
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
                  style: F.caps.copyWith(color: p.ink, letterSpacing: .7)),
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

  /// A day's own shape: a line per minute, or bars per hour.
  Widget _dayChart(TrendMetric m, TrendIntra intra) {
    final vs = [for (final v in intra.values) ?v];
    final axis = _axisFor(m, vs, line: !intra.hourly);
    if (intra.hourly) {
      return ScrubColumns(
        values: intra.values,
        xLabels: [for (var h = 0; h < 24; h++) h % 6 == 0 ? '$h' : ''],
        lo: axis.lo,
        hi: axis.hi,
        ticks: axis.ticks,
        tickText: (t) => _tickText(m, t),
        color: _colorOf(m),
        height: S.x16 * 4 + S.x8,
        onScrub: (i) => setState(() => _selected = i),
      );
    }
    const marks = {0: '00:00', 360: '06:00', 720: '12:00', 1080: '18:00', 1439: '24:00'};
    final mean = m.cumulative ? null : trendDayValue(m, intra);
    return ScrubLine(
      values: intra.values,
      xLabels: [for (var i = 0; i < 1440; i++) marks[i] ?? ''],
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
      onScrub: (i) => setState(() => _selected = i),
    );
  }

  Widget _chartFor(TrendMetric m, List<TrendBar> bars, List<List<TrendBar>>? layerBars,
      double? avg, ({double lo, double hi})? band, AppLocalizations? l) {
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
      color: color,
      colorOf: m.id == 'recovery' ? (i, v) => recoveryColor(v) : null,
      height: S.x16 * 4 + S.x8,
      onScrub: (i) => setState(() => _selected = i),
    );
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

  /// Each night as a bar floating from bed to wake, on a clock.
  Widget _floatingChart(TrendMetric m, List<TrendBar> bars, AppLocalizations? l) {
    final spans = _spans ?? const <String, ({double bed, double wake})>{};
    final n = bars.length;
    ({double from, double to})? rangeOf(TrendBar b) {
      // A window of days (six months is a week a bar) is the mean of its nights.
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
    if (m.id == 'consistency' && _range != TrendRange.sixMonths) {
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
    // The axis is a clock on a four-hour grid from 19:00, grown to hold every
    // night: 19:00 at the top, 11:00 at the bottom, as the week usually sits.
    const grid = 420.0, step = 240.0;
    var lo = grid, hi = grid + step * 4;
    for (final r in ranges) {
      if (r == null) continue;
      while (r.from < lo + 30) {
        lo -= step;
      }
      while (r.to > hi - 30) {
        hi += step;
      }
    }
    final week = _range == TrendRange.week;
    final consistency = m.id == 'consistency';
    return ScrubRanges(
      ranges: ranges,
      xLabels: [for (var i = 0; i < n; i++) _xLabel(i, bars, l)],
      lo: lo,
      hi: hi,
      ticks: [for (var t = lo; t <= hi + 1; t += step) t],
      tickText: _clockAfterNoon,
      timeText: _clockAfterNoon,
      color: C.dialSleep,
      emphasis: consistency ? n - 1 : null,
      labelAll: !consistency && week,
      usual: usual,
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
      if (dayValue == null) return 'No ${m.title.toLowerCase()} recorded for this day.';
      final when = _dayShown == _today ? 'today' : 'on ${_dayName(_dayShown, l)}';
      final title = m.title.toLowerCase();
      final agg = m.cumulative || title.startsWith('average')
          ? ''
          : (_intra?.hourly ?? false)
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
      return 'Your total ${_total(m)} this week is $shown. Keep wearing your '
          'band to see how this changes over time.';
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
                          color: i == index ? p.ink : p.ink3, letterSpacing: .3)),
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
            style: F.over.copyWith(color: p.ink2, letterSpacing: .7)),
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
            style: F.over.copyWith(color: p.ink2, letterSpacing: .7)),
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
            style: F.caps.copyWith(color: p.ink, letterSpacing: .7)),
        TextSpan(
            text: '($title)',
            style: F.caps.copyWith(color: p.ink3, letterSpacing: .7)),
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
                    color: p.ink, fontWeight: FontWeight.w700, letterSpacing: .9)),
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
            style: F.caps.copyWith(color: p.ink, letterSpacing: .8)),
        TextSpan(
            text: '(DAYS)',
            style: F.caps.copyWith(color: p.ink3, letterSpacing: .8)),
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
  const _Picker({required this.current, required this.onPick});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final g in TrendGroup.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x2),
            child: Row(children: [
              Text(trendGroupName(g).toUpperCase(),
                  style: F.over.copyWith(
                      color: p.ink2, fontWeight: FontWeight.w700, letterSpacing: .8)),
              const SizedBox(width: S.x3),
              Expanded(child: Container(height: S.half / 2, color: p.line)),
            ]),
          ),
          for (final m in kTrendCatalogue)
            if (m.group == g)
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
                          style: F.caps.copyWith(color: p.ink, letterSpacing: .8)),
                    ),
                  ]),
                ),
              ),
        ],
      ]),
    );
  }
}
