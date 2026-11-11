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

/// The air over the deck and under it.
const _above = S.x6;
const _below = S.x5;

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
        top: _above,
        bottom: _below,
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
                    padding: const EdgeInsets.only(top: _above, bottom: _below),
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

/// One daily card: the title and its sentence, a picture if it is one of the
/// few that earn one, and the badge that puts it away with the count left.
class DailyCardFace extends StatelessWidget {
  final DailyCard card;
  final int count;

  /// How much of the words, picture and badge show (the card beneath fades its
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
    final art = _artOf(card);
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
      decoration: panelDecoration(c).copyWith(
        boxShadow: const [
          BoxShadow(
            color: DC.cardHalo,
            blurRadius: S.x5,
            spreadRadius: S.hair,
          ),
        ],
      ),
      child: Opacity(
        opacity: content.clamp(0.0, 1.0),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                S.x5,
                art?.pad ?? S.x5,
                art?.right ?? S.x12 + S.x2,
                art?.pad ?? S.x5,
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
                            style: F.dBody.copyWith(color: p.ink),
                          ),
                          SizedBox(height: art == null ? S.half : S.x1),
                          Text(
                            card.body,
                            style: (art == null ? PH.cardWords : PH.cardBody)
                                .copyWith(color: p.ink2),
                          ),
                        ],
                      ),
                    ),
                    if (art != null) ...[
                      SizedBox(width: art.gap),
                      art.picture,
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

/// A picture beside a card's words: how far it stands from them and from the
/// card's right edge, and the air above and below it.
typedef _Art = ({Widget picture, double gap, double right, double pad});

/// Most cards are only words. A picture is kept for what is rare: a record, a
/// turn in the week's recovery, a goal reached.
_Art? _artOf(DailyCard card) {
  _Art coin(IconData icon) => (
    picture: _Coin(icon),
    gap: S.x4,
    right: S.x10 + S.x1 + S.hair,
    pad: S.x5,
  );
  return switch (card.kind) {
    DailyCardKind.hrvBest => coin(LucideIcons.activity),
    DailyCardKind.rhrLowest => coin(LucideIcons.heartPulse),
    DailyCardKind.firstRed || DailyCardKind.backToGreen when card.bars != null => (
      picture: _WeekBars(card.bars!, card.lit ?? C.recRed),
      gap: S.x6 + S.x1,
      right: S.x12 + S.x1,
      pad: S.x6 + S.hair,
    ),
    DailyCardKind.targetMet ||
    DailyCardKind.stepGoal ||
    DailyCardKind.targetReached ||
    DailyCardKind.stepGoalToday => (
      picture: const _Box(),
      gap: S.x5,
      right: S.x12 + S.x2 + S.hair,
      pad: S.x5,
    ),
    _ => null,
  };
}

/// A week of recovery as slabs coming toward you: each a little wider and
/// lower than the last, today's in its colour. A day with no score has no slab.
class _WeekBars extends StatelessWidget {
  final List<double?> values;
  final Color lit;
  const _WeekBars(this.values, this.lit);

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
    child: CustomPaint(
      size: _WeekBarsPaint.size,
      painter: _WeekBarsPaint(values, lit),
    ),
  );
}

class _WeekBarsPaint extends CustomPainter {
  final List<double?> values;
  final Color lit;
  _WeekBarsPaint(this.values, this.lit);

  static const size = Size(83, 92);

  // Seven slabs, measured off the reference, oldest first.
  static const _left = [0.0, 10.5, 21.0, 32.6, 44.7, 57.7, 71.8];
  static const _wide = [6.1, 6.3, 7.6, 7.7, 8.9, 10.3, 11.2];
  static const _foot = [76.5, 78.5, 80.5, 83.0, 85.8, 89.0, 91.0];

  /// A score of 100, and how far each foot leans down to the right.
  static const _full = 86.0;
  static const _lean = .12;

  @override
  void paint(Canvas canvas, Size _) {
    final today = values.length - 1;
    for (var i = 0; i < values.length && i < _left.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = _left[i], w = _wide[i], foot = _foot[i];
      final top = foot - math.max(w, _full * (v / 100).clamp(0.0, 1.0));
      final drop = w * _lean;
      const r = S.half;
      final slab = Path()
        ..moveTo(x, top + r)
        ..quadraticBezierTo(x, top, x + r, top)
        ..lineTo(x + w - r, top)
        ..quadraticBezierTo(x + w, top, x + w, top + r)
        ..lineTo(x + w, foot + drop)
        ..lineTo(x, foot - drop)
        ..close();
      final box = slab.getBounds();
      canvas.drawPath(
        slab,
        Paint()
          ..shader = LinearGradient(
            colors: i == today
                ? [
                    Color.lerp(lit, DC.coinEdgeLo, .2)!,
                    Color.lerp(lit, DC.coinEdgeLo, .35)!,
                  ]
                : const [DC.barEdge, DC.barFace, DC.barSide],
          ).createShader(box),
      );
    }
  }

  @override
  bool shouldRepaint(_WeekBarsPaint o) => o.values != values || o.lit != lit;
}

/// A box with its lid slid back and the light coming out of it: a goal reached.
class _Box extends StatelessWidget {
  const _Box();

  @override
  Widget build(BuildContext c) => ExcludeSemantics(
    child: CustomPaint(size: _BoxPaint.size, painter: const _BoxPaint()),
  );
}

