// Scrubbing: drag a finger along a chart and the point under it is read out
// big, with a soft column behind it. Every chart with a point per day or per
// minute goes through [ScrubArea], so the gesture, the guide and the geometry
// are one implementation. The chart paints itself; the area only reads the
// finger and draws the guide, and both measure the plot with [plotRect], so
// the guide and the drawn point cannot disagree about where a point is.
//
// Lifting the finger returns the chart to rest. Nothing is kept selected, so
// the number a screen shows at rest is always the one it would show by default.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'grammar.dart';
import 'theme.dart';

/// The plot inside a chart's box, after its [EdgeInsets]. The painter and the
/// guide both read it, which is the whole reason this is a function.
Rect plotRect(Size s, EdgeInsets inset) => Rect.fromLTRB(
    inset.left, inset.top, math.max(inset.left, s.width - inset.right),
    math.max(inset.top, s.height - inset.bottom));

/// The point index under a horizontal position, in a plot of [count] points.
/// Bars sit in the middle of equal slots; lines sit on the edges, so index 0
/// is the left edge and the last index the right one.
int scrubIndexAt(double x, Rect plot, int count, {required bool slots}) {
  if (count <= 0 || plot.width <= 0) return 0;
  final f = ((x - plot.left) / plot.width).clamp(0.0, 1.0);
  final i = slots
      ? (f * count).floor()
      : (f * (count - 1)).round();
  return i.clamp(0, count - 1);
}

/// Where point [i] sits horizontally.
double scrubXOf(int i, Rect plot, int count, {required bool slots}) => slots
    ? plot.left + (i + .5) * plot.width / count
    : plot.left + (count > 1 ? i / (count - 1) : .5) * plot.width;

/// A chart that reads a finger. [builder] paints the chart and receives the
/// index being touched (null at rest). The area draws the guide over it.
class ScrubArea extends StatefulWidget {
  /// How many points the chart draws, left to right.
  final int count;

  /// Bars sit in slots ([scrubXOf] centres them); lines sit on the edges.
  final bool slots;

  /// The space around the plot: axis labels, value tags, the x-label band.
  final EdgeInsets inset;

  /// The height of the whole area, insets included.
  final double height;

  /// Paints the chart for the touched index, or for rest when it is null.
  final Widget Function(BuildContext context, int? at) builder;

  /// Reports the index under the finger, and null when the finger lifts.
  final ValueChanged<int?> onScrub;

  /// Where point [i]'s dot sits, as a fraction of the plot height from the
  /// bottom (0 = bottom, 1 = top). Null for no dot at that point.
  final double? Function(int i)? dotAt;

  /// What the chart is called, and what point [i] reads as, for a screen reader.
  final String label;
  final String Function(int i) describe;

  /// The column behind the touched point, when it is not one point wide (a
  /// whole month). Null takes the default width.
  final ({double left, double right})? Function(int at, Rect plot)? bandSpan;

  /// Two fingers on the chart, to zoom it.
  final PinchCallback? onPinch;

  const ScrubArea({
    super.key,
    required this.count,
    required this.builder,
    required this.onScrub,
    this.slots = true,
    this.inset = EdgeInsets.zero,
    this.height = 200,
    this.dotAt,
    this.label = 'Chart',
    this.describe = _describeIndex,
    this.bandSpan,
    this.onPinch,
  });

  @override
  State<ScrubArea> createState() => _ScrubAreaState();
}

class _ScrubAreaState extends State<ScrubArea> {
  int? _at;

  void _touch(double x, Rect plot) {
    if (widget.count <= 0) return;
    final i = scrubIndexAt(x, plot, widget.count, slots: widget.slots);
    if (i == _at) return;
    setState(() => _at = i);
    widget.onScrub(i);
  }

  void _lift() {
    if (_at == null) return;
    setState(() => _at = null);
    widget.onScrub(null);
  }

