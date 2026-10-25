// Scrubbing: drag a finger along a chart and the point under it is read out
// big, with a guide line through it. Every chart with a point per day or per
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
          label: widget.label,
          describe: (f) => widget.describe(scrubIndexAt(f * size.width, plot,
              widget.count, slots: widget.slots)),
          child: Stack(children: [
            Positioned.fill(child: widget.builder(c, at)),
            if (at != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GuidePainter(
                      x: scrubXOf(at, plot, widget.count, slots: widget.slots),
                      plot: plot,
                      dot: widget.dotAt?.call(at),
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

/// The dashed guide through the touched point, and the dot on it.
class _GuidePainter extends CustomPainter {
  final double x;
  final Rect plot;
  final double? dot;
  final Color ink, ring;

  _GuidePainter({
    required this.x,
    required this.plot,
    required this.dot,
    required this.ink,
    required this.ring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = ink.withValues(alpha: .85)
      ..strokeWidth = 1.5;
    // Dashes of three, gaps of three: the same rhythm the average line uses.
    for (var y = plot.top; y < plot.bottom; y += S.x1 + S.half) {
      canvas.drawLine(
          Offset(x, y), Offset(x, math.min(y + S.half + 1, plot.bottom)), guide);
    }
    final v = dot;
    if (v == null) return;
    final cy = plot.bottom - v.clamp(0.0, 1.0) * plot.height;
    canvas.drawCircle(Offset(x, cy), S.x2 * .75 + 2, Paint()..color = ring);
    canvas.drawCircle(Offset(x, cy), S.x2 * .75, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.x != x ||
      old.dot != dot ||
      old.plot != plot ||
      old.ink != ink ||
      old.ring != ring;
}

/// The readout that goes big above a chart: a small caption (the average, or
/// the date under the finger), the number, and anything that qualifies it.
class ScrubReadout extends StatelessWidget {
  final String caption;
  final String value;
  final Widget? under;

  /// The number's size. The trend screen's readout uses the big style; the
  /// cards on the strain screen use the smaller one.
  final bool big;

  const ScrubReadout({
    super.key,
    required this.caption,
    required this.value,
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
            style: F.over.copyWith(color: p.ink2, letterSpacing: 1.2)),
        const SizedBox(height: S.half),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: (big ? F.n34 : F.n24)
                  .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        ),
        if (under != null) ...[const SizedBox(height: S.x2), under!],
      ],
    );
  }
}

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

  /// The dashed average, or null for none.
  final double? avg;
  final String avgTag;

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
    this.avgTag = 'AVG.',
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
      dotAt: (i) {
        final v = values[i];
        return v == null || hi <= lo ? null : (v - lo) / (hi - lo);
      },
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
          avgTag: avgTag,
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
  final String avgTag;
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
    required this.avgTag,
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
    final bw = slot * (n <= 8 ? .34 : .56);

    // Gridlines and their values, in the gutter.
    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = yOf(t);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      if (inset.left <= 0) continue;
      final tp = _text(tickText(t), F.over.copyWith(color: p.ink3, fontWeight: FontWeight.w600),
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

    final zero = yOf(lo > 0 ? lo : 0);
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = r.left + i * slot + (slot - bw) / 2;
      final base = colorOf?.call(i, v) ?? color;
      final dimmed = at != null && at != i;
      final stack = stacks?[i];
      if (stack != null && segmentColors != null) {
        // Bottom to top, each segment its own colour.
        var from = zero;
        for (var s = 0; s < stack.length && s < segmentColors!.length; s++) {
          final top = yOf(lo + stack.take(s + 1).fold<double>(0, (a, b) => a + b));
          final c = dimmed ? Color.lerp(segmentColors![s], p.bg, .72)! : segmentColors![s];
          canvas.drawRect(Rect.fromLTRB(x, math.min(top, from), x + bw, math.max(top, from)),
              Paint()..color = c);
          from = top;
        }
      } else {
        final y = yOf(v);
        final c = dimmed ? Color.lerp(base, p.bg, .72)! : base;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(x, math.min(y, zero), x + bw, math.max(y, zero)),
            topLeft: const Radius.circular(R.sm),
            topRight: const Radius.circular(R.sm),
          ),
          Paint()..color = c,
        );
      }
      if (i < valueLabels.length && valueLabels[i].isNotEmpty) {
        final top = stack != null
            ? yOf(lo + stack.fold<double>(0, (a, b) => a + b))
            : yOf(v);
        final tp = _text(valueLabels[i], F.cap.copyWith(
          color: at == i ? p.ink : base,
          fontWeight: FontWeight.w700,
        ), width: slot * 2);
        tp.paint(canvas, Offset(x + bw / 2 - tp.width / 2, top - tp.height - S.half));
      }
    }

    // The average: a dashed line across the plot and its tag at the left edge.
    final a = avg;
    if (a != null && a >= lo && a <= hi) {
      final y = yOf(a);
      final dash = Paint()
        ..color = p.ink
        ..strokeWidth = 1.5;
      for (var x = r.left; x < r.right; x += S.x2) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + S.x1, r.right), y), dash);
      }
      final tag = _text(avgTag, F.over.copyWith(color: p.bg, fontWeight: FontWeight.w800, letterSpacing: 1.2));
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + S.half, y - (tag.height + S.half) / 2,
            tag.width + S.x3, tag.height + S.half),
        const Radius.circular(R.sm),
      );
      canvas.drawRRect(box, Paint()..color = p.ink);
      tag.paint(canvas, Offset(box.left + S.x3 / 2, box.top + S.half / 2));
    }

    // The x labels, in the band under the plot. The touched day is bolder.
    for (var i = 0; i < n && i < xLabels.length; i++) {
      if (xLabels[i].isEmpty) continue;
      final focus = i == at || i == highlight;
      final tp = _text(
        xLabels[i],
        F.over.copyWith(
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
