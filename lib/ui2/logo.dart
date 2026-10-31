// The Locus mark: a cursive L, one continuous stroke with a loop at the top
// and one at the foot. The outline is the source artwork traced
// (logo_geometry.dart, 99.3% pixel overlap); the brand files are cut from the
// same outline (assets/brand/*.svg), and so is the launcher icon.
//
// It is DRAWN the way it was written: the pen runs the stroke's own route —
// in at the crossbar, up and round the top loop, down the stem, round the foot
// loop and out along the leg — and the ink it lays is clipped to the exact
// outline, so the finished drawing IS the mark, not an approximation of it.
// That is the threads-style reveal: a wide pen, a precise mask.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'logo_geometry.dart';
import 'theme.dart';

/// The colourways the mark comes in. [ink] follows the theme (white on dark,
/// near-black on light); the rest are the dials' own colours.
enum LocusTint { ink, strain, recovery, sleep, dials }

/// The pen's route, measured once: where each sample is, how wide the pen is
/// there, and how far along the route it lies.
class _Route {
  static final _Route i = _Route._();
  final List<Offset> at = [];
  final List<double> r = [], cum = [0];
  final Path outline = locusOutlinePath();

  _Route._() {
    for (var k = 0; k < kLocusRoute.length; k += 3) {
      at.add(Offset(kLocusRoute[k], kLocusRoute[k + 1]));
      r.add(kLocusRoute[k + 2]);
    }
    for (var k = 1; k < at.length; k++) {
      cum.add(cum.last + (at[k] - at[k - 1]).distance);
    }
  }

  double get length => cum.last;
}

/// Paints the mark with the ink between [erase] and [draw] (shares of the
/// route) laid down. Fully drawn, it is the outline filled.
class LocusMarkPainter extends CustomPainter {
  final double draw, erase;
  final LocusTint tint;

  /// The ink for [LocusTint.ink]; the theme's, read by the widget.
  final Color ink;

  /// The whole mark in this colour under the ink, so the drawing is white
  /// written into a gray one (the pull to refresh); none for the plain mark.
  final Color? base;

  const LocusMarkPainter({
    this.draw = 1,
    this.erase = 0,
    this.tint = LocusTint.ink,
    this.ink = C.white,
    this.base,
  });

  Paint _paint() {
    final p = Paint()..isAntiAlias = true;
    switch (tint) {
      case LocusTint.ink:
        p.color = ink;
      case LocusTint.strain:
        p.color = C.dialStrain;
      case LocusTint.recovery:
        p.color = C.optimal;
      case LocusTint.sleep:
        p.color = C.dialSleep;
      case LocusTint.dials:
        p.shader = const LinearGradient(
          begin: Alignment(-.6, -.5),
          end: Alignment(.5, .6),
          colors: [C.dialStrain, C.optimal],
        ).createShader(const Rect.fromLTWH(0, 0, 1000, 1000));
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width, size.height) / 1000;
    canvas.save();
    canvas.translate((size.width - 1000 * k) / 2, (size.height - 1000 * k) / 2);
    canvas.scale(k);
    final route = _Route.i;
    if (base != null) {
      canvas.drawPath(route.outline, Paint()..color = base!..isAntiAlias = true);
    }
    final paint = _paint();
    final a = erase.clamp(0.0, 1.0) * route.length;
    final b = draw.clamp(0.0, 1.0) * route.length;
    if (a <= 0 && b >= route.length) {
      canvas.drawPath(route.outline, paint);
    } else if (b > a) {
      canvas.clipPath(route.outline);
      paint
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var s = 0; s < route.at.length - 1; s++) {
        final s0 = route.cum[s], s1 = route.cum[s + 1];
        final from = math.max(a, s0), to = math.min(b, s1);
        if (to <= from) continue;
        final p0 = route.at[s], p1 = route.at[s + 1];
        final len = s1 - s0;
        Offset at(double d) =>
            len <= 0 ? p0 : Offset.lerp(p0, p1, (d - s0) / len)!;
        paint.strokeWidth = 2 * math.max(route.r[s], route.r[s + 1]);
        canvas.drawLine(at(from), at(to), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LocusMarkPainter o) =>
      o.draw != draw ||
      o.erase != erase ||
      o.tint != tint ||
      o.ink != ink ||
      o.base != base;
}

/// The mark as a widget. Still by default; [animate] writes it once, and
/// [loop] keeps writing it — in, a hold, the pen lifting the ink back off from
/// where it started — for as long as something is being waited on. Reduced
/// motion shows it still.
class LocusMark extends StatefulWidget {
  final double size;
  final bool animate, loop;
  final LocusTint tint;

  /// Once the first drawing is complete.
  final VoidCallback? onDrawn;

  const LocusMark({
    super.key,
    this.size = S.x16,
    this.animate = false,
    this.loop = false,
    this.tint = LocusTint.ink,
    this.onDrawn,
  });

  @override
  State<LocusMark> createState() => _LocusMarkState();
}

class _LocusMarkState extends State<LocusMark>
    with SingleTickerProviderStateMixin {
  // One timeline. Written once, the pen takes the first 80% (ease in and
  // out) and the mark holds. Looping, it writes in the first half, holds, and
  // the ink lifts off from the start in the last stretch.
  // Made in initState, never lazily: a still mark that never touched it
  // would otherwise create its ticker in dispose, off a dead element.
  late final AnimationController _c;
  bool _started = false, _told = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }

  bool get _moving => widget.animate || widget.loop;
  double get _drawn => widget.loop ? .5 : .8;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !_moving) return;
    _started = true;
    final d = motion(context, Motion.logo);
    if (d == Duration.zero) {
      _c.value = 1;
      _land();
      return;
    }
    _c.duration = d;
    _c.addListener(() {
      if (_c.value >= _drawn) _land();
    });
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && widget.loop && mounted) {
        _c.forward(from: 0);
      }
    });
    _c.forward();
  }

  void _land() {
    if (_told) return;
    _told = true;
    widget.onDrawn?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _span(double t, double a, double b, [Curve c = Curves.linear]) =>
      c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext c) {
    final ink = P.of(c).ink;
    final mark = SizedBox.square(
      dimension: widget.size,
      child: _moving
          ? AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                final t = _c.value;
                final loop = widget.loop;
                return CustomPaint(
                  painter: LocusMarkPainter(
                    draw: _span(t, 0, _drawn, Curves.easeInOutCubic),
                    erase: loop ? _span(t, .72, .97, Curves.easeInOutCubic) : 0,
                    tint: widget.tint,
                    ink: ink,
                  ),
                );
              },
            )
          : CustomPaint(
              painter: LocusMarkPainter(tint: widget.tint, ink: ink)),
    );
    return Semantics(label: 'Locus', image: true, child: mark);
  }
}

