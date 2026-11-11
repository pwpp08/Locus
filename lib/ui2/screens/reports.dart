// REPORTS — a week or a month at a glance. The list pages every week (or
// month) since the first stored day, each with its mean recovery; a report
// lays out the three averages against the period before, the days by recovery
// colour, the averages that make up a day, training balance, the journal's
// strongest effects and the best and worst day. Every figure is read off the
// stored daily series (period_report.dart); a period with none of a figure
// shows '--' for it.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../compute/behavior_impact.dart';
import '../../compute/period_report.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../ui2.dart';
import 'behavior_insights.dart';
import 'dial_parts.dart';
import '../../l10n/app_localizations.dart';
import 'home/home_data.dart'
    show monthName, monthShortName, recoveryColor, weekdayShortName;
import 'home_screen.dart' show repoOf;
import 'readiness_detail.dart';
import 'trend_view.dart' show shiftDay;

/// Every series a report reads, per local day.
Future<Map<String, Map<String, double>>> loadReportSeries(
  LocalRepository repo,
) async {
  return {
    for (final key in kReportSeries.values) key: await dialSeries(repo, key),
  };
}

String _dayMonth(String day, AppLocalizations? l) {
  final d = DateTime.parse(day);
  return '${d.day} ${monthShortName(d.month, l)}';
}

/// '2 Nov - 8 Nov' for a week, 'November 2026' for a month.
String reportRange(
  ReportSpan span,
  String from,
  String to,
  AppLocalizations? l,
) {
  if (span == ReportSpan.week) {
    return '${_dayMonth(from, l)} - ${_dayMonth(to, l)}';
  }
  final d = DateTime.parse(from);
  return '${monthName(d.month, l)} ${d.year}';
}

// ══════════════════ THE LIST ══════════════════

class ReportsScreen extends StatefulWidget {
  /// Series to show instead of reading the repository (the gallery, tests).
  final Map<String, Map<String, double>>? series;
  final String? today;
  const ReportsScreen({super.key, this.series, this.today});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, Map<String, double>>? _series;
  var _span = ReportSpan.week;

  @override
  void initState() {
    super.initState();
    _series = widget.series;
    if (_series == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final s = await loadReportSeries(repo);
      if (mounted) setState(() => _series = s);
    } catch (_) {
      if (mounted) setState(() => _series = const {});
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final today = widget.today ?? todayLabel();
    final series = _series;
    final rec = series?['recovery'] ?? const <String, double>{};
    final first = [
      for (final m in series?.values ?? const <Map<String, double>>[])
        ...m.keys,
    ].fold<String?>(null, (a, d) => a == null || d.compareTo(a) < 0 ? d : a);
    final periods = first == null
        ? const <(String, String)>[]
        : reportPeriods(_span, first, today);

    final rows = <Widget>[];
    String? group;
    for (final (from, to) in periods) {
      final d = DateTime.parse(from);
      final g = _span == ReportSpan.week
          ? '${monthName(d.month, l)} ${d.year}'
          : '${d.year}';
      if (g != group) {
        group = g;
        rows.add(_GroupHeading(g));
      }
      final partial = from.compareTo(today) <= 0 && to.compareTo(today) >= 0;
      rows.add(
        ReportRow(
          label: _span == ReportSpan.week
              ? reportRange(_span, from, to, l)
              : monthName(DateTime.parse(from).month, l),
          partial: partial
              ? (_span == ReportSpan.week ? 'Partial week' : 'Partial month')
              : null,
          recovery: meanOver(rec, from, to.compareTo(today) > 0 ? today : to),
          onTap: () => Navigator.of(c).push(
            MaterialPageRoute(
              builder: (_) => ReportScreen(
                span: _span,
                day: from,
                series: series,
                today: today,
              ),
            ),
          ),
        ),
      );
    }

    return DialScaffold(
      title: 'Reports',
      children: [
        const SizedBox(height: S.half),
        RangeSegments(
          const ['WEEKLY', 'MONTHLY'],
          _span.index,
          (i) => setState(() => _span = ReportSpan.values[i]),
          width: null,
        ),
        const SizedBox(height: S.x2 + S.half),
        if (series == null)
          const Padding(
            padding: EdgeInsets.all(S.x8),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: S.x8),
            child: Text(
              'Reports start with your first scored day.',
              textAlign: TextAlign.center,
              style: F.dBody.copyWith(color: DC.ink2),
            ),
          )
        else
          ...rows,
      ],
    );
  }
}

