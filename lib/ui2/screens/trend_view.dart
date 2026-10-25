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

/// One metric Trend View can chart.
class TrendMetric {
  final String id;
  final String title;
  final TrendGroup group;
  final IconData icon;
  final TrendFmt fmt;

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

  /// Non-null: this app does not produce the metric, and this is why.
  final String? absent;

  const TrendMetric(
    this.id,
    this.title,
    this.group,
    this.icon,
    this.fmt, {
    this.higherBetter,
    this.weekly = false,
    this.zeroFill = false,
    this.signed = false,
    this.axisMax,
    this.absent,
  });
}

/// Every metric, in the order the picker lists them.
const kTrendCatalogue = <TrendMetric>[
  TrendMetric('strain', 'Day strain', TrendGroup.strain, LucideIcons.dumbbell,
      TrendFmt.decimal1, axisMax: 21),
  TrendMetric('steps', 'Steps (beta)', TrendGroup.strain,
      LucideIcons.footprints, TrendFmt.grouped, higherBetter: true),
  TrendMetric('zones_13', 'Heart rate zones 1-3', TrendGroup.strain,
      LucideIcons.heartPulse, TrendFmt.hmm, higherBetter: true, weekly: true),
  TrendMetric('zones_45', 'Heart rate zones 4-5', TrendGroup.strain,
      LucideIcons.heart, TrendFmt.hmm, higherBetter: true, weekly: true),
  TrendMetric('zones_all', 'Heart rate zones all', TrendGroup.strain,
      LucideIcons.timer, TrendFmt.hmm, higherBetter: true, weekly: true),
  TrendMetric('strength_time', 'Strength activity time', TrendGroup.strain,
      LucideIcons.dumbbell, TrendFmt.hmm,
      higherBetter: true, weekly: true, zeroFill: true),
  TrendMetric('volume_load', 'Total volume load', TrendGroup.strain,
      LucideIcons.weight, TrendFmt.grouped,
      higherBetter: true, weekly: true, zeroFill: true),
  TrendMetric('avg_hr', 'Average heart rate', TrendGroup.strain,
      LucideIcons.heartPulse, TrendFmt.integer),
  TrendMetric('calories', 'Calories', TrendGroup.strain, LucideIcons.flame,
      TrendFmt.grouped),
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
      LucideIcons.activity, TrendFmt.integer, higherBetter: true),
  TrendMetric('resting_hr', 'Resting heart rate', TrendGroup.recovery,
      LucideIcons.heartHandshake, TrendFmt.integer, higherBetter: false),
  TrendMetric('resp_rate', 'Respiratory rate', TrendGroup.recovery,
      LucideIcons.wind, TrendFmt.decimal1),
  TrendMetric('sleep_perf', 'Sleep performance', TrendGroup.sleep,
      LucideIcons.moon, TrendFmt.percent, higherBetter: true, axisMax: 100),
  TrendMetric('time_in_bed', 'Time in bed', TrendGroup.sleep,
      LucideIcons.bedDouble, TrendFmt.hmm),
  TrendMetric('hvn_hours', 'Hours vs. needed (hours)', TrendGroup.sleep,
      LucideIcons.clock3, TrendFmt.hmm, higherBetter: true, signed: true),
  TrendMetric('hvn_pct', 'Hours vs. needed (%)', TrendGroup.sleep,
      LucideIcons.clock3, TrendFmt.percent, higherBetter: true),
  TrendMetric('consistency', 'Sleep consistency', TrendGroup.sleep,
      LucideIcons.repeat, TrendFmt.percent, higherBetter: true, axisMax: 100),
  TrendMetric('restorative_pct', 'Restorative sleep (%)', TrendGroup.sleep,
      LucideIcons.sparkles, TrendFmt.percent, higherBetter: true),
  TrendMetric('restorative_hours', 'Restorative sleep (hours)',
      TrendGroup.sleep, LucideIcons.sparkles, TrendFmt.hmm, higherBetter: true),
  TrendMetric('efficiency', 'Sleep efficiency', TrendGroup.sleep,
      LucideIcons.gauge, TrendFmt.percent, higherBetter: true, axisMax: 100),
  TrendMetric('sleep_debt', 'Sleep debt', TrendGroup.sleep,
      LucideIcons.hourglass, TrendFmt.hmm, higherBetter: false, signed: true),
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
              style: F.caps.copyWith(color: p.ink, letterSpacing: 1.4)),
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

enum TrendRange { week, month, sixMonths }

