// What to expect next: shown once, right after onboarding, and from the
// milestones screen ("How calibration works"). A wheel of the first fourteen
// nights, each metric's icon on the night it unlocks, tonight lit.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openstrap_analytics/onehz.dart' show quietHrrMinDays;

import '../screens/calibration.dart' show Calibration;
import '../ui2.dart';

class WhatToExpectScreen extends StatelessWidget {
  /// Nights logged so far; tonight is the next.
  final int nights;

  /// FINISH. Pops when null.
  final VoidCallback? onFinish;

  const WhatToExpectScreen({super.key, this.nights = 0, this.onFinish});

  @override
  Widget build(BuildContext c) {
    return AlwaysChar(
      child: Builder(builder: (c) {
        final p = P.of(c);
        final done = onFinish ?? () => Navigator.of(c).maybePop();
        final fill = p.fill(C.optimal);
        return Scaffold(
          backgroundColor: p.bg,
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-1, 1),
                radius: 1.1,
                colors: [C.optimal.withValues(alpha: .12), p.bg.withValues(alpha: 0)],
              ),
            ),
            child: SafeArea(
              child: CustomScrollView(slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        S.gutter, 0, S.gutter, S.x6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Navigator.of(c).canPop()
                              ? Pressable(
                                  semanticLabel: 'Back',
                                  onTap: () => Navigator.of(c).pop(),
                                  child: SizedBox(
                                    width: S.tap,
                                    height: S.tap,
                                    child: Align(
                                      alignment: AlignmentDirectional.centerStart,
                                      child: BoldChevron(
                                          left: true,
                                          color: p.ink,
                                          height: S.x4),
                                    ),
                                  ),
                                )
                              : const SizedBox(height: S.tap),
                        ),
                        const SizedBox(height: S.x4),
                        NightWheel(nights: nights),
                        const Spacer(),
                        const SizedBox(height: S.x6),
                        Text('What to expect next',
                            style: F.t2.copyWith(color: p.ink)),
                        const SizedBox(height: S.x2),
                        Text(
                            'Over the next two weeks Locus learns your body '
                            'and its patterns. Wear the band day and night, '
                            'and new insights unlock as the nights add up.',
                            style: F.body.copyWith(color: p.ink2)),
                        const SizedBox(height: S.x6),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Text('FINISH',
                              style: F.caps
                                  .copyWith(color: p.ink, letterSpacing: 1.3)),
                          const SizedBox(width: S.x4),
                          Pressable(
                            semanticLabel: 'Finish',
                            onTap: done,
                            child: Container(
                              width: S.x16,
                              height: S.x16,
                              decoration: BoxDecoration(
                                  color: fill, shape: BoxShape.circle),
                              child: Icon(LucideIcons.check,
                                  size: I.lg, color: p.inkOn(fill)),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

/// The first [Calibration.total] nights round a ring, numbered at each
/// night's end: the nights logged and tonight lit, and on the night each
/// metric unlocks, its icon.
class NightWheel extends StatelessWidget {
  final int nights;
  const NightWheel({super.key, this.nights = 0});

  /// Segment (0-based) → the icons of what unlocks then.
  static const _unlocks = <int, List<IconData>>{
    0: [LucideIcons.moon],
    quietHrrMinDays: [LucideIcons.zap, LucideIcons.brain],
    Calibration.total - 1: [LucideIcons.batteryCharging, LucideIcons.heartPulse],
  };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const n = Calibration.total;
    final lit = math.min(n, nights + 1);
    return Semantics(
      label: 'Fourteen nights. Sleep unlocks after the first, strain and '
          'stress on day ${quietHrrMinDays + 1}, recovery and the health '
          'monitor after night $n.',
      excludeSemantics: true,
      // Sized off the screen, not a LayoutBuilder: the page lays out in a
      // SliverFillRemaining, which asks its child's intrinsic height.
      child: Builder(builder: (c) {
        final d = (MediaQuery.sizeOf(c).width - S.gutter * 2)
            .clamp(S.x16 * 2, S.x16 * 5);
        const pip = S.x3;
        final t = d * .14;
        // The lit segments stand 15 % proud of the ring; all of it inside.
        final rc = d / 2 - math.max(pip, t * 1.15 / 2) - S.half;
        const a0 = -math.pi / 2;
        const step = math.pi * 2 / n;
        Offset at(double a) =>
            Offset(d / 2 + rc * math.cos(a), d / 2 + rc * math.sin(a));
        return Center(
          child: SizedBox.square(
            dimension: d,
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _WheelPainter(
                    n: n,
                    lit: lit,
                    rc: rc,
                    t: t,
                    track: p.ink.withValues(alpha: .1),
                  ),
                ),
              ),
              for (final e in _unlocks.entries)
                _place(
                  at(a0 + step * (e.key + .5)),
                  S.x10,
                  S.x6,
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final i in e.value)
                      Icon(i,
                          size: I.sm,
                          color: e.key < lit ? p.inkOn(C.calibrate) : p.ink2),
                  ]),
                ),
              for (var i = 0; i < n; i++)
                _place(
                  at(a0 + step * (i + 1)),
                  pip * 2,
                  pip * 2,
                  Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.bg,
                      border: Border.all(
                          color: i < lit
                              ? C.calibrate
                              : p.ink.withValues(alpha: .18)),
                    ),
                    child: Text('${i + 1}',
                        style: F.num(F.over).copyWith(
                            color: i < lit ? p.ink : p.ink3)),
                  ),
                ),
              Center(
                // Inside the ring whatever the text size: it shrinks to fit.
                child: SizedBox.square(
                  dimension: (rc - t / 2) * 1.4,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const LocusMark(size: S.x12),
                  const SizedBox(height: S.x3),
                  Text('NEW FEATURES\nUNLOCK NIGHT\nBY NIGHT',
                      textAlign: TextAlign.center,
                      style: F.over.copyWith(color: p.ink, letterSpacing: 1.3)),
                    ]),
                  ),
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
  final int n, lit;
  final double rc, t;
  final Color track;
  const _WheelPainter({
    required this.n,
    required this.lit,
    required this.rc,
    required this.t,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size s) {
    final centre = s.center(Offset.zero);
    final step = math.pi * 2 / n;
    final gap = S.x1 / rc;
    for (var i = 0; i < n; i++) {
      final on = i < lit;
      final w = on ? t * 1.15 : t;
      final start = -math.pi / 2 + step * i + gap / 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w;
      if (on) {
        paint.shader = SweepGradient(
          endAngle: step,
          colors: [C.calibrate.withValues(alpha: .7), C.calibrate],
          transform: GradientRotation(start),
        ).createShader(Rect.fromCircle(center: centre, radius: rc));
      } else {
        paint.color = track;
      }
      canvas.drawArc(Rect.fromCircle(center: centre, radius: rc), start,
          step - gap, false, paint);
    }
  }

  @override
  bool shouldRepaint(_WheelPainter o) =>
      o.n != n || o.lit != lit || o.rc != rc || o.t != t || o.track != track;
}
