// DAY STRAIN — when the day's effort actually happened.
//
// `getDayStrain` was fully implemented and called by nothing. Everything drawn
// here was already computed and persisted: `series.strain_curve` (one point per
// WAKE MINUTE), the zone minutes, and `max_hr_used` — the ceiling the pipeline
// actually integrated against, printed rather than laundered into the score.
//
// The CURVE leads. The 0–21 is a summary of the curve, not the other way round:
// two days can land on the same number with completely different shapes, and
// the shape is the thing you can act on.
//
// What this screen deliberately does NOT draw:
//   * CTL/ATL/TSB. That is a fortnight of history and it already has a card one
//     tap away on the Workout tab. A day screen repeating it is noise.
//   * the resting heart rate TRIMP was anchored on. `getDayHeart`'s
//     `resting_hr` is now that same nocturnal number (`scalars.rhr` no longer
//     falls back to daytime HR), so it COULD be printed — it just does not earn
//     a line on a day screen whose subject is the curve. Naming the input in a
//     sentence is enough.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/date_text.dart';
import '../../models/metric.dart' show whyFromNote;
import '../screens/home_screen.dart'
    show monthShortName, repoOf, weekdayShortName;
import '../screens/metric_detail.dart' show dayNavRow, detailScaffold;
import '../screens/trend_view.dart';
import '../../theme/theme_switcher.dart' show themedRoute;
import '../screens/workout_detail.dart' show WorkoutDetailScreen;
import '../ui2.dart';
import 'catalogue.dart' show activityByName, zonesWhy;
import 'zones.dart' show ZonesDetail;

/// Below this the day is not comparable to a full one and the screen says so.
/// Wear coverage is a percentage of the whole day, so a normal night off the
/// wrist already costs ~30 points — this is "most of the waking day", not
/// "nearly all of it".
const _lowCoveragePct = 60;

/// The trace, the score, and everything needed to say what the score is made
/// of. Every field is nullable: a day the band never saw renders its absence.
class DayStrainData {
  /// The local day the curve actually came from. `getDayStrain` falls back to
  /// the last settled bundle while today is still deriving, so this is read off
  /// the curve's own timestamps rather than off the label we asked for.
  final DateTime? day;

  /// One slot per minute of [day], null where nothing was recorded. A compacted
  /// curve under a 00:00–24:00 axis draws a sync gap as though it were measured.
  final List<double?> curve;

  final double? strain;

  /// Five zone minutes, or null when the day banked no split.
  final List<int>? zoneMin;

  /// The HR ceiling the pipeline integrated against — `max_hr_used`, the same
  /// number the maths saw.
  final num? maxHrUsed;

  /// TS-04 — which anchors THIS day's zone bars were binned on: 'karvonen'
  /// (observed ceiling + measured resting HR), 'observed' (measured ceiling
  /// only) or 'tanaka' (the age estimate). The bar's footnote states what the
  /// bar IS, rather than what it usually is.
  final String? zoneSource;
  final num? zoneMaxHr;

  /// The five lower zone edges, in bpm, of the set this day was binned with.
  final List<num>? zoneLowerBpm;

  final int? peakHr, wornMin, coveragePct;

  /// WHY the day has no strain, as the bundle said it — never a sentence
  /// written on this screen. Null means nothing came back with the absence, and
  /// the screen then says exactly that.
  final String? note;

  const DayStrainData({
    this.day,
    this.curve = const [],
    this.strain,
    this.zoneMin,
    this.maxHrUsed,
    this.zoneSource,
    this.zoneMaxHr,
    this.zoneLowerBpm,
    this.peakHr,
    this.wornMin,
    this.coveragePct,
    this.note,
  });

  bool get hasCurve => curve.any((v) => v != null);

