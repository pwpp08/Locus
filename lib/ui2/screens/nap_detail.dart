// A NAP, opened from My Day, the Naps list or the Sleep screen. Laid out like
// a recorded activity: the figure up top, the heart rate through the nap with
// the wrist's movement under it, then the key statistics.
//
// ONLY WHAT WAS MEASURED. The pipeline stores a nap as a window and the
// minutes asleep in it — no stages — so this screen draws no stages. It used
// to: deep sleep was set to 40 % of the nap, REM to 10 %, laid out in a
// scripted order, with wake events, latency and "typical ranges" computed
// from that script, a respiratory rate of 16.4 when none was read, and "this
// nap reduced your sleep need by N minutes" stating the raw nap minutes the
// sleep coach deliberately does not take (crossday_pipeline.dart). All of it
// is gone. What remains is the window, the minutes asleep, the heart rate the
// band recorded and the movement it measured.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compute/nap_edits.dart';
import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart';
import '../ui2.dart';
import 'home_screen.dart' show repoOf;
import 'movement_lane.dart';
import 'window_editor.dart' show HrPoint, WindowKind, openWindowEditor;

/// "0:52": hours and minutes, as a recorded activity writes its duration.
String _hmm(int min) => '${min ~/ 60}:${(min % 60).toString().padLeft(2, '0')}';

class NapDetailData {
  final String day;
  final int start, end;

  /// Minutes asleep, as the detector (or the user) recorded them. Null when
  /// the nap carries none — never the window's length standing in for it.
  final int? asleepMin;
  final String? source;

  /// What the chart shows: the nap with a little either side.
  final int from, to;
  final List<HrPoint> hr;

  /// The band's heart rate inside the nap itself.
  final int? avgHr, lowHr;
  final List<MovePoint> movement;

  const NapDetailData({
    required this.day,
    required this.start,
    required this.end,
    this.asleepMin,
    this.source,
    required this.from,
    required this.to,
    this.hr = const [],
    this.avgHr,
    this.lowHr,
    this.movement = const [],
  });

  int get inBedMin => math.max(0, (end - start) ~/ 60);

  /// The nap as the list handed it over, with nothing read around it.
  factory NapDetailData.bare(Map<String, dynamic> nap, {String? day}) {
    final (start, end) = _window(nap);
    final pad = math.max(60, (end - start) ~/ 12);
    return NapDetailData(
      day: day ??
          nap['day']?.toString() ??
          dayLabelOf(DateTime.fromMillisecondsSinceEpoch(start * 1000)),
      start: start,
      end: end,
      asleepMin: (nap['duration_min'] as num?)?.round(),
      source: nap['source']?.toString(),
      from: start - pad,
      to: end + pad,
    );
  }

  /// The window from whichever keys the caller's map uses. A missing end is
  /// the start plus the minutes asleep; a missing start is an empty window.
  static (int, int) _window(Map<String, dynamic> nap) {
    final start = ((nap['start'] ?? nap['start_ts'] ?? nap['onset_ts'])
            as num?)
        ?.toInt();
    final end = ((nap['end'] ?? nap['end_ts'] ?? nap['wake_ts']) as num?)
        ?.toInt();
    if (start == null || start <= 0) return (0, 0);
    if (end != null && end > start) return (start, end);
    final mins = (nap['duration_min'] as num?)?.toInt() ?? 0;
    return (start, start + mins * 60);
  }

