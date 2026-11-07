// BEHAVIOR INSIGHTS — behind the Recovery screen. What the user's own days say
// about each behavior and the next morning's Recovery, then the ones with too few
// days to say yet. Everything is an association in their own history, and each
// figure is the difference of two means they can read on its details screen.

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:openstrap_analytics/onehz.dart' show journalTagLagDays;

import '../../compute/behavior_impact.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../ui2.dart';
import 'dial_parts.dart';
import 'home_screen.dart';
import 'journal_compose.dart';
import 'stress_monitor.dart' show StressSource;
import 'trend_view.dart' show shiftDay;

/// How far back the comparison reaches.
const _span = 90;

/// An impact this size or bigger wears the colour of its side.
const _strongImpact = 3.0;

class BehaviorInsightsData {
  final List<BehaviorImpact> behaviors;
  const BehaviorInsightsData({this.behaviors = const []});

  static Future<({BehaviorInsightsData data, List<String> days})> load(
      LocalRepository repo, String day) async {
    final days = [for (var i = _span - 1; i >= 0; i--) shiftDay(day, -i)];
    final recovery = await dialSeries(repo, 'recovery');
    final perf = await dialSeries(repo, 'sleep_performance');
    final strain = await dialSeries(repo, 'strain');
    final spans = await bedAndWake(repo, day: day, nights: _span + 1);

    final since = DateTime.parse(shiftDay(days.first, -2));
    final until = DateTime.parse(shiftDay(day, 1));
    final early = <String>{};
    for (final s in await repo.getSessions(
        from: since.millisecondsSinceEpoch ~/ 1000,
        to: until.millisecondsSinceEpoch ~/ 1000,
        includeDetected: false)) {
      final at = s['start_ts'];
      if (at is! num) continue;
      final t = DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000);
      if (t.hour < kEarlyWorkoutHour) early.add(dayLabelOf(t));
    }

    final logged = <String, Set<String>>{};
    for (final r in await repo.getJournal(range: '90d')) {
      final d = r['date'];
      final tags = r['tags'];
      if (d is String && tags is List) {
        logged[d] = {for (final t in tags) '$t'};
      }
    }

    return (
      days: days,
      data: BehaviorInsightsData(behaviors: [
        ...autoBehaviors(
          days: days,
          recovery: recovery,
          sleepPerformance: perf,
          bed: {for (final e in spans.entries) e.key: e.value.bed},
          wake: {for (final e in spans.entries) e.key: e.value.wake},
          strain: strain,
          highStressPct: const {},
          earlyWorkoutDays: early,
          dayBefore: (d) => shiftDay(d, -1),
        ),
        ...tagBehaviors(
          logged: logged,
          recovery: recovery,
          lagOf: (t) => journalTagLagDays[t] ?? 0,
          shift: shiftDay,
        ),
      ]),
    );
  }
}

class BehaviorInsightsScreen extends StatefulWidget {
  /// The day it runs up to.
  final String? day;
  final BehaviorInsightsData? data;
  const BehaviorInsightsScreen({super.key, this.day, this.data});

  @override
  State<BehaviorInsightsScreen> createState() => _BehaviorInsightsScreenState();
}