extension on TrendRange {
  int get days => switch (this) {
        TrendRange.week => 7,
        TrendRange.month => 30,
        TrendRange.sixMonths => 182,
      };
  String get word => switch (this) {
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


class TrendViewScreen extends StatefulWidget {
  final String initial;

  /// Injected by tests; production builds its own.
  final TrendLoader? loader;
  final String? today;

  const TrendViewScreen(
      {super.key, required this.initial, this.loader, this.today});

  @override
  State<TrendViewScreen> createState() => _TrendViewScreenState();
}

class _TrendViewScreenState extends State<TrendViewScreen> {
  late TrendMetric _m = trendMetricOf(widget.initial) ?? kTrendCatalogue.first;
  TrendRange _range = TrendRange.month;
  int _back = 0; // windows behind the current one

  /// The bar under a finger. Null at rest, so the readout shows the average.
  int? _selected;
  bool _picking = false;

  TrendLoader? _loader;
  Map<String, double>? _daily;
  String? _firstDay;

  String get _today => widget.today ?? todayLabel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final loader = _loader ??= widget.loader ?? TrendLoader(repoOf(context));
    final m = _m;
    final daily = await loader.daily(m);
    final first = await loader.firstDay();
    if (!mounted || m != _m) return;
    setState(() {
      _daily = daily;
      _firstDay = first;
    });
  }

  void _pick(TrendMetric m) {
    setState(() {
      _m = m;
      _picking = false;
      _daily = null;
      _selected = null;
    });
    _load();
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

  /// The readout's caption for a bar: its date, or its week's dates.
  String _caption(TrendBar b, AppLocalizations? l) => b.from == b.to
      ? _longDate(b.from, l)
      : '${_shortDate(b.from, l)} - ${_longDate(b.to, l)}';

  /// The axis: a round step, from zero (or the lowest value) to the highest
  /// (or the metric's own ceiling).
  ({double lo, double hi, List<double> ticks}) _axis(
      TrendMetric m, List<TrendBar> bars) {
    final vs = [for (final b in bars) ?b.v];
    var lo = math.min(0.0, vs.isEmpty ? 0.0 : vs.reduce(math.min));
    var hi = m.axisMax ?? (vs.isEmpty ? 1.0 : vs.reduce(math.max));
    // Minutes step in whole half-hours, everything else on a round number.
    double stepFor(double span) => m.fmt == TrendFmt.hmm
        ? math.max(30.0, (_niceStep(span) / 30).ceil() * 30.0)
        : _niceStep(span);
    final step = stepFor(hi - lo);
    hi = (hi / step).ceil() * step;
    if (lo < 0) lo = (lo / step).floor() * step;
    if (hi <= lo) hi = lo + step;
    return (
      lo: lo,
      hi: hi,
      ticks: [for (var t = lo; t <= hi + step / 1000; t += step) t],
    );
  }

  String _tickText(TrendMetric m, double t) => m.fmt == TrendFmt.hmm
      ? '${(t / 60).round()}h'
      : m.fmt == TrendFmt.percent
          ? '${t.round()}'
          : (t >= 1000
              ? '${(t / 1000).toStringAsFixed(t % 1000 == 0 ? 0 : 1)}k'
              : '${t.round()}');

  /// The label under each bar. A week names its days, a month marks every
  /// seventh day counting back from today, six months names each new month.
  String _xLabel(int i, List<TrendBar> bars, AppLocalizations? l) {
    final d = _dateOf(bars[i].to);
    return switch (_range) {
      TrendRange.week => weekdayShortName(d.weekday, l),
      TrendRange.month => (bars.length - 1 - i) % 7 == 0
          ? '${monthShortName(d.month, l)}\n${d.day}'
          : '',
      TrendRange.sixMonths => i == 0 ||
              _dateOf(bars[i].from).month != _dateOf(bars[i - 1].from).month
          ? monthShortName(_dateOf(bars[i].from).month, l)
          : '',
    };
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final m = _m;
    final daily = _daily ?? const <String, double>{};
    final end = shiftDay(_today, -_back * _range.days);
    final bars = trendBars(m, daily, _range, end, firstDay: _firstDay);
    final prev = trendAverage(trendBars(
        m, daily, _range, shiftDay(end, -_range.days),
        firstDay: _firstDay));
    final avg = trendAverage(
        trendBars(m, daily, _range, end, firstDay: _firstDay, skip: _today));
    final includesToday = _back == 0;
    final sel = _selected != null && _selected! < bars.length
        ? bars[_selected!]
        : null;

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
                Expanded(
                  child: ScrubReadout(
                    caption: sel != null
                        ? _caption(sel, l)
                        : _range == TrendRange.sixMonths && m.weekly
                            ? 'Weekly average'
                            : 'Average',
                    value: trendFormat(m, sel != null ? sel.v : avg),
                    under: sel == null &&
                            avg != null &&
                            prev != null &&
                            _range != TrendRange.month
                        ? Padding(
                            padding: const EdgeInsets.only(top: S.x2),
                            child: _DeltaChip(
                                m: m, avg: avg, prev: prev, range: _range),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: S.x3),
                SizedBox(
                  width: S.x16 * 2.75,
                  child: SubTabs(const ['W', 'M', '6M'], _range.index,
                      (i) => setState(() {
                            _range = TrendRange.values[i];
                            _back = 0;
                            _selected = null;
                          })),
                ),
              ]),
              const SizedBox(height: S.x3),
              Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _Step(LucideIcons.chevronLeft, 'Earlier',
                      () => setState(() {
                            _back++;
                            _selected = null;
                          })),
                  Text(
                    '${_shortDate(bars.first.from, l)} - '
                    '${_shortDate(end, l)}, ${(_dateOf(end).year % 100).toString().padLeft(2, '0')}'
                        .toUpperCase(),
                    style: F.over.copyWith(
                        color: p.ink, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                  ),
                  _Step(
                      LucideIcons.chevronRight,
                      'Later',
                      _back == 0
                          ? null
                          : () => setState(() {
                                _back--;
                                _selected = null;
                              })),
                ]),
              ),
              const SizedBox(height: S.x4),
              Text(_sentence(m, avg, prev),
                  style: F.head.copyWith(color: p.ink, height: 1.3)),
              const SizedBox(height: S.x6),
              if (_daily == null)
                const SizedBox(
                    height: S.x16 * 4,
                    child: Center(child: CircularProgressIndicator()))
              else
                _chart(m, bars, avg, l, highlight: includesToday ? bars.length - 1 : null),
              if (includesToday) ...[
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
              if (m.id == 'strain' && _daily != null) ...[
                const SizedBox(height: S.x8),
                _StrainBreakdown(bars: bars),
              ],
            ],
          ],
        ]),
      ),
    );
  }

  Widget _chart(TrendMetric m, List<TrendBar> bars, double? avg,
      AppLocalizations? l, {int? highlight}) {
    final axis = _axis(m, bars);
    final color = switch (m.group) {
      TrendGroup.strain => C.dialStrain,
      TrendGroup.recovery => C.optimal,
      TrendGroup.sleep => C.dialSleep,
    };
    return ScrubColumns(
      values: [for (final b in bars) b.v],
      xLabels: [for (var i = 0; i < bars.length; i++) _xLabel(i, bars, l)],
      // A week's values sit over its bars; a month is too many to label.
      valueLabels: _range == TrendRange.week
          ? [for (final b in bars) trendFormat(m, b.v)]
          : const [],
      lo: axis.lo,
      hi: axis.hi,
      ticks: axis.ticks,
      tickText: (t) => _tickText(m, t),
      avg: avg,
      color: color,
      colorOf: m.id == 'recovery'
          ? (i, v) => recoveryColor(v)
          : null,
      highlight: highlight,
      height: S.x16 * 4 + S.x8,
      onScrub: (i) => setState(() => _selected = i),
    );
  }

  String _sentence(TrendMetric m, double? avg, double? prev) {
    final word = _range.word;
    if (avg == null) return 'No ${m.title} recorded this $word.';
    final shown = trendFormat(m, avg);
    if (_range == TrendRange.week && prev != null) {
      final rel = trendFormat(m, avg) == trendFormat(m, prev)
          ? 'the same as'
          : avg > prev
              ? 'above'
              : 'below';
      return 'During this 7-day period, your average ${m.title} ($shown) was '
          '$rel your average at the time (${trendFormat(m, prev)}).';
    }
    return 'Your average ${m.title} this $word is $shown. Keep wearing your '
        'band to see how this changes over time.';
  }
}

