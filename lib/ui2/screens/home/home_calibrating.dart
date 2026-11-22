// Home while Locus is still calibrating, laid out on its reference: the
// Stress Monitor tile with the day's line (or an empty grid and NO DATA, and
// how many more days it needs), and the card that stands at the top of My
// Dashboard before the first night, the band with a pulse running through it.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../compute/stress_monitor.dart' show stressLevel;
import '../../../state/clock_format.dart';
import '../../ui2.dart';
import '../calibration.dart' show CalibrationStrip, Milestone;
import '../stress_monitor.dart' show StressMonitorData, stressColor;

/// My Dashboard's Stress Monitor: when it was last read, the level and score
/// then, and the day's line on a 0–3 scale. Before there is a reading the
/// grid stays, empty, with NO DATA over it; while the baseline is still
/// being learned its strip says how many more days.
class HomeStressCard extends StatelessWidget {
  final StressMonitorData? data;

  /// The stress monitor's milestone while it is still calibrating.
  final Milestone? calibrating;
  final VoidCallback onOpen;

  /// Now, for the empty chart's last label; the clock when null.
  final DateTime? now;

  const HomeStressCard({
    super.key,
    required this.data,
    required this.onOpen,
    this.calibrating,
    this.now,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = data;
    final last = d?.last;
    final at = now ?? DateTime.now();
    final has = d != null && last != null;
    final end = has ? last : at.hour * 60 + at.minute;
    final values = has
        ? d.scores.sublist(0, end + 1)
        : List<double?>.filled(end + 1, null);
    final score = has ? d.scores[end] : null;
    String clock(int m) => formatClockMinute(m);
    final labels = [
      for (var i = 0; i <= end; i++)
        i == end
            ? clock(end)
            : i == 0 || ({360, 720, 1080}.contains(i) && end - i > 150)
                ? clock(i)
                : '',
    ];
    return Surface(
      onTap: onOpen,
      semanticLabel: score == null
          ? 'Stress monitor. No reading yet'
          : 'Stress monitor. ${stressLevel(score).name} '
              '${score.toStringAsFixed(1)} at ${clock(end)}',
      pad: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('STRESS MONITOR',
                style: F.caps.copyWith(
                    color: p.ink, fontWeight: FontWeight.w700)),
          ),
          BoldChevron(left: false, color: p.ink3, height: S.x3),
        ]),
        const SizedBox(height: S.x4),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
          Expanded(
            child: Text('Last updated ${clock(end)}',
                style: F.num(F.cap).copyWith(color: p.ink2)),
          ),
          if (score != null) ...[
            Text(stressLevel(score).name.toUpperCase(),
                style: F.caps.copyWith(
                    color: p.ink, fontWeight: FontWeight.w800)),
            const SizedBox(width: S.x2),
          ],
          Text(score == null ? '--' : score.toStringAsFixed(1),
              style: F.n17.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: S.x4),
        Stack(children: [
          ScrubLine(
            values: values,
            xLabels: labels,
            lo: -.08,
            hi: 3,
            ticks: const [0, 1, 2, 3],
            tickText: (t) => t.toStringAsFixed(1),
            color: C.stressMedium,
            colorAt: stressColor,
            fill: false,
            markers: false,
            slots: false,
            gap: 12,
            highlight: has ? end : null,
            height: S.x16 * 3 + S.x6,
            gutter: S.x10,
            label: 'Stress through the day',
            onScrub: (_) {},
            paintOver: (canvas, plot, xOf, yOf) {
              // Now: a dashed line down to a dot.
              final x = xOf(end);
              final dash = Paint()
                ..color = p.ink
                ..strokeWidth = 1.5;
              for (var y = plot.top; y < plot.bottom; y += S.x2) {
                canvas.drawLine(Offset(x, y),
                    Offset(x, math.min(y + S.x1, plot.bottom)), dash);
              }
              canvas.drawCircle(Offset(x, score == null ? plot.bottom : yOf(score)),
                  S.x1 - S.hair, Paint()..color = p.ink);
            },
          ),
          if (!has)
            Positioned.fill(
              bottom: S.x6,
              child: IgnorePointer(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.chartNoAxesColumn,
                        size: I.xl, color: p.ink2),
                    const SizedBox(height: S.x2),
                    Text('NO DATA',
                        style: F.caps.copyWith(
                            color: p.ink, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
        ]),
        if (calibrating case final m?) ...[
          const SizedBox(height: S.x4),
          CalibrationStrip(m),
        ],
      ]),
    );
  }
}

/// The top of My Dashboard before the first night: what is happening, and
/// the band with a pulse running through it.
class PersonalizingCard extends StatelessWidget {
  const PersonalizingCard({super.key});

  @override
  Widget build(BuildContext c) => Semantics(
        container: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x3, S.x5),
          decoration: BoxDecoration(
            color: CB.well,
            borderRadius: R.rXl,
            border: Border.all(color: CB.wellEdge),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Getting to Know You',
                      style: GS.title.copyWith(color: DC.pure)),
                  const SizedBox(height: S.x1),
                  Text(
                      'The band is learning how your body works. Your '
                      'trends start to fill in here over the first nights.',
                      style: GS.text.copyWith(color: GS.body)),
                ],
              ),
            ),
            const SizedBox(width: S.x2),
            ExcludeSemantics(
              child: SizedBox(
                width: S.x16 * 2,
                height: S.x16 + S.x10,
                child: Stack(fit: StackFit.expand, children: [
                  const CustomPaint(painter: _PulsePainter()),
                  Image.asset('assets/images/get_started_band.png'),
                ]),
              ),
            ),
          ]),
        ),
      );
}

/// A heartbeat-like wave across the picture, behind the band.
class _PulsePainter extends CustomPainter {
  const _PulsePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final mid = s.height * .55;
    final path = Path()..moveTo(0, mid + s.height * .18);
    for (var x = 0.0; x <= s.width; x += 1) {
      final t = x / s.width;
      // Calm at the edges, a few quick beats in the middle.
      final amp = s.height * (.10 + .22 * math.sin(t * math.pi));
      path.lineTo(x, mid - amp * math.sin(t * math.pi * 5.5));
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = S.half
          ..strokeCap = StrokeCap.round
          ..color = CB.pulse);
  }

  @override
  bool shouldRepaint(_PulsePainter old) => false;
}
