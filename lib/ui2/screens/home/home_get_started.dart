// Get Started: the first weeks' cards on Home, laid out on their reference.
// Each card is a title, two or three lines, a violet way in and a picture on
// the right; the first one stands out on a warm ground in a warm-to-violet
// rim. A card goes once its way in has been taken, and the section with the
// last of them.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/alarm_manager.dart';
import '../../../state/app_state.dart';
import '../../../state/prefs.dart';
import '../../profile/schedule_flow.dart' show openScheduleFlow;
import '../../ui2.dart';
import '../../community/community.dart' show CommunityScreen;
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
      _setUpSleep,
      side: S.x16 + S.x10,
    ),
    _Card(
      'journal',
      'Start Your Journal',
      'Log a few habits each day and see which ones move your sleep and '
          'recovery.',
      'OPEN JOURNAL',
      const CustomPaint(painter: _JournalPainter()),
      (c) => go(c, const JournalCompose()),
      side: S.x16 + S.x8,
    ),
    _Card(
      'crew',
      'Find Your Crew',
      'Start a team with a friend to keep each other going, or join one and '
          'see how you stack up.',
      'OPEN COMMUNITY',
      const CustomPaint(painter: _CrewPainter()),
      (c) => go(c, const CommunityScreen()),
      side: S.x16 + S.x8,
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
        PromptCard(
          title: left[i].title,
          body: left[i].body,
          cta: left[i].cta,
          picture: left[i].picture,
          side: left[i].side,
          featured: left[i].featured,
          onOpen: () {
            Prefs.setBool(GetStartedSection.donePref(left[i].id), true);
            left[i].open(c);
            setState(() {});
          },
        ),
      ],
    ]);
  }
}

/// Straight into making a wake schedule; the planner where there is no app
/// state to keep one in.
void _setUpSleep(BuildContext c) {
  AlarmManager? mgr;
  try {
    mgr = c.read<AppState>().alarmManager;
  } catch (_) {}
  if (mgr == null) return go(c, const SleepPlannerScreen());
  openScheduleFlow(c, mgr);
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

/// One of Home's prompt cards (Get Started, Sleep Detected, Sleep Pending):
/// a title, two or three lines, a way in in caps with its arrow, and a
/// picture on the right. Without [cta] it only tells; without [picture] the
/// words take the width.
class PromptCard extends StatelessWidget {
  final String title, body;
  final String? cta;
  final Widget? picture;
  final double side;
  final bool featured;

  /// The way in's colour: violet for setting up, the sleep colour for sleep.
  final Color link;
  final VoidCallback? onOpen;

  const PromptCard({
    super.key,
    required this.title,
    required this.body,
    this.cta,
    this.picture,
    this.side = S.x16 + S.x3,
    this.featured = false,
    this.link = GS.link,
    this.onOpen,
  });

  @override
  Widget build(BuildContext c) {
    final body = Padding(
      padding: EdgeInsets.fromLTRB(
          S.x5, S.x5, picture == null ? S.x5 : S.x3, S.x5),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: GS.title.copyWith(color: DC.pure)),
              const SizedBox(height: S.half),
              Text(this.body, style: GS.text.copyWith(color: GS.body)),
              if (cta != null) ...[
                const SizedBox(height: S.x2 + S.half),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: Text(cta!, style: GS.cta.copyWith(color: link))),
                  const SizedBox(width: S.x3),
                  Icon(LucideIcons.arrowRight, size: I.md, color: link),
                ]),
              ],
            ],
          ),
        ),
        if (picture != null) ...[
          const SizedBox(width: S.x3),
          ExcludeSemantics(
            child: SizedBox.square(dimension: side, child: picture),
          ),
        ],
      ]),
    );
    return Pressable(
      onTap: onOpen,
      semanticLabel: [title, cta ?? this.body].join('. '),
      child: featured
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

/// The goals card's picture, flat: the band's pod as a rounded square,
/// tilted, its rim and its ring lit blue into violet, the mark in white.
class _PodPainter extends CustomPainter {
  const _PodPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    canvas.save();
    canvas.translate(w / 2, w / 2);
    canvas.rotate(-.16);
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w * .78, height: w * .70),
        Radius.circular(w * .22));
    // Its shadow, flat, down and right.
    canvas.drawRRect(body.shift(Offset(w * .02, w * .05)),
        Paint()..color = OB.metalDeep);
    canvas.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(OB.metal, GS.rimC, .22)!, GS.warmB],
          ).createShader(body.outerRect));
    final lit = SweepGradient(
      colors: const [OB.lit, GS.rimC, OB.lit],
      transform: const GradientRotation(math.pi / 4),
    );
    canvas.drawRRect(
        body.deflate(w * .012),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .024
          ..shader = lit.createShader(body.outerRect));
    final ring = Rect.fromCircle(center: Offset.zero, radius: w * .19);
    canvas.drawOval(ring, Paint()..color = OB.metalDeep);
    canvas.drawOval(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .022
          ..shader = lit.createShader(ring));
    canvas.translate(-w * .11, -w * .12);
    LocusMarkPainter(ink: DC.pure).paint(canvas, Size.square(w * .22));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PodPainter old) => false;
}

