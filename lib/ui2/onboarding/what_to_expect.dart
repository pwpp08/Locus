// What to expect next: shown once, right after onboarding, and from the
// milestones screen ("How calibration works"). Laid out on its reference: a
// ring of the first week's nights round a peak with the sun coming up on it,
// the nights so far lit purple from a lock at the top, then the headline,
// what the weeks hold, and FINISH.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/calibration.dart' show Calibration;
import '../ui2.dart';
import 'setup_parts.dart';

class WhatToExpectScreen extends StatelessWidget {
  /// Nights logged so far; tonight is the next.
  final int nights;

  /// FINISH. Pops when null.
  final VoidCallback? onFinish;

  const WhatToExpectScreen({super.key, this.nights = 0, this.onFinish});

  @override
  Widget build(BuildContext c) {
    final nav = Navigator.of(c);
    return SetupFrame(
      picture: SizedBox(
        width: MediaQuery.sizeOf(c).width - kSetupMargin * 2,
        child: NightWheel(nights: nights),
      ),
      pictureTop: S.x1 + S.hair,
      titleGap: S.x16 * 2 - S.x1 - S.hair,
      title: 'What to Expect Next',
      body: 'Through your first week Locus learns how your body works. Wear '
          'the band day and night and something new opens up each night; '
          'recovery joins after ${Calibration.total} nights.',
      onBack: nav.canPop() ? () => nav.pop() : null,
      action: 'FINISH',
      finish: true,
      onNext: onFinish ?? () => nav.maybePop(),
    );
  }
}

/// The first week round a ring: a pip at the end of each night, the nights
/// logged and tonight lit purple from the lock at the top, and a peak in the
/// middle with the sun lit on it.
class NightWheel extends StatelessWidget {
  final int nights;
  const NightWheel({super.key, this.nights = 0});

  /// The nights round the ring.
  static const count = 7;

  @override
  Widget build(BuildContext c) {
    final lit = math.min(count, nights + 1);
    return Semantics(
      label: 'The first $count nights. $lit lit so far. Sleep unlocks after '
          'the first night, recovery after ${Calibration.total}.',
      excludeSemantics: true,
      child: Builder(builder: (c) {
        // 390 px of 480 across.
        final d = math.min(MediaQuery.sizeOf(c).width * .8125, S.x16 * 5);
        final w = d * .11;
        final rc = d / 2 - w / 2;
        const pip = S.x6 + S.x1 - S.hair;
        Offset at(double a) =>
            Offset(d / 2 + rc * math.sin(a), d / 2 - rc * math.cos(a));
        return Center(
          child: SizedBox.square(
            dimension: d,
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                    painter: _WheelPainter(lit: lit, rc: rc, w: w)),
              ),
              Center(
                child: CustomPaint(
                  size: Size(d * .34, d * .34),
                  painter: const _PeakPainter(),
                ),
              ),
              // The lock where the lit run begins.
              _place(at(_WheelPainter.start), pip, pip,
                  const Icon(LucideIcons.lockOpen,
                      size: I.sm, color: OB.pipOffInk)),
              for (var i = 1; i <= count; i++)
                _place(
                  at(_WheelPainter.pipAngle(i)),
                  pip,
                  pip,
                  Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= lit ? OB.pipOn : OB.pipOff,
                      border: i <= lit
                          ? Border.all(color: DC.pure, width: S.half - S.hair / 2)
                          : null,
                    ),
                    child: Text('$i',
                        style: OB.pip.copyWith(
                            color: i <= lit ? DC.pure : OB.pipOffInk)),
                  ),
                ),
            ]),
          ),
        );
      }),
    );
  }

  static Widget _place(Offset o, double w, double h, Widget child) =>
      Positioned(
        left: o.dx - w / 2,
        top: o.dy - h / 2,
        width: w,
        height: h,
        child: child,
      );
}

class _WheelPainter extends CustomPainter {
  final int lit;
  final double rc, w;
  const _WheelPainter({required this.lit, required this.rc, required this.w});

  /// Where the run starts, clockwise from the top, and the room between the
  /// pips.
  static const start = math.pi / 180 * 7.6;
  static const step = math.pi / 180 * 49.2;

  /// Night [i]'s pip, at the end of its stretch.
  static double pipAngle(int i) => start + step * i;

  @override
  void paint(Canvas canvas, Size s) {
    final centre = s.center(Offset.zero);
    final box = Rect.fromCircle(center: centre, radius: rc);
    // Canvas angles run from three o'clock; ours from twelve.
    double canvasAngle(double a) => a - math.pi / 2;

    final runEnd = pipAngle(lit) + step * .84;
    final end = pipAngle(NightWheel.count);

    // The nights to come: from the run's end round to the last pip.
    canvas.drawArc(
        box,
        canvasAngle(runEnd),
        end - runEnd,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [OB.ringOffEdge, OB.ringOff],
          ).createShader(Offset.zero & s));

    // The nights so far, from the lock.
    canvas.drawArc(
        box,
        canvasAngle(start),
        runEnd - start,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: const [OB.ringB, OB.ringA, OB.ringB],
            transform: GradientRotation(canvasAngle(start)),
          ).createShader(box));
  }

  @override
  bool shouldRepaint(_WheelPainter o) =>
      o.lit != lit || o.rc != rc || o.w != w;
}

/// A low peak in facets of grey, the sun lit purple on its tip.
class _PeakPainter extends CustomPainter {
  const _PeakPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Offset at(double x, double y) => Offset(x * w, y * h);
    final peak = at(.52, .22);

    // The sun: a glow, a disc, and short rays round it.
    final sun = at(.52, .18);
    canvas.drawCircle(
        sun,
        w * .2,
        Paint()
          ..shader = RadialGradient(colors: [
            OB.ringB.withValues(alpha: .55),
            OB.ringB.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: sun, radius: w * .2)));
    final ray = Paint()
      ..color = OB.ringB.withValues(alpha: .8)
      ..strokeWidth = w * .016
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 14; i++) {
      final a = i * math.pi * 2 / 14;
      canvas.drawLine(
          sun + Offset(math.cos(a), math.sin(a)) * w * .09,
          sun + Offset(math.cos(a), math.sin(a)) * w * .115,
          ray);
    }
    canvas.drawCircle(sun, w * .075, Paint()..color = OB.ringB);

    // The facets: the lit left face, the shaded right, the dark foot.
    void face(List<Offset> pts, Color col) => canvas.drawPath(
        Path()..addPolygon(pts, true), Paint()..color = col);
    final left = at(0, .74), right = at(1, .70), front = at(.47, .92);
    final ridge = at(.66, .50), shoulder = at(.30, .56);
    face([peak, shoulder, left], OB.metalLit);
    face([peak, right, ridge], OB.metal);
    face([peak, ridge, shoulder], OB.metalLit.withValues(alpha: .92));
    face([shoulder, ridge, front, left], OB.metal);
    face([ridge, right, front], OB.metalDark);
  }

  @override
  bool shouldRepaint(_PeakPainter old) => false;
}
