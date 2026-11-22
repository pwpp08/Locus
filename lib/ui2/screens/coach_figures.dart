// The coach's figures, drawn with the app's OWN charts.
//
// The model emits a typed spec map ({type, title, …payload}); this file turns
// it into a `ChartFrame` around a real painter from `charts.dart`. Nothing here
// draws pixels of its own — that was the point of the `render` tool, and the
// version this replaces carried six private painters that looked like the app
// and obeyed none of its rules (no axis, no legend, no spoken summary, raw
// pigment as text).
//
// Every parser fails SOFT: LLM output is liberal, and a figure that cannot be
// read renders as `NoData` inside its frame rather than throwing inside a
// ListView builder. A frame with no data keeps its title and its unit, which is
// the house form for "the number exists but the series behind the picture does
// not".

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../state/clock_format.dart' show formatClockOf;
import '../ui2.dart';
import 'home/home_data.dart' show monthShortName, weekdayShortName;

// ── loose parsing (the model is not a schema) ────────────────────────────────

List<dynamic> _list(dynamic v) {
  if (v is List) return v;
  if (v is Map && v['item'] is List) return v['item'] as List;
  if (v is Map && v['items'] is List) return v['items'] as List;
  return const [];
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) {
    final d = double.tryParse(v.trim());
    if (d != null) return d;
    // '62 ms' — units glued on. Take the first number.
    final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(v);
    return m == null ? null : double.tryParse(m.group(0)!);
  }
  if (v is Map) return _num(v['value'] ?? v['y'] ?? v['v']);
  return null;
}

String _str(dynamic v) => v == null ? '' : v.toString();

List<double?> _values(dynamic v) => [for (final e in _list(v)) _num(e)];

/// One named line of numbers.
typedef _Series = ({String name, List<double?> values});

List<_Series> _seriesOf(Map<String, dynamic> s) => [
  for (final e in _list(s['series'] ?? s['lanes']).whereType<Map>())
    (
      name: _str(e['name'] ?? e['label']),
      values: _values(e['values'] ?? e['data'] ?? e['y']),
    ),
];

/// Series colours, solved against the surface. Raw pigment is not legible as a
/// mark on a card — and the legend swatch is the mark's real colour because it
/// comes from the same list.
List<Color> _inks(P p) => [
  p.on(C.dialStrain),
  p.on(C.strainDown),
  p.on(C.stressLow),
  p.on(C.dialStrain),
  p.on(C.optimal),
];

/// First, middle and last — the three positions `ChartFrame` marks. More than
/// three labels under a 90-point series is a smear.
List<String> _xLabels(dynamic raw) {
  final all = [for (final e in _list(raw)) _str(e)];
  if (all.length <= 3) return all;
  return [all.first, all[all.length ~/ 2], all.last];
}

/// The axis every painter in one figure shares. Null when nothing is finite,
/// which is the signal to render the frame's empty state.
AxisSpec? _axisFor(
  Iterable<List<double?>> series, {
  List<double> alsoShow = const [],
}) {
  final flat = [
    for (final s in series)
      for (final v in s)
        if (v != null && v.isFinite) v,
  ];
  if (flat.isEmpty) return null;
  flat.addAll(alsoShow);
  return AxisSpec.of(flat, format: axisFixedOrInt);
}

// ── annotations ──────────────────────────────────────────────────────────────

/// A figure's reference line, usual range and events, read from its spec.
class _Notes {
  final (double, String)? baseline;
  final (double, double, String)? range;
  final List<(int, String)> markers;
  const _Notes(this.baseline, this.range, this.markers);

  factory _Notes.of(Map<String, dynamic> spec) {
    final b = spec['baseline'], r = spec['normal_range'];
    final bv = b is Map ? _num(b['value']) : null;
    final lo = r is Map ? _num(r['min']) : null;
    final hi = r is Map ? _num(r['max']) : null;
    final labels = [
      for (final e in _list(spec['x_labels'] ?? spec['labels'] ?? spec['x']))
        _str(e),
    ];
    return _Notes(
      bv == null ? null : (bv, _str((b as Map)['label'])),
      lo == null || hi == null ? null : (lo, hi, _str((r as Map)['label'])),
      [
        for (final m in _list(spec['markers']).whereType<Map>())
          if (labels.contains(_str(m['x'])))
            (labels.indexOf(_str(m['x'])), _str(m['label'])),
      ],
    );
  }

  bool get isEmpty => baseline == null && range == null && markers.isEmpty;

  List<double> get values => [
    ?baseline?.$1,
    ?range?.$1,
    ?range?.$2,
  ];

  List<(String, Color)> legend(P p) => [
    if (baseline case final b?) (b.$2, p.ink2),
    if (range case final r?) (r.$3, p.on(C.stressLow)),
    for (final m in markers) (m.$2, p.on(C.strainDown)),
  ];
}

