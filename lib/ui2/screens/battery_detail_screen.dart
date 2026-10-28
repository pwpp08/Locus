// battery_detail_screen.dart — charts battery level progress throughout the day and week,
// displaying drain rates, charging periods, and smart battery life projections.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../notify/battery_forecast.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart';
import '../ui2.dart';

enum BatteryTimeRange { day, week }

class BatteryDetailScreen extends StatefulWidget {
  const BatteryDetailScreen({super.key});

  @override
  State<BatteryDetailScreen> createState() => _BatteryDetailScreenState();
}

class _BatteryDetailScreenState extends State<BatteryDetailScreen> {
  BatteryTimeRange _range = BatteryTimeRange.day;
  List<BatterySample> _samples = [];
  bool _loading = true;
  BatteryForecast? _forecast;
  int? _touchedIndex;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final spanSec = _range == BatteryTimeRange.day ? 86400 : 7 * 86400;
    final startSec = nowSec - spanSec;

    final rows = await LocalDb.bandBatteryRange(startSec: startSec, endSec: nowSec);

    final samples = <BatterySample>[
      for (final r in rows)
        if (r['battery_pct'] != null && r['ts'] != null)
          BatterySample(
            tsSec: (r['ts'] as num).toInt(),
            pct: (r['battery_pct'] as num).toDouble(),
            charging: (r['charging'] as num?)?.toInt() == 1,
          ),
    ];

    final wakeAt = DateTime(now.year, now.month, now.day + 1, 7, 0);
    final f = const BatteryForecaster().forecast(
      samples: samples,
      now: now,
      wakeAt: wakeAt,
    );

