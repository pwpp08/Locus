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
enum StatMark {
  zonesLow,
  zonesHigh,
  strength,
  steps,
  // Sleep's contributors.
  hoursNeeded,
  consistency,
  efficiency,
  sleepStress,
  // Recovery's contributors.
  hrv,
  restingHr,
  respRate,
  sleepPerf,
  // Behavior Insights' door.
  bulb,
  // The Profile page's badges.
  heartDown,
  heartUp,
  pulseDown,
  pulseUp,
  lotus,
  lifter,
  flame,
  heartbeat,
}

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

  /// The upright arrow at the right of the grid: pointing up, or down.
  static void _arrow(Canvas canvas, Paint line, bool up) {
    const x = 19.8, top = 7.0, foot = 17.6, k = 3.1;
    canvas.drawLine(const Offset(x, top), const Offset(x, foot), line);
    final tip = up ? top : foot;
    final back = up ? top + k : foot - k;
    canvas.drawPath(
        Path()
          ..moveTo(x - k, back)
          ..lineTo(x, tip)
          ..lineTo(x + k, back),
        line);
  }

  /// The crescent of a circle with a second one bitten out of it.
  static Path _moon(Offset c1, double r1, Offset c2, double r2) => Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c1, radius: r1)),
      Path()..addOval(Rect.fromCircle(center: c2, radius: r2)));

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
      case StatMark.hoursNeeded:
        // A crescent with clock hands in its hollow.
        canvas.drawPath(_moon(const Offset(11.8, 12), 11, const Offset(15, 12), 8.6), line);
        canvas.drawPath(
            Path()
              ..moveTo(15.4, 7.6)
              ..lineTo(15.4, 12)
              ..lineTo(18.4, 15),
            line);
      case StatMark.consistency:
        // Three crescents, each a night like the last.
        canvas.drawPath(_moon(const Offset(10.6, 12), 10, const Offset(13.6, 12), 8), line);
        canvas.drawPath(
            Path()..addArc(Rect.fromCircle(center: const Offset(16.4, 12), radius: 7),
                math.pi * .22, math.pi * 1.56),
            line);
      case StatMark.efficiency:
        // Four bars standing over a bed.
        for (final (x, top) in const [
          (3.2, 11.0),
          (8.8, 7.4),
          (14.6, 2.6),
          (20.2, 5.0),
        ]) {
          canvas.drawPath(
              Path()
                ..moveTo(x - 1.9, 14.6)
                ..lineTo(x - 1.9, top + 1.9)
                ..arcToPoint(Offset(x + 1.9, top + 1.9),
                    radius: const Radius.circular(1.9))
                ..lineTo(x + 1.9, 14.6),
              line);
        }
        canvas.drawPath(
            Path()
              ..moveTo(1.2, 15.8)
              ..lineTo(1.2, 21.8)
              ..moveTo(1.2, 19.4)
              ..lineTo(22.8, 19.4)
              ..lineTo(22.8, 21.8)
              ..moveTo(3.4, 19.4)
              ..lineTo(3.4, 17.2)
              ..lineTo(8.4, 17.2)
              ..cubicTo(13, 15.2, 19, 15.6, 22.4, 19),
            line);
      case StatMark.sleepStress:
        // A gauge, open at the foot, its needle at the top right.
        const dial = Rect.fromLTRB(1.8, 2.6, 22.2, 23);
        canvas.drawArc(dial, math.pi * .85, math.pi * .87, false, line);
        canvas.drawArc(dial, math.pi * 1.9, math.pi * .3, false, line);
        canvas.drawLine(const Offset(15.4, 10.4), const Offset(19.6, 4.4), line);
      case StatMark.hrv:
        // A slanted pulse through a rounded band.
        canvas.drawPath(
            Path()
              ..moveTo(9.4, 8.6)
              ..lineTo(3, 8.6)
              ..cubicTo(1.2, 8.6, 1.2, 12, 3, 12)
              ..lineTo(7.2, 12)
              ..lineTo(7, 19.4)
              ..cubicTo(7, 21.2, 9.4, 21.2, 10.2, 19.6)
              ..lineTo(14.6, 5)
              ..cubicTo(15.2, 3.2, 17.4, 3.2, 17.4, 5)
              ..lineTo(17.4, 8.6)
              ..lineTo(21, 8.6)
              ..cubicTo(22.8, 8.6, 22.8, 12, 21, 12)
              ..lineTo(13.2, 12),
            line);
      case StatMark.restingHr:
        // A heart and, beside it, an arrow going down.
        canvas.save();
        canvas.translate(-1, .4);
        canvas.scale(.78);
        canvas.drawPath(_heart(), line..strokeWidth = 1.7);
        canvas.restore();
        line.strokeWidth = 1.35;
        canvas.drawLine(const Offset(19.2, 8.4), const Offset(19.2, 18.4), line);
        canvas.drawPath(
            Path()
              ..moveTo(15.6, 14.8)
              ..lineTo(19.2, 18.4)
              ..lineTo(22.8, 14.8),
            line);
      case StatMark.respRate:
        // A pair of lungs on a windpipe.
        canvas.drawLine(const Offset(12, 3), const Offset(12, 12.2), line);
        canvas.drawPath(
            Path()
              ..moveTo(9.6, 8.4)
              ..cubicTo(6, 8.2, 2.4, 13.6, 2.2, 17.4)
              ..cubicTo(2.2, 20.6, 6, 21.4, 9, 19.8)
              ..cubicTo(10.4, 19, 10.4, 17.4, 10.4, 16)
              ..lineTo(10.4, 10)
              ..cubicTo(10.4, 9.2, 10.2, 8.6, 9.6, 8.4),
            line);
        canvas.drawPath(
            Path()
              ..moveTo(14.4, 8.4)
              ..cubicTo(18, 8.2, 21.6, 13.6, 21.8, 17.4)
              ..cubicTo(21.8, 20.6, 18, 21.4, 15, 19.8)
              ..cubicTo(13.6, 19, 13.6, 17.4, 13.6, 16)
              ..lineTo(13.6, 10)
              ..cubicTo(13.6, 9.2, 13.8, 8.6, 14.4, 8.4),
            line);
        canvas.drawLine(const Offset(12, 12.2), const Offset(7.6, 15.6), line);
        canvas.drawLine(const Offset(12, 12.2), const Offset(16.4, 15.6), line);
      case StatMark.bulb:
        // A bulb with its rays.
        canvas.drawArc(const Rect.fromLTRB(7, 6.4, 17, 16.4), math.pi * .75,
            math.pi * 1.5, false, line);
        canvas.drawPath(
            Path()
              ..moveTo(8.5, 14.9)
              ..lineTo(9.6, 18)
              ..lineTo(14.4, 18)
              ..lineTo(15.5, 14.9)
              ..moveTo(10, 20.6)
              ..lineTo(14, 20.6),
            line);
        for (final (a, b, c, d) in const [
          (12.0, 1.4, 12.0, 3.8),
          (4.4, 4.4, 6.1, 6.1),
          (19.6, 4.4, 17.9, 6.1),
          (1.2, 11.4, 3.6, 11.4),
          (20.4, 11.4, 22.8, 11.4),
        ]) {
          canvas.drawLine(Offset(a, b), Offset(c, d), line);
        }
      case StatMark.heartDown:
      case StatMark.heartUp:
        // A heart, and beside it the arrow.
        canvas.save();
        canvas.translate(-.6, 3.7);
        canvas.scale(.68);
        canvas.drawPath(_heart(), Paint.from(line)..strokeWidth = 1.98);
        canvas.restore();
        _arrow(canvas, line, mark == StatMark.heartUp);
      case StatMark.pulseDown:
      case StatMark.pulseUp:
        // A beat of the heart trace, and beside it the arrow.
        canvas.drawPath(
            Path()
              ..moveTo(1.6, 13.4)
              ..lineTo(5, 13.4)
              ..lineTo(8.2, 6.2)
              ..lineTo(11.6, 18)
              ..lineTo(14.2, 11.4),
            line);
        _arrow(canvas, line, mark == StatMark.pulseUp);
      case StatMark.lotus:
        // A figure sitting cross-legged, hands on the knees.
        canvas.drawCircle(const Offset(12, 4.4), 2.3, line);
        canvas.drawPath(
            Path()
              ..moveTo(12, 8.6)
              ..cubicTo(9.6, 8.6, 8.8, 10.2, 7.6, 11.8)
              ..lineTo(3.8, 15.2)
              ..moveTo(12, 8.6)
              ..cubicTo(14.4, 8.6, 15.2, 10.2, 16.4, 11.8)
              ..lineTo(20.2, 15.2)
              ..moveTo(9.4, 10.2)
              ..lineTo(9.8, 15)
              ..moveTo(14.6, 10.2)
              ..lineTo(14.2, 15),
            line);
        canvas.drawPath(
            Path()
              ..moveTo(2.4, 17.2)
              ..cubicTo(7.6, 16.2, 14.6, 18.6, 18.8, 21)
              ..moveTo(21.6, 17.2)
              ..cubicTo(16.4, 16.2, 9.4, 18.6, 5.2, 21),
            line);
      case StatMark.lifter:
        // A barbell held overhead: the bar, its plates, the arms and body.
        canvas.drawLine(const Offset(3.4, 6.4), const Offset(20.6, 6.4), line);
        for (final (x, h) in const [
          (1.8, 1.7),
          (4.4, 3.1),
          (19.6, 3.1),
          (22.2, 1.7),
        ]) {
          canvas.drawLine(Offset(x, 6.4 - h), Offset(x, 6.4 + h), line);
        }
        canvas.drawPath(
            Path()
              ..moveTo(7.6, 6.4)
              ..lineTo(9.8, 14)
              ..lineTo(10.6, 21)
              ..lineTo(13.4, 21)
              ..lineTo(14.2, 14)
              ..lineTo(16.4, 6.4),
            line);
        canvas.drawCircle(const Offset(12, 10.4), 2, line);
      case StatMark.flame:
        canvas.drawPath(
            Path()
              ..moveTo(12, 2.4)
              ..cubicTo(12.6, 6.4, 18.8, 9.4, 18.8, 15)
              ..cubicTo(18.8, 19, 15.8, 21.7, 12, 21.7)
              ..cubicTo(8.2, 21.7, 5.2, 19, 5.2, 15)
              ..cubicTo(5.2, 12.8, 6.3, 11, 7.6, 9.8)
              ..cubicTo(7.8, 11.8, 8.8, 13, 10.2, 13.4)
              ..cubicTo(9.4, 9.6, 10, 5.4, 12, 2.4)
              ..close(),
            line);
      case StatMark.heartbeat:
        // A heart with one beat across it.
        canvas.drawPath(_heart(), line);
        canvas.drawPath(
            Path()
              ..moveTo(6.4, 11.8)
              ..lineTo(9.4, 11.8)
              ..lineTo(11, 8.6)
              ..lineTo(13.2, 15)
              ..lineTo(14.6, 11.8)
              ..lineTo(17.6, 11.8),
            line);
      case StatMark.sleepPerf:
        // One thin crescent, open at the top right.
        canvas.drawPath(
            Path()
              ..moveTo(17.6, 1.8)
              ..cubicTo(22.6, 8, 22.4, 16.4, 16.8, 20.2)
              ..cubicTo(11, 23.8, 4.6, 21.4, 1.6, 18.2)
              ..cubicTo(9.6, 21, 19, 13.4, 17.6, 1.8)
              ..close(),
            line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StatPaint old) => old.mark != mark || old.color != color;
}

