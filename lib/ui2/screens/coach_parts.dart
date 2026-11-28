// The coach's pieces: its ground, the two sides of a conversation, the
// gradient-edged card its figures and workouts sit in, the reply chips and the
// scroll-down button. Kept apart from `coach.dart`, which owns the state, so
// each can be drawn on its own in the gallery.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../coach/coach_prompt.dart'
    show kChartLinkIds, withoutChartLinks;
import '../ui2.dart';
import 'trend_view.dart' show TrendViewScreen;

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
            aiMarkdown(
              c,
              text,
              // The prose sits a step back so the bold figures lead the eye.
              F.body.copyWith(
                  color: C.white.withValues(alpha: .74),
                  fontWeight: FontWeight.w400,
                  height: 1.6),
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

/// A model's words, as every screen shows them: aired out, bold leading the
/// eye, and figures that open their chart underlined.
Widget aiMarkdown(BuildContext context, String text, TextStyle style) =>
    GptMarkdown(
      spacedParagraphs(text),
      style: style,
      inlineComponents: kCoachInlineMarkdown,
      // Our own chart links; any other link keeps the package's look and,
      // as before, opens nothing.
      linkBuilder: (c, span, url, base) {
        final id = _chartIdOfUrl(url);
        if (!url.startsWith(_chartScheme)) return Text.rich(span);
        return Text(span.toPlainText(),
            // The paragraph already scales its inline widgets.
            textScaler: TextScaler.noScaling,
            style: base.copyWith(
                color: C.white,
                fontWeight: FontWeight.w700,
                decoration: id == null ? null : TextDecoration.underline,
                decorationColor: C.dialStrain,
                decorationThickness: 2));
      },
      onLinkTap: (url, _) {
        final id = _chartIdOfUrl(url);
        if (id == null) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => TrendViewScreen(initial: id)));
      },
    );

const _chartScheme = 'chart:';

String? _chartIdOfUrl(String url) {
  if (!url.startsWith(_chartScheme)) return null;
  final id = url.substring(_chartScheme.length);
  return kChartLinkIds.contains(id) ? id : null;
}

final _chartWords = [
  (RegExp(r'\bhrv\b'), 'hrv'),
  (RegExp(r'\brecovery\b'), 'recovery'),
  (RegExp(r'resting (heart rate|hr)\b|\brhr\b'), 'resting_hr'),
  (RegExp(r'respiratory rate'), 'resp_rate'),
  (RegExp(r'\bstrain\b'), 'strain'),
  (RegExp(r'\bsteps\b'), 'steps'),
  (RegExp(r'sleep performance'), 'sleep_perf'),
  (RegExp(r'sleep debt'), 'sleep_debt'),
  (RegExp(r'sleep efficiency'), 'efficiency'),
  (RegExp(r'\bof sleep\b|\basleep\b'), 'hvn_hours'),
  (RegExp(r'\bstress\b'), 'day_stress'),
  (RegExp(r'\bcalories\b|\bkcal\b'), 'calories'),
];

/// The chart a bold phrase is about, when it states a figure and names its
/// metric ("**recovery 67%**"): a link even when the model wrote none.
String? chartIdFor(String bold) {
  if (bold.length > 32 || !bold.contains(RegExp(r'\d'))) return null;
  final t = bold.toLowerCase();
  for (final (words, id) in _chartWords) {
    if (words.hasMatch(t)) return id;
  }
  return null;
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
    final id = chartIdFor('${match?[1]}');
    if (id != null && config.linkBuilder != null) {
      return buildLinkSpan(context, conf,
          url: '$_chartScheme$id', label: '${match?[1]}');
    }
    return TextSpan(
      children: MarkdownComponent.generate(
          context, '${match?[1]}', conf, false),
      style: conf.style,
    );
  }
}

/// The coach's mark beside each answer.
const double kCoachAvatar = 20;

final _listLine = RegExp(r'^\s*([-*+]|\d+[.)])\s');
final _boldRoundLink =
    RegExp(r'\*\*\s*(\[[^\]]*\]\(chart:[a-z0-9_]+\))\s*\*\*');
final _boldInLink = RegExp(r'\[\*\*([^\]*]*)\*\*\](?=\(chart:)');

/// [md] laid out to be skimmed, outside code fences: one blank line between
/// blocks and round a list, none between a list's own items. Bold around or
/// inside a chart link is dropped (the link is bold already).
String spacedParagraphs(String md) {
  final out = StringBuffer();
  var fenced = false;
  var blank = false;
  var wasItem = false;
  for (var line in md.split('\n')) {
    final fence = line.trimLeft().startsWith('```');
    if (!fenced && line.trim().isEmpty) {
      blank = true;
      continue;
    }
    final item = !fenced && _listLine.hasMatch(line);
    // An indented line under an item belongs to it.
    final continues = wasItem && !item && line.startsWith('  ');
    if (!fenced && !fence) {
      line = line
          .replaceAllMapped(_boldRoundLink, (m) => m[1]!)
          .replaceAllMapped(_boldInLink, (m) => '[${m[1]}]');
    }
    if (out.isNotEmpty) {
      final gap = !fenced &&
          !continues &&
          !(item && wasItem) &&
          (blank || item != wasItem);
      out.write(gap ? '\n\n' : '\n');
    }
    if (fence) fenced = !fenced;
    blank = false;
    wasItem = item || continues;
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
          await Clipboard.setData(
              ClipboardData(text: withoutChartLinks(widget.text)));
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
