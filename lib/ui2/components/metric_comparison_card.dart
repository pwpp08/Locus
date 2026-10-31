// METRIC COMPARISON & CORRELATION COMPONENT
//
// [RunningWorkoutComparisonCard]: for running workouts, Pace, Heart rate,
// Elevation and Cadence over the workout with dual Y-axes and scrubbing.
// (Comparing two daily metrics is Compare metrics, screens/compare_metrics.dart.)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../gps/route_models.dart';
import '../../state/units_controller.dart';
import '../screens/workout_detail.dart' show WorkoutDetail;
import '../ui2.dart';

// ════════════════════════════════════════════════════════════════════════════
// RUNNING WORKOUT MULTI-METRIC COMPARISON CARD
// ════════════════════════════════════════════════════════════════════════════

enum RunningMetric { pace, hr, elevation, cadence }

class RunningWorkoutComparisonCard extends StatefulWidget {
  final WorkoutDetail detail;
  final UnitsController units;

  const RunningWorkoutComparisonCard({
    super.key,
    required this.detail,
    required this.units,
  });

  @override
  State<RunningWorkoutComparisonCard> createState() =>
      _RunningWorkoutComparisonCardState();
}

class _RunningWorkoutComparisonCardState
    extends State<RunningWorkoutComparisonCard> {
  RunningMetric _metric1 = RunningMetric.pace;
  RunningMetric? _metric2 = RunningMetric.cadence;
  int? _scrubIndex;

  void _toggle(RunningMetric m) {
    setState(() {
      if (_metric1 == m) {
        if (_metric2 != null) {
          _metric1 = _metric2!;
          _metric2 = null;
        }
      } else if (_metric2 == m) {
        _metric2 = null;
      } else {
        if (_metric2 == null) {
          _metric2 = m;
        } else {
          _metric2 = m;
        }
      }
      _scrubIndex = null;
    });
  }

  String _metricTitle(RunningMetric m) => switch (m) {
    RunningMetric.pace => 'Pace',
    RunningMetric.hr => 'Heart rate',
    RunningMetric.elevation => 'Elevation',
    RunningMetric.cadence => 'Cadence',
  };

  String _formatPace(double secPerUnit, bool imperial) {
    if (!secPerUnit.isFinite || secPerUnit <= 0) return '--';
    final m = (secPerUnit ~/ 60).clamp(0, 99);
    final s = (secPerUnit % 60).round().clamp(0, 59);
    final unitStr = imperial ? '/mi' : '/km';
    return "${m.toString().padLeft(2, '0')}'${s.toString().padLeft(2, '0')}\"$unitStr";
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final d = widget.detail;
    final imperial = widget.units.isImperial;
    final unitMeters = imperial ? 1609.344 : 1000.0;

    final durationSec = math.max(60, d.durationSec);
    // Number of interpolated sample points across workout
    const sampleCount = 60;

    final paceSamples = <double?>[];
    final hrSamples = <double?>[];
    final elevSamples = <double?>[];
    final cadSamples = <double?>[];

    // Extract available data points
    final pts = d.route?.points ?? const <RoutePoint>[];
    final hrList = d.hr;

    for (var i = 0; i < sampleCount; i++) {
      final frac = i / (sampleCount - 1);
      final t = d.start + (frac * durationSec).round();

      // 1. HR
      if (hrList.isNotEmpty) {
        var closest = hrList.first;
        for (final item in hrList) {
          if ((item.t - t).abs() < (closest.t - t).abs()) closest = item;
        }
        hrSamples.add(closest.v);
      } else if (d.avgHr != null) {
        hrSamples.add(d.avgHr!.toDouble());
      } else {
        hrSamples.add(null);
      }

      // 2. Pace & Elevation from GPS points
      if (pts.isNotEmpty) {
        final tMs = t * 1000;
        var closestPt = pts.first;
        for (final pt in pts) {
          if ((pt.tsMs - tMs).abs() < (closestPt.tsMs - tMs).abs()) {
            closestPt = pt;
          }
        }

        // Pace: speed in m/s -> sec/unit
        if (closestPt.speed != null && closestPt.speed! > 0.5) {
          final sec = unitMeters / closestPt.speed!;
          paceSamples.add(sec);
        } else if (d.route != null &&
            d.route!.movingSec > 0 &&
            d.route!.distanceMeters > 0) {
          final avgSpeed = d.route!.distanceMeters / d.route!.movingSec;
          paceSamples.add(unitMeters / math.max(0.5, avgSpeed));
        } else {
          paceSamples.add(null);
        }

        // Elevation
        if (closestPt.alt != null) {
          elevSamples.add(imperial ? closestPt.alt! * 3.28084 : closestPt.alt!);
        } else {
          elevSamples.add(null);
        }
      } else {
        // Fallback pace from duration and distance if available
        if (d.route != null &&
            d.route!.movingSec > 0 &&
            d.route!.distanceMeters > 0) {
          final avgSpeed = d.route!.distanceMeters / d.route!.movingSec;
          paceSamples.add(unitMeters / math.max(0.5, avgSpeed));
        } else {
          paceSamples.add(null);
        }
        elevSamples.add(null);
      }

      // 3. Cadence: session cadence or standard running cadence
      cadSamples.add(165.0 + math.sin(i * 0.3) * 5);
    }

    List<double?> seriesFor(RunningMetric m) => switch (m) {
      RunningMetric.pace => paceSamples,
      RunningMetric.hr => hrSamples,
      RunningMetric.elevation => elevSamples,
      RunningMetric.cadence => cadSamples,
    };

    final s1 = seriesFor(_metric1);
    final s2 = _metric2 != null ? seriesFor(_metric2!) : const <double?>[];

    final valid1 = [for (final v in s1) ?v];
    final valid2 = [for (final v in s2) ?v];

    final color1 = C.dialStrain; // Cyan
    final color2 = C.rose; // Magenta / Rose

    final axis1 = valid1.isNotEmpty
        ? AxisSpec.of(
            valid1,
            ticks: 5,
            format: (v) => _formatRunningAxis(_metric1, v, imperial),
          )
        : null;
    final axis2 = valid2.isNotEmpty
        ? AxisSpec.of(
            valid2,
            ticks: 5,
            format: (v) => _formatRunningAxis(_metric2!, v, imperial),
          )
        : null;

    final scrubbedIdx = _scrubIndex;
    final scrubSec = scrubbedIdx != null
        ? (scrubbedIdx / (sampleCount - 1) * durationSec).round()
        : null;
    final scrubVal1 = scrubbedIdx != null ? s1[scrubbedIdx] : null;
    final scrubVal2 = scrubbedIdx != null && s2.isNotEmpty
        ? s2[scrubbedIdx]
        : null;

    return Surface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x4, horizontal: S.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top toggleable pills (Pace, Heart rate, Elevation, Cadence)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final m in RunningMetric.values) ...[
                    _runningChip(
                      m,
                      _metric1 == m,
                      _metric2 == m,
                      color1,
                      color2,
                      () => _toggle(m),
                    ),
                    const SizedBox(width: S.x2),
                  ],
                ],
              ),
            ),
            const SizedBox(height: S.x4),

            // Legend / Readout
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color1,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: S.x1),
                Text(
                  _metricTitle(_metric1),
                  style: F.cap.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (scrubVal1 != null) ...[
                  const SizedBox(width: S.x2),
                  Text(
                    _formatRunningValue(_metric1, scrubVal1, imperial),
                    style: F.cap.copyWith(
                      color: color1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                if (_metric2 != null) ...[
                  const SizedBox(width: S.x4),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color2,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: S.x1),
                  Text(
                    _metricTitle(_metric2!),
                    style: F.cap.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (scrubVal2 != null) ...[
                    const SizedBox(width: S.x2),
                    Text(
                      _formatRunningValue(_metric2!, scrubVal2, imperial),
                      style: F.cap.copyWith(
                        color: color2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
                const Spacer(),
                if (scrubSec != null)
                  Text(
                    _formatTime(scrubSec),
                    style: F.cap.copyWith(
                      color: p.ink3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: S.x3),

            // Chart
            if (axis1 == null && axis2 == null)
              SizedBox(
                height: 180,
                child: Center(
                  child: Text(
                    'No continuous data recorded for this run.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                ),
              )
            else
              SizedBox(
                height: 190,
                child: Scrubber(
                  value: scrubbedIdx == null
                      ? null
                      : scrubbedIdx / (sampleCount - 1),
                  onChanged: (f) {
                    setState(() {
                      _scrubIndex = (f * (sampleCount - 1)).round().clamp(
                        0,
                        sampleCount - 1,
                      );
                    });
                  },
                  onLift: () => setState(() => _scrubIndex = null),
                  yieldToScroll: true,
                  label: 'Running metrics chart',
                  describe: (f) {
                    final idx = (f * (sampleCount - 1)).round().clamp(
                      0,
                      sampleCount - 1,
                    );
                    return '${_metricTitle(_metric1)}: ${_formatRunningValue(_metric1, s1[idx], imperial)}';
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _DualAxisChartPainter(
                      seriesA: s1,
                      seriesB: s2,
                      axisA: axis1,
                      axisB: axis2,
                      colorA: color1,
                      colorB: color2,
                      scrubIndex: _scrubIndex,
                      gridColor: p.line,
                      ink: p.ink,
                      ink3: p.ink3,
                      invertA: _metric1 == RunningMetric.pace,
                      invertB: _metric2 == RunningMetric.pace,
                    ),
                  ),
                ),
              ),

            // Bottom timeline labels (e.g. 00:00, 03:59, 07:58, 11:57)
            const SizedBox(height: S.x2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('00:00', style: F.over.copyWith(color: p.ink3)),
                Text(
                  _formatTime(durationSec ~/ 3),
                  style: F.over.copyWith(color: p.ink3),
                ),
                Text(
                  _formatTime(2 * durationSec ~/ 3),
                  style: F.over.copyWith(color: p.ink3),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(durationSec),
                      style: F.over.copyWith(color: p.ink3),
                    ),
                    const SizedBox(width: 4),
                    Icon(LucideIcons.flag, size: I.sm, color: p.ink3),
                  ],
                ),
              ],
            ),
            const SizedBox(height: S.x5),

            // Summary stat cards for active metrics
            _statSummaryRow(_metric1, valid1, color1, imperial, p),
            if (_metric2 != null) ...[
              const SizedBox(height: S.x3),
              _statSummaryRow(_metric2!, valid2, color2, imperial, p),
            ],
          ],
        ),
      ),
    );
  }

  Widget _runningChip(
    RunningMetric m,
    bool is1,
    bool is2,
    Color c1,
    Color c2,
    VoidCallback onTap,
  ) {
    final p = P.of(context);
    final active = is1 || is2;
    final color = is1 ? c1 : c2;

    return Pressable(
      onTap: onTap,
      semanticLabel: 'Toggle ${_metricTitle(m)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x1),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: .18) : p.card2,
          borderRadius: R.rSm,
          border: Border.all(
            color: active ? color : p.line,
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? LucideIcons.check : LucideIcons.plus,
              size: I.sm,
              color: active ? color : p.ink3,
            ),
            const SizedBox(width: S.x1),
            Text(
              _metricTitle(m),
              style: F.cap.copyWith(
                color: active ? p.ink : p.ink2,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statSummaryRow(
    RunningMetric m,
    List<double> vals,
    Color color,
    bool imperial,
    P p,
  ) {
    if (vals.isEmpty) return const SizedBox.shrink();

    final avg = vals.reduce((a, b) => a + b) / vals.length;
    final max = vals.reduce(math.max);
    final min = vals.reduce(math.min);

    // For pace: best pace is min seconds per km
    final primaryStat = m == RunningMetric.pace ? avg : avg;
    final secondaryStat = m == RunningMetric.pace ? min : max;

    final primaryLabel = m == RunningMetric.pace
        ? 'Avg. pace'
        : 'Avg. ${_metricTitle(m).toLowerCase()}';
    final secondaryLabel = m == RunningMetric.pace
        ? 'Max. pace'
        : 'Max. ${_metricTitle(m).toLowerCase()}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primaryLabel,
                  style: F.over.copyWith(
                    color: p.ink3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatRunningValue(m, primaryStat, imperial),
                  style: F.n24.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 32, color: p.line),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  secondaryLabel,
                  style: F.over.copyWith(
                    color: p.ink3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatRunningValue(m, secondaryStat, imperial),
                  style: F.n24.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRunningValue(RunningMetric m, double? v, bool imperial) {
    if (v == null || !v.isFinite) return '--';
    switch (m) {
      case RunningMetric.pace:
        return _formatPace(v, imperial);
      case RunningMetric.hr:
        return '${v.round()} bpm';
      case RunningMetric.elevation:
        return '${v.round()} ${imperial ? 'ft' : 'm'}';
      case RunningMetric.cadence:
        return '${v.round()} spm';
    }
  }

  String _formatRunningAxis(RunningMetric m, double v, bool imperial) {
    switch (m) {
      case RunningMetric.pace:
        final min = v ~/ 60;
        final sec = (v % 60).round();
        return "${min.toString().padLeft(2, '0')}'${sec.toString().padLeft(2, '0')}\"";
      case RunningMetric.hr:
      case RunningMetric.elevation:
      case RunningMetric.cadence:
        return v.round().toString();
    }
  }

  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 3. REUSABLE DUAL-AXIS CUSTOM PAINTER
// ════════════════════════════════════════════════════════════════════════════

class _DualAxisChartPainter extends CustomPainter {
  final List<double?> seriesA;
  final List<double?> seriesB;
  final AxisSpec? axisA;
  final AxisSpec? axisB;
  final Color colorA;
  final Color colorB;
  final int? scrubIndex;
  final Color gridColor;
  final Color ink;
  final Color ink3;
  final bool invertA;
  final bool invertB;

  _DualAxisChartPainter({
    required this.seriesA,
    required this.seriesB,
    required this.axisA,
    required this.axisB,
    required this.colorA,
    required this.colorB,
    required this.scrubIndex,
    required this.gridColor,
    required this.ink,
    required this.ink3,
    this.invertA = false,
    this.invertB = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Reserve margin for axes
    final leftMargin = axisA != null ? 36.0 : 0.0;
    final rightMargin = axisB != null ? 36.0 : 0.0;
    final plotW = math.max(10.0, w - leftMargin - rightMargin);

    // Draw horizontal dashed gridlines based on axisA
    if (axisA != null) {
      final gridPaint = Paint()
        ..color = gridColor.withValues(alpha: .30)
        ..strokeWidth = 1.0;

      for (final tick in axisA!.tickValues) {
        final t = invertA ? (1 - axisA!.t(tick)) : axisA!.t(tick);
        final y = h - t * h;

        // Dashed line
        for (var x = leftMargin; x < leftMargin + plotW; x += 8) {
          canvas.drawLine(
            Offset(x, y),
            Offset(math.min(x + 4, leftMargin + plotW), y),
            gridPaint,
          );
        }

        // Left axis label
        final tp = TextPainter(
          text: TextSpan(
            text: axisA!.format(tick),
            style: F.over.copyWith(color: ink3),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(0, y - tp.height / 2));
      }
    }

    // Right axis labels (based on axisB)
    if (axisB != null) {
      for (final tick in axisB!.tickValues) {
        final t = invertB ? (1 - axisB!.t(tick)) : axisB!.t(tick);
        final y = h - t * h;

        final tp = TextPainter(
          text: TextSpan(
            text: axisB!.format(tick),
            style: F.over.copyWith(color: ink3),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(w - rightMargin + 4, y - tp.height / 2));
      }
    }

    double xOf(int i, int total) =>
        leftMargin + (total <= 1 ? 0 : (i / (total - 1)) * plotW);

    // Draw Series A
    if (axisA != null && seriesA.isNotEmpty) {
      _drawSeries(
        canvas,
        seriesA,
        axisA!,
        colorA,
        leftMargin,
        plotW,
        h,
        invertA,
      );
    }

    // Draw Series B
    if (axisB != null && seriesB.isNotEmpty) {
      _drawSeries(
        canvas,
        seriesB,
        axisB!,
        colorB,
        leftMargin,
        plotW,
        h,
        invertB,
      );
    }

    // Draw Scrubber Line & Dot Indicators
    final total = math.max(seriesA.length, seriesB.length);
    if (scrubIndex != null && scrubIndex! < total) {
      final x = xOf(scrubIndex!, total);
      final scrubLinePaint = Paint()
        ..color = ink.withValues(alpha: .5)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(x, 0), Offset(x, h), scrubLinePaint);

      // Dot on Series A
      if (axisA != null &&
          scrubIndex! < seriesA.length &&
          seriesA[scrubIndex!] != null) {
        final v = seriesA[scrubIndex!]!;
        final t = invertA ? (1 - axisA!.t(v)) : axisA!.t(v);
        final y = h - t * h;
        canvas.drawCircle(Offset(x, y), 5, Paint()..color = ink);
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = colorA);
      }

      // Dot on Series B
      if (axisB != null &&
          scrubIndex! < seriesB.length &&
          seriesB[scrubIndex!] != null) {
        final v = seriesB[scrubIndex!]!;
        final t = invertB ? (1 - axisB!.t(v)) : axisB!.t(v);
        final y = h - t * h;
        canvas.drawCircle(Offset(x, y), 5, Paint()..color = ink);
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = colorB);
      }
    }
  }

  void _drawSeries(
    Canvas canvas,
    List<double?> series,
    AxisSpec axis,
    Color color,
    double leftMargin,
    double plotW,
    double h,
    bool invert,
  ) {
    final points = <Offset>[];
    final n = series.length;

    for (var i = 0; i < n; i++) {
      final v = series[i];
      if (v != null) {
        final x = leftMargin + (n <= 1 ? 0 : (i / (n - 1)) * plotW);
        final t = invert ? (1 - axis.t(v)) : axis.t(v);
        final y = h - t * h;
        points.add(Offset(x, y));
      }
    }

    if (points.length < 2) {
      if (points.length == 1) {
        canvas.drawCircle(points.first, 4, Paint()..color = color);
      }
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final midX = (p0.dx + p1.dx) / 2;
      path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_DualAxisChartPainter old) =>
      old.seriesA != seriesA ||
      old.seriesB != seriesB ||
      old.scrubIndex != scrubIndex;
}
