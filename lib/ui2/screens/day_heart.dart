// THE DAY'S HEART RATE, sideways: every minute from falling asleep last night
// to now, with the night and each activity marked over it — the night's
// length and each activity's strain on top, their stretches shaded and drawn
// in their own colour, the wake as a green line and the day's strain over the
// last reading. Opened from My Day's expand button; pinch to zoom, drag to
// move along a zoomed day, the magnifier to jump in and back out.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/db.dart';
import '../../state/clock_format.dart';
import '../activity/catalogue.dart';
import '../ui2.dart';
import 'window_editor.dart' show HrPoint;

/// One stretch marked on the day: the night, or an activity.
typedef DayMark = ({int from, int to, IconData icon, String value, bool sleep});

class DayHeartScreen extends StatefulWidget {
  /// The local day, `yyyy-MM-dd`.
  final String day;

  /// The night that ended on [day] (`getDaySleepV2`) and the day's sessions
  /// (`getSessions`), as My Day already holds them.
  final Map<String, dynamic> night;
  final List<Map<String, dynamic>> sessions;

  /// The day's strain, for the figure over the last reading.
  final double? strain;

  /// Per-minute heart rate, for a test; the band's store when null.
  final Future<List<HrPoint>> Function(int from, int to)? hr;

  /// "Now", for a test.
  final DateTime? now;

  const DayHeartScreen({
    super.key,
    required this.day,
    this.night = const {},
    this.sessions = const [],
    this.strain,
    this.hr,
    this.now,
  });

  @override
  State<DayHeartScreen> createState() => _DayHeartScreenState();
}

Future<List<HrPoint>> _readHr(int from, int to) async {
  try {
    final rows = await LocalDb.hrPerMinuteBetween(from, to);
    return [
      for (final r in rows)
        if (r['t'] is num && r['v'] is num)
          (t: (r['t'] as num).toInt(), v: (r['v'] as num).toDouble()),
    ];
  } catch (_) {
    return const [];
  }
}

class _DayHeartScreenState extends State<DayHeartScreen> {
  List<HrPoint> _hr = const [];
  late final int _t0, _t1;
  late final List<DayMark> _marks;
  int? _wake;

