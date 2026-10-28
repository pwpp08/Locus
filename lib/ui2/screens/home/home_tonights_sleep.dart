import 'package:flutter/material.dart';

import '../../../state/clock_format.dart' show formatClockOf;
import '../../../theme/theme_switcher.dart' show themedRoute;
import '../../profile/alarm.dart' show AlarmArmState, AlarmScreen;
import '../../theme.dart' show C, F, I, P, R, S;
import '../../ui2.dart' show LucideIcons, Pressable, Surface;
import '../sleep_planner.dart' show SleepPlannerScreen;
import 'home_data.dart' show clock;

class HomeTonightsSleep extends StatelessWidget {
  final int? bedtimeMin;
  final (DateTime?, AlarmArmState)? alarm;
  const HomeTonightsSleep({super.key, required this.bedtimeMin, required this.alarm});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final at = alarm?.$1;
    final state = alarm?.$2 ?? AlarmArmState.none;
    final (String status, Color dot) = at == null
        ? ('ALARM OFF', p.ink3)
        : switch (state) {
            AlarmArmState.confirmed => ('ALARM ON', C.recGreen),
            AlarmArmState.pending => ('SENDING TO BAND', C.recYellow),
            AlarmArmState.unknown => ('NOT CONFIRMED', C.recYellow),
            AlarmArmState.none => ('ALARM OFF', p.ink3),
          };
    void openAlarm() => Navigator.of(c).push(
        themedRoute((_) => const AlarmScreen(), name: 'AlarmScreen'));

    Widget half(IconData icon, String time, Widget under) =>
        Column(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: I.lg, color: p.ink2),
            const SizedBox(width: S.x2),
            Text(time,
                style: F.n24.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: S.x1),
          under,
        ]);

    return Surface(
      pad: const EdgeInsets.all(S.x4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Pressable(
          onTap: () => Navigator.of(c).push(
              themedRoute((_) => const SleepPlannerScreen(), name: 'SleepPlannerScreen')),
          semanticLabel: 'Tonight’s sleep',
          child: Row(children: [
            Expanded(
                child: Text('TONIGHT’S SLEEP',
                    style: F.caps.copyWith(color: p.ink))),
            SizedBox(
              width: S.tap,
              height: S.tap,
              child: Icon(LucideIcons.chevronRight, size: I.md, color: p.ink2),
            ),
          ]),
        ),
        const SizedBox(height: S.x2),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: half(
              LucideIcons.sunset,
              bedtimeMin == null ? '--' : clock(bedtimeMin),
              Text('RECOMMENDED\nBEDTIME',
                  textAlign: TextAlign.center,
                  style: F.over.copyWith(
                      color: p.ink2, fontWeight: FontWeight.w700)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: S.x4),
            child: Text('- - - -', style: F.cap.copyWith(color: p.ink3)),
          ),
          Expanded(
            child: half(
              LucideIcons.alarmClock,
              at == null ? '--' : formatClockOf(at),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: S.x2,
                  height: S.x2,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: S.x1),
                Flexible(
                  child: Text(status,
                      style: F.over.copyWith(
                          color: dot == p.ink3 ? p.ink2 : dot,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: S.x4),
        Pressable(
          onTap: openAlarm,
          semanticLabel: at == null ? 'Set alarm' : 'Edit alarm',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: S.x4),
            decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(LucideIcons.pencil, size: I.md, color: p.ink),
              const SizedBox(width: S.x3),
              Text(at == null ? 'SET ALARM' : 'EDIT ALARM',
                  style: F.caps.copyWith(color: p.ink)),
            ]),
          ),
        ),
      ]),
    );
  }
}
