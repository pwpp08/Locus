// The deck of daily cards under Home's dials (home_daily_cards.dart decides
// which). The top card follows the finger sideways with a little tilt; a
// flick or a long enough drag throws it off, anything less springs it back.
// The card beneath rises into its place as the top one leaves, and the deck's
// height follows. The badge in the corner puts the top card away the same way.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../grammar.dart' show Pressable, SideDrag, panelDecoration;
import '../../theme.dart';
import '../../ui2.dart' show LucideIcons;
import 'home_daily_cards.dart';

/// How far the card beneath shows under the top one, and how much narrower
/// it sits on each side (measured off the reference: ~11 and ~14 pt).
const _peek = S.x2 + S.half;
const _inset = S.x3;

/// A throw: this fast (px/s) away from rest, or this share of the width.
const _flingSpeed = 700.0;
const _throwShare = .35;

/// The top card's tilt at a full width of travel, radians (~6°).
const _tilt = .1;

/// The spring a card returns to rest on: quick, with a hint of overshoot.
final _spring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 420,
  ratio: .78,
);

class DailyCardDeck extends StatefulWidget {
  final List<DailyCard> cards;

  /// The local day the cards are for: a card put away is remembered against
  /// it. Null remembers nothing (the gallery).
  final String? day;

  const DailyCardDeck({super.key, required this.cards, this.day});

  @override
  State<DailyCardDeck> createState() => _DailyCardDeckState();
}