class _GroupHeading extends StatelessWidget {
  final String text;
  const _GroupHeading(this.text);

  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.fromLTRB(
      S.x1 + S.hair,
      S.x4 + S.half,
      0,
      S.x2 + S.half,
    ),
    child: Text(text.toUpperCase(), style: F.dInsight.copyWith(color: DC.ink)),
  );
}

/// One week or month in the list: its range, the small recovery ring and the
/// mean beside it.
class ReportRow extends StatelessWidget {
  final String label;
  final String? partial;
  final double? recovery;
  final VoidCallback? onTap;
  const ReportRow({
    super.key,
    required this.label,
    this.partial,
    this.recovery,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final r = recovery;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x2 + S.hair),
      child: Pressable(
        onTap: onTap,
        semanticLabel:
            '$label${partial == null ? '' : ', $partial'}: recovery ${r == null ? 'not scored' : '${r.round()}%'}',
        child: Container(
          constraints: const BoxConstraints(minHeight: S.x16 - S.half / 5),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: kDialPad,
            vertical: S.x2,
          ),
          decoration: dialCard(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.dInsight.copyWith(color: DC.pure),
                    ),
                    if (partial != null) ...[
                      const SizedBox(height: S.x1 - S.hair),
                      Text(partial!, style: F.dLegend.copyWith(color: DC.ink2)),
                    ],
                  ],
                ),
              ),
              CustomPaint(
                size: const Size.square(S.x6 + S.half / 4),
                painter: Ring(
                  ((r ?? 0) / 100).clamp(0.0, 1.0),
                  r == null ? DC.track : recoveryColor(r),
                  DC.track,
                  stroke: S.x1 - S.hair / 2,
                  solid: true,
                  flatStart: true,
                ),
              ),
              const SizedBox(width: S.x3 - S.hair),
              SizedBox(
                width: S.x10,
                child: _fit(
                  Text(
                    r == null ? '--' : '${r.round()}%',
                    maxLines: 1,
                    style: F.nSmall.copyWith(color: DC.ink),
                  ),
                  Alignment.centerRight,
                ),
              ),
              const SizedBox(width: S.x3 + S.half / 4),
              const Icon(LucideIcons.chevronRight, size: I.lg, color: DC.ink2),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════ ONE REPORT ══════════════════

class ReportScreen extends StatefulWidget {
  final ReportSpan span;

  /// A day inside the period to open.
  final String day;
  final Map<String, Map<String, double>>? series;
  final String? today;