/// How much of the wordmark's weight is shaved off, in logical pixels across a
/// stroke (half each side). Super Bubble is one heavy weight; this is a
/// lighter cut of it, made at paint time so the font file stays exactly as its
/// author drew it.
const double kWordmarkThin = 1.2;

/// LOCUS, in Super Bubble ([F.wordmark]) a little lighter than the font draws
/// it. The word is painted into its own layer under an erode filter, which
/// eats the rendered letters in from every edge (and opens up the tiny
/// counters this heavy a face has: the O's hole, the U's slit). It works on
/// the pixels, not the outlines, so it holds on any ground, a gradient
/// included.
class Wordmark extends StatelessWidget {
  final Color color;

  /// The word; LOCUS everywhere.
  final String text;
  const Wordmark({super.key, required this.color, this.text = 'LOCUS'});

  @override
  Widget build(BuildContext c) {
    final fill = TextPainter(
      text: TextSpan(text: text, style: F.wordmark.copyWith(color: color)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(c),
    )..layout();
    return Semantics(
      label: 'Locus',
      header: true,
      excludeSemantics: true,
      child: CustomPaint(
        size: fill.size,
        painter: _WordmarkPainter(fill),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  final TextPainter fill;
  _WordmarkPainter(this.fill);

  @override
  void paint(Canvas canvas, Size size) {
    const r = kWordmarkThin / 2;
    canvas.saveLayer(
      (Offset.zero & size).inflate(S.x1),
      Paint()..imageFilter = ui.ImageFilter.erode(radiusX: r, radiusY: r),
    );
    fill.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter o) => o.fill != fill;
}

/// The wordmark gray, white written into it from left to right: the pull to
/// refresh. [fill] is how much of the word has been written, 0…1; the edge of
/// the white is soft, so it reads as ink spreading rather than a wipe.
class WordmarkFill extends StatelessWidget {
  final double fill;

  /// The unwritten word, and the ink written over it.
  final Color base, ink;
  const WordmarkFill(
      {super.key, required this.fill, required this.base, required this.ink});

  @override
  Widget build(BuildContext c) {
    const soft = .22;
    final f = fill.clamp(0.0, 1.0);
    // The edge runs from `f - soft` to `f`, scaled so 0 starts clear of the
    // first letter and 1 is past the last.
    final edge = f * (1 + soft);
    return Stack(
      children: [
        Wordmark(color: base),
        if (f > 0)
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => LinearGradient(
              colors: [C.white, C.white, C.white.withValues(alpha: 0)],
              stops: [0, (edge - soft).clamp(0.0, 1.0), edge.clamp(0.0, 1.0)],
            ).createShader(r),
            child: Wordmark(color: ink),
          ),
      ],
    );
  }
}
