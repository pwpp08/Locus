// The daily cards' pictures beyond the coin and the slabs: one object each,
// in the coin's metal, with one part of it lit in the card's own colour.
// Each is 76 × 76 and decorative (no semantics).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Which picture a goal or sleep card carries.
enum CardPicture {
  /// A flight of steps, the top one lit gold: the step goal.
  steps,

  /// A peak with a strain-blue flag planted on it: the strain target.
  summit,

  /// A signal, its bottom lens lit green: ready for a big day.
  signal,

  /// A pillow with sleep blue under it: more sleep than needed.
  pillow,

  /// An hourglass, its sand run through: sleep debt paid.
  hourglass,

  /// A cell, its window full of deep and REM: restorative sleep.
  cell,

  /// A metronome, its weight lit: a steady schedule.
  metronome,
}

class CardPictureView extends StatelessWidget {
  final CardPicture picture;
  const CardPictureView(this.picture, {super.key});

  static const size = Size(76, 76);

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
        child: CustomPaint(size: size, painter: _Paint(picture)),
      );
}

class _Paint extends CustomPainter {
  final CardPicture picture;
  _Paint(this.picture);

  @override
  void paint(Canvas c, Size _) => switch (picture) {
        CardPicture.steps => _steps(c),
        CardPicture.summit => _summit(c),
        CardPicture.signal => _signal(c),
        CardPicture.pillow => _pillow(c),
        CardPicture.hourglass => _hourglass(c),
        CardPicture.cell => _cell(c),
        CardPicture.metronome => _metronome(c),
      };

  @override
  bool shouldRepaint(_Paint o) => o.picture != picture;
}

// ---- shared ----------------------------------------------------------------

/// Which way depth runs on the page, per unit: back and to the right.
const _k = Offset(.72, -.44);

Path _poly(List<Offset> p) => Path()..addPolygon(p, true);

Paint _grad(
  Rect r,
  List<Color> cs, {
  Alignment a = Alignment.topLeft,
  Alignment b = Alignment.bottomRight,
}) =>
    Paint()
      ..shader = LinearGradient(begin: a, end: b, colors: cs).createShader(r);

Paint _glow(Color c, [double blur = 4]) => Paint()
  ..color = c
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

/// A lit colour's highlight.
Color _hi(Color c, double t) => Color.lerp(c, DC.pictureHi, t)!;

/// The soft shadow an object stands on.
void _shade(Canvas c, Rect r) => c.drawOval(r, _glow(DC.coinShade, 5));

/// A block: its face toward you, its top running back, its right side.
void _cuboid(Canvas c, Rect f, double depth, {Color? lit}) {
  final k = _k * depth;
  c.drawPath(
    _poly([f.topRight, f.topRight + k, f.bottomRight + k, f.bottomRight]),
    Paint()..color = DC.boxLidEdge,
  );
  final top = _poly([f.topLeft, f.topLeft + k, f.topRight + k, f.topRight]);
  if (lit != null) c.drawPath(top, _glow(lit, 5));
  c.drawPath(
    top,
    _grad(
      top.getBounds(),
      lit == null ? const [DC.boxLedge, DC.boxLidHi] : [_hi(lit, .25), lit],
    ),
  );
  c.drawRect(
    f,
    _grad(f, const [DC.boxFront, DC.boxLidLo],
        a: Alignment.topCenter, b: Alignment.bottomCenter),
  );
}

/// A disc lying down: its rim [thick] deep, its face shaded light to dark.
void _disc(Canvas c, Offset o, double rx, double ry, double thick) {
  for (var i = thick.round(); i >= 1; i--) {
    c.drawOval(
      Rect.fromCenter(
          center: o + Offset(0, i.toDouble()), width: rx * 2, height: ry * 2),
      Paint()..color = Color.lerp(DC.coinEdgeHi, DC.coinEdgeLo, i / thick)!,
    );
  }
  final r = Rect.fromCenter(center: o, width: rx * 2, height: ry * 2);
  c.drawOval(r, _grad(r, const [DC.coinHi, DC.coinLo]));
}

