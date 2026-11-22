// The full-screen moment a write takes: the page behind blurred into the
// dark, a ring turning round the Locus mark with what is happening in caps
// under it ("SAVING YOUR SCHEDULE…", "PROCESSING…"), then a green ring with a
// check and SUCCESS once it has landed, held long enough to read, then gone.
// Laid out on its reference: a 92 ring, 36 to the caps, the line under them.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui2.dart';

/// How long SUCCESS stays before the overlay lifts.
const kStatusDoneHold = Motion.linger;

/// Runs [task] under the overlay. True when it finished; false when it threw,
/// after the overlay has gone, so the caller can say why.
Future<bool> runWithStatus(
  BuildContext c, {
  required String working,
  String? workingLine,
  String done = 'SUCCESS',
  String? doneLine,
  required Future<void> Function() task,
}) async {
  final state = ValueNotifier<bool>(false);
  final nav = Navigator.of(c, rootNavigator: true);
  final route = PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: Motion.base,
    reverseTransitionDuration: Motion.base,
    pageBuilder: (_, _, _) => ValueListenableBuilder<bool>(
      valueListenable: state,
      builder: (_, ok, _) => StatusOverlay(
        done: ok,
        title: ok ? done : working,
        line: ok ? doneLine : workingLine,
      ),
    ),
    transitionsBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );
  nav.push(route);
  var ok = false;
  try {
    await task();
    ok = true;
    state.value = true;
    await Future<void>.delayed(kStatusDoneHold);
  } catch (_) {
    ok = false;
  } finally {
    if (route.isActive) nav.removeRoute(route);
    state.dispose();
  }
  return ok;
}

/// The overlay itself: working (the turning ring round the mark) or [done]
/// (the green ring and its check).
class StatusOverlay extends StatelessWidget {
  final bool done;
  final String title;
  final String? line;
  const StatusOverlay(
      {super.key, required this.done, required this.title, this.line});

  static const double ring = S.x16 + S.x6 + S.x1;

  @override
  Widget build(BuildContext c) {
    // Its own route, so no page under it gives its text a Material.
    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
        liveRegion: true,
        label: [title, ?line].join('. '),
        excludeSemantics: true,
        // The page behind, frosted, then all but put out.
        child: Glass(
          radius: BorderRadius.zero,
          child: ColoredBox(
            color: DC.syncBar.withValues(alpha: .86),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox.square(
                    dimension: ring,
                    child: AnimatedSwitcher(
                      duration: motion(c, Motion.base),
                      child: done
                          ? const _DoneRing(key: ValueKey('done'))
                          : const _WorkingRing(key: ValueKey('working')),
                    ),
                  ),
                  const SizedBox(height: S.x8 + S.x1),
                  Text(title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: F.caps.copyWith(
                          color: DC.pure,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6)),
                  if (line != null) ...[
                    const SizedBox(height: S.x2),
                    Text(line!,
                        textAlign: TextAlign.center,
                        style: F.body.copyWith(color: DC.ink2, height: 1.4)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// A white ring, a sixth of it open, turning round the mark. Still where
/// motion is off.
class _WorkingRing extends StatefulWidget {
  const _WorkingRing({super.key});

  @override
  State<_WorkingRing> createState() => _WorkingRingState();
}

class _WorkingRingState extends State<_WorkingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: Motion.roll)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _t.forward(from: 0);
        });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.enabled(context)) {
      if (!_t.isAnimating) _t.forward();
    } else {
      _t.stop();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Stack(alignment: Alignment.center, children: [
        RotationTransition(
          turns: _t,
          child: const CustomPaint(
              size: Size.square(StatusOverlay.ring), painter: _ArcPaint()),
        ),
        const LocusMark(size: S.x16 + S.x2),
      ]);
}

class _ArcPaint extends CustomPainter {
  const _ArcPaint();

  @override
  void paint(Canvas canvas, Size size) {
    const w = S.half + S.hair;
    canvas.drawArc(
        (Offset.zero & size).deflate(w / 2),
        -math.pi / 2 + math.pi / 6,
        math.pi * 5 / 3,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = DC.pure);
  }

  @override
  bool shouldRepaint(_ArcPaint old) => false;
}

/// The closed green ring and its check.
class _DoneRing extends StatelessWidget {
  const _DoneRing({super.key});

  @override
  Widget build(BuildContext c) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: C.optimal, width: S.x1),
        ),
        child: const Center(
          child: Icon(LucideIcons.check, size: I.xl, color: C.optimal),
        ),
      );
}
