// Calibration: the first two weeks, while Locus learns what normal looks like
// for you. Each metric that is read against your own baseline unlocks when
// its own count is reached, never earlier, and never by a promise:
//
//   Sleep           after the first night
//   Strain          from day 4 (`quietHrrMinDays` + 1)
//   Stress monitor  three days with quiet, awake heart rate and HRV
//   Recovery        14 nights of baseline (`readinessCompositeMinBaseline`)
//   Health monitor  14 nights of vitals (`kWhoopMonitorMinNights`)
//
// What is here: the model ([Calibration], [Milestone]), the segmented bar
// every count is drawn with, the "N more nights to calibrate" strip, Home's
// timeline card, and the milestones screen it opens. The onboarding page
// that explains it all is `onboarding/what_to_expect.dart`.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openstrap_analytics/onehz.dart'
    show quietHrrMinDays, readinessCompositeMinBaseline;

import '../../compute/stress_monitor.dart' show kStressBaselineDays;
import '../../compute/whoop_scores.dart' show kWhoopMonitorMinNights;
import '../activity/day_strain.dart' show DayStrainDetail;
import '../onboarding/what_to_expect.dart' show WhatToExpectScreen;
import '../ui2.dart';
import 'health_monitor.dart' show HealthMonitorScreen;
import 'home/home_cards.dart' show HomeSwipeAway;
import 'readiness_detail.dart' show ReadinessDetail;
import 'sleep_detail.dart' show SleepDetail;
import 'stress_monitor.dart' show StressMonitorScreen;

/// One metric on its way to being unlocked.
class Milestone {
  final String title, about;
  final IconData icon;

  /// What it needs ([need] nights, or days when [days]) and how far along it is.
  final int need, have;
  final bool days, done;

  /// Where VIEW DETAILS goes once it is unlocked.
  final Widget Function()? open;

  const Milestone({
    required this.title,
    required this.about,
    required this.icon,
    required this.need,
    required this.have,
    required this.done,
    this.days = false,
    this.open,
  });

  /// Segments to fill: every one once it is unlocked, never every one before,
  /// so a count that has caught up while the metric still abstains does not
  /// read as unlocked.
  int get filled => done ? need : have.clamp(0, need - 1);

  int get left => need - filled;

  String get toUnlock => days
      ? 'Wear the band $need ${need == 1 ? 'day' : 'days'} to unlock'
      : 'Log $need ${need == 1 ? 'sleep' : 'sleeps'} to unlock';

  /// The calibrating strip's line.
  String get toGo => days
      ? 'Wear the band for $left more ${left == 1 ? 'day' : 'days'} to calibrate'
      : 'Wear the band to sleep for $left more '
          '${left == 1 ? 'night' : 'nights'} to calibrate';
}

/// Where the first two weeks stand.
class Calibration {
  /// Sleeps logged toward the recovery baseline.
  final int nights;

  /// Days the band has recorded.
  final int days;

  /// Usable stress-baseline days, when the stress monitor has been read.
  final int? stressDays;

  final bool slept, strain, stress, recovery, health;

  const Calibration({
    required this.nights,
    required this.days,
    this.stressDays,
    this.slept = false,
    this.strain = false,
    this.stress = false,
    this.recovery = false,
    this.health = false,
  });

  /// The length of the timeline: the longest baseline, recovery's.
  static const int total = readinessCompositeMinBaseline;

  /// From what Home holds. [baselineNights] is the recovery note's own
  /// count (`need_baseline:have=H`); without one, recorded days stand in.
  /// A metric that is not on screen today (no strain yet this morning) is
  /// still unlocked once its count is past: the count is the gate.
  factory Calibration.of({
    required int days,
    int? baselineNights,
    bool sleep = false,
    bool strain = false,
    bool? stress,
    int? stressDays,
    bool recovery = false,
    bool health = false,
  }) {
    final rec = recovery || (baselineNights == null && days > total);
    final nights =
        rec ? math.max(days, total) : (baselineNights ?? days).clamp(0, total);
    return Calibration(
      nights: nights,
      days: days,
      stressDays: stressDays,
      slept: sleep || days > 0,
      strain: strain || days > quietHrrMinDays,
      stress: stress ?? days > kStressBaselineDays,
      recovery: rec,
      health: health || nights >= kWhoopMonitorMinNights,
    );
  }

