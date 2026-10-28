import 'package:flutter/material.dart';

import '../../../compute/sleep_performance.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/presentation_text.dart';
import '../../charts.dart' show DashedRing, Ring;
import '../../grammar.dart' show Pressable;
import '../../marks.dart' show BoldChevron;
import '../../theme.dart' show C, F, P, S, animate;
import 'home_data.dart';
import 'home_rings.dart';

const kDialOrder = [
  HomeRingKind.sleep,
  HomeRingKind.recovery,
  HomeRingKind.strain,
];

(double, double)? strainBand(HomeData d) {
  final t = d.strainTarget;
  final lo = (t?['low'] as num?)?.toDouble();
  final hi = (t?['high'] as num?)?.toDouble();
  if (lo == null || hi == null || hi <= lo || lo < 0) return null;
  return (lo / 21, hi / 21);
}

(String, String, double?, Color) dialFace(RingState r, HomeData d, P p) {
  var value = '--';
  var suffix = '';
  double? frac;
  var arc = p.ink3;
  if (r.measured) {
    switch (r.kind) {
      case HomeRingKind.sleep:
        final slept = d.sleepMin.value;
        final need = d.sleepNeedMin.value ?? 480.0;
        if (slept != null && need > 0) {
          final perf = computeAdjustedSleepPerformance(
            tstMin: slept.toDouble(),
            needMin: need.toDouble(),
            efficiencyPct: d.sleepEfficiency.value?.toDouble(),
            remMin: d.remMin.value?.toDouble(),
            deepMin: d.deepMin.value?.toDouble(),
          );
          value = '${perf.round()}';
          suffix = '%';
          frac = perf / 100;
        } else if (slept != null) {
          value = hMinutes(slept);
        }
        arc = C.dialSleep;
      case HomeRingKind.recovery:
        final v = d.readiness.value!;
        value = '${v.round()}';
        suffix = '%';
        frac = v / 100;
        arc = r.provisional ? p.ink3 : recoveryColor(v);
      case HomeRingKind.strain:
        final v = d.strain.value!;
        value = v.toStringAsFixed(1);
        frac = v / 21;
        arc = C.dialStrain;
    }
  } else if (r.calibrating) {
    frac = r.frac;
  }
  return (value, suffix, frac, arc);
}

String dialName(HomeRingKind k, AppLocalizations? l) => switch (k) {
      HomeRingKind.sleep => l?.homeRingSleep ?? 'Sleep',
      HomeRingKind.recovery => l?.homeRingRecovery ?? 'Recovery',
      HomeRingKind.strain => l?.homeRingStrain ?? 'Strain',
    };

final _never = ValueNotifier<int>(0);

class HomeDials extends StatelessWidget {
  final HomeData d;
  final void Function(HomeRingKind) onOpen;
  final Map<HomeRingKind, GlobalKey>? keys;
  final ScrollController? scroll;
  final String? note;

  const HomeDials({
    super.key,
    required this.d,
    required this.onOpen,
    this.keys,
    this.scroll,
    this.note,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final rings = [for (final k in kDialOrder) ringOf(k, d, l)];
    return Column(children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < rings.length; i++) ...[
            if (i > 0) const SizedBox(width: S.x3),
            Expanded(
              child: HomeScoreDial(
                rings[i],
                d: d,
                onTap: () => onOpen(rings[i].kind),
                ringKey: keys?[rings[i].kind],
                scroll: scroll,
              ),
            ),
          ],
        ],
      ),
      if (note != null) ...[
        const SizedBox(height: S.x2),
        Text(note!, style: F.cap.copyWith(color: p.ink3)),
      ],
      if (recoveryUpdatedLine(d.readinessUpdate, l) case final note?) ...[
        const SizedBox(height: S.x2),
        Text(note, style: F.cap.copyWith(color: p.ink3)),
      ],
      const SizedBox(height: S.x3),
    ]);
  }
}

class HomeScoreDial extends StatelessWidget {
  final RingState r;
  final HomeData d;
  final VoidCallback onTap;
  final GlobalKey? ringKey;
  final ScrollController? scroll;

  const HomeScoreDial(
    this.r, {
    super.key,
    required this.d,
    required this.onTap,
    this.ringKey,
    this.scroll,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final (value, suffix, frac, arc) = dialFace(r, d, p);
    final name = dialName(r.kind, l);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$name. ${r.measured ? '$value$suffix' : r.value}',
      child: Column(children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: S.x16 * 2 + S.x4),
          child: FractionallySizedBox(
            widthFactor: 0.85,
            child: AspectRatio(
              key: ringKey,
              aspectRatio: 1,
              child: ListenableBuilder(
                listenable: scroll ?? _never,
                builder: (c, ring) => Opacity(
                  opacity: scroll != null && scroll!.hasClients && scroll!.offset > .5 ? 0 : 1,
                  child: ring,
                ),
                child: LayoutBuilder(builder: (c, box) {
                  final stroke = box.maxWidth * .058;
                  final target = r.kind == HomeRingKind.strain ? strainBand(d) : null;
                  return Stack(alignment: Alignment.center, children: [
                    CustomPaint(
                      size: Size.infinite,
                      painter: r.calibrating
                          ? DashedRing(frac ?? 0, p.ink3, p.track,
                              stroke: stroke, segments: r.need ?? 24)
                          : Ring(frac ?? 0, arc, p.track,
                              stroke: stroke,
                              t: animate(c, 1),
                              solid: true,
                              flatStart: true,
                              band: target,
                              bandColor: Color.alphaBlend(
                                  p.ink.withValues(alpha: .24), p.track),
                              tick: target?.$1,
                              tickColor: p.ink),
                    ),
                    Padding(
                      padding: EdgeInsets.all(stroke + S.x2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(value,
                                style: F.n34.copyWith(
                                    color: r.provisional ? p.ink3 : p.ink,
                                    fontWeight: FontWeight.w700)),
                            if (suffix.isNotEmpty)
                              Text(suffix,
                                  style: F.n17.copyWith(
                                      color: r.provisional ? p.ink3 : p.ink,
                                      fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        ),
        const SizedBox(height: S.x3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(name.toUpperCase(),
                textAlign: TextAlign.center,
                style: F.caps.copyWith(color: p.ink)),
          ),
          const SizedBox(width: S.x2),
          BoldChevron(left: false, color: p.ink3, height: S.x3),
        ]),
        if (r.provisional || r.calibrating) ...[
          const SizedBox(height: S.half),
          Text(presentationText(l, r.sub),
              textAlign: TextAlign.center,
              style: F.over.copyWith(color: p.ink3)),
        ],
      ]),
    );
  }
}
