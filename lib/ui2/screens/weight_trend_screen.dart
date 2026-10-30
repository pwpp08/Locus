// WEIGHT TREND SCREEN — dedicated weight history and trend chart in the More tab.
//
// Follows the Trend View visual grammar and Locus design system:
//   * Range selector: Week, Month, 6 Months.
//   * Stepping earlier/later across time windows.
//   * Hero readout with latest weight and 7-day EWMA average.
//   * Smooth 7-day EWMA trend line over real entered weights.
//   * Honest gaps: days without an entry are not silently interpolated.
//   * Interactive scrubber to inspect any day in the window.
//   * All-time stats card (Current, Lowest, Highest, Total logged).
//   * Direct "Log weight" action.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/journal_fields.dart';
import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../ui2.dart';
import 'home_screen.dart' show monthShortName, weekdayShortName;
import 'log_weight_sheet.dart';

enum WeightTrendRange { week, month, sixMonths }

class WeightTrendScreen extends StatefulWidget {
  const WeightTrendScreen({super.key});

  @override
  State<WeightTrendScreen> createState() => _WeightTrendScreenState();
}

class _WeightTrendScreenState extends State<WeightTrendScreen> {
  WeightTrendRange _range = WeightTrendRange.week;
  int _back = 0;
  int? _scrubIndex;
  bool _loading = true;
  Map<String, double> _byDay = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      // Load up to 365 days of entries
      final since = dayLabelOf(DateTime(now.year, now.month, now.day - 365));
      final rows = await LocalDb.journalMetricsByDay(sinceDaysEpoch: since);
      if (!mounted) return;
      setState(() {
        _byDay = {
          for (final e in rows.entries)
            // ignore: use_null_aware_elements
            if (e.value['weight_kg']?.value case final v?
                when v.isFinite && v > 0)
              e.key: v,
        };
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _windowDays => switch (_range) {
    WeightTrendRange.week => 7,
    WeightTrendRange.month => 30,
    WeightTrendRange.sixMonths => 180,
  };

  DateTime get _endDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(today.year, today.month, today.day - _back * _windowDays);
  }

  DateTime get _startDate => DateTime(
      _endDate.year, _endDate.month, _endDate.day - (_windowDays - 1));

  void _step(int delta) {
    setState(() {
      _back = math.max(0, _back + delta);
      _scrubIndex = null;
    });
  }

  void _setRange(WeightTrendRange r) {
    if (_range == r) return;
    setState(() {
      _range = r;
      _back = 0;
      _scrubIndex = null;
    });
  }

  Future<void> _logWeight() async {
    final updated = await LogWeightSheet.show(context);
    if (updated == true && mounted) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final units = context.watch<UnitsController>();
    final app = context.watch<AppState>();
    final unit = units.isImperial ? 'lb' : 'kg';

    final days = <DateTime>[];
    for (var i = 0; i < _windowDays; i++) {
      days.add(DateTime(_startDate.year, _startDate.month, _startDate.day + i));
    }

    double toUserUnit(double kg) => units.isImperial ? kg * 2.20462262185 : kg;

    // Build raw points and 7-day EWMA trend series
    final trendMap = weightTrendEwma(_byDay);
    final rawWindowVals = <double?>[];
    final trendWindowVals = <double?>[];

    for (final d in days) {
      final key = dayLabelOf(d);
      final raw = _byDay[key];
      final tr = trendMap[key];
      rawWindowVals.add(raw != null ? toUserUnit(raw) : null);
      trendWindowVals.add(tr != null ? toUserUnit(tr) : null);
    }

    // Numbers present for axis computation
    final present = [
      for (final v in rawWindowVals) ?v,
      for (final v in trendWindowVals) ?v,
    ];

    final profileKg = (app.user?['weight_kg'] as num?)?.toDouble();
    final currentVal = _byDay.isNotEmpty
        ? toUserUnit(_byDay.entries.last.value)
        : (profileKg != null ? toUserUnit(profileKg) : null);

    // Compute average of visible readings
    final visibleReadings = [for (final v in rawWindowVals) ?v];
    final visibleAvg = visibleReadings.isNotEmpty
        ? visibleReadings.reduce((a, b) => a + b) / visibleReadings.length
        : null;

    final scrubbedDay = _scrubIndex != null && _scrubIndex! < days.length
        ? days[_scrubIndex!]
        : null;
    final scrubbedRaw = _scrubIndex != null
        ? rawWindowVals[_scrubIndex!]
        : null;
    final scrubbedTrend = _scrubIndex != null
        ? trendWindowVals[_scrubIndex!]
        : null;

    // All-time stats
    final allTimeVals = [for (final v in _byDay.values) toUserUnit(v)];
    final minVal = allTimeVals.isNotEmpty
        ? allTimeVals.reduce(math.min)
        : currentVal;
    final maxVal = allTimeVals.isNotEmpty
        ? allTimeVals.reduce(math.max)
        : currentVal;

    final axis = present.isNotEmpty
        ? AxisSpec.of(present, ticks: 3, format: (v) => v.toStringAsFixed(1))
        : null;

    final dateRangeStr =
        '${_startDate.month}/${_startDate.day} – ${_endDate.month}/${_endDate.day}, ${_endDate.year}';

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
          children: [
            Row(
              children: [
                Pressable(
                  onTap: () => Navigator.of(context).maybePop(),
                  semanticLabel: 'Back',
                  child: SizedBox(
                    width: S.tap,
                    height: S.tap,
                    child: Center(
                      child: BoldChevron(
                        left: true,
                        height: S.x5,
                        color: p.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: S.x2),
                Icon(LucideIcons.scale, size: I.lg, color: C.dialStrain),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(
                    'WEIGHT TREND',
                    style: F.caps.copyWith(
                      color: p.ink,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Pressable(
                  onTap: _logWeight,
                  semanticLabel: 'Log weight',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x3,
                      vertical: S.x1 + S.half,
                    ),
                    decoration: BoxDecoration(
                      color: p.card2,
                      borderRadius: R.rSm,
                      border: Border.all(color: p.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: I.sm, color: p.ink),
                        const SizedBox(width: S.x1),
                        Text(
                          'LOG',
                          style: F.over.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.x4),

            // Range switcher and readout row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            scrubbedRaw != null
                                ? scrubbedRaw.toStringAsFixed(1)
                                : (currentVal != null
                                      ? currentVal.toStringAsFixed(1)
                                      : '--'),
                            style: F.num(F.n34).copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: S.x1 + S.half),
                          Text(
                            unit,
                            style: F.head.copyWith(
                              color: p.ink3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: S.half),
                      Text(
                        scrubbedDay != null
                            ? '${weekdayShortName(scrubbedDay.weekday, null)}, ${monthShortName(scrubbedDay.month, null)} ${scrubbedDay.day}'
                            : (visibleAvg != null
                                  ? '7-DAY AVG: ${visibleAvg.toStringAsFixed(1)} $unit'
                                  : 'ENTERED, NEVER MEASURED'),
                        style: F.over.copyWith(
                          color: p.ink3,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                RangeSegments(
                  const ['1W', '1M', '6M'],
                  _range.index,
                  (i) => _setRange(WeightTrendRange.values[i]),
                  width: S.x16 * 2.2,
                ),
              ],
            ),
            const SizedBox(height: S.x3),

            // The window and the steps either side of it.
            Align(
              alignment: Alignment.centerRight,
              child: WindowPager(
                dateRangeStr,
                onEarlier: () => _step(1),
                onLater: _back == 0 ? null : () => _step(-1),
              ),
            ),
            const SizedBox(height: S.x4),

            // Chart
            if (_loading)
              const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (present.isEmpty)
              Surface(
                child: Padding(
                  padding: const EdgeInsets.all(S.x6),
                  child: Column(
                    children: [
                      Icon(LucideIcons.scale, size: I.xl, color: p.ink3),
                      const SizedBox(height: S.x3),
                      Text(
                        'No weight logged yet',
                        style: F.body.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: S.x2),
                      Text(
                        'Tap "LOG" above to record your current weight. Your weight trend will smooth daily water fluctuations.',
                        textAlign: TextAlign.center,
                        style: F.cap.copyWith(color: p.ink3, height: 1.4),
                      ),
                      const SizedBox(height: S.x4),
                      BigButton(
                        'LOG FIRST WEIGHT',
                        icon: LucideIcons.plus,
                        color: C.dialStrain,
                        onTap: _logWeight,
                      ),
                    ],
                  ),
                ),
              )
            else
              Surface(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(S.x3, S.x4, S.x3, S.x2),
                  child: Column(
                    children: [
                      // Legend
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: C.dialStrain,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: S.x1),
                              Text(
                                '7-DAY TREND',
                                style: F.over.copyWith(
                                  color: p.ink2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: S.x4),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: p.ink.withValues(alpha: .5),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: S.x1),
                              Text(
                                'LOGGED',
                                style: F.over.copyWith(
                                  color: p.ink3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (scrubbedRaw != null || scrubbedTrend != null)
                            Text(
                              scrubbedRaw != null
                                  ? '${scrubbedRaw.toStringAsFixed(1)} $unit'
                                  : (scrubbedTrend != null
                                        ? '~${scrubbedTrend.toStringAsFixed(1)}'
                                        : ''),
                              style: F.over.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: S.x3),
                      SizedBox(
                        height: 180,
                        child: Scrubber(
                          value: _scrubIndex == null
                              ? null
                              : (_scrubIndex! / math.max(1, _windowDays - 1)),
                          onChanged: (f) {
                            setState(() {
                              _scrubIndex = (f * (_windowDays - 1))
                                  .round()
                                  .clamp(0, _windowDays - 1);
                            });
                          },
                          onLift: () => setState(() => _scrubIndex = null),
                          yieldToScroll: true,
                          label: 'Weight trend chart',
                          describe: (f) {
                            final idx = (f * (_windowDays - 1)).round().clamp(
                              0,
                              _windowDays - 1,
                            );
                            final v =
                                rawWindowVals[idx] ?? trendWindowVals[idx];
                            return v != null
                                ? '${v.toStringAsFixed(1)} $unit'
                                : '--';
                          },
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _WeightChartPainter(
                              rawVals: rawWindowVals,
                              trendVals: trendWindowVals,
                              axis: axis!,
                              scrubIndex: _scrubIndex,
                              lineColor: C.dialStrain,
                              dotColor: p.ink,
                              gridColor: p.line,
                              ink: p.ink,
                              ink3: p.ink3,
                              avgVal: visibleAvg,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: S.x2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${monthShortName(_startDate.month, null)} ${_startDate.day}',
                            style: F.over.copyWith(color: p.ink3),
                          ),
                          Text(
                            '${monthShortName(_endDate.month, null)} ${_endDate.day}',
                            style: F.over.copyWith(color: p.ink3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: S.x6),

            // All-time stats card
            Surface(
              child: Padding(
                padding: const EdgeInsets.all(S.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WEIGHT STATISTICS',
                      style: F.caps.copyWith(
                        color: p.ink2,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: S.x4),
                    Row(
                      children: [
                        _statTile(
                          p,
                          'CURRENT',
                          currentVal != null
                              ? currentVal.toStringAsFixed(1)
                              : '--',
                          unit,
                        ),
                        _statTile(
                          p,
                          'LOWEST',
                          minVal != null ? minVal.toStringAsFixed(1) : '--',
                          unit,
                        ),
                        _statTile(
                          p,
                          'HIGHEST',
                          maxVal != null ? maxVal.toStringAsFixed(1) : '--',
                          unit,
                        ),
                        _statTile(
                          p,
                          'LOGGED',
                          _byDay.length.toString(),
                          'days',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: S.x6),
            Text(
              'The solid curve shows your 7-day exponentially weighted moving average. '
              'Water, meals, and salt move your scale weight by 1–2 kg each day; '
              'the trend filters out daily noise so you see genuine body composition shifts.',
              style: F.cap.copyWith(color: p.ink3, height: 1.45),
            ),
            const SizedBox(height: S.x8),
          ],
        ),
      ),
    );
  }

  Widget _statTile(P p, String title, String val, String unit) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: F.over.copyWith(
            color: p.ink3,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: S.x1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              val,
              style: F.num(
                F.n24,
              ).copyWith(color: p.ink, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: F.over.copyWith(
                color: p.ink3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _WeightChartPainter extends CustomPainter {
  final List<double?> rawVals;
  final List<double?> trendVals;
  final AxisSpec axis;
  final int? scrubIndex;
  final Color lineColor;
  final Color dotColor;
  final Color gridColor;
  final Color ink;
  final Color ink3;
  final double? avgVal;

  _WeightChartPainter({
    required this.rawVals,
    required this.trendVals,
    required this.axis,
    required this.scrubIndex,
    required this.lineColor,
    required this.dotColor,
    required this.gridColor,
    required this.ink,
    required this.ink3,
    this.avgVal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final n = rawVals.length;
    if (n < 2) return;

    // Draw horizontal gridlines and axis labels
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: .35)
      ..strokeWidth = 1.0;

    for (final tick in axis.tickValues) {
      final y = h - axis.t(tick) * h;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: axis.format(tick),
          style: F.over.copyWith(color: ink3),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height - 2));
    }

    // Average line
    if (avgVal != null) {
      final yAvg = h - axis.t(avgVal!) * h;
      final dashPaint = Paint()
        ..color = ink.withValues(alpha: .28)
        ..strokeWidth = 1.0;
      for (var x = 0.0; x < w; x += 8) {
        canvas.drawLine(
          Offset(x, yAvg),
          Offset(math.min(x + 4, w), yAvg),
          dashPaint,
        );
      }
    }

    double xOf(int i) => (i / (n - 1)) * w;
    double yOf(double v) => h - axis.t(v) * h;

    // Draw 7-day EWMA trend line (smooth path)
    final trendPoints = <Offset>[];
    for (var i = 0; i < n; i++) {
      final v = trendVals[i];
      if (v != null) {
        trendPoints.add(Offset(xOf(i), yOf(v)));
      }
    }

    if (trendPoints.length >= 2) {
      final path = Path()..moveTo(trendPoints.first.dx, trendPoints.first.dy);
      for (var i = 1; i < trendPoints.length; i++) {
        final p0 = trendPoints[i - 1];
        final p1 = trendPoints[i];
        final midX = (p0.dx + p1.dx) / 2;
        path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
      }

      final linePaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, linePaint);
    }

    // Draw raw weight logged dots
    final dotPaint = Paint()..color = dotColor.withValues(alpha: .85);
    final dotRingPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var i = 0; i < n; i++) {
      final v = rawVals[i];
      if (v != null) {
        final pt = Offset(xOf(i), yOf(v));
        canvas.drawCircle(pt, 3.5, dotPaint);
        canvas.drawCircle(pt, 5.0, dotRingPaint);
      }
    }

    // Scrubber line & active dots
    if (scrubIndex != null && scrubIndex! < n) {
      final x = xOf(scrubIndex!);
      final scrubLinePaint = Paint()
        ..color = ink.withValues(alpha: .4)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(x, 0), Offset(x, h), scrubLinePaint);

      final rV = rawVals[scrubIndex!];
      if (rV != null) {
        final pt = Offset(x, yOf(rV));
        canvas.drawCircle(pt, 6, Paint()..color = ink);
        canvas.drawCircle(pt, 3, Paint()..color = lineColor);
      }

      final tV = trendVals[scrubIndex!];
      if (tV != null && tV != rV) {
        final pt = Offset(x, yOf(tV));
        canvas.drawCircle(pt, 4.5, Paint()..color = lineColor);
      }
    }
  }

  @override
  bool shouldRepaint(_WeightChartPainter old) =>
      old.rawVals != rawVals ||
      old.trendVals != trendVals ||
      old.scrubIndex != scrubIndex ||
      old.avgVal != avgVal;
}