  static Future<DayStrainData> load(LocalRepository repo, {String? forDay}) async {
    final asked = forDay ?? todayLabel();
    final s = await repo.getDayStrain(asked);
    if (s.isEmpty) return const DayStrainData();

    final pts = <(int, double)>[
      for (final e in (s['curve'] as List? ?? const []))
        if (e is Map && e['t'] is num && e['v'] is num)
          ((e['t'] as num).toInt(), (e['v'] as num).toDouble()),
    ];

    DateTime? day;
    var grid = const <double?>[];
    if (pts.isNotEmpty) {
      final first =
          DateTime.fromMillisecondsSinceEpoch(pts.first.$1 * 1000);
      day = DateTime(first.year, first.month, first.day);
      final dayStart = day.millisecondsSinceEpoch ~/ 1000;
      final out = List<double?>.filled(1440, null);
      for (final p in pts) {
        final i = (p.$1 - dayStart) ~/ 60;
        if (i >= 0 && i < 1440) out[i] = p.$2;
      }
      grid = out;
    }

    // Wear for THE DAY THE CURVE CAME FROM, not the day we asked for — both
    // reads fall back the same way, so asking for the resolved label is what
    // keeps the coverage figure and the trace describing one day.
    //
    // Read even when there is NO curve, which it did not used to be. Whether
    // the band saw the day is what decides if "wear the band through the day"
    // is an instruction or an insult, and a day with no strain is exactly the
    // day that question gets asked on.
    Map<String, dynamic> wear = const {};
    try {
      wear = await repo.getDayWear(day == null ? asked : dayLabelOf(day));
    } catch (_) {
      wear = const {};
    }

    final z = s['zones'];
    final zoneMin = z is Map &&
            [for (var i = 1; i <= 5; i++) z['z$i']].every((v) => v is num)
        ? [for (var i = 1; i <= 5; i++) (z['z$i'] as num).toInt()]
        : null;

    final hr = s['hr'];
    return DayStrainData(
      day: day,
      curve: grid,
      strain: (s['strain'] as num?)?.toDouble(),
      zoneMin: zoneMin,
      maxHrUsed: s['max_hr_used'] as num?,
      zoneSource: s['zone_source'] as String?,
      zoneMaxHr: s['zone_max_hr'] as num?,
      zoneLowerBpm: switch (s['zone_lower_bpm']) {
        final List e when e.length == 5 && e.every((v) => v is num) =>
          e.cast<num>(),
        _ => null,
      },
      peakHr: hr is Map ? (hr['max'] as num?)?.toInt() : null,
      wornMin: (wear['worn_min'] as num?)?.toInt(),
      coveragePct: (wear['coverage_pct'] as num?)?.toInt(),
      // The headline absence's reason, at the top level of the payload — the
      // same string as `absent.strain`.
      note: s['note'] as String?,
    );
  }
}



class DayStrainDetail extends StatefulWidget {
  /// Preloaded, for goldens. Null means read the repo on open.
  final DayStrainData? data;

  /// Injected by tests; production reads the repo.
  final TrendLoader? loader;

  /// The day to open; null is today.
  final String? day;

  const DayStrainDetail({super.key, this.data, this.loader, this.day});

  @override
  State<DayStrainDetail> createState() => _DayStrainDetailState();
}

/// The metrics this screen compares, the zone minutes behind its stacked
/// cards, and the day's saved sessions. Read once per open.
class _StrainTrends {
  /// Metric id → that metric's value per day.
  final Map<String, Map<String, double>> daily;

  /// Zone minutes per day: zones 1-3 and zones 4-5, one entry per zone.
  final Map<String, List<double>> zones13, zones45;
  final List<Map<String, dynamic>> sessions;
  final String? firstDay;

  const _StrainTrends({
    this.daily = const {},
    this.zones13 = const {},
    this.zones45 = const {},
    this.sessions = const [],
    this.firstDay,
  });

  static const ids = [
    'strain',
    'steps',
    'calories',
    'zones_13',
    'zones_45',
    'strength_time',
  ];

  static Future<_StrainTrends> load(
      TrendLoader loader, LocalRepository? repo, String today) async {
    final daily = <String, Map<String, double>>{
      for (final id in ids) id: await loader.daily(trendMetricOf(id)!),
    };
    return _StrainTrends(
      daily: daily,
      zones13: await loader.zoneStack(const [1, 2, 3]),
      zones45: await loader.zoneStack(const [4, 5]),
      sessions: repo == null ? const [] : await _sessionsOn(repo, today),
      firstDay: await loader.firstDay(),
    );
  }

  static Future<List<Map<String, dynamic>>> _sessionsOn(
      LocalRepository repo, String day) async {
    final t = DateTime.parse(day);
    final from = DateTime(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 1000;
    final to = DateTime(t.year, t.month, t.day + 1).millisecondsSinceEpoch ~/
        1000 -
        1;
    try {
      final rows = await repo.getSessions(
          from: from, to: to, includeDetected: false);
      return [
        for (final r in rows)
          if (r['start_ts'] is num) r,
      ]..sort((a, b) =>
          (a['start_ts'] as num).compareTo(b['start_ts'] as num));
    } catch (_) {
      return const [];
    }
  }
}

class _DayStrainDetailState extends State<DayStrainDetail> {
  DayStrainData? _d;
  bool _loading = true;
  _StrainTrends _t = const _StrainTrends();
  late String? _day = widget.day;
  List<String> _days = const [];

