// Get Started: the first weeks' cards on Home, laid out on their reference.
// Each card is a title, two or three lines, a violet way in and a picture on
// the right; the first one stands out on a warm ground in a warm-to-violet
// rim. A card goes once its way in has been taken, and the section with the
// last of them.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../state/prefs.dart';
import '../../ui2.dart';
import '../coach.dart' show openCoachSheet;
import '../home_screen.dart' show go;
import '../journal_compose.dart' show JournalCompose;
import '../sleep_planner.dart' show SleepPlannerScreen;

/// One card's words, picture and what its way in does.
class _Card {
  final String id, title, body, cta;
  final Widget picture;
  final bool featured;
  final void Function(BuildContext c) open;

  /// The picture's side: each is drawn at the size its reference shows it.
  final double side;
  const _Card(this.id, this.title, this.body, this.cta, this.picture,
      this.open, {this.featured = false, this.side = S.x16 + S.x3});
}

/// The Get Started heading and the cards not yet done.
class GetStartedSection extends StatefulWidget {
  const GetStartedSection({super.key});

  /// The pref a card's way in sets once taken.
  static String donePref(String id) => 'get_started.done.$id';

  @override
  State<GetStartedSection> createState() => _GetStartedSectionState();
}

class _GetStartedSectionState extends State<GetStartedSection> {
  static final _cards = [
    _Card(
      'goals',
      'Fit Locus to Your Goals',
      'A few questions for your coach, so its advice is shaped around what '
          'you are after.',
      'GET STARTED',
      const CustomPaint(painter: _PodPainter()),
      (c) => openCoachSheet(c,
          initialMessage: 'Help me set my goals. Ask me a few short '
              'questions about what I want from training, sleep and '
              'recovery, then remember my answers.'),
      featured: true,
    ),
    _Card(
      'charge',
      'Keep It Charged',
      'A full battery lets the band record your whole first day and night.',
      'CHARGING TIPS',
      Image.asset('assets/images/get_started_band.png'),
      _chargingTips,
      side: S.x16 + S.x10 - S.x1,
    ),
    _Card(
      'sleep',
      'Set Up Your Sleep',
      'Tell Locus when you like to sleep and it helps you wind down on time '
          'and wakes you gently.',
      'SET UP SLEEP',
      const CustomPaint(painter: _ClockPainter()),
      (c) => go(c, const SleepPlannerScreen()),
      side: S.x16 + S.x8 - S.x1,
    ),
    _Card(
      'journal',
      'Start Your Journal',
      'Log a few habits each day and see which ones move your sleep and '
          'recovery.',
      'OPEN JOURNAL',
      const CustomPaint(painter: _JournalPainter()),
      (c) => go(c, const JournalCompose()),
    ),
  ];

  bool _done(String id) =>
      Prefs.getBool(GetStartedSection.donePref(id), false);

  @override
  Widget build(BuildContext c) {
    final left = [for (final k in _cards) if (!_done(k.id)) k];
    if (left.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: S.x6, bottom: S.x5),
        child: Semantics(
          header: true,
          child: Text('Get Started', style: GS.head.copyWith(color: DC.pure)),
        ),
      ),
      for (var i = 0; i < left.length; i++) ...[
        if (i > 0) const SizedBox(height: S.x4),
        _CardView(left[i], onOpen: () {
          Prefs.setBool(GetStartedSection.donePref(left[i].id), true);
          left[i].open(c);
          setState(() {});
        }),
      ],
    ]);
  }
}

void _chargingTips(BuildContext c) => AppSheet.show<void>(
      c,
      title: 'Charging tips',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final t in const [
          'Charge the battery pack first, then slide it onto the band while '
              'you wear it — it charges without coming off your wrist.',
          'A full band lasts about four to five days. Top it up when Locus '
              'says the battery is low rather than letting it run out.',
          'Before your first night, give it a full charge so the night is '
              'recorded from start to finish.',
          'If the band will not charge, clean the contacts and seat the pack '
              'again until it clicks.',
        ]) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: S.x1, right: S.x3),
              child: Icon(LucideIcons.batteryCharging,
                  size: I.sm, color: P.of(c).ink2),
            ),
            Expanded(
              child: Text(t,
                  style: F.body.copyWith(
                      color: P.of(c).ink2, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: S.x3),
        ],
      ]),
    );

class _CardView extends StatelessWidget {
  final _Card card;
  final VoidCallback onOpen;
  const _CardView(this.card, {required this.onOpen});

  @override
  Widget build(BuildContext c) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x3, S.x5),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(card.title, style: GS.title.copyWith(color: DC.pure)),
              const SizedBox(height: S.half),
              Text(card.body, style: GS.text.copyWith(color: GS.body)),
              const SizedBox(height: S.x2 + S.half),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(card.cta, style: GS.cta.copyWith(color: GS.link)),
                const SizedBox(width: S.x3),
                const Icon(LucideIcons.arrowRight,
                    size: I.md, color: GS.link),
              ]),
            ],
          ),
        ),
        const SizedBox(width: S.x3),
        ExcludeSemantics(
          child: SizedBox.square(dimension: card.side, child: card.picture),
        ),
      ]),
    );
    return Pressable(
      onTap: onOpen,
      semanticLabel: '${card.title}. ${card.cta}',
      child: card.featured
          ? Container(
              padding: const EdgeInsets.all(S.hair + S.half / 4),
              decoration: const BoxDecoration(
                borderRadius: R.rXl,
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [GS.rimA, GS.rimB, GS.rimC],
                ),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  borderRadius: R.rXl,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [GS.warmA, GS.warmB],
                  ),
                ),
                child: body,
              ),
            )
          : Container(
              decoration:
                  const BoxDecoration(color: GS.card, borderRadius: R.rXl),
              child: body,
            ),
    );
  }
}

