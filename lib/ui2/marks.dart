// Small drawn marks: the stat-row icons and the triangles that say above or
// below. Drawn rather than taken from the icon font so a stroke can be as fine
// as the screen wants, and so each sits on the same 24-unit grid.

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