  @override
  void initState() {
    super.initState();
    _d = widget.data;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _goDay(String day) {
    setState(() {
      _day = day;
      _loading = true;
    });
    _load();
  }

  Future<void> _load() async {
    final repo = _repoOrNull();
    if (repo == null && widget.loader == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final want = _day;
    try {
      if (repo != null) {
        try {
          _days = await repo.availableDays();
        } catch (_) {}
      }
      final d = widget.data ??
          (repo == null
              ? const DayStrainData()
              : await DayStrainData.load(repo, forDay: want));
      final today = dayLabelOf(d.day ?? DateTime.tryParse(want ?? '') ?? DateTime.now());
      final t = await _StrainTrends.load(
          widget.loader ?? TrendLoader(repo), repo, today);
      if (mounted && want == _day) {
        setState(() {
          _d = d;
          _t = t;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The repo, or null in a test that never provided one.
  LocalRepository? _repoOrNull() {
    try {
      return repoOf(context);
    } catch (_) {
      return null;
    }
  }

  // ── the numbers the screen compares ──────────────────────────────────────
  /// The day's value for [id], zero-filled where the metric says so.
  double? _valueOn(String id, String today) {
    final m = trendMetricOf(id)!;
    return trendBars(m, _t.daily[id] ?? const {}, TrendRange.week, today,
            firstDay: _t.firstDay)
        .last
        .v;
  }

  /// The mean of the 30 days before [today]. Today is left out, as on Trend
  /// View: a day still in progress is not part of a baseline.
  double? _avg30(String id, String today) => trendAverage(trendBars(
        trendMetricOf(id)!,
        _t.daily[id] ?? const {},
        TrendRange.month,
        shiftDay(today, -1),
        firstDay: _t.firstDay,
      ));

  // ── the day ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = _d ?? const DayStrainData();
    final shown = d.day ?? DateTime.now();
    final today = dayLabelOf(shown);
    // The pager under the bar names the day, as on Sleep and Recovery; with
    // no days on record to page through, the bar still dates the screen.
    final title = _days.isEmpty
        ? localizedDate(shown, l?.localeName ?? 'en', pattern: 'EEE, MMM d')
        : 'Strain';

    return detailScaffold(
      c,
      title,
      [
        ...dayNavRow(_day, _days, _goDay),
        if (_loading && _d == null) ...[
          const SizedBox(height: S.x8),
          const Center(child: CircularProgressIndicator()),
        ] else ...[
          _ring(p, d),
          const SizedBox(height: S.x4),
          _statsPanel(p, today),
          const SizedBox(height: S.x4),
          _comparisonLegend(p, shown, l),
          const SizedBox(height: S.x6),
          ..._absence(p, l, d),
          _band(d.strain),
          const SizedBox(height: S.x8),
          _todaysActivities(p, l),
          const SizedBox(height: S.x8),
          _weeklyTrends(p, l, today),
          const SizedBox(height: S.x8),
          ..._throughTheDay(p, l, d),
          ..._zones(p, l, d),
          Section(l?.dayStrainInputsSection ?? 'What this is made of',
              _inputs(p, l, d)),
        ],
      ],
    );
  }

  // ── the ring: the day's strain against the 0–21 scale ───────────────────
  Widget _ring(P p, DayStrainData d) {
    final s = d.strain;
    final baseline = _avg30('strain', dayLabelOf(d.day ?? DateTime.now()));
    return LayoutBuilder(builder: (c, box) {
      final side = math.min(box.maxWidth * .84, S.x16 * 5.4);
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: Size.square(side),
              painter: _StrainRingPainter(
                fraction: s == null ? null : (s / 21).clamp(0.0, 1.0),
                baselineFraction:
                    baseline == null ? null : (baseline / 21).clamp(0.0, 1.0),
                track: p.track,
                arc: C.dialStrain,
                tick: C.white,
              ),
            ),
            // The whole block scales to fit the circle, so a large text size
            // shrinks it rather than spilling out of the ring.
            Padding(
              padding: const EdgeInsets.all(S.x8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('LOCUS', style: F.wordmark.copyWith(color: p.ink3)),
                  const SizedBox(height: S.x1),
                  Text(s == null ? '--' : s.toStringAsFixed(1),
                      style: F.n80.copyWith(
                          color: p.ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: S.x1),
                  Text('STRAIN',
                      style: F.caps.copyWith(color: p.ink, letterSpacing: 2.2)),
                ]),
              ),
            ),
          ]),
        ),
      );
    });
  }

