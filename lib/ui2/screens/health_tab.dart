// The Health tab: the live heart rate over its grid, then four cards — Locus
// Age, the Health Monitor, the Stress Monitor and the Journal — each opening
// its own screen. Laid out after the reference's Health tab, measured at
// 2.77 px to the dp (HT in theme.dart holds the numbers).
//
// Every card says what it has and nothing it does not: a vital with no
// reading has no tick, a stress day still calibrating says so, and an age
// still locked shows a dash. Green is never on a word (arrows, ticks and the
// blob keep it).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../compute/stress_monitor.dart' show kStressBaselineDays;
import '../../compute/whoop_age.dart' show WhoopAgeResult;
import '../../data/day_label.dart';
import '../../data/db.dart' show LocalDb;
import '../../data/local_repository.dart';
import '../ui2.dart';
import 'health_monitor.dart'
    show HealthHeartRate, HealthMonitorScreen, VitalGlance, vitalGlyph, vitalsGlanceOf;
import 'home_screen.dart' show go, repoOf, weekdayShortName;
import 'journal_compose.dart';
import 'locus_age.dart'
    show LocusAgeScreen, finishedSaturdays, locusRoughness, locusTones;
import 'locus_blob.dart';
import 'stress_monitor.dart'
    show StressMonitorData, StressMonitorScreen, StressSource, stressColor;
import 'trend_view.dart' show TrendLoader, shiftDay;

/// Everything the four cards draw. Each part is null until it loads, and
/// stays null when there is nothing to read.
class HealthTabData {
  final WhoopAgeResult? age, lastWeek;
  final List<VitalGlance> vitals;
  final StressMonitorData? stress;

  /// Entries logged on each of the last seven days, oldest first (today
  /// last): behaviours ticked plus numbers filled in.
  final List<int>? journal;

  const HealthTabData({
    this.age,
    this.lastWeek,
    this.vitals = const [],
    this.stress,
    this.journal,
  });

  static Future<HealthTabData> load(LocalRepository? repo) async {
    if (repo == null) return const HealthTabData();
    final today = todayLabel();
    final loader = TrendLoader(repo);
    Future<T?> safe<T>(Future<T> f) => f.then<T?>((v) => v).catchError((_) => null);
    // The week the Locus Age screen opens on, the last finished one, against
    // the week before it: today's unfinished week read differently from the
    // screen the card opens.
    final week = finishedSaturdays(today, 2);
    final got = await Future.wait<Object?>([
      safe(loader.whoopAge(asOf: week[0])),
      safe(loader.whoopAge(asOf: week[1])),
      safe(vitalsGlanceOf(repo)),
      safe(StressSource(repo).load(today)),
      safe(_journalWeek(repo, today)),
    ]);
    var age = got[0] as WhoopAgeResult?;
    var lastWeek = got[1] as WhoopAgeResult?;
    // No finished week yet: this week so far, as the screen shows it.
    if (age?.whoopAge == null) {
      age = await safe(loader.whoopAge(asOf: today));
      lastWeek = null;
    }
    return HealthTabData(
      age: age,
      lastWeek: lastWeek,
      vitals: (got[2] as List<VitalGlance>?) ?? const [],
      stress: got[3] as StressMonitorData?,
      journal: got[4] as List<int>?,
    );
  }

  static Future<List<int>> _journalWeek(LocalRepository repo, String today) async {
    final days = [for (var i = 6; i >= 0; i--) shiftDay(today, -i)];
    final tags = {
      for (final r in await repo.getJournal(range: '7d'))
        '${r['date']}': (r['tags'] as List?)?.length ?? 0,
    };
    final numbers = await repo.getJournalMetricsSince(days.first);
    return [
      for (final d in days) (tags[d] ?? 0) + (numbers[d]?.length ?? 0),
    ];
  }
}

class HealthTab extends StatefulWidget {
  const HealthTab({super.key});

  @override
  State<HealthTab> createState() => _HealthTabState();
}

