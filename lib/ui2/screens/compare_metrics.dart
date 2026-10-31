// Compare metrics: two metrics' weeks on ONE chart, each in its own Trend View
// shape — a line for HRV, columns for steps, zones stacked in their colours,
// nights as ranges on a clock — the first read on the left axis and the second
// on the right, each axis in its metric's colour. Two column metrics stand
// side by side in each day's slot; a line runs over any columns. Touching a
// day reads it out for both. A week pager steps back through earlier weeks,
// and a line under the chart says whether the two have moved together over
// the four weeks up to the one shown — only when enough days pair up.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../state/prefs.dart';
import '../ui2.dart';
import 'home_screen.dart' show monthShortName, weekdayShortName;
import 'trend_view.dart';

/// The pair shown until the user picks another.
const kComparePairDefault = ('hrv', 'resting_hr');

/// The saved pair, falling back to [kComparePairDefault] for anything gone.
(String, String) comparePairOf() {
  final parts = Prefs.getString(Prefs.comparePair, '').split(',');
  bool ok(String id) =>
      trendMetricOf(id)?.absent == null && trendMetricOf(id) != null;
  if (parts.length == 2 &&
      ok(parts[0]) &&
      ok(parts[1]) &&
      parts[0] != parts[1]) {
    return (parts[0], parts[1]);
  }
  return kComparePairDefault;
}

/// What a metric's charts are drawn from: its daily figure, and the layers or
/// the nights its shape needs.
typedef CompareData = ({
  Map<String, double> daily,
  List<Map<String, double>>? layers,
  Map<String, ({double bed, double wake})>? spans,
});

/// How two daily series moved together over the days both have: Pearson's r
/// and how many days it rests on. Null under [minDays] paired days, or when
/// either series is flat (r is undefined).
({double r, int n})? compareCorrelation(
  Map<String, double> a,
  Map<String, double> b, {
  required List<String> days,
  int minDays = 10,
}) {
  final xs = <double>[], ys = <double>[];
  for (final d in days) {
    final x = a[d], y = b[d];
    if (x == null || y == null || !x.isFinite || !y.isFinite) continue;
    xs.add(x);
    ys.add(y);
  }
  final n = xs.length;
  if (n < minDays) return null;
  final mx = xs.reduce((p, q) => p + q) / n;
  final my = ys.reduce((p, q) => p + q) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - mx, dy = ys[i] - my;
    sxy += dx * dy;
    sxx += dx * dx;
    syy += dy * dy;
  }
  if (sxx <= 0 || syy <= 0) return null;
  return (r: sxy / math.sqrt(sxx * syy), n: n);
}

/// The relationship in a sentence, for [compareCorrelation]'s result.
String compareSentence(String a, String b, ({double r, int n}) c) {
  final s = c.r.abs();
  final how = s < .2
      ? 'barely moved together'
      : c.r > 0
      ? (s < .5 ? 'tended to rise and fall together' : 'rose and fell together')
      : (s < .5
            ? 'tended to move in opposite directions'
            : 'moved in opposite directions');
  return 'Over these four weeks, $a and $b $how '
      '(r ${c.r < 0 ? '−' : ''}${s.toStringAsFixed(2)}, ${c.n} days).';
}