  List<Milestone> get milestones => [
        Milestone(
          title: 'Sleep',
          about: 'How long and how well you slept, stage by stage, and how '
              'much sleep you need tonight.',
          icon: LucideIcons.moon,
          need: 1,
          have: nights,
          done: slept,
          open: () => const SleepDetail(),
        ),
        Milestone(
          title: 'Strain',
          about: 'How hard each day was on your heart, from 0 to 21, against '
              'your own quiet heart rate.',
          icon: LucideIcons.zap,
          need: quietHrrMinDays + 1,
          have: days,
          days: true,
          done: strain,
          open: () => const DayStrainDetail(),
        ),
        Milestone(
          title: 'Stress monitor',
          about: 'Your stress through the day, read against your own quiet, '
              'awake heart rate and HRV.',
          icon: LucideIcons.brain,
          need: kStressBaselineDays,
          have: stressDays ?? days,
          days: true,
          done: stress,
          open: () => const StressMonitorScreen(),
        ),
        Milestone(
          title: 'Recovery',
          about: 'How ready your body is each morning, from your sleep, '
              'resting heart rate and HRV against your own normal.',
          icon: LucideIcons.batteryCharging,
          need: total,
          have: nights,
          done: recovery,
          open: () => const ReadinessDetail(),
        ),
        Milestone(
          title: 'Health monitor',
          about: 'Your overnight vitals, each held against the range that is '
              'usual for you.',
          icon: LucideIcons.heartPulse,
          need: kWhoopMonitorMinNights,
          have: nights,
          done: health,
          open: () => const HealthMonitorScreen(),
        ),
      ];

  /// Every milestone unlocked: the timeline has nothing left to show.
  bool get complete => milestones.every((m) => m.done);
}

/// [count] segments, the first [filled] in the calibration colour. Each is at
/// most [S.x6] wide, so a short count stays short and a long one fits.
class SegmentBar extends StatelessWidget {
  final int count, filled;
  const SegmentBar({super.key, required this.count, required this.filled});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Semantics(
      label: '$filled of $count',
      excludeSemantics: true,
      // Flexible, not a LayoutBuilder: Home's monitor row measures its
      // intrinsic height, which a LayoutBuilder cannot answer.
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: S.x1),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: S.x6),
              height: S.x1,
              decoration: BoxDecoration(
                color: i < filled ? C.calibrate : p.ink.withValues(alpha: .2),
                borderRadius: R.rPill,
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// "Wear the band to sleep for 3 more nights to calibrate", over its
/// segments, on a recessed panel: the foot of a card still calibrating.
class CalibrationStrip extends StatelessWidget {
  final Milestone milestone;
  const CalibrationStrip(this.milestone, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final m = milestone;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(S.x3),
      decoration: BoxDecoration(color: p.bg, borderRadius: R.rMd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.toGo, style: F.cap.copyWith(color: p.ink)),
        const SizedBox(height: S.x2),
        SegmentBar(count: m.need, filled: m.filled),
      ]),
    );
  }
}

/// The ring on Home's timeline card: nights logged out of [total].
class CalibrationRing extends StatelessWidget {
  final int nights, total;
  const CalibrationRing({super.key, required this.nights, required this.total});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Semantics(
      label: '$nights of $total nights',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: S.x12,
        child: CustomPaint(
          painter: _RingPainter(nights / total, p.ink.withValues(alpha: .12)),
          child: Center(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$nights', style: F.n17.copyWith(color: p.ink)),
              TextSpan(
                  text: '/$total',
                  style: F.num(F.over).copyWith(color: p.ink3)),
            ])),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double frac;
  final Color track;
  const _RingPainter(this.frac, this.track);