/// Draws [_Notes] on the same scale as the chart beneath it.
class _NotesPainter extends CustomPainter {
  final _Notes notes;
  final AxisSpec axis;
  final int points;

  /// Bars sit in the middle of a slot, line points on its edges.
  final bool slotted;
  final Color line, band, mark;
  const _NotesPainter(
    this.notes,
    this.axis,
    this.points, {
    required this.slotted,
    required this.line,
    required this.band,
    required this.mark,
  });

  @override
  void paint(Canvas cv, Size s) {
    double y(double v) => s.height - axis.t(v) * s.height;
    if (notes.range case final r?) {
      cv.drawRect(
        Rect.fromLTRB(0, y(r.$2), s.width, y(r.$1)),
        Paint()..color = band.withValues(alpha: .14),
      );
    }
    if (notes.baseline case final b?) {
      final at = y(b.$1);
      final paint = Paint()
        ..color = line
        ..strokeWidth = S.hair * 2;
      for (var x = 0.0; x < s.width; x += S.x2) {
        cv.drawLine(Offset(x, at), Offset(x + S.x1, at), paint);
      }
    }
    if (points < 1) return;
    final paint = Paint()
      ..color = mark.withValues(alpha: .6)
      ..strokeWidth = S.hair;
    for (final (i, _) in notes.markers) {
      final x = slotted
          ? (i + .5) / points * s.width
          : (points == 1 ? 0.0 : i / (points - 1) * s.width);
      cv.drawLine(Offset(x, S.x1), Offset(x, s.height), paint);
      cv.drawCircle(Offset(x, S.x1), S.x1, Paint()..color = mark);
    }
  }

  @override
  bool shouldRepaint(_NotesPainter o) =>
      o.notes != notes || o.axis != axis || o.points != points ||
      o.line != line || o.band != band || o.mark != mark;
}

// ── the figure ───────────────────────────────────────────────────────────────

/// One figure from the coach. [spec] is `{type, title, …}` — either a `render`
/// payload or `ChartSpec.toJson()`, which is the same shape.
class CoachFigure extends StatelessWidget {
  final Map<String, dynamic> spec;
  const CoachFigure({super.key, required this.spec});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final type = _str(spec['type']).toLowerCase();
    final title = _str(spec['title']);
    final unit = _str(spec['unit'] ?? spec['y_unit']);
    final note = _str(spec['note']);

    final body = switch (type) {
      'line' || 'area' || 'multi_series' => _lines(c, p, title, unit),
      'bar' || 'bars' => _bars(c, p, title, unit),
      'lanes' || 'dual_axis' => _lanes(c, p, title),
      'hypnogram' => _hypnogram(c, p, title),
      'zone_bar' || 'stacked_zone_bar' => _zones(c, p, title),
      'gauge' => _gauge(c, p, title, unit),
      'kpi_grid' => _kpis(c, p, title),
      'heatmap' => _heatmap(c, p, title, unit),
      'table' => _table(c, p, title),
      _ => _unsupported(c, title, type),
    };