class _HealthTabState extends State<HealthTab> with RevisionReload {
  HealthTabData _d = const HealthTabData();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
    // A journal entry is no derive: the card's count updates the moment it
    // is saved.
    LocalDb.journalRevision.addListener(reload);
  }

  @override
  void dispose() {
    LocalDb.journalRevision.removeListener(reload);
    super.dispose();
  }

  @override
  void reload() => unawaited(() async {
        final token = beginRead(#health);
        final d = await HealthTabData.load(repoOf(context));
        if (mounted && stillNewest(#health, token)) setState(() => _d = d);
      }());

  @override
  Widget build(BuildContext c) => HealthTabView(
        data: _d,
        onAge: () => go(c, const LocusAgeScreen(page: true)),
        onHealth: () => go(c, const HealthMonitorScreen()),
        onStress: () => go(c, const StressMonitorScreen()),
        onJournal: () => go(c, const JournalCompose()),
      );
}

/// The tab drawn from [data]: what the renders and the gallery photograph.
class HealthTabView extends StatelessWidget {
  final HealthTabData data;
  final VoidCallback? onAge, onHealth, onStress, onJournal;

  /// The live heart rate at the top; a render passes a still one.
  final Widget? heart;

  const HealthTabView({
    super.key,
    required this.data,
    this.onAge,
    this.onHealth,
    this.onStress,
    this.onJournal,
    this.heart,
  });

  @override
  Widget build(BuildContext c) {
    final d = data;
    final h = MediaQuery.sizeOf(c).height;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HT.foot,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [...HT.page, HT.foot],
          stops: [
            for (final dp in HT.pageDepths) (dp / h).clamp(0.0, 1.0),
            1,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(bottom: S.navClear(c)),
          children: [
            SizedBox(
              height: S.x12,
              child: Center(
                child: Text('HEALTH', style: HM.title.copyWith(color: DC.pure)),
              ),
            ),
            heart ?? const HealthHeartRate(),
            const SizedBox(height: S.x5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4 - S.hair),
              child: Column(children: [
                LocusAgeCard(now: d.age, lastWeek: d.lastWeek, onTap: onAge),
                const SizedBox(height: S.x4),
                HealthMonitorCard(vitals: d.vitals, onTap: onHealth),
                const SizedBox(height: S.x4),
                StressCard(data: d.stress, onTap: onStress),
                const SizedBox(height: S.x4),
                JournalCard(week: d.journal, onTap: onJournal),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── the card shell ─────────────────────────────

/// A card: its title in tracked capitals with a chevron, then [child].
class _Card extends StatelessWidget {
  final String title, semantic;
  final VoidCallback? onTap;
  final Widget child;
  const _Card(this.title, this.semantic, this.onTap, this.child);

  @override
  Widget build(BuildContext c) {
    final card = Container(
      padding: const EdgeInsets.fromLTRB(
          HT.padX, HT.padTop, HT.padX - S.x1 - S.hair, HT.padBottom),
      decoration: const BoxDecoration(
        color: HM.card,
        borderRadius: BorderRadius.all(Radius.circular(HT.radius)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: HT.vitalIcon,
          child: Row(children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HM.kicker.copyWith(color: DC.pure)),
            ),
            const Icon(LucideIcons.chevronRight, size: I.md, color: HM.dash),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(right: S.x1 + S.hair),
          child: child,
        ),
      ]),
    );
    return Pressable(semanticLabel: semantic, onTap: onTap, child: card);
  }
}

/// The small rounded pill under a figure: an arrow and a few words.
class _Pill extends StatelessWidget {
  final String text;

  /// Null draws no arrow; otherwise up or down, in [arrow].
  final bool? up;
  final Color arrow, fill;
  const _Pill(this.text, {this.up, this.arrow = HT.mint, this.fill = HT.good});

  @override
  Widget build(BuildContext c) => Container(
        height: HT.pillH,
        padding: const EdgeInsets.symmetric(horizontal: S.x1 + S.hair),
        decoration: BoxDecoration(color: fill, borderRadius: R.rSm),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (up != null) ...[
            DeltaTriangle(up: up!, color: arrow, size: S.x2 - S.hair),
            const SizedBox(width: S.x1 + S.hair),
          ],
          Text(text, style: HT.pill.copyWith(color: DC.pure)),
        ]),
      );
}

/// The strip at a card's foot.
class _Strip extends StatelessWidget {
  final Widget child;
  final double height;
  const _Strip({required this.child, this.height = HT.stripH});

  @override
  Widget build(BuildContext c) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: S.x2 - S.hair),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: HT.strip,
          borderRadius: BorderRadius.all(Radius.circular(HT.stripRadius)),
        ),
        child: child,
      );
}

// ─────────────────────────────── Locus Age ────────────────────────────────

/// PACE OF AGING and its figure on the left, the age in its blob on the
/// right, and how far it sits from their real age in the strip below.
class LocusAgeCard extends StatelessWidget {
  final WhoopAgeResult? now, lastWeek;
  final VoidCallback? onTap;
  const LocusAgeCard({super.key, this.now, this.lastWeek, this.onTap});

  @override
  Widget build(BuildContext c) {
    final r = now ?? const WhoopAgeResult(why: 'no_data');
    final age = r.whoopAge, real = r.age, pace = r.pace;
    final delta = age == null || real == null ? null : age - real;
    final before = lastWeek?.pace;
    final (top, bottom, _) = locusTones(r);

    final Widget pill;
    if (pace == null) {
      pill = _Pill(age == null ? 'Unlocks with more data' : 'Needs 30 days',
          fill: HM.noneChip);
    } else if (before == null) {
      pill = const _Pill('First full week', fill: HM.noneChip);
    } else {
      final d = pace - before;
      pill = d.abs() < .05
          ? const _Pill('same as last week', fill: HM.noneChip)
          : d < 0
              ? const _Pill('slower vs. last week', up: false)
              : const _Pill('faster vs. last week',
                  up: true, arrow: C.poor, fill: HT.bad);
    }

    final words = delta == null
        ? null
        : delta.abs() < .05
            ? 'Same as'
            : '${delta.abs().toStringAsFixed(1)} Years '
                '${delta > 0 ? 'Older' : 'Younger'}';

    return _Card(
      'LOCUS AGE',
      age == null
          ? 'Locus Age. Not unlocked yet'
          : 'Locus Age ${age.toStringAsFixed(1)}. '
              '${pace == null ? '' : 'Pace of aging ${pace.toStringAsFixed(1)} times. '}'
              '${words ?? ''} your actual age',
      onTap,
      LayoutBuilder(builder: (c, box) {
        // The blob's centre sits 68 % across the card and 70 dp down it.
        final cx = (box.maxWidth + HT.padX * 2) * .679 - HT.padX;
        return Stack(clipBehavior: Clip.none, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: S.x5 + S.hair),
            // Everything left of the blob, shrunk to fit at large text.
            for (final w in [
              Text('PACE OF AGING', style: HT.kicker.copyWith(color: HM.label)),
              const SizedBox(height: S.x1 + S.hair),
              Text(pace == null ? '--' : '${pace.toStringAsFixed(1)}x',
                  style: HT.pace.copyWith(color: DC.pure)),
              const SizedBox(height: S.x2 + S.hair),
              pill,
            ])
              w is SizedBox
                  ? w
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: math.max(S.x16, cx - HT.blob / 2 - S.x2)),
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: w),
                    ),
            const SizedBox(height: S.x6 + S.hair),
            _Strip(
              height: HT.stripH - S.x1 - S.hair,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: words ?? (age == null ? 'Not unlocked yet' : '--'),
                      style: HT.stripSmall.copyWith(
                          color: DC.pure, fontWeight: FontWeight.w800)),
                  if (words != null)
                    TextSpan(
                        text: '   vs. Actual Age',
                        style: HT.stripSmall.copyWith(color: HM.label)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          // The notch the strip points up at the blob with.
          Positioned(
            left: cx - S.x2,
            bottom: HT.stripH - S.x1 - S.hair,
            child: CustomPaint(
              size: const Size(S.x4, S.x1 + S.hair),
              painter: _Notch(),
            ),
          ),
          Positioned(
            left: cx - HT.blob * .75,
            // Centred 70 dp down the card: 36 under its title row.
            top: S.x8 + S.x1 - HT.blob * .75,
            width: HT.blob * 1.5,
            height: HT.blob * 1.5,
            child: _MiniBlob(
              top: top,
              bottom: bottom,
              roughness: locusRoughness(r),
              label: age == null ? '--' : age.toStringAsFixed(1),
            ),
          ),
        ]);
      }),
    );
  }
}

