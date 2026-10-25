// STRAIN & RECOVERY — the week's two stories on one chart: how hard each day
// was (blue, 0–21, left scale) against how recovered you were for it (grey,
// 0–100 %, right scale, each point coloured by its band).
//
// Each day carries its two numbers. Where the two points sit close, the lower
// one's number goes under it and the higher one's over it, so neither covers
// the other. A finger on the chart moves the column band, and the numbers of
// the day under it go white. A day with no figure is a gap in its line, never
// a zero.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'home_screen.dart' show recoveryColor, weekdayShortName;

class StrainRecoveryCard extends StatelessWidget {
  /// The local days to draw, oldest first.
  final List<String> days;

  /// Day → value. Strain 0–21, recovery 0–100.
  final Map<String, double> strain, recovery;

  const StrainRecoveryCard({
    super.key,
    required this.days,
    required this.strain,
    required this.recovery,
  });

  static const _inset = EdgeInsets.fromLTRB(S.x6, S.x8, S.x8 + S.x1, S.x10);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final n = days.length;
    final sv = [for (final d in days) strain[d]];
    final rv = [for (final d in days) recovery[d]];
    final empty = !sv.any((v) => v != null) && !rv.any((v) => v != null);

    return Container(
      padding: const EdgeInsets.all(S.x5),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('STRAIN & RECOVERY',
                style: F.caps.copyWith(
                    color: p.ink, fontWeight: FontWeight.w700)),
          ),
          Pressable(
            onTap: () => _info(c),
            semanticLabel: 'About strain and recovery',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(LucideIcons.info, size: I.lg, color: p.ink2),
              ),
            ),
          ),
        ]),
        const SizedBox(height: S.x2),
        if (empty || n == 0)
          SizedBox(
            height: S.x16 * 2,
            child: Center(
              child: Text('Nothing recorded this week.',
                  style: F.cap.copyWith(color: p.ink3)),
            ),
          )
        else
          ScrubArea(
            count: n,
            slots: true,
            inset: _inset,
            height: S.x16 * 4 + S.x12,
            label: 'Strain and recovery, last $n days',
            describe: (i) {
              final d = DateTime.parse(days[i]);
              return '${weekdayShortName(d.weekday, l)} ${d.day}: strain '
                  '${sv[i] == null ? 'none' : sv[i]!.toStringAsFixed(1)}, recovery '
                  '${rv[i] == null ? 'none' : '${rv[i]!.round()}%'}';
            },
            onScrub: (_) {},
            builder: (c, at) => CustomPaint(
              size: Size.infinite,
              painter: _DualPainter(
                p: p,
                strain: sv,
                recovery: rv,
                xLabels: [
                  for (final d in days)
                    '${weekdayShortName(DateTime.parse(d).weekday, l)}\n${DateTime.parse(d).day}',
                ],
                focus: at ?? n - 1,
                rest: at == null,
                inset: _inset,
              ),
            ),
          ),
      ]),
    );
  }

  void _info(BuildContext c) {
    final p = P.of(c);
    AppSheet.show<void>(
      c,
      title: 'Strain & recovery',
      child: Text(
        'Strain (blue, left scale, 0 to 21) is how hard the day was on your '
        'heart. Recovery (grey, right scale, 0 to 100%) is how ready you were '
        'for it that morning: green from 67%, yellow from 34%, red below. '
        'Reading them side by side shows whether you are asking for more than '
        'your body has to give.',
        style: F.body.copyWith(color: p.ink2, height: 1.4),
      ),
    );
  }
}

class _DualPainter extends CustomPainter {
  final P p;
  final List<double?> strain, recovery;
  final List<String> xLabels;
  final int focus;

  /// Nothing is touched: the newest day carries the column itself. A touch
  /// moves the column to [ScrubArea], which draws it behind this chart.
  final bool rest;
  final EdgeInsets inset;

  _DualPainter({
    required this.p,
    required this.strain,
    required this.recovery,
    required this.xLabels,
    required this.focus,
    required this.rest,
    required this.inset,
  });

  TextPainter _text(String s, TextStyle style, {double? width, TextAlign align = TextAlign.center}) =>
      TextPainter(
        text: TextSpan(text: s, style: style),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width ?? double.infinity);

