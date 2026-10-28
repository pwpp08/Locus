import 'package:flutter/material.dart';
import 'package:openstrap_analytics/onehz.dart'
    show quietHrrMinDays, readinessCompositeMinBaseline;

import '../../../data/day_label.dart' show todayLabel;
import '../../../data/db.dart' show DbRebuild;
import '../../../l10n/app_localizations.dart';
import '../../../state/prefs.dart';
import '../../grammar.dart' show StatusCard, Surface;
import '../../theme.dart' show C, F, I, P, S;
import '../../ui2.dart' show LucideIcons;
import 'home_data.dart' show prettyDay, thousands;

StatusCard? dbRebuiltCard(DbRebuild? r, [AppLocalizations? l]) {
  if (r == null) return null;
  final saved = r.salvaged.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final lost = r.salvaged.entries.where((e) => e.value == 0).toList();
  final savedList = saved.map((e) => '${e.key} ${thousands(e.value)}').join(' · ');
  final lostList = lost.map((e) => e.key).join(' · ');
  return StatusCard(
    l?.homeDbRebuiltTitle ?? 'Your database was rebuilt to start the app',
    '${r.cause}\n\n'
        '${saved.isEmpty ? (l?.homeDbRebuiltNothingRecovered ?? 'Nothing could be read back.') : (l?.homeDbRebuiltRecovered(savedList) ?? 'Recovered: $savedList.')}'
        '${lost.isEmpty ? '' : ' ${l?.homeDbRebuiltEmpty(lostList) ?? 'Empty: $lostList.'}'}'
        '\n\n${l?.homeDbRebuiltKept(r.quarantinePath) ?? 'The original file is kept at ${r.quarantinePath} — nothing was deleted.'}',
    icon: LucideIcons.databaseBackup,
  );
}

StatusCard workoutHoldCard([AppLocalizations? l]) => StatusCard(
      l?.homeWorkoutHoldTitle ?? 'A workout is still running',
      l?.homeWorkoutHoldBody ??
          'Today is paused while a workout runs. The band keeps recording; finish the workout from the bar below and today fills in.',
      icon: LucideIcons.timer,
    );

StatusCard? staleInsightsCard(
    Map<String, dynamic>? reason, VoidCallback? onSync, [AppLocalizations? l]) {
  final s = reason;
  if (s == null) return null;
  final built = s['built_for_day']?.toString();
  return StatusCard(
    l?.homeInsightsRebuildingTitle ?? 'Your cross-day insights are being rebuilt',
    switch (s['kind']) {
      'algo_version' => l?.homeInsightsRebuildingAlgoVersion ??
          'How these are computed changed with the last update.',
      'stale' => built == null || built.isEmpty
          ? (l?.homeInsightsStaleOverWeek ??
              'Your trends were last updated over a week ago. Sync the band to bring them up to date.')
          : (l?.homeInsightsStaleOnDay(prettyDay(built, l)) ??
              'Your trends were last updated on ${prettyDay(built, l)}. Sync the band to bring them up to date.'),
      _ => l?.homeInsightsNoVersionStamp ?? 'Your trends are being updated. This takes a minute after a sync.',
    },
    fix: onSync == null ? '' : (l?.homeSyncBand ?? 'Sync the band'),
    icon: LucideIcons.refreshCw,
    onFix: onSync,
  );
}

Widget firstWeekCard(BuildContext c,
    {required int days, required bool strainScored, int? recoveryNightsLeft}) {
  final p = P.of(c);
  final l = AppLocalizations.of(c);
  final strainDay = quietHrrMinDays + 1;
  final recoveryNight = readinessCompositeMinBaseline + 1;
  Widget step(bool done, String text) => Semantics(
        label: done ? (l?.homeFirstWeekDone(text) ?? 'Done: $text') : text,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          child: Row(children: [
            Icon(done ? LucideIcons.circleCheck : LucideIcons.circle,
                size: I.md, color: done ? p.on(C.green) : p.ink3),
            const SizedBox(width: S.x3),
            Expanded(
                child: Text(text, style: F.body.copyWith(color: p.ink))),
          ]),
        ),
      );
  return HomeSwipeAway(
    child: Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l?.homeFirstWeekTitle ?? 'Your first weeks',
            style: F.head.copyWith(color: p.ink)),
        const SizedBox(height: S.x2),
        step(days > 0, l?.homeFirstWeekWear ?? 'Wear the band tonight'),
        step(days > 0,
            l?.homeFirstWeekSleep ?? 'Sleep: the morning after your first night'),
        step(strainScored,
            l?.homeFirstWeekStrain(strainDay) ?? 'Strain: from day $strainDay'),
        step(
            false,
            recoveryNightsLeft != null
                ? (l?.homeRecoveryStartsIn(recoveryNightsLeft) ??
                    'Recovery starts in $recoveryNightsLeft nights')
                : (l?.homeFirstWeekRecovery(recoveryNight) ??
                    'Recovery: from night $recoveryNight, once it knows your normal')),
        const SizedBox(height: S.x1),
        Text(l?.homeFirstWeekSoFar(days) ?? '$days days recorded so far',
            style: F.cap.copyWith(color: p.ink3)),
      ]),
    ),
  );
}

class HomeSwipeAway extends StatefulWidget {
  final Widget child;
  const HomeSwipeAway({super.key, required this.child});

  @override
  State<HomeSwipeAway> createState() => _HomeSwipeAwayState();
}

class _HomeSwipeAwayState extends State<HomeSwipeAway> {
  late bool _gone = Prefs.getString(Prefs.firstWeeksDismissedOn, '') == todayLabel();

  @override
  Widget build(BuildContext c) {
    if (_gone) return const SizedBox.shrink();
    return Dismissible(
      key: const ValueKey('first-weeks-card'),
      onDismissed: (_) {
        Prefs.setString(Prefs.firstWeeksDismissedOn, todayLabel());
        setState(() => _gone = true);
      },
      child: widget.child,
    );
  }
}
