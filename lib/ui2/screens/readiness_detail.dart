import '../../l10n/presentation_text.dart';
// RECOVERY — the dial's own screen, laid out from the reference recording (sizes
// at 1.5 px to the dp, see DC): the ring and its four contributors against the
// last 30 days, the door to Behavior Insights, then seven days of each.
//
// A contributor with no stored value is '--' with no triangle; a morning that
// did not score keeps the pipeline's own reason in place of the ring.

import 'package:flutter/material.dart';
import 'package:openstrap_analytics/onehz.dart' show readinessCompositeMinBaseline;

import '../../compute/onehz_pipeline.dart'
    show
        kUnknownAbsenceNote,
        readinessInputShortfallNote,
        readinessUnstableBaselineNote;
import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart';
import '../../models/payloads.dart' show todayHeadlineOf;
import '../ui2.dart';
import 'behavior_insights.dart';
import 'dial_parts.dart';
import 'home_screen.dart';
import 'trend_view.dart' show TrendViewScreen, shiftDay;

/// How far back "last 30 days" reaches.
const _window = 30;

/// The stored series the screen reads, by day.
class RecoveryVitals {
  /// Seven days ending on the morning shown, oldest first.
  final List<String> week;
  final Map<String, double> recovery, hrv, restingHr, resp, sleepPerf;
  final int? streak;
  const RecoveryVitals({
    this.week = const [],
    this.recovery = const {},
    this.hrv = const {},
    this.restingHr = const {},
    this.resp = const {},
    this.sleepPerf = const {},
    this.streak,
  });

  /// The mean of a series over the [_window] days before [day].
  double? prior(Map<String, double> m, String? day) {
    if (day == null) return null;
    final xs = [
      for (var i = 1; i <= _window; i++) ?m[shiftDay(day, -i)],
    ];
    return xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
  }

  static Future<RecoveryVitals> load(LocalRepository repo, String day) async {
    final recovery = await dialSeries(repo, 'recovery');
    var streak = 0;
    for (var d = day; recovery[d] != null; d = shiftDay(d, -1)) {
      streak++;
    }
    return RecoveryVitals(
      week: [for (var i = 6; i >= 0; i--) shiftDay(day, -i)],
      recovery: recovery,
      hrv: await dialSeries(repo, 'hrv'),
      restingHr: await dialSeries(repo, 'resting_hr'),
      resp: await dialSeries(repo, 'resp'),
      sleepPerf: await dialSeries(repo, 'sleep_performance'),
      streak: streak == 0 ? null : streak,
    );
  }
}

class ReadinessData {
  final Metric readiness;

  /// `readiness_absent_diag` off the stored bundle — per input `{value,
  /// baseline_n}` plus the composite's own `note`. Produced on
  /// EVERY day readiness comes back absent, and until now its only destination
  /// was a Firebase breadcrumb: the app told its developer why the number was
  /// missing and never told the person looking at the gap.
  ///
  /// Null when readiness scored, which is the same fact as the number existing.
  final Map<String, dynamic>? absentDiag;

  /// The last night that scored, when that is NOT today's.
  ///
  /// It is no longer the source of the number above — [overnightMetric]
  /// refuses an older night, so the headline is today's or it is absent, and
  /// the screen no longer wears a date in its nav bar claiming otherwise. What
  /// is left is coverage: naming the night the data stops at, inside the
  /// absence.
  final String? heldOverNight;

  /// `todayHeadlineOf` off the same `getToday()`: the state and update note
  /// Home shows beside this number.
  final Map<String, dynamic> head;

  bool get provisional => head['recovery_state'] == 'provisional';

  const ReadinessData({
    this.head = const {},
    this.readiness = Metric.empty,
    this.heldOverNight,
    this.absentDiag,
    this.day,
    this.vitals = const RecoveryVitals(),
  });

  /// The day on screen.
  final String? day;
  final RecoveryVitals vitals;