/// The band's pod tilted on the page, its mark ringed in light.
class _PodPainter extends CustomPainter {
  const _PodPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    canvas.save();
    canvas.translate(w / 2, w / 2);
    canvas.rotate(-.12);
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w * .84, height: w * .7),
        Radius.circular(w * .2));
    canvas.drawRRect(body.shift(Offset(w * .03, w * .06)),
        Paint()..color = OB.metalDeep);
    canvas.drawRRect(
        body,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [OB.metal, OB.metalDark],
          ).createShader(body.outerRect));
    // The rim catches blue along the bottom right.
    canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .025
          ..shader = SweepGradient(colors: [
            OB.lit,
            OB.lit.withValues(alpha: 0),
            OB.lit.withValues(alpha: 0),
            OB.lit,
          ], stops: const [0, .3, .7, 1])
              .createShader(body.outerRect));
    // The mark in its ring.
    canvas.drawCircle(Offset.zero, w * .17,
        Paint()..color = OB.metalDeep.withValues(alpha: .6));
    canvas.drawCircle(
        Offset.zero,
        w * .17,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .02
          ..color = OB.lit);
    final mark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .028
      ..strokeCap = StrokeCap.round
      ..color = DC.pure;
    canvas.drawPath(
        Path()
          ..moveTo(-w * .05, -w * .08)
          ..lineTo(-w * .05, w * .07)
          ..lineTo(w * .07, w * .07),
        mark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PodPainter old) => false;
}

/// A bedside clock seen from three quarters: a long box with its top and
/// its end lit differently, a sunken screen on its face showing a time in
/// thin digits, a pink bar for the alarm and three dots at its edge.
class _ClockPainter extends CustomPainter {
  const _ClockPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    Offset at(double x, double y) => Offset(x * w, y * w);
    Path quad(Offset a, Offset b, Offset c, Offset d) =>
        Path()..addPolygon([a, b, c, d], true);

    // The face runs down to the right; the box goes back up and right.
    final fa = at(.02, .38), fb = at(.80, .60);
    final down = at(0, .34), back = at(.16, -.10);
    final fc = fb + down, fd = fa + down;

    // Top, then the end, then the face.
    canvas.drawPath(quad(fa, fb, fb + back, fa + back),
        Paint()..color = OB.metal);
    canvas.drawPath(
        quad(fb, fb + back, fc + back, fc), Paint()..color = OB.metalDeep);
    canvas.drawPath(
        quad(fa, fb, fc, fd),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [OB.metalDark, OB.metalDeep],
          ).createShader(Rect.fromPoints(fa, fc)));

    // The screen, sunk into the face, and what it shows, drawn in the face's
    // own skew: x runs along its top edge, y straight down its sides, so the
    // screen sits square to all four edges.
    final len = (fb - fa).distance;
    final h = down.dy;
    canvas.save();
    canvas.transform(Float64List.fromList([
      (fb.dx - fa.dx) / len, (fb.dy - fa.dy) / len, 0, 0, //
      0, 1, 0, 0, //
      0, 0, 1, 0, //
      fa.dx, fa.dy, 0, 1,
    ]));
    final screen = RRect.fromRectAndRadius(
        Rect.fromLTWH(len * .07, h * .16, len * .86, h * .68),
        Radius.circular(w * .03));
    canvas.drawRRect(screen, Paint()..color = OB.metalDeep);
    canvas.drawRRect(
        screen,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .012
          ..color = OB.metal.withValues(alpha: .5));
    // Three dots at the screen's left edge.
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(len * .13, h * (.32 + i * .18)), w * .009,
          Paint()..color = OB.metalLit);
    }
    final tp = TextPainter(
      text: TextSpan(
          text: '8:24',
          style: GS.digits.copyWith(
              color: OB.metalLit, fontWeight: FontWeight.w300)),
      textDirection: TextDirection.ltr,
      // The digits grow with the picture.
      textScaler: TextScaler.linear(w * .011),
    )..layout();
    tp.paint(canvas, Offset(len * .2, h * .5 - tp.height / 2));
    canvas.drawLine(
        Offset(len * .73, h * .5),
        Offset(len * .84, h * .5),
        Paint()
          ..color = GS.pink
          ..strokeWidth = w * .035
          ..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ClockPainter old) => false;
}

/// A closed journal, a pink ribbon hanging from its pages.
class _JournalPainter extends CustomPainter {
  const _JournalPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    canvas.save();
    canvas.translate(w / 2, w / 2);
    canvas.rotate(math.pi / 180 * 8);
    final book = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w * .62, height: w * .8),
        Radius.circular(w * .06));
    canvas.drawRRect(book.shift(Offset(w * .05, w * .04)),
        Paint()..color = OB.metalDeep);
    canvas.drawRRect(book, Paint()..color = OB.metalDark);
    canvas.drawRect(
        Rect.fromLTWH(book.left, book.top, w * .08, book.height),
        Paint()..color = OB.metalDeep);
    final line = Paint()
      ..color = OB.metalLit.withValues(alpha: .6)
      ..strokeWidth = w * .03
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = -w * .14 + i * w * .1;
      canvas.drawLine(Offset(-w * .14, y), Offset(w * .2, y), line);
    }
    canvas.drawPath(
        Path()
          ..moveTo(w * .12, book.bottom - w * .02)
          ..lineTo(w * .12, book.bottom + w * .1)
          ..lineTo(w * .16, book.bottom + w * .07)
          ..lineTo(w * .2, book.bottom + w * .1)
          ..lineTo(w * .2, book.bottom - w * .02)
          ..close(),
        Paint()..color = GS.pink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JournalPainter old) => false;
}
