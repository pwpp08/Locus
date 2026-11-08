// PROFILE — what the avatar on Home opens: the best of the circles, the
// longest streaks and the notable figures of a chosen stretch of time, then
// what was trained in it. Every size here is measured off the reference
// recording at 1.5 px to the dp (see [PH]).
//
// Nothing here is estimated to fill a row: a figure with no days behind it is
// a '--' in the circles and streaks, and no row at all in the lists.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/day_label.dart';
import '../../data/db.dart' show LocalDb;
import '../activity/catalogue.dart';
import '../screens/dial_parts.dart';
import '../screens/home/home_data.dart' show recoveryColor, thousands;
import '../screens/home_screen.dart' show repoOf;
import '../screens/trend_view.dart' show shiftDay;
import '../ui2.dart';

/// The stretch of time a card reads.
enum HighlightPeriod {
  month('1M'),
  quarter('3M'),
  all('ALL TIME');

  const HighlightPeriod(this.label);
  final String label;

  /// The first day it covers; null for all of it.
  String? fromDay(DateTime today) => switch (this) {
    HighlightPeriod.month =>
      dayLabelOf(DateTime(today.year, today.month - 1, today.day)),
    HighlightPeriod.quarter =>
      dayLabelOf(DateTime(today.year, today.month - 3, today.day)),
    HighlightPeriod.all => null,
  };
}

/// The most days in a row whose value passes. Null with no days at all, so
/// "no data" never reads as a streak of nothing.
int? longestStreak(Map<String, double> byDay, bool Function(double) pass) {
  if (byDay.isEmpty) return null;
  final days = byDay.keys.toList()..sort();
  var best = 0, run = 0;
  String? prev;
  for (final d in days) {
    if (!pass(byDay[d]!)) {
      run = 0;
    } else {
      run = prev != null && run > 0 && shiftDay(prev, 1) == d ? run + 1 : 1;
      best = math.max(best, run);
    }
    prev = d;
  }
  return best;
}

/// One line of Notable Stats.
class NotableStat {
  final StatMark mark;
  final String title, value, unit;
  const NotableStat(this.mark, this.title, this.value, this.unit);
}

/// The top card's figures for one period.
class Highlights {
  final double? bestSleep, peakRecovery, maxStrain;
  final int? sleepStreak, recoveryStreak, strainStreak;
  final List<NotableStat> notable;
  const Highlights({
    this.bestSleep,
    this.peakRecovery,
    this.maxStrain,
    this.sleepStreak,
    this.recoveryStreak,
    this.strainStreak,
    this.notable = const [],
  });
}

/// Compact heartbeats: 5.4M, 412k, 980.
String _beats(double n) => n >= 1e6
    ? '${(n / 1e6).toStringAsFixed(1)}M'
    : n >= 1e3
    ? '${(n / 1e3).round()}k'
    : '${n.round()}';

