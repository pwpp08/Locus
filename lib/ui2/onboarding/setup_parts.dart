// The setup pages' parts, laid out on their reference (480 px across =
// 393 dp): a back chevron, a picture on the left, a headline and a line under
// it, the page's own controls, and at the foot the word NEXT beside a ring
// whose blue arc is how far through setup the person is. Settings' profile
// editors stand on the same frame, with SAVE.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/dial_parts.dart' show kDialGround;
import '../ui2.dart';

/// The page's side margin: 20 px of 480.
const kSetupMargin = S.x4;

/// One setup page.
class SetupFrame extends StatelessWidget {
  final Widget? picture;
  final String title;
  final String? body;
  final List<Widget> children;

  /// How far through setup, 0–1, drawn round the NEXT ring.
  final double progress;

  /// Null while the page cannot go on: the word and the arrow go grey.
  final VoidCallback? onNext;

  /// Null shows no chevron.
  final VoidCallback? onBack;

  /// NEXT, SAVE or FINISH.
  final String action;

  /// FINISH: a mint disc with a tick instead of the ring.
  final bool finish;

  /// The room between the chevron's row and the picture: each reference
  /// page sets its picture at its own height.
  final double pictureTop;

  /// The room between the picture and the headline.
  final double titleGap;

  const SetupFrame({
    super.key,
    required this.title,
    this.picture,
    this.body,
    this.children = const [],
    this.progress = 0,
    this.onNext,
    this.onBack,
    this.action = 'NEXT',
    this.finish = false,
    this.pictureTop = S.x16 + S.x8 + S.x1 - S.half,
    this.titleGap = S.x8,
  });

  /// The screen height the reference gaps were drawn for. A shorter one gives
  /// up the room above the picture first.
  static const _drawnFor = S.x16 * 12;