/// Nearest round step that cuts [span] into about four.
double _niceStep(double span) {
  if (span <= 0) return 1;
  final raw = span / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final f in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (raw <= f * mag) return f * mag;
  }
  return 10 * mag;
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
                    color: p.ink, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
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
            style: F.caps.copyWith(color: p.ink, letterSpacing: 1.4)),
        TextSpan(
            text: '(DAYS)',
            style: F.caps.copyWith(color: p.ink3, letterSpacing: 1.4)),
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

class _DeltaChip extends StatelessWidget {
  final TrendMetric m;
  final double avg, prev;
  final TrendRange range;
  const _DeltaChip(
      {required this.m, required this.avg, required this.prev, required this.range});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final diff = avg - prev;
    final past = switch (range) {
      TrendRange.week => 'prior week',
      TrendRange.month => 'prior month',
      TrendRange.sixMonths => 'prior 6 months',
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (trendFormat(m, diff.abs()) != trendFormat(m, 0)) ...[
        Icon(diff > 0 ? LucideIcons.arrowUp : LucideIcons.arrowDown,
            size: I.sm, color: diff > 0 ? C.optimal : C.amber),
        const SizedBox(width: S.half),
      ],
      Flexible(
        child: Text('${trendFormat(m, diff.abs())} vs. $past',
            style: F.cap.copyWith(color: p.ink2, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
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
                      color: p.ink2, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
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
                          style: F.caps.copyWith(color: p.ink, letterSpacing: 1.4)),
                    ),
                  ]),
                ),
              ),
        ],
      ]),
    );
  }
}