  /// A past [day]: its stored score off the recovery series, and why it is
  /// missing when it is.
  static Future<ReadinessData> loadDay(LocalRepository repo, String day) async {
    final vitals = await RecoveryVitals.load(repo, day);
    final v = vitals.recovery[day];
    return ReadinessData(
      day: day,
      vitals: vitals,
      readiness: v == null ? const Metric(note: kUnknownAbsenceNote) : Metric(value: v),
      absentDiag: v != null ? null : await LocalDb.readinessAbsentDiag(day),
    );
  }

  static Future<ReadinessData> load(LocalRepository repo,
      {String? day}) async {
    if (day != null && day != todayLabel()) return loadDay(repo, day);
    final today = await repo.getToday();
    final daily = today['daily'];

    // Same rule as Home: a provisional night shows its own number, greyed.
    final head = todayHeadlineOf(today);
    final readiness = head['recovery_state'] == 'provisional'
        ? metricOf(daily is Map ? daily['readiness_provisional'] : null)
        : overnightMetric(
            today, daily is Map ? daily['readiness'] : null);
    final shown = (today['status'] as Map?)?['today_day']?.toString() ?? todayLabel();

    return ReadinessData(
      day: shown,
      head: head,
      readiness: readiness,
      heldOverNight: heldOverNightOf(today),
      vitals: await RecoveryVitals.load(repo, shown),
      // Only read when there is nothing to explain away — a scored day has no
      // diag in its bundle anyway, and this is one more day_result decode.
      //
      // TODAY'S DAY, never the held-over one. The held-over night usually
      // scored fine, so its diagnostic explains an absence that is not the one
      // on screen: it would list four measured inputs under a card saying the
      // number is missing. A day with no bundle has no diag and this comes back
      // null, which is correct — the note on the metric is the reason then.
      absentDiag: readiness.value != null
          ? null
          : await LocalDb.readinessAbsentDiag(
              (today['status'] as Map?)?['today_day']?.toString()),
    );
  }
}

class ReadinessDetail extends StatefulWidget {
  final ReadinessData? data;

  /// The day to open; null is today.
  final String? day;
  const ReadinessDetail({super.key, this.data, this.day});

  @override
  State<ReadinessDetail> createState() => _ReadinessDetailState();
}

class _ReadinessDetailState extends State<ReadinessDetail> {
  ReadinessData? _d;
  bool _loading = true;
  late final String? _day = widget.day;

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _d = widget.data;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final d = await ReadinessData.load(repo, day: _day);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = _d ?? const ReadinessData();
    final v = d.readiness.value;
    final name = dialDayName(d.day ?? _day, l);
    final title = name.isEmpty ? (l?.readinessDetailTitle ?? 'Recovery') : name;
    final badge = StreakBadge(StreakKind.recovery, d.vitals.streak);

    if (_loading && _d == null) {
      return DialScaffold(title: title, trailing: badge, children: const [
        SizedBox(height: S.x8),
        Center(child: CircularProgressIndicator()),
      ]);
    }

