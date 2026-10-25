// CHOOSE YOUR ALARM MODE — what an alarm waits for before it wakes you. The
// rules themselves live in `state/alarm_mode.dart`; this only asks.

import 'package:flutter/material.dart';

import '../../state/alarm_mode.dart';
import '../ui2.dart';

/// Opens the sheet and returns the mode picked, or null when it is dismissed.
Future<AlarmMode?> openAlarmModeSheet(BuildContext c, {AlarmMode? current}) =>
    AppSheet.open<AlarmMode>(
      c,
      bare: true,
      scroll: true,
      builder: (_) => _ModeSheet(current: current),
    );

class _ModeSheet extends StatefulWidget {
  final AlarmMode? current;
  const _ModeSheet({this.current});

  @override
  State<_ModeSheet> createState() => _ModeSheetState();
}

class _ModeSheetState extends State<_ModeSheet> {
  bool _help = false;

  static const _explain = {
    AlarmMode.exact: 'Rings at the time you set, whatever the night was.',
    AlarmMode.sleepGoal:
        'Rings once you have had the time in bed your sleep need takes, up to '
            'an hour before the time you set, and never after it.',
    AlarmMode.inTheGreen:
        'The same, with half an hour more for the restorative sleep recovery '
            'is built from. It is a rule of thumb, not a forecast of your '
            'recovery.',
  };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Color.alphaBlend(p.ink.withValues(alpha: .08), p.bg),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      padding: EdgeInsets.fromLTRB(
          S.gutter, S.x6, S.gutter, S.x8 + MediaQuery.paddingOf(c).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Pressable(
            onTap: () => Navigator.of(c).pop(),
            semanticLabel: 'Back',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Icon(LucideIcons.arrowLeft, size: I.lg, color: p.ink),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('Choose your alarm mode',
                  style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.w500)),
            ),
          ),
          Pressable(
            onTap: () => setState(() => _help = !_help),
            semanticLabel: 'About the modes',
            child: Container(
              width: S.x8,
              height: S.x8,
              margin: const EdgeInsets.all(S.x1 + S.half),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.ink3, width: S.half),
              ),
              child: Icon(LucideIcons.circleHelp, size: I.sm, color: p.ink3),
            ),
          ),
        ]),
        const SizedBox(height: S.x6),
        for (final m in AlarmMode.values) ...[
          Pressable(
            onTap: () => Navigator.of(c).pop(m),
            semanticLabel: '${m.title}. ${m.blurb}',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: S.x4, vertical: S.x6 + S.x1),
              decoration: BoxDecoration(
                color: Color.alphaBlend(C.char.withValues(alpha: .35), p.bg),
                borderRadius: R.rMd,
                border: Border.all(
                    color: m == widget.current
                        ? p.ink
                        : C.char.withValues(alpha: .9),
                    width: S.half),
              ),
              child: Column(children: [
                Text(m.title,
                    style: F.head.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6)),
                const SizedBox(height: S.x2),
                Text(m.blurb,
                    textAlign: TextAlign.center,
                    style: F.head.copyWith(
                        color: p.ink2, fontWeight: FontWeight.w400)),
                if (_help) ...[
                  const SizedBox(height: S.x3),
                  Text(_explain[m]!,
                      textAlign: TextAlign.center,
                      style: F.cap.copyWith(color: p.ink3, height: 1.4)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: S.x2),
        ],
      ]),
    );
  }
}