  _ColumnPainter _bandFor(int at, Rect plot, P p) {
    final x = scrubXOf(at, plot, widget.count, slots: widget.slots);
    final span = widget.bandSpan?.call(at, plot);
    final width = span != null
        ? span.right - span.left
        : widget.slots
            ? math.min(plot.width / widget.count * .8, S.x12)
            : S.x4;
    return _ColumnPainter(
      x: span != null ? (span.left + span.right) / 2 : x,
      width: width,
      top: math.max(0.0, plot.top - S.x3),
      tint: p.ink.withValues(alpha: .1),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (c, box) {
        final size = Size(box.maxWidth, widget.height);
        final plot = plotRect(size, widget.inset);
        final at = _at;
        return Scrubber(
          value: at == null
              ? null
              : scrubXOf(at, plot, widget.count, slots: widget.slots) /
                  size.width,
          onChanged: (f) => _touch(f * size.width, plot),
          onLift: _lift,
          yieldToScroll: true,
          onPinch: widget.onPinch,
          label: widget.label,
          describe: (f) => widget.describe(scrubIndexAt(f * size.width, plot,
              widget.count, slots: widget.slots)),
          child: Stack(children: [
            // The column the finger is on, behind the chart so its bars and
            // lines sit on it.
            if (at != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _bandFor(at, plot, p),
                  ),
                ),
              ),
            Positioned.fill(child: widget.builder(c, at)),
            if (at != null && widget.dotAt?.call(at) != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DotPainter(
                      x: scrubXOf(at, plot, widget.count, slots: widget.slots),
                      plot: plot,
                      dot: widget.dotAt!.call(at)!,
                      ink: p.ink,
                      ring: p.bg,
                    ),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

String _describeIndex(int i) => '${i + 1}';

/// The soft rounded column behind the touched point, from just above the plot
/// to the foot of the chart (so it takes in the label under the point).
class _ColumnPainter extends CustomPainter {
  final double x, width, top;
  final Color tint;

  _ColumnPainter(
      {required this.x, required this.width, required this.top, required this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(x - width / 2, top, x + width / 2, size.height),
          const Radius.circular(S.x1)),
      Paint()..color = tint,
    );
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      old.x != x || old.width != width || old.top != top || old.tint != tint;
}

/// The dot on the touched point of a line.
class _DotPainter extends CustomPainter {
  final double x;
  final Rect plot;
  final double dot;
  final Color ink, ring;

  _DotPainter({
    required this.x,
    required this.plot,
    required this.dot,
    required this.ink,
    required this.ring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = plot.bottom - dot.clamp(0.0, 1.0) * plot.height;
    canvas.drawCircle(Offset(x, cy), S.x2 * .75 + 2, Paint()..color = ring);
    canvas.drawCircle(Offset(x, cy), S.x2 * .75, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.x != x || old.dot != dot || old.plot != plot || old.ink != ink || old.ring != ring;
}

/// The readout that goes big above a chart: a small caption (the average, or
/// the date under the finger), the number, and anything that qualifies it.
class ScrubReadout extends StatelessWidget {
  final String caption;
  final String value;

  /// What the number is measured in, written small after it.
  final String? unit;
  final Widget? under;

  /// The number's size. The trend screen's readout uses the big style; the
  /// cards on the strain screen use the smaller one.
  final bool big;

  const ScrubReadout({
    super.key,
    required this.caption,
    required this.value,
    this.unit,
    this.under,
    this.big = true,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(caption.toUpperCase(),
            style: F.num(F.over).copyWith(color: p.ink2)),
        const SizedBox(height: S.half),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: (big ? F.n34 : F.n24)
                      .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              if (unit != null) ...[
                const SizedBox(width: S.x1),
                Text(unit!,
                    style: (big ? F.head : F.cap)
                        .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
        if (under != null) ...[const SizedBox(height: S.x2), under!],
      ],
    );
  }
}

/// A short white line across columns [from]..[to] (both included) at [v], with
/// [text] over it: a month's average on a six-month chart.
typedef ColumnMark = ({int from, int to, double v, String text});

/// One column chart, scrubbable: bars (or stacks of bars) over gridlines, a
/// value above each bar, the day or month under it, and an optional dashed
/// average with its tag.
class ScrubColumns extends StatelessWidget {
  /// One value per bar; null draws no bar.
  final List<double?> values;

  /// Per bar, the segments to stack from the bottom. When given, the bar is
  /// the sum of its segments and [segmentColors] colours them in order.
  final List<List<double>?>? stacks;
  final List<Color>? segmentColors;

  /// One x label per bar. Two lines are allowed ("Apr\n16"); '' draws none.
  final List<String> xLabels;

  /// One value label per bar, drawn above it. '' draws none.
  final List<String> valueLabels;

  /// The axis, in the values' own units.
  final double lo, hi;
  final List<double> ticks;
  final String Function(double) tickText;

  /// The subtle dashed average behind the bars, or null for none.
  final double? avg;

  /// White average lines over stretches of columns, each with its figure.
  final List<ColumnMark> marks;

  /// The colour of the figure over each bar, when it should not be the bar's.
  final Color? labelColor;

  final Color color;

  /// Per-bar colour from the bar's value (the recovery traffic light).
  final Color Function(int i, double v)? colorOf;

  /// The bar to mark with a column band: the day the screen is about.
  final int? highlight;

  final ValueChanged<int?> onScrub;
  final double height;

  /// What the chart is called, and what each bar reads as, for a screen reader.
  final String label;
  final String Function(int i)? describe;

  /// The width kept for the axis labels. Zero for a card with none.
  final double gutter;

  const ScrubColumns({
    super.key,
    required this.values,
    required this.xLabels,
    required this.lo,
    required this.hi,
    required this.ticks,
    required this.tickText,
    required this.color,
    required this.onScrub,
    this.stacks,
    this.segmentColors,
    this.valueLabels = const [],
    this.avg,
    this.marks = const [],
    this.labelColor,
    this.colorOf,
    this.highlight,
    this.height = 200,
    this.gutter = S.x10,
    this.label = 'Chart',
    this.describe,
  });

  static const _band = S.x8;
  static const _top = S.x6;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final inset = EdgeInsets.fromLTRB(gutter, _top, 0, _band);
    return ScrubArea(
      count: values.length,
      slots: true,
      inset: inset,
      height: height,
      onScrub: onScrub,
      label: label,
      describe: describe ?? _describeIndex,
      builder: (c, at) => CustomPaint(
        size: Size.infinite,
        painter: _ColumnsPainter(
          p: p,
          values: values,
          stacks: stacks,
          segmentColors: segmentColors,
          xLabels: xLabels,
          valueLabels: valueLabels,
          lo: lo,
          hi: hi,
          ticks: ticks,
          tickText: tickText,
          avg: avg,
          marks: marks,
          labelColor: labelColor,
          color: color,
          colorOf: colorOf,
          highlight: highlight,
          at: at,
          inset: inset,
        ),
      ),
    );
  }
}

class _ColumnsPainter extends CustomPainter {
  final P p;
  final List<double?> values;
  final List<List<double>?>? stacks;
  final List<Color>? segmentColors;
  final List<String> xLabels, valueLabels;
  final double lo, hi;
  final List<double> ticks;
  final String Function(double) tickText;
  final double? avg;
  final List<ColumnMark> marks;
  final Color? labelColor;
  final Color color;
  final Color Function(int i, double v)? colorOf;
  final int? highlight, at;
  final EdgeInsets inset;

  _ColumnsPainter({
    required this.p,
    required this.values,
    required this.stacks,
    required this.segmentColors,
    required this.xLabels,
    required this.valueLabels,
    required this.lo,
    required this.hi,
    required this.ticks,
    required this.tickText,
    required this.avg,
    required this.marks,
    required this.labelColor,
    required this.color,
    required this.colorOf,
    required this.highlight,
    required this.at,
    required this.inset,
  });

  TextPainter _text(String s, TextStyle style, {double? width, TextAlign align = TextAlign.center}) =>
      TextPainter(
        text: TextSpan(text: s, style: style),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width ?? double.infinity);

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final span = hi - lo;
    if (n == 0 || span <= 0) return;
    final r = plotRect(size, inset);
    double yOf(double v) => r.bottom - (v - lo) / span * r.height;
    final slot = r.width / n;
    // A week's bars are wide, a month's narrow, and both sit centred in
    // their slot.
    final bw = slot * (n <= 4 ? .62 : n <= 8 ? .38 : .56);

    // Gridlines and their values, in the gutter.
    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = yOf(t);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      if (inset.left <= 0) continue;
      final tp = _text(tickText(t), F.num(F.over).copyWith(color: p.ink3, fontWeight: FontWeight.w600),
          width: inset.left - S.x2, align: TextAlign.right);
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    // The column band behind the day the screen is about.
    final hl = highlight;
    if (hl != null && hl >= 0 && hl < n) {
      final band = RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + hl * slot + slot * .12, r.top - S.x2,
            slot * .76, r.height + S.x2),
        const Radius.circular(R.sm),
      );
      canvas.drawRRect(band, Paint()..color = p.ink.withValues(alpha: .08));
    }

    // The average sits behind the bars: dashed, faint, and unlabelled.
    final a = avg;
    if (a != null && a >= lo && a <= hi) {
      final y = yOf(a);
      final dash = Paint()
        ..color = p.ink.withValues(alpha: .28)
        ..strokeWidth = 1;
      for (var x = r.left; x < r.right; x += S.x2) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + S.x1, r.right), y), dash);
      }
    }

    final zero = yOf(lo > 0 ? lo : 0);
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = r.left + i * slot + (slot - bw) / 2;
      final base = colorOf?.call(i, v) ?? color;
      final dimmed = at != null && at != i;
      final stack = stacks?[i];
      if (stack != null && segmentColors != null) {
        // Bottom to top, each segment its own colour, rounded, with a sliver
        // of the page between one segment and the next.
        final parts = <(Rect, Color)>[];
        var from = zero;
        for (var s = 0; s < stack.length && s < segmentColors!.length; s++) {
          final top = yOf(lo + stack.take(s + 1).fold<double>(0, (a, b) => a + b));
          if ((from - top).abs() >= .5) {
            final c = dimmed ? Color.lerp(segmentColors![s], p.bg, .72)! : segmentColors![s];
            parts.add((Rect.fromLTRB(x, math.min(top, from), x + bw, math.max(top, from)), c));
          }
          from = top;
        }
        const gap = 1.5;
        for (var k = 0; k < parts.length; k++) {
          final isBottom = k == 0, isTop = k == parts.length - 1;
          var r0 = parts[k].$1;
          r0 = Rect.fromLTRB(r0.left, r0.top + (isTop ? 0 : gap / 2),
              r0.right, r0.bottom - (isBottom ? 0 : gap / 2));
          if (r0.height < 1) continue;
          final rad = Radius.circular(math.min(math.min(3.0, bw / 3), r0.height / 2));
          canvas.drawRRect(
            RRect.fromRectAndCorners(r0,
                topLeft: rad,
                topRight: rad,
                bottomLeft: isBottom ? Radius.zero : rad,
                bottomRight: isBottom ? Radius.zero : rad),
            Paint()..color = parts[k].$2,
          );
        }
      } else {
        final y = yOf(v);
        final c = dimmed ? Color.lerp(base, p.bg, .72)! : base;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(x, math.min(y, zero), x + bw, math.max(y, zero)),
            topLeft: const Radius.circular(R.sm / 3),
            topRight: const Radius.circular(R.sm / 3),
          ),
          Paint()..color = c,
        );
      }
      if (i < valueLabels.length && valueLabels[i].isNotEmpty) {
        final top = stack != null
            ? yOf(lo + stack.fold<double>(0, (a, b) => a + b))
            : yOf(v);
        final tp = _text(valueLabels[i], F.num(F.cap).copyWith(
          color: at == i ? p.ink : (labelColor ?? base),
          fontWeight: FontWeight.w700,
        ), width: slot * 2);
        tp.paint(canvas, Offset(x + bw / 2 - tp.width / 2, top - tp.height - S.half));
      }
    }

