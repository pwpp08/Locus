// Energy reserve on Home: what is left today, and what charged and drained it.

import 'package:flutter/material.dart';

import '../../../compute/energy_reserve.dart';
import '../../ui2.dart';

Color _tone(double level) => level >= 67
    ? C.recGreen
    : level >= 34
        ? C.recYellow
        : C.recRed;

String _clockOf(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class EnergyReserveCard extends StatelessWidget {
  final EnergyReserve data;
  final int midnight;
  const EnergyReserveCard({
    super.key,
    required this.data,
    required this.midnight,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final tone = _tone(data.level);
    Widget tile(String label, String value, Color colour) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: S.x3,
          vertical: S.x3,
        ),
        decoration: BoxDecoration(
          color: p.ink.withValues(alpha: .08),
          borderRadius: R.rLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: F.n24.copyWith(color: colour)),
            ),
          ],
        ),
      ),
    );
    return Surface(
      pad: const EdgeInsets.all(S.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ENERGY RESERVE',
                  style: F.caps.copyWith(color: p.ink),
                ),
              ),
              Pressable(
                semanticLabel: 'About energy reserve',
                onTap: () => AppSheet.show<void>(
                  c,
                  title: 'Energy reserve',
                  child: Text(
                    'An estimate of how much you have left today. Your '
                    'recovery sets the level you wake with, sleep charges it, '
                    'and raised heart rate drains it, effort most of all. '
                    'Time off the wrist changes nothing.\n\n'
                    'It is a guide built from your heart rate, not a '
                    'measurement.',
                    style: F.body.copyWith(color: p.ink2),
                  ),
                ),
                child: Icon(LucideIcons.info, size: I.md, color: p.ink2),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Row(
            children: [
              Text(
                '${data.level.round()}%',
                style: F.n24.copyWith(color: p.ink),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, S.x5),
                  painter: _TicksPainter(
                    data.level,
                    tone,
                    p.ink.withValues(alpha: .14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x1),
          Text(
            'Woke at ${_clockOf(data.wokeTs)} with ${data.wokeLevel.round()}%',
            style: F.cap.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x4),
          ExcludeSemantics(
            child: CustomPaint(
              size: const Size(double.infinity, S.x16 * 1.6),
              painter: _ChartPainter(
                data,
                midnight,
                axis: p.ink3,
                grid: p.ink.withValues(alpha: .1),
                dotRing: p.bg,
              ),
            ),
          ),
          const SizedBox(height: S.x4),
          Row(
            children: [
              tile('CHARGED', '+${data.charged}', C.recGreen),
              const SizedBox(width: S.x3),
              tile('DRAINED', '-${data.drained}', C.strainDown),
            ],
          ),
          if (data.activities.isNotEmpty) ...[
            const SizedBox(height: S.x3),
            for (final a in data.activities)
              Padding(
                padding: const EdgeInsets.only(top: S.x1),
                child: Text(
                  'Activity at ${_clockOf(a.ts)} · ${a.delta}',
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  final double level;
  final Color on, off;
  const _TicksPainter(this.level, this.on, this.off);

  @override
  void paint(Canvas canvas, Size s) {
    const n = 46;
    final paint = Paint()
      ..strokeWidth = S.half
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final x = i / (n - 1) * s.width;
      paint.color = (i + .5) / n * 100 <= level ? on : off;
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), paint);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter o) =>
      o.level != level || o.on != on || o.off != off;
}

class _ChartPainter extends CustomPainter {
  final EnergyReserve d;
  final int midnight;
  final Color axis, grid, dotRing;
  const _ChartPainter(
    this.d,
    this.midnight, {
    required this.axis,
    required this.grid,
    required this.dotRing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = S.x8, bottom = S.x6;
    final h = size.height - bottom;
    final w = size.width - left;
    double x(int t) => left + (t - midnight) / 86400 * w;
    double y(double v) => S.x1 + (h - S.x2) * (1 - v / 100);

    void label(String s, Offset at, {bool centre = false}) {
      final t = TextPainter(
        text: TextSpan(text: s, style: F.cap.copyWith(color: axis)),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(canvas, at - Offset(centre ? t.width / 2 : 0, t.height / 2));
      t.dispose();
    }

    final dash = Paint()
      ..color = grid
      ..strokeWidth = S.hair;
    for (final v in const [100, 67, 33]) {
      for (var a = left; a < size.width; a += S.x2) {
        canvas.drawLine(
          Offset(a, y(v.toDouble())),
          Offset(a + S.x1, y(v.toDouble())),
          dash,
        );
      }
      label('$v', Offset(0, y(v.toDouble())));
    }
    for (final hour in const [0, 6, 12, 18]) {
      label(
        '${hour.toString().padLeft(2, '0')}:00',
        Offset(x(midnight + hour * 3600) + (hour == 0 ? S.x4 : 0), h + S.x4),
        centre: true,
      );
    }

    final pts = d.points;
    if (pts.length < 2) return;
    final fill = Path()..moveTo(x(pts.first.$1), h);
    for (final (t, v) in pts) {
      fill.lineTo(x(t), y(v));
    }
    fill
      ..lineTo(x(pts.last.$1), h)
      ..close();
    final tone = _tone(d.level);
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tone.withValues(alpha: .28), tone.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    final line = Paint()
      ..strokeWidth = S.half
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < pts.length; i++) {
      line.color = _tone((pts[i - 1].$2 + pts[i].$2) / 2);
      canvas.drawLine(
        Offset(x(pts[i - 1].$1), y(pts[i - 1].$2)),
        Offset(x(pts[i].$1), y(pts[i].$2)),
        line,
      );
    }
    double levelAt(int t) {
      for (var i = 1; i < pts.length; i++) {
        if (pts[i].$1 >= t) return pts[i].$2;
      }
      return pts.last.$2;
    }

    for (final a in d.activities) {
      canvas.drawCircle(
        Offset(x(a.ts), y(levelAt(a.ts))),
        S.x1,
        Paint()..color = C.strainDown,
      );
    }
    final end = Offset(x(pts.last.$1), y(pts.last.$2));
    canvas.drawCircle(end, S.x1 + S.half, Paint()..color = dotRing);
    canvas.drawCircle(end, S.x1, Paint()..color = tone);
  }

  @override
  bool shouldRepaint(_ChartPainter o) => o.d != d || o.midnight != midnight;
}
