// The coach's "Attach chart": any Trend View metric over a range, read with
// Trend View's own loader so the coach sees the numbers the chart shows.

import 'package:flutter/material.dart';

import '../../coach/coach_chart_attachment.dart';
import '../../data/day_label.dart';
import '../ui2.dart';
import 'home_screen.dart' show repoOf;
import 'trend_view.dart';

/// Opens the picker; the chart chosen, or null.
Future<CoachChartAttachment?> pickCoachChart(BuildContext context) {
  final loader = TrendLoader(repoOf(context));
  return AppSheet.show<CoachChartAttachment>(
    context,
    title: 'Attach a chart',
    child: _ChartPicker(loader),
  );
}

/// [m]'s values over the last [days] days as an attachment.
Future<CoachChartAttachment> coachChartFor(
    TrendLoader loader, TrendMetric m, int days) async {
  final to = todayLabel();
  final from = shiftDay(to, -(days - 1));
  return CoachChartAttachment(
    metricId: m.id,
    title: m.title,
    unit: m.fmt == TrendFmt.hmm ? 'h:mm' : m.unit,
    higherBetter: m.higherBetter,
    about: trendAbout(m.id),
    from: from,
    to: to,
    daily: await loader.daily(m),
    format: (v) => trendFormat(m, v),
    line: m.line,
    zeroFill: m.zeroFill,
    firstDay: m.zeroFill ? await loader.firstDay() : null,
  );
}

class _ChartPicker extends StatefulWidget {
  final TrendLoader loader;
  const _ChartPicker(this.loader);

  @override
  State<_ChartPicker> createState() => _ChartPickerState();
}

class _ChartPickerState extends State<_ChartPicker> {
  var _range = 1; // 30 days
  String? _loading;
  String? _error;

  Future<void> _pick(TrendMetric m) async {
    if (_loading != null) return;
    setState(() {
      _loading = m.id;
      _error = null;
    });
    final (days, label) = kCoachChartRanges[_range];
    try {
      final a = await coachChartFor(widget.loader, m, days);
      if (!mounted) return;
      if (a.isEmpty) {
        setState(() {
          _loading = null;
          _error = 'No ${m.title} values in the last $label.';
        });
        return;
      }
      Navigator.of(context).pop(a);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = null;
          _error = '${m.title} could not be read: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final metrics = [
      for (final m in kTrendCatalogue)
        if (m.absent == null) m,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RangeSegments(
          [for (final (_, label) in kCoachChartRanges) label.toUpperCase()],
          _range,
          (i) => setState(() {
            _range = i;
            _error = null;
          }),
          width: null,
        ),
        if (_error case final e?) ...[
          const SizedBox(height: S.x3),
          ErrorLine(e),
        ],
        for (final g in TrendGroup.values) ...[
          const SizedBox(height: S.x5),
          Text(trendGroupName(g).toUpperCase(),
              style: F.over.copyWith(color: p.ink3)),
          const SizedBox(height: S.x1),
          for (final m in metrics)
            if (m.group == g)
              Pressable(
                onTap: () => _pick(m),
                semanticLabel: 'Attach ${m.title}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x3),
                  child: Row(children: [
                    Icon(m.icon, size: I.md, color: p.ink2),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Text(m.title,
                          style: F.body.copyWith(color: p.ink)),
                    ),
                    if (_loading == m.id)
                      SizedBox.square(
                        dimension: I.sm,
                        child: CircularProgressIndicator(
                            strokeWidth: S.half, color: p.ink2),
                      )
                    else
                      Icon(LucideIcons.plus, size: I.sm, color: p.ink3),
                  ]),
                ),
              ),
        ],
      ],
    );
  }
}