  // ── the four comparisons, each against its own 30-day average ───────────
  Widget _statsPanel(P p, String today) {
    Widget row(String id, StatMark mark, String label) {
      final m = trendMetricOf(id)!;
      final v = _valueOn(id, today);
      final avg = _avg30(id, today);
      final dir = v == null || avg == null
          ? null
          : v > avg
              ? 1
              : v < avg
                  ? -1
                  : null;
      return _StatRow(
          mark: mark,
          label: m.title.toUpperCase(),
          value: trendFormat(m, v),
          average: avg == null ? null : trendFormat(m, avg),
          direction: dir);
    }

    final rows = [
      row('zones_13', StatMark.zonesLow, 'Heart rate zones 1-3'),
      row('zones_45', StatMark.zonesHigh, 'Heart rate zones 4-5'),
      row('strength_time', StatMark.strength, 'Strength activity time'),
      row('steps', StatMark.steps, 'Steps (beta)'),
    ];
    return Column(children: [
      // The caret points up at the ring it belongs to.
      CustomPaint(
        size: const Size(S.x5, S.x2),
        painter: _CaretPainter(
            color: Color.alphaBlend(p.ink.withValues(alpha: .05), p.bg),
            edge: p.ink.withValues(alpha: .09)),
      ),
      Container(
        decoration: panelDecoration(context, tone: PanelTone.rich),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(
                  height: 1,
                  thickness: 1,
                  color: p.ink.withValues(alpha: .08),
                  indent: S.x5,
                  endIndent: S.x5),
          ],
        ]),
      ),
    ]);
  }

  /// The key to the triangles: green is above your usual, orange below it.
  Widget _comparisonLegend(P p, DateTime shown, AppLocalizations? l) {
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        decoration: BoxDecoration(
          color: Color.alphaBlend(C.char.withValues(alpha: .55), p.bg),
          borderRadius: R.rMd,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const DeltaTriangle(up: true, color: C.optimal, size: S.x3),
          const SizedBox(width: S.x2),
          const DeltaTriangle(up: false, color: C.strainDown, size: S.x3),
          const SizedBox(width: S.x3),
          Flexible(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${weekdayShortName(shown.weekday, l)}, '
                      '${monthShortName(shown.month, l)} ${shown.day}',
                  style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              TextSpan(
                  text: ' vs. last 30 days',
                  style: F.cap.copyWith(color: p.ink2, fontWeight: FontWeight.w500)),
            ])),
          ),
        ]),
      );
  }

  /// What the strain figure means, in words. The bands are the ones Trend View
  /// counts days into.
  Widget _band(double? s) {
    final p = P.of(context);
    final text = s == null
        ? 'No strain was recorded for this day.'
        : s >= 18
            ? 'Strain of 18 or more is considered all out. Your cardiovascular system has been pushed to its limit.'
            : s >= 14
                ? 'Strain between 14 and 17.9 is considered strenuous. Your cardiovascular system has been working hard.'
                : s >= 10
                    ? 'Strain between 10 and 13.9 is considered moderate. Your cardiovascular system has been working at a steady pace.'
                    : 'Strain below 10 is considered light. Your cardiovascular system has had an easy day.';
    return Padding(
      padding: const EdgeInsets.only(top: S.x6),
      child: Text(text,
          style: F.body.copyWith(
              color: p.ink, fontWeight: FontWeight.w500, height: 1.4)),
    );
  }

  /// Why there is no number, or what limits it. Shown only when it applies.
  List<Widget> _absence(P p, AppLocalizations? l, DayStrainData d) {
    final out = <Widget>[];
    if (!d.hasCurve) {
      // THE BUNDLE'S REASON, or none. A cause the screen did not receive is a
      // guess, so it is only printed when it came with the absence.
      final why = whyFromNote(d.note, unit: 'days');
      // "Wear the band" is only an instruction on a day the band did not see.
      final saw = (d.wornMin ?? 0) > 0 || (d.coveragePct ?? 0) > 0;
      // A strain with no minute trace behind it is a real day; the card may
      // say the trace is missing, and nothing about the score.
      final s = d.strain;
      out.add(StatusCard(
        s == null
            ? (l?.dayStrainNoTraceTitle ?? 'No strain trace for this day')
            : (l?.dayStrainNoMinuteTraceTitle ??
                'No minute-by-minute trace for this day'),
        s == null
            ? why ??
                (l?.dayStrainNoReasonBody ??
                    'Nothing recorded says why this day produced no strain.')
            : (l?.dayStrainScoredNoTraceBody(s.toStringAsFixed(1)) ??
                'The day strain is ${s.toStringAsFixed(1)}. The waking minutes '
                    'it was built from are not stored for this day.'),
        fix: (s == null && !saw)
            ? (l?.dayStrainWearBandFix ?? 'Wear the band through the day')
            : '',
        icon: LucideIcons.trendingUp,
      ));
    }
    if (d.coveragePct != null && d.coveragePct! < _lowCoveragePct) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: S.x4),
        child: StatusCard(
          l?.dayStrainLowCoverageTitle(d.coveragePct!) ??
              'The band saw ${d.coveragePct}% of this day',
          l?.dayStrainLowCoverageBody ??
              'Strain is a total over the minutes that were recorded, so a '
                  'partly-worn day reads lower than a full one and the two are '
                  'not comparable.',
          icon: LucideIcons.watch,
        ),
      ));
    }
    return out;
  }

  // ── today's activities: each saved session, its strain and its times ────
  Widget _todaysActivities(P p, AppLocalizations? l) {
    final sessions = _t.sessions;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Today's Activities",
          style: F.head.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
      const SizedBox(height: S.x4),
      if (sessions.isEmpty)
        Text('No activities were recorded for this day.',
            style: F.cap.copyWith(color: p.ink3))
      else
        for (final s in sessions) _ActivityCard(session: s),
    ]);
  }

  // ── weekly trends: the seven days ending on the day shown ───────────────
  Widget _weeklyTrends(P p, AppLocalizations? l, String today) {
    List<TrendBar> bars(String id) => trendBars(
        trendMetricOf(id)!, _t.daily[id] ?? const {}, TrendRange.week, today,
        firstDay: _t.firstDay);

    // Zone stacks: a day's bar is the sum of its zones, drawn in order.
    List<List<double>?> stacks(Map<String, List<double>> z, List<TrendBar> b) =>
        [for (final x in b) z[x.to]];
    List<double?> sums(List<List<double>?> s) => [
          for (final x in s) x?.fold<double>(0, (a, v) => a + v),
        ];

    final strain = bars('strain');
    final z13 = bars('zones_13');
    final z45 = bars('zones_45');
    final steps = bars('steps');
    final cals = bars('calories');
    final s13 = stacks(_t.zones13, z13);
    final s45 = stacks(_t.zones45, z45);
    final sum13 = sums(s13);
    final sum45 = sums(s45);

    String hmm(double? v) => trendFormat(trendMetricOf('zones_13')!, v);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Weekly Trends',
          style: F.head.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
      const SizedBox(height: S.x4),
      _WeekCard(
        title: 'Strain',
        metricId: 'strain',
        bars: strain,
        format: (v) => trendFormat(trendMetricOf('strain')!, v),
        color: C.dialStrain,
      ),
      const SizedBox(height: S.x3),
      _WeekCard(
        title: 'Heart rate zones 1-3',
        metricId: 'zones_13',
        bars: [
          for (var i = 0; i < z13.length; i++)
            (from: z13[i].from, to: z13[i].to, v: sum13[i]),
        ],
        stacks: s13,
        segments: _zoneColours.sublist(0, 3),
        segmentNames: const ['Zone 1', 'Zone 2', 'Zone 3'],
        format: hmm,
        color: C.dialStrain,
      ),
      const SizedBox(height: S.x3),
      _WeekCard(
        title: 'Heart rate zones 4-5',
        metricId: 'zones_45',
        bars: [
          for (var i = 0; i < z45.length; i++)
            (from: z45[i].from, to: z45[i].to, v: sum45[i]),
        ],
        stacks: s45,
        segments: _zoneColours.sublist(3, 5),
        segmentNames: const ['Zone 4', 'Zone 5'],
        format: hmm,
        color: C.dialStrain,
      ),
      const SizedBox(height: S.x3),
      _WeekCard(
        title: 'Steps (beta)',
        metricId: 'steps',
        bars: steps,
        format: (v) => trendFormat(trendMetricOf('steps')!, v),
        color: C.dialStrain,
      ),
      const SizedBox(height: S.x3),
      _WeekCard(
        title: 'Calories',
        metricId: 'calories',
        bars: cals,
        format: (v) => trendFormat(trendMetricOf('calories')!, v),
        color: C.dialStrain,
      ),
    ]);
  }

  // ── the curve, scrubbed, and only then the number ───────────────────────
  List<Widget> _throughTheDay(P p, AppLocalizations? l, DayStrainData d) {
    if (!d.hasCurve) return const [];
    final drawn = d.curve.where((v) => v != null).length;
    return [
      _CurveCard(
        curve: d.curve,
        strain: d.strain,
        title: l?.dayStrainChartTitle ?? 'Strain through the day',
        footnote: l?.dayStrainChartFootnote(drawn) ??
            'Effort above your usual waking pace. It can ease later if you slow back toward that pace. From $drawn recorded waking minutes.',
      ),
      if (d.peakHr != null || d.wornMin != null) ...[
        const SizedBox(height: S.x4),
        InlineMetrics([
          if (d.peakHr != null)
            (l?.dayStrainPeakHr ?? 'Peak HR', '${d.peakHr} bpm', C.red),
          if (d.wornMin != null)
            (l?.dayStrainWorn ?? 'Worn', '${d.wornMin} min', C.teal),
        ]),
      ],
    ];
  }

  // ── where the effort sat, by zone: the minutes and the edges in bpm ──────
  List<Widget> _zones(P p, AppLocalizations? l, DayStrainData d) {
    final z = d.zoneMin;
    if (z == null) return const [];
    final total = z.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return const [];
    return [
      Section(
        l?.dayStrainTimeInZonesSection ?? 'Time in zones',
        Surface(
          child: ZoneRows(
            [for (final v in z) v.toDouble()],
            lowerBpm: d.zoneLowerBpm,
            title: l?.dayStrainZonesChartTitle ?? 'Time in zones',
            // TS-03/TS-04 — the edges, and where THIS day's came from.
            footnote: zonesWhy(d.zoneSource, d.zoneMaxHr, l),
          ),
        ),
        // Progressive disclosure: the ceiling and the 28-day distribution are
        // one tap behind this link, not rows on the day.
        action: l?.dayStrainHowSet ?? 'How these are set',
        onAction: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ZonesDetail())),
      ),
    ];
  }

  // ── the inputs, named ────────────────────────────────────────────────────
  Widget _inputs(P p, AppLocalizations? l, DayStrainData d) {
    final max = d.maxHrUsed;
    return Surface(
      elevation: 0,
      color: p.card2,
      child: Text(
        [
          l?.dayStrainInputsBase ??
              'How hard your heart worked while awake, by minutes in each heart-rate zone, on a 0–21 scale.',
          if (max != null)
            l?.dayStrainInputsMaxHr(max.round()) ??
                'It was integrated against an assumed maximum of '
                    '${max.round()} bpm — estimated from your age and your strap, '
                    'not measured.',
          // Said out loud because the zone bar above can now be banded on a
          // MEASURED ceiling while this number is still the age estimate, and
          // two different ceilings on one screen with nothing saying so is
          // exactly the defect TS-03a removed.
          if (max != null && d.zoneSource != null && d.zoneSource != 'tanaka')
            l?.dayStrainInputsMeasuredCeilingNote ??
                'The zone bar uses your measured maximum. Strain does not, so the strain scores you have already seen stay the same.',
          l?.dayStrainInputsRhrAnchor ??
              'The other anchor is your resting heart rate from the night before, '
                  'so a night the band missed moves the whole day.',
        ].join(' '),
        style: F.cap.copyWith(color: p.ink3, height: 1.5),
      ),
    );
  }
}

