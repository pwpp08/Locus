// WINDOW EDITOR: one screen for "when was it". A sleep entered by hand, a
// nap or workout the detector proposed, a sleep or nap added from Add
// activity: each is two moments, and the one thing that shows when they were
// is the heart rate around them. So the chart comes first, a day or two of the
// band's per-minute heart rate, with the window drawn on it as two lines and
// the stretch between them shaded. A finger drags the nearer line, two fingers
// zoom; the two pickers under the chart set the same moments to the minute.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../state/clock_format.dart';
import '../../theme/theme_switcher.dart' show themedRoute;
import '../ui2.dart';
import 'home_screen.dart' show pad;

/// What the window is: its colour, its limits and its words.
enum WindowKind { sleep, nap, workout }

typedef HrPoint = ({int t, double v});

/// Per-minute heart rate between two epoch seconds, oldest first.
typedef HrReader = Future<List<HrPoint>> Function(int from, int to);

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

const _hour = 3600;
const _day = 24 * _hour;

/// The shortest and longest window each kind may be, in minutes.
(int, int) windowLimits(WindowKind k) => switch (k) {
      WindowKind.sleep => (30, 18 * 60),
      WindowKind.nap => (5, 6 * 60),
      WindowKind.workout => (1, 12 * 60),
    };

/// Why [start]–[end] cannot be saved as a [k], or null when it can.
String? windowProblem(WindowKind k, DateTime start, DateTime end, DateTime now) {
  if (!end.isAfter(start)) return 'The end has to come after the start.';
  if (end.isAfter(now)) return 'The end has not happened yet.';
  final min = end.difference(start).inMinutes;
  final (lo, hi) = windowLimits(k);
  String span(int m) => m % 60 == 0 ? '${m ~/ 60} hours' : '$m minutes';
  final what = switch (k) {
    WindowKind.sleep => 'A sleep',
    WindowKind.nap => 'A nap',
    WindowKind.workout => 'An activity',
  };
  if (min < lo || min > hi) {
    return '$what lasts between ${span(lo)} and ${span(hi)}.';
  }
  return null;
}

/// Opens the editor and returns the chosen window, or null when it was left.
Future<(DateTime, DateTime)?> openWindowEditor(
  BuildContext c, {
  required WindowKind kind,
  required String title,
  required DateTime start,
  required DateTime end,
  String save = 'Save',
  HrReader? hr,
}) =>
    Navigator.of(c).push<(DateTime, DateTime)>(themedRoute(
      (_) => WindowEditor(
          kind: kind, title: title, start: start, end: end, save: save, hr: hr),
      name: 'WindowEditor',
    ));

class WindowEditor extends StatefulWidget {
  final WindowKind kind;
  final String title;
  final DateTime start, end;
  final String save;

  /// Where the heart rate comes from; the band's own store when null.
  final HrReader? hr;

  /// "Now", for a test.
  final DateTime? now;

  const WindowEditor({
    super.key,
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
    this.save = 'Save',
    this.hr,
    this.now,
  });

  @override
  State<WindowEditor> createState() => _WindowEditorState();
}

class _WindowEditorState extends State<WindowEditor> {
  late DateTime _start = widget.start, _end = widget.end;

  /// The chart's view: its right edge and its width, in epoch seconds.
  late int _viewEnd;
  int _span = _day;

  List<HrPoint> _hr = const [];
  int? _loadedFrom, _loadedTo;
  bool _loading = false;

  /// The line a drag holds, until the finger lifts: true the start.
  bool? _grab;

  /// The view when a pinch began.
  int _pinchSpan = _day, _pinchFrom = 0;