/// [series] is value per day by series name ([kHighlightSeries], plus
/// `hr_max` and `hr_avg`); [from] is the first day counted, null for all.
Highlights highlightsOf(Map<String, Map<String, double>> series, String? from) {
  Map<String, double> of(String k) => {
    for (final e in (series[k] ?? const <String, double>{}).entries)
      if ((from == null || e.key.compareTo(from) >= 0) && e.value > 0)
        e.key: e.value,
  };
  double? top(Iterable<double> v) => v.isEmpty ? null : v.reduce(math.max);
  double? low(Iterable<double> v) => v.isEmpty ? null : v.reduce(math.min);
  double? sum(Iterable<double> v) =>
      v.isEmpty ? null : v.reduce((a, b) => a + b);

  final sleep = of('sleep_performance'),
      recovery = of('recovery'),
      strain = of('strain'),
      rhr = of('resting_hr'),
      hrv = of('hrv'),
      tst = of('tst_min'),
      worn = of('worn_min'),
      avg = of('hr_avg');

  final notable = <NotableStat>[];
  void add(StatMark m, String title, double? v, String unit,
      [String Function(double)? fmt]) {
    if (v == null) return;
    notable.add(NotableStat(m, title, (fmt ?? (x) => '${x.round()}')(v), unit));
  }

  add(StatMark.heartDown, 'Lowest RHR', low(rhr.values), 'bpm');
  add(StatMark.heartUp, 'Highest RHR', top(rhr.values), 'bpm');
  add(StatMark.pulseDown, 'Lowest HRV', low(hrv.values), 'ms');
  add(StatMark.pulseUp, 'Highest HRV', top(hrv.values), 'ms');
  add(StatMark.heartUp, 'Max Heart Rate', top(of('hr_max').values), 'bpm');
  add(StatMark.sleepPerf, 'Longest Sleep', top(tst.values), 'hr', clockDur);
  add(StatMark.lotus, 'Lowest Recovery', low(recovery.values), '%');
  // What used to be Milestones: running totals of the same period.
  add(StatMark.flame, 'Energy Burned', sum(of('calories').values), 'kcal',
      thousands);
  add(StatMark.steps, 'Steps Taken', sum(of('steps').values), 'steps',
      thousands);
  add(StatMark.hoursNeeded, 'Time Slept',
      tst.isEmpty ? null : sum(tst.values)! / 60, 'hr', thousands);
  // Only days with both a mean heart rate and a worn time count: a day
  // without either has no heartbeats to add, not an average one.
  add(
    StatMark.heartbeat,
    'Heartbeats',
    sum([
      for (final d in avg.keys)
        if (worn[d] != null) avg[d]! * worn[d]!,
    ]),
    'beats',
    _beats,
  );

  return Highlights(
    bestSleep: top(sleep.values),
    peakRecovery: top(recovery.values),
    maxStrain: top(strain.values),
    sleepStreak: longestStreak(sleep, (v) => v >= 70),
    recoveryStreak: longestStreak(recovery, (v) => v >= 67),
    strainStreak: longestStreak(strain, (v) => v >= 10),
    notable: notable,
  );
}

/// One kind of activity over a period.
class ActivityTally {
  final String name;
  final IconData? icon;
  final int count;

  /// Mean of the sessions that were scored; null when none were.
  final double? avgStrain;
  const ActivityTally(this.name, this.icon, this.count, this.avgStrain);
}

/// Every kind with at least one finished session since [from], the most
/// frequent first and then by name. [sessions] are `getSessions` rows.
List<ActivityTally> tallyOf(
  List<Map<String, dynamic>> sessions,
  String? from, {
  String Function(Activity)? nameOf,
}) {
  final by = <String, List<Map<String, dynamic>>>{};
  for (final s in sessions) {
    final start = s['start_ts'] as num?;
    final type = s['type']?.toString();
    if (start == null || s['end_ts'] == null || type == null) continue;
    final day = dayLabelOf(
      DateTime.fromMillisecondsSinceEpoch(start.toInt() * 1000),
    );
    if (from != null && day.compareTo(from) < 0) continue;
    (by[activityByName(type)?.typeKey ?? type] ??= []).add(s);
  }
  final out = [
    for (final e in by.entries)
      () {
        final a = activityByName(e.key);
        final scored = [
          for (final s in e.value)
            if (s['strain'] case final num v) v.toDouble(),
        ];
        return ActivityTally(
          a == null ? e.key : (nameOf?.call(a) ?? a.name),
          a?.icon,
          e.value.length,
          scored.isEmpty
              ? null
              : scored.reduce((x, y) => x + y) / scored.length,
        );
      }(),
  ];
  return out
    ..sort((a, b) {
      final n = b.count.compareTo(a.count);
      return n != 0 ? n : a.name.compareTo(b.name);
    });
}

/// The stored series the top card reads.
const kHighlightSeries = [
  'sleep_performance',
  'recovery',
  'strain',
  'resting_hr',
  'hrv',
  'tst_min',
  'calories',
  'steps',
  'worn_min',
];

class DataHighlightsScreen extends StatefulWidget {
  /// The series and sessions to show, for tests and the gallery; read from the
  /// repository when null.
  final Map<String, Map<String, double>>? series;
  final List<Map<String, dynamic>>? sessions;
  const DataHighlightsScreen({super.key, this.series, this.sessions});

  @override
  State<DataHighlightsScreen> createState() => _DataHighlightsScreenState();
}