/// A [StatMark] inside a fine scalloped ring, its rim a dimmer [color]: the
/// Profile page's badges.
class ScallopMark extends StatelessWidget {
  final StatMark mark;
  final Color color;
  final double size;
  const ScallopMark(this.mark,
      {super.key, required this.color, this.size = PH.badge});

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          painter: _ScallopPaint(color.withValues(alpha: .6)),
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: StatIcon(mark, color: color, size: size * .57),
            ),
          ),
        ),
      );
}

class _ScallopPaint extends CustomPainter {
  final Color color;
  _ScallopPaint(this.color);

  static const _lobes = 12, _depth = .055;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - PH.badgeStroke / 2;
    final path = Path();
    const steps = _lobes * 16;
    for (var i = 0; i <= steps; i++) {
      final a = 2 * math.pi * i / steps - math.pi / 2;
      final d = r * (1 - _depth + _depth * math.cos(_lobes * (a + math.pi / 2)));
      final p = c + Offset(math.cos(a) * d, math.sin(a) * d);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path..close(),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = PH.badgeStroke
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_ScallopPaint old) => old.color != color;
}

/// The coach's mark: a speech bubble with a heartbeat in it — the coach
/// talking about your body. Drawn on Lucide's 24 grid at its 300 weight
/// (1.5), so it sits beside the icon font's glyphs as one of them; sized and
/// tinted like an [Icon] (the [IconTheme]'s colour when [color] is null).
class CoachMark extends StatelessWidget {
  final double size;
  final Color? color;