  @override
  void paint(Canvas canvas, Size s) {
    const w = S.x1;
    final r = Rect.fromLTWH(w / 2, w / 2, s.width - w, s.height - w);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, paint);
    if (frac <= 0) return;
    canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * frac.clamp(0.0, 1.0),
        false,
        paint
          ..color = C.calibrate
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.frac != frac || o.track != track;
}

/// Home's "Calibration timeline" card, while anything is still locked. Opens
/// the milestones; swiped away, it stays gone for the rest of the day.
class CalibrationCard extends StatelessWidget {
  final Calibration cal;
  const CalibrationCard(this.cal, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return HomeSwipeAway(
      child: Surface(
        pad: const EdgeInsets.all(S.x4),
        semanticLabel: 'Calibration timeline, ${cal.nights} of '
            '${Calibration.total} nights. Open your milestones',
        onTap: () => Navigator.of(c).push(MaterialPageRoute<void>(
            builder: (_) => MilestonesScreen(cal))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('CALIBRATION TIMELINE',
                  style:
                      F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
            ),
            BoldChevron(left: false, color: p.ink3, height: S.x3),
          ]),
          const SizedBox(height: S.x2),
          Row(children: [
            Expanded(
              child: Text(
                  'Wear the band to bed every night and check back here to '
                  'follow your sleeps and what they unlock.',
                  style: F.cap.copyWith(color: p.ink2)),
            ),
            const SizedBox(width: S.x4),
            CalibrationRing(nights: cal.nights, total: Calibration.total),
          ]),
        ]),
      ),
    );
  }
}