  static Future<NapDetailData> load(
    LocalRepository repo,
    Map<String, dynamic> nap, {
    String? day,
  }) async {
    final b = NapDetailData.bare(nap, day: day);
    if (b.end <= b.start) return b;

    var sec = <(int, int)>[];
    try {
      final rows = await LocalDb.hrSamplesInRange(b.from, b.to);
      sec = [
        for (final r in rows)
          if (r['rec_ts'] is num && r['hr'] is num && (r['hr'] as num) > 0)
            ((r['rec_ts'] as num).toInt(), (r['hr'] as num).toInt()),
      ];
    } catch (_) {}

    // The trace, bucketed to about 160 points across the chart.
    final hr = <HrPoint>[];
    if (sec.isNotEmpty) {
      final bucket = math.max(5, (b.to - b.from) ~/ 160);
      var b0 = sec.first.$1 ~/ bucket, sum = 0, cnt = 0;
      for (final (t, v) in sec) {
        final k = t ~/ bucket;
        if (k != b0 && cnt > 0) {
          hr.add((t: b0 * bucket + bucket ~/ 2, v: sum / cnt));
          sum = 0;
          cnt = 0;
        }
        b0 = k;
        sum += v;
        cnt++;
      }
      if (cnt > 0) hr.add((t: b0 * bucket + bucket ~/ 2, v: sum / cnt));
    }

    // The nap's own seconds, for its average and its lowest minute.
    final inside = [
      for (final (t, v) in sec)
        if (t >= b.start && t <= b.end) (t, v),
    ];
    int? avg, low;
    if (inside.isNotEmpty) {
      avg = (inside.fold<int>(0, (a, e) => a + e.$2) / inside.length).round();
      // The lowest MINUTE, not the lowest second: one dropped beat is not a
      // resting heart rate.
      final mins = <int, (int, int)>{};
      for (final (t, v) in inside) {
        final m = mins[t ~/ 60] ?? (0, 0);
        mins[t ~/ 60] = (m.$1 + v, m.$2 + 1);
      }
      low = mins.values
          .where((m) => m.$2 >= 20)
          .map((m) => (m.$1 / m.$2).round())
          .fold<int?>(null, (a, v) => a == null || v < a ? v : a);
    }

    return NapDetailData(
      day: b.day,
      start: b.start,
      end: b.end,
      asleepMin: b.asleepMin,
      source: b.source,
      from: b.from,
      to: b.to,
      hr: hr,
      avgHr: avg,
      lowHr: low,
      movement: await readMovement(b.from, b.to, repo: repo, day: b.day),
    );
  }
}

class NapDetailScreen extends StatefulWidget {
  final Map<String, dynamic> nap;
  final String? day;
  final NapDetailData? data;

  const NapDetailScreen({super.key, required this.nap, this.day, this.data});

  @override
  State<NapDetailScreen> createState() => _NapDetailScreenState();
}

class _NapDetailScreenState extends State<NapDetailScreen> {
  NapDetailData? _d;
  int? _v0, _v1, _scrubT;
  int _pinchSpan = 1, _pinchFrom = 0;
  bool _changed = false;

  (int, int) _view(NapDetailData d) => (_v0 ?? d.from, _v1 ?? d.to);

  void _setView(NapDetailData d, int from, int span) {
    final full = math.max(1, d.to - d.from);
    span = span.clamp(math.min(120, full), full);
    from = from.clamp(d.from, d.to - span);
    setState(() {
      _v0 = from;
      _v1 = from + span;
    });
  }

  void _pinch(
    NapDetailData d,
    PinchPhase phase,
    double scale,
    double focal,
    double pan,
  ) {
    if (phase == PinchPhase.start) {
      final (a, b) = _view(d);
      _pinchSpan = b - a;
      _pinchFrom = a;
      setState(() => _scrubT = null);
    } else if (phase == PinchPhase.update) {
      final span = (_pinchSpan / math.max(scale, .01)).round();
      final at = _pinchFrom + (focal * _pinchSpan).round();
      _setView(d, at - ((focal + pan) * span).round(), span);
    }
  }

  void _scrub(NapDetailData d, double f) {
    final (a, b) = _view(d);
    final t = a + (f * (b - a)).round();
    if (d.hr.isEmpty) {
      setState(() => _scrubT = t);
      return;
    }
    var best = d.hr.first;
    for (final e in d.hr) {
      if ((e.t - t).abs() < (best.t - t).abs()) best = e;
    }
    setState(() => _scrubT = best.t);
  }

  @override
  void initState() {
    super.initState();
    _d = widget.data;
    if (_d == null) _load();
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    NapDetailData d;
    try {
      d = repo != null
          ? await NapDetailData.load(repo, widget.nap, day: widget.day)
          : NapDetailData.bare(widget.nap, day: widget.day);
    } catch (_) {
      d = NapDetailData.bare(widget.nap, day: widget.day);
    }
    if (mounted) setState(() => _d = d);
  }

  static const _mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDateSpan(int start, int end) {
    final s = DateTime.fromMillisecondsSinceEpoch(start * 1000);
    final w = DateTime.fromMillisecondsSinceEpoch(end * 1000);
    return '${_mo[s.month - 1]} ${s.day}, ${s.year} '
        '${formatClock(s.hour, s.minute)} to ${formatClock(w.hour, w.minute)}';
  }

