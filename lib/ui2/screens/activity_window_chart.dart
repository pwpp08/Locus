// EDIT ACTIVITY's chart, laid out on its reference: the heart rate across
// the activity with a little either side, the activity's stretch bright and
// filled down to the floor, the rest dimmed. A dotted line stands at the
// start and at the end, the time and the bpm there over each, a round knob
// with three grips at each foot; a finger near a line takes it (to the
// minute), a finger between them slides both. Under it, the wrist's movement
// on the same clock.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/clock_format.dart';
import '../ui2.dart';
import 'movement_lane.dart';
import 'window_editor.dart' show HrPoint, HrReader, readWindowHr;

class ActivityWindowChart extends StatefulWidget {
  /// The activity, epoch seconds.
  final int start, end;
  final void Function(int start, int end) onChanged;

  /// Where the heart rate and movement come from; the band's store when null.
  final HrReader? hr;
  final Future<List<MovePoint>> Function(int from, int to)? movement;

  /// Never past this (now, epoch seconds); the clock when null.
  final int? latest;

  const ActivityWindowChart({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
    this.hr,
    this.movement,
    this.latest,
  });

  /// Room over the plot for the time and bpm.
  static const labels = S.x10 + S.x1;

  /// The plot, the knobs' row and the movement lane under it.
  static const plot = S.x16 * 3;
  static const knob = S.x2 + S.half;
  static const lane = S.x6;

  @override
  State<ActivityWindowChart> createState() => _ActivityWindowChartState();
}

class _ActivityWindowChartState extends State<ActivityWindowChart> {
  late int _s = widget.start, _e = widget.end;
  late int _from, _to;
  List<HrPoint> _hr = const [];
  List<MovePoint> _move = const [];

  // 1 the start, 2 the end, 3 both; null between touches.
  int? _mode;
  int _grabT = 0, _grabS = 0, _grabE = 0;

  @override
  void initState() {
    super.initState();
    _fit();
    _load();
  }

  @override
  void didUpdateWidget(ActivityWindowChart old) {
    super.didUpdateWidget(old);
    if (_mode == null && (widget.start != _s || widget.end != _e)) {
      _s = widget.start;
      _e = widget.end;
      _fit();
      _load();
    }
  }

  /// The view: the activity with a twelfth of it (at least five minutes)
  /// either side, never past now.
  void _fit() {
    final pad = math.max(5 * 60, (_e - _s) ~/ 12);
    final now =
        widget.latest ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _from = _s - pad;
    _to = math.max(_e + 60, math.min(_e + pad, now));
  }

  Future<void> _load() async {
    final from = _from, to = _to;
    try {
      final hr = await (widget.hr ?? readWindowHr)(from, to);
      final mv = widget.movement != null
          ? await widget.movement!(from, to)
          : (widget.hr == null ? await readMovement(from, to) : const <MovePoint>[]);
      if (!mounted || from != _from || to != _to) return;
      setState(() {
        _hr = hr;
        _move = mv;
      });
    } catch (_) {}
  }

  int _tOf(double f) => _from + (f * (_to - _from)).round();

  void _touch(double f) {
    final t = _tOf(f.clamp(0.0, 1.0));
    final snapped = (t / 60).round() * 60;
    if (_mode == null) {
      final reach = math.max(120, (_to - _from) ~/ 10);
      final ds = (t - _s).abs(), de = (t - _e).abs();
      _mode = math.min(ds, de) <= reach
          ? (ds <= de ? 1 : 2)
          : (t > _s && t < _e ? 3 : (ds <= de ? 1 : 2));
      _grabT = snapped;
      _grabS = _s;
      _grabE = _e;
    }
    var s = _s, e = _e;
    switch (_mode) {
      case 1:
        s = math.min(snapped, _e - 60).clamp(_from, _to).toInt();
      case 2:
        e = math.max(snapped, _s + 60).clamp(_from, _to).toInt();
      case 3:
        final d = snapped - _grabT;
        s = _grabS + d;
        e = _grabE + d;
    }
    if (s == _s && e == _e) return;
    setState(() {
      _s = s;
      _e = e;
    });
    widget.onChanged(s, e);
  }

  void _lift() {
    _mode = null;
    // Re-fit round where the lines were left, so a line taken to the edge
    // can be taken further on the next touch.
    setState(_fit);
    _load();
  }

  double? _bpmAt(int t) {
    HrPoint? best;
    for (final p in _hr) {
      if (best == null || (p.t - t).abs() < (best.t - t).abs()) best = p;
    }
    return best == null || (best.t - t).abs() > 180 ? null : best.v;
  }

  String _clock(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return formatClock(d.hour, d.minute);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final lane = _move.any((m) => m.v > 0);
    final height = ActivityWindowChart.labels +
        ActivityWindowChart.plot +
        (lane ? S.x3 + ActivityWindowChart.lane : 0);
    return SizedBox(
      height: height,
      child: Scrubber(
        value: null,
        onChanged: _touch,
        onLift: _lift,
        yieldToScroll: true,
        label: 'Activity time on the heart rate. Drag a line to move it',
        describe: (f) => _clock(_tOf(f)),
        child: CustomPaint(
          size: Size.infinite,
          painter: _ChartPaint(
            hr: _hr,
            move: lane ? _move : const [],
            from: _from,
            to: _to,
            start: _s,
            end: _e,
            ink: p.ink,
            ink3: p.ink3,
            knobInk: p.bg,
            startLabel: _clock(_s),
            endLabel: _clock(_e),
            startBpm: _bpmAt(_s),
            endBpm: _bpmAt(_e),
          ),
        ),
      ),
    );
  }
}