class _BoxPaint extends CustomPainter {
  const _BoxPaint();

  static const size = Size(76, 74);

  // The corners, measured off the reference.
  static const _backLeft = Offset(0, 17.5);
  static const _lowLeft = Offset(0, 48.7);
  static const _foot = Offset(24.5, 73.5);
  static const _lowRight = Offset(66.4, 61.7);
  static const _highRight = Offset(66.4, 32.2);
  static const _seam = Offset(33.4, 38.1);
  static const _ledge = Offset(24, 41);
  static const _lid = [
    Offset(9.8, 6.8),
    Offset(49.3, 0),
    Offset(73.3, 25.1),
    Offset(34, 32.8),
  ];
  static const _lidDeep = 5.6;
  static const _slot = [
    Offset(3.3, 17.5),
    Offset(12.2, 15.7),
    _seam,
    _ledge,
  ];

  Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  @override
  void paint(Canvas canvas, Size _) {
    // Inside, seen past the lid, with the strip of light down it.
    canvas.drawPath(
      _poly(const [_backLeft, Offset(12.2, 15.7), _seam, _ledge, _lowLeft]),
      Paint()..color = DC.boxInner,
    );
    canvas.drawPath(
      _poly(const [Offset(0, 39), _ledge, _seam, Offset(24, 41.8), _lowLeft]),
      Paint()..color = DC.boxLedge,
    );
    final slot = _poly(_slot);
    canvas.drawPath(
      slot,
      Paint()
        ..color = DC.boxGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, S.x1),
    );
    canvas.drawPath(
      slot,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DC.boxGlow, DC.boxGlowHi],
        ).createShader(slot.getBounds()),
    );
    // The two faces toward you.
    final front = _poly(const [
      _lowLeft,
      _foot,
      _lowRight,
      _highRight,
      _seam,
      _ledge,
    ]);
    canvas.drawPath(front, Paint()..color = DC.boxFront);
    // The lid: its edge, then its top with the mark struck into it.
    final deep = const Offset(0, _lidDeep);
    canvas.drawPath(
      _poly([_lid[3], _lid[2], _lid[2] + deep, _lid[3] + deep]),
      Paint()..color = DC.boxLidEdge,
    );
    final lid = _poly(_lid);
    canvas.drawPath(
      lid,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DC.boxLidHi, DC.boxLidLo],
        ).createShader(lid.getBounds()),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(42.2, 15.3), width: 26, height: 14.6),
      Paint()
        ..color = DC.boxInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = S.hair * .8,
    );
  }

  @override
  bool shouldRepaint(_BoxPaint o) => false;
}

/// A metal coin, seen a little from the side: a thick dark edge, a brushed
/// face with a gold rim, and the record's mark struck into it.
class _Coin extends StatelessWidget {
  final IconData icon;
  const _Coin(this.icon);
  static const _size = Size(S.x16 + S.x2 + S.x1, S.x16 + S.x4 + S.hair);

  /// Where the face sits in the coin's box, and how far it leans.
  static const _face = Offset(S.x8 + S.hair, S.x10 + S.hair / 2);
  static const _lean = .16;

  @override
  Widget build(BuildContext c) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: _size,
        painter: _CoinPaint(PH.gold),
        child: SizedBox.fromSize(
          size: _size,
          child: Stack(
            children: [
              Positioned(
                left: _face.dx - I.xl / 2,
                top: _face.dy - I.xl / 2,
                child: Transform.rotate(
                  angle: _lean,
                  child: Icon(
                    icon,
                    size: I.xl,
                    color: DC.coinInk,
                    shadows: const [
                      Shadow(
                        color: DC.coinShine,
                        offset: Offset(S.hair * .8, S.hair * .8),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinPaint extends CustomPainter {
  final Color rim;
  _CoinPaint(this.rim);

  static const _rx = 31.0, _ry = 38.0;
  static const _depth = 9;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(_Coin._face.dx, _Coin._face.dy);
    canvas.rotate(_Coin._lean);
    Rect oval(double inset, [Offset at = Offset.zero]) => Rect.fromCenter(
      center: at,
      width: (_rx - inset) * 2,
      height: (_ry - inset) * 2,
    );

    canvas.drawOval(
      oval(-S.x1, const Offset(S.x2, S.x1)),
      Paint()
        ..color = DC.coinShade
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, S.x2 - S.hair),
    );
    // The edge: the face's outline repeated back to the right.
    for (var i = _depth; i >= 1; i--) {
      canvas.drawOval(
        oval(0, Offset(i * 1.15, i * .2)),
        Paint()
          ..color = Color.lerp(DC.coinEdgeHi, DC.coinEdgeLo, i / _depth)!,
      );
    }
    final face = oval(0);
    canvas.drawOval(
      face,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DC.coinHi, DC.coinLo],
        ).createShader(face),
    );
    canvas.drawOval(
      oval(S.hair / 2 + .3),
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // The sunk middle: shaded the other way, its lip caught by the light.
    final well = oval(S.x2 - S.hair);
    canvas.drawOval(
      well,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DC.coinLo, DC.coinHi],
        ).createShader(well),
    );
    canvas.drawOval(
      well,
      Paint()
        ..color = DC.coinShade
        ..style = PaintingStyle.stroke
        ..strokeWidth = S.hair,
    );
  }

  @override
  bool shouldRepaint(_CoinPaint o) => o.rim != rim;
}
