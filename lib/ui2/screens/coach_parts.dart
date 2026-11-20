// The coach's pieces: its ground, the two sides of a conversation, the
// gradient-edged card its figures and workouts sit in, the reply chips and the
// scroll-down button. Kept apart from `coach.dart`, which owns the state, so
// each can be drawn on its own in the gallery.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../ui2.dart';

/// The coach's ground: warm taupe under the header, through slate and navy,
/// into the near-black floor. The fall is a fixed [C.coachDusk] deep, so a
/// short sheet and a tall one start the same way. Always dark (the app is).
class CoachGround extends StatelessWidget {
  final Widget child;
  const CoachGround({super.key, required this.child});

  @override
  Widget build(BuildContext c) => ColoredBox(
        color: C.coachFloor,
        child: Stack(children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: C.coachDusk,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: C.coachNight,
                  stops: C.coachNightStops,
                ),
              ),
            ),
          ),
          child,
        ]),
      );
}

/// The top of the coach: its orb and name in a translucent pill.
class CoachTag extends StatelessWidget {
  final String label;
  const CoachTag(this.label, {super.key});

  @override
  Widget build(BuildContext c) => Container(
        padding: const EdgeInsets.fromLTRB(S.x1, S.x1, S.x3, S.x1),
        decoration: BoxDecoration(
          color: C.white.withValues(alpha: .10),
          borderRadius: R.rPill,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const AiOrb(size: S.x6),
          const SizedBox(width: S.x2),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.body.copyWith(color: C.white)),
          ),
        ]),
      );
}

/// The person's turn: a translucent bubble on the right.
class CoachUserBubble extends StatelessWidget {
  final String text;
  const CoachUserBubble(this.text, {super.key});

  @override
  Widget build(BuildContext c) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: S.x12, bottom: S.x5),
          padding:
              const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          decoration: BoxDecoration(
            color: C.white.withValues(alpha: .11),
            borderRadius: R.rXxl,
          ),
          child: Text(text,
              style: F.body.copyWith(
                  color: C.white,
                  fontWeight: FontWeight.w400,
                  height: 1.4)),
        ),
      );
}

/// The coach's turn: plain text on the ground, bold where it matters, and
/// under a finished answer, copy and (on the latest one) answer again.
class CoachAnswer extends StatelessWidget {
  final String text;

  /// Whether to show the row under it: false while it is still arriving.
  final bool actions;

  /// Ask again for a new answer; null hides the button.
  final VoidCallback? onRegenerate;

  const CoachAnswer(this.text,
      {super.key, this.actions = true, this.onRegenerate});

  @override
  Widget build(BuildContext c) => Padding(
        padding: EdgeInsets.only(bottom: actions ? S.x3 : S.x5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // The coach's mark beside its words, level with the first line.
          const Padding(
            padding: EdgeInsets.only(top: S.half),
            child: AiOrb(size: kCoachAvatar),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GptMarkdown(
              // Paragraphs sit close, a line apart rather than a blank line.
              tightParagraphs(text),
              // The prose sits a step back so the bold figures lead the eye.
              style: F.body.copyWith(
                  color: C.white.withValues(alpha: .74),
                  fontWeight: FontWeight.w400,
                  height: 1.4),
              inlineComponents: kCoachInlineMarkdown,
            ),
            if (actions)
              // The glyphs sit on the text's left edge; their tap areas
              // reach out past it.
              Transform.translate(
                offset: const Offset(-(S.tap - I.sm) / 2, 0),
                child: Row(children: [
                _CopyButton(text),
                if (onRegenerate != null)
                  Pressable(
                    onTap: onRegenerate,
                    semanticLabel: 'Answer again',
                    child: SizedBox.square(
                      dimension: S.tap,
                      child: Icon(LucideIcons.refreshCw,
                          size: I.sm, color: C.white.withValues(alpha: .6)),
                    ),
                  ),
              ]),
              ),
          ],
            ),
          ),
        ]),
      );
}

/// Markdown's inline syntaxes with bold made the answer's anchor: full white
/// and heavier than the dimmed prose round it, so a glance down the reply
/// lands on the figures and the verdicts.
final List<MarkdownComponent> kCoachInlineMarkdown = [
  for (final m in MarkdownComponent.inlineComponents)
    m is BoldMd ? CoachBoldMd() : m,
];