class _ChartPaint extends CustomPainter {
  final List<HrPoint> hr;
  final List<MovePoint> move;
  final int from, to, start, end;
  final Color ink, ink3, knobInk;
  final String startLabel, endLabel;
  final double? startBpm, endBpm;

  _ChartPaint({
    required this.hr,
    required this.move,
    required this.from,
    required this.to,
    required this.start,
    required this.end,
    required this.ink,
    required this.ink3,
    required this.knobInk,
    required this.startLabel,
    required this.endLabel,
    required this.startBpm,
    required this.endBpm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const top = ActivityWindowChart.labels;
    final floor = top + ActivityWindowChart.plot - ActivityWindowChart.knob;
    final plot = Rect.fromLTRB(0, top + S.x3, w, floor);
    double xOf(num t) => (t - from) / math.max(1, to - from) * w;
    final x0 = xOf(start), x1 = xOf(end);

    // The scale: what is in view, with a little room.
    final vs = [for (final e in hr) if (e.t >= from && e.t <= to) e.v];
    var lo = 60.0, hi = 140.0;
    if (vs.isNotEmpty) {
      lo = vs.reduce(math.min) - 6;
      hi = vs.reduce(math.max) + 4;
      if (hi - lo < 30) hi = lo + 30;
    }
    double yOf(double v) =>
        plot.bottom - (v - lo) / (hi - lo) * plot.height;

    // The line, broken where the band has a gap of over three minutes.
    final runs = <List<Offset>>[];
    int? last;
    for (final e in hr) {
      if (e.t < from - 60 || e.t > to + 60) continue;
      if (last == null || e.t - last > 180) runs.add([]);
      runs.last.add(Offset(xOf(e.t), yOf(e.v)));
      last = e.t;
    }
    Path lineOf(List<Offset> pts) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      return path;
    }

    final inside = Rect.fromLTRB(x0, 0, x1, size.height);
    for (final run in runs) {
      if (run.length < 2) continue;
      final line = lineOf(run);
      // Dimmed outside the activity.
      canvas.save();
      canvas.clipPath(Path.combine(PathOperation.difference,
          Path()..addRect(Offset.zero & size), Path()..addRect(inside)));
      canvas.drawPath(
          line,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = S.half
            ..strokeJoin = StrokeJoin.round
            ..color = C.dialStrain.withValues(alpha: .45));
      canvas.restore();
      // Bright and filled inside it.
      canvas.save();
      canvas.clipRect(inside);
      final fill = Path.from(line)
        ..lineTo(run.last.dx, plot.bottom)
        ..lineTo(run.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                C.dialStrain.withValues(alpha: .42),
                C.dialStrain.withValues(alpha: 0),
              ],
            ).createShader(plot));
      canvas.drawPath(
          line,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = S.half
            ..strokeJoin = StrokeJoin.round
            ..color = C.dialStrain);
      canvas.restore();
    }

    // Each line: dotted from under its label down to its knob.
    final dot = Paint()
      ..color = ink
      ..strokeWidth = 1.2;
    for (final x in [x0, x1]) {
      for (var y = top; y < floor; y += S.x1 + S.half) {
        canvas.drawLine(
            Offset(x, y), Offset(x, math.min(y + S.x1 - S.hair, floor)), dot);
      }
    }

    // The time and bpm over each line: the start's reading to its right,
    // the end's to its left, each kept on the chart.
    void label(double x, String time, double? bpm, bool atStart) {
      final t = _tp(time,
          F.num(F.cap).copyWith(color: ink, fontWeight: FontWeight.w700));
      final b = _tp(bpm == null ? '' : '${bpm.round()}bpm',
          F.num(F.over).copyWith(
              color: C.dialStrain, fontWeight: FontWeight.w700));
      final wide = math.max(t.width, b.width);
      final left = (atStart ? x : x - wide).clamp(0.0, math.max(0.0, w - wide));
      final align = atStart ? 0.0 : 1.0;
      t.paint(canvas, Offset(left + (wide - t.width) * align, 0));
      b.paint(canvas, Offset(left + (wide - b.width) * align, t.height));
      t.dispose();
      b.dispose();
    }

    label(x0, startLabel, startBpm, true);
    label(x1, endLabel, endBpm, false);

    // The knobs: white, three dark grips.
    for (final x in [x0, x1]) {
      final o = Offset(x, floor);
      canvas.drawCircle(o, ActivityWindowChart.knob, Paint()..color = ink);
      final grip = Paint()
        ..color = knobInk
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      for (final dx in [-S.x1 + S.hair, 0.0, S.x1 - S.hair]) {
        canvas.drawLine(Offset(x + dx, floor - S.x1),
            Offset(x + dx, floor + S.x1), grip);
      }
    }

    // The wrist's movement under it, brighter within the activity.
    if (move.isNotEmpty) {
      final laneTop = top + ActivityWindowChart.plot + S.x3;
      final laneRect =
          Rect.fromLTWH(0, laneTop, w, ActivityWindowChart.lane);
      canvas.save();
      canvas.clipPath(Path.combine(PathOperation.difference,
          Path()..addRect(laneRect), Path()..addRect(inside)));
      paintMovement(canvas, laneRect, move, xOf, ink3.withValues(alpha: .22));
      canvas.restore();
      canvas.save();
      canvas.clipRect(inside);
      paintMovement(canvas, laneRect, move, xOf, ink3.withValues(alpha: .6));
      canvas.restore();
    }
  }

  TextPainter _tp(String s, TextStyle st) => TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  @override
  bool shouldRepaint(_ChartPaint o) =>
      o.hr != hr ||
      o.move != move ||
      o.from != from ||
      o.to != to ||
      o.start != start ||
      o.end != end ||
      o.ink != ink;
}