    // Each month's average, a white line over its columns with the figure on it.
    for (final m in marks) {
      if (m.v < lo || m.v > hi) continue;
      final y = yOf(m.v);
      final x0 = r.left + m.from * slot + S.half, x1 = r.left + (m.to + 1) * slot - S.half;
      canvas.drawLine(
          Offset(x0, y),
          Offset(x1, y),
          Paint()
            ..color = p.ink
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round);
      if (x1 - x0 < S.x10) continue;
      final tp = _text(m.text, F.num(F.cap).copyWith(color: p.ink, fontWeight: FontWeight.w700));
      final c = (x0 + x1) / 2;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(c, y - S.x2 - tp.height / 2),
                  width: tp.width + S.x2,
                  height: tp.height + S.x1),
              const Radius.circular(R.sm)),
          Paint()..color = p.bg.withValues(alpha: .55));
      tp.paint(canvas, Offset(c - tp.width / 2, y - S.x2 - tp.height));
    }

    // The x labels, in the band under the plot. The touched day is bolder.
    for (var i = 0; i < n && i < xLabels.length; i++) {
      if (xLabels[i].isEmpty) continue;
      final focus = i == at || i == highlight;
      final tp = _text(
        xLabels[i],
        F.num(F.over).copyWith(
          color: focus ? p.ink : p.ink3,
          fontWeight: focus ? FontWeight.w800 : FontWeight.w600,
          height: 1.15,
        ),
        width: math.max(slot, S.x12),
      );
      tp.paint(canvas, Offset(r.left + (i + .5) * slot - tp.width / 2, r.bottom + S.x1));
    }
  }

  @override
  bool shouldRepaint(_ColumnsPainter old) => true;
}

/// Draws on a [ScrubLine] with its own geometry: the plot, where point `i`
/// sits across, and where a value sits down.
typedef ScrubPaint = void Function(
    Canvas canvas, Rect plot, double Function(int i) xOf, double Function(double v) yOf);

/// A line chart you can scrub: a point per day (ring markers, the value above
/// each) or a point per minute (a plain line), with an optional faint band for
/// a typical range, a subtle average behind the line, and a soft fill under it.
class ScrubLine extends StatelessWidget {
  /// One value per point; null is a gap, never a zero.
  final List<double?> values;