class _Notch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
      Path()
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..close(),
      Paint()..color = HT.strip);

  @override
  bool shouldRepaint(_Notch old) => false;
}

/// The Locus Age blob, small: alive while motion is allowed, still otherwise.
class _MiniBlob extends StatefulWidget {
  final Color top, bottom;
  final String label;
  final double roughness;
  const _MiniBlob(
      {required this.top,
      required this.bottom,
      required this.label,
      required this.roughness});

  @override
  State<_MiniBlob> createState() => _MiniBlobState();
}

class _MiniBlobState extends State<_MiniBlob> with SingleTickerProviderStateMixin {
  final _sim = BlobSim();
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  void _tick(Duration now) {
    _sim.step((now - _last).inMicroseconds / Duration.microsecondsPerSecond);
    _last = now;
    _frame.value++;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.enabled(context)) {
      if (!_ticker.isActive) {
        _last = Duration.zero;
        unawaited(_ticker.start());
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    _sim.roughness = widget.roughness;
    return Stack(alignment: Alignment.center, children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: LocusBlobPainter(
                sim: _sim,
                radius: HT.blob / 2,
                top: widget.top,
                bottom: widget.bottom,
                glow: false,
                repaint: _frame,
              ),
            ),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.label, style: HT.blobNum.copyWith(color: DC.pure)),
          const SizedBox(height: S.x1),
          Text('LOCUS AGE', style: HT.blobLabel.copyWith(color: HM.label)),
        ]),
      ]);
  }
}