  /// The journal's effects, given rather than read (the gallery, tests).
  final List<BehaviorImpact>? effects;
  const ReportScreen({
    super.key,
    required this.span,
    required this.day,
    this.series,
    this.today,
    this.effects,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late ReportSpan _span = widget.span;
  late String _day = widget.day;
  Map<String, Map<String, double>>? _series;
  List<BehaviorImpact>? _effects;

  @override
  void initState() {
    super.initState();
    _series = widget.series;
    _effects = widget.effects;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      _series ??= await loadReportSeries(repo);
      if (mounted) setState(() {});
      if (_effects == null) {
        final got = await BehaviorInsightsData.load(
          repo,
          widget.today ?? todayLabel(),
        );
        if (mounted) setState(() => _effects = got.data.behaviors);
      }
    } catch (_) {
      if (mounted) setState(() => _series ??= const {});
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final today = widget.today ?? todayLabel();
    final series = _series;
    final r = series == null
        ? null
        : periodReport(span: _span, day: _day, today: today, series: series);
    final first = [
      for (final m in series?.values ?? const <Map<String, double>>[])
        ...m.keys,
    ].fold<String?>(null, (a, d) => a == null || d.compareTo(a) < 0 ? d : a);
    final (from, to) = periodOf(_span, _day);
    final earlier = first != null && from.compareTo(first) > 0;
    final later = to.compareTo(today) < 0;
    final word = _span == ReportSpan.week ? 'week' : 'month';

    return DialScaffold(
      title: _span == ReportSpan.week ? 'Weekly Report' : 'Monthly Report',
      trailing: r == null
          ? null
          : Pressable(
              onTap: () => Share.share(
                reportText(r, l),
                subject: reportRange(_span, from, to, l),
              ),
              semanticLabel: 'Share this report',
              child: const SizedBox.square(
                dimension: S.tap,
                child: Icon(LucideIcons.share2, size: I.lg, color: DC.ink),
              ),
            ),
      children: [
        const SizedBox(height: S.x3 - S.hair),
        Center(
          child: Container(
            width: S.x16 * 3 + S.x1 - S.hair,
            decoration: const BoxDecoration(
              color: DC.chip,
              borderRadius: R.rPill,
            ),
            child: WindowPager(
              reportRange(_span, from, to, l),
              spread: true,
              onEarlier: earlier
                  ? () => setState(() => _day = periodBefore(_span, from).$1)
                  : null,
              onLater: later
                  ? () => setState(() => _day = shiftDay(to, 1))
                  : null,
            ),
          ),
        ),
        const SizedBox(height: S.x3 + S.half),
        Center(
          child: RangeSegments(
            const ['WEEK', 'MONTH'],
            _span.index,
            (i) => setState(() {
              _span = ReportSpan.values[i];
              // The new span opens on the period holding the old one's end,
              // or today's if that is still to come.
              _day = to.compareTo(today) > 0 ? today : to;
            }),
            width: S.x16 * 2 + S.x6 - S.hair,
          ),
        ),
        if (r == null)
          const Padding(
            padding: EdgeInsets.all(S.x8),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ReportBody(r, effects: _effects),
        if (r != null && r.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: S.x4),
            child: Text(
              'Nothing was scored this $word.',
              textAlign: TextAlign.center,
              style: F.dBody.copyWith(color: DC.ink2),
            ),
          ),
      ],
    );
  }
}

/// The report as plain text, for sharing.
String reportText(PeriodReport r, AppLocalizations? l) {
  String v(ReportMetric m) => _fmt(m, r.now[m]) + _unit(m);
  final word = r.span == ReportSpan.week ? 'Weekly' : 'Monthly';
  return [
    '$word report, ${reportRange(r.span, r.from, r.to, l)}'
        '${r.partial ? ' (so far)' : ''}',
    r.summary,
    for (final m in ReportMetric.values) '${_names[m]}: ${v(m)}',
  ].join('\n');
}

const _names = {
  ReportMetric.recovery: 'Recovery',
  ReportMetric.strain: 'Day Strain',
  ReportMetric.sleepPerformance: 'Sleep Performance',
  ReportMetric.sleepHours: 'Hours of Sleep',
  ReportMetric.sleepConsistency: 'Sleep Consistency',
  ReportMetric.hrv: 'Heart Rate Variability',
  ReportMetric.restingHr: 'Resting Heart Rate',
};

String _fmt(ReportMetric m, double? v) {
  if (v == null) return '--';
  return switch (m) {
    ReportMetric.strain => v.toStringAsFixed(1),
    ReportMetric.sleepHours => clockDur(v),
    _ => '${v.round()}',
  };
}

String _unit(ReportMetric m) => switch (m) {
  ReportMetric.recovery ||
  ReportMetric.sleepPerformance ||
  ReportMetric.sleepConsistency => '%',
  ReportMetric.hrv => ' ms',
  ReportMetric.restingHr => ' bpm',
  _ => '',
};

/// Everything under the pager: the rings, the summary and the cards.
class ReportBody extends StatelessWidget {
  final PeriodReport r;
  final List<BehaviorImpact>? effects;
  const ReportBody(this.r, {super.key, this.effects});

  @override
  Widget build(BuildContext c) {
    final journal = [
      for (final b in rankedOf(effects ?? const []))
        if (!b.auto) b,
    ]..sort((a, b) => b.impact!.abs().compareTo(a.impact!.abs()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: S.x6 - S.hair),
        _Rings(r),
        const SizedBox(height: S.x6 + S.x1),
        _Summary(r.summary),
        const SizedBox(height: S.x10 - S.hair),
        _Breakdown(r),
        const SizedBox(height: S.x8 + S.x1),
        _Averages(r),
        const SizedBox(height: S.x4),
        _Balance(r),
        if (journal.isNotEmpty) ...[
          const SizedBox(height: S.x4),
          _Effects(journal.take(3).toList()),
        ],
        if (r.best != null) ...[const SizedBox(height: S.x4), _BestWorst(r)],
      ],
    );
  }
}

class _Rings extends StatelessWidget {
  final PeriodReport r;
  const _Rings(this.r);

