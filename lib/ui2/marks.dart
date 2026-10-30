// Small drawn marks: the stat-row icons and the triangles that say above or
// below. Drawn rather than taken from the icon font so a stroke can be as fine
// as the screen wants, and so each sits on the same 24-unit grid.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A solid triangle with softened corners: above (up) or below (down) a
/// comparison. Green for good, orange for not, plain for neither.
class DeltaTriangle extends StatelessWidget {
  final bool up;
  final Color color;

  /// Width. The height is a little under it.
  final double size;

  const DeltaTriangle(
      {super.key, required this.up, required this.color, this.size = S.x3});

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
        child: CustomPaint(
          size: Size(size, size * .8),
          painter: _TrianglePaint(color: color, up: up),
        ),
      );
}

class _TrianglePaint extends CustomPainter {
  final Color color;
  final bool up;
  _TrianglePaint({required this.color, required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    // Inset by the stroke so the rounding stays inside the box.
    const k = 1.0;
    final w = size.width - 2 * k, h = size.height - 2 * k;
    final path = up
        ? (Path()
          ..moveTo(k, k + h)
          ..lineTo(k + w / 2, k)
          ..lineTo(k + w, k + h)
          ..close())
        : (Path()
          ..moveTo(k, k)
          ..lineTo(k + w, k)
          ..lineTo(k + w / 2, k + h)
          ..close());
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = k * 1.6
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_TrianglePaint old) => old.color != color || old.up != up;
}

/// The four marks on the strain screen's stat rows.
enum StatMark { zonesLow, zonesHigh, strength, steps }

/// A fine-lined icon for one of the [StatMark]s, drawn on a 24-unit grid.
class StatIcon extends StatelessWidget {
  final StatMark mark;
  final Color color;
  final double size;

  const StatIcon(this.mark, {super.key, required this.color, this.size = I.lg});

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          painter: _StatPaint(mark, color),
        ),
      );
}

class _StatPaint extends CustomPainter {
  final StatMark mark;
  final Color color;
  _StatPaint(this.mark, this.color);

  static Path _heart() => Path()
    ..moveTo(12, 20.6)
    ..cubicTo(12, 20.6, 2.6, 15.4, 2.6, 8.9)
    ..cubicTo(2.6, 5.9, 4.8, 3.9, 7.4, 3.9)
    ..cubicTo(9.3, 3.9, 11, 4.9, 12, 6.6)
    ..cubicTo(13, 4.9, 14.7, 3.9, 16.6, 3.9)
    ..cubicTo(19.2, 3.9, 21.4, 5.9, 21.4, 8.9)
    ..cubicTo(21.4, 15.4, 12, 20.6, 12, 20.6)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (mark) {
      case StatMark.zonesLow:
        canvas.drawPath(_heart(), line);
        // Three bands, narrowing toward the point of the heart.
        canvas.drawLine(const Offset(7.2, 9.2), const Offset(16.8, 9.2), line);
        canvas.drawLine(const Offset(7.9, 12), const Offset(16.1, 12), line);
        canvas.drawLine(const Offset(9.4, 14.8), const Offset(14.6, 14.8), line);
      case StatMark.zonesHigh:
        canvas.drawPath(_heart(), line);
        // Two stacked chevrons: pushing upward.
        canvas.drawPath(
            Path()
              ..moveTo(8.6, 11.2)
              ..lineTo(12, 8.2)
              ..lineTo(15.4, 11.2),
            line);
        canvas.drawPath(
            Path()
              ..moveTo(8.6, 14.6)
              ..lineTo(12, 11.6)
              ..lineTo(15.4, 14.6),
            line);
      case StatMark.strength:
        // A barbell on its side: bar, two plates, two collars.
        canvas.drawLine(const Offset(7, 12), const Offset(17, 12), line);
        final plate = Paint.from(line);
        for (final r in const [
          Rect.fromLTRB(4.2, 6.4, 7, 17.6),
          Rect.fromLTRB(17, 6.4, 19.8, 17.6),
        ]) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(r, const Radius.circular(1.2)), plate);
        }
        canvas.drawLine(const Offset(2.2, 9.6), const Offset(2.2, 14.4), line);
        canvas.drawLine(const Offset(21.8, 9.6), const Offset(21.8, 14.4), line);
      case StatMark.steps:
        // A running shoe in profile.
        canvas.drawPath(
            Path()
              ..moveTo(3, 18.2)
              ..lineTo(3, 12.4)
              ..cubicTo(3, 11.6, 3.5, 11.1, 4.3, 11)
              ..lineTo(8, 10.5)
              ..lineTo(10.2, 7.4)
              ..cubicTo(10.6, 6.9, 11.3, 6.8, 11.8, 7.2)
              ..lineTo(13, 8.2)
              ..cubicTo(14, 9.8, 16, 10.7, 18.2, 11.4)
              ..cubicTo(20.2, 12, 21.4, 13.2, 21.4, 15.4)
              ..lineTo(21.4, 18.2)
              ..close(),
            line);
        canvas.drawLine(const Offset(3, 15.6), const Offset(21.4, 15.6), line);
        canvas.drawLine(const Offset(11.4, 9.6), const Offset(13, 11.2), line);
        canvas.drawLine(const Offset(9.2, 10.9), const Offset(10.8, 12.4), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StatPaint old) => old.mark != mark || old.color != color;
}