  @override
  void paint(Canvas canvas, Size size) {
    final n = strain.length;
    if (n == 0) return;
    final r = plotRect(size, inset);
    double xOf(int i) => scrubXOf(i, r, n, slots: true);
    double yS(double v) => r.bottom - (v / 21).clamp(0.0, 1.0) * r.height;
    double yR(double v) => r.bottom - (v / 100).clamp(0.0, 1.0) * r.height;

    // The day under the finger, or the newest, as a column band.
    final slot = r.width / n;
    if (rest) {
      final w = math.min(slot * .8, S.x12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(xOf(focus) - w / 2, math.max(0.0, r.top - S.x3),
                xOf(focus) + w / 2, size.height),
            const Radius.circular(S.x1)),
        Paint()..color = p.ink.withValues(alpha: .10),
      );
    }

    // Four gridlines, and what each is worth on either scale.
    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (var k = 0; k <= 3; k++) {
      final y = r.bottom - r.height * k / 3;
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      final left = _text('${7 * k}',
          F.over.copyWith(color: C.dialStrain, fontWeight: FontWeight.w700),
          width: inset.left - S.x2, align: TextAlign.right);
      left.paint(canvas, Offset(0, y - left.height / 2));
      final pct = const [0, 33, 66, 100][k];
      final right = _text('$pct%',
          F.over.copyWith(color: recoveryColor(pct), fontWeight: FontWeight.w700),
          width: inset.right - S.x2, align: TextAlign.left);
      right.paint(canvas, Offset(r.right + S.x2, y - right.height / 2));
    }

    void line(List<double?> vs, double Function(double) y, Color color, double alpha) {
      Path? path;
      for (var i = 0; i < n; i++) {
        final v = vs[i];
        if (v == null) {
          path = null;
          continue;
        }
        if (path == null) {
          path = Path()..moveTo(xOf(i), y(v));
        } else {
          path.lineTo(xOf(i), y(v));
        }
        // Painted per stretch so a gap breaks the line.
        final next = i + 1 < n ? vs[i + 1] : null;
        if (next == null) {
          canvas.drawPath(
            path,
            Paint()
              ..color = color.withValues(alpha: alpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    line(recovery, yR, p.ink2, .7);
    line(strain, yS, C.dialStrain, .6);

    void marker(double x, double y, Color color) {
      canvas.drawCircle(Offset(x, y), 6.5, Paint()..color = p.bg);
      canvas.drawCircle(
        Offset(x, y),
        5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }

    void label(String s, double x, double y, Color color, bool below, bool focused) {
      final tp = _text(s, F.cap.copyWith(color: focused ? p.ink : color, fontWeight: FontWeight.w700),
          width: slot * 2);
      final dy = below ? S.x3 : -S.x3 - tp.height;
      tp.paint(canvas, Offset(x - tp.width / 2, y + dy));
    }

    for (var i = 0; i < n; i++) {
      final s = strain[i], rec = recovery[i];
      final ys = s == null ? null : yS(s), yr = rec == null ? null : yR(rec);
      // Of the two, the lower point's number goes under it.
      final strainBelow = ys != null && yr != null && ys > yr;
      if (rec != null) {
        final col = recoveryColor(rec);
        marker(xOf(i), yr!, col);
        label('${rec.round()}%', xOf(i), yr, col, ys != null && !strainBelow, i == focus);
      }
      if (s != null) {
        marker(xOf(i), ys!, C.dialStrain);
        label(s.toStringAsFixed(1), xOf(i), ys, C.dialStrain, strainBelow, i == focus);
      }
    }

    for (var i = 0; i < n && i < xLabels.length; i++) {
      final on = i == focus;
      final tp = _text(
        xLabels[i],
        F.over.copyWith(
          color: on ? p.ink : p.ink3,
          fontWeight: on ? FontWeight.w800 : FontWeight.w600,
          height: 1.2,
        ),
        width: math.max(slot, S.x12),
      );
      tp.paint(canvas, Offset(xOf(i) - tp.width / 2, r.bottom + S.x3));
    }
  }

  @override
  bool shouldRepaint(_DualPainter old) => true;
}
