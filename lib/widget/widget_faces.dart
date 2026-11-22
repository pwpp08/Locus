// The six home-screen widget faces, drawn here and handed to Android as
// pictures. A widget cannot draw arcs or a typeface of its own, so each face
// is painted on a canvas with the app's own rings, numerals and mark (the
// Home dials, not a lookalike), written to a PNG, and the native side shows
// it. The numbers are the ones Home shows: what this file decides is layout.
//
//   dials       Sleep · Recovery · Strain, three dials in a row (4x2)
//   ringsWide   strain over recovery as two rings, HRV and calories beside (4x2)
//   rings       the same two rings, small (2x2)
//   sleep, recovery, strain   one dial each (2x2)

import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../ui2/logo.dart' show LocusMarkPainter;
import '../ui2/theme.dart' show F, ST;

enum WidgetFace {
  dials(344, 162),
  ringsWide(344, 162),
  rings(162, 162),
  sleep(162, 162),
  recovery(162, 162),
  strain(162, 162);

  final double width, height;
  const WidgetFace(this.width, this.height);

  Size get size => Size(width, height);

  /// The file the native side reads: files/widget_faces/NAME.png.
  String get file => '$name.png';
}

/// One ring as a face draws it. [value] is a number when [numeric], else a
/// short sentence (the absence in words) that is drawn small and muted.
class FaceRing {
  final String value, suffix;
  final bool numeric;

  /// What to sweep, 0..1; null when there is nothing honest to sweep.
  final double? frac;
  final Color color;

  /// The strain target: its range as fractions of the turn, and where the
  /// tick sits. Strain only.
  final (double, double)? band;
  final double? tick;
  const FaceRing({
    required this.value,
    this.suffix = '',
    this.numeric = true,
    this.frac,
    required this.color,
    this.band,
    this.tick,
  });
}

/// Everything the faces draw. Null where the app has no figure: a face shows
/// "--", never a stand-in.
class FaceData {
  final FaceRing sleep, recovery, strain;
  final int? hrv, calories, batteryPct;
  final bool batteryStale;
  const FaceData({
    required this.sleep,
    required this.recovery,
    required this.strain,
    this.hrv,
    this.calories,
    this.batteryPct,
    this.batteryStale = false,
  });

  FaceData withBattery(int? pct, bool stale) => FaceData(
        sleep: sleep,
        recovery: recovery,
        strain: strain,
        hrv: hrv,
        calories: calories,
        batteryPct: pct,
        batteryStale: stale,
      );
}

/// The colour of a ring that is not a reading.
const kFaceMuted = Color(0xFF6B7176);

class FacePainter extends CustomPainter {
  final WidgetFace face;
  final FaceData d;
  const FacePainter(this.face, this.d);

  static const _ink = Colors.white;
  static const _grey = Color(0xFF8D9296);
  static const _lo = Color(0xFFD9DCDE);
  static const _track = Color(0x24FFFFFF);
  static const _band = Color(0x3DFFFFFF);

  // Everything below is measured off the reference, in logical points: cards
  // of 344 x 162 and 162 x 162, a dial 77 to 107 across inside them.
  static const _edge = 16.0;