// ──────────────────────────── Health Monitor ──────────────────────────────

/// One column per vital: its glyph, its short name and a square that ticks
/// when it is inside the usual range. The strip says how many are.
class HealthMonitorCard extends StatelessWidget {
  final List<VitalGlance> vitals;
  final VoidCallback? onTap;
  const HealthMonitorCard({super.key, required this.vitals, this.onTap});

  static const _fallback = <VitalGlance>[
    (key: 'resp_rate', short: 'RESP', present: false, side: null),
    (key: 'resting_hr', short: 'RHR', present: false, side: null),
    (key: 'hrv', short: 'HRV', present: false, side: null),
    (key: 'skin_temp', short: 'TEMP', present: false, side: null),
  ];

  @override
  Widget build(BuildContext c) {
    final vs = vitals.isEmpty ? _fallback : vitals;
    final held = [for (final v in vs) if (v.present && v.side != null) v];
    final inside = held.where((v) => v.side == Side.inside).length;
    final anyReading = vs.any((v) => v.present);
    final allIn = held.isNotEmpty && inside == held.length;
    final String line = held.isEmpty
        ? (anyReading ? 'Learning your usual ranges' : 'No readings yet')
        : allIn
            ? '$inside/${held.length} metrics within range'
            : '${held.length - inside} of ${held.length} metrics out of range';

    Widget square(VitalGlance v) {
      final inRange = v.present && v.side == Side.inside;
      final out = v.present && v.side != null && v.side != Side.inside;
      return Container(
        width: HT.vitalSquare,
        height: HT.vitalSquare,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: inRange
              ? HT.good
              : out
                  ? HT.bad
                  : HM.noneChip,
          borderRadius: HT.rSquare,
        ),
        child: Icon(
          inRange
              ? LucideIcons.check
              : out
                  ? LucideIcons.triangleAlert
                  : LucideIcons.minus,
          size: HT.check,
          color: inRange
              ? HT.mint
              : out
                  ? C.poor
                  : HM.dash,
        ),
      );
    }

    final columns = <Widget>[];
    for (final (i, v) in vs.indexed) {
      if (i > 0) {
        columns.add(Container(width: S.hair, color: HT.divider));
      }
      columns.add(Expanded(
        child: Column(children: [
          vitalGlyph(v.key, HM.icon, size: HT.vitalIcon),
          const SizedBox(height: S.x2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(v.short, maxLines: 1, style: HT.vital.copyWith(color: DC.pure)),
          ),
          const SizedBox(height: S.x2),
          square(v),
        ]),
      ));
    }