/// The band, drawn from the side as the original draws it: a rounded loop with
/// the strap's thickness down its right edge and the clasp near the foot. The
/// loop is left open at the right, over the foot of its status: [badge] fills
/// the gap, the arrow of a sync or the dot of a link (see [StrapIcon.badge]).
class StrapIcon extends StatelessWidget {
  final Color color;

  /// Height; the width follows (a little under it).
  final double height;

  /// What sits in the loop's gap, centred on the arrow's place. It is given the
  /// arrow's box, so a [SyncArrowMark] fills it and a dot centres in it.
  final Widget? badge;

  const StrapIcon({super.key, required this.color, this.height = 38, this.badge});

  // The drawing's own grid: the loop in 375 x 495, the arrow beside it.
  static const _w = 430.0, _h = 495.0;

  /// Width at [height].
  static double widthFor(double height) => _w * height / _h;

  @override
  Widget build(BuildContext c) {
    final k = height / _h;
    return ExcludeSemantics(
      child: SizedBox(
        width: _w * k,
        height: height,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: CustomPaint(painter: _StrapPaint(color, k))),
          if (badge != null)
            Positioned(
              left: 290 * k,
              top: 105 * k,
              width: 125 * k,
              height: 140 * k,
              child: Center(child: badge),
            ),
        ]),
      ),
    );
  }
}

