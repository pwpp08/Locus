// The Locus Age blob: a ring of springs with a cloud of specks inside it.
//
// [BlobSim] is the physics, with no Flutter in it, so a test can drive it.
// [LocusBlobPainter] draws one frame of it and repaints on its own notifier:
// the blob moves sixty times a second without a single widget rebuilding.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme.dart';

double _wrap(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

/// The whole blob, in units of its resting radius, centred on the origin.
class BlobSim {
  static const nodeCount = 72;
  static const dotCount = 340;

  // A soft ring: stiff enough to come home in about a second, loose enough
  // that a poke travels round it.
  static const _pull = 34.0, _couple = 60.0, _damp = 5.5;
  static const _dotPull = 22.0, _dotDamp = 5.0;
  static const _maxOffset = .24;

  final _r = Float64List(nodeCount), _v = Float64List(nodeCount);
  final _homeA = Float64List(dotCount), _homeR = Float64List(dotCount);
  final _spin = Float64List(dotCount), _phase = Float64List(dotCount);
  final _size = Float64List(dotCount);
  final _dx = Float64List(dotCount), _dy = Float64List(dotCount);
  final _vx = Float64List(dotCount), _vy = Float64List(dotCount);
  double _t = 0;
  double? _fx, _fy;

  BlobSim({int seed = 11}) {
    final rng = math.Random(seed);
    for (var i = 0; i < dotCount; i++) {
      final a = rng.nextDouble() * 2 * math.pi;
      // Clumped a little, so the specks read as drifting matter and not an
      // even sprinkle.
      _homeA[i] = a + .25 * math.sin(3 * a);
      // Most of them live in the bright ring, leaving the middle for the age.
      _homeR[i] = rng.nextDouble() < .86
          ? .98 - .43 * math.pow(rng.nextDouble(), 1.4)
          : .32 + .23 * rng.nextDouble();
      _spin[i] = (rng.nextBool() ? 1 : -1) * (.02 + rng.nextDouble() * .06);
      _phase[i] = rng.nextDouble() * 2 * math.pi;
      _size[i] = .7 + 2.6 * math.pow(rng.nextDouble(), 3);
    }
    for (var i = 0; i < nodeCount; i++) {
      _r[i] = _rest(_angle(i));
    }
  }

  double _angle(int i) => i / nodeCount * 2 * math.pi;

  /// The slow idle shape: a few sines drifting against each other, and a
  /// breath over the whole of it.
  double _rest(double a) =>
      .036 * math.sin(2 * a + _t * .31) +
      .030 * math.sin(3 * a - _t * .43 + 1.3) +
      .014 * math.sin(5 * a + _t * .67 + .7) +
      .012 * math.sin(_t * .9);

  /// Where the rim is at node [i], as a multiple of the resting radius.
  double radiusAt(int i) => 1 + _r[i];

  double angleAt(int i) => _angle(i);

  double dotX(int i) => _dotPos(i).$1;
  double dotY(int i) => _dotPos(i).$2;
  double dotSize(int i) => _size[i];

  /// How far from the middle dot [i] sits at rest.
  double dotHomeRadius(int i) => _homeR[i];

  /// Its twinkle, 0.1 to 1.
  double dotGlow(int i) =>
      .55 + .45 * math.sin(_phase[i] + _t * (.6 + _size[i] * .25));

  (double, double) _dotPos(int i) {
    final a = _homeA[i];
    // Specks ride the rim's swell, the outer ones most.
    final n = ((_wrap(a) + 2 * math.pi) / (2 * math.pi) * nodeCount).floor() %
        nodeCount;
    final h = _homeR[i] * (1 + _r[n] * _homeR[i]);
    return (h * math.cos(a) + _dx[i], h * math.sin(a) + _dy[i]);
  }

  /// A finger is on the blob at ([x], [y]). The rim reaches for it and the
  /// specks scatter from under it.
  void press(double x, double y) {
    _fx = x;
    _fy = y;
  }

  void release() {
    _fx = _fy = null;
  }

  /// A quick tap: the rim gives way where it was struck, the rest draws in,
  /// and the specks nearby are thrown clear.
  void tap(double x, double y) {
    final at = math.atan2(y, x);
    for (var i = 0; i < nodeCount; i++) {
      final d = _wrap(_angle(i) - at);
      _v[i] -= .5 + 1.5 * math.exp(-(d * d) / .5);
    }
    for (var i = 0; i < dotCount; i++) {
      final (px, py) = _dotPos(i);
      final dx = px - x, dy = py - y;
      final d2 = dx * dx + dy * dy;
      final d = math.sqrt(d2) + .001;
      final kick = 2.2 * math.exp(-d2 / .4);
      _vx[i] += dx / d * kick;
      _vy[i] += dy / d * kick;
    }
  }

  /// Move on by [dt] seconds. A long frame is cut short, not integrated: the
  /// springs would blow up, and a blob that skips reads no worse than a list
  /// that does.
  void step(double dt) {
    final span = dt.clamp(0.0, 1 / 30);
    const steps = 2;
    final h = span / steps;
    for (var s = 0; s < steps; s++) {
      _t += h;
      _stepRing(h);
      _stepDots(h);
    }
  }

  void _stepRing(double h) {
    final fx = _fx, fy = _fy;
    final fa = fx == null ? 0.0 : math.atan2(fy!, fx);
    final fd = fx == null ? 0.0 : math.sqrt(fx * fx + fy! * fy);
    for (var i = 0; i < nodeCount; i++) {
      var target = _rest(_angle(i));
      if (fx != null && fd < 1.5) {
        final d = _wrap(_angle(i) - fa);
        target += math.exp(-(d * d) / .3) * .1 * (.35 + fd.clamp(0.0, 1.0));
      }
      final l = _r[(i + nodeCount - 1) % nodeCount];
      final r = _r[(i + 1) % nodeCount];
      _v[i] += h *
          (_pull * (target - _r[i]) +
              _couple * (l + r - 2 * _r[i]) -
              _damp * _v[i]);
    }
    for (var i = 0; i < nodeCount; i++) {
      _r[i] = (_r[i] + h * _v[i]).clamp(-_maxOffset, _maxOffset);
    }
  }

  void _stepDots(double h) {
    final fx = _fx, fy = _fy;
    for (var i = 0; i < dotCount; i++) {
      _homeA[i] += _spin[i] * h;
      var ax = -_dotPull * _dx[i] - _dotDamp * _vx[i];
      var ay = -_dotPull * _dy[i] - _dotDamp * _vy[i];
      if (fx != null) {
        final (px, py) = _dotPos(i);
        final rx = px - fx, ry = py - fy!;
        final d = math.sqrt(rx * rx + ry * ry) + .001;
        if (d < .6) {
          final push = 16 * (1 - d / .6);
          ax += rx / d * push;
          ay += ry / d * push;
        }
      }
      _vx[i] += h * ax;
      _vy[i] += h * ay;
      _dx[i] += h * _vx[i];
      _dy[i] += h * _vy[i];
    }
  }
}

/// Paints [sim] at resting radius [radius] around the middle of its canvas,
/// which must be big enough to take the swell and the glow.
class LocusBlobPainter extends CustomPainter {
  final BlobSim sim;
  final double radius;
  final Color top, bottom;

  LocusBlobPainter({
    required this.sim,
    required this.radius,
    required this.top,
    required this.bottom,
    super.repaint,
  });

  Path _outline(Offset c) {
    final pts = [
      for (var i = 0; i < BlobSim.nodeCount; i++)
        c +
            Offset.fromDirection(sim.angleAt(i), radius * sim.radiusAt(i)),
    ];
    Offset mid(int i) =>
        (pts[i % pts.length] + pts[(i + 1) % pts.length]) / 2;
    final p = Path()..moveTo(mid(0).dx, mid(0).dy);
    for (var i = 1; i <= pts.length; i++) {
      final q = pts[i % pts.length], m = mid(i);
      p.quadraticBezierTo(q.dx, q.dy, m.dx, m.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = _outline(c);
    final box = Rect.fromCircle(center: c, radius: radius * 1.28);
    final body = Rect.fromCircle(center: c, radius: radius * 1.05);
    final tone = ui.Gradient.linear(
      Offset(c.dx, c.dy - radius),
      Offset(c.dx, c.dy + radius),
      [top, bottom],
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = tone
        ..colorFilter = const ColorFilter.mode(AC.blobGlow, BlendMode.dstIn)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .09),
    );

    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(box, Paint()..shader = tone);
    canvas.drawRect(
      box,
      Paint()
        ..shader = ui.Gradient.radial(c, body.width / 2, const [
          AC.blobCore,
          AC.blobCore,
          AC.blobCore86,
          AC.blobCore40,
          AC.blobCore0,
        ], const [0, .50, .68, .86, 1]),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .10
        ..shader = tone
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .05),
    );
    _dots(canvas, c);
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Color.lerp(top, AC.blobSpeck, .35)!.withValues(alpha: .85),
    );
  }

  void _dots(Canvas canvas, Offset c) {
    // Three sizes by two brightnesses: six draw calls, not one per speck.
    const sizes = 3, bright = 2;
    final points = [for (var i = 0; i < sizes * bright; i++) <double>[]];
    for (var i = 0; i < BlobSim.dotCount; i++) {
      final s = sim.dotSize(i);
      final size = s < 1.1 ? 0 : (s < 2 ? 1 : 2);
      // Specks over the middle stay faint, to keep the number clear.
      final glow = sim.dotGlow(i) * (sim.dotHomeRadius(i) < .55 ? .5 : 1);
      points[size * bright + (glow > .55 ? 1 : 0)]
        ..add(c.dx + sim.dotX(i) * radius)
        ..add(c.dy + sim.dotY(i) * radius);
    }
    final scale = (radius / 137).clamp(.45, 1.0);
    final colour = Color.lerp(AC.blobSpeck, top, .22)!;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (var i = 0; i < points.length; i++) {
      if (points[i].isEmpty) continue;
      paint
        ..strokeWidth = const [1.4, 2.4, 4.4][i ~/ bright] * scale
        ..color = colour.withValues(alpha: i.isOdd ? .95 : .45);
      canvas.drawRawPoints(
          ui.PointMode.points, Float32List.fromList(points[i]), paint);
    }
  }

  @override
  bool shouldRepaint(LocusBlobPainter old) =>
      old.sim != sim ||
      old.radius != radius ||
      old.top != top ||
      old.bottom != bottom;
}
