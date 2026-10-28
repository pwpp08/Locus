import 'package:flutter/material.dart';

import '../../../compute/onehz_pipeline.dart'
    show readinessInputShortfallNote, readinessUnstableBaselineNote;
import '../../../l10n/app_localizations.dart';
import '../../../l10n/presentation_text.dart';
import '../../../models/metric.dart';
import '../../../state/clock_format.dart' show formatClockOf;
import '../../charts.dart' show DashedRing, Ring;
import '../../grammar.dart' show Pressable, Surface;
import '../../theme.dart' show C, F, I, P, S, animate, bigText;
import '../../ui2.dart' show LucideIcons;
import 'home_data.dart';

/// Which ring. The three the app can stand behind on a home screen.
enum HomeRingKind { recovery, strain, sleep }

/// "Updated 8:12 · 2 → 28" off a `todayHeadlineOf` `recovery_update`, or null.
String? recoveryUpdatedLine(Object? update, AppLocalizations? l) {
  if (update case {
    'from': final int from,
    'to': final int to,
    'at': final int at,
  }) {
    final time = formatClockOf(DateTime.fromMillisecondsSinceEpoch(at));
    return l?.homeRecoveryUpdated(time, from, to) ??
        'Updated $time · $from → $to';
  }
  return null;
}

/// The short line every screen showing today's recovery puts beside it when
/// it is not simply final.
String? recoveryStateLine(Map<String, dynamic> head, AppLocalizations? l) =>
    switch (head['recovery_state']) {
      'night_in_progress' => l?.homeRecoverySleeping ?? 'Sleeping…',
      'provisional' => l?.homeRecoveryFinishingUp ?? 'Finishing up',
      _ => recoveryUpdatedLine(head['recovery_update'], l),
    };

/// One ring's resolved state.
class RingState {
  final HomeRingKind kind;
  final String label, value, sub;
  final IconData icon;
  final Color color;
  final double? frac;
  final bool calibrating;
  final int? have, need;
  final String? why;
  final bool provisional;

  const RingState(
    this.kind,
    this.label,
    this.icon,
    this.color, {
    required this.value,
    this.sub = '',
    this.frac,
    this.calibrating = false,
    this.have,
    this.need,
    this.why,
    this.provisional = false,
  });

  bool get measured => why == null && !calibrating;

  Color arc(P p) => calibrating || provisional ? p.ink3 : p.on(color);
  Color ink(P p) => measured && !provisional ? p.on(color) : p.ink3;

  String get spoken => [
        label,
        measured ? value : value.toLowerCase(),
        if (sub.isNotEmpty) sub,
        ?why,
      ].join('. ');
}

RingState ringOf(HomeRingKind k, HomeData d, AppLocalizations? l) {
  switch (k) {
    case HomeRingKind.recovery:
      final v = d.readiness.value;
      final band = readinessBand(v, l);
      if (d.recoveryState == 'night_in_progress') {
        return RingState(k, l?.homeRingRecovery ?? 'Recovery',
            LucideIcons.batteryCharging, C.green,
            value: l?.homeRecoverySleeping ?? 'Sleeping…',
            why: l?.homeRecoveryAfterWake ??
                'Recovery is scored after you wake.');
      }
      if (d.recoveryState == 'provisional' && v != null) {
        return RingState(k, l?.homeRingRecovery ?? 'Recovery',
            LucideIcons.batteryCharging, band.color,
            value: '${v.round()}',
            sub: l?.homeRecoveryFinishingUp ?? 'Finishing up',
            frac: v / 100,
            provisional: true);
      }
      return v == null
          ? _gap(k, l?.homeRingRecovery ?? 'Recovery', LucideIcons.batteryCharging,
              C.green, d.readiness, l?.homeReadinessNotScored ?? 'Not scored', l,
              fallbackWhy: readinessInputShortfallNote(d.absentDiag,
                      metricName: 'recovery') ??
                  readinessUnstableBaselineNote(
                      d.absentDiag?['note']?.toString(),
                      metricName: 'recovery') ??
                  '')
          : RingState(k, l?.homeRingRecovery ?? 'Recovery',
              LucideIcons.batteryCharging, band.color,
              value: '${v.round()}', sub: band.label, frac: v / 100);
    case HomeRingKind.strain:
      final v = d.strain.value;
      return v == null
          ? _gap(k, l?.homeRingStrain ?? 'Strain', LucideIcons.zap, C.domMove,
              d.strain, l?.homeRingNoStrain ?? 'No strain', l, unit: 'days')
          : RingState(k, l?.homeRingStrain ?? 'Strain', LucideIcons.zap, C.domMove,
              value: v.toStringAsFixed(1), sub: l?.homeStrainOf21 ?? 'of 21', frac: v / 21);
    case HomeRingKind.sleep:
      final v = d.sleepMin.value;
      final need = d.sleepNeedMin.value;
      return v == null
          ? _gap(k, l?.homeRingSleep ?? 'Sleep', LucideIcons.moon, C.domSleep,
              d.sleepMin, l?.homeRingNoSleep ?? 'No sleep', l,
              fallbackWhy: l?.homeSleepGapFallback ??
                  'No night long enough to score was recorded.')
          : RingState(k, l?.homeRingSleep ?? 'Sleep', LucideIcons.moon, C.domSleep,
              value: hm(v),
              sub: need == null
                  ? (l?.homeSleepNoTarget ?? 'No target yet')
                  : (l?.homeOfSpan(hm(need)) ?? 'of ${hm(need)}'),
              frac: need == null || need <= 0 ? null : v / need);
  }
}