class _StrapPaint extends CustomPainter {
  final Color color;
  final double k;
  _StrapPaint(this.color, this.k);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(k);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset o(double x, double y) => Offset(x - 105, y - 115);
    // The loop, from the open end at the right round the foot, up the left,
    // along the top to the strap's beak, and down its thickness to the hook.
    canvas.drawPath(
        Path()
          ..moveTo(o(478, 368).dx, o(478, 368).dy)
          ..cubicTo(o(480, 470).dx, o(480, 470).dy, o(440, 590).dx,
              o(440, 590).dy, o(375, 607).dx, o(375, 607).dy)
          ..lineTo(o(225, 607).dx, o(225, 607).dy)
          ..cubicTo(o(185, 607).dx, o(185, 607).dy, o(165, 555).dx,
              o(165, 555).dy, o(150, 508).dx, o(150, 508).dy)
          ..lineTo(o(120, 495).dx, o(120, 495).dy)
          ..cubicTo(o(106, 470).dx, o(106, 470).dy, o(104, 400).dx,
              o(104, 400).dy, o(108, 330).dx, o(108, 330).dy)
          ..cubicTo(o(112, 250).dx, o(112, 250).dy, o(135, 150).dx,
              o(135, 150).dy, o(215, 120).dx, o(215, 120).dy)
          ..lineTo(o(385, 120).dx, o(385, 120).dy)
          ..lineTo(o(408, 130).dx, o(408, 130).dy)
          ..lineTo(o(372, 152).dx, o(372, 152).dy)
          ..cubicTo(o(335, 230).dx, o(335, 230).dy, o(316, 330).dx,
              o(316, 330).dy, o(316, 420).dx, o(316, 420).dy)
          ..cubicTo(o(316, 450).dx, o(316, 450).dy, o(310, 480).dx,
              o(310, 480).dy, o(303, 497).dx, o(303, 497).dy)
          ..cubicTo(o(300, 520).dx, o(300, 520).dy, o(312, 545).dx,
              o(312, 545).dy, o(326, 553).dx, o(326, 553).dy),
        line);
    // The clasp.
    canvas.drawLine(o(158, 458), o(285, 458), line);
  }

  @override
  bool shouldRepaint(_StrapPaint old) => old.color != color || old.k != k;
}

/// The sync arrow: an up arrow with a flat-cut shaft, in the orange of a
/// transfer under way. Fills its box.
class SyncArrowMark extends StatelessWidget {
  final Color color;
  const SyncArrowMark({super.key, this.color = C.orange});

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
        child: CustomPaint(size: Size.infinite, painter: _ArrowPaint(color)),
      );
}

class _ArrowPaint extends CustomPainter {
  final Color color;
  _ArrowPaint(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 125;
    final w = 22 * k;
    final x = size.width / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawLine(Offset(x, w * .6), Offset(x, size.height), paint);
    canvas.drawPath(
        Path()
          ..moveTo(w * .55, 65 * k + w * .3)
          ..lineTo(x, w * .45)
          ..lineTo(size.width - w * .55, 65 * k + w * .3),
        paint);
  }

  @override
  bool shouldRepaint(_ArrowPaint old) => old.color != color;
}

/// A bold chevron, for the day pager: thick, round-ended, pointing left or
/// right.
class BoldChevron extends StatelessWidget {
  final bool left;
  final Color color;

  /// Height; the width and the stroke follow.
  final double height;

  const BoldChevron(
      {super.key, required this.left, required this.color, this.height = 15});

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
        child: CustomPaint(
          size: Size(height * 11 / 15, height),
          painter: _ChevronPaint(left, color),
        ),
      );
}

class _ChevronPaint extends CustomPainter {
  final bool left;
  final Color color;
  _ChevronPaint(this.left, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.height * .22;
    final a = left ? size.width - w / 2 : w / 2;
    final b = left ? w / 2 : size.width - w / 2;
    canvas.drawPath(
        Path()
          ..moveTo(a, w / 2)
          ..lineTo(b, size.height / 2)
          ..lineTo(a, size.height - w / 2),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_ChevronPaint old) => old.left != left || old.color != color;
}

/// Marks along a chart's time axis, grouped where they would overlap: walking
/// left to right, a mark whose centre is within [gap] of the group before it
/// joins that group. Each group is drawn once, at the mean of its centres, as
/// the mark itself when it holds one and as a [MarkCount] when it holds more.
/// Zooming the chart spreads the centres, so the groups come apart on their
/// own and each mark shows again.
List<List<T>> clusterMarks<T>(List<T> marks, double Function(T) x,
    {double gap = S.x8}) {
  final sorted = [...marks]..sort((a, b) => x(a).compareTo(x(b)));
  final out = <List<T>>[];
  for (final m in sorted) {
    if (out.isNotEmpty) {
      final g = out.last;
      final mid = g.map(x).reduce((a, b) => a + b) / g.length;
      if (x(m) - mid < gap) {
        g.add(m);
        continue;
      }
    }
    out.add([m]);
  }
  return out;
}

/// How many marks a group stands for: the number in a ring, in place of
/// icons that would sit on top of each other.
class MarkCount extends StatelessWidget {
  final int count;
  final Color color;
  final double size;
  const MarkCount(this.count, {super.key, required this.color, this.size = I.md});

