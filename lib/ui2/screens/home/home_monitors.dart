import 'package:flutter/material.dart';

import '../../../compute/stress_monitor.dart' show StressLevel, stressLevel;
import '../../grammar.dart' show Surface;
import '../../marks.dart' show BoldChevron;
import '../../theme.dart' show C, F, I, P, R, S;
import '../../ui2.dart' show LucideIcons;
import '../health_monitor.dart' show HealthGlance;
import '../stress_monitor.dart' show StressMonitorData;

class HomeMonitors extends StatelessWidget {
  final HealthGlance? health;
  final StressMonitorData? stress;
  final VoidCallback onHealth, onStress;

  const HomeMonitors({
    super.key,
    required this.health,
    required this.stress,
    required this.onHealth,
    required this.onStress,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);

    Widget card(String title, String semantic, VoidCallback onTap, Widget tile,
            String word, Color wordColor, String sub) =>
        Expanded(
          child: Surface(
            onTap: onTap,
            semanticLabel: semantic,
            pad: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x3, S.x4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(title,
                        maxLines: 1,
                        style: F.caps.copyWith(
                            color: p.ink, fontWeight: FontWeight.w800)),
                  ),
                ),
                BoldChevron(left: false, color: p.ink3, height: S.x3),
              ]),
              const SizedBox(height: S.x5),
              Row(children: [
                tile,
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(word,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.caps.copyWith(
                            color: wordColor, fontWeight: FontWeight.w800)),
                    const SizedBox(height: S.half),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.num(F.cap).copyWith(
                            color: p.ink2, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ]),
          ),
        );

    Widget square(Color colour, Widget child) => Container(
          width: S.x10,
          height: S.x10,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colour.withValues(alpha: .2),
            borderRadius: R.rMd,
          ),
          child: child,
        );

    final h = health;
    final allIn = h != null && h.inside == h.total;
    final hColour = h == null ? p.ink3 : (allIn ? C.stressMedium : C.stressHigh);
    final d = stress;
    final last = d?.last;
    final score = last == null ? null : d!.scores[last];
    final level = score == null ? null : stressLevel(score);
    final sColour = switch (level) {
      StressLevel.low => C.stressLow,
      StressLevel.medium => C.stressMedium,
      StressLevel.high => C.stressHigh,
      null => p.ink3,
    };
    String at(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          card(
            'HEALTH MONITOR',
            h == null
                ? 'Health monitor. No data'
                : 'Health monitor. ${h.inside} of ${h.total} metrics within range',
            onHealth,
            square(hColour,
                Icon(h == null ? LucideIcons.minus : (allIn ? LucideIcons.check : LucideIcons.triangleAlert),
                    size: I.md, color: hColour)),
            h == null ? 'NO DATA' : (allIn ? 'WITHIN RANGE' : 'OUT OF RANGE'),
            hColour,
            h == null ? 'Needs a night' : '${h.inside}/${h.total} Metrics',
          ),
          const SizedBox(width: S.x3),
          card(
            'STRESS MONITOR',
            score == null
                ? 'Stress monitor. No reading'
                : 'Stress monitor. ${score.toStringAsFixed(1)} of 3, ${level!.name}',
            onStress,
            square(
                sColour,
                Text(score == null ? '--' : score.toStringAsFixed(1),
                    style: F.n17.copyWith(
                        color: sColour, fontWeight: FontWeight.w700))),
            level == null
                ? (d != null && d.baseline == null ? 'BUILDING' : 'NO READING')
                : level.name.toUpperCase(),
            sColour,
            last == null
                ? (d != null && d.baseline == null ? 'Your baseline' : '')
                : at(last),
          ),
        ]),
      ),
    );
  }
}