/// [b], unless its hue is within 30° of [a]'s; then whichever accent sits
/// furthest from [a] on the colour wheel.
Color compareSecondColour(Color a, Color b) {
  double hue(Color c) => HSVColor.fromColor(c).hue;
  double apart(Color x, Color y) {
    final d = (hue(x) - hue(y)).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  if (apart(a, b) >= 30) return b;
  const accents = [C.orange, C.purple, C.teal, C.yellow, C.red];
  return accents.reduce((x, y) => apart(a, x) >= apart(a, y) ? x : y);
}

class CompareMetricsCard extends StatefulWidget {
  final TrendLoader loader;
  final String today;
  final String? firstDay;

  /// The door into Trend View (Home); null where the card already is there.
  final VoidCallback? onOpen;

  /// The pair to start on, for a test; the saved one when null.
  final (String, String)? pair;

  const CompareMetricsCard({
    super.key,
    required this.loader,
    required this.today,
    this.firstDay,
    this.onOpen,
    this.pair,
  });

  @override
  State<CompareMetricsCard> createState() => _CompareMetricsCardState();
}

class _CompareMetricsCardState extends State<CompareMetricsCard> {
  late (String, String) _pair = widget.pair ?? comparePairOf();
  final _data = <String, CompareData>{};

  /// Weeks behind this one.
  int _back = 0;

  /// The day under a finger, on either chart.
  int? _at;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CompareMetricsCard old) {
    super.didUpdateWidget(old);
    // Home reads everything afresh on a pull or a sync: so does the card.
    if (old.loader != widget.loader) {
      _data.clear();
      _load();
    }
  }

  Future<void> _load() async {
    for (final id in [_pair.$1, _pair.$2]) {
      if (_data.containsKey(id)) continue;
      final m = trendMetricOf(id)!;
      final daily = await widget.loader.daily(m);
      final layers = m.kind == TrendKind.stacked || m.kind == TrendKind.dual
          ? await widget.loader.layers(m)
          : null;
      final spans = m.kind == TrendKind.floating
          ? await widget.loader.sleepSpans()
          : null;
      if (!mounted) return;
      setState(() => _data[id] = (daily: daily, layers: layers, spans: spans));
    }
  }

  void _set(int slot, String id) {
    final other = slot == 0 ? _pair.$2 : _pair.$1;
    // Picking the other slot's metric swaps the two.
    final next = id == other
        ? (_pair.$2, _pair.$1)
        : (slot == 0 ? (id, _pair.$2) : (_pair.$1, id));
    setState(() {
      _pair = next;
      _at = null;
    });
    Prefs.setString(Prefs.comparePair, '${next.$1},${next.$2}');
    _load();
  }

  Future<void> _choose(BuildContext c, int slot) async {
    final current = slot == 0 ? _pair.$1 : _pair.$2;
    final id = await AppSheet.show<String>(
      c,
      title: 'COMPARE',
      child: _MetricList(current: current),
    );
    if (id != null && id != current) _set(slot, id);
  }

  String get _end => shiftDay(widget.today, -7 * _back);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final end = _end;
    final first = DateTime.parse(shiftDay(end, -6)), last = DateTime.parse(end);
    final range =
        '${monthShortName(first.month, l)} ${first.day} - '
        '${monthShortName(last.month, l)} ${last.day}';
    final earliest = widget.firstDay;
    final canEarlier =
        earliest == null || shiftDay(end, -7).compareTo(earliest) >= 0;
    final a = trendMetricOf(_pair.$1)!, b = trendMetricOf(_pair.$2)!;
    final da = _data[a.id], db = _data[b.id];
    // Two metrics of one family (HRV and resting HR are both heart blues)
    // would read as one on one chart: the second takes the accent furthest
    // round the colour wheel from the first.
    final ca = trendColorOf(a);
    final cb = compareSecondColour(ca, trendColorOf(b));

    // Four weeks up to the one shown, the day in progress left out.
    final corrDays = [
      for (var i = 27; i >= 0; i--)
        if (shiftDay(end, -i) != widget.today) shiftDay(end, -i),
    ];
    final corr = da == null || db == null
        ? null
        : compareCorrelation(da.daily, db.daily, days: corrDays);
    final paired = da == null || db == null
        ? 0
        : corrDays
              .where((d) => da.daily[d] != null && db.daily[d] != null)
              .length;

    return Container(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x4),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(
            onTap: widget.onOpen,
            semanticLabel: widget.onOpen == null
                ? 'Compare metrics'
                : 'Open Compare metrics in Trend View',
            child: SizedBox(
              height: S.tap,
              child: Row(
                children: [
                  Icon(LucideIcons.gitCompareArrows, size: I.md, color: p.ink3),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                      'COMPARE METRICS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.caps.copyWith(color: p.ink),
                    ),
                  ),
                  if (widget.onOpen != null)
                    BoldChevron(
                      left: false,
                      color: p.ink3,
                      height: S.x3 + S.half,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: S.x2),
          Row(
            children: [
              Expanded(
                child: _Chip(m: a, onTap: () => _choose(c, 0)),
              ),
              const SizedBox(width: S.x2),
              Expanded(
                child: _Chip(m: b, onTap: () => _choose(c, 1)),
              ),
            ],
          ),
          const SizedBox(height: S.x1),
          Align(
            alignment: Alignment.centerRight,
            child: WindowPager(
              range,
              onEarlier: canEarlier
                  ? () => setState(() {
                      _back++;
                      _at = null;
                    })
                  : null,
              onLater: _back == 0
                  ? null
                  : () => setState(() {
                      _back--;
                      _at = null;
                    }),
            ),
          ),
          const SizedBox(height: S.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Readout(
                  m: a,
                  data: da,
                  color: ca,
                  end: end,
                  today: widget.today,
                  firstDay: widget.firstDay,
                  at: _at,
                ),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: _Readout(
                  m: b,
                  data: db,
                  color: cb,
                  end: end,
                  today: widget.today,
                  firstDay: widget.firstDay,
                  at: _at,
                  right: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          if (da == null || db == null)
            const SizedBox(height: _CompareChart.height)
          else
            _CompareChart(
              a: compareSeriesOf(a, da, end: end, firstDay: widget.firstDay),
              b: compareSeriesOf(b, db, end: end, firstDay: widget.firstDay),
              ca: ca,
              cb: cb,
              end: end,
              onScrub: (i) => setState(() => _at = i),
            ),
          const SizedBox(height: S.x4),
          Container(height: S.hair, color: p.line),
          const SizedBox(height: S.x3),
          Text(
            corr == null
                ? (da == null || db == null
                      ? ' '
                      : paired < 10
                      ? 'Fewer than 10 days with both in these four weeks: '
                            'too few to say how they move together.'
                      : 'One of them held steady these four weeks, so there '
                            'is no movement to compare.')
                : compareSentence(_short(a), _short(b), corr),
            style: F.cap.copyWith(color: p.ink2, height: 1.45),
          ),
          if (corr != null) ...[
            const SizedBox(height: S.x1),
            Text(
              'Moving together is not cause and effect.',
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
        ],
      ),
    );
  }

  static String _short(TrendMetric m) => switch (m.id) {
    'hrv' => 'HRV',
    'resting_hr' => 'resting HR',
    'resp_rate' => 'respiratory rate',
    'vo2max' => 'VO₂ max',
    _ => m.title.toLowerCase(),
  };
}

/// One metric's figure over the chart: its name in its colour, the week's
/// figure (or the touched day's), and what that figure is. The first metric
/// reads from the left, the second from the right, as their axes do.
class _Readout extends StatelessWidget {
  final TrendMetric m;
  final CompareData? data;
  final Color color;
  final String end, today;
  final String? firstDay;
  final int? at;
  final bool right;

  const _Readout({
    required this.m,
    required this.data,
    required this.color,
    required this.end,
    required this.today,
    required this.firstDay,
    required this.at,
    this.right = false,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = data;
    final bars = d == null
        ? const <TrendBar>[]
        : trendBars(m, d.daily, TrendRange.week, end, firstDay: firstDay);
    final sel = at != null && at! < bars.length ? bars[at!] : null;
    // The week's figure as Trend View states it: a weekly metric's total,
    // anything else's average with the day still in progress left out.
    double? figure;
    if (d != null) {
      if (m.weekly) {
        final vs = [for (final b in bars) ?b.v];
        figure = vs.isEmpty ? null : vs.fold<double>(0, (x, y) => x + y);
      } else {
        figure = trendAverage(
          trendBars(
            m,
            d.daily,
            TrendRange.week,
            end,
            firstDay: firstDay,
            skip: today,
          ),
        );
      }
    }
    final v = sel != null ? sel.v : figure;
    final dt = sel == null ? null : DateTime.parse(sel.to);
    final caption = dt != null
        ? '${weekdayShortName(dt.weekday, l)}, ${monthShortName(dt.month, l)} ${dt.day}'
        : (m.weekly ? 'Weekly total' : 'Average');
    return Column(
      crossAxisAlignment: right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: S.x2,
              height: S.x2,
              decoration: BoxDecoration(
                color: p.fill(color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: S.x2),
            Flexible(
              child: Text(
                compareChipName(m).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.over.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x1),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: d == null ? ' ' : trendFormat(m, v),
                style: F.num(
                  F.n24,
                ).copyWith(color: p.ink, fontWeight: FontWeight.w700),
              ),
              if (v != null && m.unit != null)
                TextSpan(
                  text: ' ${m.unit}',
                  style: F.cap.copyWith(color: p.ink3),
                ),
            ],
          ),
          maxLines: 1,
        ),
        Text(caption.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
      ],
    );
  }
}

/// How a metric is drawn on the shared chart: its own Trend View shape.
enum CompareShape { line, columns, stacked, ranges }

/// One metric's week, ready for the shared chart: a value per day (a stack of
/// layers, or a night's bed-to-wake range, where that is the metric's shape),
/// and the axis it is read on.
class CompareSeries {
  final TrendMetric m;
  final CompareShape shape;
  final List<double?> values;
  final List<List<double>?> stacks;
  final List<({double from, double to})?> ranges;

  /// The layers' colours, for a stacked metric.
  final List<Color> layerColours;
  final ({double lo, double hi, List<double> ticks}) axis;

  const CompareSeries({
    required this.m,
    required this.shape,
    required this.values,
    required this.axis,
    this.stacks = const [],
    this.ranges = const [],
    this.layerColours = const [],
  });

  bool get bars => shape != CompareShape.line;

  /// Nights run down the clock: bedtime above wake.
  bool get down => shape == CompareShape.ranges;

  bool get empty => shape == CompareShape.ranges
      ? ranges.every((r) => r == null)
      : values.every((v) => v == null);

  String tick(double t) =>
      shape == CompareShape.ranges ? trendClockText(t) : trendTickText(m, t);

  /// Where [v] sits in [plot] on this series' axis.
  double y(double v, Rect plot) {
    final span = axis.hi - axis.lo;
    final f = span <= 0 ? 0.0 : ((v - axis.lo) / span).clamp(0.0, 1.0);
    return down ? plot.top + f * plot.height : plot.bottom - f * plot.height;
  }
}

/// [m]'s week ending [end], in the shape Trend View draws it in.
CompareSeries compareSeriesOf(
  TrendMetric m,
  CompareData d, {
  required String end,
  String? firstDay,
}) {
  final bars = trendBars(m, d.daily, TrendRange.week, end, firstDay: firstDay);
  final values = [for (final b in bars) b.v];
  final spans = d.spans;
  if (m.kind == TrendKind.floating && spans != null) {
    final ranges = <({double from, double to})?>[
      for (final b in bars)
        spans[b.to] == null
            ? null
            : (from: spans[b.to]!.bed, to: spans[b.to]!.wake),
    ];
    return CompareSeries(
      m: m,
      shape: CompareShape.ranges,
      values: values,
      ranges: ranges,
      axis: trendClockAxis(ranges),
    );
  }
  final layers = d.layers;
  if (m.kind == TrendKind.stacked && layers != null && layers.isNotEmpty) {
    final layerBars = [
      for (final lm in layers)
        trendBars(m, lm, TrendRange.week, end, firstDay: firstDay),
    ];
    final stacks = <List<double>?>[];
    final totals = <double?>[];
    for (var i = 0; i < bars.length; i++) {
      final parts = [for (final lb in layerBars) lb[i].v];
      if (parts.every((v) => v == null)) {
        stacks.add(null);
        totals.add(null);
      } else {
        final ps = [for (final v in parts) v ?? 0.0];
        stacks.add(ps);
        totals.add(ps.fold<double>(0, (a, b) => a + b));
      }
    }
    return CompareSeries(
      m: m,
      shape: CompareShape.stacked,
      values: totals,
      stacks: stacks,
      layerColours: trendLayerColours(m),
      axis: trendAxis(m, [for (final t in totals) ?t], line: false),
    );
  }
  return CompareSeries(
    m: m,
    shape: m.line ? CompareShape.line : CompareShape.columns,
    values: values,
    axis: trendAxis(m, [for (final v in values) ?v], line: m.line),
  );
}

/// The two series on one plot: [a] on the left axis, [b] on the right.
class _CompareChart extends StatelessWidget {
  static const height = S.x16 * 3 + S.x10;
  static const _inset = EdgeInsets.fromLTRB(S.x10, S.x3, S.x10, S.x8);

  final CompareSeries a, b;
  final Color ca, cb;
  final String end;
  final ValueChanged<int?> onScrub;

  const _CompareChart({
    required this.a,
    required this.b,
    required this.ca,
    required this.cb,
    required this.end,
    required this.onScrub,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final days = [
      for (var i = 6; i >= 0; i--) DateTime.parse(shiftDay(end, -i)),
    ];
    String say(CompareSeries s, int i) {
      if (s.shape == CompareShape.ranges) {
        final r = s.ranges[i];
        return r == null
            ? 'no night'
            : '${trendClockText(r.from)} to ${trendClockText(r.to)}';
      }
      final v = s.values[i];
      return v == null ? 'not recorded' : trendFormat(s.m, v);
    }

    if (a.empty && b.empty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Nothing recorded for either this week.',
            style: F.num(F.cap).copyWith(color: p.ink3),
          ),
        ),
      );
    }
    return ScrubArea(
      count: 7,
      inset: _inset,
      height: height,
      onScrub: onScrub,
      label: 'Compare ${a.m.title} and ${b.m.title}',
      describe: (i) =>
          '${weekdayShortName(days[i].weekday, l)} ${days[i].day}: '
          '${a.m.title} ${say(a, i)}, ${b.m.title} ${say(b, i)}',
      builder: (c, at) => CustomPaint(
        size: Size.infinite,
        painter: _ComparePainter(
          a: a,
          b: b,
          ca: p.fill(ca),
          cb: p.fill(cb),
          line: p.line,
          card: p.card,
          xLabels: [
            for (final d in days) '${weekdayShortName(d.weekday, l)}\n${d.day}',
          ],
          axisA: F.num(F.over).copyWith(color: p.on(ca)),
          axisB: F.num(F.over).copyWith(color: p.on(cb)),
          xStyle: F.over.copyWith(color: p.ink3),
          xOn: F.over.copyWith(color: p.ink, fontWeight: FontWeight.w800),
          at: at,
          inset: _inset,
        ),
      ),
    );
  }
}