    return DialScaffold(title: title, trailing: badge, children: [
      if (v == null)
        // No `why:`. The pipeline records why readiness abstained on every
        // day it does, and the "What was missing" section directly below
        // shows the same record in more detail. `why:` below reuses the
        // EXACT SAME computed reason as that section (readinessInputShortfallNote
        // off d.absentDiag) rather than a second, independently-guessed one
        // — the two must never be able to disagree, only one be shorter.
        // readinessUnstableBaselineNote covers the OTHER absence shape
        // (PR #510): a z-cap withhold has no baseline shortfall to report
        // (every input already cleared its floor), so the first function
        // alone fell straight to the generic fallback for it.
        Builder(builder: (c) {
          final diagReason = readinessInputShortfallNote(d.absentDiag) ??
              readinessUnstableBaselineNote(
                  d.absentDiag?['note']?.toString());
          // StatusCard.forMetric prefers a prose note already ON the
          // metric (`told`, via whyFromNote) over `why:` — deliberately,
          // for screen-authored text like the held-over "nothing synced
          // yet" sentence [overnightMetric] attaches. When that wins, the
          // diagnostic reason above never reaches the banner at all
          // (PR #510 follow-up) — _absence below shows it in that one
          // case so it is not lost from the screen entirely, without
          // reintroducing the general "says it twice" duplication fixed
          // earlier in this same PR. Mirrors forMetric's precedence
          // exactly: a need_baseline note is rendered as the fix, not
          // `told`, so `why:` still wins there; a `gap` replaces `why:`.
          final note = d.readiness.note;
          final bannerShowsDiag = d.heldOverNight == null &&
              (needMessageFromNote(note) != null ||
                  whyFromNote(note) == null);
          return Column(children: [
            StatusCard.forMetric(
                    l?.readinessDetailNotScoredTitle ??
                        'Recovery is not scored',
                    d.readiness,
                    why: diagReason ?? '',
                    // Where the data stops, appended to whatever the
                    // pipeline said. Not a substitute for the reason and
                    // not a reading — "the last one was Saturday" is a
                    // fact about coverage.
                    gap: d.heldOverNight == null
                        ? null
                        : (l?.readinessDetailLastNightScored(
                                prettyDay(d.heldOverNight, l)) ??
                            'The last night scored was '
                                '${prettyDay(d.heldOverNight, l)}.')) ??
                const SizedBox.shrink(),
            if (d.absentDiag != null)
              Section(
                  l?.readinessDetailWhatWasMissing ?? 'What was missing',
                  _absence(
                    c,
                    p,
                    d.absentDiag!,
                    fallbackReason: bannerShowsDiag ? null : diagReason,
                  )),
          ]);
        })
      else
        DialRing(
          fraction: d.readiness.normalized(100),
          // A provisional score keeps a grey arc and grey figure: this number
          // may still move.
          color: d.provisional ? DC.ink3 : recoveryColor(v),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Wordmark(color: DC.ink3),
            const SizedBox(height: S.x1 + S.hair),
            dialFigure(v.toDouble(), d.provisional ? DC.ink3 : DC.ink),
            const SizedBox(height: S.x2),
            Text((l?.readinessDetailTitle ?? 'Recovery').toUpperCase(),
                style: F.dHero.copyWith(color: DC.ink)),
          ]),
        ),
      if (v != null && recoveryStateLine(d.head, l) != null)
        Padding(
          padding: const EdgeInsets.only(top: S.x2),
          child: Center(
            child: Text(recoveryStateLine(d.head, l)!,
                style: F.dText.copyWith(color: DC.ink3)),
          ),
        ),
      const SizedBox(height: S.x6 + S.half + S.hair),
      _contributors(c, d),
      const SizedBox(height: S.x8),
      Pressable(
        onTap: () => go(c, BehaviorInsightsScreen(day: d.day ?? _day)),
        semanticLabel: 'Behavior Insights',
        child: Container(
          constraints: const BoxConstraints(minHeight: S.x16 + S.x1 - S.hair),
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
          decoration: dialCard(DC.weekCard),
          child: Row(children: [
            const StatIcon(StatMark.bulb, color: DC.ink2, size: S.x5),
            const SizedBox(width: S.x2),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BEHAVIOR INSIGHTS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.dInsight.copyWith(color: DC.ink)),
                    const SizedBox(height: S.hair),
                    Text('See how what you do lines up with recovery.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.dText.copyWith(color: DC.ink2)),
                  ]),
            ),
            const Icon(LucideIcons.chevronRight, size: I.md, color: DC.ink2),
          ]),
        ),
      ),
      const SizedBox(height: S.x12 + S.hair),
      dialHeading('Weekly Trends'),
      const SizedBox(height: S.x8 + S.half),
      _RecoveryWeek(d.vitals),
    ]);
  }

  /// The panel under the ring: four contributors against their last 30 days.
  Widget _contributors(BuildContext c, ReadinessData d) {
    final v = d.vitals;
    final day = d.day ?? _day;
    Widget row(StatMark mark, String label, String metric, Map<String, double> m,
        String Function(double) text,
        {required bool higherBetter}) {
      final now = day == null ? null : m[day];
      final usual = v.prior(m, day);
      return _RecoveryRow(
        mark: mark,
        label: label,
        value: now == null ? '--' : text(now),
        usual: usual == null ? '' : text(usual),
        delta: deltaMark(now, usual, higherBetter, size: S.x2),
        onTap: () => Navigator.of(c).push(MaterialPageRoute(
            builder: (_) => TrendViewScreen(initial: metric))),
      );
    }

    const hair = Divider(height: S.hair, thickness: S.hair, color: DC.line);
    return CaretPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.x4 + S.hair),
        child: Column(children: [
          row(StatMark.hrv, 'Heart rate variability', 'hrv', v.hrv,
              (x) => '${x.round()}', higherBetter: true),
          hair,
          row(StatMark.restingHr, 'Resting heart rate', 'resting_hr', v.restingHr,
              (x) => '${x.round()}', higherBetter: false),
          hair,
          row(StatMark.respRate, 'Respiratory rate', 'resp_rate', v.resp,
              (x) => x.toStringAsFixed(1), higherBetter: false),
          hair,
          row(StatMark.sleepPerf, 'Sleep performance', 'sleep_perf', v.sleepPerf,
              (x) => '${x.round()}%', higherBetter: true),
          const SizedBox(height: S.x3 + S.hair),
          Container(
            height: S.x6,
            padding: const EdgeInsets.symmetric(horizontal: S.x3),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(color: DC.well, borderRadius: R.rMd),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
              const DeltaTriangle(up: true, color: C.optimal, size: S.x2),
              const SizedBox(width: S.x1),
              const DeltaTriangle(up: false, color: C.strainDown, size: S.x2),
              const SizedBox(width: S.x2),
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: dialDayName(day, AppLocalizations.of(c)),
                    style: F.dLegend.copyWith(color: DC.ink)),
                TextSpan(
                    text: ' vs. last 30 days',
                    style: F.dLegend.copyWith(color: DC.ink2)),
              ])),
            ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// The pipeline's own absence diagnostic, one row per input: did last night
  /// produce this input, and how many of your own nights are behind it
  /// against the floor every input needs ([readinessCompositeMinBaseline]).
  /// The genuine "why" sentence lives ONLY in the banner above this section
  /// now (built from the same [readinessInputShortfallNote] off the same
  /// [diag]) — this used to repeat a second copy of it here, which read as
  /// the screen saying the same thing twice.
  /// [fallbackReason] is non-null ONLY in the one case the banner above this
  /// section does not already show the diagnostic reason itself: a held-over
  /// night (the `gap` sentence replaces `why:`), or a prose note on the
  /// metric that `StatusCard.forMetric` prefers over it. Null in the ordinary case — the banner
  /// already said it once, and repeating it here is the exact duplication a
  /// prior pass of this same PR removed.
  Widget _absence(
    BuildContext c,
    P p,
    Map<String, dynamic> diag, {
    String? fallbackReason,
  }) {
    final l = AppLocalizations.of(c);
    final rows = <(String, String)>[];
    for (final k in const ['hrv', 'rhr', 'resp', 'temp']) {
      final e = diag[k];
      if (e is! Map) continue;
      final n = (e['baseline_n'] as num?)?.toInt() ?? 0;
      rows.add((
        driverLabel(k, l),
        '${e['value'] == true ? (l?.readinessDetailMeasured ?? 'Measured') : (l?.readinessDetailNotMeasured ?? 'Not measured')} · '
            '${l?.readinessDetailNightsOfTarget(n, readinessCompositeMinBaseline) ?? '$n of $readinessCompositeMinBaseline nights'}',
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(
          // Explicit, not the default `center`: each row's inner Column
          // shrink-wraps to its own (narrow) text width, same as every row
          // in `_breakdown` below it — the difference is that `_breakdown`'s
          // rows are a `Row` (fills the full width by default regardless of
          // the parent's alignment), so only this Column needed the
          // alignment said out loud for the two sections to actually match.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x3),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rows[i].$1, style: F.body.copyWith(color: p.ink)),
                      Text(rows[i].$2,
                          style: F.over.copyWith(color: p.ink3)),
                    ]),
              ),
            ],
          ],
          ),
        ),
        if (fallbackReason != null) ...[
          const SizedBox(height: S.x3),
          Text(
            presentationText(l, fallbackReason),
            style: F.cap.copyWith(color: p.ink3, height: 1.5),
          ),
        ],
      ],
    );
  }
}