  /// One x label per point; '' draws none. Two lines are allowed.
  final List<String> xLabels;

  /// One value label per point, drawn above its marker. '' draws none.
  final List<String> valueLabels;

  final double lo, hi;
  final List<double> ticks;
  final String Function(double) tickText;

  /// The subtle dashed average behind the line, or null for none.
  final double? avg;

  /// A typical range, drawn as a band behind the line.
  final ({double lo, double hi})? band;

  final Color color;

  /// A ring at every point. Off for a line of hundreds of points.
  final bool markers;

  /// Points sit in the middle of equal slots (a day each) rather than running
  /// edge to edge (a minute each).
  final bool slots;

  /// The slot marked with a column band: the day the screen is about.
  final int? highlight;

  /// A gap wider than this many slots breaks the line instead of bridging it.
  final int gap;

  /// A colour per value, so the line itself can say how high it is. When set,
  /// each stretch is drawn in the colour of its mean and [color] is unused.
  final Color Function(double v)? colorAt;

  /// The soft fill under the line.
  final bool fill;

  /// Round the corners where the segments meet (a point per hour, say), by
  /// curving through the midpoints between points.
  final bool smooth;

  /// Painted after the grid and before the line (a shaded span), and after the
  /// markers (a "now" line).
  final ScrubPaint? paintUnder, paintOver;

  final ValueChanged<int?> onScrub;
  final double height;
  final double gutter;
  final String label;
  final String Function(int i)? describe;

  /// Two fingers on the line, to zoom it.
  final PinchCallback? onPinch;

  const ScrubLine({
    super.key,
    required this.values,
    required this.xLabels,
    required this.lo,
    required this.hi,
    required this.ticks,
    required this.tickText,
    required this.color,
    required this.onScrub,
    this.valueLabels = const [],
    this.avg,
    this.band,
    this.markers = true,
    this.slots = true,
    this.highlight,
    this.gap = 1 << 30,
    this.colorAt,
    this.fill = true,
    this.smooth = false,
    this.paintUnder,
    this.paintOver,
    this.height = 200,
    this.gutter = S.x10,
    this.label = 'Chart',
    this.describe,
    this.onPinch,
  });

  static const _band = S.x8;
  static const _top = S.x6;

  /// The plot's insets, so a screen laying marks over the chart agrees with it.
  EdgeInsets get inset => EdgeInsets.fromLTRB(gutter, _top, slots ? 0 : S.x2, _band);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final inset = this.inset;
    return ScrubArea(
      count: values.length,
      slots: slots,
      inset: inset,
      height: height,
      onScrub: onScrub,
      onPinch: onPinch,
      label: label,
      describe: describe ?? _describeIndex,
      dotAt: (i) {
        final v = values[i];
        return v == null || hi <= lo ? null : (v - lo) / (hi - lo);
      },
      builder: (c, at) => CustomPaint(
        size: Size.infinite,
        painter: _LinePainter(
          p: p,
          values: values,
          xLabels: xLabels,
          valueLabels: valueLabels,
          lo: lo,
          hi: hi,
          ticks: ticks,
          tickText: tickText,
          avg: avg,
          band: band,
          color: color,
          markers: markers,
          slots: slots,
          highlight: highlight,
          gap: gap,
          colorAt: colorAt,
          fill: fill,
          smooth: smooth,
          paintUnder: paintUnder,
          paintOver: paintOver,
          at: at,
          inset: inset,
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final P p;
  final List<double?> values;
  final List<String> xLabels, valueLabels;
  final double lo, hi;
  final List<double> ticks;
  final String Function(double) tickText;
  final double? avg;
  final ({double lo, double hi})? band;
  final Color color;
  final bool markers, slots;
  final int? highlight, at;
  final int gap;
  final Color Function(double v)? colorAt;
  final bool fill;
  final bool smooth;
  final ScrubPaint? paintUnder, paintOver;
  final EdgeInsets inset;

  _LinePainter({
    required this.p,
    required this.values,
    required this.xLabels,
    required this.valueLabels,
    required this.lo,
    required this.hi,
    required this.ticks,
    required this.tickText,
    required this.avg,
    required this.band,
    required this.color,
    required this.markers,
    required this.slots,
    required this.highlight,
    required this.at,
    required this.gap,
    required this.colorAt,
    required this.fill,
    required this.smooth,
    required this.paintUnder,
    required this.paintOver,
    required this.inset,
  });

  TextPainter _text(String s, TextStyle style, {double? width, TextAlign align = TextAlign.center}) =>
      TextPainter(
        text: TextSpan(text: s, style: style),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width ?? double.infinity);

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final span = hi - lo;
    if (n == 0 || span <= 0) return;
    final r = plotRect(size, inset);
    double yOf(double v) => r.bottom - (v - lo) / span * r.height;
    double xOf(int i) => scrubXOf(i, r, n, slots: slots);

    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = yOf(t);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      if (inset.left <= 0) continue;
      final tp = _text(tickText(t), F.num(F.over).copyWith(color: p.ink3, fontWeight: FontWeight.w600),
          width: inset.left - S.x2, align: TextAlign.right);
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    // The typical range: a soft band the line travels through.
    final b = band;
    if (b != null) {
      final top = yOf(math.min(b.hi, hi)), bottom = yOf(math.max(b.lo, lo));
      if (bottom > top) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(r.left, top, r.right, bottom), const Radius.circular(R.sm)),
          Paint()..color = p.ink.withValues(alpha: .07),
        );
      }
    }