  @override
  Widget build(BuildContext c) {
    // With the keyboard up there is no room for the picture.
    final typing = MediaQuery.viewInsetsOf(c).bottom > 0;
    return Scaffold(
      backgroundColor: DC.bgFoot,
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: kDialGround,
        child: SafeArea(
          // Never scrolls: what is above the button is set to fit, and shrinks
          // as one piece on a screen too short even with the gaps closed.
          child: LayoutBuilder(builder: (c, box) {
            final short = math.max(0.0, _drawnFor - box.maxHeight);
            final top = typing ? 0.0 : math.max(S.x2, pictureTop - short);
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                  kSetupMargin, 0, kSetupMargin, S.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: S.x12 + S.x2,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: onBack == null
                          ? null
                          : Pressable(
                              semanticLabel: 'Back',
                              onTap: onBack,
                              child: SizedBox.square(
                                dimension: S.tap,
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        start: S.x3),
                                    child: Icon(LucideIcons.chevronLeft,
                                        size: I.xl, color: DC.pure),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (c, room) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: room.maxWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // The same three slots with the keyboard up,
                              // so a field below keeps its focus.
                              if (picture case final pic?) ...[
                                SizedBox(height: top),
                                Offstage(
                                  offstage: typing,
                                  child: Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: pic),
                                ),
                                SizedBox(
                                    height: typing
                                        ? 0
                                        : math.max(
                                            S.x3,
                                            titleGap -
                                                math.max(0.0,
                                                    short - pictureTop))),
                              ],
                              Semantics(
                                header: true,
                                child: Text(title,
                                    style: OB.title.copyWith(color: DC.pure)),
                              ),
                              if (body case final b?) ...[
                                const SizedBox(height: S.x2),
                                Text(b,
                                    style: OB.body.copyWith(color: OB.sub)),
                              ],
                              ...children,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x3),
                  SetupNext(
                    label: action,
                    progress: progress,
                    onTap: onNext,
                    finish: finish,
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// The word and the ring at a setup page's foot.
class SetupNext extends StatelessWidget {
  final String label;
  final double progress;
  final VoidCallback? onTap;
  final bool finish;

  const SetupNext({
    super.key,
    required this.label,
    this.progress = 0,
    this.onTap,
    this.finish = false,
  });

  /// The ring's side: 95 px of 480.
  static const side = S.x16 + S.x3 + S.half;

  @override
  Widget build(BuildContext c) {
    final on = onTap != null;
    final ink = on ? DC.pure : OB.off;
    return Pressable(
      onTap: onTap,
      // "Next", not "NEXT": a screen reader spells capitals out.
      semanticLabel: label.isEmpty
          ? label
          : label[0] + label.substring(1).toLowerCase(),
      child: ExcludeSemantics(
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text(label, style: OB.button.copyWith(color: ink)),
        const SizedBox(width: S.x4),
        SizedBox.square(
          dimension: side,
          child: finish
              ? Container(
                  margin: const EdgeInsets.all(S.x1),
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: OB.finish),
                  child: const Icon(LucideIcons.check,
                      size: I.xl, color: OB.finishInk),
                )
              : CustomPaint(
                  painter: _RingPainter(progress.clamp(0, 1)),
                  child: Center(
                    child: Icon(LucideIcons.arrowRight,
                        size: I.xl, color: ink),
                  ),
                ),
        ),
        const SizedBox(width: S.x3),
      ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  const _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const w = S.x2 - S.hair;
    final r = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    canvas.drawOval(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = OB.track);
    if (progress <= 0) return;
    canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = OB.progress);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// A field's name in tracked capitals, over the field.
class SetupLabel extends StatelessWidget {
  final String text;
  const SetupLabel(this.text, {super.key});

  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(left: S.x1, bottom: S.x2),
        child: Text(text.toUpperCase(),
            style: OB.caps.copyWith(color: OB.label)),
      );
}

/// A typed answer: a dark well with a faint edge, the words inset.
class SetupField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final TextCapitalization capital;
  final TextInputAction action;

  const SetupField(
    this.controller, {
    super.key,
    required this.label,
    this.onChanged,
    this.capital = TextCapitalization.words,
    this.action = TextInputAction.next,
  });

  @override
  Widget build(BuildContext c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SetupLabel(label),
          Container(
            height: S.x10 + S.half + S.hair,
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: OB.field,
              borderRadius: R.rLg,
              border: Border.all(color: OB.fieldEdge, width: S.hair),
            ),
            child: AppField(
              controller: controller,
              bare: true,
              semanticLabel: label,
              textCapitalization: capital,
              textInputAction: action,
              autocorrect: false,
              onChanged: onChanged,
              textStyle: OB.input.copyWith(color: DC.pure),
            ),
          ),
        ],
      );
}

/// The choices one under another: grey, the chosen one white.
class SetupChoices extends StatelessWidget {
  final List<String> labels;
  final int? chosen;
  final ValueChanged<int> onChoose;

  const SetupChoices(this.labels,
      {super.key, required this.chosen, required this.onChoose});

  @override
  Widget build(BuildContext c) => Column(children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(height: S.x3 + S.hair),
          Semantics(
            selected: i == chosen,
            button: true,
            child: Pressable(
              onTap: () => onChoose(i),
              semanticLabel: labels[i],
              child: AnimatedContainer(
                duration: motion(c, Motion.fast),
                height: S.x12 + S.x2 - S.hair,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == chosen ? OB.chosen : OB.choice,
                  borderRadius: R.rLg,
                ),
                child: Text(labels[i].toUpperCase(),
                    style: OB.button.copyWith(
                        color: i == chosen ? OB.chosenInk : DC.pure)),
              ),
            ),
          ),
        ],
      ]);
}

/// Two halves in a dark well, the chosen one lifted: IMPERIAL / METRIC.
class SetupSegments extends StatelessWidget {
  final List<String> labels;
  final int chosen;
  final ValueChanged<int> onChoose;

  const SetupSegments(this.labels,
      {super.key, required this.chosen, required this.onChoose});