/// The five zone colours, in zone order (zone 1 is the grey at the bottom).
const _zoneColours = <Color>[
  C.refZone1,
  C.refZone2,
  C.refZone3,
  C.refZone4,
  C.refZone5,
];

/// One row of the stats panel: its icon and label, the value, the 30-day
/// average under it, and the triangle that says which side of it the value is.
class _StatRow extends StatelessWidget {
  final StatMark mark;
  final String label;
  final String value;

  /// The 30-day average the triangle compares against, written as the value is.
  final String? average;

  /// 1 above the average, -1 below it, null when there is nothing to compare.
  final int? direction;

  const _StatRow({
    required this.mark,
    required this.label,
    required this.value,
    required this.average,
    required this.direction,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x5, vertical: S.x4),
      child: Row(children: [
        StatIcon(mark, color: p.ink2, size: I.lg + S.x1),
        const SizedBox(width: S.x4),
        Expanded(
          child: Text(label,
              style: F.caps.copyWith(
                  color: p.ink, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: S.x2),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value, style: F.n17.copyWith(color: p.ink)),
          if (average != null)
            Padding(
              padding: const EdgeInsets.only(top: S.half),
              child: Text(average!,
                  style: F.num(F.cap).copyWith(color: p.ink3, fontWeight: FontWeight.w600)),
            ),
        ]),
        SizedBox(
          width: S.x6,
          child: direction == null
              ? null
              : Align(
                  alignment: Alignment.centerRight,
                  child: DeltaTriangle(
                      up: direction! > 0,
                      color: direction! > 0 ? C.optimal : C.strainDown,
                      size: S.x3),
                ),
        ),
      ]),
    );
  }
}