    // The column band behind the day the screen is about.
    final hl = highlight;
    if (slots && hl != null && hl >= 0 && hl < n) {
      final slot = r.width / n;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(r.left + hl * slot + slot * .12, r.top - S.x2,
                slot * .76, r.height + S.x2),
            const Radius.circular(R.sm)),
        Paint()..color = p.ink.withValues(alpha: .08),
      );
    }

    // The average sits behind the line: dashed, faint, and unlabelled.
    final a = avg;
    if (a != null && a >= lo && a <= hi) {
      final y = yOf(a);
      final dash = Paint()
        ..color = p.ink.withValues(alpha: .28)
        ..strokeWidth = 1;
      for (var x = r.left; x < r.right; x += S.x2) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + S.x1, r.right), y), dash);
      }
    }

    paintUnder?.call(canvas, r, xOf, yOf);

    // Runs of consecutive points, broken wherever a gap is too wide to bridge.
    final runs = <List<int>>[];
    var run = <int>[];
    for (var i = 0; i < n; i++) {
      if (values[i] == null) continue;
      if (run.isNotEmpty && i - run.last > gap) {
        runs.add(run);
        run = <int>[];
      }
      run.add(i);
    }
    if (run.isNotEmpty) runs.add(run);

    for (final ru in runs) {
      if (ru.length < 2) continue;
      final path = Path()..moveTo(xOf(ru.first), yOf(values[ru.first]!));
      if (smooth && ru.length > 2) {
        // A curve THROUGH every point: a cardinal spline, with each stretch's
        // control points held between its two ends so it never swings past a
        // reading (a peak is a peak, not an overshoot beside it).
        final pts = [for (final i in ru) Offset(xOf(i), yOf(values[i]!))];
        for (var k = 0; k < pts.length - 1; k++) {
          final p0 = pts[math.max(0, k - 1)], p1 = pts[k], p2 = pts[k + 1];
          final p3 = pts[math.min(pts.length - 1, k + 2)];
          final lo = math.min(p1.dy, p2.dy), hi = math.max(p1.dy, p2.dy);
          final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
          path.cubicTo(c1.dx, c1.dy.clamp(lo, hi), c2.dx, c2.dy.clamp(lo, hi),
              p2.dx, p2.dy);
        }
      } else {
        for (final i in ru.skip(1)) {
          path.lineTo(xOf(i), yOf(values[i]!));
        }
      }
      if (colorAt != null) {
        // Each stretch in the colour of its own height.
        for (var k = 1; k < ru.length; k++) {
          final a = values[ru[k - 1]]!, b = values[ru[k]]!;
          canvas.drawLine(
            Offset(xOf(ru[k - 1]), yOf(a)),
            Offset(xOf(ru[k]), yOf(b)),
            Paint()
              ..color = colorAt!((a + b) / 2)
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round,
          );
        }
        continue;
      }
      if (fill) {
        final area = Path.from(path)
          ..lineTo(xOf(ru.last), r.bottom)
          ..lineTo(xOf(ru.first), r.bottom)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
            ).createShader(r),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: markers ? .55 : 1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = markers ? 2.5 : 1.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // Rings and the value over each, last so nothing draws across them.
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = xOf(i), y = yOf(v);
      if (markers) {
        canvas.drawCircle(Offset(x, y), S.x1 + S.half, Paint()..color = p.bg);
        canvas.drawCircle(
          Offset(x, y),
          S.x1 + S.half - 1,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      if (i < valueLabels.length && valueLabels[i].isNotEmpty) {
        final tp = _text(
          valueLabels[i],
          F.num(F.cap).copyWith(color: at == i ? p.ink : color, fontWeight: FontWeight.w700),
          width: r.width / n * 2,
        );
        final pill = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x, y - S.x5 - tp.height / 2),
              width: tp.width + S.x2,
              height: tp.height + S.x1),
          const Radius.circular(R.sm),
        );
        canvas.drawRRect(pill, Paint()..color = p.bg.withValues(alpha: .45));
        tp.paint(canvas, Offset(x - tp.width / 2, pill.center.dy - tp.height / 2));
      }
    }

    paintOver?.call(canvas, r, xOf, yOf);

    // The x labels. Labels near an edge are pulled inside it.
    for (var i = 0; i < n && i < xLabels.length; i++) {
      if (xLabels[i].isEmpty) continue;
      final focus = i == at || i == highlight;
      final tp = _text(
        xLabels[i],
        F.num(F.over).copyWith(
          color: focus ? p.ink : p.ink3,
          fontWeight: focus ? FontWeight.w800 : FontWeight.w600,
          height: 1.15,
        ),
        width: math.max(r.width / n, S.x12 * 1.5),
      );
      final x = (xOf(i) - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();
      tp.paint(canvas, Offset(x, r.bottom + S.x1));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}

/// Floating bars on a clock: one bar per night from the time you went to bed
/// to the time you woke, on an axis of hours of the day that runs downward
/// from the evening to the morning. The bed time is written over each bar and
/// the wake time under it.
class ScrubRanges extends StatelessWidget {
  /// Per night, minutes after noon at going to bed and at waking (waking can
  /// pass 1440: it is the next morning). Null draws no bar.
  final List<({double from, double to})?> ranges;

  /// One x label per bar. Two lines are allowed.
  final List<String> xLabels;

  /// The axis in the same minutes, and what each tick reads as a clock time.
  final double lo, hi;
  final List<double> ticks;
  final String Function(double) tickText;

  /// How a bed or wake time is written over and under a bar.
  final String Function(double) timeText;

  /// The bars' colour. With [emphasis] set, only that bar (or the one under a
  /// finger) wears it and the rest are grey.
  final Color color;
  final int? emphasis;

  /// Write the times on every bar, rather than only on the emphasised one.
  final bool labelAll;

  /// A dashed line through the usual bed and wake times, one point per bar.
  final List<({double bed, double wake})?>? usual;

  /// Levels to mark across the whole chart: a dashed line with its time in a
  /// white tag at the left (the average bed and wake times of a month).
  final List<({double at, String text})> tags;

  final ValueChanged<int?> onScrub;
  final double height;
  final double gutter;
  final String label;
  final String Function(int i)? describe;

  const ScrubRanges({
    super.key,
    required this.ranges,
    required this.xLabels,
    required this.lo,
    required this.hi,
    required this.ticks,
    required this.tickText,
    required this.timeText,
    required this.color,
    required this.onScrub,
    this.emphasis,
    this.labelAll = true,
    this.usual,
    this.tags = const [],
    this.height = 260,
    this.gutter = S.x10,
    this.label = 'Chart',
    this.describe,
  });

  static const _top = S.x8;
  static const _band = S.x8;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final inset = EdgeInsets.fromLTRB(gutter, _top, 0, _band);
    return ScrubArea(
      count: ranges.length,
      slots: true,
      inset: inset,
      height: height,
      onScrub: onScrub,
      label: label,
      describe: describe ?? _describeIndex,
      builder: (c, at) => CustomPaint(
        size: Size.infinite,
        painter: _RangesPainter(
          p: p,
          ranges: ranges,
          xLabels: xLabels,
          lo: lo,
          hi: hi,
          ticks: ticks,
          tickText: tickText,
          timeText: timeText,
          color: color,
          emphasis: emphasis,
          labelAll: labelAll,
          usual: usual,
          tags: tags,
          at: at,
          inset: inset,
        ),
      ),
    );
  }
}