class _DataHighlightsScreenState extends State<DataHighlightsScreen> {
  late Map<String, Map<String, double>> _series = widget.series ?? const {};
  late List<Map<String, dynamic>> _sessions = widget.sessions ?? const [];
  var _top = HighlightPeriod.all, _activity = HighlightPeriod.all;
  var _expanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.series == null) _load();
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) return;
    final series = <String, Map<String, double>>{};
    var sessions = const <Map<String, dynamic>>[];
    try {
      for (final k in kHighlightSeries) {
        series[k] = await dialSeries(repo, k);
      }
      final max = series['hr_max'] = {}, avg = series['hr_avg'] = {};
      for (final r in await LocalDb.dayTrendFigures()) {
        final d = r['day'] as String?;
        if (d == null) continue;
        if (r['hr_max'] case final num v) max[d] = v.toDouble();
        if (r['hr_avg'] case final num v) avg[d] = v.toDouble();
      }
      sessions = await repo.getSessions(
        from: 0,
        to: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    } catch (_) {
      // Whatever was read still shows; the rest stays absent.
    }
    if (mounted) {
      setState(() {
        _series = series;
        _sessions = sessions;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final today = DateTime.now();
    final h = highlightsOf(_series, _top.fromDay(today));
    final rows = tallyOf(
      _sessions,
      _activity.fromDay(today),
      nameOf: (a) => a.displayName(c),
    );
    return DialScaffold(
      title: 'Profile',
      barHeight: PH.barHeight,
      band: true,
      children: [
        const SizedBox(height: PH.toHeading),
        dialHeading('Data Highlights'),
        const SizedBox(height: PH.headingGap),
        _HighlightsCard(
          h: h,
          period: _top,
          onPeriod: (p) => setState(() => _top = p),
        ),
        const SizedBox(height: PH.cardGap),
        dialHeading('Activity Summary'),
        const SizedBox(height: PH.headingGap),
        _ActivityCard(
          rows: rows,
          period: _activity,
          onPeriod: (p) => setState(() => _activity = p),
          expanded: _expanded,
          onExpand: () => setState(() => _expanded = !_expanded),
        ),
      ],
    );
  }
}

/// The three-way period switch, the selected part a lighter pill.
class _PeriodBar extends StatelessWidget {
  final HighlightPeriod value;
  final ValueChanged<HighlightPeriod> onPick;
  const _PeriodBar({required this.value, required this.onPick});

  @override
  Widget build(BuildContext c) {
    const all = HighlightPeriod.values;
    return Container(
      height: PH.periodHeight,
      padding: const EdgeInsets.all(PH.periodInset),
      decoration: const BoxDecoration(color: PH.well, borderRadius: R.rXl),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: Alignment(-1.0 + value.index, 0),
            duration: motion(c, Motion.base),
            curve: Ease.standard,
            child: const FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PH.pill,
                  borderRadius: R.rMd,
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final p in all)
                Expanded(
                  child: Pressable(
                    onTap: () => onPick(p),
                    semanticLabel: p.label,
                    child: Center(
                      child: Text(
                        p.label,
                        maxLines: 1,
                        style: PH.period.copyWith(
                          color: p == value ? DC.pure : DC.body,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A figure with its small unit on the same baseline.
Widget _figure(String value, String unit, TextStyle style, TextStyle unitStyle,
    {double gap = PH.unitGap}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(value, maxLines: 1, style: style.copyWith(color: DC.pure)),
      if (unit.isNotEmpty) ...[
        SizedBox(width: gap),
        Text(unit, maxLines: 1, style: unitStyle),
      ],
    ],
  );
}

/// Capitals and a hairline running out to the card's inset.
Widget _kicker(String text) => Row(
  children: [
    Text(text, style: PH.kicker.copyWith(color: DC.body)),
    const SizedBox(width: PH.kickerGap),
    const Expanded(child: _Rule()),
  ],
);

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext c) =>
      const ColoredBox(color: DC.line, child: SizedBox(height: PH.hair));
}

class _HighlightsCard extends StatelessWidget {
  final Highlights h;
  final HighlightPeriod period;
  final ValueChanged<HighlightPeriod> onPeriod;
  const _HighlightsCard({
    required this.h,
    required this.period,
    required this.onPeriod,
  });

  @override
  Widget build(BuildContext c) {
    final strain = h.maxStrain;
    return Container(
      decoration: dialCard(),
      padding: const EdgeInsets.fromLTRB(
        kDialPad,
        kDialPad,
        kDialPad,
        PH.cardFoot,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodBar(value: period, onPick: onPeriod),
          const SizedBox(height: PH.toRings),
          Row(
            children: [
              _BestRing(
                value: h.bestSleep,
                max: 100,
                color: C.dialSleep,
                text: h.bestSleep?.round().toString(),
                pct: true,
                label: 'Best Sleep',
              ),
              _BestRing(
                value: h.peakRecovery,
                max: 100,
                color: h.peakRecovery == null
                    ? C.recGreen
                    : recoveryColor(h.peakRecovery!),
                text: h.peakRecovery?.round().toString(),
                pct: true,
                label: 'Peak Recovery',
              ),
              _BestRing(
                value: strain,
                max: 21,
                color: C.dialStrain,
                text: strain?.toStringAsFixed(1),
                label: 'Max Strain',
              ),
            ],
          ),
          const SizedBox(height: PH.toStreaks),
          _kicker('STREAKS'),
          const SizedBox(height: PH.toBadges),
          Row(
            children: [
              _Streak(
                nudge: -PH.streakNudge,
                mark: StatMark.sleepPerf,
                color: C.dialSleep,
                days: h.sleepStreak,
                what: '70%+ Sleep',
              ),
              _Streak(
                mark: StatMark.lotus,
                color: C.recGreen,
                days: h.recoveryStreak,
                what: 'Green Recovery',
              ),
              _Streak(
                nudge: PH.streakNudge,
                mark: StatMark.lifter,
                color: C.dialStrain,
                days: h.strainStreak,
                what: '10+ Strain',
              ),
            ],
          ),
          if (h.notable.isNotEmpty) ...[
            const SizedBox(height: PH.toNotable),
            _kicker('NOTABLE STATS'),
            const SizedBox(height: PH.toFirstRow),
            for (var i = 0; i < h.notable.length; i++) ...[
              if (i > 0) const _Rule(),
              _NotableRow(h.notable[i]),
            ],
          ],
        ],
      ),
    );
  }
}

class _BestRing extends StatelessWidget {
  final double? value;
  final double max;
  final Color color;
  final String? text;
  final bool pct;
  final String label;
  const _BestRing({
    required this.value,
    required this.max,
    required this.color,
    required this.text,
    required this.label,
    this.pct = false,
  });

  @override
  Widget build(BuildContext c) {
    final v = value;
    return Expanded(
      child: Semantics(
        label: '$label ${text ?? 'no data'}${pct && v != null ? ' percent' : ''}',
        excludeSemantics: true,
        child: Column(
          children: [
            SizedBox.square(
              dimension: PH.ring,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(PH.ring),
                    painter: Ring(
                      v == null ? 0 : (v / max).clamp(0.0, 1.0),
                      color,
                      DC.track,
                      stroke: PH.ringStroke,
                      solid: true,
                      flatStart: true,
                      softStart: true,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _figure(
                      text ?? '--',
                      pct && v != null ? '%' : '',
                      PH.figure,
                      PH.figureUnit.copyWith(color: DC.pure),
                      gap: PH.pctGap,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PH.ringToLabel),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.dBody.copyWith(color: DC.pure),
            ),
          ],
        ),
      ),
    );
  }
}

class _Streak extends StatelessWidget {
  final double nudge;
  final StatMark mark;
  final Color color;
  final int? days;
  final String what;
  const _Streak({
    required this.mark,
    required this.color,
    required this.days,
    required this.what,
    this.nudge = 0,
  });

  @override
  Widget build(BuildContext c) {
    final n = days;
    final count = n == null ? '--' : '$n ${n == 1 ? 'Day' : 'Days'}';
    return Expanded(
      child: Semantics(
        label: '$what streak, $count',
        excludeSemantics: true,
        child: Transform.translate(
          offset: Offset(nudge, 0),
          child: Column(
            children: [
              ScallopMark(mark, color: color),
              const SizedBox(height: PH.badgeToDays),
              Text(
                count,
                maxLines: 1,
                style: F.dBody.copyWith(color: DC.pure),
              ),
              Text(
                what,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PH.sub.copyWith(color: DC.body),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotableRow extends StatelessWidget {
  final NotableStat s;
  const _NotableRow(this.s);

  @override
  Widget build(BuildContext c) {
    return Semantics(
      label: '${s.title}, ${s.value} ${s.unit}',
      excludeSemantics: true,
      child: SizedBox(
        height: PH.rowHeight,
        child: Row(
          children: [
            ScallopMark(s.mark, color: PH.gold),
            const SizedBox(width: PH.badgeToTitle),
            Expanded(
              child: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.dBody.copyWith(color: DC.pure),
              ),
            ),
            const SizedBox(width: S.x2),
            _figure(
              s.value,
              s.unit,
              PH.figure,
              F.dText.copyWith(color: DC.body),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final List<ActivityTally> rows;
  final HighlightPeriod period;
  final ValueChanged<HighlightPeriod> onPeriod;
  final bool expanded;
  final VoidCallback onExpand;
  const _ActivityCard({
    required this.rows,
    required this.period,
    required this.onPeriod,
    required this.expanded,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext c) {
    final total = rows.fold<int>(0, (n, r) => n + r.count);
    final top = rows.isEmpty ? 1 : rows.first.count;
    final shown = expanded ? rows : rows.take(PH.collapsedRows).toList();
    return Container(
      decoration: dialCard(),
      padding: const EdgeInsets.all(kDialPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodBar(value: period, onPick: onPeriod),
          const SizedBox(height: PH.toTotal),
          Text('${total}x', style: PH.total.copyWith(color: DC.pure)),
          const SizedBox(height: PH.totalGap),
          Text('TOTAL ACTIVITIES', style: PH.kicker.copyWith(color: DC.ink3)),
          const SizedBox(height: PH.toHeader),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ACTIVITY | AVG. STRAIN',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PH.kicker.copyWith(color: DC.body),
                ),
              ),
              Text('TOTAL', style: PH.kicker.copyWith(color: DC.body)),
            ],
          ),
          const SizedBox(height: PH.toFirstActivity),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x2),
              child: Text(
                'No activities in this period.',
                style: F.dText.copyWith(color: DC.body),
              ),
            ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: PH.barToRule),
              const _Rule(),
              const SizedBox(height: PH.ruleToRow),
            ],
            _ActivityRow(shown[i], top: top),
          ],
          if (rows.length > PH.collapsedRows) ...[
            const SizedBox(height: PH.barToRule),
            Pressable(
              onTap: onExpand,
              semanticLabel: expanded ? 'Show less' : 'Show all',
              child: Container(
                height: PH.periodHeight,
                decoration: const BoxDecoration(
                  color: PH.pill,
                  borderRadius: R.rMd,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: I.md,
                      color: DC.pure,
                    ),
                    const SizedBox(width: S.x2),
                    Text(
                      expanded ? 'SHOW LESS' : 'SHOW ALL',
                      style: PH.period.copyWith(color: DC.pure),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final ActivityTally r;
  final int top;
  const _ActivityRow(this.r, {required this.top});

  @override
  Widget build(BuildContext c) {
    final avg = r.avgStrain?.toStringAsFixed(1);
    return Semantics(
      label:
          '${r.name}, ${r.count} times${avg == null ? '' : ', average strain $avg'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: PH.activityLine,
            child: Row(
              children: [
                SizedBox(
                  width: PH.activityIcon,
                  child: r.icon == null
                      ? null
                      : Icon(r.icon, size: I.md, color: DC.body),
                ),
                const SizedBox(width: PH.activityIconGap),
                // The name and its average share what the count leaves, so
                // the count stays against the right edge.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PH.kicker.copyWith(color: DC.pure),
                        ),
                      ),
                      if (avg != null) ...[
                        const SizedBox(width: PH.kickerGap),
                        Text(avg, style: PH.avg.copyWith(color: DC.body)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: S.x2),
                Text(
                  '${r.count}x',
                  style: PH.count.copyWith(color: C.dialStrain),
                ),
              ],
            ),
          ),
          const SizedBox(height: PH.lineToBar),
          HatchBar(r.count / top, C.dialStrain, height: PH.bar, coarse: true),
        ],
      ),
    );
  }
}