// ---- the pictures ----------------------------------------------------------

void _steps(Canvas c) {
  _shade(c, const Rect.fromLTWH(4, 60, 70, 12));
  const w = 15.0, d = 16.0, base = 70.0;
  for (var i = 0; i < 4; i++) {
    final h = 14.0 + i * 12;
    _cuboid(c, Rect.fromLTWH(2 + i * w, base - h, w, h), d,
        lit: i == 3 ? PH.gold : null);
  }
}

void _summit(Canvas c) {
  _shade(c, const Rect.fromLTWH(2, 60, 74, 14));
  const a = Offset(2, 68), p = Offset(32, 24), b = Offset(72, 68);
  const crease = Offset(27, 68), q = Offset(50, 44), knee = Offset(50, 68);
  // A lower peak behind, then the faces toward you: lit, middle, in shade.
  c.drawPath(
    _poly(const [Offset(38, 68), Offset(58, 36), Offset(76, 68)]),
    _grad(const Rect.fromLTWH(38, 36, 38, 32),
        const [DC.boxLidLo, DC.coinEdgeLo]),
  );
  c.drawPath(
    _poly(const [a, p, crease]),
    _grad(const Rect.fromLTWH(2, 24, 30, 44), const [DC.coinHi, DC.boxLedge]),
  );
  c.drawPath(
    _poly(const [crease, p, q, knee]),
    _grad(const Rect.fromLTWH(27, 24, 23, 44),
        const [DC.coinLo, DC.coinEdgeHi]),
  );
  c.drawPath(
    _poly(const [knee, q, b]),
    _grad(const Rect.fromLTWH(50, 44, 22, 24),
        const [DC.coinEdgeHi, DC.coinEdgeLo]),
  );
  // The flag on top.
  c.drawLine(
    p,
    p + const Offset(0, -20),
    Paint()
      ..color = DC.boxLedge
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round,
  );
  final flag = _poly([
    p + const Offset(.8, -20),
    p + const Offset(15, -15.5),
    p + const Offset(.8, -11),
  ]);
  c.drawPath(flag, _glow(C.dialStrain, 4));
  c.drawPath(
      flag, _grad(flag.getBounds(), [_hi(C.dialStrain, .3), C.dialStrain]));
}

void _signal(Canvas c) {
  _shade(c, const Rect.fromLTWH(10, 62, 60, 12));
  final body = RRect.fromLTRBR(18, 4, 48, 70, const Radius.circular(10));
  for (var i = 12; i >= 1; i--) {
    c.drawRRect(
      body.shift(_k * i.toDouble()),
      Paint()..color = Color.lerp(DC.coinEdgeHi, DC.coinEdgeLo, i / 12)!,
    );
  }
  c.drawRRect(body, _grad(body.outerRect, const [DC.coinHi, DC.coinLo]));
  final green = Color.lerp(C.recGreen, DC.coinEdgeLo, .25)!;
  for (var i = 0; i < 3; i++) {
    final o = Offset(33, 17.0 + i * 20);
    final well = Rect.fromCircle(center: o, radius: 8.2);
    c.drawOval(well, _grad(well, const [DC.coinEdgeLo, DC.coinHi]));
    final lens = Rect.fromCircle(center: o, radius: 6.4);
    final lit = i == 2;
    if (lit) c.drawOval(lens.inflate(2), _glow(green, 5));
    c.drawOval(
      lens,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.3, -.35),
          colors: lit
              ? [_hi(green, .45), green]
              : const [DC.boxLidLo, DC.coinEdgeLo],
        ).createShader(lens),
    );
    // The hood over each lens.
    c.drawArc(
      Rect.fromCircle(center: o, radius: 9.6),
      math.pi * 1.08,
      math.pi * .84,
      false,
      Paint()
        ..color = DC.boxLedge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }
}