  @override
  Widget build(BuildContext c) {
    final word = r.span == ReportSpan.week ? 'week' : 'month';
    Widget ring(String label, ReportMetric m, double max, Color color) {
      final v = r.now[m], b = r.before[m];
      final strain = m == ReportMetric.strain;
      final d = v == null || b == null ? null : v - b;
      final shown = d == null
          ? null
          : (strain ? (d * 10).round() / 10 : d.round().toDouble());
      final delta = shown == null
          ? 'No last $word'
          : shown == 0
          ? 'Same as last $word'
          : '${shown > 0 ? '+' : '−'}${strain ? shown.abs().toStringAsFixed(1) : shown.abs().round()} vs. last $word';
      final tone = shown == null || shown == 0 || strain
          ? DC.ink2
          : (shown > 0 ? C.optimal : C.strainDown);
      // Three columns a little wider than a ring, the outer two flush with
      // the page's margin.
      return SizedBox(
        width: _ring + S.x1 + S.hair,
        child: Column(
          children: [
            SizedBox.square(
              dimension: _ring,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(_ring),
                    painter: Ring(
                      ((v ?? 0) / max).clamp(0.0, 1.0),
                      color,
                      DC.track,
                      stroke: _stroke,
                      solid: true,
                      flatStart: true,
                      softStart: true,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(S.x3),
                    child: _fit(
                      _figure(
                        v == null ? '--' : _fmt(m, v),
                        strain || v == null ? '' : '%',
                        F.n24,
                        F.nTiny,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.x2 + S.hair),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'AVG $label',
                maxLines: 1,
                style: F.dLabel.copyWith(color: DC.ink),
              ),
            ),
            const SizedBox(height: S.x2 + S.hair),
            Text(
              delta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.dTiny.copyWith(color: tone),
            ),
          ],
        ),
      );
    }

    final rec = r.now[ReportMetric.recovery];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ring('SLEEP', ReportMetric.sleepPerformance, 100, C.dialSleep),
        ring(
          'RECOVERY',
          ReportMetric.recovery,
          100,
          rec == null ? DC.track : recoveryColor(rec),
        ),
        ring('STRAIN', ReportMetric.strain, 21, C.dialStrain),
      ],
    );
  }
}

const _ring = S.x16 + S.x8 + S.x1;
const _stroke = S.x1 + S.half + S.hair;

/// [w] at its own size, or shrunk to the space it has (large text).
Widget _fit(Widget w, [Alignment alignment = Alignment.center]) =>
    FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: w);

/// [w] no wider than a title line can spare for it.
Widget _capped(Widget w) => ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: S.x16 + S.x8),
  child: _fit(w, Alignment.centerRight),
);

/// A figure and a smaller unit on one baseline.
Widget _figure(
  String value,
  String unit,
  TextStyle big,
  TextStyle small, {
  Color color = DC.ink,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(value, style: big.copyWith(color: color)),
      if (unit.isNotEmpty) ...[
        const SizedBox(width: S.half / 2),
        Text(unit, style: small.copyWith(color: color)),
      ],
    ],
  );
}

/// The summary under the rings, inside the coach's lavender-to-teal edge.
class _Summary extends StatelessWidget {
  final String text;
  const _Summary(this.text);

