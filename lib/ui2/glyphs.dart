// Glyphs the icon set does not have, drawn on the same 24 pt grid and 1.5 pt
// round stroke as the Lucide set so they sit beside it: the group of three
// (the Community tab, Enter invite code, Humans), a group with a magnifier,
// and a page with a magnifier (Discover more).

import 'package:flutter/material.dart';

import 'theme.dart';

/// Which glyph.
enum GlyphKind { group, groupSearch, fileSearch }

/// A stroked glyph at [size], in [color].
class Glyph extends StatelessWidget {
  final GlyphKind kind;
  final double size;
  final Color color;
  const Glyph(this.kind, {super.key, this.size = I.lg, required this.color});

  /// Three people: a head each, the middle one tall, the sides hooked in.
  const Glyph.group({super.key, this.size = I.lg, required this.color})
      : kind = GlyphKind.group;

  /// The group with a magnifier at its lower right.
  const Glyph.groupSearch({super.key, this.size = I.lg, required this.color})
      : kind = GlyphKind.groupSearch;

  /// A page of text lines with a magnifier at its lower right.
  const Glyph.fileSearch({super.key, this.size = I.lg, required this.color})
      : kind = GlyphKind.fileSearch;

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _GlyphPainter(kind, color)),
        ),
      );
}

class _GlyphPainter extends CustomPainter {
  final GlyphKind kind;
  final Color color;
  const _GlyphPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 24;
    canvas.scale(k);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    switch (kind) {
      case GlyphKind.group:
        _group(canvas, line);
      case GlyphKind.groupSearch:
        canvas.saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint());
        canvas.save();
        canvas.translate(.6, -.2);
        canvas.scale(.9);
        _group(canvas, line);
        canvas.restore();
        // Rubbed out under the lens so the bodies do not run through it.
        canvas.drawCircle(const Offset(16.2, 16.4), 5,
            Paint()..blendMode = BlendMode.clear);
        canvas.restore();
        _lens(canvas, line, const Offset(16.2, 16.4), 3.4);
      case GlyphKind.fileSearch:
        final page = Path()
          ..moveTo(13.5, 3)
          ..lineTo(6.6, 3)
          ..quadraticBezierTo(4.5, 3, 4.5, 5.1)
          ..lineTo(4.5, 18.9)
          ..quadraticBezierTo(4.5, 21, 6.6, 21)
          ..lineTo(8.5, 21)
          ..moveTo(13.5, 3)
          ..lineTo(19.5, 8.2)
          ..lineTo(19.5, 10.5)
          ..moveTo(13.5, 3)
          ..lineTo(13.5, 7)
          ..quadraticBezierTo(13.5, 8.2, 14.7, 8.2)
          ..lineTo(19.5, 8.2);
        canvas.drawPath(page, line);
        canvas.drawLine(const Offset(7.8, 9), const Offset(11.6, 9), line);
        canvas.drawLine(const Offset(7.8, 12.6), const Offset(9.8, 12.6), line);
        canvas.drawLine(const Offset(7.8, 16.2), const Offset(9.8, 16.2), line);
        _lens(canvas, line, const Offset(15, 15.6), 3.8);
    }
  }

  void _lens(Canvas canvas, Paint line, Offset c, double r) {
    canvas.drawCircle(c, r, line);
    final d = r * .72;
    canvas.drawLine(c + Offset(d, d), c + Offset(d + 3.2, d + 3.2), line);
  }

  void _group(Canvas canvas, Paint line) {
    canvas.drawCircle(const Offset(12, 6.2), 2.4, line);
    canvas.drawPath(
        Path()
          ..moveTo(8.6, 19.5)
          ..lineTo(8.6, 12.9)
          ..quadraticBezierTo(8.6, 10.6, 10.9, 10.6)
          ..lineTo(13.1, 10.6)
          ..quadraticBezierTo(15.4, 10.6, 15.4, 12.9)
          ..lineTo(15.4, 19.5),
        line);
    for (final m in const [1.0, -1.0]) {
      double x(double v) => 12 + m * (v - 12) * -1;
      // Left (m = 1) then its mirror about x = 12.
      canvas.drawCircle(Offset(x(18.7), 8.4), 1.8, line);
      canvas.drawPath(
          Path()
            ..moveTo(x(21), 18.6)
            ..lineTo(x(21), 14.7)
            ..quadraticBezierTo(x(21), 12.6, x(18.9), 12.6)
            ..lineTo(x(17.7), 12.6),
          line);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter o) => o.kind != kind || o.color != color;
}