class _ComparePainter extends CustomPainter {
  final CompareSeries a, b;
  final Color ca, cb, line, card;
  final List<String> xLabels;
  final TextStyle axisA, axisB, xStyle, xOn;
  final int? at;
  final EdgeInsets inset;

  _ComparePainter({
    required this.a,
    required this.b,
    required this.ca,
    required this.cb,
    required this.line,
    required this.card,
    required this.xLabels,
    required this.axisA,
    required this.axisB,
    required this.xStyle,
    required this.xOn,
    required this.at,
    required this.inset,
  });

  void _text(
    Canvas cv,
    String s,
    TextStyle st,
    Offset o, {
    double ax = 0,
    double ay = .5,
    TextAlign align = TextAlign.left,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(cv, o - Offset(tp.width * ax, tp.height * ay));
  }

  @override
  void paint(Canvas cv, Size size) {
    final plot = plotRect(size, inset);
    const n = 7;
    final slot = plot.width / n;
    double cx(int i) => plot.left + (i + .5) * slot;

    // Gridlines on the left metric's ticks (the right one's when the left has
    // nothing this week); each axis labelled in its own metric's colour.
    final grid = a.empty ? b : a;
    final gp = Paint()
      ..color = line
      ..strokeWidth = S.hair;
    for (final t in grid.axis.ticks) {
      final y = grid.y(t, plot);
      cv.drawLine(Offset(plot.left, y), Offset(plot.right, y), gp);
    }
    if (!a.empty) {
      for (final t in a.axis.ticks) {
        _text(
          cv,
          a.tick(t),
          axisA,
          Offset(plot.left - S.x2, a.y(t, plot)),
          ax: 1,
        );
      }
    }
    if (!b.empty) {
      for (final t in b.axis.ticks) {
        _text(cv, b.tick(t), axisB, Offset(plot.right + S.x2, b.y(t, plot)));
      }
    }

    // Columns: side by side when both are columns, centred when one is.
    final cols = [if (a.bars && !a.empty) a, if (b.bars && !b.empty) b];
    final w = slot * (cols.length == 2 ? .3 : .44);
    final gap = cols.length == 2 ? S.half : 0.0;
    final r = Radius.circular(math.min(w / 2, R.sm));
    for (final (k, s) in cols.indexed) {
      final colour = identical(s, a) ? ca : cb;
      final dx = cols.length == 2
          ? (k == 0 ? -(w / 2 + gap) : w / 2 + gap)
          : 0.0;
      Rect rect(double x, double y0, double y1) => Rect.fromLTRB(
        x - w / 2,
        math.min(y0, y1),
        x + w / 2,
        math.max(y0, y1),
      );
      for (var i = 0; i < n; i++) {
        final x = cx(i) + dx;
        switch (s.shape) {
          case CompareShape.ranges:
            final g = s.ranges[i];
            if (g == null) continue;
            cv.drawRRect(
              RRect.fromRectAndRadius(
                rect(x, s.y(g.from, plot), s.y(g.to, plot)),
                r,
              ),
              Paint()..color = colour,
            );
          case CompareShape.stacked:
            final st = s.stacks[i];
            if (st == null) continue;
            final base = s.y(math.max(s.axis.lo, 0), plot);
            final total = st.fold<double>(0, (x, y) => x + y);
            cv.save();
            cv.clipRRect(
              RRect.fromRectAndCorners(
                rect(x, s.y(total, plot), base),
                topLeft: r,
                topRight: r,
              ),
            );
            var acc = 0.0;
            for (final (j, part) in st.indexed) {
              final y0 = s.y(acc, plot), y1 = s.y(acc + part, plot);
              acc += part;
              cv.drawRect(
                rect(x, y1, y0),
                Paint()
                  ..color = j < s.layerColours.length
                      ? s.layerColours[j]
                      : colour,
              );
            }
            cv.restore();
          case CompareShape.columns:
          case CompareShape.line:
            final v = s.values[i];
            if (v == null) continue;
            final base = s.y(math.max(s.axis.lo, 0), plot);
            cv.drawRRect(
              RRect.fromRectAndCorners(
                rect(x, s.y(v, plot), base),
                topLeft: r,
                topRight: r,
              ),
              Paint()..color = colour,
            );
        }
      }
    }

    // Lines over any columns: a break where a day is missing, a dot on every
    // day that has one.
    for (final s in [a, b]) {
      if (s.shape != CompareShape.line || s.empty) continue;
      final colour = identical(s, a) ? ca : cb;
      final path = Path();
      var pen = false;
      for (var i = 0; i < n; i++) {
        final v = s.values[i];
        if (v == null) {
          pen = false;
          continue;
        }
        final pt = Offset(cx(i), s.y(v, plot));
        if (pen) {
          path.lineTo(pt.dx, pt.dy);
        } else {
          path.moveTo(pt.dx, pt.dy);
        }
        pen = true;
      }
      cv.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = S.half + S.hair
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = colour,
      );
      for (var i = 0; i < n; i++) {
        final v = s.values[i];
        if (v == null) continue;
        final pt = Offset(cx(i), s.y(v, plot));
        cv.drawCircle(pt, S.x1 + S.hair, Paint()..color = card);
        cv.drawCircle(pt, S.x1 - S.hair, Paint()..color = colour);
      }
    }

    for (var i = 0; i < n; i++) {
      _text(
        cv,
        xLabels[i],
        i == at ? xOn : xStyle,
        Offset(cx(i), plot.bottom + S.x2),
        ax: .5,
        ay: 0,
        align: TextAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(_ComparePainter o) =>
      o.a != a || o.b != b || o.at != at || o.ca != ca || o.cb != cb;
}

/// A metric's name short enough for half a row.
String compareChipName(TrendMetric m) => switch (m.id) {
  'hrv' => 'HRV',
  'resting_hr' => 'Resting HR',
  'avg_hr' => 'Average HR',
  'resp_rate' => 'Resp. rate',
  'sleep_perf' => 'Sleep perf.',
  'hvn_hours' => 'Hours vs. need',
  'hvn_pct' => 'Hours vs. need %',
  'restorative_pct' => 'Restorative %',
  'restorative_hours' => 'Restorative h',
  'zones_13' => 'Zones 1-3',
  'zones_45' => 'Zones 4-5',
  'zones_all' => 'HR zones',
  'strength_time' => 'Strength time',
  'volume_load' => 'Volume load',
  'vo2max' => 'VO₂ max',
  _ => m.title,
};

/// A slot's metric: its colour, its name, tap to change.
class _Chip extends StatelessWidget {
  final TrendMetric m;
  final VoidCallback onTap;
  const _Chip({required this.m, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '${m.title}. Change',
      child: Container(
        height: S.tap,
        padding: const EdgeInsets.symmetric(horizontal: S.x3),
        decoration: BoxDecoration(color: p.card2, borderRadius: R.rLg),
        child: Row(
          children: [
            Icon(m.icon, size: I.md, color: trendColorOf(m)),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text(
                compareChipName(m),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.cap.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: I.sm, color: p.ink3),
          ],
        ),
      ),
    );
  }
}

/// Every metric that can be drawn, by group; pops the chosen id.
class _MetricList extends StatelessWidget {
  final String current;
  const _MetricList({required this.current});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final shown = [
      for (final m in kTrendCatalogue)
        if (m.absent == null) m,
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .6),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: S.x4),
        children: [
          for (final g in TrendGroup.values)
            if (shown.any((m) => m.group == g)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x1),
                child: Text(
                  trendGroupName(g).toUpperCase(),
                  style: F.over.copyWith(
                    color: p.ink3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final m in shown)
                if (m.group == g)
                  Pressable(
                    onTap: () => Navigator.of(c).pop(m.id),
                    semanticLabel: m.title,
                    child: Container(
                      height: S.tap + S.x2,
                      margin: const EdgeInsets.symmetric(horizontal: S.x2),
                      padding: const EdgeInsets.symmetric(horizontal: S.x3),
                      decoration: BoxDecoration(
                        color: m.id == current ? p.card2 : null,
                        borderRadius: R.rLg,
                      ),
                      child: Row(
                        children: [
                          Icon(m.icon, size: I.md, color: trendColorOf(m)),
                          const SizedBox(width: S.x3),
                          Expanded(
                            child: Text(
                              m.title,
                              style: F.body.copyWith(color: p.ink),
                            ),
                          ),
                          if (m.id == current)
                            Icon(LucideIcons.check, size: I.md, color: p.ink),
                        ],
                      ),
                    ),
                  ),
            ],
        ],
      ),
    );
  }
}