  @override
  Widget build(BuildContext c) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
        child: Text('$count',
            style: F.num(F.cap).copyWith(
                color: color, fontWeight: FontWeight.w700, height: 1)),
      );
}

/// A figure that rolls from [from] to [value] the way an odometer turns: every
/// digit in its own window, the last one fastest, a higher one only as the one
/// below it passes 9 — up when the figure grew, down when it fell. Eases out,
/// so it slows into the result. Reduced motion shows the result at once.
///
/// [onTick] fires as the last digit turns over (no more often than
/// [Motion.tickGap]), for a haptic; [onDone] once the roll has settled.
class RollingNumber extends StatefulWidget {
  final double from, value;
  final int decimals;
  final TextStyle style;
  final VoidCallback? onTick, onDone;

  const RollingNumber({
    super.key,
    required this.from,
    required this.value,
    required this.style,
    this.decimals = 1,
    this.onTick,
    this.onDone,
  });

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this)
    ..addListener(_tick)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone?.call();
    });
  bool _started = false;
  int? _last;
  Duration _lastTickAt = Duration.zero;

  double get _shown =>
      widget.from +
      (widget.value - widget.from) * Ease.standard.transform(_c.value);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final d = motion(context, Motion.roll);
    if (d == Duration.zero) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone?.call();
      });
      return;
    }
    _c.duration = d;
    _c.forward();
  }

  void _tick() {
    final low = (_shown * math.pow(10, widget.decimals)).floor();
    if (low == _last) return;
    final first = _last == null;
    _last = low;
    final at = _c.lastElapsedDuration ?? Duration.zero;
    if (first || at - _lastTickAt < Motion.tickGap) return;
    _lastTickAt = at;
    widget.onTick?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final style =
        widget.style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final tp = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(c),
    )..layout();
    final w = tp.width, h = tp.height;
    final whole = math.max(widget.from.abs(), widget.value.abs()).floor();
    final places = '$whole'.length;
    return Semantics(
      label: widget.value.toStringAsFixed(widget.decimals),
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final v = _shown;
            // Each place's position from the last one up: the last turns with
            // the value, a higher one by the carry of the place below.
            final pos = <double>[];
            var carry = 0.0;
            for (var k = -widget.decimals; k < places; k++) {
              final at = v / math.pow(10, k);
              final p = k == -widget.decimals
                  ? at % 10
                  : (at.floor() % 10) + carry;
              pos.add(p);
              carry = p > 9 ? p - 9 : 0;
            }
            Widget digit(int k) {
              final p = pos[k + widget.decimals];
              final base = p.floor();
              final frac = p - base;
              // A leading place the figure has not reached yet stays blank.
              String face(int d) =>
                  k > 0 && v < math.pow(10, k) && d % 10 == 0 ? '' : '${d % 10}';
              return ClipRect(
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(children: [
                    Positioned(
                        left: 0,
                        right: 0,
                        top: -frac * h,
                        child: Text(face(base),
                            textAlign: TextAlign.center, style: style)),
                    Positioned(
                        left: 0,
                        right: 0,
                        top: (1 - frac) * h,
                        child: Text(face(base + 1),
                            textAlign: TextAlign.center, style: style)),
                  ]),
                ),
              );
            }

            return Row(mainAxisSize: MainAxisSize.min, children: [
              for (var k = places - 1; k >= 0; k--) digit(k),
              if (widget.decimals > 0) Text('.', style: style),
              for (var k = -1; k >= -widget.decimals; k--) digit(k),
            ]);
          },
        ),
      ),
    );
  }
}