/// A session as a card: its strain in a blue block, its name, and its start
/// and end.
class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> session;
  const _ActivityCard({required this.session});

  String _clock(int ts) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final type = (session['type'] ?? session['sport'] ?? 'Workout').toString();
    final act = activityByName(type);
    final strain = (session['strain'] as num?)?.toDouble();
    final start = (session['start_ts'] as num).toInt();
    final end = (session['end_ts'] as num?)?.toInt();
    return Pressable(
      onTap: () => Navigator.of(c).push(themedRoute(
          (_) => WorkoutDetailScreen(session: session),
          name: 'WorkoutDetailScreen')),
      semanticLabel: '${act?.name ?? type}, open the activity',
      child: Container(
      margin: const EdgeInsets.only(bottom: S.x3),
      padding: const EdgeInsets.all(S.x2),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
      child: Row(children: [
        Container(
          width: S.x16 * 1.75,
          height: S.x12,
          padding: const EdgeInsets.symmetric(horizontal: S.x3),
          decoration: BoxDecoration(color: C.dialStrain, borderRadius: R.rMd),
          child: Row(children: [
            Icon(act?.icon ?? LucideIcons.activity, size: I.lg, color: C.white),
            const SizedBox(width: S.x2),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(strain == null ? '--' : strain.toStringAsFixed(1),
                    style: F.n24.copyWith(color: C.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        const SizedBox(width: S.x4),
        Expanded(
          child: Text((act?.name ?? type).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_clock(start), style: F.num(F.cap).copyWith(color: p.ink3, fontWeight: FontWeight.w600)),
          Text(end == null ? '--' : _clock(end),
              style: F.num(F.cap).copyWith(color: p.ink3, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(width: S.x2),
        Container(width: S.half * 1.5, height: S.x8, color: C.dialStrain),
      ]),
    ));
  }
}

/// A weekly card: the title, the day under the finger in big, and a column
/// chart of the week. Each card scrubs on its own.
class _WeekCard extends StatefulWidget {
  final String title;
  final String metricId;
  final List<TrendBar> bars;
  final List<List<double>?>? stacks;
  final List<Color>? segments;
  final List<String>? segmentNames;
  final String Function(double?) format;
  final Color color;

  const _WeekCard({
    required this.title,
    required this.metricId,
    required this.bars,
    required this.format,
    required this.color,
    this.stacks,
    this.segments,
    this.segmentNames,
  });

  @override
  State<_WeekCard> createState() => _WeekCardState();
}

class _WeekCardState extends State<_WeekCard> {
  int? _at;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final bars = widget.bars;
    if (bars.isEmpty) return const SizedBox.shrink();
    final last = bars.length - 1;
    final bar = bars[_at ?? last];
    final values = [for (final b in bars) b.v];
    final top = values.fold<double>(0, (a, v) => math.max(a, v ?? 0));
    final hi = top <= 0 ? 1.0 : top * 1.12;
    final day = _dateOf(bar.to);
    return Container(
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(widget.title.toUpperCase(),
                style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          ),
          Pressable(
            onTap: () => Navigator.of(c).push(MaterialPageRoute(
                builder: (_) => TrendViewScreen(initial: widget.metricId))),
            semanticLabel: '${widget.title}: open trend view',
            child: SizedBox(
              width: S.x8,
              height: S.tap,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(LucideIcons.chevronRight, size: I.lg, color: p.ink2),
              ),
            ),
          ),
        ]),
        const SizedBox(height: S.x1),
        ScrubReadout(
          caption: '${weekdayShortName(day.weekday, l)}, '
              '${monthShortName(day.month, l)} ${day.day}',
          value: widget.format(bar.v),
          big: false,
        ),
        if (widget.segments != null && widget.segmentNames != null) ...[
          const SizedBox(height: S.x2),
          Wrap(spacing: S.x4, runSpacing: S.x1, children: [
            for (var i = 0; i < widget.segments!.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: S.x2 + S.half,
                  height: S.x2 + S.half,
                  decoration: BoxDecoration(
                      color: widget.segments![i], borderRadius: R.rSm),
                ),
                const SizedBox(width: S.x2),
                Text(widget.segmentNames![i].toUpperCase(),
                    style: F.over.copyWith(color: p.ink2, fontWeight: FontWeight.w700)),
              ]),
          ]),
        ],
        const SizedBox(height: S.x3),
        ScrubColumns(
          values: values,
          stacks: widget.stacks,
          segmentColors: widget.segments,
          xLabels: [
            for (final b in bars) weekdayShortName(_dateOf(b.to).weekday, l),
          ],
          valueLabels: [
            for (final b in bars) b.v == null ? '' : widget.format(b.v),
          ],
          lo: 0,
          hi: hi,
          ticks: [for (var k = 0; k <= 3; k++) hi * k / 3],
          tickText: (_) => '',
          color: widget.color,
          labelColor: p.ink,
          // The newest day carries the column at rest; a touch moves it.
          highlight: _at == null ? last : null,
          height: S.x16 * 3,
          gutter: 0,
          onScrub: (i) => setState(() => _at = i),
        ),
      ]),
    );
  }
}