class _BehaviorInsightsScreenState extends State<BehaviorInsightsScreen> {
  BehaviorInsightsData? _d;
  bool _loading = true;

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
    final day = widget.day ?? todayLabel();
    try {
      final got = await BehaviorInsightsData.load(repo, day);
      if (!mounted) return;
      setState(() {
        _d = got.data;
        _loading = false;
      });
      unawaited(_addStress(repo, day, got.days, got.data));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The stress row reads every day's heart rate, so it joins after the screen
  /// has drawn, worked out away from the UI.
  Future<void> _addStress(LocalRepository repo, String day, List<String> days,
      BehaviorInsightsData base) async {
    try {
      final pct =
          await StressSource(repo).highPctByDay([for (final d in days) shiftDay(d, -1)]);
      if (!mounted || pct.isEmpty) return;
      final recovery = await dialSeries(repo, 'recovery');
      final split = splitDays(days, (d) => pct[shiftDay(d, -1)],
          (v) => v >= kHighStressDayPct);
      final row = impactOf(
          BehaviorKind.highStress,
          '${kHighStressDayPct.round()}%+ of the Day in High Stress Zone',
          recovery,
          yes: split.yes,
          no: split.no);
      if (mounted) {
        setState(() => _d =
            BehaviorInsightsData(behaviors: [...base.behaviors, row]));
      }
    } catch (_) {
      // No stress row: the others stand on their own.
    }
  }

  void _open(BuildContext c, BehaviorImpact b, double scale) =>
      Navigator.of(c).push(MaterialPageRoute(
          builder: (_) => BehaviorDetailsScreen(behavior: b, scale: scale)));

  @override
  Widget build(BuildContext c) {
    final all = _d?.behaviors ?? const <BehaviorImpact>[];
    final open = rankedOf(all);
    final locked = lockedOf(all);
    final scale = open.fold<double>(
        1, (a, b) => b.impact!.abs() > a ? b.impact!.abs() : a);
    return DialScaffold(
      title: 'Behavior Insights',
      barHeight: S.x16 + S.x12 + S.hair + S.hair - S.x8 - S.x1,
      titleAt: S.x10,
      children: [
        const SizedBox(height: S.x12 + S.x2),
        Text('Recovery Impact Analysis', style: F.dTitle.copyWith(color: DC.ink)),
        const SizedBox(height: S.x1 + S.hair),
        Text(
          'See how what you do lines up with your Recovery over the past '
          '90 days. Tap a behavior for the numbers behind it.',
          style: F.dBody.copyWith(color: DC.ink3),
        ),
        const SizedBox(height: S.x3 + S.half),
        Row(children: [
          const _SparkChip(),
          const SizedBox(width: S.x2),
          Text('Auto-generated Behaviors',
              style: F.dText.copyWith(color: DC.ink2)),
        ]),
        const SizedBox(height: S.x12 + S.x1),
        const _ImpactHeader(),
        const SizedBox(height: S.x2 + S.hair),
        if (_loading && _d == null)
          const Padding(
            padding: EdgeInsets.all(S.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
        for (final b in open)
          _ImpactRow(b, scale: scale, onTap: () => _open(c, b, scale)),
        if (locked.isNotEmpty) ...[
          const SizedBox(height: S.x6 + S.x1 - S.hair),
          Text('KEEP LOGGING TO UNLOCK', style: F.dNav.copyWith(color: DC.ink)),
          const SizedBox(height: S.x2 + S.hair),
          Text(
            'A behavior unlocks once you have $kBehaviorMinDays days where you '
            'did it and $kBehaviorMinDays where you didn’t.',
            style: F.dBody.copyWith(color: DC.ink3),
          ),
          const SizedBox(height: S.x5 + S.half),
          for (final b in locked)
            _LockedRow(b, onTap: () => _open(c, b, scale)),
        ],
        const SizedBox(height: S.x6),
        const Divider(height: S.hair, thickness: S.hair, color: DC.line),
        const SizedBox(height: S.x8 + S.x1 + S.hair),
        const _ExploreCard(),
      ],
    );
  }
}

class _SparkChip extends StatelessWidget {
  const _SparkChip();

  @override
  Widget build(BuildContext c) {
    return Container(
      width: S.x5 + S.half,
      height: S.x5 + S.half,
      decoration: const BoxDecoration(
          color: DC.sparkChip,
          borderRadius: BorderRadius.all(Radius.circular(S.x1))),
      child: const CustomPaint(painter: _SparkPaint()),
    );
  }
}

/// Two four-point stars, the mark of a behavior the app found for itself.
class _SparkPaint extends CustomPainter {
  const _SparkPaint();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = DC.line2;
    void star(Offset o, double r) {
      final k = r * .22;
      canvas.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - r)
            ..lineTo(o.dx + k, o.dy - k)
            ..lineTo(o.dx + r, o.dy)
            ..lineTo(o.dx + k, o.dy + k)
            ..lineTo(o.dx, o.dy + r)
            ..lineTo(o.dx - k, o.dy + k)
            ..lineTo(o.dx - r, o.dy)
            ..lineTo(o.dx - k, o.dy - k)
            ..close(),
          fill);
    }

    final c = size.center(Offset.zero);
    star(c + const Offset(-S.hair, S.hair), S.x1 + S.hair);
    star(c + const Offset(S.x1, -S.x1), S.x1 / 2 + S.hair * .5);
  }