/// The sleep card's picture, flat: a bedside clock face on, tilted, its
/// screen showing a time in thin digits, a pink bar for the alarm, three
/// dots at its left edge and a button on its top.
class _ClockPainter extends CustomPainter {
  const _ClockPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    canvas.save();
    canvas.translate(w / 2, w / 2);
    canvas.rotate(.22);
    final box = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, w * .03), width: w * .9, height: w * .42),
        Radius.circular(w * .07));
    // The button on its top, then the box, its top edge lit.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-w * .22, box.top - w * .05, w * .3, w * .07),
            Radius.circular(w * .02)),
        Paint()..color = OB.metalDark);
    canvas.drawRRect(box.shift(Offset(w * .015, w * .035)),
        Paint()..color = OB.metalDeep);
    canvas.drawRRect(box, Paint()..color = OB.metalDark);
    canvas.drawRRect(
        RRect.fromRectAndCorners(
            Rect.fromLTWH(box.left, box.top, box.width, w * .06),
            topLeft: Radius.circular(w * .07),
            topRight: Radius.circular(w * .07)),
        Paint()..color = OB.metal);
    final screen = RRect.fromRectAndRadius(
        Rect.fromLTRB(box.left + w * .06, box.top + w * .1, box.right - w * .06,
            box.bottom - w * .06),
        Radius.circular(w * .035));
    canvas.drawRRect(screen, Paint()..color = OB.metalDeep);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
          Offset(screen.left + w * .035, screen.top + screen.height * (.28 + i * .22)),
          w * .009,
          Paint()..color = OB.metalLit);
    }
    final tp = TextPainter(
      text: TextSpan(
          text: '8:24',
          style: GS.digits.copyWith(
              color: OB.metalLit, fontWeight: FontWeight.w300)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(w * .0105),
    )..layout();
    tp.paint(canvas,
        Offset(screen.left + w * .09, screen.center.dy - tp.height / 2));
    tp.dispose();
    canvas.drawLine(
        Offset(screen.right - w * .14, screen.center.dy + w * .01),
        Offset(screen.right - w * .05, screen.center.dy + w * .01),
        Paint()
          ..color = GS.pink
          ..strokeWidth = w * .04
          ..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ClockPainter old) => false;
}

