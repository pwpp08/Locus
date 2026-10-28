import 'package:flutter/material.dart';

import '../../../data/day_label.dart' show dayLabelOf;
import '../../../l10n/app_localizations.dart';
import '../../../state/clock_format.dart' show formatClockOf;
import '../../grammar.dart' show Pressable, Surface;
import '../../theme.dart' show C, F, I, P, R, S;
import '../../ui2.dart' show LucideIcons;
import '../../activity/catalogue.dart' show activityByName;
import 'home_data.dart';

class HomeSectionHead extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const HomeSectionHead(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.only(top: S.x6, bottom: S.x3),
      child: Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: F.t1.copyWith(color: p.ink)),
          ),
        ),
        ?trailing,
      ]),
    );
  }
}

class HomeMyDay extends StatelessWidget {
  final String day;
  final Map<String, dynamic> night;
  final List<Map<String, dynamic>> sessions;
  final VoidCallback onExpand, onSleep, onAdd;
  final void Function(Map<String, dynamic> session) onSession;
  final VoidCallback? onStart;

  const HomeMyDay({
    super.key,
    required this.day,
    required this.night,
    required this.sessions,
    required this.onExpand,
    required this.onSleep,
    required this.onSession,
    required this.onAdd,
    this.onStart,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final rows = <Widget>[];
    final tst = night['duration_min'] as num?;
    if (tst != null) {
      rows.add(HomeActivityRow(
        color: C.blockSleep,
        icon: LucideIcons.moon,
        value: hMinutes(tst),
        name: l?.homeRingSleep ?? 'Sleep',
        start: night['onset_ts'] as num?,
        end: night['wake_ts'] as num?,
        day: day,
        onTap: onSleep,
      ));
    }
    for (final s in sessions) {
      final a = activityByName(s['type']?.toString());
      final strain = s['strain'] as num?;
      final mins = s['duration_min'] as num?;
      rows.add(HomeActivityRow(
        color: C.blockSession,
        icon: a?.icon ?? LucideIcons.dumbbell,
        value: strain != null
            ? strain.toStringAsFixed(1)
            : (mins == null ? '--' : hMinutes(mins)),
        name: a?.name ?? (s['title']?.toString() ?? 'Activity'),
        start: s['start_ts'] as num?,
        end: s['end_ts'] as num?,
        day: day,
        onTap: () => onSession(s),
      ));
    }
    return Surface(
      pad: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Padding(
            padding: const EdgeInsets.only(left: S.x1),
            child: Text('ACTIVITIES',
                style: F.caps.copyWith(color: p.ink, letterSpacing: .6)),
          )),
          Pressable(
            onTap: onExpand,
            semanticLabel: l?.homeBreakdownTitle ?? 'Breakdown of your day',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Icon(LucideIcons.maximize2, size: I.md, color: p.ink3),
            ),
          ),
        ]),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Text('Nothing recorded for this day yet.',
                style: F.body.copyWith(color: p.ink3)),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x3),
            rows[i],
          ],
        const SizedBox(height: S.x6),
        Row(children: [
          Expanded(
              child: homeDayButton(p, LucideIcons.plus, 'ADD ACTIVITY', onAdd)),
          if (onStart != null) ...[
            const SizedBox(width: S.x3),
            Expanded(
                child: homeDayButton(
                    p, LucideIcons.timer, 'START ACTIVITY', onStart!)),
          ],
        ]),
      ]),
    );
  }
}

Widget homeDayButton(P p, IconData icon, String label, VoidCallback onTap) =>
    Pressable(
      onTap: onTap,
      semanticLabel: label[0] + label.substring(1).toLowerCase(),
      child: Container(
        height: S.x12 + S.x1,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: S.x2),
        decoration: BoxDecoration(
          color: p.ink.withValues(alpha: .09),
          borderRadius: R.rLg,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: I.md, color: p.ink),
            const SizedBox(width: S.x2),
            Text(label, style: F.caps.copyWith(color: p.ink, letterSpacing: .6)),
          ]),
        ),
      ),
    );

class HomeActivityRow extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String value, name, day;
  final num? start, end;
  final VoidCallback onTap;

  const HomeActivityRow({
    super.key,
    required this.color,
    required this.icon,
    required this.value,
    required this.name,
    required this.start,
    required this.end,
    required this.day,
    required this.onTap,
  });

  String _when(BuildContext c, num? ts) {
    if (ts == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(ts.round() * 1000);
    final clock = formatClockOf(t);
    return dayLabelOf(t) == day
        ? clock
        : '[${weekdayShortName(t.weekday, AppLocalizations.of(c))}] $clock';
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$name, $value, ${_when(c, start)} to ${_when(c, end)}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x4, S.x2),
        decoration: BoxDecoration(
          color: Color.alphaBlend(p.ink.withValues(alpha: .08), p.card),
          borderRadius: R.rLg,
        ),
        child: Row(children: [
          Container(
            constraints: const BoxConstraints(minWidth: S.x16 + S.x12),
            height: S.x12,
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            decoration: BoxDecoration(color: color, borderRadius: R.rMd),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: I.lg, color: C.white),
              const SizedBox(width: S.x3),
              Text(value,
                  style: F.n24.copyWith(color: C.white, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: S.x5),
          Expanded(
            child: Text(name.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: F.caps.copyWith(color: p.ink, letterSpacing: .6)),
          ),
          const SizedBox(width: S.x2),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_when(c, start),
                style: F.num(F.cap).copyWith(color: p.ink3, fontWeight: FontWeight.w700)),
            const SizedBox(height: S.x2),
            Text(_when(c, end),
                style: F.num(F.cap).copyWith(color: p.ink3, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(width: S.x3),
          SizedBox(
            width: S.x2,
            height: S.x10,
            child: CustomPaint(painter: HomeSpanPainter(color)),
          ),
        ]),
      ),
    );
  }
}

class HomeSpanPainter extends CustomPainter {
  final Color color;
  HomeSpanPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    canvas.drawLine(
        Offset(x, 2),
        Offset(x, size.height - 2),
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);
    for (final y in [2.0, size.height - 2]) {
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = C.white);
    }
  }

  @override
  bool shouldRepaint(HomeSpanPainter old) => old.color != color;
}
