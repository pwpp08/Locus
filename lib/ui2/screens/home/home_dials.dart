import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../l10n/presentation_text.dart';
import '../../charts.dart' show DashedRing, Ring;
import '../../grammar.dart' show Pressable;
import '../../marks.dart' show BoldChevron;
import '../../theme.dart' show C, F, I, Motion, P, R, S, animate, motion;
import '../../ui2.dart' show LucideIcons;
import 'home_data.dart';
import 'home_rings.dart';

const kDialOrder = [
  HomeRingKind.sleep,
  HomeRingKind.recovery,
  HomeRingKind.strain,
];

/// The day's strain target as fractions of the dial: the recommended range
/// and its optimal, drawn exactly as on the strain screen's ring.
({(double, double) band, double optimal})? strainBand(HomeData d) {
  final t = d.strainTarget;
  final lo = (t?['low'] as num?)?.toDouble();
  final hi = (t?['high'] as num?)?.toDouble();
  if (lo == null || hi == null || hi <= lo || lo < 0) return null;
  final mid = ((t?['value'] as num?)?.toDouble() ?? (lo + hi) / 2)
      .clamp(lo, hi);
  return (band: (lo / 21, hi / 21), optimal: mid / 21);
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
        final perf = d.sleepPerformance.value;
        if (slept != null && perf != null) {
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
      if (d.recoveryState == 'night_in_progress' ||
          d.recoveryState == 'provisional') ...[
        const SizedBox(height: S.x3),
        const _AwakePill(),
      ],
      const SizedBox(height: S.x3),
    ]);
  }
}

/// While today's night is still open: "I'm awake" ends it now, so recovery
/// is scored as soon as the band's data catches up instead of waiting out
/// the settle margin. Turns into a quiet "Scoring your night" once pressed.
class _AwakePill extends StatefulWidget {
  const _AwakePill();

  @override
  State<_AwakePill> createState() => _AwakePillState();
}

class _AwakePillState extends State<_AwakePill> {
  bool _sent = false;

  Future<void> _tap() async {
    setState(() => _sent = true);
    final ok = await context.read<AppState>().markAwake();
    if (!ok && mounted) setState(() => _sent = false);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: _sent ? null : _tap,
      semanticLabel: _sent
          ? 'Scoring your night'
          : "I'm awake: end the night and score recovery",
      child: AnimatedContainer(
        duration: motion(c, Motion.base),
        curve: Curves.easeOut,
        height: S.x8,
        padding: const EdgeInsets.symmetric(horizontal: S.x3 + S.half),
        decoration: BoxDecoration(
          color: _sent ? p.card : p.ink,
          borderRadius: const BorderRadius.all(Radius.circular(R.xl)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_sent ? LucideIcons.hourglass : LucideIcons.sunrise,
              size: I.sm, color: _sent ? p.ink3 : p.bg),
          const SizedBox(width: S.x2 - S.hair),
          Text(_sent ? 'Scoring your night…' : "I'm awake",
              style: F.cap.copyWith(
                  color: _sent ? p.ink3 : p.bg, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
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
                              band: target?.band,
                              bandColor: Color.alphaBlend(
                                  p.ink.withValues(alpha: .24), p.track),
                              tick: target?.optimal,
                              tickColor: p.ink,
                              tickWidth: .26),
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