  @override
  void paint(Canvas c, Size s) {
    final card = RRect.fromRectAndRadius(
        Offset.zero & s, const Radius.circular(28));
    c.drawRRect(
      card,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: ST.ground,
          stops: ST.groundStops,
        ).createShader(Offset.zero & s),
    );
    c.save();
    c.clipRRect(card);
    switch (face) {
      case WidgetFace.dials:
        _dials(c, s);
      case WidgetFace.ringsWide:
        _ringsWide(c, s);
      case WidgetFace.rings:
        _ringsSmall(c, s);
      case WidgetFace.sleep:
        _single(c, s, d.sleep, 'SLEEP');
      case WidgetFace.recovery:
        _single(c, s, d.recovery, 'RECOVERY');
      case WidgetFace.strain:
        _single(c, s, d.strain, 'STRAIN');
    }
    c.restore();
  }

  // ── parts ────────────────────────────────────────────────────────────

  TextPainter _tp(InlineSpan t,
      {double? width, TextAlign align = TextAlign.left}) {
    return TextPainter(
      text: t,
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width ?? double.infinity);
  }

  /// [at] is the anchor; [ax] 0 left, .5 centre, 1 right of it; [ay] likewise.
  void _put(Canvas c, TextPainter p, Offset at, {double ax = 0, double ay = 0}) {
    p.paint(c, at - Offset(p.width * ax, p.height * ay));
  }

  TextStyle _num(double size, Color color) => F.n34.copyWith(
      fontSize: size, color: color, fontWeight: FontWeight.w700, height: 1);

  TextStyle _caps(double size, Color color) => F.caps.copyWith(
      fontSize: size,
      color: color,
      fontWeight: FontWeight.w800,
      letterSpacing: size * .12,
      height: 1);

  /// A figure and its unit, the unit at .6 of it, on one baseline.
  TextSpan _fig(String value, String unit, double size, Color color) =>
      TextSpan(children: [
        TextSpan(text: value, style: _num(size, color)),
        if (unit.isNotEmpty) TextSpan(text: unit, style: _num(size * .6, color)),
      ]);

  /// The battery, top right. The wide cards read it on one line, level then
  /// cell; the square ones stack the level under the cell, as the reference.
  void _battery(Canvas c, Size s, {required bool stacked}) {
    final pct = d.batteryPct;
    if (pct == null || pct < 0) return;
    final color = d.batteryStale ? _grey : _lo;
    const w = 14.5, h = 7.0;
    final right = s.width - (stacked ? 14 : _edge);
    final cellY = stacked ? 16.0 : 23.0;
    final cell = Rect.fromLTWH(right - w - 1.6, cellY - h / 2, w, h);
    c.drawRRect(
        RRect.fromRectAndRadius(cell, const Radius.circular(1.8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color);
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cell.right + .6, cellY - 1.7, 1.3, 3.4),
            const Radius.circular(.6)),
        Paint()..color = color);
    final fill = pct.clamp(0, 100) / 100 * (w - 2.6);
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cell.left + 1.3, cell.top + 1.3, fill, h - 2.6),
            const Radius.circular(.9)),
        Paint()..color = color);
    final t = _tp(TextSpan(text: '$pct%', style: _num(11, _ink)));
    if (stacked) {
      _put(c, t, Offset(right, 32), ax: 1, ay: .5);
    } else {
      _put(c, t, Offset(cell.left - 5, cellY), ax: 1, ay: .5);
    }
  }

  void _wordmark(Canvas c, Size s) {
    final t = _tp(const TextSpan(
        text: 'LOCUS',
        style: TextStyle(
            fontFamily: 'SuperBubble',
            fontSize: 16,
            letterSpacing: 1.4,
            height: 1,
            color: Color(0xFFA4A9AD))));
    _put(c, t, Offset(s.width / 2, 22), ax: .5, ay: .5);
  }

  void _mark(Canvas c, Offset center, double size, Color color) {
    c.save();
    c.translate(center.dx - size / 2, center.dy - size / 2);
    LocusMarkPainter(ink: color).paint(c, Size(size, size));
    c.restore();
  }

  /// A ring with square ends, as the reference's: the track, the strain
  /// target's range and tick when it has one, then the arc.
  void _ring(Canvas c, Offset center, double dia, double stroke, FaceRing r) {
    final rect = Rect.fromCircle(center: center, radius: dia / 2 - stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;
    const top = -1.5707963;
    const turn = 6.2831853;
    c.drawArc(rect, 0, turn, false, p..color = _track);
    final band = r.band;
    if (band != null) {
      c.drawArc(rect, top + band.$1 * turn, (band.$2 - band.$1) * turn, false,
          p..color = _band);
    }
    final f = r.frac;
    if (f != null && f > 0) {
      c.drawArc(rect, top, f.clamp(0.0, 1.0) * turn, false, p..color = r.color);
    }
    final tick = r.tick;
    if (tick != null) {
      final a = top + tick * turn;
      final inner = dia / 2 - stroke, outer = dia / 2;
      c.drawLine(
          center + Offset.fromDirection(a, inner),
          center + Offset.fromDirection(a, outer),
          Paint()
            ..color = _ink
            ..strokeWidth = stroke * .26);
    }
  }

  /// One line of words in a ring, shrunk until it fits.
  void _words(Canvas c, Offset center, double dia, String text) {
    var size = dia * .14;
    TextPainter p;
    do {
      p = _tp(TextSpan(
          text: text,
          style: F.cap.copyWith(
              fontSize: size,
              color: _grey,
              fontWeight: FontWeight.w700,
              height: 1)));
      size -= .5;
    } while (p.width > dia * .7 && size > 7);
    _put(c, p, center, ax: .5, ay: .5);
  }

  void _dial(Canvas c, Offset center, double dia, FaceRing r,
      {double figure = .31}) {
    _ring(c, center, dia, dia * .078, r);
    if (r.numeric) {
      _put(c, _tp(_fig(r.value, r.suffix, dia * figure, _ink)), center,
          ax: .5, ay: .5);
    } else {
      _words(c, center, dia, r.value);
    }
  }

  // ── faces ────────────────────────────────────────────────────────────

  void _dials(Canvas c, Size s) {
    _wordmark(c, s);
    _battery(c, s, stacked: false);
    const dia = 77.0;
    final col = (s.width - 2 * 12.5) / 3;
    for (final (i, r, name) in [
      (0, d.sleep, 'SLEEP'),
      (1, d.recovery, 'RECOVERY'),
      (2, d.strain, 'STRAIN'),
    ]) {
      final cx = 12.5 + col * (i + .5);
      _dial(c, Offset(cx, 80.5), dia, r);
      _put(c, _tp(TextSpan(text: name, style: _caps(10.7, _ink))),
          Offset(cx, 134),
          ax: .5, ay: .5);
    }
  }

  /// Strain outside, recovery inside, the mark in the middle.
  void _twoRings(Canvas c, Offset center, double dia) {
    final stroke = dia * .066;
    _ring(c, center, dia, stroke, d.strain);
    _ring(c, center, dia * .77, stroke, d.recovery);
    _mark(c, center, dia * .2, _ink);
  }

  void _ringsSmall(Canvas c, Size s) {
    _battery(c, s, stacked: true);
    _twoRings(c, Offset(s.width / 2, 78), 107);
    _put(
        c,
        _tp(_fig(d.recovery.numeric ? d.recovery.value : '--',
            d.recovery.numeric ? d.recovery.suffix : '', 14, d.recovery.color)),
        const Offset(16, 139),
        ay: .5);
    _put(
        c,
        _tp(_fig(d.strain.numeric ? d.strain.value : '--', '', 14,
            d.strain.color)),
        Offset(s.width - 16, 139),
        ax: 1,
        ay: .5);
  }

  void _ringsWide(Canvas c, Size s) {
    _battery(c, s, stacked: false);
    const dia = 104.0;
    final center = Offset(s.width / 2, 78);
    _twoRings(c, center, dia);
    final leftEdge = center.dx - dia / 2 - 17;
    final rightEdge = center.dx + dia / 2 + 17;
    for (final (x, ax, value, suffix, color, name, sub, subValue) in [
      (
        leftEdge,
        1.0,
        d.recovery.numeric ? d.recovery.value : '--',
        d.recovery.numeric ? d.recovery.suffix : '',
        d.recovery.color,
        'RECOVERY',
        'HRV',
        d.hrv == null ? '--' : '${d.hrv}',
      ),
      (
        rightEdge,
        0.0,
        d.strain.numeric ? d.strain.value : '--',
        '',
        d.strain.color,
        'STRAIN',
        'CALORIES',
        d.calories == null ? '--' : _thousands(d.calories!),
      ),
    ]) {
      _put(c, _tp(_fig(value, suffix, 16, color)), Offset(x, 55.5),
          ax: ax, ay: .5);
      _put(c, _tp(TextSpan(text: name, style: _caps(10.7, color))),
          Offset(x, 72),
          ax: ax, ay: .5);
      _put(c, _tp(TextSpan(text: sub, style: _caps(10.7, _grey))),
          Offset(x, 94),
          ax: ax, ay: .5);
      _put(c, _tp(TextSpan(text: subValue, style: _num(14.5, _grey))),
          Offset(x, 111),
          ax: ax, ay: .5);
    }
  }

  void _single(Canvas c, Size s, FaceRing r, String name) {
    _battery(c, s, stacked: true);
    _dial(c, Offset(s.width / 2, 78), 104, r, figure: .3);
    _mark(c, const Offset(24, 141), 16, _grey);
    _put(c, _tp(TextSpan(text: name, style: _caps(10.7, _ink))),
        Offset(s.width / 2, 145),
        ax: .5, ay: .5);
  }

  static String _thousands(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  @override
  bool shouldRepaint(FacePainter o) => o.face != face || o.d != d;
}

/// The faces as PNGs on disk, where the native widgets read them.
class WidgetFaces {
  static const _ratio = 3.0;

  static Future<Uint8List?> png(WidgetFace f, FaceData d) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.scale(_ratio);
    FacePainter(f, d).paint(c, f.size);
    final img = await rec.endRecording().toImage(
        (f.width * _ratio).round(), (f.height * _ratio).round());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bytes?.buffer.asUint8List();
  }

  /// Writes every face under files/widget_faces. Android only: elsewhere the
  /// widgets are native and draw themselves.
  static Future<void> write(FaceData d) async {
    if (!Platform.isAndroid) return;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}'
        '/widget_faces');
    await dir.create(recursive: true);
    for (final f in WidgetFace.values) {
      final bytes = await png(f, d);
      if (bytes == null) continue;
      await File('${dir.path}/${f.file}').writeAsBytes(bytes, flush: true);
    }
  }

  /// Removes the pictures (a wiped database must not leave numbers on a home
  /// screen); the native side shows its no-data card without them.
  static Future<void> erase() async {
    if (!Platform.isAndroid) return;
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}'
          '/widget_faces');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