  @override
  bool shouldRepaint(_SparkPaint old) => false;
}

class _ImpactHeader extends StatelessWidget {
  const _ImpactHeader();

  @override
  Widget build(BuildContext c) {
    Widget chip(Color bg, Color fg, bool up) => Container(
          width: S.x4 + S.hair,
          height: S.x4 + S.hair,
          decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.all(Radius.circular(S.x1))),
          alignment: Alignment.center,
          child: DeltaTriangle(up: up, color: fg, size: S.x2),
        );
    return Row(children: [
      chip(DC.hurtChip, C.poor, false),
      const SizedBox(width: S.x2 + S.hair),
      Expanded(
        child: Text('HURTS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: F.dLabel.copyWith(color: C.poor)),
      ),
      Expanded(
        child: Text('% IMPACT',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: F.dLabel.copyWith(color: DC.ink)),
      ),
      Expanded(
        child: Text('HELPS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: F.dLabel.copyWith(color: C.optimal)),
      ),
      const SizedBox(width: S.x2 + S.hair),
      chip(DC.helpChip, C.optimal, true),
    ]);
  }
}

String _impactText(double v) {
  final r = v.round();
  return r > 0 ? '+$r%' : '$r%';
}

Color _barColor(double v) => v.abs() < _strongImpact
    ? DC.stageAwake
    : (v > 0 ? C.optimal : C.poor);

Color _textColor(double v) => v.abs() < _strongImpact
    ? DC.ink2
    : (v > 0 ? C.optimal : C.poor);

/// The stripes with a dot at their middle and a bar out from it: [v] of [scale]
/// from the middle to the end. Null [v]: only the small dot.
class _ImpactBarPaint extends CustomPainter {
  final double? v;
  final double scale;
  const _ImpactBarPaint(this.v, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    paintHatch(canvas, Offset.zero & size, radius: S.half);
    final mid = Offset(size.width / 2, size.height / 2);
    final x = v;
    if (x == null) {
      canvas.drawCircle(mid, S.half + S.hair * .5, Paint()..color = DC.ink);
      return;
    }
    final reach = size.width / 2 * (x.abs() / scale).clamp(0.0, 1.0);
    final box = x >= 0
        ? Rect.fromLTWH(mid.dx, 0, reach, size.height)
        : Rect.fromLTWH(mid.dx - reach, 0, reach, size.height);
    canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(S.x1)),
        Paint()..color = _barColor(x));
    canvas.drawCircle(mid, S.x1 + S.hair, Paint()..color = DC.well);
    canvas.drawCircle(mid, S.hair + S.hair * .5, Paint()..color = DC.ink);
  }

  @override
  bool shouldRepaint(_ImpactBarPaint old) => old.v != v || old.scale != scale;
}

