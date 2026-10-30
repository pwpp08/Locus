// METRIC COMPARISON & CORRELATION COMPONENT
//
// Dual-metric comparison cards strictly adhering to the Locus design system:
// 1. [TrendMetricComparisonCard]: For Trend View, comparing 16 toggleable health metrics,
//    calculating Pearson correlation coefficients, and rendering dual Y-axis curves.
// 2. [RunningWorkoutComparisonCard]: For Running workouts only, comparing Pace, Heart rate,
//    Elevation, and Cadence over the workout duration with dual Y-axes and scrub interaction.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/day_label.dart';
import '../../gps/route_models.dart';
import '../../state/units_controller.dart';
import '../screens/home_screen.dart' show monthShortName, weekdayShortName;
import '../screens/trend_view.dart'
    show TrendLoader, TrendMetric, kTrendCatalogue, trendMetricOf;
import '../screens/workout_detail.dart' show WorkoutDetail;
import '../ui2.dart';

// ════════════════════════════════════════════════════════════════════════════
// 1. TREND VIEW METRIC COMPARISON & CORRELATION CARD
// ════════════════════════════════════════════════════════════════════════════

/// The 16 selectable metrics requested for Trend View comparison.
const List<String> kComparisonMetricIds = [
  'resting_hr', // RHR
  'hrv', // HRV
  'avg_hr', // Average HR
  'steps', // Steps
  'strain', // Day strain
  'sleep_perf', // Sleep performance
  'hvn_hours', // Hours vs needed
  'calories', // Calories
  'resp_rate', // Respiratory rate
  'time_in_bed', // Time in bed
  'recovery', // Recovery
  'restorative_hours', // Restorative sleep
  'efficiency', // Sleep efficiency
  'sleep_debt', // Sleep debt
  'strength_time', // Strength activity time
  'volume_load', // Total volume load
];

class TrendMetricComparisonCard extends StatefulWidget {
  final TrendLoader loader;
  final String? currentMetricId;

  const TrendMetricComparisonCard({
    super.key,
    required this.loader,
    this.currentMetricId,
  });

  @override
  State<TrendMetricComparisonCard> createState() =>
      _TrendMetricComparisonCardState();
}

class _TrendMetricComparisonCardState extends State<TrendMetricComparisonCard> {
  late String _metricA;
  String? _metricB;

  // Window: default 30 days for trend correlation
  final int _windowDays = 30;
  int? _scrubIndex;
  bool _loading = false;

  Map<String, double> _dataA = const {};
  Map<String, double> _dataB = const {};