RingState _ringOf(HomeRingKind k, HomeData d, AppLocalizations? l) =>
    ringOf(k, d, l);

RingState _gap(HomeRingKind k, String label, IconData icon, Color color,
    Metric m, String word, AppLocalizations? l,
    {String unit = 'nights', String fallbackWhy = ''}) {
  final counts = baselineCountsFromNote(m.note);
  if (counts != null) {
    return RingState(k, label, icon, color,
        value: l?.homeCalibrating ?? 'Learning your usual',
        sub: unit == 'days'
            ? (l?.homeCalibratingDays(counts.have, counts.need) ??
                '${counts.have} of ${counts.need} days')
            : (l?.homeCalibratingNights(counts.have, counts.need) ??
                '${counts.have} of ${counts.need} nights'),
        frac: (counts.have / counts.need).clamp(0.0, 1.0),
        calibrating: true,
        have: counts.have,
        need: counts.need);
  }
  return RingState(k, label, icon, color,
      value: word,
      why: whyFromNote(m.note, unit: unit) ??
          (fallbackWhy.isNotEmpty
              ? fallbackWhy
              : (l?.homeGapNoReason ?? 'Nothing recorded says why this is missing.')));
}

class RingTrio extends StatelessWidget {
  final HomeData d;
  final void Function(HomeRingKind)? onOpen;

  const RingTrio({super.key, required this.d, this.onOpen});

  static bool has(HomeData d) =>
      HomeRingKind.values.any((k) => _ringOf(k, d, null).why == null);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final rings = [for (final k in HomeRingKind.values) _ringOf(k, d, l)];
    final gaps = rings.where((r) => r.why != null).toList();

    return Surface(
      child: Column(children: [
        if (bigText(c))
          for (var i = 0; i < rings.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x2),
            _RingRow(rings[i], onTap: _open(rings[i].kind)),
          ]
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < rings.length; i++) ...[
                if (i > 0) const SizedBox(width: S.x3),
                Expanded(
                    child: _RingColumn(rings[i], onTap: _open(rings[i].kind))),
              ],
            ],
          ),
        for (final r in gaps) ...[
          const SizedBox(height: S.x2),
          Divider(color: p.line, height: 1),
          _GapRow(r, onTap: _open(r.kind)),
        ],
        if (recoveryUpdatedLine(d.readinessUpdate, l) case final note?) ...[
          const SizedBox(height: S.x2),
          Text(note, style: F.cap.copyWith(color: p.ink3)),
        ],
        if (d.readiness.value != null && d.drivers.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          Divider(color: p.line, height: 1),
          const SizedBox(height: S.x3),
          Pressable(
            onTap: _open(HomeRingKind.recovery),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l?.homeWhyLabel ?? 'Why?', style: F.cap.copyWith(color: p.ink3)),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  d.drivers
                      .take(3)
                      .map((e) => driverLabel(e['label'], l))
                      .join(' · '),
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ),
              Icon(LucideIcons.chevronRight, size: I.sm, color: p.ink3),
            ]),
          ),
        ],
      ]),
    );
  }

  VoidCallback? _open(HomeRingKind k) {
    final f = onOpen;
    return f == null ? null : () => f(k);
  }
}