    return _Card(
      'HEALTH MONITOR',
      'Health monitor. $line',
      onTap,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: S.x5 - S.hair),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: columns),
        ),
        const SizedBox(height: S.x4 - S.hair),
        _Strip(
          child: Row(children: [
            Container(
              width: HT.checkBox,
              height: HT.checkBox,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: allIn
                    ? HT.mint
                    : held.isEmpty
                        ? HM.noneChip
                        : C.poor,
                borderRadius: HT.rSquare,
              ),
              child: Icon(
                allIn
                    ? LucideIcons.check
                    : held.isEmpty
                        ? LucideIcons.minus
                        : LucideIcons.triangleAlert,
                size: HT.check,
                color: held.isEmpty ? HM.dash : HT.foot,
              ),
            ),
            const SizedBox(width: S.x2 + S.hair),
            Expanded(
              child: Text(line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HT.stripText.copyWith(color: DC.pure)),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ──────────────────────────── Stress Monitor ──────────────────────────────

/// TODAY'S HIGH STRESS against a typical day, beside the day's stress line.
class StressCard extends StatelessWidget {
  final StressMonitorData? data;
  final VoidCallback? onTap;
  const StressCard({super.key, this.data, this.onTap});

  @override
  Widget build(BuildContext c) {
    final d = data;
    final calibrating = d != null && d.baseline == null;
    final last = d?.last;
    final high = d == null || calibrating || last == null ? null : d.minutes.high;
    final typical = d?.typical?.high;

    final Widget pill;
    if (calibrating) {
      final n = kStressBaselineDays -
          d.usableDays.clamp(0, kStressBaselineDays - 1);
      pill = _Pill('Calibrating · $n more ${n == 1 ? 'day' : 'days'}',
          fill: HM.noneChip);
    } else if (high == null) {
      pill = const _Pill('No reading yet', fill: HM.noneChip);
    } else if (typical == null) {
      pill = const _Pill('Typical day after 3 days', fill: HM.noneChip);
    } else if ((high - typical).abs() < 1) {
      pill = const _Pill('same as a typical day', fill: HM.noneChip);
    } else if (high < typical) {
      pill = const _Pill('vs. typical day', up: false);
    } else {
      pill = const _Pill('vs. typical day',
          up: true, arrow: C.poor, fill: HT.bad);
    }

    return _Card(
      'STRESS MONITOR',
      high == null
          ? 'Stress monitor. ${calibrating ? 'Calibrating' : 'No reading'}'
          : 'Stress monitor. ${high ~/ 60} hours ${high % 60} minutes of high '
              'stress today',
      onTap,
      _FigureBeside(
        kicker: "TODAY'S HIGH STRESS",
        value: high == null ? '--' : '${high ~/ 60}:${(high % 60).toString().padLeft(2, '0')}',
        unit: high == null ? null : 'hrs',
        pill: pill,
        chart: CustomPaint(
          painter: _StressLine(
            last == null || d == null ? const [] : d.scores.sublist(0, last + 1),
          ),
        ),
      ),
    );
  }
}

/// A kicker, a figure and a pill on the left; a chart on the right.
class _FigureBeside extends StatelessWidget {
  final String kicker, value;
  final String? unit;
  final Widget pill, chart;
  const _FigureBeside({
    required this.kicker,
    required this.value,
    required this.pill,
    required this.chart,
    this.unit,
  });

  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(top: S.x2 + S.hair, bottom: S.x2 + S.hair),
        // At least the chart's height; taller only when large text needs it.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: HT.chartH),
          child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: S.x16 * 2 + S.x3 - S.hair,
              child: Padding(
                padding: const EdgeInsets.only(top: S.x5 - S.hair),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(kicker,
                        maxLines: 1, style: HT.kicker.copyWith(color: HM.label)),
                  ),
                  const SizedBox(height: S.x1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(value, style: HT.big.copyWith(color: DC.pure)),
                        if (unit != null) ...[
                          const SizedBox(width: S.x1 + S.hair),
                          Text(unit!, style: HT.unit.copyWith(color: HM.label)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: pill,
                  ),
                ]),
              ),
            ),
            const SizedBox(width: S.x1),
            Expanded(child: chart),
          ]),
          ),
        ),
      );
}