  @override
  Widget build(BuildContext c) => CustomPaint(
    painter: const _EdgePaint(),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        S.x5,
        S.x4 + S.half / 2,
        S.x5,
        S.x4 + S.half,
      ),
      child: Text(
        text,
        style: F.dBody.copyWith(
          color: DC.ink,
          fontWeight: FontWeight.w400,
          height: 1.38,
        ),
      ),
    ),
  );
}

class _EdgePaint extends CustomPainter {
  const _EdgePaint();

  @override
  void paint(Canvas canvas, Size size) {
    final box = (Offset.zero & size).deflate(S.hair / 2);
    canvas.drawRRect(
      R.rXl.toRRect(box),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = S.hair
        ..shader = const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [C.coachEdgeB, C.coachEdgeA],
        ).createShader(box),
    );
  }

  @override
  bool shouldRepaint(_EdgePaint old) => false;
}

/// A report card: the title line, its trailing words and ⓘ, then [child].
Widget _card(
  String title, {
  String? note,
  Widget? action,
  required String info,
  required Widget child,
  double bottom = S.x5,
}) {
  return Container(
    decoration: dialCard(),
    // The ⓘ's 44 pt target reaches past its glyph, so the title line runs
    // out to the card's edge less that and the content keeps the pad.
    padding: EdgeInsets.fromLTRB(
      kDialPad,
      S.x5 + S.half,
      kDialPad - S.x3,
      bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: I.md,
          child: dialCardTitle(
            title,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // At large text the words shrink before the title gives way.
                if (note != null) ...[
                  _capped(Text(note, style: F.dTiny.copyWith(color: DC.ink2))),
                  const SizedBox(width: S.x2),
                ],
                if (action != null) ...[
                  _capped(action),
                  const SizedBox(width: S.x1 + S.half),
                ],
                DialInfo(title, info),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: S.x3),
          child: child,
        ),
      ],
    ),
  );
}

class _Breakdown extends StatelessWidget {
  final PeriodReport r;
  const _Breakdown(this.r);

