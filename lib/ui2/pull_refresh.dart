// Pull to refresh with nothing drawn: pulling the page down past the line
// starts the work and the page springs straight back. What answers the pull
// is the page itself (Home's black data bar appears while the data catches
// up), not a mark in the gap.
//
// Only a pull counts. A flick up the page stops dead at its top rather than
// carrying past it ([PullOnlyPhysics]), so scrolling back up never starts a
// refresh.
//
// A sliver, to sit first in a [CustomScrollView] whose physics let the page
// be pulled past its top ([BouncingScrollPhysics]).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// The pull itself: past [trigger] and let go, [onRefresh] starts, with a
/// light tap of haptics, and the page goes straight back up without waiting
/// for it.
class PullToRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const PullToRefresh({super.key, required this.onRefresh});

  /// The pull that starts the refresh.
  static const trigger = S.x16 + S.x4;

  @override
  Widget build(BuildContext c) => CupertinoSliverRefreshControl(
        refreshTriggerPullDistance: trigger,
        refreshIndicatorExtent: 0,
        onRefresh: () async {
          unawaited(HapticFeedback.lightImpact());
          unawaited(onRefresh().then<void>((_) {}, onError: (Object _) {}));
        },
        builder: (c, mode, pulled, trigger, extent) => const SizedBox.shrink(),
      );
}