Path _cushion(double dy) {
  final a = Offset(4, 34 + dy), b = Offset(46, 12 + dy);
  final cc = Offset(74, 30 + dy), d = Offset(30, 56 + dy);
  final m = Offset(38, 33 + dy);
  Offset pull(Offset p, Offset q) => Offset.lerp((p + q) / 2, m, .16)!;
  final ab = pull(a, b), bc = pull(b, cc), cd = pull(cc, d), da = pull(d, a);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..quadraticBezierTo(ab.dx, ab.dy, b.dx, b.dy)
    ..quadraticBezierTo(bc.dx, bc.dy, cc.dx, cc.dy)
    ..quadraticBezierTo(cd.dx, cd.dy, d.dx, d.dy)
    ..quadraticBezierTo(da.dx, da.dy, a.dx, a.dy)
    ..close();
}

void _pillow(Canvas c) {
  _shade(c, const Rect.fromLTWH(6, 46, 68, 20));
  c.drawPath(_cushion(9), _glow(C.dialSleep, 6));
  for (var i = 8; i >= 1; i--) {
    c.drawPath(
      _cushion(i.toDouble()),
      Paint()..color = Color.lerp(DC.boxLidLo, DC.coinEdgeLo, i / 8)!,
    );
  }
  final top = _cushion(0);
  c.drawPath(top, _grad(top.getBounds(), const [DC.boxLedge, DC.boxLidLo]));
  // The seam a little in from the edge, and the dent where a head was.
  c.save();
  c.translate(38, 33);
  c.scale(.82);
  c.translate(-38, -33);
  c.drawPath(
    top,
    Paint()
      ..color = DC.boxInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9,
  );
  c.restore();
  final dent =
      Rect.fromCenter(center: const Offset(40, 32), width: 30, height: 13);
  c.drawOval(dent, _grad(dent, const [DC.boxLidLo, DC.boxLedge]));
}