  Future<void> _menu(Offset at) async {
    final size = MediaQuery.sizeOf(context);
    final p = P.of(context);
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          height: S.x12,
          child: Row(
            children: [
              Icon(icon, size: I.md, color: p.ink2),
              const SizedBox(width: S.x4),
              Text(label, style: F.caps.copyWith(color: p.ink)),
            ],
          ),
        );
    final pick = await showMenu<String>(
      context: context,
      color: p.card,
      elevation: 12,
      position: RelativeRect.fromLTRB(at.dx - 140, at.dy, size.width - at.dx, 0),
      shape: RoundedRectangleBorder(
        borderRadius: R.rXxl,
        side: BorderSide(color: C.white.withValues(alpha: .14), width: 1.0),
      ),
      items: [
        item('edit', LucideIcons.pencil, 'EDIT NAP'),
        item('delete', LucideIcons.trash2, 'DELETE NAP'),
        item('convert', LucideIcons.bedDouble, 'CONVERT TO SLEEP'),
      ],
    );
    if (!mounted || pick == null) return;
    final d = _d;
    if (d == null) return;
    switch (pick) {
      case 'edit':
        await _editNap(d);
      case 'delete':
        await _deleteNap(d);
      case 'convert':
        await _convertToSleep(d);
    }
  }

  Future<void> _editNap(NapDetailData d) async {
    final r = await openWindowEditor(
      context,
      kind: WindowKind.nap,
      title: 'Edit nap',
      start: DateTime.fromMillisecondsSinceEpoch(d.start * 1000),
      end: DateTime.fromMillisecondsSinceEpoch(d.end * 1000),
      save: 'Save nap',
    );
    if (r == null || !mounted) return;
    final s = r.$1.millisecondsSinceEpoch ~/ 1000;
    final e = r.$2.millisecondsSinceEpoch ~/ 1000;
    if (!manualNapWindowIsValid(s, e)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A nap is between 5 minutes and 6 hours.')),
      );
      return;
    }
    final app = context.read<AppState>();
    if (d.source == 'manual' && d.start != s) {
      await LocalDb.deleteNapEdit(d.day, d.start);
    }
    await LocalDb.putNapEdit(dayId: d.day, startTs: s, endTs: e, source: 'manual');
    await app.reanalyzeForNapEdit();
    _changed = true;
    if (mounted) _load();
  }

  Future<void> _deleteNap(NapDetailData d) async {
    final ok = await confirmRemove(
      context,
      title: 'Delete this nap?',
      body:
          'It disappears from your sleep record and sleep need is recalculated.',
      remove: 'Delete',
    );
    if (!ok || !mounted) return;
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    if (d.source == 'manual') {
      await LocalDb.deleteNapEdit(d.day, d.start);
    } else {
      await LocalDb.putNapEdit(
        dayId: d.day,
        startTs: d.start,
        endTs: d.end,
        source: 'rejected',
      );
    }
    await app.reanalyzeForNapEdit();
    if (!mounted) return;
    nav.pop(true);
  }

  Future<void> _convertToSleep(NapDetailData d) async {
    final ok = await confirmRemove(
      context,
      title: 'Convert to Sleep?',
      body: 'This nap will become your main sleep period for ${d.day}.',
      remove: 'Convert',
    );
    if (!ok || !mounted) return;
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    await app.setSleepOverride(
      d.day,
      DateTime.fromMillisecondsSinceEpoch(d.start * 1000),
      DateTime.fromMillisecondsSinceEpoch(d.end * 1000),
    );
    await LocalDb.deleteNapEdit(d.day, d.start);
    await app.reanalyzeForNapEdit();
    if (!mounted) return;
    nav.pop(true);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d ?? NapDetailData.bare(widget.nap, day: widget.day);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                p.bg,
                Color.alphaBlend(p.ink.withValues(alpha: .025), p.bg),
                Color.alphaBlend(p.ink.withValues(alpha: .04), p.bg),
                p.bg,
              ],
              stops: const [0.0, 0.12, 0.35, 0.55],
            ),
          ),
          child: Column(
            children: [
              _header(c, p, d),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(bottom: S.navClear(c)),
                  children: [
                    _hero(p, d),
                    const SizedBox(height: S.x2),
                    _chart(p, d),
                    const SizedBox(height: S.x8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.x4),
                      child: Text('KEY STATISTICS',
                          style: F.caps.copyWith(color: p.ink)),
                    ),
                    const SizedBox(height: S.x3),
                    _keyStats(p, d),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── the header, as a recorded activity has it: on the left ──────────────
  Widget _header(BuildContext c, P p, NapDetailData d) {
    final menuKey = GlobalKey();
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x3, S.x2),
      child: Row(
        children: [
          Pressable(
            onTap: () => Navigator.of(c).pop(_changed),
            semanticLabel: 'Back',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Center(
                child: BoldChevron(left: true, height: S.x5, color: p.ink),
              ),
            ),
          ),
          const SizedBox(width: S.x2),
          _NapIcon(size: I.lg, color: p.ink),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NAP', style: F.caps.copyWith(color: p.ink)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatDateSpan(d.start, d.end),
                    maxLines: 1,
                    style: F.over.copyWith(
                      color: p.ink3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Pressable(
            key: menuKey,
            onTap: () {
              final box =
                  menuKey.currentContext?.findRenderObject() as RenderBox?;
              _menu(box == null
                  ? Offset(MediaQuery.sizeOf(c).width, S.x16)
                  : box.localToGlobal(Offset(0, box.size.height)));
            },
            semanticLabel: 'More',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: S.x1),
                    Container(
                      width: S.x2,
                      height: S.x2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: p.ink, width: S.half),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── the figure: time asleep, or the reading under a finger ──────────────
  Widget _hero(P p, NapDetailData d) {
    final t = _scrubT;
    HrPoint? at;
    if (t != null) {
      for (final e in d.hr) {
        if (e.t == t) at = e;
      }
    }
    final move = t == null ? null : movementAt(d.movement, t);
    final figure = F.n34.copyWith(color: C.dialSleep, fontWeight: FontWeight.w700);
    final label = F.over.copyWith(color: p.ink3, fontWeight: FontWeight.w800);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      child: SizedBox(
        height: S.x16,
        child: t != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(at == null ? '--' : '${at.v.round()}', style: figure),
                      const SizedBox(width: S.x2),
                      Text('bpm',
                          style: F.cap.copyWith(color: C.dialSleep)),
                      if (move != null) ...[
                        const SizedBox(width: S.x4),
                        Text('${(move * 100).round()}%',
                            style: F.num(F.head).copyWith(
                                color: p.ink, fontWeight: FontWeight.w700)),
                        const SizedBox(width: S.x1),
                        Text('moving', style: F.cap.copyWith(color: p.ink3)),
                      ],
                    ],
                  ),
                  Text(_clockAt(t), style: F.num(F.cap).copyWith(color: p.ink3)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.asleepMin == null ? '--' : _hmm(d.asleepMin!),
                      style: figure),
                  Text('TIME ASLEEP', style: label),
                ],
              ),
      ),
    );
  }

  static String _clockAt(int t) {
    final x = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return formatClock(x.hour, x.minute);
  }

  // ── the heart rate, the movement under it: touch to read, pinch to zoom ─
  Widget _chart(P p, NapDetailData d) {
    final (v0, v1) = _view(d);
    final zoomed = v1 - v0 < d.to - d.from;
    return Stack(
      children: [
        Scrubber(
          value: null,
          onChanged: (f) => _scrub(d, f),
          onLift: () => setState(() => _scrubT = null),
          yieldToScroll: true,
          onPinch: (ph, sc, fo, pa) => _pinch(d, ph, sc, fo, pa),
          label: 'Heart rate and movement through the nap',
          describe: (f) => _clockAt(v0 + (f * (v1 - v0)).round()),
          child: SizedBox(
            height: S.x16 * 3 + S.x10,
            child: CustomPaint(
              size: Size.infinite,
              painter: _NapChartPainter(
                d: d,
                v0: v0,
                v1: v1,
                scrubT: _scrubT,
                ink: p.ink,
                ink3: p.ink3,
                grid: p.ink.withValues(alpha: .08),
                ground: Color.alphaBlend(p.ink.withValues(alpha: .04), p.bg),
              ),
            ),
          ),
        ),
        if (zoomed)
          Positioned(
            right: S.x3,
            top: S.x2,
            child: Pressable(
              onTap: () => setState(() => _v0 = _v1 = null),
              semanticLabel: 'Show the whole nap',
              child: Container(
                height: S.x8,
                padding: const EdgeInsets.symmetric(horizontal: S.x3),
                decoration: BoxDecoration(
                  color: p.ink.withValues(alpha: .12),
                  borderRadius: R.rPill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.zoomOut, size: I.sm, color: p.ink),
                    const SizedBox(width: S.x1),
                    Text('RESET', style: F.over.copyWith(color: p.ink)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── the key statistics: measured, or a dash ────────────────────────────
  Widget _keyStats(P p, NapDetailData d) {
    final moving = d.movement.where((m) =>
        m.t + m.span > d.start && m.t < d.end);
    final restless = moving.isEmpty
        ? null
        : (moving.fold<double>(0, (a, m) => a + m.v) / moving.length * 100)
            .round();
    final cells = [
      (LucideIcons.bedDouble, 'IN BED', _hmm(d.inBedMin), ''),
      (LucideIcons.moon, 'ASLEEP', d.asleepMin == null ? '--' : _hmm(d.asleepMin!), ''),
      (LucideIcons.heart, 'AVG HR', d.avgHr == null ? '--' : '${d.avgHr}', 'bpm'),
      (LucideIcons.heartPulse, 'LOWEST HR', d.lowHr == null ? '--' : '${d.lowHr}', 'bpm'),
      if (restless != null) (LucideIcons.activity, 'MOVING', '$restless', '%'),
    ];
    Widget cell((IconData, String, String, String) s) => Container(
          padding: const EdgeInsets.fromLTRB(S.x3, S.x3, S.x3, S.x3),
          decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(s.$1, size: I.sm, color: p.ink3),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(s.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.over.copyWith(
                          color: p.ink3, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: S.x2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(s.$3,
                      style: F.num(F.head)
                          .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
                  if (s.$4.isNotEmpty) ...[
                    const SizedBox(width: S.x1),
                    Text(s.$4, style: F.cap.copyWith(color: p.ink3)),
                  ],
                ],
              ),
            ],
          ),
        );
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: S.x2));
      rows.add(Row(children: [
        Expanded(child: cell(cells[i])),
        const SizedBox(width: S.x2),
        Expanded(
          child: i + 1 < cells.length
              ? cell(cells[i + 1])
              : const SizedBox.shrink(),
        ),
      ]));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(children: rows),
    );
  }
}

/// The nap's mark: a lounger.
class _NapIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const _NapIcon({this.size = I.md, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? P.of(context).ink;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _NapIconPainter(c)),
    );
  }
}

