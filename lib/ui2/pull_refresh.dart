// Pull to refresh, the Locus way. The word is not on the page: pulling the
// page down opens a gap at the top and LOCUS slides into it, gray and
// unfilled. Let go past the line and it holds there while the page waits, and
// white fills it from left to right. When the refresh is done the page rises
// again and takes the word up with it, out of sight.
//
// A sliver, to sit first in a [CustomScrollView] whose physics let the page
// be pulled past its top ([BouncingScrollPhysics]): the platform's own
// refresh control paints over the page instead of moving it.

import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl, RefreshIndicatorMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'logo.dart';
import 'theme.dart';

/// Physics for a page that can be pulled down: it always scrolls, and it
/// gives past its top the way the refresh needs.
const ScrollPhysics kPullPhysics =
    AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());

class LocusPullRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const LocusPullRefresh({super.key, required this.onRefresh});

  /// The pull that arms the refresh, and the height the page is held at while
  /// it runs: room for the mark and the air above and below it.
  static const trigger = S.x16 + S.x4;
  static const held = S.x16;

  @override
  Widget build(BuildContext c) {
    // The write-on is never cut short by a fast refresh: the page waits for
    // the mark to be drawn before it lets go.
    final minimum = motion(c, Motion.write);
    return CupertinoSliverRefreshControl(
      refreshTriggerPullDistance: trigger,
      refreshIndicatorExtent: held,
      onRefresh: () async {
        await Future.wait([onRefresh(), Future<void>.delayed(minimum)]);
      },
      builder: (c, mode, pulled, trigger, extent) =>
          _LocusPullMark(mode: mode, pulled: pulled, trigger: trigger),
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
    // A tick under the finger the moment the pull is enough.
    final armed = m == RefreshIndicatorMode.armed;
    if (armed && !_armed) HapticFeedback.selectionClick();
    _armed = armed;
    if (m == RefreshIndicatorMode.refresh &&
        old.mode != RefreshIndicatorMode.refresh) {
      _c.duration == Duration.zero ? _c.value = 1 : _c.forward(from: 0);
    }
    // Back at rest: gray again for the next pull.
    if (m == RefreshIndicatorMode.inactive && old.mode != m) _c.value = 0;
  }

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