DateTime _dateOf(String day) => DateTime.parse(day);

/// The day's curve through the minutes, scrubbed: the minute under the finger,
/// and its strain, in big.
class _CurveCard extends StatefulWidget {
  final List<double?> curve;
  final double? strain;
  final String title, footnote;
  const _CurveCard({
    required this.curve,
    required this.strain,
    required this.title,
    required this.footnote,
  });

  @override
  State<_CurveCard> createState() => _CurveCardState();
}

class _CurveCardState extends State<_CurveCard> {
  int? _at;

  String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const axis = AxisSpec(min: 0, max: 21, ticks: 4, format: axisInt);
    final at = _at;
    final v = at == null ? null : widget.curve[at];
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ScrubReadout(
          caption: at == null ? widget.title : _clock(at),
          value: at == null
              ? (widget.strain == null ? '--' : widget.strain!.toStringAsFixed(1))
              : (v == null ? '--' : v.toStringAsFixed(1)),
          big: false,
        ),
        const SizedBox(height: S.x3),
        ChartFrame(
          title: '',
          unit: '0–21',
          height: 170,
          yAxis: axis,
          xLabels: const ['00:00', '12:00', '24:00'],
          series: widget.curve,
          footnote: widget.footnote,
          child: ScrubArea(
            count: widget.curve.length,
            slots: false,
            height: 170,
            onScrub: (i) => setState(() => _at = i),
            dotAt: (i) {
              final y = widget.curve[i];
              return y == null ? null : (y / 21).clamp(0.0, 1.0);
            },
            builder: (c, _) => CustomPaint(
              size: Size.infinite,
              painter: LineChart(widget.curve, p.on(C.purple),
                  axis: axis, t: animate(c, 1)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The caret above the stats panel: a small triangle in the panel's colour.
class _CaretPainter extends CustomPainter {
  final Color color, edge;
  _CaretPainter({required this.color, required this.edge});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width / 2, 0)
          ..lineTo(size.width, size.height),
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.color != color || old.edge != edge;
}

/// The ring: the day's strain as a sweep from the top, the 30-day average as a
/// white tick across it.
class _StrainRingPainter extends CustomPainter {
  final double? fraction, baselineFraction;
  final Color track, arc, tick;

  _StrainRingPainter({
    required this.fraction,
    required this.baselineFraction,
    required this.track,
    required this.arc,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .064;
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2);
    canvas.drawArc(ring, 0, math.pi * 2, false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    final f = fraction;
    if (f != null && f > 0) {
      canvas.drawArc(ring, -math.pi / 2, math.pi * 2 * f, false,
          Paint()
            ..color = arc
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = stroke);
    }
    // The 30-day average: a white tick across the ring, no longer than the
    // ring is thick.
    final b = baselineFraction;
    if (b != null) {
      final a = -math.pi / 2 + math.pi * 2 * b;
      final c = rect.center;
      final r = ring.width / 2;
      final half = stroke / 2;
      canvas.drawLine(
          Offset(c.dx + (r - half) * math.cos(a), c.dy + (r - half) * math.sin(a)),
          Offset(c.dx + (r + half) * math.cos(a), c.dy + (r + half) * math.sin(a)),
          Paint()
            ..color = tick
            ..strokeWidth = stroke * .15
            ..strokeCap = StrokeCap.butt);
    }
  }

  @override
  bool shouldRepaint(_StrainRingPainter old) =>
      old.fraction != fraction ||
      old.baselineFraction != baselineFraction ||
      old.track != track ||
      old.arc != arc;
}