  @override
  void initState() {
    super.initState();
    _metricA =
        widget.currentMetricId != null &&
            kComparisonMetricIds.contains(widget.currentMetricId)
        ? widget.currentMetricId!
        : 'strain';
    _metricB = _metricA == 'recovery' ? 'strain' : 'recovery';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void didUpdateWidget(TrendMetricComparisonCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentMetricId != null &&
        widget.currentMetricId != oldWidget.currentMetricId &&
        kComparisonMetricIds.contains(widget.currentMetricId)) {
      if (_metricA != widget.currentMetricId) {
        setState(() {
          _metricA = widget.currentMetricId!;
        });
        _loadData();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final mA = trendMetricOf(_metricA);
      final mB = _metricB != null ? trendMetricOf(_metricB!) : null;

      final resA = mA != null
          ? await widget.loader.daily(mA)
          : <String, double>{};
      final resB = mB != null
          ? await widget.loader.daily(mB)
          : <String, double>{};

      if (!mounted) return;
      setState(() {
        _dataA = resA;
        _dataB = resB;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleMetric(String id) {
    setState(() {
      if (_metricA == id) {
        if (_metricB != null) {
          _metricA = _metricB!;
          _metricB = null;
        }
      } else if (_metricB == id) {
        _metricB = null;
      } else {
        if (_metricB == null) {
          _metricB = id;
        } else {
          // Replace second metric
          _metricB = id;
        }
      }
      _scrubIndex = null;
    });
    _loadData();
  }

  String _formatMetricVal(TrendMetric m, double? v) {
    if (v == null || !v.isFinite) return '--';
    switch (m.id) {
      case 'strain':
        return v.toStringAsFixed(1);
      case 'steps':
      case 'calories':
      case 'volume_load':
        return v.round().toString();
      case 'recovery':
      case 'sleep_perf':
      case 'efficiency':
        return '${v.round()}%';
      case 'hrv':
        return '${v.round()} ms';
      case 'resting_hr':
      case 'avg_hr':
        return '${v.round()} bpm';
      case 'resp_rate':
        return '${v.toStringAsFixed(1)} rpm';
      case 'time_in_bed':
      case 'restorative_hours':
      case 'strength_time':
        final totalMins = (v * 60).round();
        final h = totalMins ~/ 60;
        final min = totalMins % 60;
        return '${h}h ${min.toString().padLeft(2, '0')}m';
      case 'hvn_hours':
      case 'sleep_debt':
        final sign = v < 0 ? '-' : (v > 0 ? '+' : '');
        final totalMins = v.abs().round();
        final h = totalMins ~/ 60;
        final min = totalMins % 60;
        return '$sign${h}h ${min.toString().padLeft(2, '0')}m';
      default:
        return v.toStringAsFixed(1);
    }
  }

  String _metricShortName(TrendMetric m) {
    switch (m.id) {
      case 'resting_hr':
        return 'RHR';
      case 'hrv':
        return 'HRV';
      case 'avg_hr':
        return 'Avg HR';
      case 'steps':
        return 'Steps';
      case 'strain':
        return 'Day Strain';
      case 'sleep_perf':
        return 'Sleep Perf';
      case 'hvn_hours':
        return 'Hours vs Need';
      case 'calories':
        return 'Calories';
      case 'resp_rate':
        return 'Resp Rate';
      case 'time_in_bed':
        return 'Time in Bed';
      case 'recovery':
        return 'Recovery';
      case 'restorative_hours':
        return 'Restorative';
      case 'efficiency':
        return 'Efficiency';
      case 'sleep_debt':
        return 'Sleep Debt';
      case 'strength_time':
        return 'Strength Time';
      case 'volume_load':
        return 'Volume Load';
      default:
        return m.title;
    }
  }

  double? _computePearson(List<double?> s1, List<double?> s2) {
    final pairs = <(double, double)>[];
    for (var i = 0; i < s1.length && i < s2.length; i++) {
      if (s1[i] != null && s2[i] != null) {
        pairs.add((s1[i]!, s2[i]!));
      }
    }
    if (pairs.length < 5) return null;

    final n = pairs.length;
    var sum1 = 0.0, sum2 = 0.0;
    for (final p in pairs) {
      sum1 += p.$1;
      sum2 += p.$2;
    }
    final mean1 = sum1 / n;
    final mean2 = sum2 / n;

    var num = 0.0, den1 = 0.0, den2 = 0.0;
    for (final p in pairs) {
      final d1 = p.$1 - mean1;
      final d2 = p.$2 - mean2;
      num += d1 * d2;
      den1 += d1 * d1;
      den2 += d2 * d2;
    }
    final den = math.sqrt(den1 * den2);
    if (den <= 0) return 0.0;
    return (num / den).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final mA = trendMetricOf(_metricA) ?? kTrendCatalogue.first;
    final mB = _metricB != null ? trendMetricOf(_metricB!) : null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate =
        DateTime(today.year, today.month, today.day - (_windowDays - 1));

    final days = <DateTime>[];
    for (var i = 0; i < _windowDays; i++) {
      days.add(DateTime(startDate.year, startDate.month, startDate.day + i));
    }

    final seriesA = <double?>[];
    final seriesB = <double?>[];

    for (final d in days) {
      final k = dayLabelOf(d);
      seriesA.add(_dataA[k]);
      seriesB.add(mB != null ? _dataB[k] : null);
    }

    final validA = [for (final v in seriesA) ?v];
    final validB = [for (final v in seriesB) ?v];

    final avgA = validA.isNotEmpty
        ? validA.reduce((a, b) => a + b) / validA.length
        : null;
    final avgB = validB.isNotEmpty
        ? validB.reduce((a, b) => a + b) / validB.length
        : null;

    final minA = validA.isNotEmpty ? validA.reduce(math.min) : null;
    final maxA = validA.isNotEmpty ? validA.reduce(math.max) : null;
    final minB = validB.isNotEmpty ? validB.reduce(math.min) : null;
    final maxB = validB.isNotEmpty ? validB.reduce(math.max) : null;

    final scrubbedDay = _scrubIndex != null && _scrubIndex! < days.length
        ? days[_scrubIndex!]
        : null;
    final scrubValA = _scrubIndex != null ? seriesA[_scrubIndex!] : null;
    final scrubValB = _scrubIndex != null ? seriesB[_scrubIndex!] : null;

    final correlation = mB != null ? _computePearson(seriesA, seriesB) : null;

    final colorA = C.dialStrain;
    final colorB = C.rose;

    final axisA = validA.isNotEmpty
        ? AxisSpec.of(validA, ticks: 3, format: (v) => _formatAxis(mA, v))
        : null;
    final axisB = validB.isNotEmpty
        ? AxisSpec.of(validB, ticks: 3, format: (v) => _formatAxis(mB!, v))
        : null;

    return Surface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x4, horizontal: S.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(LucideIcons.sliders, size: I.md, color: p.ink),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(
                    'CORRELATION & COMPARISON',
                    style: F.caps.copyWith(
                      color: p.ink,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: S.x2 + S.half,
                    vertical: S.half,
                  ),
                  decoration: BoxDecoration(
                    color: p.card2,
                    borderRadius: R.rSm,
                  ),
                  child: Text(
                    '${_windowDays}D',
                    style: F.over.copyWith(
                      color: p.ink3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.x1),
            Text(
              'Select metrics to plot side-by-side and discover correlations.',
              style: F.cap.copyWith(color: p.ink3),
            ),
            const SizedBox(height: S.x4),

            // Top row toggleable metric pills (horizontally scrollable)
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kComparisonMetricIds.length,
                separatorBuilder: (_, _) => const SizedBox(width: S.x2),
                itemBuilder: (context, index) {
                  final id = kComparisonMetricIds[index];
                  final m = trendMetricOf(id);
                  if (m == null) return const SizedBox.shrink();

                  final isA = _metricA == id;
                  final isB = _metricB == id;
                  final isSelected = isA || isB;
                  final activeColor = isA ? colorA : colorB;

                  return Pressable(
                    onTap: () => _toggleMetric(id),
                    semanticLabel: 'Toggle ${m.title}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: S.x3,
                        vertical: S.x1,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? activeColor.withValues(alpha: .18)
                            : p.card2,
                        borderRadius: R.rSm,
                        border: Border.all(
                          color: isSelected ? activeColor : p.line,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? LucideIcons.check : LucideIcons.plus,
                            size: I.sm,
                            color: isSelected ? activeColor : p.ink3,
                          ),
                          const SizedBox(width: S.x1),
                          Text(
                            _metricShortName(m),
                            style: F.caps.copyWith(
                              color: isSelected ? p.ink : p.ink2,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: S.x5),

            // Legend / Readout
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: colorA,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: S.x1),
                      Flexible(
                        child: Text(
                          _metricShortName(mA).toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: F.over.copyWith(
                            color: colorA,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: S.x2),
                      Text(
                        _scrubIndex != null
                            ? _formatMetricVal(mA, scrubValA)
                            : (avgA != null
                                  ? _formatMetricVal(mA, avgA)
                                  : '--'),
                        style: F.over.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (mB != null)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: colorB,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: S.x1),
                        Flexible(
                          child: Text(
                            _metricShortName(mB).toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: F.over.copyWith(
                              color: colorB,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: S.x2),
                        Text(
                          _scrubIndex != null
                              ? _formatMetricVal(mB, scrubValB)
                              : (avgB != null
                                    ? _formatMetricVal(mB, avgB)
                                    : '--'),
                          style: F.over.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (scrubbedDay != null) ...[
              const SizedBox(height: S.x1),
              Center(
                child: Text(
                  '${weekdayShortName(scrubbedDay.weekday, null)}, ${monthShortName(scrubbedDay.month, null)} ${scrubbedDay.day}',
                  style: F.over.copyWith(
                    color: p.ink3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: S.x3),

            // Chart
            if (_loading)
              const SizedBox(
                height: 170,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (axisA == null && axisB == null)
              SizedBox(
                height: 170,
                child: Center(
                  child: Text(
                    'No data available for the selected metrics in this window.',
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                ),
              )
            else
              SizedBox(
                height: 180,
                child: Scrubber(
                  value: _scrubIndex == null
                      ? null
                      : (_scrubIndex! / math.max(1, _windowDays - 1)),
                  onChanged: (f) {
                    setState(() {
                      _scrubIndex = (f * (_windowDays - 1)).round().clamp(
                        0,
                        _windowDays - 1,
                      );
                    });
                  },
                  onLift: () => setState(() => _scrubIndex = null),
                  yieldToScroll: true,
                  label: 'Metric comparison chart',
                  describe: (f) {
                    final idx = (f * (_windowDays - 1)).round().clamp(
                      0,
                      _windowDays - 1,
                    );
                    return '${_metricShortName(mA)}: ${_formatMetricVal(mA, seriesA[idx])}';
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _DualAxisChartPainter(
                      seriesA: seriesA,
                      seriesB: mB != null ? seriesB : const [],
                      axisA: axisA,
                      axisB: axisB,
                      colorA: colorA,
                      colorB: colorB,
                      scrubIndex: _scrubIndex,
                      gridColor: p.line,
                      ink: p.ink,
                      ink3: p.ink3,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: S.x2),

            // Bottom date labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${monthShortName(startDate.month, null)} ${startDate.day}',
                  style: F.over.copyWith(color: p.ink3),
                ),
                Text(
                  '${monthShortName(today.month, null)} ${today.day}',
                  style: F.over.copyWith(color: p.ink3),
                ),
              ],
            ),
            const SizedBox(height: S.x5),

            // Stats summary tiles
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(S.x3),
                    decoration: BoxDecoration(
                      color: p.card2,
                      borderRadius: R.rMd,
                      border: Border.all(color: colorA.withValues(alpha: .3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: colorA,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: S.x1),
                            Expanded(
                              child: Text(
                                _metricShortName(mA).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: F.over.copyWith(
                                  color: colorA,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: S.x2),
                        _statLine('AVG', _formatMetricVal(mA, avgA), p),
                        const SizedBox(height: S.half),
                        _statLine('MIN', _formatMetricVal(mA, minA), p),
                        const SizedBox(height: S.half),
                        _statLine('MAX', _formatMetricVal(mA, maxA), p),
                      ],
                    ),
                  ),
                ),
                if (mB != null) ...[
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(S.x3),
                      decoration: BoxDecoration(
                        color: p.card2,
                        borderRadius: R.rMd,
                        border: Border.all(color: colorB.withValues(alpha: .3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: colorB,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: S.x1),
                              Expanded(
                                child: Text(
                                  _metricShortName(mB).toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: F.over.copyWith(
                                    color: colorB,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: S.x2),
                          _statLine('AVG', _formatMetricVal(mB, avgB), p),
                          const SizedBox(height: S.half),
                          _statLine('MIN', _formatMetricVal(mB, minB), p),
                          const SizedBox(height: S.half),
                          _statLine('MAX', _formatMetricVal(mB, maxB), p),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // Correlation box (when 2 metrics are chosen)
            if (mB != null && correlation != null) ...[
              const SizedBox(height: S.x4),
              Container(
                padding: const EdgeInsets.all(S.x3),
                decoration: BoxDecoration(
                  color: p.card2,
                  borderRadius: R.rMd,
                  border: Border.all(color: p.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      correlation.abs() > 0.4
                          ? LucideIcons.sparkles
                          : LucideIcons.info,
                      size: I.sm,
                      color: correlation > 0.4
                          ? C.optimal
                          : (correlation < -0.4 ? C.strainDown : p.ink3),
                    ),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _correlationLabel(correlation).toUpperCase(),
                                style: F.over.copyWith(
                                  color: correlation > 0.4
                                      ? C.optimal
                                      : (correlation < -0.4
                                            ? C.strainDown
                                            : p.ink),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: S.x2),
                              Text(
                                'r = ${correlation >= 0 ? '+' : ''}${correlation.toStringAsFixed(2)}',
                                style: F.over.copyWith(
                                  color: p.ink3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: S.half),
                          Text(
                            _correlationSentence(
                              correlation,
                              _metricShortName(mA),
                              _metricShortName(mB),
                            ),
                            style: F.cap.copyWith(color: p.ink2, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatAxis(TrendMetric m, double v) {
    switch (m.id) {
      case 'strain':
        return v.toStringAsFixed(0);
      case 'steps':
      case 'calories':
        return '${(v / 1000).toStringAsFixed(1)}k';
      case 'recovery':
      case 'sleep_perf':
      case 'efficiency':
        return '${v.round()}%';
      case 'time_in_bed':
      case 'restorative_hours':
      case 'strength_time':
        return '${v.toStringAsFixed(1)}h';
      default:
        return v.round().toString();
    }
  }

  Widget _statLine(String label, String value, P p) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: F.over.copyWith(color: p.ink3)),
      Text(
        value,
        style: F.over.copyWith(color: p.ink, fontWeight: FontWeight.bold),
      ),
    ],
  );

  String _correlationLabel(double r) {
    if (r >= 0.6) return 'Strong Positive';
    if (r >= 0.3) return 'Moderate Positive';
    if (r <= -0.6) return 'Strong Inverse';
    if (r <= -0.3) return 'Moderate Inverse';
    return 'Low / Neutral';
  }

  String _correlationSentence(double r, String nameA, String nameB) {
    if (r >= 0.6) {
      return '$nameA and $nameB strongly rise and fall together across days.';
    } else if (r >= 0.3) {
      return 'Higher $nameA moderately associates with higher $nameB.';
    } else if (r <= -0.6) {
      return 'As $nameA rises, $nameB systematically decreases.';
    } else if (r <= -0.3) {
      return 'Higher $nameA moderately associates with lower $nameB.';
    } else {
      return '$nameA and $nameB show no meaningful statistical linear coupling.';
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 2. RUNNING WORKOUT MULTI-METRIC COMPARISON CARD
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