class _RangesPainter extends CustomPainter {
  final P p;
  final List<({double from, double to})?> ranges;
  final List<String> xLabels;
  final double lo, hi;
  final List<double> ticks;
  final String Function(double) tickText, timeText;
  final Color color;
  final int? emphasis, at;
  final bool labelAll;
  final List<({double bed, double wake})?>? usual;
  final List<({double at, String text})> tags;
  final EdgeInsets inset;

  _RangesPainter({
    required this.p,
    required this.ranges,
    required this.xLabels,
    required this.lo,
    required this.hi,
    required this.ticks,
    required this.tickText,
    required this.timeText,
    required this.color,
    required this.emphasis,
    required this.labelAll,
    required this.usual,
    required this.tags,
    required this.at,
    required this.inset,
  });

  TextPainter _text(String s, TextStyle style, {double? width, TextAlign align = TextAlign.center}) =>
      TextPainter(
        text: TextSpan(text: s, style: style),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width ?? double.infinity);

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + S.x1, m.length)), paint);
        d += S.x2 + S.half;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = ranges.length;
    final span = hi - lo;
    if (n == 0 || span <= 0) return;
    final r = plotRect(size, inset);
    // Time runs DOWN: the evening is the top line, the morning the bottom.
    double yOf(double t) => r.top + (t - lo) / span * r.height;
    final slot = r.width / n;
    final bw = slot * (n <= 8 ? .38 : .56);

    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = yOf(t);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      if (inset.left <= 0) continue;
      final tp = _text(tickText(t), F.num(F.over).copyWith(color: p.ink3, fontWeight: FontWeight.w600),
          width: inset.left - S.x2, align: TextAlign.right);
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    // Marked levels, behind the bars: a faint dash across, the time in a tag.
    for (final t in tags) {
      final y = yOf(t.at);
      final dash = Paint()
        ..color = p.ink.withValues(alpha: .3)
        ..strokeWidth = 1;
      for (var x = r.left; x < r.right; x += S.x2) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + S.x1, r.right), y), dash);
      }
    }

    // What is usual, behind the bars.
    final u = usual;
    if (u != null) {
      final dash = Paint()
        ..color = p.ink.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final bed in [true, false]) {
        Path? path;
        for (var i = 0; i < n; i++) {
          final v = u[i];
          if (v == null) {
            if (path != null) _dashed(canvas, path, dash);
            path = null;
            continue;
          }
          final pt = Offset(r.left + (i + .5) * slot, yOf(bed ? v.bed : v.wake));
          if (path == null) {
            path = Path()..moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        if (path != null) _dashed(canvas, path, dash);
      }
    }

    final focus = at ?? emphasis;
    for (var i = 0; i < n; i++) {
      final rg = ranges[i];
      if (rg == null) continue;
      final x = r.left + i * slot + (slot - bw) / 2;
      final top = yOf(rg.from), bottom = yOf(rg.to);
      final lit = emphasis != null ? i == focus : (at == null || at == i);
      final base = emphasis != null
          ? (lit ? color : C.barGrey)
          : (lit ? color : Color.lerp(color, p.bg, .72)!);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(x, top, x + bw, bottom), const Radius.circular(R.sm / 3)),
        Paint()..color = base,
      );
      if (labelAll || i == focus) {
        final style = F.num(F.cap).copyWith(
            color: lit ? (emphasis != null ? color : p.ink2) : p.ink3, fontWeight: FontWeight.w700);
        final above = _text(timeText(rg.from), style, width: slot * 2);
        above.paint(canvas, Offset(x + bw / 2 - above.width / 2, top - above.height - S.x1));
        final below = _text(timeText(rg.to), style, width: slot * 2);
        below.paint(canvas, Offset(x + bw / 2 - below.width / 2, bottom + S.x1));
      }
    }

    for (var i = 0; i < n && i < xLabels.length; i++) {
      if (xLabels[i].isEmpty) continue;
      final on = i == (at ?? emphasis);
      final tp = _text(
        xLabels[i],
        F.num(F.over).copyWith(
          color: on ? p.ink : p.ink3,
          fontWeight: on ? FontWeight.w800 : FontWeight.w600,
          height: 1.15,
        ),
        width: math.max(slot, S.x12),
      );
      tp.paint(canvas, Offset(r.left + (i + .5) * slot - tp.width / 2, r.bottom + S.x1));
    }

    // The tags sit last, over the axis labels they stand in for.
    for (final t in tags) {
      final y = yOf(t.at);
      final tp = _text(t.text, F.num(F.cap).copyWith(color: p.bg, fontWeight: FontWeight.w800));
      final box = Rect.fromLTWH(0, y - (tp.height + S.x2) / 2, tp.width + S.x4, tp.height + S.x2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(R.sm)), Paint()..color = p.ink);
      tp.paint(canvas, Offset(S.x2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RangesPainter old) => true;
}

/// Two lines on one scale, each point a ring: [a] with its numbers over the
/// points, [b] with its numbers under them. Hours of sleep against the hours
/// the body asked for, say.
class ScrubPair extends StatelessWidget {
  final List<double?> a, b;
  final List<String> aLabels, bLabels, xLabels;
  final double lo, hi;
  final List<double> ticks;
  final String Function(double) tickText;
  final Color colorA, colorB;
  final ValueChanged<int?> onScrub;
  final double height;
  final double gutter;
  final String label;
  final String Function(int i)? describe;