  DateTime get _now => widget.now ?? DateTime.now();
  int get _nowSec => _now.millisecondsSinceEpoch ~/ 1000;
  static int _sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
  static DateTime _at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000);

  @override
  void initState() {
    super.initState();
    _frame(_day);
  }

  /// The window in the middle of a view [span] wide, never past now.
  void _frame(int span) {
    _span = span;
    final mid = (_sec(_start) + _sec(_end)) ~/ 2;
    _viewEnd = math.min(_nowSec + _hour ~/ 2, mid + span ~/ 2);
    // A window wider than the view still starts on screen.
    if (_viewEnd - span > _sec(_start)) _viewEnd = _sec(_start) + span;
    _ensure();
  }

  /// Reads the heart rate the view needs, a day either side, once.
  Future<void> _ensure() async {
    final from = _viewEnd - _span, to = _viewEnd;
    if (_loading ||
        (_loadedFrom != null && from >= _loadedFrom! && to <= _loadedTo!)) {
      return;
    }
    _loading = true;
    final a = from - _day, b = math.min(to + _day, _nowSec);
    final pts = await (widget.hr ?? _readHr)(a, b);
    if (!mounted) return;
    setState(() {
      _hr = pts;
      _loadedFrom = a;
      _loadedTo = b;
      _loading = false;
    });
  }

  /// A finger on the chart: the nearer line follows it, to five minutes.
  void _drag(double f) {
    final t = _viewEnd - _span + (f * _span).round();
    final snapped = (t / 300).round() * 300;
    _grab ??= (snapped - _sec(_start)).abs() <= (snapped - _sec(_end)).abs();
    setState(() {
      if (_grab!) {
        _start = _at(math.min(snapped, _sec(_end) - 300));
      } else {
        _end = _at(math.max(snapped, _sec(_start) + 300));
      }
    });
  }

  void _pinch(PinchPhase phase, double scale, double focal, double pan) {
    switch (phase) {
      case PinchPhase.start:
        _pinchSpan = _span;
        _pinchFrom = _viewEnd - _span;
      case PinchPhase.update:
        final span =
            (_pinchSpan / math.max(scale, .01)).round().clamp(_hour, 2 * _day);
        final at = _pinchFrom + (focal * _pinchSpan).round();
        final from = at - ((focal + pan) * span).round();
        setState(() {
          _span = span;
          _viewEnd = math.min(from + span, _nowSec + _hour);
        });
      case PinchPhase.end:
        _ensure();
    }
  }

  Future<void> _pick(bool start) async {
    final value = start ? _start : _end;
    final day = await showDatePicker(
      context: context,
      initialDate: value.isAfter(_now) ? _now : value,
      firstDate: DateTime(2000),
      lastDate: _now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
    // The view follows the window when it moved off screen.
    final from = _viewEnd - _span;
    if (_sec(picked) < from || _sec(picked) > _viewEnd) _frame(_span);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final problem = windowProblem(widget.kind, _start, _end, _now);
    final minutes = _end.difference(_start).inMinutes;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: pad,
          children: [
            NavBar(widget.title),
            const SizedBox(height: S.x2),
            Row(children: [
              _spanChip(c, '1 DAY', _day),
              const SizedBox(width: S.x2),
              _spanChip(c, '2 DAYS', 2 * _day),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text('Pinch to zoom',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.cap.copyWith(color: p.ink3)),
              ),
            ]),
            const SizedBox(height: S.x3),
            _chart(c, p),
            const SizedBox(height: S.x2),
            Text(
              'Drag a line, or set the times below. Your heart rate drops '
              'and steadies while you ${widget.kind == WindowKind.workout ? 'rest' : 'sleep'}.',
              style: F.cap.copyWith(color: p.ink3, height: 1.4),
            ),
            const SizedBox(height: S.x4),
            Row(children: [
              Expanded(child: _timeTile(c, p, 'START', _start, () => _pick(true))),
              const SizedBox(width: S.x3),
              Expanded(child: _timeTile(c, p, 'END', _end, () => _pick(false))),
            ]),
            const SizedBox(height: S.x4),
            Center(
              child: Text(
                minutes > 0 ? '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m' : '--',
                style: F.num(F.n34).copyWith(color: p.ink, fontWeight: FontWeight.w700),
              ),
            ),
            Center(
              child: Text(
                widget.kind == WindowKind.workout ? 'DURATION' : 'TIME IN BED',
                style: F.caps.copyWith(color: p.ink3),
              ),
            ),
            const SizedBox(height: S.x4),
            if (problem != null) ...[
              Center(
                child: Text(problem,
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(color: C.orange)),
              ),
              const SizedBox(height: S.x3),
            ],
            BigButton(
              widget.save,
              icon: LucideIcons.check,
              onTap: problem != null
                  ? null
                  : () => Navigator.of(c).pop((_start, _end)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spanChip(BuildContext c, String label, int span) {
    final p = P.of(c);
    final on = _span == span;
    return Pressable(
      onTap: () => setState(() => _frame(span)),
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
        decoration: BoxDecoration(
          color: on ? p.ink : p.card,
          borderRadius: R.rPill,
        ),
        child: Text(label,
            style: F.caps.copyWith(color: on ? p.bg : p.ink2)),
      ),
    );
  }

  Widget _timeTile(
      BuildContext c, P p, String label, DateTime t, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label ${_date(t)} ${formatClock(t.hour, t.minute)}',
      child: Container(
        padding: const EdgeInsets.all(S.x4),
        decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: F.caps.copyWith(color: p.ink3)),
          const SizedBox(height: S.x2),
          Text(formatClock(t.hour, t.minute),
              style: F.num(F.n24).copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: S.x1),
          Text(_date(t), style: F.cap.copyWith(color: p.ink2)),
        ]),
      ),
    );
  }

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static String _date(DateTime d) =>
      '${_wd[d.weekday - 1]}, ${_mo[d.month - 1]} ${d.day}';

  Widget _chart(BuildContext c, P p) {
    const h = S.x16 * 4;
    final from = _viewEnd - _span;
    final s = _sec(_start), e = _sec(_end);
    return SizedBox(
      height: h,
      child: Builder(builder: (c) {
        return Scrubber(
          value: null,
          onChanged: _drag,
          onLift: () {
            _grab = null;
            _ensure();
          },
          yieldToScroll: true,
          onPinch: _pinch,
          label: 'Heart rate around the window',
          describe: (f) {
            final t = _at(from + (f * _span).round());
            return formatClock(t.hour, t.minute);
          },
          child: WindowChart(
            hr: _hr,
            from: from,
            span: _span,
            start: s,
            end: e,
            kind: widget.kind,
            empty: _hr.isEmpty && !_loading,
          ),
        );
      }),
    );
  }
}

