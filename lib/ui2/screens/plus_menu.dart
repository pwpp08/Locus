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
    showAnchoredMenu<PlusChoice>(c, anchor, PlusMenu.homeRows,
        closeButton: Builder(
            builder: (d) =>
                PlusButton(onTap: () => Navigator.of(d).pop(), open: true)));

/// The same panel for any list of doors: [rows] as (value, glyph, label),
/// opening above [anchor] and resolving to the value taken. [closeButton]
/// stands over the anchor while it is open; null draws a plain cross.
Future<T?> showAnchoredMenu<T>(
  BuildContext c,
  Rect anchor,
  List<(T, IconData, String)> rows, {
  Widget? closeButton,
}) =>
    showGeneralDialog<T>(
      context: c,
      barrierDismissible: true,
      barrierLabel: 'Close the menu',
      barrierColor: C.char.withValues(alpha: .45),
      transitionDuration: motion(c, Motion.base),
      pageBuilder: (_, _, _) =>
          PlusMenu<T>(anchor: anchor, rows: rows, closeButton: closeButton),
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
          // Opaque when open: it sits over the real button, whose plus would
          // otherwise show through it.
          color: open ? C.char : p.ink,
          borderRadius: R.rMd,
        ),
        child: Icon(open ? LucideIcons.xBold : LucideIcons.plus,
            size: open ? I.lg : I.md, color: open ? C.white : p.bg),
      ),
    );
  }
}

class PlusMenu<T> extends StatelessWidget {
  final Rect anchor;
  final List<(T, IconData, String)> rows;
  final Widget? closeButton;
  const PlusMenu(
      {super.key, required this.anchor, required this.rows, this.closeButton});

  /// The doors behind the + beside "My Day".
  static const homeRows = [
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
    final h = rows.length * _row + 2 * _pad;
    const w = 216.0;

    // Open upward, cleanly positioned above the plus button with a clear gap
    // so it never overlaps the button when it turns into an X.
    var top = anchor.top - h - S.x2;
    if (top < inset.top + S.x2) {
      top = anchor.bottom + S.x2;
    }
    top = top.clamp(inset.top + S.x2, size.height - inset.bottom - h - S.x2);
    final right = (size.width - anchor.right).clamp(S.x2, size.width - w - S.x2);
    // A button in the left half opens its panel rightward from its own edge.
    final fromLeft = anchor.center.dx < size.width / 2;
    final left = anchor.left.clamp(S.x2, size.width - w - S.x2);

    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned(
          top: top,
          right: fromLeft ? null : right,
          left: fromLeft ? left : null,
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
                for (final (choice, icon, label) in rows)
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
        Positioned.fromRect(
          rect: anchor,
          child: closeButton ??
              Pressable(
                onTap: () => Navigator.of(c).pop(),
                semanticLabel: 'Close the menu',
                child: Center(
                    child: Icon(LucideIcons.x, size: I.lg, color: C.white)),
              ),
        ),
      ]),
    );
  }
}