class _RecoveryRow extends StatelessWidget {
  final StatMark mark;
  final String label, value, usual;
  final Widget? delta;
  final VoidCallback onTap;
  const _RecoveryRow({
    required this.mark,
    required this.label,
    required this.value,
    required this.usual,
    required this.delta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label $value, usually $usual',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: S.x16),
        child: Row(children: [
          const SizedBox(width: S.x1 + S.hair),
          StatIcon(mark, color: DC.ink2, size: S.x5 + S.hair),
          const SizedBox(width: S.x2 + S.hair + S.hair),
          Expanded(
            child: Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.dLabel.copyWith(color: DC.ink)),
          ),
          Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: F.nRow.copyWith(color: DC.ink)),
                if (usual.isNotEmpty) ...[
                  const SizedBox(height: S.half),
                  Text(usual, style: F.nTiny.copyWith(color: DC.ink2)),
                ],
              ]),
          SizedBox(
            width: S.x5,
            child: Center(child: delta ?? const SizedBox.shrink()),
          ),
          const SizedBox(width: S.x2),
        ]),
      ),
    );
  }
}

/// Seven days of each contributor, and of Recovery itself.
class _RecoveryWeek extends StatelessWidget {
  final RecoveryVitals v;
  const _RecoveryWeek(this.v);