void _hourglass(Canvas c) {
  const cx = 38.0;
  _shade(c, const Rect.fromLTWH(10, 62, 60, 12));
  _disc(c, const Offset(cx, 64), 27, 8, 5);
  // The glass: two bulbs and the neck.
  final glass = Path()
    ..moveTo(cx - 19, 14)
    ..cubicTo(cx - 19, 30, cx - 3, 32, cx - 2.5, 38)
    ..cubicTo(cx - 3, 44, cx - 19, 46, cx - 19, 62)
    ..lineTo(cx + 19, 62)
    ..cubicTo(cx + 19, 46, cx + 3, 44, cx + 2.5, 38)
    ..cubicTo(cx + 3, 32, cx + 19, 30, cx + 19, 14)
    ..close();
  c.drawPath(glass, Paint()..color = DC.glass);
  // The sand, all of it run through.
  final sand = Path()
    ..moveTo(cx - 18, 62)
    ..quadraticBezierTo(cx - 10, 50, cx, 47)
    ..quadraticBezierTo(cx + 10, 50, cx + 18, 62)
    ..close();
  c.drawPath(sand, _glow(C.dialSleep, 4));
  c.drawPath(
    sand,
    _grad(sand.getBounds(), [_hi(C.dialSleep, .35), C.dialSleep],
        a: Alignment.topCenter, b: Alignment.bottomCenter),
  );
  c.drawPath(
    glass,
    Paint()
      ..color = DC.glassEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  // Two posts and the top cap.
  for (final x in const [cx - 24, cx + 24]) {
    final post = Rect.fromLTWH(x - 1.8, 12, 3.6, 52);
    c.drawRect(
      post,
      _grad(post, const [DC.coinHi, DC.coinEdgeLo],
          a: Alignment.centerLeft, b: Alignment.centerRight),
    );
  }
  _disc(c, const Offset(cx, 9), 27, 8, 5);
}

void _cell(Canvas c) {
  c.save();
  c.translate(38, 38);
  c.rotate(.16);
  c.translate(-38, -38);
  const cx = 36.0, rx = 17.0, ry = 6.0, top = 14.0, foot = 66.0;
  _shade(
    c,
    Rect.fromCenter(
        center: const Offset(cx + 6, foot + 4), width: 44, height: 12),
  );
  final side = Path()
    ..addRect(const Rect.fromLTRB(cx - rx, top, cx + rx, foot))
    ..addOval(Rect.fromCenter(
        center: const Offset(cx, foot), width: rx * 2, height: ry * 2));
  c.drawPath(
    side,
    _grad(side.getBounds(), const [DC.coinHi, DC.coinLo, DC.coinEdgeLo],
        a: Alignment.centerLeft, b: Alignment.centerRight),
  );
  // The window, full, its level lit.
  final win = RRect.fromLTRBR(
      cx - 9, top + 9, cx + 6, foot - 4, const Radius.circular(3));
  c.drawRRect(win, _glow(C.sleepRem, 4));
  c.drawRRect(
    win,
    _grad(win.outerRect, const [C.sleepRem, C.sleepDeep],
        a: Alignment.topCenter, b: Alignment.bottomCenter),
  );
  for (var i = 1; i < 4; i++) {
    final y = win.top + win.height * i / 4;
    c.drawLine(
      Offset(win.left, y),
      Offset(win.right, y),
      Paint()
        ..color = DC.cellRule
        ..strokeWidth = .9,
    );
  }
  // The top, and the nub.
  final cap = Rect.fromCenter(
      center: const Offset(cx, top), width: rx * 2, height: ry * 2);
  c.drawOval(cap, _grad(cap, const [DC.boxLedge, DC.coinLo]));
  _disc(c, const Offset(cx, top - 3), 6.5, 2.4, 3);
  c.restore();
}

void _metronome(Canvas c) {
  _shade(c, const Rect.fromLTWH(4, 62, 70, 12));
  _cuboid(c, const Rect.fromLTWH(6, 62, 52, 7), 12);
  const bl = Offset(10, 62), br = Offset(54, 62);
  const tr = Offset(39, 8), tl = Offset(25, 8);
  final k = _k * 12;
  c.drawPath(_poly([br, tr, tr + k, br + k]), Paint()..color = DC.boxLidEdge);
  c.drawPath(_poly([tl, tl + k, tr + k, tr]), Paint()..color = DC.boxLedge);
  final front = _poly(const [bl, br, tr, tl]);
  c.drawPath(front, _grad(front.getBounds(), const [DC.coinHi, DC.coinLo]));
  // The well the arm swings in, with its scale.
  final well = _poly(const [
    Offset(19, 56),
    Offset(45, 56),
    Offset(36.5, 16),
    Offset(27.5, 16),
  ]);
  c.drawPath(well, _grad(well.getBounds(), const [DC.coinEdgeLo, DC.coinLo]));
  for (var i = 0; i < 5; i++) {
    final y = 22.0 + i * 7;
    c.drawLine(
      Offset(30, y),
      Offset(34, y),
      Paint()
        ..color = DC.coinEdgeHi
        ..strokeWidth = .8,
    );
  }
  // The arm, off to one side of its swing, with its weight lit.
  const pivot = Offset(32, 52), end = Offset(23, 13);
  c.drawLine(
    pivot,
    end,
    Paint()
      ..color = DC.boxLedge
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round,
  );
  final at = Offset.lerp(pivot, end, .62)!;
  c.save();
  c.translate(at.dx, at.dy);
  c.rotate(math.atan2(end.dy - pivot.dy, end.dx - pivot.dx) + math.pi / 2);
  final w = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: 10, height: 7),
    const Radius.circular(2),
  );
  c.drawRRect(w.inflate(1), _glow(C.dialSleep, 3));
  c.drawRRect(
      w, _grad(w.outerRect, [_hi(C.dialSleep, .3), C.dialSleep]));
  c.restore();
  c.drawCircle(pivot, 2.4, Paint()..color = DC.coinInk);
}