    if (mounted) {
      setState(() {
        _samples = samples;
        _forecast = f;
        _loading = false;
        _touchedIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final currentPct = app.device.batteryPct ??
        (_samples.isNotEmpty ? _samples.last.pct : null);
    final isCharging = app.device.charging == true;

    final rate = _forecast?.drainPctPerHour ?? 2.1;
    final hoursLeft = currentPct != null && rate > 0
        ? math.max(0, (currentPct / rate).round())
        : null;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(S.x4),
          children: [
            const NavBar('Strap Battery'),
            // Hero Status Card
            Container(
              padding: const EdgeInsets.all(S.x5),
              decoration: BoxDecoration(
                color: isCharging ? p.wash(C.green) : p.wash(C.blue),
                borderRadius: R.rLg,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCharging
                                ? LucideIcons.batteryCharging
                                : (currentPct != null && currentPct <= 20
                                    ? LucideIcons.batteryLow
                                    : LucideIcons.batteryMedium),
                            size: 28,
                            color: isCharging
                                ? C.green
                                : (currentPct != null && currentPct <= 20 ? C.red : C.blue),
                          ),
                          const SizedBox(width: S.x2),
                          Text(
                            currentPct != null ? '${currentPct.round()}%' : '—',
                            style: F.n48.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1),
                        decoration: BoxDecoration(
                          color: isCharging ? C.green.withValues(alpha: 0.2) : p.wash(p.ink),
                          borderRadius: R.rMd,
                        ),
                        child: Text(
                          isCharging ? 'Charging' : (hoursLeft != null ? '~$hoursLeft h left' : 'Discharging'),
                          style: F.cap.copyWith(
                            color: isCharging ? C.green : p.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x3),

                  // Battery progress track
                  ClipRRect(
                    borderRadius: R.rSm,
                    child: LinearProgressIndicator(
                      value: currentPct != null ? (currentPct / 100.0).clamp(0.0, 1.0) : 0.0,
                      minHeight: 8,
                      backgroundColor: p.ink3.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isCharging
                            ? C.green
                            : (currentPct != null && currentPct <= 20 ? C.red : C.blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x3),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isCharging ? 'Connected to charger' : 'Drain rate: ~${rate.toStringAsFixed(1)}%/h',
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                      if (hoursLeft != null && !isCharging)
                        Text(
                          'Recharge tonight',
                          style: F.cap.copyWith(color: p.ink3, fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.x4),

            // Time Range Toggle (Day vs Week)
            SegmentedButton<BatteryTimeRange>(
              segments: const [
                ButtonSegment(
                  value: BatteryTimeRange.day,
                  label: Text('Today (24h)'),
                  icon: Icon(LucideIcons.clock, size: 16),
                ),
                ButtonSegment(
                  value: BatteryTimeRange.week,
                  label: Text('Past 7 Days'),
                  icon: Icon(LucideIcons.calendar, size: 16),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (set) {
                if (set.first != _range) {
                  setState(() => _range = set.first);
                  _loadData();
                }
              },
            ),
            const SizedBox(height: S.x4),

            // Chart Container
            Container(
              padding: const EdgeInsets.all(S.x4),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: R.rLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _range == BatteryTimeRange.day ? '24-Hour Battery Level' : '7-Day Battery History',
                        style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
                      ),
                      if (_touchedIndex != null && _touchedIndex! < _samples.length)
                        Text(
                          '${_samples[_touchedIndex!].pct.round()}% at ${formatClockOf(DateTime.fromMillisecondsSinceEpoch(_samples[_touchedIndex!].tsSec * 1000))}',
                          style: F.cap.copyWith(color: C.blue, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                  const SizedBox(height: S.x3),

                  _loading
                      ? const SizedBox(
                          height: 180,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _samples.isEmpty
                          ? Container(
                              height: 180,
                              alignment: Alignment.center,
                              child: Text(
                                'No battery samples recorded yet.\nSamples are logged automatically during sync.',
                                textAlign: TextAlign.center,
                                style: F.cap.copyWith(color: p.ink3),
                              ),
                            )
                          : SizedBox(
                              height: 200,
                              child: LayoutBuilder(
                                builder: (ctx, constraints) {
                                  return Scrubber(
                                    hold: true,
                                    value: _touchedIndex == null || _samples.length < 2
                                        ? null
                                        : _touchedIndex! / (_samples.length - 1),
                                    onChanged: _handleTouch,
                                    onEnd: () => setState(() => _touchedIndex = null),
                                    label: 'Battery level',
                                    describe: (v) {
                                      final s = _samples[_indexAt(v)];
                                      return '${s.pct.round()}% at ${formatClockOf(DateTime.fromMillisecondsSinceEpoch(s.tsSec * 1000))}';
                                    },
                                    child: CustomPaint(
                                      size: Size(constraints.maxWidth, 200),
                                      painter: _BatteryChartPainter(
                                        samples: _samples,
                                        range: _range,
                                        palette: p,
                                        touchedIndex: _touchedIndex,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                ],
              ),
            ),
            const SizedBox(height: S.x4),

            // Smart Battery Recommendations & Stats
            Container(
              padding: const EdgeInsets.all(S.x4),
              decoration: BoxDecoration(
                color: p.wash(p.ink3).withValues(alpha: 0.05),
                borderRadius: R.rMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.lightbulb, size: 18, color: p.ink),
                      const SizedBox(width: S.x2),
                      Text(
                        'Battery Intelligence',
                        style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x2),
                  if (hoursLeft != null) ...[
                    Text(
                      '• ~${hoursLeft}h left on your WHOOP (${currentPct?.round()}%) — recharge tonight.',
                      style: F.body.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: S.x1),
                    Text(
                      '• At ~${rate.toStringAsFixed(1)}%/h, your strap drains ~${(rate * 24).round()}% per day.',
                      style: F.body.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: S.x1),
                  ],
                  Text(
                    '• Sleep tracking consumes ~15–20% battery per night. Charge before bed if below 25%.',
                    style: F.body.copyWith(color: p.ink),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _indexAt(double fraction) =>
      (fraction.clamp(0.0, 1.0) * (_samples.length - 1)).round();

  void _handleTouch(double fraction) {
    if (_samples.isEmpty) return;
    setState(() => _touchedIndex = _indexAt(fraction));
  }
}

class _BatteryChartPainter extends CustomPainter {
  final List<BatterySample> samples;
  final BatteryTimeRange range;
  final P palette;
  final int? touchedIndex;

  _BatteryChartPainter({
    required this.samples,
    required this.range,
    required this.palette,
    this.touchedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height - 24; // leave room for time labels
    if (samples.isEmpty || w <= 0 || h <= 0) return;

    // Draw horizontal grid lines (0%, 25%, 50%, 75%, 100%)
    final gridPaint = Paint()
      ..color = palette.line.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    final textStyle = F.over.copyWith(
      color: palette.ink3.withValues(alpha: 0.6),
    );

    for (final pct in [0, 25, 50, 75, 100]) {
      final y = h - (pct / 100.0) * h;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);

      final tp = TextPainter(
        text: TextSpan(text: '$pct%', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - 12));
    }

    final minTs = samples.first.tsSec.toDouble();
    final maxTs = samples.last.tsSec.toDouble();
    final dt = math.max(1.0, maxTs - minTs);

    // Build line path
    final path = Path();
    final fillPath = Path();

    Offset? firstPoint;
    Offset? lastPoint;

    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final x = samples.length > 1
          ? ((s.tsSec - minTs) / dt) * w
          : w / 2;
      final y = h - (s.pct / 100.0).clamp(0.0, 1.0) * h;
      final pt = Offset(x, y);

      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
        fillPath.moveTo(pt.dx, h);
        fillPath.lineTo(pt.dx, pt.dy);
        firstPoint = pt;
      } else {
        path.lineTo(pt.dx, pt.dy);
        fillPath.lineTo(pt.dx, pt.dy);
      }
      lastPoint = pt;
    }

    if (firstPoint != null && lastPoint != null) {
      fillPath.lineTo(lastPoint.dx, h);
      fillPath.close();

      // Draw gradient fill
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            C.blue.withValues(alpha: 0.25),
            C.blue.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
      canvas.drawPath(fillPath, fillPaint);
    }

    // Draw main stroke line
    final linePaint = Paint()
      ..color = C.blue
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Highlight charging segments
    final chargingPaint = Paint()
      ..color = C.green
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < samples.length; i++) {
      if (samples[i].charging) {
        final x = samples.length > 1
            ? ((samples[i].tsSec - minTs) / dt) * w
            : w / 2;
        final y = h - (samples[i].pct / 100.0).clamp(0.0, 1.0) * h;
        canvas.drawCircle(Offset(x, y), 3, chargingPaint);
      }
    }

    // Draw touched cursor indicator
    if (touchedIndex != null && touchedIndex! < samples.length) {
      final s = samples[touchedIndex!];
      final x = samples.length > 1
          ? ((s.tsSec - minTs) / dt) * w
          : w / 2;
      final y = h - (s.pct / 100.0).clamp(0.0, 1.0) * h;

      final cursorPaint = Paint()
        ..color = palette.ink
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(x, 0), Offset(x, h), cursorPaint);

      canvas.drawCircle(
        Offset(x, y),
        5,
        Paint()..color = s.charging ? C.green : C.blue,
      );
      canvas.drawCircle(
        Offset(x, y),
        2,
        Paint()..color = palette.card,
      );
    }

    // X Axis labels
    final startDt = DateTime.fromMillisecondsSinceEpoch(samples.first.tsSec * 1000);
    final endDt = DateTime.fromMillisecondsSinceEpoch(samples.last.tsSec * 1000);

    final startLabel = formatClockOf(startDt);
    final endLabel = formatClockOf(endDt);

    final startTp = TextPainter(
      text: TextSpan(text: startLabel, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    startTp.paint(canvas, Offset(0, h + 6));

    final endTp = TextPainter(
      text: TextSpan(text: endLabel, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    endTp.paint(canvas, Offset(w - endTp.width, h + 6));
  }

  @override
  bool shouldRepaint(covariant _BatteryChartPainter old) {
    return old.samples != samples ||
        old.range != range ||
        old.touchedIndex != touchedIndex;
  }
}