/// The milestones: sleeps logged so far, and each metric with what it still
/// needs. Opened from Home's timeline card.
class MilestonesScreen extends StatelessWidget {
  final Calibration cal;
  const MilestonesScreen(this.cal, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final glow = Color.alphaBlend(
        C.calibrate.withValues(alpha: p.dark ? .22 : .12), p.bg);
    return Scaffold(
      backgroundColor: p.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, -.2),
            colors: [glow, p.bg],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Row(children: [
              Pressable(
                semanticLabel: 'Close',
                onTap: () => Navigator.of(c).pop(),
                child: SizedBox.square(
                  dimension: S.tap + S.x2,
                  child: Icon(LucideIcons.x, size: I.lg, color: p.ink),
                ),
              ),
              Expanded(
                child: Text('YOUR FIRST TWO WEEKS',
                    textAlign: TextAlign.center,
                    style: F.caps.copyWith(color: p.ink, letterSpacing: 1.3)),
              ),
              const SizedBox(width: S.tap + S.x2),
            ]),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    S.gutter, S.x4, S.gutter, S.x16 + S.x8),
                children: [
                  Text('Unlock key milestones',
                      style: F.t2.copyWith(color: p.ink)),
                  const SizedBox(height: S.x2),
                  Text(
                      'Every night counts. Wear the band to sleep and Locus '
                      'learns your normal, one metric at a time.',
                      style: F.body.copyWith(color: p.ink2)),
                  const SizedBox(height: S.x6),
                  Row(children: [
                    Text(
                        'SLEEPS LOGGED ${math.min(cal.nights, Calibration.total)}'
                        '/${Calibration.total}',
                        style: F.num(F.over)
                            .copyWith(color: p.ink3, letterSpacing: 1.0)),
                    const SizedBox(width: S.x3),
                    Expanded(child: Container(height: S.hair, color: p.line)),
                  ]),
                  const SizedBox(height: S.x4),
                  NightPips(nights: cal.nights, total: Calibration.total),
                  const SizedBox(height: S.x8),
                  Text('Your key milestones',
                      style: F.head.copyWith(
                          color: p.ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: S.x3),
                  for (final m in cal.milestones) ...[
                    MilestoneCard(m),
                    const SizedBox(height: S.x3),
                  ],
                  const SizedBox(height: S.x2),
                  Center(
                    child: TextAction(
                      'How calibration works',
                      () => Navigator.of(c).push(MaterialPageRoute<void>(
                          builder: (_) =>
                              WhatToExpectScreen(nights: cal.nights))),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One numbered pip per night, seven to a row; the nights logged ringed in
/// the calibration colour.
class NightPips extends StatelessWidget {
  final int nights, total;
  const NightPips({super.key, required this.nights, required this.total});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget pip(int n) {
      final on = n <= nights;
      return Container(
        width: S.x8,
        height: S.x8,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? C.calibrate.withValues(alpha: .18) : null,
          border: Border.all(
              color: on ? C.calibrate : p.ink.withValues(alpha: .22),
              width: on ? S.half : S.hair * 1.5),
        ),
        child: Text('$n',
            style: F.num(F.cap).copyWith(
                color: on ? p.ink : p.ink3, fontWeight: FontWeight.w700)),
      );
    }

    return Semantics(
      label: '$nights of $total nights logged',
      excludeSemantics: true,
      child: Column(children: [
        for (var row = 0; row * 7 < total; row++) ...[
          if (row > 0) const SizedBox(height: S.x3),
          Row(children: [
            for (var i = row * 7; i < math.min(total, row * 7 + 7); i++) ...[
              if (i > row * 7) const SizedBox(width: S.x3),
              pip(i + 1),
            ],
          ]),
        ],
      ]),
    );
  }
}

/// A milestone: unlocked, a card with the way in; locked, an outline with
/// what it still needs and its segments.
class MilestoneCard extends StatelessWidget {
  final Milestone m;
  const MilestoneCard(this.m, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final open = m.open;
    final tile = Container(
      width: S.x12 + S.x2,
      height: S.x12 + S.x2,
      decoration: BoxDecoration(
        color: m.done ? p.card2 : p.ink.withValues(alpha: .05),
        borderRadius: R.rMd,
      ),
      child: Icon(m.icon, size: I.lg, color: m.done ? p.ink : p.ink3),
    );
    final link = p.on(C.calibrate);
    final words = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(m.title,
          style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
      const SizedBox(height: S.half),
      if (m.done) ...[
        Text(m.about, style: F.cap.copyWith(color: p.ink2)),
        if (open != null) ...[
          const SizedBox(height: S.x2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text('VIEW DETAILS',
                  style: F.caps.copyWith(color: link, letterSpacing: 1.0)),
            ),
            const SizedBox(width: S.x1),
            Icon(LucideIcons.arrowRight, size: I.sm, color: link),
          ]),
        ],
      ] else ...[
        Text(m.toUnlock, style: F.cap.copyWith(color: p.ink2)),
        const SizedBox(height: S.x2),
        SegmentBar(count: m.need, filled: m.filled),
      ],
    ]);
    final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      tile,
      const SizedBox(width: S.x4),
      Expanded(child: words),
      if (!m.done)
        Pressable(
          semanticLabel: 'About ${m.title.toLowerCase()}',
          onTap: () => AppSheet.show<void>(c,
              title: m.title,
              child: Text(
                  '${m.about}\n\nIt unlocks once Locus has '
                  '${m.need} ${m.days ? (m.need == 1 ? 'day' : 'days') : (m.need == 1 ? 'night' : 'nights')} '
                  'of yours to compare with, so the number is yours and not '
                  'a guess.',
                  style: F.body.copyWith(color: p.ink2))),
          child: SizedBox(
            width: S.x8,
            height: S.x8,
            child: Align(
              alignment: Alignment.topRight,
              child: Icon(LucideIcons.info, size: I.sm, color: p.ink3),
            ),
          ),
        ),
    ]);
    if (m.done) {
      return Surface(
        pad: const EdgeInsets.all(S.x4),
        semanticLabel: '${m.title}, unlocked. View details',
        onTap: open == null
            ? null
            : () => Navigator.of(c)
                .push(MaterialPageRoute<void>(builder: (_) => open())),
        child: row,
      );
    }
    return Container(
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(
        borderRadius: R.rXl,
        border: Border.all(color: p.ink.withValues(alpha: .14)),
      ),
      child: row,
    );
  }
}