/// The journal card's picture, flat: a closed notebook, tilted, its spine
/// darker, an elastic band down its right side with a tab, a ringed mark
/// pressed into the cover and a pink ribbon out of its foot.
class _JournalPainter extends CustomPainter {
  const _JournalPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    canvas.save();
    canvas.translate(w / 2, w / 2);
    canvas.rotate(math.pi / 180 * 22);
    final book = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w * .6, height: w * .82),
        Radius.circular(w * .05));
    // The ribbon first, under the book.
    final rx = book.left + w * .14;
    canvas.drawPath(
        Path()
          ..moveTo(rx, book.bottom - w * .04)
          ..lineTo(rx, book.bottom + w * .1)
          ..lineTo(rx + w * .045, book.bottom + w * .07)
          ..lineTo(rx + w * .09, book.bottom + w * .1)
          ..lineTo(rx + w * .09, book.bottom - w * .04)
          ..close(),
        Paint()..color = GS.pink);
    // The pages' edge, then the cover over it.
    canvas.drawRRect(book.shift(Offset(w * .03, w * .025)),
        Paint()..color = OB.metalLit);
    canvas.drawRRect(book, Paint()..color = OB.metal);
    canvas.drawRRect(
        RRect.fromRectAndCorners(
            Rect.fromLTWH(book.left, book.top, w * .09, book.height),
            topLeft: Radius.circular(w * .05),
            bottomLeft: Radius.circular(w * .05)),
        Paint()..color = OB.metalDark);
    // The elastic band and its tab.
    final band = Rect.fromLTWH(book.right - w * .1, book.top, w * .045, book.height);
    canvas.drawRect(band, Paint()..color = OB.metalDark);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(band.left - w * .015, -w * .05, w * .1, w * .1),
            Radius.circular(w * .02)),
        Paint()..color = OB.metalDark);
    // The mark pressed into the cover.
    canvas.drawCircle(
        Offset(w * .04, w * .2),
        w * .075,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .012
          ..color = OB.metalDark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JournalPainter old) => false;
}

/// The crew card's picture, flat: two hands raised to meet in a high five,
/// pink sparks round where they touch.
class _CrewPainter extends CustomPainter {
  const _CrewPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    // One open hand, palm out, fingers up: drawn upright about its palm's
    // centre, then turned.
    void hand(Offset at, double turn, Color color) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(turn);
      final paint = Paint()..color = color;
      // Forearm and palm.
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(-w * .1, w * .02, w * .2, w * .5),
              Radius.circular(w * .06)),
          paint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: w * .26, height: w * .24),
              Radius.circular(w * .08)),
          paint);
      // Four fingers, the middle ones longest.
      const lens = [.17, .21, .2, .15];
      for (var i = 0; i < 4; i++) {
        final x = -w * .095 + i * w * .063;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x - w * .028, -w * .06 - w * lens[i], w * .056,
                    w * lens[i] + w * .06),
                Radius.circular(w * .028)),
            paint);
      }
      canvas.restore();
    }

    hand(Offset(w * .56, w * .5), .1, OB.metalDark);
    hand(Offset(w * .48, w * .53), -.05, OB.metal);
    // Sparks round the touch.
    final spark = Paint()
      ..color = GS.pink
      ..strokeWidth = w * .018
      ..strokeCap = StrokeCap.round;
    final o = Offset(w * .5, w * .24);
    for (final a in [-2.6, -2.0, -1.57, -1.1, -.55]) {
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(o + d * w * .23, o + d * w * .28, spark);
    }
    for (final a in [-3.0, -.1]) {
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(o + d * w * .24, o + d * w * .29, spark);
    }
  }

  @override
  bool shouldRepaint(_CrewPainter old) => false;
}

/// The Sleep Detected card's picture, flat: a crescent moon whose inner edge
/// catches the sleep colour, two small stars in its hollow.
class SleepMoonPainter extends CustomPainter {
  const SleepMoonPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final body = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: Offset(w * .54, w * .52), radius: w * .43)),
      Path()..addOval(Rect.fromCircle(center: Offset(w * .35, w * .40), radius: w * .37)),
    );
    canvas.drawPath(
        body,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [OB.metal, OB.metalDeep],
          ).createShader(Offset.zero & s));
    // The lit inner edge: the cut circle's arc that lies inside the moon.
    canvas.save();
    canvas.clipPath(Path()
      ..addOval(Rect.fromCircle(center: Offset(w * .54, w * .52), radius: w * .43)));
    canvas.drawArc(
        Rect.fromCircle(center: Offset(w * .35, w * .40), radius: w * .37),
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .05
          ..color = C.dialSleep);
    canvas.restore();
    // Two four-point stars in the hollow.
    void star(Offset o, double r) {
      canvas.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - r)
            ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
            ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
            ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
            ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
            ..close(),
          Paint()..color = OB.metalLit);
    }

    star(Offset(w * .36, w * .3), w * .05);
    star(Offset(w * .22, w * .44), w * .035);
  }

  @override
  bool shouldRepaint(SleepMoonPainter old) => false;
}