class _Dial extends StatelessWidget {
  final RingState r;
  final double stroke, icon;
  final bool numeral;

  const _Dial(this.r,
      {required this.stroke, required this.icon, this.numeral = false});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Stack(alignment: Alignment.center, children: [
      CustomPaint(
        size: Size.infinite,
        painter: r.calibrating
            ? DashedRing(r.frac ?? 0, r.arc(p), p.track,
                stroke: stroke, segments: r.need ?? 24)
            : Ring(r.frac ?? 0, r.arc(p), p.track,
                stroke: stroke, t: animate(c, 1), solid: r.measured),
      ),
      if (numeral && r.measured)
        Padding(
          padding: EdgeInsets.all(stroke + S.x1),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              presentationText(AppLocalizations.of(c), r.value),
              style: F.n24.copyWith(color: r.provisional ? p.ink3 : p.ink),
            ),
          ),
        )
      else
        Icon(r.icon, size: icon, color: r.ink(p)),
    ]);
  }
}

class _RingColumn extends StatelessWidget {
  final RingState r;
  final VoidCallback? onTap;

  const _RingColumn(this.r, {this.onTap});

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        semanticLabel: r.spoken,
        child: Column(children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: AspectRatio(
              aspectRatio: 1,
              child: _Dial(r, stroke: 12, icon: I.md, numeral: true),
            ),
          ),
          const SizedBox(height: S.x3),
          _RingText(r, align: TextAlign.center, numeralInside: true),
        ]),
      );
}

class _RingRow extends StatelessWidget {
  final RingState r;
  final VoidCallback? onTap;

  const _RingRow(this.r, {this.onTap});

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        semanticLabel: r.spoken,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          child: Row(children: [
            SizedBox(
              width: 56,
              height: 56,
              child: _Dial(r, stroke: 6, icon: I.sm),
            ),
            const SizedBox(width: S.x3),
            Expanded(child: _RingText(r, align: TextAlign.start)),
          ]),
        ),
      );
}

class _RingText extends StatelessWidget {
  final RingState r;
  final TextAlign align;
  final bool numeralInside;

  const _RingText(this.r, {required this.align, this.numeralInside = false});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final cross = align == TextAlign.center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final label = Text(r.label.toUpperCase(),
        style: F.over.copyWith(color: p.ink3), textAlign: align);
    return Column(crossAxisAlignment: cross, children: [
      if (numeralInside) ...[
        Icon(r.icon, size: I.sm, color: r.ink(p)),
        const SizedBox(height: S.x1),
      ],
      label,
      if (!(numeralInside && r.measured)) ...[
        const SizedBox(height: S.x1),
        Text(
          presentationText(AppLocalizations.of(c), r.value),
          style: r.measured
              ? F.n24.copyWith(color: r.provisional ? p.ink3 : p.ink)
              : F.body.copyWith(color: p.ink2),
          textAlign: align,
        ),
      ],
      if (r.sub.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          presentationText(AppLocalizations.of(c), r.sub),
          style: F.cap.copyWith(color: p.ink3),
          textAlign: align,
        ),
      ],
    ]);
  }
}

class _GapRow extends StatelessWidget {
  final RingState r;
  final VoidCallback? onTap;

  const _GapRow(this.r, {this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(r.icon, size: I.sm, color: p.ink3),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: '${r.label} · ',
                        style: F.cap.copyWith(
                            color: p.ink2, fontWeight: FontWeight.w600)),
                    TextSpan(
                      text: presentationText(
                        AppLocalizations.of(c),
                        r.why ?? '',
                      ),
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: S.x2),
            Icon(LucideIcons.chevronRight, size: I.sm, color: p.ink3),
          ],
        ),
      ),
    );
  }
}