  @override
  Widget build(BuildContext c) => Container(
        height: S.x12 - S.half,
        // Sides only: each half takes taps down the well's whole height.
        padding: const EdgeInsets.symmetric(horizontal: S.x1),
        decoration: const BoxDecoration(color: OB.well, borderRadius: R.rLg),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == chosen,
                button: true,
                child: Pressable(
                  onTap: () => onChoose(i),
                  semanticLabel: labels[i],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x1),
                    child: AnimatedContainer(
                      duration: motion(c, Motion.fast),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == chosen ? OB.wellOn : null,
                        borderRadius: R.rMd,
                      ),
                      child: Text(labels[i].toUpperCase(),
                          style: OB.button.copyWith(
                              color: i == chosen ? DC.pure : OB.sub)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// One column of a wheel: the rows turn on a drum and fade at its edges.
class SetupWheel extends StatefulWidget {
  final int count;
  final int initial;
  final String Function(int i) label;
  final ValueChanged<int> onChanged;
  final double width;
  final double rowHeight;
  final TextStyle on, off;
  final TextAlign align;

  /// The drum's diameter over the wheel's height: smaller turns the far
  /// rows away faster.
  final double drum;

  /// Days and months come round again; years do not.
  final bool loop;

  /// How tightly the rows sit round the drum: above 1 packs them closer,
  /// as the reference's wheels do.
  final double squeeze;

  const SetupWheel({
    super.key,
    required this.count,
    required this.initial,
    required this.label,
    required this.onChanged,
    required this.width,
    this.rowHeight = S.x8 - S.half,
    this.on = OB.wheelOn,
    this.off = OB.wheel,
    this.align = TextAlign.center,
    this.drum = 1,
    this.loop = false,
    this.squeeze = 1,
  });

  @override
  State<SetupWheel> createState() => _SetupWheelState();
}

class _SetupWheelState extends State<SetupWheel> {
  late final _ctl = FixedExtentScrollController(initialItem: widget.initial);
  late int _at = widget.initial;

  @override
  void didUpdateWidget(SetupWheel old) {
    super.didUpdateWidget(old);
    // A switch of units moves the wheel to the same body in the new unit.
    // Not when the page hands back the row the wheel is already on: a jump
    // then stops the fling after every notch.
    if (old.count != widget.count || widget.initial != _at) {
      _at = widget.initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ctl.hasClients) _ctl.jumpToItem(widget.initial);
      });
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Widget _row(int i) => Center(
        child: SizedBox(
          width: widget.width,
          child: Text(
            widget.label(i),
            textAlign: widget.align,
            maxLines: 1,
            style: i == _at
                ? widget.on.copyWith(color: DC.pure)
                : widget.off.copyWith(color: OB.wheelInk),
          ),
        ),
      );

  @override
  Widget build(BuildContext c) => SizedBox(
        width: widget.width,
        child: ListWheelScrollView.useDelegate(
          controller: _ctl,
          itemExtent: widget.rowHeight,
          diameterRatio: widget.drum,
          squeeze: widget.squeeze,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (i) {
            final at = i % widget.count;
            setState(() => _at = at);
            HapticFeedback.selectionClick();
            widget.onChanged(at);
          },
          childDelegate: widget.loop
              ? ListWheelChildLoopingListDelegate(children: [
                  for (var i = 0; i < widget.count; i++) _row(i),
                ])
              : ListWheelChildBuilderDelegate(
                  childCount: widget.count,
                  builder: (_, i) => _row(i),
                ),
        ),
      );
}

/// Wheels side by side over their band, faded top and bottom.
class SetupWheels extends StatelessWidget {
  final double height;
  final List<Widget> wheels;

  /// The bands behind the chosen row, as (left, width) in the row; one band
  /// across all of it when empty.
  final List<(double, double)> bands;
  final double bandHeight;
  final BorderRadius bandRadius;

  const SetupWheels({
    super.key,
    required this.height,
    required this.wheels,
    this.bands = const [],
    this.bandHeight = S.x8 + S.half,
    this.bandRadius = R.rPill,
  });

  @override
  Widget build(BuildContext c) => SizedBox(
        height: height,
        child: Stack(children: [
          for (final (left, width) in bands)
            Positioned(
              left: left,
              width: width,
              top: (height - bandHeight) / 2,
              height: bandHeight,
              child: DecoratedBox(
                decoration:
                    BoxDecoration(color: OB.band, borderRadius: bandRadius),
              ),
            ),
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [OB.fadeOut, OB.fadeIn, OB.fadeIn, OB.fadeOut],
                stops: [.06, .36, .64, .94],
              ).createShader(r),
              child: Row(children: wheels),
            ),
          ),
        ]),
      );
}

/// Two hands meeting high, in the pictures' metal, three blue sparks round
/// the touch: the welcome. Decorative.
class ClapPicture extends StatelessWidget {
  const ClapPicture({super.key});

  @override
  Widget build(BuildContext c) => const ExcludeSemantics(
        child: CustomPaint(
            size: Size(S.x16 + S.x3, S.x16 + S.x10 - S.x2),
            painter: _ClapPainter()),
      );
}

class _ClapPainter extends CustomPainter {
  const _ClapPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Offset at(double x, double y) => Offset(x * w, y * h);

