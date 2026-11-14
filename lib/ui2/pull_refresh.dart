// Pull to refresh, the Locus way. The word is not on the page: pulling the
// page down opens a gap at the top and LOCUS slides into it, gray and
// unfilled. Once the pull is past the line white fills it from left to right,
// and on letting go it holds there while the page waits. When the refresh is
// done the page rises again and takes the word up with it, out of sight.
//
// Only a pull opens the gap. A flick up the page stops dead at its top rather
// than carrying past it ([PullOnlyPhysics]), so scrolling back up never shows
// the word, let alone starts a refresh.
//
// A sliver, to sit first in a [CustomScrollView] whose physics let the page
// be pulled past its top ([BouncingScrollPhysics]): the platform's own
// refresh control paints over the page instead of moving it.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl, RefreshIndicatorMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'logo.dart';
import 'theme.dart';

/// Physics for a page that can be pulled down: it always scrolls, and it
/// gives past its top under a finger, the way the refresh needs.
const ScrollPhysics kPullPhysics =
    AlwaysScrollableScrollPhysics(parent: PullOnlyPhysics());

/// Bouncing physics whose fling toward the top stops at the top. A finger
/// still pulls past it; a page let go out past it still springs back.
class PullOnlyPhysics extends BouncingScrollPhysics {
  const PullOnlyPhysics({super.parent});

  @override
  PullOnlyPhysics applyTo(ScrollPhysics? ancestor) =>
      PullOnlyPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final sim = super.createBallisticSimulation(position, velocity);
    // Only a fling heading up from inside the page; a release out past the
    // top is the pull's own spring back.
    if (sim == null ||
        velocity >= 0 ||
        position.pixels < position.minScrollExtent) {
      return sim;
    }
    return _StopAtTop(sim, position.minScrollExtent);
  }
}

/// [inner], ending where it reaches [top] instead of running past it.
class _StopAtTop extends Simulation {
  final Simulation inner;
  final double top;
  _StopAtTop(this.inner, this.top);

  @override
  double x(double time) => math.max(inner.x(time), top);

  @override
  double dx(double time) => inner.x(time) <= top ? 0 : inner.dx(time);

  @override
  bool isDone(double time) => inner.isDone(time) || inner.x(time) <= top;
}

class LocusPullRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  const LocusPullRefresh({super.key, required this.onRefresh});

  /// The pull that arms the refresh, and the height the page is held at while
  /// it runs: room for the mark and the air above and below it.
  static const trigger = S.x16 + S.x4;
  static const held = S.x16;

  @override
  State<LocusPullRefresh> createState() => _LocusPullRefreshState();
}

class _LocusPullRefreshState extends State<LocusPullRefresh> {
  /// Completes when the finger has let go of the pull that started the work.
  Completer<void>? _released;

  @override
  Widget build(BuildContext c) {
    // The write-on is never cut short by a fast refresh: the page waits for
    // the finger to let go and the whole word to be white (plus a beat to see
    // it) before it lets go itself, and never waits longer than
    // [Motion.refreshCap] for the work or the finger, so the word always goes
    // back up.
    final minimum = motion(c, Motion.write + Motion.slow);
    return CupertinoSliverRefreshControl(
      refreshTriggerPullDistance: LocusPullRefresh.trigger,
      refreshIndicatorExtent: LocusPullRefresh.held,
      onRefresh: () async {
        final released = _released = Completer<void>();
        await Future.wait([
          widget.onRefresh().timeout(Motion.refreshCap, onTimeout: () {}),
          released.future
              .timeout(Motion.refreshCap, onTimeout: () {})
              .then((_) => Future<void>.delayed(minimum)),
        ]);
      },
      builder: (c, mode, pulled, trigger, extent) {
        // The control leaves `armed` for `refresh` once the page settles back
        // to its held height, which is the finger having let go.
        if (mode == RefreshIndicatorMode.refresh &&
            _released?.isCompleted == false) {
          _released!.complete();
        }
        return _LocusPullMark(mode: mode, pulled: pulled, trigger: trigger);
      },
    );
  }
}

class _LocusPullMark extends StatefulWidget {
  final RefreshIndicatorMode mode;
  final double pulled, trigger;
  const _LocusPullMark(
      {required this.mode, required this.pulled, required this.trigger});

  @override
  State<_LocusPullMark> createState() => _LocusPullMarkState();
}

class _LocusPullMarkState extends State<_LocusPullMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Motion.write);
    _armed = widget.mode == RefreshIndicatorMode.armed;
    // One quick pull can build this already armed, or already refreshing,
    // with no earlier state to change from: fill from here.
    if (_armed || widget.mode == RefreshIndicatorMode.refresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _c.value == 0 && !_c.isAnimating) _fill();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.duration = motion(context, Motion.write);
  }

  @override
  void didUpdateWidget(_LocusPullMark old) {
    super.didUpdateWidget(old);
    final m = widget.mode;
    // A tick under the finger the moment the pull is enough, and the white
    // starts across the word then, not once the page has settled.
    final armed = m == RefreshIndicatorMode.armed;
    if (armed && !_armed) HapticFeedback.selectionClick();
    if ((armed || m == RefreshIndicatorMode.refresh) &&
        _c.value == 0 &&
        !_c.isAnimating) {
      _fill();
    }
    // Pulled back under the line before letting go: gray again.
    if (m == RefreshIndicatorMode.drag && old.mode == RefreshIndicatorMode.armed) {
      _c.value = 0;
    }
    _armed = armed;
    // Back at rest: gray again for the next pull.
    if (m == RefreshIndicatorMode.inactive && old.mode != m) _c.value = 0;
  }

  void _fill() =>
      _c.duration == Duration.zero ? _c.value = 1 : _c.forward(from: 0);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _size = S.x10;
  static const _rest = S.x4;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final pulled = widget.pulled;
    // In step with the page until it reaches its place, then it stays.
    final top = math.min(pulled - _size, _rest);
    final grow = (pulled / widget.trigger).clamp(0.0, 1.0);
    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            top: top,
            left: 0,
            right: 0,
            height: _size,
            child: Center(
              child: Opacity(
                opacity: Curves.easeOut.transform(grow),
                child: Transform.scale(
                  scale: 1.05 + .25 * grow,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, _) => WordmarkFill(
                      base: p.ink3.withValues(alpha: .45),
                      ink: p.ink,
                      fill: Curves.easeInOutCubic.transform(_c.value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
