// The Action (+) button's sheet and the coach button.
//
// The (+) is the quickest route to the three things you START: an activity,
// the journal, and the live heart rate. Each row closes the sheet and pushes
// the screen that already does the work — nothing here records anything.

import 'package:flutter/material.dart';

import '../ui2.dart';
import 'coach.dart';
import 'home_screen.dart' show go;
import 'log_food.dart' show LogFoodSheet;
import 'log_weight_sheet.dart' show LogWeightSheet;
import 'start_activity.dart' show StartActivityScreen;

/// The coach, or its setup when no model is configured yet.
void openCoach(BuildContext c) =>
    go(c, coachReadyNow(c) ? const CoachScreen() : const CoachSetup());

Future<void> openActionSheet(BuildContext c) {
  return AppSheet.show<void>(
    c,
    title: 'QUICK ACTIONS',
    child: Builder(builder: (sheet) {
      void then(void Function() open) {
        Navigator.of(sheet).pop();
        open();
      }

      return Column(mainAxisSize: MainAxisSize.min, children: [
        _ActionRow(
          LucideIcons.scale,
          C.green,
          'Log weight',
          'Keep your profile weight current for calorie accuracy',
          () => then(() => LogWeightSheet.show(c)),
        ),
        _ActionRow(
          LucideIcons.dumbbell,
          C.dialStrain,
          'Start activity',
          'Track a workout live with strain and heart rate',
          // The same door My Day's + opens, not the bare picker.
          () => then(() => go(c, const StartActivityScreen())),
        ),
        _ActionRow(
          LucideIcons.utensils,
          C.amber,
          'Log macros',
          'Record meals, snacks or scan food barcode',
          () => then(() => LogFoodSheet.show(c)),
        ),
      ]);
    }),
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, sub;
  final VoidCallback onTap;
  const _ActionRow(this.icon, this.color, this.title, this.sub, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: S.x12,
            height: S.x12,
            decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
            child: Icon(icon, size: I.lg, color: p.ink),
          ),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.toUpperCase(), style: F.caps.copyWith(color: p.ink)),
              const SizedBox(height: S.half),
              Text(sub, style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Icon(LucideIcons.chevronRight, size: I.md, color: p.ink3),
        ]),
      ),
    );
  }
}