/// The day's stress, minute by minute in five-minute steps, coloured by its
/// level, fading in from the left, with a dashed line and a dot at now.
class _StressLine extends CustomPainter {
  final List<double?> scores;
  _StressLine(this.scores);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = HT.grid
      ..strokeWidth = 1;
    final plot = Rect.fromLTRB(S.x4, S.x1 + S.hair, size.width - S.x4, size.height - S.x4);
    for (var i = 0; i < 4; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    // Five-minute means, so the line reads as a line and not as noise.
    final pts = <double?>[];
    for (var i = 0; i < scores.length; i += 5) {
      final xs = [
        for (var j = i; j < math.min(i + 5, scores.length); j++) ?scores[j],
      ];
      pts.add(xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length);
    }
    final first = pts.indexWhere((v) => v != null);
    if (first < 0) return;
    final n = pts.length;
    double x(int i) => plot.left + (n == 1 ? plot.width : plot.width * i / (n - 1));
    double y(double v) => plot.bottom - plot.height * (v.clamp(0.0, 3.0) / 3);
    for (var i = first + 1; i < n; i++) {
      final a = pts[i - 1], b = pts[i];
      if (a == null || b == null) continue;
      final fade = ((i - first) / math.max(1, (n - first) * .18)).clamp(.25, 1.0);
      canvas.drawLine(
        Offset(x(i - 1), y(a)),
        Offset(x(i), y(b)),
        Paint()
          ..color = stressColor((a + b) / 2).withValues(alpha: fade)
          ..strokeWidth = S.x1 / 2 + S.hair
          ..strokeCap = StrokeCap.round,
      );
    }
    final lx = x(n - 1);
    final dash = Paint()
      ..color = HM.dash
      ..strokeWidth = 1.2;
    for (var dy = 0.0; dy < size.height; dy += S.x1 + S.hair) {
      canvas.drawLine(Offset(lx, dy), Offset(lx, math.min(dy + S.half, size.height)), dash);
    }
    final lastV = pts.last;
    if (lastV != null) {
      final p = Offset(lx, y(lastV));
      canvas.drawCircle(p, S.x2 - S.hair, Paint()..color = HT.foot);
      canvas.drawCircle(p, S.x1 + S.half, Paint()..color = DC.pure);
    }
  }

  @override
  bool shouldRepaint(_StressLine old) => old.scores != scores;
}

// ─────────────────────────────── Journal ──────────────────────────────────

/// What was logged today against the week, beside the week as bars.
class JournalCard extends StatelessWidget {
  /// Entries per day over the last seven, today last; null until loaded.
  final List<int>? week;
  final VoidCallback? onTap;
  const JournalCard({super.key, this.week, this.onTap});

  @override
  Widget build(BuildContext c) {
    final w = week;
    final today = w == null || w.isEmpty ? null : w.last;
    final before = w == null || w.length < 2 ? null : w.sublist(0, w.length - 1);
    final logged = before?.where((n) => n > 0).toList();
    final avg = logged == null || logged.isEmpty
        ? null
        : logged.reduce((a, b) => a + b) / logged.length;

    final Widget pill;
    if (today == null || today == 0) {
      pill = const _Pill('Tap to log today', fill: HM.noneChip);
    } else if (avg == null || (today - avg).abs() < .5) {
      pill = const _Pill('on your usual day', fill: HM.noneChip);
    } else {
      pill = _Pill('vs. your usual day', up: today > avg);
    }

    return _Card(
      'JOURNAL',
      today == null
          ? 'Journal'
          : 'Journal. $today ${today == 1 ? 'entry' : 'entries'} logged today',
      onTap,
      _FigureBeside(
        kicker: "TODAY'S ENTRIES",
        value: today == null ? '--' : '$today',
        unit: today == null ? null : (today == 1 ? 'entry' : 'entries'),
        pill: pill,
        chart: CustomPaint(painter: _WeekBars(w ?? const [])),
      ),
    );
  }
}

/// Seven bars, today's lit, under the same grid and "now" line as stress.
class _WeekBars extends CustomPainter {
  final List<int> week;
  _WeekBars(this.week);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(S.x4, S.x1 + S.hair, size.width - S.x4, size.height - S.x4);
    final grid = Paint()
      ..color = HT.grid
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    if (week.isEmpty) return;
    final top = math.max(1, week.reduce(math.max));
    final slot = plot.width / week.length;
    final barW = math.min(slot * .46, S.x3);
    for (final (i, n) in week.indexed) {
      final today = i == week.length - 1;
      final cx = plot.left + slot * (i + .5);
      final h = n == 0 ? S.half : plot.height * n / top;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - barW / 2, plot.bottom - h, cx + barW / 2, plot.bottom),
          const Radius.circular(R.sm / 3),
        ),
        Paint()..color = today ? HM.line : HM.line.withValues(alpha: .35),
      );
      // Today is the last bar; each before it a day earlier.
      final weekday = (DateTime.now().weekday - 1 - (week.length - 1 - i)) % 7 + 1;
      final tp = TextPainter(
        text: TextSpan(
          text: weekdayShortName(weekday, null).substring(0, 1),
          style: HM.caps.copyWith(color: today ? DC.pure : HM.dash),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, plot.bottom + S.x1));
    }
  }

  @override
  bool shouldRepaint(_WeekBars old) => old.week != week;
}
