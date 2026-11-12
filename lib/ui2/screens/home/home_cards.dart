import 'package:flutter/material.dart';

import '../../../data/day_label.dart' show todayLabel;
import '../../../data/db.dart' show DbRebuild;
import '../../../l10n/app_localizations.dart';
import '../../../state/prefs.dart';
import '../../grammar.dart' show StatusCard;
import '../../ui2.dart' show LucideIcons;
import 'home_data.dart' show thousands;

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
