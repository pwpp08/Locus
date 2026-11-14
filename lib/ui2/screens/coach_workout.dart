// The workouts the coach proposes, as cards in the chat, and the one the
// person committed to, as a card on Home with a Start button.

import 'package:flutter/material.dart';

import '../../coach/workout_plan.dart';
import '../activity/catalogue.dart';
import '../ui2.dart';
import 'coach_parts.dart';

const _zoneInk = [
  C.refZone1,
  C.refZone2,
  C.refZone3,
  C.refZone4,
  C.refZone5,
];

/// The estimate as the cards write it: one decimal, or a dash with none.
String planStrainText(double? strain) =>
    strain == null ? '–' : strain.toStringAsFixed(1);

IconData _iconFor(String sport) =>
    activityByName(sport)?.icon ?? LucideIcons.activity;

/// The zones a plan spends time in, as a bar in proportion and the minutes
/// under it.
class PlanZones extends StatelessWidget {
  final List<double> zoneMin;
  final bool dark;
  const PlanZones(this.zoneMin, {super.key, this.dark = true});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final used = [
      for (var z = 0; z < 5; z++)
        if (zoneMin[z] > 0) z,
    ];
    final ink = dark ? C.white : p.ink;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (final z in used)
          Expanded(
            flex: (zoneMin[z] * 10).round().clamp(1, 100000),
            child: Container(
              height: S.x1 + S.half,
              margin: const EdgeInsets.symmetric(horizontal: S.half / 2),
              decoration: BoxDecoration(
                  color: _zoneInk[z], borderRadius: R.rPill),
            ),
          ),
      ]),
      const SizedBox(height: S.x2),
      Row(children: [
        for (final z in used)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Zone ${z + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.cap.copyWith(color: _zoneInk[z])),
                Text('${zoneMin[z].round()} min',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.cap.copyWith(color: ink)),
              ],
            ),
          ),
      ]),
    ]);
  }
}

/// One proposed workout: the sport, how long, the app's strain estimate, the
/// zone targets, and Commit.
class CoachWorkoutCard extends StatelessWidget {
  final WorkoutPlan plan;
  final bool committed;
  final VoidCallback? onCommit;
  const CoachWorkoutCard(this.plan,
      {super.key, this.committed = false, this.onCommit});

  @override
  Widget build(BuildContext c) {
    Widget fact(String label, String value) => Text.rich(TextSpan(children: [
          TextSpan(
              text: '$label  ',
              style: F.body.copyWith(
                  color: C.white.withValues(alpha: .65),
                  fontWeight: FontWeight.w500)),
          TextSpan(text: value, style: F.body.copyWith(color: C.white)),
        ]));
    return CoachCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_iconFor(plan.sport), size: I.lg, color: C.white),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(plan.sport,
                style: F.head.copyWith(color: C.white)),
          ),
        ]),
        const SizedBox(height: S.x3),
        Wrap(spacing: S.x5, runSpacing: S.x1, children: [
          fact('Duration', '${plan.durationMin} min'),
          fact('Estimated strain', planStrainText(plan.strain)),
        ]),
        const SizedBox(height: S.x4),
        Text('HR zone targets',
            style: F.cap.copyWith(color: C.white.withValues(alpha: .65))),
        const SizedBox(height: S.x2),
        PlanZones(plan.zoneMin),
        const SizedBox(height: S.x4),
        CoachGoButton(committed ? 'Committed' : 'Commit',
            done: committed, onTap: onCommit),
      ]),
    );
  }
}

/// Up to three proposals, one at a time with dots to move between them, and
/// a way to ask for different ones.
class CoachWorkoutOptions extends StatefulWidget {
  final List<WorkoutPlan> plans;

  /// The plan already committed, to mark its card.
  final WorkoutPlan? committed;
  final ValueChanged<WorkoutPlan> onCommit;

  /// Ask the coach for other options; null hides it.
  final VoidCallback? onAlternatives;

  const CoachWorkoutOptions({
    super.key,
    required this.plans,
    required this.onCommit,
    this.committed,
    this.onAlternatives,
  });

  @override
  State<CoachWorkoutOptions> createState() => _CoachWorkoutOptionsState();
}

class _CoachWorkoutOptionsState extends State<CoachWorkoutOptions> {
  int _i = 0;

  @override
  Widget build(BuildContext c) {
    final plans = widget.plans;
    if (plans.isEmpty) return const SizedBox.shrink();
    final i = _i.clamp(0, plans.length - 1);
    final plan = plans[i];
    final done = widget.committed != null && widget.committed!.sameAs(plan);
    return Column(children: [
      AnimatedSwitcher(
        duration: motion(c, Motion.fast),
        child: CoachWorkoutCard(
          plan,
          key: ValueKey(i),
          committed: done,
          onCommit: () => widget.onCommit(plan),
        ),
      ),
      if (plans.length > 1)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 0; k < plans.length; k++)
            Pressable(
              onTap: () => setState(() => _i = k),
              semanticLabel: 'Option ${k + 1} of ${plans.length}',
              child: SizedBox(
                width: S.x6,
                height: S.tap,
                child: Center(
                  child: Container(
                    width: S.x2,
                    height: S.x2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.white.withValues(alpha: k == i ? 1 : .3),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      if (widget.onAlternatives != null)
        Pressable(
          onTap: widget.onAlternatives,
          semanticLabel: 'Generate alternatives',
          child: SizedBox(
            height: S.tap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(LucideIcons.refreshCw, size: I.sm, color: C.white),
              const SizedBox(width: S.x2),
              Flexible(
                child: Text('GENERATE ALTERNATIVES',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.cap.copyWith(
                        color: C.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5)),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Home's card for the workout committed for today: what, how long, the
/// zones, Start, and a cross to drop it.
class TodayPlanCard extends StatelessWidget {
  final WorkoutPlan plan;
  final VoidCallback onStart;
  final VoidCallback onDrop;
  const TodayPlanCard(this.plan,
      {super.key, required this.onStart, required this.onDrop});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      pad: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x1, S.x4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text("TODAY'S PLAN",
                style: F.over.copyWith(color: p.ink3)),
          ),
          Pressable(
            onTap: onDrop,
            semanticLabel: "Drop today's plan",
            child: SizedBox.square(
              dimension: S.tap,
              child: Icon(LucideIcons.x, size: I.sm, color: p.ink3),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: S.x3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_iconFor(plan.sport), size: I.md, color: p.ink),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                    '${plan.sport} · ${plan.durationMin} min'
                    '${plan.strain == null ? '' : ' · strain ${planStrainText(plan.strain)}'}',
                    style: F.head.copyWith(color: p.ink)),
              ),
            ]),
            const SizedBox(height: S.x3),
            PlanZones(plan.zoneMin, dark: false),
            const SizedBox(height: S.x4),
            BigButton('Start', icon: LucideIcons.play, onTap: onStart),
          ]),
        ),
      ]),
    );
  }
}