  @override
  Widget build(BuildContext c) {
    final d = r.recoveryDays;
    final parts = [
      (d.green, C.recGreen, 'GREEN (67-100%)'),
      (d.yellow, C.recYellow, 'YELLOW (34-66%)'),
      (d.red, C.recRed, 'RED (0-33%)'),
    ];
    final total = d.green + d.yellow + d.red;
    return _card(
      'Recovery Breakdown',
      note: 'Days',
      info:
          'How many days of this period scored green, yellow and red. A day '
          'counts once its morning recovery is in.',
      bottom: S.x4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: S.x4),
          SizedBox(
            height: S.x3 + S.half - S.hair / 2,
            child: total == 0
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                      color: DC.track,
                      borderRadius: BorderRadius.all(Radius.circular(S.half)),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, (n, color, _)) in parts.indexed)
                        if (n > 0) ...[
                          if (parts.take(i).any((p) => p.$1 > 0))
                            const SizedBox(width: S.half),
                          Expanded(
                            flex: n,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(S.half),
                                ),
                              ),
                            ),
                          ),
                        ],
                    ],
                  ),
          ),
          const SizedBox(height: S.x3 - S.hair),
          for (final (n, color, name) in parts)
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: S.x6 + S.half - S.hair * .4,
              ),
              child: Row(
                children: [
                  Container(
                    width: S.x3,
                    height: S.x3,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: S.x3 + S.hair),
                  SizedBox(
                    width: S.x16 + S.x1,
                    child: _fit(
                      Text('${n}x', style: F.n17.copyWith(color: DC.ink)),
                      Alignment.centerLeft,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.dLabel.copyWith(color: DC.ink2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Averages extends StatelessWidget {
  final PeriodReport r;
  const _Averages(this.r);

  @override
  Widget build(BuildContext c) {
    final ms = ReportMetric.values;
    return _card(
      'Averages',
      note: 'vs. last',
      info:
          'Each figure is the mean of the days that have it, with the period '
          'before under it. A green triangle is a change for the better.',
      bottom: S.x4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: S.x4 + S.half + S.hair),
          for (final (i, m) in ms.indexed) ...[
            if (i > 0)
              const Divider(height: S.hair, thickness: S.hair, color: DC.line),
            _AverageRow(m, r.now[m], r.before[m]),
          ],
        ],
      ),
    );
  }
}

class _AverageRow extends StatelessWidget {
  final ReportMetric m;
  final double? v, before;
  const _AverageRow(this.m, this.v, this.before);

  @override
  Widget build(BuildContext c) {
    final unit = _unit(m).trim();
    final better = reportBetter(m);
    Widget? mark;
    final a = v, b = before;
    if (a != null && b != null && a != b) {
      final up = a > b;
      mark = DeltaTriangle(
        up: up,
        color: better == 0
            ? DC.ink2
            : (up == (better > 0) ? C.optimal : C.strainDown),
        size: S.x2 + S.hair,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: S.x16 - S.half / 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _names[m]!.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: F.dLabel.copyWith(color: DC.ink),
            ),
          ),
          Flexible(
            child: _fit(
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _figure(_fmt(m, v), v == null ? '' : unit, F.nRow, F.dText),
                  const SizedBox(height: S.x1 - S.hair),
                  Text(
                    before == null ? '--' : _fmt(m, before) + _unit(m),
                    style: F.dLegend.copyWith(color: DC.ink2),
                  ),
                ],
              ),
              Alignment.centerRight,
            ),
          ),
          SizedBox(
            width: S.x5 - S.hair,
            child: Align(alignment: Alignment.centerRight, child: mark),
          ),
        ],
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  final PeriodReport r;
  const _Balance(this.r);

  @override
  Widget build(BuildContext c) {
    final ratio = r.balanceRatio;
    final band = ratio == null ? null : trainingBalanceOf(ratio);
    final (word, color, line) = switch (band) {
      TrainingBalance.easing => (
        'Easing off',
        C.dialStrain,
        'Your training ran lighter than what your body is used to.',
      ),
      TrainingBalance.balanced => (
        'Balanced',
        C.optimal,
        'Your training held steady with what your body is used to.',
      ),
      TrainingBalance.overreaching => (
        'Overreaching',
        C.strainDown,
        'Your training ran well past what your body is used to. Plan some '
            'easier days.',
      ),
      null => (
        'Not enough data',
        DC.ink2,
        'Training balance needs at least two weeks of strain.',
      ),
    };
    return _card(
      'Training Balance',
      info:
          'Fatigue is your mean strain over the last 7 days, fitness over the '
          'last 42. From 0.8 to 1.3 the two are balanced.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: S.x3 + S.half),
          Text(
            word,
            style: F.t2.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          if (ratio != null) ...[
            const SizedBox(height: S.x1 - S.hair),
            Text(
              'Fatigue ÷ Fitness ${ratio.toStringAsFixed(2)}',
              style: F.dTiny.copyWith(color: DC.ink2),
            ),
          ],
          const SizedBox(height: S.x3 + S.half),
          Text(
            line,
            style: F.dBody.copyWith(
              color: DC.ink2,
              fontWeight: FontWeight.w400,
              height: 1.38,
            ),
          ),
        ],
      ),
      bottom: S.x4 + S.half,
    );
  }
}

class _Effects extends StatelessWidget {
  final List<BehaviorImpact> top;
  const _Effects(this.top);

