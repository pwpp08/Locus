// The card that says new behavior insights have unlocked: the behaviors by
// name, what that means, and one way in. Warm-to-violet ground and a rim that
// runs salmon into violet, as the first-night card's.

import 'package:flutter/material.dart';

import '../../ui2.dart';

class InsightUnlockedCard extends StatelessWidget {
  /// The behaviors that unlocked, by name.
  final List<String> titles;
  final VoidCallback onOpen, onDismiss;
  const InsightUnlockedCard({
    super.key,
    required this.titles,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final shown = titles.take(3).toList();
    final more = titles.length - shown.length;
    final one = titles.length == 1;
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: R.rLg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GS.rimA, GS.rimB, GS.rimC],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(S.hair),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: R.rLg,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [GS.warmA, GS.warmB],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x2, S.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: S.x8,
                    height: S.x8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [CB.pillA, CB.pillB]),
                    ),
                    child: const Icon(LucideIcons.sparkles,
                        size: I.md, color: C.white),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                        one ? 'NEW INSIGHT UNLOCKED' : 'NEW INSIGHTS UNLOCKED',
                        style: F.caps.copyWith(color: p.ink, letterSpacing: .8)),
                  ),
                  Pressable(
                    onTap: onDismiss,
                    semanticLabel: 'Dismiss',
                    child: SizedBox.square(
                      dimension: S.tap,
                      child: Icon(LucideIcons.x, size: I.md, color: p.ink3),
                    ),
                  ),
                ]),
                const SizedBox(height: S.x3),
                Padding(
                  padding: const EdgeInsets.only(right: S.x2),
                  child: Text(
                    one
                        ? 'Your log is long enough to show how ${shown.first} lines up with your Recovery.'
                        : 'Your log is long enough to show how these line up with your Recovery.',
                    style: F.body.copyWith(color: GS.body, height: 1.4),
                  ),
                ),
                const SizedBox(height: S.x3),
                Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                  for (final t in shown) _Chip(t),
                  if (more > 0) _Chip('+$more'),
                ]),
                const SizedBox(height: S.x4),
                Padding(
                  padding: const EdgeInsets.only(right: S.x2),
                  child: Pressable(
                    onTap: onOpen,
                    semanticLabel: 'See insights',
                    child: Container(
                      height: S.tap,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        borderRadius: R.rMd,
                        gradient: LinearGradient(colors: [CB.pillA, CB.pillB]),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('SEE INSIGHTS',
                            style: F.caps.copyWith(
                                color: C.white, fontWeight: FontWeight.w800)),
                        const SizedBox(width: S.x2),
                        const Icon(LucideIcons.arrowRight,
                            size: I.sm, color: C.white),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1),
        decoration: BoxDecoration(
          color: C.white.withValues(alpha: .1),
          borderRadius: R.rPill,
        ),
        child: Text(text, style: F.cap.copyWith(color: C.white)),
      );
}
