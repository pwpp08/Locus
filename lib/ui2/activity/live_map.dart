// live_map.dart — the dark map behind a session: the start screen (where you
// are), the live MAP tab (the route so far and where you are now). Real tiles
// through tiles.dart when they may be fetched and arrive; the drawn line on
// the card's own ground when they do not, so offline still shows the shape.

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'tiles.dart';

class LiveMap extends StatefulWidget {
  /// The route so far, oldest first.
  final List<(double, double)> route;

  /// Where the person is now; the route's last point when null.
  final (double, double)? here;

  /// The line's colour.
  final Color ink;

  /// Room left round the route, as a share of the frame.
  final double pad;

  const LiveMap(
      {super.key,
      this.route = const [],
      this.here,
      this.ink = C.dialStrain,
      this.pad = .18});

  /// Widget tests have no network and must not leave a fetch timer behind.
  static bool fetch = !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  RouteMosaic? _m;
  Size? _for;
  bool _busy = false;
  DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  (double, double)? get _here =>
      widget.here ?? (widget.route.isEmpty ? null : widget.route.last);

  @override
  void dispose() {
    _m?.dispose();
    super.dispose();
  }

  /// Refetch when there is no map, the box changed, or where the person is
  /// has walked off the middle of it — at most every 30 s.
  /// ponytail: one still mosaic refetched whole, not a tiled pannable map;
  /// tiles are drawn at 1:1 logical pixels (soft on a dense screen).
  void _maybeFetch(Size size) {
    if (_busy || !LiveMap.fetch || !mapTilesAllowed) return;
    final h = _here;
    if (h == null || size.isEmpty) return;
    final m = _m;
    var need = m == null || _for != size;
    if (!need && m.project != null) {
      final o = m.project!(h.$1, h.$2);
      final inset = Rect.fromLTWH(0, 0, m.width, m.height)
          .deflate(math.min(m.width, m.height) * .12);
      need = !inset.contains(o);
    }
    if (!need) return;
    if (m != null && DateTime.now().difference(_at).inSeconds < 30) return;
    _busy = true;
    _at = DateTime.now();
    final pts = widget.route.isEmpty ? [h] : widget.route;
    var lo = pts.first, hi = pts.first;
    for (final p in pts) {
      lo = (math.min(lo.$1, p.$1), math.min(lo.$2, p.$2));
      hi = (math.max(hi.$1, p.$1), math.max(hi.$2, p.$2));
    }
    // A street's worth of ground at the least, so one fix is a map, not a
    // tile at zoom 17.
    const span = .003;
    final cy = (lo.$1 + hi.$1) / 2, cx = (lo.$2 + hi.$2) / 2;
    final dy = math.max(span, hi.$1 - lo.$1) / 2;
    final dx = math.max(span, hi.$2 - lo.$2) / 2;
    final p = P.of(context);
    unawaited(buildRouteMosaic([(cy - dy, cx - dx), (cy + dy, cx + dx)],
            width: size.width.round(),
            height: size.height.round(),
            bg: C.char,
            ink: p.ink3,
            pad: widget.pad)
        .then((got) {
      _busy = false;
      if (!mounted) {
        got?.dispose();
        return;
      }
      if (got == null) return;
      setState(() {
        _m?.dispose();
        _m = got;
        _for = size;
      });
    }));
  }

  @override
  Widget build(BuildContext c) {
    return LayoutBuilder(builder: (_, box) {
      final size = box.biggest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeFetch(size);
      });
      final m = _m != null && _for == size ? _m : null;
      return Stack(fit: StackFit.expand, children: [
        CustomPaint(
          painter: _MapPainter(
            mosaic: m,
            route: widget.route,
            here: _here,
            ink: widget.ink,
            ground: Color.alphaBlend(C.white.withValues(alpha: .04), C.char),
          ),
        ),
        if (m != null)
          Positioned(
            right: S.x2,
            bottom: S.x1,
            child: Text(kOsmAttribution,
                style: F.over.copyWith(color: C.white.withValues(alpha: .45))),
          ),
      ]);
    });
  }
}

class _MapPainter extends CustomPainter {
  final RouteMosaic? mosaic;
  final List<(double, double)> route;
  final (double, double)? here;
  final Color ink, ground;

  _MapPainter(
      {this.mosaic,
      required this.route,
      this.here,
      required this.ink,
      required this.ground});

  @override
  void paint(Canvas cv, Size s) {
    final m = mosaic;
    late final Offset Function((double, double)) at;
    if (m != null && m.project != null) {
      cv.drawImage(m.image, Offset.zero, Paint());
      at = (g) => m.project!(g.$1, g.$2);
    } else {
      cv.drawRect(Offset.zero & s, Paint()..color = ground);
      // No tiles: the route framed on its own, north up, one scale both ways.
      final pts = [...route, ?here];
      if (pts.isEmpty) return;
      var lo = pts.first, hi = pts.first;
      for (final p in pts) {
        lo = (math.min(lo.$1, p.$1), math.min(lo.$2, p.$2));
        hi = (math.max(hi.$1, p.$1), math.max(hi.$2, p.$2));
      }
      final k = math.cos(((lo.$1 + hi.$1) / 2) * math.pi / 180);
      final spanY = hi.$1 - lo.$1, spanX = (hi.$2 - lo.$2) * k;
      final span = math.max(math.max(spanX, spanY), 1e-4);
      final box = math.min(s.width, s.height) * .7;
      final cy = (lo.$1 + hi.$1) / 2, cx = (lo.$2 + hi.$2) / 2;
      at = (g) => Offset(s.width / 2 + (g.$2 - cx) * k / span * box,
          s.height / 2 - (g.$1 - cy) / span * box);
    }
    if (route.length > 1) {
      final path = Path()..moveTo(at(route.first).dx, at(route.first).dy);
      for (final g in route.skip(1)) {
        final o = at(g);
        path.lineTo(o.dx, o.dy);
      }
      cv.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = ink);
    }
    final h = here;
    if (h != null) {
      final o = at(h);
      cv.drawCircle(o, 16, Paint()..color = ink.withValues(alpha: .22));
      cv.drawCircle(o, 8, Paint()..color = C.white);
      cv.drawCircle(o, 5.5, Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter o) =>
      o.mosaic != mosaic || o.route != route || o.here != here || o.ink != ink;
}