  const CoachMark({super.key, this.size = I.lg, this.color});

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          painter: _CoachPaint(color ?? IconTheme.of(c).color ?? P.of(c).ink),
        ),
      );
}

class _CoachPaint extends CustomPainter {
  final Color color;
  _CoachPaint(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // Lucide's 300 weight, but never under one logical pixel: at the orb's
      // smallest the bubble would otherwise thin to a hairline.
      ..strokeWidth = math.max(1.5, 24 / size.width)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The bubble: a rounded square with its tail dropped from the bottom
    // edge, square on the left like a quote mark's.
    const l = 3.0, t = 3.5, r = 21.0, b = 17.0, k = 3.5;
    canvas.drawPath(
        Path()
          ..moveTo(l + k, t)
          ..lineTo(r - k, t)
          ..arcToPoint(const Offset(r, t + k), radius: const Radius.circular(k))
          ..lineTo(r, b - k)
          ..arcToPoint(const Offset(r - k, b), radius: const Radius.circular(k))
          ..lineTo(11.5, b)
          ..lineTo(8, 20.5)
          ..lineTo(8, b)
          ..lineTo(l + k, b)
          ..arcToPoint(const Offset(l, b - k), radius: const Radius.circular(k))
          ..lineTo(l, t + k)
          ..arcToPoint(const Offset(l + k, t), radius: const Radius.circular(k))
          ..close(),
        line);
    // The heartbeat across it.
    canvas.drawPath(
        Path()
          ..moveTo(6.5, 10.25)
          ..lineTo(9, 10.25)
          ..lineTo(10.5, 7.25)
          ..lineTo(13, 13.25)
          ..lineTo(14.5, 10.25)
          ..lineTo(17.5, 10.25),
        line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoachPaint old) => old.color != color;
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
  const SyncArrowMark({super.key, this.color = C.strainDown});

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

  /// A unit after the figure ("kg"), sat on the figure's baseline.
  final String? unit;
  final TextStyle? unitStyle;

  const RollingNumber({
    super.key,
    required this.from,
    required this.value,
    required this.style,
    this.decimals = 1,
    this.onTick,
    this.onDone,
    this.unit,
    this.unitStyle,
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

  /// The figure under way, in units of its last digit and rid of the float
  /// noise that left 71.4 resting a hair under its 4.
  double get _shown {
    final v = widget.from +
        (widget.value - widget.from) * Ease.standard.transform(_c.value);
    final s = math.pow(10, widget.decimals);
    return (v * s * 1e6).roundToDouble() / 1e6 / s;
  }

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
    // How far the unit's baseline sits from its box's foot, against the
    // figure's: the unit drops by the difference to share the baseline.
    double foot(TextPainter t) =>
        t.height - t.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final unit = widget.unit;
    final unitTp = unit == null
        ? null
        : (TextPainter(
            text: TextSpan(text: unit, style: widget.unitStyle ?? style),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(c),
          )..layout());
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

            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var k = places - 1; k >= 0; k--) digit(k),
                if (widget.decimals > 0) Text('.', style: style),
                for (var k = -1; k >= -widget.decimals; k--) digit(k),
                if (unitTp != null) ...[
                  const SizedBox(width: S.x1),
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: math.max(0.0, foot(tp) - foot(unitTp))),
                    child: Text(unit!, style: widget.unitStyle ?? style),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