class _ImpactRow extends StatelessWidget {
  final BehaviorImpact b;
  final double scale;
  final VoidCallback onTap;
  const _ImpactRow(this.b, {required this.scale, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final v = b.impact!;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x2 + S.hair),
      child: Pressable(
        onTap: onTap,
        semanticLabel: '${b.title}: ${_impactText(v)} Recovery',
        child: Container(
          constraints:
              const BoxConstraints(minHeight: S.x16 + S.x3 + S.hair + S.hair),
          padding: const EdgeInsets.fromLTRB(S.x3 + S.half, S.x4, S.x3, 0),
          decoration: const BoxDecoration(
              color: DC.weekCard, borderRadius: R.rLg),
          child: Column(children: [
            SizedBox(
              height: S.x5,
              child: Row(children: [
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text(b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: F.dBody.copyWith(color: DC.ink)),
                    ),
                    if (b.auto) ...[
                      const SizedBox(width: S.x2 + S.hair),
                      const _SparkChip(),
                    ],
                  ]),
                ),
                const Icon(LucideIcons.chevronRight, size: I.md, color: DC.ink2),
              ]),
            ),
            const SizedBox(height: S.x3),
            Row(children: [
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, S.x2 + S.half),
                  painter: _ImpactBarPaint(v, scale),
                ),
              ),
              SizedBox(
                width: S.x10 + S.x1,
                child: Text(_impactText(v),
                    textAlign: TextAlign.right,
                    style: F.nWeek.copyWith(color: _textColor(v))),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _LockedRow extends StatelessWidget {
  final BehaviorImpact b;
  final VoidCallback onTap;
  const _LockedRow(this.b, {required this.onTap});

  @override
  Widget build(BuildContext c) {
    Widget box(IconData icon, int n) {
      final done = n >= kBehaviorMinDays;
      final color = done ? DC.ink : DC.ink3;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: I.md, color: color),
        const SizedBox(width: S.x1),
        Text('$n', style: F.nTiny.copyWith(color: color)),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Pressable(
        onTap: onTap,
        semanticLabel:
            '${b.title}: ${b.no} days without, ${b.yes} with. Not enough to compare.',
        child: Container(
          constraints: const BoxConstraints(minHeight: S.x16 + S.x1 + S.half),
          padding: const EdgeInsets.fromLTRB(S.x3 + S.half, S.x3, S.x3, 0),
          decoration: BoxDecoration(
            borderRadius: R.rLg,
            border: Border.all(color: DC.edge, width: S.half * .75),
          ),
          child: Column(children: [
            SizedBox(
              height: S.x5,
              child: Row(children: [
                Expanded(
                  child: Text(b.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.dBody.copyWith(color: DC.ink)),
                ),
                const Icon(LucideIcons.chevronRight, size: I.md, color: DC.ink2),
              ]),
            ),
            const SizedBox(height: S.x2 - S.hair),
            Row(children: [
              const Expanded(
                child: CustomPaint(
                  size: Size(double.infinity, S.x2 + S.half),
                  painter: _ImpactBarPaint(null, 1),
                ),
              ),
              const SizedBox(width: S.x3),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    box(LucideIcons.squareX, b.no),
                    const SizedBox(width: S.x2 + S.hair),
                    box(LucideIcons.squareCheck, b.yes),
                  ]),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard();

  @override
  Widget build(BuildContext c) {
    return Container(
      constraints: const BoxConstraints(minHeight: S.x16 * 2 + S.x6 + S.x1 + S.half),
      padding: const EdgeInsets.fromLTRB(S.x6 - S.hair, S.x6 + S.x1, S.x4, 0),
      decoration: dialCard(),
      child: Stack(children: [
        const Positioned(
          right: 0,
          top: 0,
          child: CustomPaint(
            size: Size(S.x16 + S.x8 + S.half + S.hair, S.x16 + S.x8 + S.x1 + S.hair),
            painter: _NotebookPaint(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: S.x16 + S.x12 + S.x2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Explore more behaviors',
                style: F.dBody.copyWith(color: DC.ink)),
            const SizedBox(height: S.x2 - S.hair),
            Text(
              'Tag your days in the journal and see what each one does to your '
              'Recovery.',
              style: F.dText.copyWith(color: DC.ink2),
            ),
            // Its tap target reaches up over the text's last line.
            Transform.translate(
              offset: const Offset(0, -S.x1 - S.half),
              child: Pressable(
                onTap: () => go(c, const JournalCompose()),
                semanticLabel: 'Open journal',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('OPEN JOURNAL',
                      style: F.dLabel.copyWith(color: DC.line2)),
                  const SizedBox(width: S.x2),
                  const Icon(LucideIcons.arrowRight, size: I.md, color: DC.line2),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// A notebook lying on a slant, its ribbon hanging out of the foot.
class _NotebookPaint extends CustomPainter {
  const _NotebookPaint();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset at(double x, double y) => Offset(w * x, h * y);
    Path quad(Offset a, Offset b, Offset c, Offset d) => Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
    Paint soft(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.fill
      ..strokeJoin = StrokeJoin.round;
    Paint round(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = S.x1
      ..strokeJoin = StrokeJoin.round;

    // The pages, showing along the foot and the right.
    final pages = quad(at(.03, .84), at(.62, 1), at(1, .22), at(.97, .16));
    canvas.drawPath(pages, soft(DC.journalEdge));
    canvas.drawPath(pages, round(DC.journalEdge));

    // The cover and its spine.
    final cover = quad(at(.36, .03), at(.96, .16), at(.58, .92), at(.03, .77));
    canvas.drawPath(cover, soft(DC.journalBody));
    canvas.drawPath(cover, round(DC.journalBody));
    canvas.drawLine(at(.33, .1), at(.08, .78),
        Paint()
          ..color = DC.journalEdge
          ..strokeWidth = S.hair);

    // The strap.
    canvas.drawLine(at(.72, .42), at(.96, .47), round(DC.journalEdge));

    // The ribbon.
    canvas.drawPath(quad(at(.08, .84), at(.2, .87), at(.15, 1), at(.05, .98)),
        soft(DC.line2));
  }

  @override
  bool shouldRepaint(_NotebookPaint old) => false;
}

// ── Behavior Details ────────────────────────────────────────────────────────

/// Own-words background and advice for each behavior.
(String, String) _copyOf(BehaviorImpact b) => switch (b.kind) {
      BehaviorKind.sleepPerformance => (
        'Sleep is when your body does most of its repair, so getting the sleep '
            'you need tends to show up in how ready you are the next morning. '
            'This compares mornings after nights at or above your own typical '
            'performance with mornings after nights below it.',
        'Give yourself enough time in bed for what your Sleep Need says, keep '
            'bed and wake times steady, and leave heavy meals, alcohol and '
            'bright screens for earlier in the evening.',
      ),
      BehaviorKind.consistentBed => (
        'Your body clock prepares you for sleep at about the same time each '
            'evening, and it works best with a schedule it can predict. This '
            'compares nights within ${kConsistentWithinMin.round()} minutes of '
            'your usual bed time with nights further from it.',
        'Pick a bed time you can keep on most nights, weekends included, and '
            'start winding down half an hour ahead of it.',
      ),
      BehaviorKind.consistentWake => (
        'A steady wake time anchors the rest of your day, from when you get '
            'hungry to when you get sleepy. This compares mornings within '
            '${kConsistentWithinMin.round()} minutes of your usual wake time '
            'with mornings further from it.',
        'Set one wake time and keep it, even after a late night. A short nap '
            'makes up for lost sleep better than a long lie-in does.',
      ),
      BehaviorKind.earlyWorkout => (
        'When you train changes how your body winds down that night. This '
            'compares mornings after a day with a workout starting before '
            '$kEarlyWorkoutHour:00 with mornings after a day without one.',
        'If a morning session suits you, keep it regular and eat and sleep '
            'enough to support it. If your numbers dip after it, try moving it '
            'later for a couple of weeks and compare.',
      ),
      BehaviorKind.highStress => (
        'Long stretches with your heart working harder than usual, outside '
            'exercise, are still load your body has to recover from. This '
            'compares mornings after a day with ${kHighStressDayPct.round()}% '
            'or more of it in the high stress zone with mornings after calmer '
            'days.',
        'On a heavy day, break it up with a walk or a few minutes of slow '
            'breathing, and protect that night’s sleep.',
      ),
      BehaviorKind.highStrain => (
        'A hard day asks more of your body overnight, and it can take more than '
            'one night to absorb. This compares mornings after a strain of '
            '${kHardStrain.round()} or more with mornings after an easier day.',
        'Hard days are how you get fitter, so the aim is not to avoid them. '
            'Plan extra sleep after one, and follow it with an easier day when '
            'Recovery is low.',
      ),
      BehaviorKind.journalTag => (
        'This compares your Recovery on the mornings this could have touched '
            'with the same mornings when you logged a day without it.',
        'Keep logging it, along with the days you don’t do it. The more of '
            'both you have, the steadier this comparison gets.',
      ),
    };

class BehaviorDetailsScreen extends StatelessWidget {
  final BehaviorImpact behavior;
  final double scale;
  const BehaviorDetailsScreen(
      {super.key, required this.behavior, required this.scale});

  @override
  Widget build(BuildContext c) {
    final b = behavior;
    final v = b.impact;
    final (about, advice) = _copyOf(b);
    final numbers = v == null
        ? 'So far: ${b.yes} days with it and ${b.no} without. It needs '
            '$kBehaviorMinDays of each before they are compared.'
        : 'Your Recovery averaged ${b.meanYes!.round()}% across ${b.yes} days '
            'with it and ${b.meanNo!.round()}% across ${b.no} days without. '
            'That is a pattern in your own days, not proof of cause.';
    return DialScaffold(
      title: 'Behavior Details',
      backdrop: const Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: S.x16 * 5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.1,
              colors: [DC.heroGlow, Color(0x00000000)],
            ),
          ),
        ),
      ),
      children: [
        const SizedBox(height: S.x6),
        Text(b.title, style: F.dHead.copyWith(color: DC.ink)),
        const SizedBox(height: S.x4 + S.hair),
        Container(
          padding: const EdgeInsets.fromLTRB(S.x4 + S.half, S.x5 + S.hair, S.x4 + S.half, S.x5),
          decoration: dialCard(DC.weekCard),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('RECOVERY IMPACT',
                    style: F.dNav.copyWith(color: DC.ink)),
              ),
              if (v != null && v != 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: S.x2, vertical: S.half),
                  decoration: BoxDecoration(
                      color: v > 0 ? DC.helpChip : DC.hurtChip,
                      borderRadius: R.rSm),
                  child: Text(v > 0 ? 'Positive' : 'Negative',
                      style: F.dTiny.copyWith(
                          color: v > 0 ? C.optimal : C.poor,
                          fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: S.x4 + S.half),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, S.x2 + S.half),
                  // Half as far as on the list: this bar has its figure to say
                  // how big it is.
                  painter: _ImpactBarPaint(v, scale * 2.2),
                ),
              ),
              const SizedBox(width: S.x4),
              if (v == null)
                Text('--', style: F.nImpact.copyWith(color: DC.ink2))
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(_impactText(v).replaceAll('%', ''),
                        style: F.nImpact.copyWith(color: _textColor(v))),
                    Text('%', style: F.nSmall.copyWith(color: _textColor(v))),
                  ],
                ),
            ]),
          ]),
        ),
        const SizedBox(height: S.x8 - S.hair),
        Text('Impact of ${b.title}', style: F.dTitle.copyWith(color: DC.ink)),
        const SizedBox(height: S.x2 + S.hair),
        Text('$about $numbers', style: F.dText.copyWith(color: DC.body)),
        const SizedBox(height: S.x5 + S.x1),
        Container(
          padding: const EdgeInsets.fromLTRB(
              S.x4 + S.half, S.x4 + S.half, S.x4 + S.half, S.x6),
          decoration: const BoxDecoration(
            borderRadius: R.rXxl,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [DC.adviceTop, DC.adviceFoot],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const StatIcon(StatMark.bulb, color: DC.line2, size: S.x6),
              const SizedBox(width: S.x2),
              Text('RECOMMENDATION',
                  style: F.dBody.copyWith(color: DC.line2)),
            ]),
            const SizedBox(height: S.x4),
            Text(advice, style: F.dBody.copyWith(color: DC.ink)),
          ]),
        ),
      ],
    );
  }
}