/// `**bold**` in the coach's voice: white, w700.
class CoachBoldMd extends BoldMd {
  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text.trim());
    final conf = config.copyWith(
      style: (config.style ?? const TextStyle())
          .copyWith(color: C.white, fontWeight: FontWeight.w700),
    );
    return TextSpan(
      children: MarkdownComponent.generate(
          context, '${match?[1]}', conf, false),
      style: conf.style,
    );
  }
}

/// The coach's mark beside each answer.
const double kCoachAvatar = 20;

/// [md] with each run of blank lines folded into one line break, outside
/// code fences. Tables keep their blank line before them.
String tightParagraphs(String md) {
  final out = StringBuffer();
  var fenced = false;
  var blank = false;
  for (final line in md.split('\n')) {
    if (line.trimLeft().startsWith('```')) fenced = !fenced;
    if (!fenced && line.trim().isEmpty) {
      blank = true;
      continue;
    }
    if (out.isNotEmpty) {
      out.write(blank && line.trimLeft().startsWith('|') ? '\n\n' : '\n');
    }
    blank = false;
    out.write(line);
  }
  return out.toString();
}

class _CopyButton extends StatefulWidget {
  final String text;
  const _CopyButton(this.text);

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _done = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: widget.text));
          if (!mounted) return;
          setState(() => _done = true);
          _t?.cancel();
          _t = Timer(Motion.copied, () {
            if (mounted) setState(() => _done = false);
          });
        },
        semanticLabel: _done ? 'Copied' : 'Copy',
        child: SizedBox.square(
          dimension: S.tap,
          child: Icon(_done ? LucideIcons.check : LucideIcons.copy,
              size: I.sm, color: C.white.withValues(alpha: .6)),
        ),
      );
}

/// The frame the coach's figures and workouts sit in: a violet-to-teal edge
/// round a dark card.
class CoachCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const CoachCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.x4),
  });

  @override
  Widget build(BuildContext c) => Container(
        padding: const EdgeInsets.all(S.hair + S.half / 4),
        decoration: const BoxDecoration(
          borderRadius: R.rXxl,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [C.coachGoA, C.coachGoB],
          ),
        ),
        child: Container(
          padding: padding,
          decoration: const BoxDecoration(
            color: C.coachField,
            borderRadius: BorderRadius.all(Radius.circular(R.xxl - S.hair)),
          ),
          child: child,
        ),
      );
}

/// A coach card's one action: a violet-to-blue button in spaced caps. [done]
/// turns it into a quiet confirmation with a tick.
class CoachGoButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool done;
  const CoachGoButton(this.label, {super.key, this.onTap, this.done = false});

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: done ? null : onTap,
        semanticLabel: label,
        child: Container(
          height: S.tap,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: R.rLg,
            gradient: const LinearGradient(colors: [C.coachGoA, C.coachGoB]),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (done) ...[
              const Icon(LucideIcons.check, size: I.sm, color: C.white),
              const SizedBox(width: S.x2),
            ],
            Text(label.toUpperCase(),
                style: F.cap.copyWith(
                    color: C.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5)),
          ]),
        ),
      );
}

/// What to say next: white pills in a row that scrolls sideways.
class CoachReplyChips extends StatelessWidget {
  final List<String> replies;
  final ValueChanged<String> onTap;
  const CoachReplyChips(this.replies, {super.key, required this.onTap});

  @override
  Widget build(BuildContext c) => SizedBox(
        height: S.tap,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          itemCount: replies.length,
          separatorBuilder: (_, _) => const SizedBox(width: S.x2),
          itemBuilder: (_, i) => Pressable(
            onTap: () => onTap(replies[i]),
            semanticLabel: replies[i],
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: S.x4, vertical: S.x2),
                decoration: const BoxDecoration(
                    color: C.white, borderRadius: R.rPill),
                child: Text(replies[i],
                    maxLines: 1,
                    style: F.body.copyWith(
                        color: C.char, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      );
}

/// Back to the newest line: a white disc with a down arrow.
class CoachScrollDown extends StatelessWidget {
  final VoidCallback onTap;
  const CoachScrollDown({super.key, required this.onTap});

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        semanticLabel: 'Scroll to the newest message',
        child: Container(
          width: S.x10,
          height: S.x10,
          decoration:
              const BoxDecoration(color: C.white, shape: BoxShape.circle),
          child: const Icon(LucideIcons.arrowDown, size: I.md, color: C.char),
        ),
      );
}