    if (note.isEmpty) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        const SizedBox(height: S.x2),
        Text(note, style: F.cap.copyWith(color: p.ink3, height: 1.4)),
      ],
    );
  }

  Widget _unsupported(BuildContext c, String title, String type) {
    final l = AppLocalizations.of(c);
    return StatusCard(
      title.isEmpty
          ? (l?.coachFiguresCouldNotBeDrawn ?? 'A figure could not be drawn')
          : title,
      type.isEmpty
          ? (l?.coachFiguresNoType ?? 'The coach sent a figure with no type.')
          : (l?.coachFiguresUnsupportedType(type) ??
              'The coach asked for a "$type" figure, which this app does not draw.'),
      icon: LucideIcons.chartNoAxesColumn,
    );
  }

  Widget _frame(
    BuildContext c,
    String title,
    String unit,
    Widget child, {
    AxisSpec? yAxis,
    List<String> xLabels = const [],
    List<(String, Color)> legend = const [],
    List<double?> series = const [],
    double height = 140,
    Widget? empty,
    String? footnote,
  }) => ChartFrame(
    title: title.isEmpty ? (AppLocalizations.of(c)?.coachFiguresFigure ?? 'Figure') : title,
    unit: unit,
    height: height,
    yAxis: yAxis,
    xLabels: xLabels,
    legend: legend,
    series: series,
    empty: empty,
    footnote: footnote,
    child: child,
  );

  // ── line / area / multi-series ─────────────────────────────────────────────
  //
  // One shared axis for every series in the figure. Two curves on two invisible
  // scales is the classic chart lie, and it is the default a painter falls back
  // to when nobody gives it an axis.
  Widget _lines(BuildContext c, P p, String title, String unit) {
    final series = _seriesOf(spec);
    final notes = _Notes.of(spec);
    final axis = _axisFor(
      series.map((s) => s.values),
      alsoShow: notes.values,
    );
    if (axis == null) {
      return _frame(c, title, unit, const SizedBox.shrink(), empty: const NoData());
    }
    final l = AppLocalizations.of(c);
    final inks = _inks(p);
    return _frame(
      c,
      title,
      unit,
      Stack(
        children: [
          for (var i = 0; i < series.length; i++)
            Positioned.fill(
              child: CustomPaint(
                size: Size.infinite,
                painter: LineChart(
                  series[i].values,
                  inks[i % inks.length],
                  // A filled area reads as a quantity from a baseline, so it is
                  // only honest for ONE series against a stated axis.
                  fill: series.length == 1 &&
                      _str(spec['type']).toLowerCase() == 'area',
                  axis: axis,
                ),
              ),
            ),
          if (!notes.isEmpty)
            Positioned.fill(
              child: _notesLayer(p, notes, axis, series.first.values.length),
            ),
        ],
      ),
      yAxis: axis,
      xLabels: _xLabels(spec['x_labels'] ?? spec['labels'] ?? spec['x']),
      legend: [
        if (series.length > 1)
          for (var i = 0; i < series.length; i++)
            (
              series[i].name.isEmpty
                  ? (l?.coachFiguresSeriesN(i + 1) ?? 'Series ${i + 1}')
                  : series[i].name,
              inks[i % inks.length],
            ),
        ...notes.legend(p),
      ],
      series: series.length == 1 ? series.first.values : const [],
    );
  }

  // ── bars ───────────────────────────────────────────────────────────────────
  Widget _notesLayer(
    P p,
    _Notes notes,
    AxisSpec axis,
    int points, {
    bool slotted = false,
  }) => CustomPaint(
    size: Size.infinite,
    painter: _NotesPainter(
      notes,
      axis,
      points,
      slotted: slotted,
      line: p.ink2,
      band: p.on(C.stressLow),
      mark: p.on(C.strainDown),
    ),
  );

  Widget _bars(BuildContext c, P p, String title, String unit) {
    final series = _seriesOf(spec);
    final notes = _Notes.of(spec);
    final d = series.isEmpty ? _values(spec['values']) : series.first.values;
    // Bars are measured from a baseline; a bar axis that does not include zero
    // is the truncated-axis lie with the truncation hidden.
    final finite = [
      for (final v in d)
        if (v != null && v.isFinite) v,
    ];
    final axis = finite.isEmpty
        ? null
        : AxisSpec.of(
            [...finite, ...notes.values],
            floor: 0,
            format: axisFixedOrInt,
          );
    if (axis == null) {
      return _frame(c, title, unit, const SizedBox.shrink(), empty: const NoData());
    }
    return _frame(
      c,
      title,
      unit,
      Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              size: Size.infinite,
              painter: Bars(d, p.on(C.dialStrain), axis: axis),
            ),
          ),
          if (!notes.isEmpty)
            Positioned.fill(
              child: _notesLayer(p, notes, axis, d.length, slotted: true),
            ),
        ],
      ),
      yAxis: axis,
      xLabels: _xLabels(spec['x_labels'] ?? spec['labels'] ?? spec['x']),
      legend: notes.legend(p),
      series: d,
    );
  }

  // ── lanes (was dual_axis) ──────────────────────────────────────────────────
  //
  // Two units never share a y scale here. `NightStack` gives each its own lane
  // and its own axis, which is the app's answer to a second y axis — a right
  // axis is read as if it were the left one about as often as not.
  Widget _lanes(BuildContext c, P p, String title) {
    var series = _seriesOf(spec);
    if (series.isEmpty) {
      // `dual_axis` shape: {left:{name,values,unit}, right:{…}}.
      series = [
        for (final k in const ['left', 'right'])
          if (spec[k] is Map)
            (
              name: _str((spec[k] as Map)['name']),
              values: _values((spec[k] as Map)['values']),
            ),
      ];
    }
    // DENSE, holes intact. `NightStack` drops any lane whose length differs
    // from the longest one — they are on different clocks — so compacting the
    // nulls out of a lane with one missing reading would make the whole lane
    // silently disappear.
    final lanes = [
      for (final s in series)
        if (s.values.any((v) => v != null && v.isFinite)) s.values,
    ];
    if (lanes.isEmpty) {
      return _frame(c, title, '', const SizedBox.shrink(), empty: const NoData());
    }
    final loc = AppLocalizations.of(c);
    final inks = _inks(p);
    final units = [
      for (final k in const ['left', 'right'])
        if (spec[k] is Map) _str((spec[k] as Map)['unit']),
    ];
    return _frame(
      c,
      title,
      units.where((u) => u.isNotEmpty).join(' · '),
      CustomPaint(
        size: Size.infinite,
        painter: NightStack(lanes, [
          for (var i = 0; i < lanes.length; i++) inks[i % inks.length],
        ], axes: [
          for (final l in lanes)
            AxisSpec.of([
              for (final v in l)
                if (v != null && v.isFinite) v,
            ], ticks: 2),
        ]),
      ),
      height: 60.0 * lanes.length + 40,
      xLabels: _xLabels(spec['x_labels'] ?? spec['labels'] ?? spec['x']),
      legend: [
        for (var i = 0; i < series.length && i < lanes.length; i++)
          (
            series[i].name.isEmpty
                ? (loc?.coachFiguresLaneN(i + 1) ?? 'Lane ${i + 1}')
                : series[i].name,
            inks[i % inks.length],
          ),
      ],
    );
  }

  // ── hypnogram ──────────────────────────────────────────────────────────────
  Widget _hypnogram(BuildContext c, P p, String title) {
    final l = AppLocalizations.of(c);
    final noSegs =
        NoData(message: l?.coachFiguresNoSleepSegments ?? 'No sleep segments');
    final segs = _list(spec['segments']).whereType<Map>().toList();
    // The painter takes one entry per EPOCH, in order — it has no opinion about
    // time. Expand the segments onto a fixed grid so a 20-minute REM block and
    // a 20-minute deep block are the same width.
    const slots = 480; // one per minute of an eight-hour night
    final lo = [for (final s in segs) ?_num(s['start'])];
    final hi = [for (final s in segs) ?_num(s['end'])];
    if (lo.isEmpty || hi.isEmpty) {
      return _frame(c, title, 'stage', const SizedBox.shrink(), empty: noSegs);
    }
    final t0 = lo.reduce((a, b) => a < b ? a : b);
    final t1 = hi.reduce((a, b) => a > b ? a : b);
    if (t1 <= t0) {
      return _frame(c, title, 'stage', const SizedBox.shrink(), empty: noSegs);
    }
    final grid = List<SleepStage>.filled(slots, SleepStage.awake);
    for (final s in segs) {
      final a = _num(s['start']), b = _num(s['end']);
      if (a == null || b == null || b <= a) continue;
      final stage = switch (_str(s['stage']).toLowerCase()) {
        'deep' => SleepStage.deep,
        'rem' => SleepStage.rem,
        'light' => SleepStage.light,
        _ => SleepStage.awake,
      };
      final i0 = ((a - t0) / (t1 - t0) * slots).floor().clamp(0, slots - 1);
      final i1 = ((b - t0) / (t1 - t0) * slots).ceil().clamp(0, slots);
      for (var i = i0; i < i1; i++) {
        grid[i] = stage;
      }
    }
    String hhmm(double epochSec) {
      final d = DateTime.fromMillisecondsSinceEpoch(
        (epochSec * 1000).round(),
      ).toLocal();
      return formatClockOf(d);
    }

    return _frame(
      c,
      title,
      'stage',
      CustomPaint(size: Size.infinite, painter: Hypnogram(grid, p)),
      height: 130,
      xLabels: [hhmm(t0), hhmm(t1)],
      legend: Hypnogram.legend(p, AppLocalizations.of(c)),
    );
  }

  // ── zone bar ───────────────────────────────────────────────────────────────
  //
  // Five labelled rows, the same component every zone split in the app uses.
  // No bpm ranges: a figure spec carries minutes, not the edges they were cut at.
  Widget _zones(BuildContext c, P p, String title) {
    final l = AppLocalizations.of(c);
    var z = [
      for (final v in _values(spec['zones'] ?? spec['values']))
        if (v != null && v.isFinite && v >= 0) v,
    ];
    // {zones:[{name, values:[…]}]} — sum each zone across the window.
    if (z.isEmpty) {
      z = [
        for (final s in _seriesOf(spec))
          s.values.fold<double>(0, (a, v) => a + (v ?? 0)),
      ];
    }
    final total = z.fold<double>(0, (a, v) => a + v);
    if (z.length < 2 || total <= 0) {
      return _frame(
        c,
        title,
        'min',
        const SizedBox.shrink(),
        empty: NoData(
            message: l?.coachFiguresNoTimeInZone ?? 'No time in zone'),
      );
    }
    return ZoneRows(
      [...z.take(5)],
      title: title.isEmpty ? (l?.coachFiguresFigure ?? 'Figure') : title,
      footnote: l?.coachFiguresMinTotal(total.round()) ??
          '${total.round()} min total',
    );
  }

  // ── gauge ──────────────────────────────────────────────────────────────────
  Widget _gauge(BuildContext c, P p, String title, String unit) {
    final l = AppLocalizations.of(c);
    final v = _num(spec['value']);
    final lo = _num(spec['min']) ?? 0, hi = _num(spec['max']) ?? 100;
    if (v == null || hi <= lo) {
      return StatusCard(
        title.isEmpty ? (l?.coachFiguresGauge ?? 'Gauge') : title,
        l?.coachFiguresGaugeNoValue ?? 'The coach sent a gauge with no value.',
        icon: LucideIcons.gauge,
      );
    }
    final frac = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    final label = _str(spec['label']);
    return Surface(
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(84),
                  painter: Ring(frac, p.on(C.dialStrain), p.track, stroke: 8),
                ),
                Text(
                  v == v.roundToDouble()
                      ? v.round().toString()
                      : v.toStringAsFixed(1),
                  style: F.n24.copyWith(color: p.ink),
                ),
              ],
            ),
          ),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty
                      ? (label.isEmpty ? (l?.coachFiguresGauge ?? 'Gauge') : label)
                      : title,
                  style: F.head.copyWith(color: p.ink),
                ),
                const SizedBox(height: S.x1),
                Text(
                  '${lo.round()}–${hi.round()}'
                  '${unit.isEmpty ? '' : ' $unit'}',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── KPI grid ───────────────────────────────────────────────────────────────
  //
  // Real `SignalCard`s — card job A, the one the app uses for a glanceable
  // number. No sparkline: `SignalCard` has no slot for one, and a second
  // number-and-a-picture card invented here would be a card job nobody else
  // spends.
  Widget _kpis(BuildContext c, P p, String title) {
    final l = AppLocalizations.of(c);
    final cards = _list(spec['cards']).whereType<Map>().toList();
    if (cards.isEmpty) {
      return StatusCard(
        title.isEmpty ? (l?.coachFiguresSummary ?? 'Summary') : title,
        l?.coachFiguresEmptySummary ?? 'The coach sent an empty summary.',
        icon: LucideIcons.layoutGrid,
      );
    }
    final inks = [C.dialStrain, C.strainDown, C.stressLow, C.dialStrain, C.optimal];
    final grid = LayoutBuilder(
      builder: (_, box) {
        final w = (box.maxWidth - S.x3) / 2;
        return Wrap(
          spacing: S.x3,
          runSpacing: S.x3,
          children: [
            for (var i = 0; i < cards.length; i++)
              SizedBox(
                width: cards.length == 1 ? box.maxWidth : w,
                child: SignalCard(
                  LucideIcons.activity,
                  inks[i % inks.length],
                  _str(cards[i]['label']),
                  _str(cards[i]['value']),
                  unit: _str(cards[i]['unit']),
                  sub: _str(cards[i]['baseline'] ?? cards[i]['sub']),
                ),
              ),
          ],
        );
      },
    );
    if (title.isEmpty) return grid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: F.head.copyWith(color: p.ink)),
        const SizedBox(height: S.x3),
        grid,
      ],
    );
  }

  // ── heatmap ────────────────────────────────────────────────────────────────
  //
  // The app's heatmap is a CALENDAR: weeks across, Mon→Sun down. That shape is
  // what the painter draws and what the prompt asks for.
  Widget _heatmap(BuildContext c, P p, String title, String unit) {
    final weeks = [
      for (final r in _list(spec['weeks'] ?? spec['values']))
        [for (final v in _list(r)) _num(v)],
    ];
    if (weeks.isEmpty || weeks.every((w) => w.every((v) => v == null))) {
      return _frame(c, title, unit, const SizedBox.shrink(), empty: const NoData());
    }
    return _frame(
      c,
      title,
      unit,
      CustomPaint(
        size: Size.infinite,
        painter: HeatMap(weeks, p.on(C.dialStrain), p.track),
      ),
      height: 110,
      xLabels: _xLabels(spec['x_labels'] ?? spec['labels']),
      series: [for (final w in weeks) ...w],
    );
  }

  // ── table ──────────────────────────────────────────────────────────────────
  // ── table ──────────────────────────────────────────────────────────────────
  //
  // A table the eye can read in one pass: the first column names the row, a
  // column of numbers lines up on the right and carries a bar scaled to its own
  // largest value, that largest value is picked out, and with three rows or more
  // an average closes it. Words stay words; only a column that is numbers in
  // every filled cell is drawn as one.
  /// A word cell. A date reads as a person says it, the year only when it is
  /// not this one; in the name column it is a small calendar leaf, the
  /// weekday over the day, with the month beside it.
  Widget _wordCell(BuildContext c, P p, String s,
      {required bool name, required DateTime now, bool month = true}) {
    final d = tableDate(s);
    final l = AppLocalizations.of(c);
    if (d != null && name) {
      return Row(children: [
        Container(
          width: S.x8 + S.x1,
          padding: const EdgeInsets.symmetric(vertical: S.half),
          decoration: BoxDecoration(
              color: C.white.withValues(alpha: .08), borderRadius: R.rSm),
          child: Column(children: [
            Text(weekdayShortName(d.weekday, l).toUpperCase(),
                style: F.over.copyWith(color: p.ink3)),
            Text('${d.day}',
                style: F.num(F.body)
                    .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (month) ...[
        const SizedBox(width: S.x2),
        Flexible(
          child: Text(
            d.year == now.year
                ? monthShortName(d.month, l)
                : '${monthShortName(d.month, l)} ${d.year}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: F.cap.copyWith(color: p.ink2),
          ),
        ),
        ],
      ]);
    }
    return Text(
      d != null ? chatDate(d, now: now, l: l) : s,
      style: name
          ? F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600)
          : F.cap.copyWith(color: p.ink2),
    );
  }

  Widget _table(BuildContext c, P p, String title) {
    final l = AppLocalizations.of(c);
    final cols = [for (final e in _list(spec['columns'])) _str(e)];
    final rows = [
      for (final r in _list(spec['rows'])) [for (final e in _list(r)) _str(e)],
    ];
    if (rows.isEmpty) {
      return StatusCard(
        title.isEmpty ? (l?.coachFiguresTable ?? 'Table') : title,
        l?.coachFiguresTableNoRows ?? 'The coach sent a table with no rows.',
        icon: LucideIcons.table,
      );
    }
    final n = rows.fold<int>(cols.length, (a, r) => r.length > a ? r.length : a);
    String at(List<String> r, int i) => i < r.length ? r[i] : '';

    // Per column: the parsed numbers (null where a cell is not one) when the
    // column is numeric, else null. Column 0 is the row's name unless it is
    // the only column.
    final nums = <List<double?>?>[
      for (var i = 0; i < n; i++)
        () {
          if (i == 0 && n > 1) return null;
          final v = [for (final r in rows) tableNumber(at(r, i))];
          final filled = [for (final r in rows) if (at(r, i).trim().isNotEmpty) r];
          final ok = v.whereType<double>().length;
          return ok >= 1 && ok == filled.length ? v : null;
        }(),
    ];
    final hi = [
      for (final v in nums)
        v?.whereType<double>()
            .fold<double>(0, (a, x) => x.abs() > a ? x.abs() : a),
    ];
    final best = [
      for (final v in nums)
        v == null || v.whereType<double>().length < 2
            ? null
            : v.whereType<double>().reduce((a, x) => x > a ? x : a),
    ];
    final showAvg = rows.length >= 3 && nums.any((v) => v != null);
    // Each numeric column in the colour of what it measures, as the rest of
    // the app draws it: strain blue, sleep slate, heart red.
    final hues = [
      for (var i = 0; i < n; i++)
        nums[i] == null ? null : tableHue(i < cols.length ? cols[i] : ''),
    ];
    final now = DateTime.now();
    // A unit every cell of a column shares is said once, in its header.
    final units = [
      for (var i = 0; i < n; i++)
        nums[i] == null ? '' : tableUnit([for (final r in rows) at(r, i)]),
    ];
    String shown(List<String> r, int i) {
      final v = at(r, i).trim();
      return units[i].isEmpty || !v.endsWith(units[i])
          ? v
          : v.substring(0, v.length - units[i].length).trim();
    }

    // Dates in the name column all in one month: the month goes up top too.
    final dates = [for (final r in rows) tableDate(at(r, 0))];
    final oneMonth = n > 1 &&
        dates.every((d) => d != null) &&
        dates.every((d) =>
            d!.month == dates.first!.month && d.year == dates.first!.year);
    final l10n = AppLocalizations.of(c);
    String header(int i) {
      if (i == 0 && oneMonth) {
        final d = dates.first!;
        final m = monthShortName(d.month, l10n);
        return d.year == now.year ? m : '$m ${d.year}';
      }
      return i < cols.length ? cols[i] : '';
    }

    Widget cell(int i, Widget child, {bool head = false}) => Padding(
          padding: EdgeInsets.fromLTRB(
              i == 0 ? S.x2 : S.x1 + S.half, head ? S.x2 : S.x2,
              i == n - 1 ? S.x2 : S.x1 + S.half, head ? S.x2 : S.x2),
          child: child,
        );
    Widget numCell(String text, double? v, int i, {required bool top}) {
      final frac = v == null || (hi[i] ?? 0) <= 0 ? 0.0 : (v.abs() / hi[i]!).clamp(0.0, 1.0);
      // Recovery takes its band's colour per value; the rest their column's.
      final hue = v != null && tableIsRecovery(i < cols.length ? cols[i] : '')
          ? trendRecoveryHue(v)
          : (hues[i] ?? C.white);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(text,
            textAlign: TextAlign.right,
            style: F.num(F.cap).copyWith(
                color: top ? C.white : p.ink,
                fontWeight: top ? FontWeight.w700 : FontWeight.w500)),
        const SizedBox(height: S.x1),
        // The bar runs right to left, from the figure it sits under. Painted,
        // not a FractionallySizedBox: a zero factor has no finite intrinsic
        // width, and the table sizes its columns by intrinsics.
        SizedBox(
          height: S.x1,
          child: CustomPaint(
            painter: _CellBar(frac, hue.withValues(alpha: .16),
                hue.withValues(alpha: top ? 1 : .6)),
          ),
        ),
      ]);
    }

    final avgs = [
      for (var i = 0; i < n; i++)
        () {
          final v = nums[i]?.whereType<double>().toList();
          if (v == null || v.isEmpty) return '';
          final mean = v.reduce((a, x) => a + x) / v.length;
          return tableFormat(mean, [for (final r in rows) shown(r, i)]);
        }(),
    ];

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty) ...[
            Row(children: [
              Expanded(
                child: Text(title, style: F.head.copyWith(color: p.ink)),
              ),
              const SizedBox(width: S.x2),
              Text('${rows.length} ${rows.length == 1 ? 'row' : 'rows'}',
                  style: F.cap.copyWith(color: p.ink3)),
            ]),
            const SizedBox(height: S.x3),
          ],
          // A wide table scrolls inside itself rather than overflowing the
          // page; a narrow one still fills the card. The width comes from the
          // LAYOUT, not from the screen — `MediaQuery.size` minus a padding
          // constant goes negative in any frame narrower than the padding, and
          // a negative minWidth is an assertion, not a squeeze.
          LayoutBuilder(
            builder: (_, box) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: box.maxWidth),
                // A finite width for the flex column to fill: its own when
                // wider than the card, the card's otherwise.
                child: IntrinsicWidth(
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  // The name column takes what is left, so the numbers sit
                  // flush right against the card's edge.
                  columnWidths: {
                    if (n > 1) 0: const IntrinsicColumnWidth(flex: 1),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    if (cols.isNotEmpty)
                      TableRow(
                        decoration: BoxDecoration(
                            color: C.white.withValues(alpha: .07),
                            borderRadius: R.rMd),
                        children: [
                          for (var i = 0; i < n; i++)
                            cell(
                              i,
                              Row(
                                mainAxisAlignment: nums[i] != null
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [
                                  // The column's colour, keyed to its bars.
                                  if (hues[i] != null) ...[
                                    Container(
                                      width: S.x1 + S.half,
                                      height: S.x1 + S.half,
                                      decoration: BoxDecoration(
                                          color: hues[i],
                                          shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: S.x1),
                                  ],
                                  Column(
                                    crossAxisAlignment: nums[i] != null
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      Text(header(i).toUpperCase(),
                                          style:
                                              F.over.copyWith(color: p.ink2)),
                                      if (units[i].isNotEmpty)
                                        Text(units[i],
                                            style: F.over.copyWith(
                                                color: p.ink3,
                                                fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ],
                              ),
                              head: true,
                            ),
                        ],
                      ),
                    for (var r = 0; r < rows.length; r++)
                      TableRow(
                        // Every other row a shade lighter, so a long row is
                        // followed by the eye across the gap.
                        decoration: r.isOdd
                            ? BoxDecoration(
                                color: C.white.withValues(alpha: .03),
                                borderRadius: R.rMd)
                            : null,
                        children: [
                          for (var i = 0; i < n; i++)
                            cell(
                              i,
                              nums[i] != null
                                  ? numCell(shown(rows[r], i), nums[i]![r], i,
                                      top: best[i] != null &&
                                          nums[i]![r] == best[i])
                                  : _wordCell(c, p, at(rows[r], i),
                                      name: i == 0,
                                      now: now,
                                      month: !oneMonth),
                            ),
                        ],
                      ),
                    if (showAvg)
                      TableRow(
                        decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: p.line))),
                        children: [
                          for (var i = 0; i < n; i++)
                            cell(
                              i,
                              Text(
                                i == 0 ? 'Average' : avgs[i],
                                textAlign: nums[i] != null
                                    ? TextAlign.right
                                    : TextAlign.left,
                                style: (nums[i] != null ? F.num(F.cap) : F.cap)
                                    .copyWith(color: p.ink3),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A table cell read as a number: "42", "1,204", "-3.5", "61 ms", "87%",
/// "7:12" (hours and minutes, as minutes). Null for anything else, a date
/// included.
double? tableNumber(String s) {
  final t = s.trim();
  final hm = RegExp(r'^(\d{1,3}):([0-5]\d)$').firstMatch(t);
  if (hm != null) {
    return int.parse(hm.group(1)!) * 60.0 + int.parse(hm.group(2)!);
  }
  final m = RegExp(r'^([-+−]?\d[\d,]*(?:\.\d+)?)\s*([a-zA-Z%°/]{0,6})$')
      .firstMatch(t);
  if (m == null) return null;
  return double.tryParse(m.group(1)!.replaceAll(',', '').replaceAll('−', '-'));
}

/// [v] written the way its column writes numbers: h:mm when the column is
/// times, the column's own decimals and unit otherwise.
String tableFormat(double v, List<String> column) {
  final cells = [for (final c in column) if (c.trim().isNotEmpty) c.trim()];
  if (cells.isNotEmpty && cells.every((c) => c.contains(':'))) {
    final m = v.round();
    return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
  }
  var places = 0;
  String? unit;
  var oneUnit = true;
  for (final c in cells) {
    final m = RegExp(r'^[-+−]?[\d,]*(?:\.(\d+))?\s*(.*)$').firstMatch(c);
    if (m == null) continue;
    final d = m.group(1)?.length ?? 0;
    if (d > places) places = d;
    final u = m.group(2) ?? '';
    if (unit == null) {
      unit = u;
    } else if (unit != u) {
      oneUnit = false;
    }
  }
  // A whole-number column's average gets one place, so 7.5 is not shown as 8.
  final shown = v.toStringAsFixed(places == 0 && v != v.roundToDouble() ? 1 : places);
  final u = oneUnit ? (unit ?? '') : '';
  return u.isEmpty ? shown : (u == '%' ? '$shown%' : '$shown $u');
}

/// A table cell's bar: the track, and [frac] of it filled from the right.
class _CellBar extends CustomPainter {
  final double frac;
  final Color track, fill;
  const _CellBar(this.frac, this.track, this.fill);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    if (frac <= 0) return;
    final w = size.width * frac;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width - w, 0, w, size.height), r),
        Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_CellBar o) =>
      o.frac != frac || o.track != track || o.fill != fill;
}

/// A cell that is a calendar day, 'YYYY-MM-DD', as a date; else null.
DateTime? tableDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  return DateTime(
      int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

/// A day as the chat says it: "Tue 17 Nov", with the year only when it is
/// not [now]'s.
String chatDate(DateTime d, {required DateTime now, AppLocalizations? l}) {
  final s =
      '${weekdayShortName(d.weekday, l)} ${d.day} ${monthShortName(d.month, l)}';
  return d.year == now.year ? s : '$s ${d.year}';
}

bool tableIsRecovery(String header) =>
    RegExp(r'recover|readiness', caseSensitive: false).hasMatch(header);

/// Recovery's colour band for a 0-100 value.
Color trendRecoveryHue(double v) =>
    v >= 67 ? TV.recGreen : (v >= 34 ? TV.recYellow : TV.recRed);

/// The colour the app gives the measure a column header names, or null for
/// one it does not recognise (drawn white).
Color? tableHue(String header) {
  final h = header.toLowerCase();
  bool has(String re) => RegExp(re).hasMatch(h);
  if (tableIsRecovery(h)) return TV.recGreen;
  if (has(r'strain|load|kcal|calor|minutes|\bmin\b|duration|zone')) {
    return C.dialStrain;
  }
  if (has(r'sleep|asleep|deep|rem|bed|nap|efficien')) return C.dialSleep;
  if (has(r'hrv|rmssd')) return C.sleepRem;
  if (has(r'rhr|resting|heart|\bhr\b|bpm|pulse')) return TV.recRed;
  if (has(r'stress')) return C.stressHigh;
  if (has(r'step|distance|km|pace')) return C.stressWarm;
  if (has(r'temp|spo2|oxygen|resp')) return C.stressLow;
  return null;
}

/// The unit every filled cell of a column ends in ("bpm", "%", "ms"), or ''
/// when they differ or carry none.
String tableUnit(List<String> column) {
  String? unit;
  for (final c in column) {
    final t = c.trim();
    if (t.isEmpty) continue;
    final m = RegExp(r'^[-+−]?[\d,]*(?:\.\d+)?\s*([a-zA-Z%°/]{1,6})$')
        .firstMatch(t);
    final u = m?.group(1) ?? '';
    if (u.isEmpty || (unit != null && unit != u)) return '';
    unit = u;
  }
  return unit ?? '';
}