  const ScrubPair({
    super.key,
    required this.a,
    required this.b,
    required this.aLabels,
    required this.bLabels,
    required this.xLabels,
    required this.lo,
    required this.hi,
    required this.ticks,
    required this.tickText,
    required this.colorA,
    required this.colorB,
    required this.onScrub,
    this.height = 260,
    this.gutter = S.x10,
    this.label = 'Chart',
    this.describe,
  });

  static const _top = S.x8;
  static const _band = S.x8;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final inset = EdgeInsets.fromLTRB(gutter, _top, 0, _band);
    return ScrubArea(
      count: a.length,
      slots: true,
      inset: inset,
      height: height,
      onScrub: onScrub,
      label: label,
      describe: describe ?? _describeIndex,
      builder: (c, at) => CustomPaint(
        size: Size.infinite,
        painter: _PairPainter(this, p, at, inset),
      ),
    );
  }
}

class _PairPainter extends CustomPainter {
  final ScrubPair w;
  final P p;
  final int? at;
  final EdgeInsets inset;
  _PairPainter(this.w, this.p, this.at, this.inset);

  TextPainter _text(String s, TextStyle style, {double? width, TextAlign align = TextAlign.center}) =>
      TextPainter(
        text: TextSpan(text: s, style: style),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width ?? double.infinity);

  @override
  void paint(Canvas canvas, Size size) {
    final n = w.a.length;
    final span = w.hi - w.lo;
    if (n == 0 || span <= 0) return;
    final r = plotRect(size, inset);
    double yOf(double v) => r.bottom - (v - w.lo) / span * r.height;
    double xOf(int i) => scrubXOf(i, r, n, slots: true);

    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final t in w.ticks) {
      final y = yOf(t);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      final tp = _text(w.tickText(t), F.num(F.over).copyWith(color: p.ink3, fontWeight: FontWeight.w600),
          width: inset.left - S.x2, align: TextAlign.right);
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    void series(List<double?> vs, List<String> labels, Color color, bool below) {
      Path? path;
      for (var i = 0; i < n; i++) {
        final v = vs[i];
        if (v == null) {
          path = null;
          continue;
        }
        if (path == null) {
          path = Path()..moveTo(xOf(i), yOf(v));
        } else {
          path.lineTo(xOf(i), yOf(v));
        }
        if (i + 1 >= n || vs[i + 1] == null) {
          canvas.drawPath(
            path,
            Paint()
              ..color = color.withValues(alpha: .6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..strokeJoin = StrokeJoin.round,
          );
        }
      }
      for (var i = 0; i < n; i++) {
        final v = vs[i];
        if (v == null) continue;
        final x = xOf(i), y = yOf(v);
        canvas.drawCircle(Offset(x, y), S.x1 + S.half, Paint()..color = p.bg);
        canvas.drawCircle(
          Offset(x, y),
          S.x1 + S.half - 1,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        if (i < labels.length && labels[i].isNotEmpty) {
          final tp = _text(labels[i],
              F.num(F.cap).copyWith(color: at == i ? p.ink : color, fontWeight: FontWeight.w700),
              width: r.width / n * 2);
          final cy = below ? y + S.x5 + tp.height / 2 : y - S.x5 - tp.height / 2;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(x, cy), width: tp.width + S.x2, height: tp.height + S.x1),
                const Radius.circular(R.sm)),
            Paint()..color = p.bg.withValues(alpha: .45),
          );
          tp.paint(canvas, Offset(x - tp.width / 2, cy - tp.height / 2));
        }
      }
    }

    series(w.a, w.aLabels, w.colorA, false);
    series(w.b, w.bLabels, w.colorB, true);

    for (var i = 0; i < n && i < w.xLabels.length; i++) {
      if (w.xLabels[i].isEmpty) continue;
      final on = i == at;
      final tp = _text(
        w.xLabels[i],
        F.num(F.over).copyWith(
          color: on ? p.ink : p.ink3,
          fontWeight: on ? FontWeight.w800 : FontWeight.w600,
          height: 1.15,
        ),
        width: math.max(r.width / n, S.x12),
      );
      tp.paint(canvas, Offset(xOf(i) - tp.width / 2, r.bottom + S.x1));
    }
  }

  @override
  bool shouldRepaint(_PairPainter old) => true;
}

/// One calendar month on a six-month chart: the days it covers (indexes into
/// the chart's days, both ends included) and what to write for it.
class MonthMark {
  final int from, to;

  /// The month's figure, and what to write over its segment. A floating chart
  /// has a second pair: the wake time under the bed time.
  final double? value;
  final String text;
  final double? value2;
  final String text2;

  /// The month's name, under the chart.
  final String label;

  /// A short line under the segment — the change on the month before — and the
  /// colour it and the segment wear instead of white.
  final String? note;
  final Color? tone;

  const MonthMark({
    required this.from,
    required this.to,
    required this.label,
    this.value,
    this.text = '',
    this.value2,
    this.text2 = '',
    this.note,
    this.tone,
  });
}

/// Six months at a glance: the days faintly in the background, and over them a
/// short white line at each month's average with the figure above it. A
/// floating chart (bed and wake) marks two lines per month.
class ScrubMonths extends StatelessWidget {
  /// One value per day, oldest first; null leaves a gap. Drawn as a ghost.
  final List<double?> days;

  /// Instead of [days]: a floating bar per day, drawn as a ghost.
  final List<({double from, double to})?>? spans;

  final List<MonthMark> months;
  final double lo, hi;
  final List<double> ticks;
  final String Function(double) tickText;

  /// Time runs down the axis (a clock from evening to morning).
  final bool down;
  final Color color;
  final ValueChanged<int?> onScrub;
  final double height;
  final double gutter;
  final String label;
  final String Function(int i)? describe;

  const ScrubMonths({
    super.key,
    required this.days,
    required this.months,
    required this.lo,
    required this.hi,
    required this.ticks,
    required this.tickText,
    required this.color,
    required this.onScrub,
    this.spans,
    this.down = false,
    this.height = 260,
    this.gutter = S.x10,
    this.label = 'Chart',
    this.describe,
  });