  @override
  Widget build(BuildContext c) {
    final scale = top.fold<double>(
      1,
      (a, b) => b.impact!.abs() > a ? b.impact!.abs() : a,
    );
    String pct(double v) => '${v > 0 ? '' : '−'}${v.abs().round()}%';
    return _card(
      'Top Journal Effects',
      action: Pressable(
        onTap: () => Navigator.of(c).push(
          MaterialPageRoute(builder: (_) => const BehaviorInsightsScreen()),
        ),
        semanticLabel: 'View all journal effects',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('VIEW ALL', style: F.dLabel.copyWith(color: DC.ink2)),
            const SizedBox(width: S.x1),
            const Icon(LucideIcons.chevronRight, size: I.sm, color: DC.ink2),
          ],
        ),
      ),
      info:
          'The journal entries whose days line up with the biggest change in '
          'next-morning recovery, over the last 90 days. An association in your '
          'own history, not proof of cause.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: S.x4 + S.hair),
          const ImpactHeader(),
          const SizedBox(height: S.x2 + S.hair),
          for (final b in top)
            Container(
              margin: const EdgeInsets.only(bottom: S.x2 + S.hair),
              padding: const EdgeInsets.fromLTRB(
                kDialPad,
                S.x3 + S.hair,
                kDialPad,
                S.x3 + S.half,
              ),
              decoration: const BoxDecoration(
                color: DC.weekCard,
                borderRadius: R.rLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.dBody.copyWith(
                      color: DC.ink,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: S.x3),
                  Row(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          size: const Size(double.infinity, S.x2),
                          painter: ImpactBarPaint(b.impact, scale),
                        ),
                      ),
                      SizedBox(
                        width: S.x12 + S.hair,
                        child: _fit(
                          Text(
                            impactText(b.impact!),
                            style: F.nWeek.copyWith(
                              color: impactTextColor(b.impact!),
                            ),
                          ),
                          Alignment.centerRight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x3 + S.half),
                  Text(
                    '${b.yes} days with, ${b.no} without.'
                    '${b.ci90 == null ? '' : ' 90% CI ${pct(b.ci90!.lo)} to ${pct(b.ci90!.hi)}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.dLegend.copyWith(color: DC.ink2),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottom: S.x2 + S.hair,
    );
  }
}

class _BestWorst extends StatelessWidget {
  final PeriodReport r;
  const _BestWorst(this.r);

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    Widget row(String label, ReportDay d) {
      final at = DateTime.parse(d.day);
      return Pressable(
        onTap: () => Navigator.of(
          c,
        ).push(MaterialPageRoute(builder: (_) => ReadinessDetail(day: d.day))),
        semanticLabel: '$label: recovery ${d.recovery.round()}%',
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: S.x16 + S.x10 + S.half),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: S.x2),
                    Text(label, style: F.dLabel.copyWith(color: DC.ink)),
                    const SizedBox(height: S.x1 + S.half),
                    Text(
                      '${weekdayShortName(at.weekday, l)}, ${at.day} '
                      '${monthShortName(at.month, l)}',
                      style: F.dLegend.copyWith(color: DC.ink2),
                    ),
                    const SizedBox(height: S.x2),
                  ],
                ),
              ),
              Flexible(
                flex: 2,
                child: _fit(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: _small,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CustomPaint(
                                  size: const Size.square(_small),
                                  painter: Ring(
                                    (d.recovery / 100).clamp(0.0, 1.0),
                                    recoveryColor(d.recovery),
                                    DC.track,
                                    stroke: _stroke,
                                    solid: true,
                                    flatStart: true,
                                    softStart: true,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(S.x2),
                                  child: _fit(
                                    _figure(
                                      '${d.recovery.round()}',
                                      '%',
                                      F.n17,
                                      F.nTiny,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: S.x4),
                          Text(
                            'Recovery',
                            style: F.dTiny.copyWith(color: DC.ink2),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: S.x16 + S.x4,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              d.strain == null
                                  ? '--'
                                  : d.strain!.toStringAsFixed(1),
                              style: F.nRow.copyWith(color: C.dialStrain),
                            ),
                            const SizedBox(height: S.x1),
                            Text(
                              'Strain',
                              style: F.dTiny.copyWith(color: DC.ink2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Alignment.centerRight,
                ),
              ),
              const SizedBox(width: S.x3),
              const Icon(LucideIcons.chevronRight, size: I.md, color: DC.ink2),
            ],
          ),
        ),
      );
    }

    return _card(
      'Best and Worst Day',
      info:
          'The days of this period with the highest and the lowest recovery, '
          'and the strain you took on that day.',
      bottom: S.x4 + S.half,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: S.x4 + S.hair),
          row('BEST DAY', r.best!),
          if (r.worst != null) ...[
            const Divider(height: S.hair, thickness: S.hair, color: DC.line),
            row('WORST DAY', r.worst!),
          ],
        ],
      ),
    );
  }
}

const _small = S.x16 - S.x1 - S.half;