/// The heart rate from [from] for [span] seconds, with the window [start]–
/// [end] drawn on it: two lines, the stretch between them shaded, a moon over
/// a sleep. Draws only; the editor puts the gestures over it.
class WindowChart extends StatelessWidget {
  final List<HrPoint> hr;
  final int from, span, start, end;
  final WindowKind kind;

  /// Nothing was recorded here: says so instead of an empty grid.
  final bool empty;

  const WindowChart({
    super.key,
    required this.hr,
    required this.from,
    required this.span,
    required this.start,
    required this.end,
    required this.kind,
    this.empty = false,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final tint = kind == WindowKind.workout ? C.dialStrain : C.dialSleep;
    return LayoutBuilder(builder: (c, box) {
      final w = box.maxWidth;
      double xOf(int t) => (t - from) / span * w;
      final x0 = xOf(start), x1 = xOf(end);
      return Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _WindowChartPainter(
              hr: hr,
              from: from,
              span: span,
              start: start,
              end: end,
              tint: tint,
              line: C.domHealth,
              ink: p.ink,
              ink3: p.ink3,
              grid: p.line,
            ),
          ),
        ),
        if (kind != WindowKind.workout && x1 > 0 && x0 < w && x1 - x0 > I.md)
          Positioned(
            left: (math.max(x0, 0) + math.min(x1, w)) / 2 - I.md / 2,
            top: 0,
            child: Icon(LucideIcons.moon, size: I.md, color: p.ink),
          ),
        if (empty)
          Center(
            child: Text('No heart rate in this stretch',
                style: F.cap.copyWith(color: p.ink3)),
          ),
      ]);
    });
  }
}

/// [WindowChart] over the band's own heart rate, a few hours either side of
/// the window: the preview on a detected activity's card.
class WindowPreview extends StatefulWidget {
  final int start, end;
  final WindowKind kind;
  final HrReader? hr;
  final double height;

  const WindowPreview({
    super.key,
    required this.start,
    required this.end,
    required this.kind,
    this.hr,
    this.height = S.x16 * 2 + S.x8,
  });

  @override
  State<WindowPreview> createState() => _WindowPreviewState();
}

class _WindowPreviewState extends State<WindowPreview> {
  List<HrPoint>? _hr;

  /// The view: the window and a third of its length (an hour at least) on
  /// each side, so the drop into it and the rise out of it both show.
  (int, int) get _view {
    final pad = math.max(_hour, (widget.end - widget.start) ~/ 3);
    return (widget.start - pad, widget.end + pad);
  }

  @override
  void initState() {
    super.initState();
    final (a, b) = _view;
    (widget.hr ?? _readHr)(a, b).then((pts) {
      if (mounted) setState(() => _hr = pts);
    });
  }