  static const _top = S.x8;
  static const _band = S.x8;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final inset = EdgeInsets.fromLTRB(gutter, _top, S.x2, _band);
    final n = spans?.length ?? days.length;
    return ScrubArea(
      count: n,
      slots: false,
      inset: inset,
      height: height,
      onScrub: onScrub,
      label: label,
      describe: describe ?? _describeIndex,
      bandSpan: (at, plot) {
        for (final m in months) {
          if (at >= m.from && at <= m.to) {
            final half = n > 1 ? plot.width / (n - 1) / 2 : 0.0;
            return (
              left: scrubXOf(m.from, plot, n, slots: false) - half,
              right: scrubXOf(m.to, plot, n, slots: false) + half,
            );
          }
        }
        return null;
      },
      builder: (c, at) => CustomPaint(
        size: Size.infinite,
        painter: _MonthsPainter(
            p: p,
            days: days,
            spans: spans,
            months: months,
            lo: lo,
            hi: hi,
            ticks: ticks,
            tickText: tickText,
            down: down,
            color: color,
            at: at,
            inset: inset),
      ),
    );
  }
}

class _MonthsPainter extends CustomPainter {
  final P p;
  final List<double?> days;
  final List<({double from, double to})?>? spans;
  final List<MonthMark> months;
  final double lo, hi;
  final List<double> ticks;
  final String Function(double) tickText;
  final bool down;
  final Color color;
  final int? at;
  final EdgeInsets inset;

  _MonthsPainter({
    required this.p,
    required this.days,
    required this.spans,
    required this.months,
    required this.lo,
    required this.hi,
    required this.ticks,
    required this.tickText,
    required this.down,
    required this.color,
    required this.at,
    required this.inset,
  });

  TextPainter _text(String s, TextStyle style, {double? width}) => TextPainter(
        text: TextSpan(text: s, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width ?? double.infinity);

  @override
  void paint(Canvas canvas, Size size) {
    final n = spans?.length ?? days.length;
    final span = hi - lo;
    if (n < 2 || span <= 0) return;
    final r = plotRect(size, inset);
    double yOf(double v) => down
        ? r.top + (v - lo) / span * r.height
        : r.bottom - (v - lo) / span * r.height;
    double xOf(int i) => scrubXOf(i, r, n, slots: false);
    final dayW = r.width / (n - 1);

    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = yOf(t);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      final tp = _text(tickText(t), F.num(F.over).copyWith(color: p.ink3, fontWeight: FontWeight.w600),
          width: inset.left - S.x2);
      tp.paint(canvas, Offset(inset.left - S.x2 - tp.width, y - tp.height / 2));
    }

    // The ghost: every day, faint.
    final ghost = color.withValues(alpha: .22);
    final sp = spans;
    if (sp != null) {
      for (var i = 0; i < n; i++) {
        final g = sp[i];
        if (g == null) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(xOf(i) - math.max(dayW * .3, .8), yOf(g.from),
                  xOf(i) + math.max(dayW * .3, .8), yOf(g.to)),
              const Radius.circular(1)),
          Paint()..color = color.withValues(alpha: .16),
        );
      }
    } else {
      Path? path;
      int? first, last;
      void close() {
        if (path == null || first == null || last == null) return;
        canvas.drawPath(
            path!,
            Paint()
              ..color = ghost
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..strokeJoin = StrokeJoin.round);
        final area = Path.from(path!)
          ..lineTo(xOf(last!), r.bottom)
          ..lineTo(xOf(first!), r.bottom)
          ..close();
        canvas.drawPath(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withValues(alpha: .12), color.withValues(alpha: 0)],
              ).createShader(r));
        path = null;
        first = last = null;
      }

      for (var i = 0; i < n; i++) {
        final v = days[i];
        if (v == null) {
          close();
          continue;
        }
        if (path == null) {
          path = Path()..moveTo(xOf(i), yOf(v));
          first = i;
        } else {
          path!.lineTo(xOf(i), yOf(v));
        }
        last = i;
      }
      close();
    }

    // Each month's average, as a short line with its figure over it.
    void segment(MonthMark m, double v, String text, bool lit) {
      final y = yOf(v);
      final x0 = xOf(m.from) - dayW / 2 + S.half, x1 = xOf(m.to) + dayW / 2 - S.half;
      final tone = m.tone ?? p.ink;
      canvas.drawLine(
          Offset(x0, y),
          Offset(x1, y),
          Paint()
            ..color = tone.withValues(alpha: lit ? 1 : .6)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round);
      // A sliver of a month at either end has no room for its figure.
      if (x1 - x0 < S.x10) return;
      final tp = _text(text, F.num(F.cap).copyWith(color: tone, fontWeight: FontWeight.w700));
      final cx = ((x0 + x1) / 2 - tp.width / 2)
          .clamp(0.0, math.max(0.0, size.width - tp.width))
          .toDouble();
      tp.paint(canvas, Offset(cx, y - tp.height - S.x1));
      final note = m.note;
      if (note != null) {
        final np = _text(note, F.num(F.cap).copyWith(color: tone, fontWeight: FontWeight.w700));
        np.paint(
            canvas,
            Offset(((x0 + x1) / 2 - np.width / 2)
                .clamp(0.0, math.max(0.0, size.width - np.width))
                .toDouble(),
                y + S.x1));
      }
    }

    for (final m in months) {
      final lit = at == null || (at! >= m.from && at! <= m.to);
      if (m.value != null) segment(m, m.value!, m.text, lit);
      if (m.value2 != null) segment(m, m.value2!, m.text2, lit);
      // Its name under the chart, in the middle of its days.
      final mid = (xOf(m.from) + xOf(m.to)) / 2;
      if (xOf(m.to) - xOf(m.from) < S.x10) continue;
      final tp = _text(m.label,
          F.num(F.over).copyWith(color: lit && at != null ? p.ink : p.ink3, fontWeight: FontWeight.w600));
      tp.paint(canvas, Offset(mid - tp.width / 2, r.bottom + S.x1));
    }
  }

  @override
  bool shouldRepaint(_MonthsPainter old) => true;
}
