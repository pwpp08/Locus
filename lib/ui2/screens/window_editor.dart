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
String? windowProblem(
  WindowKind k,
  DateTime start,
  DateTime end,
  DateTime now,
) {
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
}) => Navigator.of(c).push<(DateTime, DateTime)>(
  themedRoute(
    (_) => WindowEditor(
      kind: kind,
      title: title,
      start: start,
      end: end,
      save: save,
      hr: hr,
    ),
    name: 'WindowEditor',
  ),
);

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

  /// The line a drag holds, until the finger lifts: 1 = start, 2 = end, 3 = window slide.
  int? _dragMode;
  int? _dragInitialT;
  int? _initialStartSec;
  int? _initialEndSec;

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

  /// A finger on the chart: dragging near an edge adjusts that edge; dragging inside moves the window.
  void _drag(double f) {
    final t = _viewEnd - _span + (f * _span).round();
    final snapSec = _span <= 2 * 3600 ? 60 : 300;
    final snapped = (t / snapSec).round() * snapSec;
    final s = _sec(_start);
    final e = _sec(_end);
    final threshold = math.max(snapSec * 2, (_span * 0.08).round());

    if (_dragMode == null) {
      if ((t - s).abs() <= threshold && (t - s).abs() < (t - e).abs()) {
        _dragMode = 1; // start handle
      } else if ((t - e).abs() <= threshold) {
        _dragMode = 2; // end handle
      } else if (t > s && t < e) {
        _dragMode = 3; // whole window slide
        _dragInitialT = snapped;
        _initialStartSec = s;
        _initialEndSec = e;
      } else {
        _dragMode = (t - s).abs() <= (t - e).abs() ? 1 : 2;
      }
    }

    setState(() {
      if (_dragMode == 1) {
        _start = _at(math.min(snapped, _sec(_end) - snapSec));
      } else if (_dragMode == 2) {
        _end = _at(math.max(snapped, _sec(_start) + snapSec));
      } else if (_dragMode == 3 &&
          _dragInitialT != null &&
          _initialStartSec != null &&
          _initialEndSec != null) {
        final delta = snapped - _dragInitialT!;
        final newStart = _initialStartSec! + delta;
        final newEnd = _initialEndSec! + delta;
        if (newEnd <= _nowSec + 1800) {
          _start = _at(newStart);
          _end = _at(newEnd);
        }
      }
    });
  }

  void _pinch(PinchPhase phase, double scale, double focal, double pan) {
    switch (phase) {
      case PinchPhase.start:
        _pinchSpan = _span;
        _pinchFrom = _viewEnd - _span;
      case PinchPhase.update:
        final span = (_pinchSpan / math.max(scale, .01)).round().clamp(
          15 * 60,
          2 * _day,
        );
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

  void _zoom(double factor) {
    final nextSpan = (_span * factor).round().clamp(15 * 60, 2 * _day);
    setState(() {
      _frame(nextSpan);
    });
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
    final picked = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
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
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: S.x1,
                    runSpacing: S.x1,
                    children: [
                      _spanChip(c, '30M', 1800),
                      _spanChip(c, '2H', 2 * _hour),
                      _spanChip(c, '6H', 6 * _hour),
                      _spanChip(c, '1D', _day),
                      _spanChip(c, '2D', 2 * _day),
                    ],
                  ),
                ),
                Pressable(
                  onTap: () => _zoom(1 / 1.6),
                  semanticLabel: 'Zoom in',
                  child: Container(
                    padding: const EdgeInsets.all(S.x1 + S.half),
                    decoration: BoxDecoration(
                      color: p.card2,
                      borderRadius: R.rSm,
                    ),
                    child: Icon(LucideIcons.plus, size: I.sm, color: p.ink),
                  ),
                ),
                const SizedBox(width: S.x1),
                Pressable(
                  onTap: () => _zoom(1.6),
                  semanticLabel: 'Zoom out',
                  child: Container(
                    padding: const EdgeInsets.all(S.x1 + S.half),
                    decoration: BoxDecoration(
                      color: p.card2,
                      borderRadius: R.rSm,
                    ),
                    child: Icon(LucideIcons.minus, size: I.sm, color: p.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.x3),
            _chart(c, p),
            const SizedBox(height: S.x2),
            Text(
              'Drag edges to adjust start/end, slide center to move, pinch or use +/- to zoom.',
              style: F.cap.copyWith(color: p.ink3, height: 1.4),
            ),
            const SizedBox(height: S.x4),
            Row(
              children: [
                Expanded(
                  child: _timeTile(c, p, 'START', _start, () => _pick(true)),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: _timeTile(c, p, 'END', _end, () => _pick(false)),
                ),
              ],
            ),
            const SizedBox(height: S.x4),
            Center(
              child: Text(
                minutes > 0
                    ? '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m'
                    : '--',
                style: F.num(
                  F.n34,
                ).copyWith(color: p.ink, fontWeight: FontWeight.w700),
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
                child: Text(
                  problem,
                  textAlign: TextAlign.center,
                  style: F.cap.copyWith(color: C.orange),
                ),
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
        child: Text(label, style: F.caps.copyWith(color: on ? p.bg : p.ink2)),
      ),
    );
  }

  Widget _timeTile(
    BuildContext c,
    P p,
    String label,
    DateTime t,
    VoidCallback onTap,
  ) {
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label ${_date(t)} ${formatClock(t.hour, t.minute)}',
      child: Container(
        padding: const EdgeInsets.all(S.x4),
        decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: F.caps.copyWith(color: p.ink3)),
            const SizedBox(height: S.x2),
            Text(
              formatClock(t.hour, t.minute),
              style: F.num(
                F.n24,
              ).copyWith(color: p.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: S.x1),
            Text(_date(t), style: F.cap.copyWith(color: p.ink2)),
          ],
        ),
      ),
    );
  }

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static String _date(DateTime d) =>
      '${_wd[d.weekday - 1]}, ${_mo[d.month - 1]} ${d.day}';

  Widget _chart(BuildContext c, P p) {
    const h = S.x16 * 4;
    final from = _viewEnd - _span;
    final s = _sec(_start), e = _sec(_end);
    return SizedBox(
      height: h,
      child: Builder(
        builder: (c) {
          return Scrubber(
            value: null,
            onChanged: _drag,
            onLift: () {
              _dragMode = null;
              _dragInitialT = null;
              _initialStartSec = null;
              _initialEndSec = null;
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
        },
      ),
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
    return LayoutBuilder(
      builder: (c, box) {
        final w = box.maxWidth;
        double xOf(int t) => (t - from) / span * w;
        final x0 = xOf(start), x1 = xOf(end);
        return Stack(
          clipBehavior: Clip.none,
          children: [
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
            if (kind != WindowKind.workout &&
                x1 > 0 &&
                x0 < w &&
                x1 - x0 > I.md)
              Positioned(
                left: (math.max(x0, 0) + math.min(x1, w)) / 2 - I.md / 2,
                top: 0,
                child: Icon(LucideIcons.moon, size: I.md, color: p.ink),
              ),
            if (empty)
              Center(
                child: Text(
                  'No heart rate in this stretch',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// [WindowChart] over the band's own heart rate, a few hours either side of
/// the window: interactive with dragging handles, window sliding, and zooming.
class WindowPreview extends StatefulWidget {
  final int start, end;
  final WindowKind kind;
  final HrReader? hr;
  final double height;
  final void Function(int start, int end)? onChanged;
  final VoidCallback? onExpand;

  const WindowPreview({
    super.key,
    required this.start,
    required this.end,
    required this.kind,
    this.hr,
    this.height = S.x16 * 2 + S.x8,
    this.onChanged,
    this.onExpand,
  });

  @override
  State<WindowPreview> createState() => _WindowPreviewState();
}

class _WindowPreviewState extends State<WindowPreview> {
  List<HrPoint>? _hr;
  int? _loadedFrom, _loadedTo;
  bool _loading = false;

  late int _curStart, _curEnd;
  late int _viewFrom, _viewSpan;

  int? _dragMode; // 1: start handle, 2: end handle, 3: whole window slide
  int? _dragInitialT;
  int? _initialStartSec;
  int? _initialEndSec;

  int _pinchSpan = 0;
  int _pinchFrom = 0;

  @override
  void initState() {
    super.initState();
    _curStart = widget.start;
    _curEnd = widget.end;
    _initView();
    _loadHr();
  }

  void _initView() {
    final dur = math.max(60, _curEnd - _curStart);
    final pad = math.max(_hour, dur ~/ 3);
    _viewFrom = _curStart - pad;
    _viewSpan = dur + 2 * pad;
  }

  @override
  void didUpdateWidget(WindowPreview old) {
    super.didUpdateWidget(old);
    if (_dragMode == null &&
        (old.start != widget.start || old.end != widget.end)) {
      _curStart = widget.start;
      _curEnd = widget.end;
      if (_curStart < _viewFrom || _curEnd > _viewFrom + _viewSpan) {
        _initView();
      }
      _loadHr();
    }
  }

  Future<void> _loadHr() async {
    final reader = widget.hr ?? _readHr;
    final from = _viewFrom - _hour;
    final to = _viewFrom + _viewSpan + _hour;
    if (_loading ||
        (_loadedFrom != null && from >= _loadedFrom! && to <= _loadedTo!)) {
      return;
    }
    _loading = true;
    try {
      final pts = await reader(from, to);
      if (mounted) {
        setState(() {
          _hr = pts;
          _loadedFrom = from;
          _loadedTo = to;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _zoom(double factor) {
    final center = _viewFrom + _viewSpan ~/ 2;
    final newSpan = (_viewSpan * factor).round().clamp(15 * 60, 2 * _day);
    setState(() {
      _viewSpan = newSpan;
      _viewFrom = center - newSpan ~/ 2;
    });
    _loadHr();
  }

  void _drag(double f) {
    final t = _viewFrom + (f * _viewSpan).round();
    final snapSec = _viewSpan <= 2 * 3600 ? 60 : 300;
    final snapped = (t / snapSec).round() * snapSec;
    final s = _curStart;
    final e = _curEnd;
    final threshold = math.max(snapSec * 2, (_viewSpan * 0.08).round());

    if (_dragMode == null) {
      if ((t - s).abs() <= threshold && (t - s).abs() < (t - e).abs()) {
        _dragMode = 1;
      } else if ((t - e).abs() <= threshold) {
        _dragMode = 2;
      } else if (t > s && t < e) {
        _dragMode = 3;
        _dragInitialT = snapped;
        _initialStartSec = s;
        _initialEndSec = e;
      } else {
        _dragMode = (t - s).abs() <= (t - e).abs() ? 1 : 2;
      }
    }

    int newS = s;
    int newE = e;
    if (_dragMode == 1) {
      newS = math.min(snapped, e - snapSec);
    } else if (_dragMode == 2) {
      newE = math.max(snapped, s + snapSec);
    } else if (_dragMode == 3 &&
        _dragInitialT != null &&
        _initialStartSec != null &&
        _initialEndSec != null) {
      final delta = snapped - _dragInitialT!;
      newS = _initialStartSec! + delta;
      newE = _initialEndSec! + delta;
    }

    if (newS != _curStart || newE != _curEnd) {
      setState(() {
        _curStart = newS;
        _curEnd = newE;
      });
      widget.onChanged?.call(newS, newE);
    }
  }

  void _onLift() {
    _dragMode = null;
    _dragInitialT = null;
    _initialStartSec = null;
    _initialEndSec = null;
    _loadHr();
  }

  void _pinch(PinchPhase phase, double scale, double focal, double pan) {
    switch (phase) {
      case PinchPhase.start:
        _pinchSpan = _viewSpan;
        _pinchFrom = _viewFrom;
      case PinchPhase.update:
        final span = (_pinchSpan / math.max(scale, .01)).round().clamp(
          15 * 60,
          2 * _day,
        );
        final at = _pinchFrom + (focal * _pinchSpan).round();
        final from = at - ((focal + pan) * span).round();
        setState(() {
          _viewSpan = span;
          _viewFrom = from;
        });
        _loadHr();
      case PinchPhase.end:
        _loadHr();
    }
  }

  DateTime _at(int sec) => DateTime.fromMillisecondsSinceEpoch(sec * 1000);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final isInteractive = widget.onChanged != null;

    final chartWidget = WindowChart(
      hr: _hr ?? const [],
      from: _viewFrom,
      span: _viewSpan,
      start: _curStart,
      end: _curEnd,
      kind: widget.kind,
      empty: _hr != null && _hr!.isEmpty,
    );

    if (!isInteractive && widget.onExpand == null) {
      return SizedBox(height: widget.height, child: chartWidget);
    }

    final durSec = math.max(0, _curEnd - _curStart);
    final minutes = durSec ~/ 60;
    final durStr = minutes >= 60
        ? '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m'
        : '${minutes}m';
    final dtStart = _at(_curStart);
    final dtEnd = _at(_curEnd);
    final timeRangeStr =
        '${formatClock(dtStart.hour, dtStart.minute)} - ${formatClock(dtEnd.hour, dtEnd.minute)}';

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: R.rLg,
        border: Border.all(color: p.line.withValues(alpha: .6), width: 1),
      ),
      padding: const EdgeInsets.all(S.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HEART RATE WINDOW',
                    style: F.caps.copyWith(color: p.ink3, letterSpacing: 1.2),
                  ),
                  const SizedBox(width: S.x2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (widget.kind == WindowKind.workout
                                  ? C.dialStrain
                                  : C.dialSleep)
                              .withValues(alpha: .15),
                      borderRadius: R.rSm,
                    ),
                    child: Text(
                      durStr,
                      style: F.num(F.over).copyWith(
                        color: widget.kind == WindowKind.workout
                            ? C.dialStrain
                            : C.dialSleep,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isInteractive) ...[
                    Pressable(
                      onTap: () => _zoom(0.67),
                      semanticLabel: 'Zoom in',
                      child: Container(
                        padding: const EdgeInsets.all(S.x1),
                        decoration: BoxDecoration(
                          color: p.card2,
                          borderRadius: R.rSm,
                        ),
                        child: Icon(LucideIcons.plus, size: I.sm, color: p.ink),
                      ),
                    ),
                    const SizedBox(width: S.x1),
                    Pressable(
                      onTap: () => _zoom(1.5),
                      semanticLabel: 'Zoom out',
                      child: Container(
                        padding: const EdgeInsets.all(S.x1),
                        decoration: BoxDecoration(
                          color: p.card2,
                          borderRadius: R.rSm,
                        ),
                        child: Icon(
                          LucideIcons.minus,
                          size: I.sm,
                          color: p.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: S.x2),
                  ],
                  if (widget.onExpand != null)
                    Pressable(
                      onTap: widget.onExpand,
                      semanticLabel: 'Open full window editor',
                      child: Container(
                        padding: const EdgeInsets.all(S.x1),
                        decoration: BoxDecoration(
                          color: p.card2,
                          borderRadius: R.rSm,
                        ),
                        child: Icon(
                          LucideIcons.maximize2,
                          size: I.sm,
                          color: p.ink,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          SizedBox(
            height: widget.height,
            child: isInteractive
                ? Scrubber(
                    value: null,
                    onChanged: _drag,
                    onLift: _onLift,
                    yieldToScroll: true,
                    onPinch: _pinch,
                    label: 'Heart rate window',
                    describe: (f) {
                      final t = _at(_viewFrom + (f * _viewSpan).round());
                      return formatClock(t.hour, t.minute);
                    },
                    child: chartWidget,
                  )
                : (widget.onExpand != null
                      ? Pressable(
                          onTap: widget.onExpand,
                          semanticLabel: 'Open window editor',
                          child: chartWidget,
                        )
                      : chartWidget),
          ),
          const SizedBox(height: S.x2),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: S.x2,
            runSpacing: S.x1,
            children: [
              Text(
                timeRangeStr,
                style: F.num(
                  F.over,
                ).copyWith(color: p.ink2, fontWeight: FontWeight.w600),
              ),
              if (isInteractive)
                Text(
                  'Slide lines • Drag center • Pinch / +/- to zoom',
                  style: F.over.copyWith(color: p.ink3),
                ),
            ],
          ),
        ],
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
    final shown = [
      for (final p in hr)
        if (p.t >= from && p.t <= to) p,
    ];

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
      canvas.drawRect(
        Rect.fromLTRB(x0, plot.top, x1, plot.bottom),
        Paint()..color = tint.withValues(alpha: .16),
      );
      canvas.drawRect(
        Rect.fromLTRB(x0, plot.top, x1, plot.top + S.half),
        Paint()..color = tint,
      );
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
        ..strokeJoin = StrokeJoin.round,
    );

    // The two lines, each with a handle at its foot and mid-height grab grip.
    for (final t in [start, end]) {
      final x = xOf(t);
      if (x < -S.x2 || x > w + S.x2) continue;
      final lp = Paint()
        ..color = ink
        ..strokeWidth = S.half;
      canvas.drawLine(Offset(x, plot.top - S.x2), Offset(x, plot.bottom), lp);
      // Foot circle
      canvas.drawCircle(
        Offset(x, plot.bottom),
        S.x1 + S.half,
        Paint()..color = ink,
      );

      // Mid-height grab handle pill
      final midY = (plot.top + plot.bottom) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, midY), width: S.x2, height: S.x6),
          const Radius.circular(S.x1),
        ),
        Paint()..color = ink,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, midY), width: 1.5, height: S.x3),
          const Radius.circular(0.75),
        ),
        Paint()..color = tint,
      );
    }

    // Clock times along the foot, at a step that leaves room for each.
    const steps = [300, 600, 900, 1800, 3600, 7200, 10800, 21600, 43200];
    final step = steps.firstWhere((s) => span / s <= 6, orElse: () => 43200);
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
      _text(
        canvas,
        formatClock(d.hour, d.minute),
        Offset(x, size.height - _bottom + S.x1),
        ink3,
        centre: true,
      );
    }
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at,
    Color color, {
    bool centre = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: F.num(F.over).copyWith(color: color),
      ),
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