    // The sparks round the fingertips.
    final spark = Paint()
      ..color = OB.lit
      ..strokeWidth = w * .028
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in [
      (at(.30, .07), at(.27, .01)),
      (at(.50, .05), at(.51, -.01)),
      (at(.16, .14), at(.10, .11)),
      (at(.66, .12), at(.72, .08)),
      (at(.70, .30), at(.77, .29)),
      (at(.73, .42), at(.80, .44)),
    ]) {
      canvas.drawLine(a, b, spark);
    }

    // Each hand: a long mitten of a palm, a thumb, a cuff at the wrist.
    void hand(bool back) {
      canvas.save();
      canvas.translate(at(.42, .55).dx, at(.42, .55).dy);
      canvas.rotate(back ? .22 : -.10);
      final dx = back ? w * .09 : -w * .03;
      final palm = RRect.fromRectAndCorners(
        Rect.fromLTWH(dx - w * .17, -h * .48, w * .34, h * .62),
        topLeft: Radius.circular(w * .17),
        topRight: Radius.circular(w * .17),
        bottomLeft: Radius.circular(w * .06),
        bottomRight: Radius.circular(w * .06),
      );
      final shade = back ? OB.metalDark : OB.metal;
      canvas.drawRRect(
          palm,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: back
                  ? const [OB.metalDark, OB.metalDeep]
                  : const [OB.metalLit, OB.metal],
            ).createShader(palm.outerRect));
      // The fingers' seams.
      final seam = Paint()
        ..color = OB.metalDeep.withValues(alpha: .55)
        ..strokeWidth = w * .012;
      for (final f in [-.06, .02, .10]) {
        canvas.drawLine(Offset(dx + w * f, -h * .44),
            Offset(dx + w * f, -h * .26), seam);
      }
      // The thumb, folded against the palm.
      final thumb = RRect.fromRectAndRadius(
          Rect.fromLTWH(dx - w * (back ? .02 : .26), -h * .14, w * .16, h * .22),
          Radius.circular(w * .08));
      canvas.drawRRect(thumb, Paint()..color = shade);
      // The cuff.
      final cuff = RRect.fromRectAndRadius(
          Rect.fromLTWH(dx - w * .19, h * .12, w * .38, h * .18),
          Radius.circular(w * .05));
      canvas.drawRRect(
          cuff, Paint()..color = back ? OB.metalDeep : OB.metalDark);
      canvas.drawLine(
          Offset(dx - w * .13, h * .19),
          Offset(dx - w * .02, h * .19),
          Paint()
            ..color = OB.metalLit
            ..strokeWidth = w * .02
            ..strokeCap = StrokeCap.round);
      canvas.restore();
    }

    hand(true);
    hand(false);
  }

  @override
  bool shouldRepaint(_ClapPainter old) => false;
}

/// A clipboard tilted on the page, a face in its corner and four blue rows
/// of answers: the questions about the person. Decorative.
class ClipboardPicture extends StatelessWidget {
  const ClipboardPicture({super.key});

  @override
  Widget build(BuildContext c) => const ExcludeSemantics(
        child: CustomPaint(
            size: Size(S.x16 + S.x3, S.x16 + S.x8 - S.half),
            painter: _ClipboardPainter()),
      );
}

class _ClipboardPainter extends CustomPainter {
  const _ClipboardPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-.16);
    canvas.translate(-w / 2, -h / 2);

    // The board's edge, then its face.
    final edge = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .17, h * .10, w * .70, h * .84),
        Radius.circular(w * .06));
    canvas.drawRRect(edge.shift(Offset(w * .04, h * .025)),
        Paint()..color = OB.metalDeep);
    canvas.drawRRect(
        edge,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [OB.metal, OB.metalDark],
          ).createShader(edge.outerRect));

    // The clip.
    final clip = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .40, h * .045, w * .24, h * .10),
        Radius.circular(w * .03));
    canvas.drawRRect(clip, Paint()..color = OB.metalDeep);
    canvas.drawCircle(Offset(w * .52, h * .045), w * .045,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .022
          ..color = OB.metalDeep);

    // The face in the corner, and the line beside it.
    final face = Offset(w * .34, h * .30);
    canvas.drawCircle(face, w * .10, Paint()..color = OB.metalDark);
    canvas.drawCircle(face.translate(0, -h * .02), w * .035,
        Paint()..color = OB.metalLit);
    final grey = Paint()
      ..color = OB.metalLit.withValues(alpha: .7)
      ..strokeWidth = h * .035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * .50, h * .26), Offset(w * .74, h * .26), grey);
    canvas.drawLine(Offset(w * .50, h * .33), Offset(w * .68, h * .33), grey);

    // The four rows of answers: blue ticks, grey lines.
    final blue = Paint()
      ..color = OB.lit
      ..strokeWidth = h * .045
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = h * (.47 + i * .095);
      canvas.drawLine(Offset(w * .30, y), Offset(w * .42, y), blue);
      canvas.drawLine(Offset(w * .50, y), Offset(w * (.76 - i % 2 * .06), y),
          grey);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ClipboardPainter old) => false;
}