class _NapIconPainter extends CustomPainter {
  final Color color;
  _NapIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = math.max(1.8, w * 0.09)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.08, h * 0.28)
        ..lineTo(w * 0.32, h * 0.58)
        ..lineTo(w * 0.68, h * 0.58)
        ..lineTo(w * 0.92, h * 0.76),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.38, h * 0.58)
        ..lineTo(w * 0.30, h * 0.88)
        ..moveTo(w * 0.62, h * 0.58)
        ..lineTo(w * 0.70, h * 0.88),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_NapIconPainter o) => o.color != color;
}

/// The heart rate in the sleep blue, filled to the floor as a recorded
/// activity's is, the nap's two edges dashed, and the movement lane under it.
class _NapChartPainter extends CustomPainter {
  final NapDetailData d;
  final int v0, v1;
  final int? scrubT;
  final Color ink, ink3, grid, ground;

  _NapChartPainter({
    required this.d,
    required this.v0,
    required this.v1,
    required this.scrubT,
    required this.ink,
    required this.ink3,
    required this.grid,
    required this.ground,
  });

  static const _foot = S.x8;
  static const _laneH = S.x8;

  @override
  void paint(Canvas canvas, Size size) {
    final hasLane = d.movement.isNotEmpty;
    final laneTop = size.height - _foot - (hasLane ? _laneH : 0);
    // The lane's label gets a row of its own between the trace and the lane,
    // rather than sitting on the first columns.
    final plot = Rect.fromLTRB(
        0, S.x2, size.width, laneTop - (hasLane ? S.x5 : 0));
    canvas.drawRect(
      plot,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, plot.top),
          Offset(0, plot.bottom),
          [
            Color.alphaBlend(ink.withValues(alpha: .025), ground),
            ground,
            ground,
            C.char.withValues(alpha: .5),
          ],
          [0.0, 0.20, 0.70, 1.0],
        ),
    );
    final span = math.max(1, v1 - v0);
    double xOf(num t) => (t - v0) / span * size.width;

    final all = d.hr;
    var a = 0, b = all.length;
    while (a + 1 < b && all[a + 1].t < v0) {
      a++;
    }
    while (b - 2 > a && all[b - 2].t > v1) {
      b--;
    }
    final pts = all.sublist(a, b);

    // The nap's own scale, padded to tens, so a zoom changes the width only.
    var lo = 40.0, hi = 90.0;
    if (all.isNotEmpty) {
      final vs = all.map((e) => e.v);
      lo = ((vs.reduce(math.min) - 4) / 10).floor() * 10.0;
      hi = ((vs.reduce(math.max) + 4) / 10).ceil() * 10.0;
      if (hi - lo < 30) hi = lo + 30;
    }
    double yOf(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
    final step = (hi - lo) >= 60 ? 20.0 : 10.0;

    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = lo + step; v < hi; v += step) {
      canvas.drawLine(Offset(0, yOf(v)), Offset(size.width, yOf(v)), gp);
    }

    // The nap itself, a faint band behind the trace.
    final n0 = xOf(d.start), n1 = xOf(d.end);
    if (n1 > 0 && n0 < size.width) {
      canvas.drawRect(Rect.fromLTRB(n0, plot.top, n1, plot.bottom),
          Paint()..color = C.dialSleep.withValues(alpha: .06));
    }

    canvas.save();
    canvas.clipRect(plot.inflate(2));
    if (pts.length >= 2) {
      final line = Path()..moveTo(xOf(pts.first.t), yOf(pts.first.v));
      for (final e in pts.skip(1)) {
        line.lineTo(xOf(e.t), yOf(e.v));
      }
      canvas.drawPath(
        Path.from(line)
          ..lineTo(xOf(pts.last.t), plot.bottom)
          ..lineTo(xOf(pts.first.t), plot.bottom)
          ..close(),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, plot.top),
            Offset(0, plot.bottom),
            [
              C.dialSleep.withValues(alpha: .42),
              C.dialSleep.withValues(alpha: .02),
            ],
          ),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = C.dialSleep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();

    for (var v = lo + step; v < hi; v += step) {
      _text(canvas, '${v.round()}', Offset(S.x1, yOf(v) - S.x2), ink3);
    }

    // The movement lane, on the same clock as the trace above it.
    if (hasLane) {
      final lane = Rect.fromLTRB(0, laneTop, size.width, laneTop + _laneH);
      canvas.drawLine(Offset(0, lane.bottom), Offset(size.width, lane.bottom), gp);
      paintMovement(canvas, lane, d.movement, xOf, ink.withValues(alpha: .45));
      // Centred: the nap's two edges are dashed down the sides.
      final tp = _layout('MOVEMENT',
          F.num(F.over).copyWith(color: ink3, fontWeight: FontWeight.w600));
      tp.paint(canvas,
          Offset((size.width - tp.width) / 2, plot.bottom + S.half));
    }

    // The nap's two edges: dashed down the chart, a dot and the time at the
    // foot.
    final floor = laneTop + (hasLane ? _laneH : 0);
    for (final (t, left) in [(d.start, true), (d.end, false)]) {
      if (t < v0 || t > v1) continue;
      final x = xOf(t);
      final dash = Paint()
        ..color = ink.withValues(alpha: .8)
        ..strokeWidth = 1.5;
      for (var y = plot.top; y < floor; y += S.x2) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + S.x1, floor)), dash);
      }
      canvas.drawCircle(Offset(x, floor), S.x1, Paint()..color = ink);
      final at = DateTime.fromMillisecondsSinceEpoch(t * 1000);
      final tp = _layout(formatClock(at.hour, at.minute),
          F.num(F.cap).copyWith(color: ink, fontWeight: FontWeight.w700));
      final tx = left ? x : x - tp.width;
      tp.paint(canvas, Offset(tx.clamp(0, size.width - tp.width), floor + S.x2));
    }

    // The finger.
    final st = scrubT;
    if (st != null && st >= v0 && st <= v1) {
      HrPoint? hit;
      for (final e in all) {
        if (e.t == st) hit = e;
      }
      final x = xOf(st);
      final dot = Paint()
        ..color = ink
        ..strokeWidth = 1.5;
      for (var y = S.x1; y < floor; y += S.x2) {
        canvas.drawLine(Offset(x, y), Offset(x, y + S.x1), dot);
      }
      if (hit != null) {
        canvas.drawCircle(Offset(x, yOf(hit.v)), S.x2 + S.half, Paint()..color = ink);
        canvas.drawCircle(Offset(x, yOf(hit.v)), S.x2, Paint()..color = C.dialSleep);
      }
    }
  }

  TextPainter _layout(String s, TextStyle st) => TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
      )..layout();

  void _text(Canvas canvas, String s, Offset at, Color color) => _layout(
          s, F.num(F.over).copyWith(color: color, fontWeight: FontWeight.w600))
      .paint(canvas, at);

  @override
  bool shouldRepaint(_NapChartPainter o) =>
      o.d != d || o.v0 != v0 || o.v1 != v1 || o.scrubT != scrubT || o.ink != ink;
}