  @override
  Widget build(BuildContext c) {
    final week = v.week;
    if (week.isEmpty) return const SizedBox.shrink();

    Widget line(String title, String id, Map<String, double> m,
        String Function(double) text) {
      final values = [for (final d in week) m[d]];
      final (lo, hi) = weekLineAxis(values);
      return WeekCard(
        title: title,
        metricId: id,
        chart: WeekChart(days: week, lo: lo, hi: hi, lines: [
          WeekLine(
            values: values,
            labels: [for (final x in values) x == null ? '' : text(x)],
            color: DC.line2,
            area: true,
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WeekCard(
        title: 'Recovery',
        metricId: 'recovery',
        chart: WeekChart(days: week, lo: 0, hi: 100, columns: [
          for (final d in week)
            if (v.recovery[d] case final x?)
              WeekColumn(hi: x, top: '${x.round()}%', color: recoveryColor(x))
            else
              const WeekColumn(),
        ]),
      ),
      line('Heart rate variability', 'hrv', v.hrv, (x) => '${x.round()}'),
      line('Resting heart rate', 'resting_hr', v.restingHr, (x) => '${x.round()}'),
      line('Respiratory rate', 'resp_rate', v.resp, (x) => x.toStringAsFixed(1)),
      WeekCard(
        title: 'Sleep performance',
        metricId: 'sleep_perf',
        chart: WeekChart(days: week, lo: 0, hi: 100, columns: [
          for (final d in week)
            if (v.sleepPerf[d] case final x?)
              WeekColumn(hi: x, top: '${x.round()}%', color: C.dialSleep)
            else
              const WeekColumn(),
        ]),
      ),
    ]);
  }
}