  @override
  Widget build(BuildContext c) {
    final (a, b) = _view;
    return SizedBox(
      height: widget.height,
      child: WindowChart(
        hr: _hr ?? const [],
        from: a,
        span: b - a,
        start: widget.start,
        end: widget.end,
        kind: widget.kind,
        empty: _hr != null && _hr!.isEmpty,
      ),
    );
  }
}

class _WindowChartPainter extends CustomPainter {
  final List<HrPoint> hr;
  final int from, span, start, end;
  final Color tint, line, ink, ink3, grid;

  _WindowChartPainter({
    required this.hr,
    required this.from,
    required this.span,
    required this.start,
    required this.end,
    required this.tint,
    required this.line,
    required this.ink,
    required this.ink3,
    required this.grid,
  });

  static const _top = S.x8, _bottom = S.x6;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final plot = Rect.fromLTRB(0, _top, w, size.height - _bottom);
    double xOf(int t) => (t - from) / span * w;
    final to = from + span;
    final shown = [for (final p in hr) if (p.t >= from && p.t <= to) p];

    // The scale: the visible heart rate, padded to whole tens.
    var lo = 40.0, hi = 120.0;
    if (shown.isNotEmpty) {
      final vs = shown.map((p) => p.v);
      lo = ((vs.reduce(math.min) - 5) / 10).floor() * 10.0;
      hi = ((vs.reduce(math.max) + 5) / 10).ceil() * 10.0;
      if (hi - lo < 30) hi = lo + 30;
    }
    double yOf(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;

    // The window, behind everything: a soft fill and a lit band at the top.
    final x0 = xOf(start).clamp(0.0, w), x1 = xOf(end).clamp(0.0, w);
    if (x1 > x0) {
      canvas.drawRect(Rect.fromLTRB(x0, plot.top, x1, plot.bottom),
          Paint()..color = tint.withValues(alpha: .16));
      canvas.drawRect(Rect.fromLTRB(x0, plot.top, x1, plot.top + S.half),
          Paint()..color = tint);
    }

    // Three grid lines and their labels.
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [lo, (lo + hi) / 2, hi]) {
      final y = yOf(v);
      canvas.drawLine(Offset(0, y), Offset(w, y), gp);
      _text(canvas, '${v.round()}', Offset(S.x1, y - S.x4), ink3);
    }

    // The heart rate, broken where the band was off.
    final path = Path();
    HrPoint? prev;
    for (final p in shown) {
      final o = Offset(xOf(p.t), yOf(p.v));
      if (prev == null || p.t - prev.t > 300) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
      prev = p;
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);

    // The two lines, each with a handle at its foot.
    for (final t in [start, end]) {
      final x = xOf(t);
      if (x < -S.x2 || x > w + S.x2) continue;
      final lp = Paint()
        ..color = ink
        ..strokeWidth = S.half;
      canvas.drawLine(Offset(x, plot.top - S.x2), Offset(x, plot.bottom), lp);
      canvas.drawCircle(Offset(x, plot.bottom), S.x1 + S.half, Paint()..color = ink);
    }

    // Clock times along the foot, at a step that leaves room for each.
    const steps = [1800, 3600, 7200, 10800, 21600, 43200];
    final step = steps.firstWhere((s) => span / s <= 5, orElse: () => 43200);
    final first = DateTime.fromMillisecondsSinceEpoch(from * 1000);
    // Local step boundaries: whole hours from local midnight.
    final midnight = DateTime(first.year, first.month, first.day);
    var t = midnight.millisecondsSinceEpoch ~/ 1000;
    while (t < from) {
      t += step;
    }
    for (; t <= to; t += step) {
      final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
      final x = xOf(t);
      if (x < S.x6 || x > w - S.x6) continue;
      _text(canvas, formatClock(d.hour, d.minute),
          Offset(x, size.height - _bottom + S.x1), ink3,
          centre: true);
    }
  }

  void _text(Canvas canvas, String s, Offset at, Color color,
      {bool centre = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: F.num(F.over).copyWith(color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre ? at - Offset(tp.width / 2, 0) : at);
  }

  @override
  bool shouldRepaint(_WindowChartPainter o) =>
      o.hr != hr ||
      o.from != from ||
      o.span != span ||
      o.start != start ||
      o.end != end ||
      o.ink != ink;
}
