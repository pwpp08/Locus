// THE PLUS MENU — what the + beside "My Day" opens: a dark panel floating over
// the page, anchored to the button, which turns into a cross while it is open.
// Four doors: start an activity, add one, the strength trainer, the journal.
// It records nothing itself; it hands back which door was taken.

import 'package:flutter/material.dart';

import '../ui2.dart';

enum PlusChoice { start, add, strength, journal }

/// Opens the menu over [anchor] (the + button's rectangle, in the screen's own
/// coordinates). Resolves to the door taken, or null when it was dismissed.
Future<PlusChoice?> showPlusMenu(BuildContext c, Rect anchor) =>
    showGeneralDialog<PlusChoice>(
      context: c,
      barrierDismissible: true,
      barrierLabel: 'Close the menu',
      barrierColor: C.char.withValues(alpha: .45),
      transitionDuration: motion(c, Motion.base),
      pageBuilder: (_, _, _) => PlusMenu(anchor: anchor),
      transitionBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Ease.standard),
        child: child,
      ),
    );

/// The + button: a rounded square with a plus, or with a cross while the menu
/// it opens is showing.
class PlusButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool open;
  const PlusButton({super.key, required this.onTap, this.open = false});

  /// The button's side.
  static const size = S.x10 + S.x1;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: open
          ? 'Close the menu'
          : 'Start an activity, add one, strength trainer or journal',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: open ? p.ink.withValues(alpha: .12) : p.ink,
          borderRadius: R.rMd,
        ),
        child: Icon(open ? LucideIcons.x : LucideIcons.plus,
            size: open ? I.lg : I.md, color: open ? p.ink : p.bg),
      ),
    );
  }
}

class PlusMenu extends StatelessWidget {
  final Rect anchor;
  const PlusMenu({super.key, required this.anchor});

  static const _rows = [
    (PlusChoice.start, LucideIcons.timer, 'Start activity'),
    (PlusChoice.add, LucideIcons.plus, 'Add activity'),
    (PlusChoice.strength, LucideIcons.dumbbell, 'Strength trainer'),
    (PlusChoice.journal, LucideIcons.notebookPen, 'Add to my journal'),
  ];

  /// One row's height, and the panel's padding above and below the rows.
  static const _row = 46.0;
  static const _pad = S.x2;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final size = MediaQuery.sizeOf(c);
    final inset = MediaQuery.paddingOf(c);
    final h = _rows.length * _row + 2 * _pad;
    const w = 216.0;

    // Open upward, cleanly positioned above the plus button with a clear gap
    // so it never overlaps the button when it turns into an X.
    var top = anchor.top - h - S.x2;
    if (top < inset.top + S.x2) {
      top = anchor.bottom + S.x2;
    }
    top = top.clamp(inset.top + S.x2, size.height - inset.bottom - h - S.x2);
    final right = (size.width - anchor.right).clamp(S.x2, size.width - w - S.x2);

    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned(
          top: top,
          right: right,
          width: w,
          height: h,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              color: Color.alphaBlend(p.ink.withValues(alpha: .10), p.card),
              border: Border.all(color: p.ink.withValues(alpha: .12)),
              boxShadow: [
                BoxShadow(
                    color: C.char.withValues(alpha: .45),
                    blurRadius: S.x6,
                    offset: const Offset(0, S.x2)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: _pad),
              child: Column(children: [
                for (final (choice, icon, label) in _rows)
                  Pressable(
                    onTap: () => Navigator.of(c).pop(choice),
                    semanticLabel: label,
                    child: SizedBox(
                      height: _row,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: S.x4),
                        child: Row(children: [
                          Icon(icon, size: I.md, color: p.ink2),
                          const SizedBox(width: S.x3),
                          Expanded(
                            child: Text(label.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: F.caps.copyWith(
                                    color: p.ink,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .6)),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        // The button, in the same place, as a cross.
        Positioned(
          left: anchor.left,
          top: anchor.top,
          child: PlusButton(onTap: () => Navigator.of(c).pop(), open: true),
        ),
      ]),
    );
  }
}