  /// The view, in epoch seconds; the whole day when not zoomed.
  late int _v0, _v1;
  int _pinchSpan = 0, _pinchFrom = 0;
  double? _dragAt;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    final d = DateTime.tryParse(widget.day) ?? _now;
    final dayStart = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000;
    final dayEnd =
        DateTime(d.year, d.month, d.day + 1).millisecondsSinceEpoch ~/ 1000;
    final nowSec = _now.millisecondsSinceEpoch ~/ 1000;
    final n = widget.night;
    final onset = (n['onset_ts'] as num?)?.toInt();
    final wake = (n['wake_ts'] as num?)?.toInt();
    final tst = n['duration_min'] as num?;
    _wake = wake;
    _marks = [
      if (onset != null && wake != null && tst != null)
        (
          from: onset,
          to: wake,
          icon: LucideIcons.moon,
          value: '${tst ~/ 60}:${(tst.round() % 60).toString().padLeft(2, '0')}',
          sleep: true,
        ),
      for (final s in widget.sessions)
        if (s['start_ts'] is num)
          (
            from: (s['start_ts'] as num).toInt(),
            to: (s['end_ts'] as num?)?.toInt() ??
                (s['start_ts'] as num).toInt() +
                    ((s['duration_min'] as num?)?.toInt() ?? 0) * 60,
            icon: activityByName(s['type'] as String?)?.icon ??
                LucideIcons.activity,
            value: (s['strain'] as num?)?.toStringAsFixed(1) ?? '--',
            sleep: false,
          ),
    ];
    // From falling asleep (or midnight) to now (or the end of a past day).
    _t0 = math.min(onset ?? dayStart, dayStart);
    _t1 = math.max(_t0 + 3600, math.min(nowSec, dayEnd));
    _v0 = _t0;
    _v1 = _t1;
    (widget.hr ?? _readHr)(_t0, _t1).then((pts) {
      if (mounted) setState(() => _hr = pts);
    });
  }

  @override
  void dispose() {
    // Back to whatever the app allows: portrait for a phone held upright.
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  void _setView(int from, int span) {
    span = span.clamp(30 * 60, _t1 - _t0);
    from = from.clamp(_t0, _t1 - span);
    setState(() {
      _v0 = from;
      _v1 = from + span;
    });
  }

  void _pinch(PinchPhase phase, double scale, double focal, double pan) {
    switch (phase) {
      case PinchPhase.start:
        _pinchSpan = _v1 - _v0;
        _pinchFrom = _v0;
        _dragAt = null;
      case PinchPhase.update:
        final span = (_pinchSpan / math.max(scale, .01)).round();
        final at = _pinchFrom + (focal * _pinchSpan).round();
        _setView(at - ((focal + pan) * span).round(), span);
      case PinchPhase.end:
        break;
    }
  }

  /// One finger moves a zoomed day along.
  void _drag(double f) {
    final last = _dragAt;
    _dragAt = f;
    if (last == null || _v1 - _v0 >= _t1 - _t0) return;
    final span = _v1 - _v0;
    _setView(_v0 - ((f - last) * span).round(), span);
  }

  /// The magnifier: into the last four hours (or the busiest stretch), and
  /// back out to the whole day.
  void _toggleZoom() {
    if (_v1 - _v0 < _t1 - _t0) {
      _setView(_t0, _t1 - _t0);
    } else {
      final span = math.min(4 * 3600, _t1 - _t0);
      _setView(_t1 - span, span);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final strain = widget.strain;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: LayoutBuilder(builder: (c, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final left = w * .115, right = w * .835;
          final headH = math.min(S.x16 * 2, h * .3);
          final span = math.max(1, _v1 - _v0);
          double xOf(int t) => left + (t - _v0) / span * (right - left);
          final end = _hr.isEmpty ? _t1 : _hr.last.t;
          final endX = xOf(end);

          // The marks over the chart, grouped where they would overlap.
          final shown = [
            for (final m in _marks)
              if (m.to > _v0 && m.from < _v1)
                (m: m, x: (xOf(math.max(m.from, _v0)) + xOf(math.min(m.to, _v1))) / 2),
          ];
          final groups = clusterMarks(shown, (e) => e.x, gap: S.x12 + S.x1);

          return Stack(children: [
            // The strip along the top: darker than the chart under it.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: headH,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.alphaBlend(C.char.withValues(alpha: .6), p.bg),
                  border: Border(
                    top: BorderSide(color: C.char, width: S.half),
                    bottom: BorderSide(color: C.char, width: S.half),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: headH,
              bottom: 0,
              child: Scrubber(
                value: null,
                onChanged: _drag,
                onLift: () => _dragAt = null,
                onPinch: _pinch,
                label: 'Heart rate through the day',
                describe: (f) {
                  final t = DateTime.fromMillisecondsSinceEpoch(
                      (_v0 + (f * span).round()) * 1000);
                  return formatClock(t.hour, t.minute);
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _DayPaint(
                    hr: _hr,
                    marks: _marks,
                    v0: _v0,
                    v1: _v1,
                    left: left,
                    right: right,
                    wake: _wake,
                    end: end,
                    first: _t0,
                    ink: p.ink,
                    ink3: p.ink3,
                    grid: p.ink.withValues(alpha: .08),
                  ),
                ),
              ),
            ),
            // Each mark's icon and figure, or how many share the spot.
            for (final g in groups)
              Builder(builder: (c) {
                final x = g.map((e) => e.x).reduce((a, b) => a + b) / g.length;
                final one = g.length == 1 ? g.first.m : null;
                return Positioned(
                  left: x - S.x12,
                  width: S.x12 * 2,
                  top: S.x3,
                  height: headH - S.x3 * 2,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    one == null
                        ? MarkCount(g.length, color: p.ink, size: I.lg)
                        : Icon(one.icon, size: I.lg, color: p.ink),
                    const SizedBox(height: S.x2),
                    Text(one?.value ?? '',
                        style: F.num(F.n24).copyWith(
                            color: p.ink, fontWeight: FontWeight.w700)),
                  ]),
                );
              }),
            // Under each mark, a bar the width of its stretch.
            for (final m in _marks)
              if (m.to > _v0 && m.from < _v1)
                Positioned(
                  left: xOf(math.max(m.from, _v0)),
                  width: math.max(S.x1, xOf(math.min(m.to, _v1)) - xOf(math.max(m.from, _v0))),
                  top: headH - S.x1,
                  height: S.x1,
                  child: ColoredBox(color: m.sleep ? C.dialSleep : C.dialStrain),
                ),
            // The day's strain, over the last reading.
            if (endX > left && endX <= right + S.x2)
              Positioned(
                left: endX - S.x12,
                width: S.x12 * 2,
                top: S.x3,
                height: headH - S.x3 * 2,
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('STRAIN',
                      style: F.caps.copyWith(
                          color: C.dialStrain, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  const SizedBox(height: S.x1),
                  Text(strain == null ? '--' : strain.toStringAsFixed(1),
                      style: F.num(F.n24).copyWith(
                          color: C.dialStrain, fontWeight: FontWeight.w700)),
                  const SizedBox(height: S.x2),
                ]),
              ),
            Positioned(
              left: S.x2,
              top: S.x1,
              child: Pressable(
                onTap: () => Navigator.of(c).maybePop(),
                semanticLabel: 'Close',
                child: SizedBox(
                  width: S.tap + S.x2,
                  height: S.tap + S.x2,
                  child: Icon(LucideIcons.x, size: I.xl, color: p.ink),
                ),
              ),
            ),
            Positioned(
              left: right + (w - right) * .45 - S.tap / 2,
              top: headH + (h - headH) * .38,
              child: Pressable(
                onTap: _toggleZoom,
                semanticLabel: _v1 - _v0 < _t1 - _t0
                    ? 'Show the whole day'
                    : 'Zoom in',
                child: SizedBox(
                  width: S.tap + S.x2,
                  height: S.tap + S.x2,
                  child: Icon(
                      _v1 - _v0 < _t1 - _t0 ? LucideIcons.zoomOut : LucideIcons.zoomIn,
                      size: I.xl,
                      color: p.ink),
                ),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

class _DayPaint extends CustomPainter {
  final List<HrPoint> hr;
  final List<DayMark> marks;
  final int v0, v1, end, first;
  final int? wake;
  final double left, right;
  final Color ink, ink3, grid;

  _DayPaint({
    required this.hr,
    required this.marks,
    required this.v0,
    required this.v1,
    required this.left,
    required this.right,
    required this.wake,
    required this.end,
    required this.first,
    required this.ink,
    required this.ink3,
    required this.grid,
  });

  static const _lo = 20.0, _hi = 220.0;

  @override
  void paint(Canvas canvas, Size size) {
    const foot = S.x10;
    final plot = Rect.fromLTRB(left, 0, right, size.height - foot);
    final span = math.max(1, v1 - v0);
    double xOf(num t) => left + (t - v0) / span * (right - left);
    double yOf(double v) =>
        plot.bottom - (v - _lo) / (_hi - _lo) * plot.height;

    // The marked stretches, behind everything.
    for (final m in marks) {
      if (m.to <= v0 || m.from >= v1) continue;
      final a = xOf(math.max(m.from, v0)), b = xOf(math.min(m.to, v1));
      canvas.drawRect(
          Rect.fromLTRB(a, plot.top, b, plot.bottom),
          Paint()
            ..color = m.sleep
                ? ink.withValues(alpha: .06)
                : C.dialStrain.withValues(alpha: .1));
    }

    // Grid lines every 40 bpm, labelled in the margin.
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = 40.0; v <= 200; v += 40) {
      final y = yOf(v);
      canvas.drawLine(Offset(left, y), Offset(right, y), gp);
      _text(canvas, '${v.round()}', Offset(left * .55, y), ink3, centre: true);
    }

    // The trace: the night in the night's colour, an activity in blue, the
    // rest of the day in grey. Broken where the band was off.
    Color colorAt(int t) {
      for (final m in marks) {
        if (t >= m.from && t <= m.to) return m.sleep ? C.dialSleep : C.dialStrain;
      }
      return ink3.withValues(alpha: .75);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(left, -S.x4, right, size.height));
    HrPoint? prev;
    for (final e in hr) {
      if (e.t < v0 - 120 || e.t > v1 + 120) {
        prev = null;
        continue;
      }
      if (prev != null && e.t - prev.t <= 300) {
        canvas.drawLine(
            Offset(xOf(prev.t), yOf(prev.v)),
            Offset(xOf(e.t), yOf(e.v)),
            Paint()
              ..color = colorAt(e.t)
              ..strokeWidth = 1.6
              ..strokeCap = StrokeCap.round);
      }
      prev = e;
    }
    canvas.restore();

    void dashed(double x, Color c) {
      if (x < left - 1 || x > right + 1) return;
      final p = Paint()
        ..color = c
        ..strokeWidth = 1.6;
      for (var y = plot.top; y < size.height - foot + S.x3; y += S.x2) {
        canvas.drawLine(Offset(x, y), Offset(x, y + S.x1), p);
      }
    }

    // The wake, and the last reading.
    if (wake != null) dashed(xOf(wake!), C.recGreen);
    dashed(xOf(end), C.dialStrain);

    // Clock times along the foot: where the view begins, every four hours,
    // and where it ends.
    final labels = <(double, String, bool)>[];
    String clock(int t) {
      final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
      return formatClock(d.hour, d.minute);
    }

    final viewEnd = math.min(v1, end);
    labels.add((xOf(v0), clock(v0), false));
    final step = span > 10 * 3600 ? 4 : (span > 4 * 3600 ? 2 : 1);
    final s0 = DateTime.fromMillisecondsSinceEpoch(v0 * 1000);
    var t = DateTime(s0.year, s0.month, s0.day, s0.hour + 1);
    while (t.hour % step != 0) {
      t = DateTime(t.year, t.month, t.day, t.hour + 1);
    }
    for (;
        t.millisecondsSinceEpoch ~/ 1000 < viewEnd;
        t = DateTime(t.year, t.month, t.day, t.hour + step)) {
      final ts = t.millisecondsSinceEpoch ~/ 1000;
      labels.add((xOf(ts), clock(ts), false));
    }
    labels.add((xOf(viewEnd), clock(viewEnd), true));
    double? last;
    for (var i = 0; i < labels.length; i++) {
      final (x, s, isEnd) = labels[i];
      // Never two labels on top of each other: the ends win.
      final nextX = i + 1 < labels.length ? labels[i + 1].$1 : null;
      if (!isEnd && i > 0 && nextX != null && labels[i + 1].$3 && nextX - x < S.x16) {
        continue;
      }
      if (last != null && x - last < S.x16) continue;
      _text(canvas, s, Offset(x, size.height - foot / 2), ink3, centre: true);
      last = x;
    }
  }

  void _text(Canvas canvas, String s, Offset at, Color color, {bool centre = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: F.num(F.head).copyWith(color: color, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        centre ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  bool shouldRepaint(_DayPaint o) =>
      o.hr != hr || o.v0 != v0 || o.v1 != v1 || o.end != end || o.ink != ink;
}