class _DailyCardDeckState extends State<DailyCardDeck>
    with SingleTickerProviderStateMixin {
  /// The top card's sideways offset, px. Unbounded: it runs past the edge.
  late final _x = AnimationController.unbounded(vsync: this);
  late Set<String> _gone = widget.day == null
      ? {}
      : dismissedCardsOn(widget.day!);
  DailyCardKind? _leaving;
  double _width = 1;

  List<DailyCard> get _live => [
    for (final card in widget.cards)
      if (!_gone.contains(card.kind.name)) card,
  ];

  @override
  void didUpdateWidget(DailyCardDeck old) {
    super.didUpdateWidget(old);
    if (widget.day != old.day) {
      _gone = widget.day == null ? {} : dismissedCardsOn(widget.day!);
    }
  }

  @override
  void dispose() {
    _x.dispose();
    super.dispose();
  }

  /// A finger lands: catch the card wherever its spring has it.
  void _grab() {
    if (_leaving == null) _x.stop();
  }

  void _drag(double dx) {
    if (_leaving == null) _x.value += dx;
  }

  void _release(double v) {
    if (_leaving != null) return;
    final x = _x.value;
    final flick = v.abs() >= _flingSpeed && (x == 0 || v.sign == x.sign);
    if (flick || x.abs() >= _width * _throwShare) {
      _throw(flick ? v.sign : x.sign, v);
    } else if (!Motion.enabled(context)) {
      _x.value = 0;
    } else {
      _x.animateWith(SpringSimulation(_spring, x, 0, v));
    }
  }

  /// Send the top card off to [dir] (±1), leaving at the finger's speed [v].
  void _throw(double dir, double v) {
    final top = _live.firstOrNull;
    if (top == null || _leaving != null) return;
    _leaving = top.kind;
    if (widget.day != null) dismissCardOn(widget.day!, top.kind);
    HapticFeedback.selectionClick();
    final to = dir * _width * 1.3;
    // easeOutCubic sets off at three times its mean speed; matching that to
    // the finger keeps the throw from lurching or stalling as it lets go.
    final ms = 3 * (to - _x.value).abs() / math.max(v.abs(), 1) * 1000;
    final slow = Motion.slow.inMilliseconds;
    final share = (ms / slow).clamp(Motion.fast.inMilliseconds / slow, 1.0);
    _x
        .animateTo(
          to,
          duration: motion(context, Motion.slow * share),
          curve: Ease.standard,
        )
        .whenCompleteOrCancel(() {
          if (!mounted) return;
          setState(() {
            _gone = {..._gone, top.kind.name};
            _leaving = null;
            _x.value = 0;
          });
        });
  }

  @override
  Widget build(BuildContext c) {
    final live = _live;
    return LayoutBuilder(
      builder: (c, box) {
        _width = math.max(1, box.maxWidth);
        return AnimatedBuilder(
          animation: _x,
          builder: (c, _) => _deck(c, live),
        );
      },
    );
  }

  /// [child]'s size eased, or as it is under reduced motion (an AnimatedSize
  /// of no duration asks for layout from inside layout).
  Widget _eased(BuildContext c, Widget child) => Motion.enabled(c)
      ? AnimatedSize(
          duration: Motion.slow,
          curve: Ease.standard,
          alignment: Alignment.topCenter,
          child: child,
        )
      : child;

  Widget _deck(BuildContext c, List<DailyCard> live) {
    final n = live.length;
    final x = _x.value;
    final t = (x.abs() / _width).clamp(0.0, 1.0);
    // How far the card beneath has risen into the top card's place.
    final rise = Ease.standard.transform(math.min(1, t / .6));
    final rest = 1 - 2 * _inset / _width;
    final peek = n > 2 ? _peek : (n == 2 ? _peek * (1 - rise) : 0.0);

    Widget layer(DailyCard card, int depth) {
      final top = depth == 0;
      final scale = switch (depth) {
        0 => 1.0,
        1 => lerpDouble(rest, 1, rise)!,
        _ => rest,
      };
      final dy = depth == 0 ? 0.0 : (depth == 1 ? _peek * (1 - rise) : _peek);
      final ground = switch (depth) {
        0 => 1 - ((t - .45) / .55).clamp(0.0, 1.0),
        1 => lerpDouble(.55, 1, rise)!,
        _ => .55 * rise,
      };
      final face = DailyCardFace(
        card,
        count: n,
        content: depth == 0 ? 1 : (depth == 1 ? rise : 0),
        onDone: top ? () => _throw(1, 0) : null,
      );
      return Positioned.fill(
        key: ValueKey(card.kind),
        top: S.x4,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.translationValues(top ? x : 0, dy, 0)
            ..rotateZ(top ? x / _width * _tilt : 0)
            ..scaleByDouble(scale, scale, 1, 1),
          child: Opacity(
            opacity: ground,
            child: IgnorePointer(
              ignoring: !top || _leaving != null,
              child: ExcludeSemantics(
                excluding: !top,
                child: SideDrag(
                  onStart: _grab,
                  onDrag: _drag,
                  onRelease: _release,
                  child: face,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // The deck is as tall as its tallest card. The sizer lays every card out
    // unseen; its size eases, and the visible cards fill it, so a shorter card
    // coming up, or the last one going, glides instead of jumping.
    return Padding(
      padding: EdgeInsets.only(bottom: peek),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _eased(
            c,
            n == 0
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: S.x4),
                    child: Stack(
                      children: [
                        for (final card in live)
                          Visibility(
                            visible: false,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: DailyCardFace(card, count: n),
                          ),
                      ],
                    ),
                  ),
          ),
          for (var i = math.min(n, 3) - 1; i >= 0; i--)
            if (i < 2 || t > 0) layer(live[i], i),
        ],
      ),
    );
  }
}

/// One daily card: the title and its sentence, a week of bars when the card
/// has them, and the badge that puts it away with the count of cards left.
class DailyCardFace extends StatelessWidget {
  final DailyCard card;
  final int count;

  /// How much of the words, bars and badge show (the card beneath fades its
  /// in as it rises).
  final double content;

  /// The badge's tap. Null on a card that is not on top.
  final VoidCallback? onDone;

  const DailyCardFace(
    this.card, {
    super.key,
    required this.count,
    this.content = 1,
    this.onDone,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final bars = card.bars;
    // Clamped like the tab labels: a badge that grew with the words would
    // sit on top of them.
    final badge = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        constraints: const BoxConstraints(
          minWidth: S.x6,
          minHeight: S.x12 - S.half,
        ),
        padding: const EdgeInsets.symmetric(vertical: S.x1),
        decoration: BoxDecoration(
          color: p.ink.withValues(alpha: .1),
          borderRadius: R.rSm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.check, size: I.sm, color: p.ink),
            const SizedBox(height: S.x1),
            AnimatedSwitcher(
              duration: motion(c, Motion.base),
              switchInCurve: Ease.standard,
              switchOutCurve: Ease.standard,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .6),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: Text(
                '$count',
                key: ValueKey(count),
                style: F.num(F.body).copyWith(color: p.ink2, height: 1),
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      width: double.infinity,
      decoration: panelDecoration(c),
      child: Opacity(
        opacity: content.clamp(0.0, 1.0),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                S.x5,
                S.x5,
                S.x2 + S.x6 + S.x5,
                S.x5,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.title,
                            style: F.head.copyWith(color: p.ink),
                          ),
                          const SizedBox(height: S.half),
                          Text(
                            card.body,
                            style: F.body.copyWith(
                              color: p.ink2,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (bars != null) ...[
                      const SizedBox(width: S.x4),
                      ExcludeSemantics(
                        // The sentence beside it says the numbers.
                        child: CustomPaint(
                          size: const Size(S.x16, S.x12),
                          painter: _WeekBars(
                            bars,
                            card.barMax,
                            p.ink.withValues(alpha: .22),
                            card.lit ?? p.ink,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              top: S.x2,
              right: S.x2,
              child: Pressable(
                onTap: onDone,
                semanticLabel:
                    'Put away: ${card.title}. $count '
                    '${count == 1 ? 'card' : 'cards'} today',
                child: badge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A week of bars from the foot, the last one lit; a day with nothing stored
/// is left empty.
class _WeekBars extends CustomPainter {
  final List<double?> values;
  final double? max;
  final Color base, lit;
  _WeekBars(this.values, this.max, this.base, this.lit);

  @override
  void paint(Canvas canvas, Size size) {
    final top =
        max ??
        values.whereType<double>().fold<double>(0, (a, b) => math.max(a, b));
    if (top <= 0 || values.isEmpty) return;
    const gap = S.x1;
    final w = (size.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null || v <= 0) continue;
      final h = math.max(w, size.height * (v / top).clamp(0.0, 1.0));
      final r = Rect.fromLTWH(i * (w + gap), size.height - h, w, h);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          r,
          topLeft: const Radius.circular(R.sm / 3),
          topRight: const Radius.circular(R.sm / 3),
        ),
        Paint()..color = i == values.length - 1 ? lit : base,
      );
    }
  }

  @override
  bool shouldRepaint(_WeekBars o) =>
      o.values != values || o.max != max || o.base != base || o.lit != lit;
}
