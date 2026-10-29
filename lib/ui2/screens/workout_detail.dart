// A WORKOUT, opened from My Day: its strain against the same sport's last
// thirty days, its heart rate over the session (and a little either side),
// the five zones it spent time in — each one a door that lights its own
// stretches on the chart — the route when one was recorded, and four key
// figures against that sport's own month. Every comparison is with the SAME
// activity: a run against runs, a ride against rides.
//
// Nothing here is invented to fill a slot. A figure the session did not
// record is a dash, a comparison with no other session of the sport is left
// off, and the map section is not drawn at all without a route.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../../gps/route_models.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart';
import '../../state/units_controller.dart';
import '../activity/catalogue.dart';
import '../activity/share.dart' show ShareSheet;
import '../activity/tiles.dart';
import '../components/metric_comparison_card.dart';
import '../ui2.dart';
import 'home_screen.dart' show repoOf, unitsOf;
import 'add_activity.dart' show openEditActivity;
import 'log_workout.dart' show bumpInsights;
import 'window_editor.dart' show HrPoint;
import 'workout_screen.dart' show sessionResultOf;

/// The five zone hues, Z1…Z5.
const _zoneColors = [
  C.refZone1,
  C.refZone2,
  C.refZone3,
  C.refZone4,
  C.refZone5,
];

/// The same sport's last thirty days, this session left out.
class SportAverage {
  final double? strain, calories, avgHr, maxHr, durationSec;

  /// Per zone, the middle half of the sport's sessions' share of their time
  /// there (0…1), or null with too few sessions to say.
  final List<(double, double)?> typical;

  const SportAverage({
    this.strain,
    this.calories,
    this.avgHr,
    this.maxHr,
    this.durationSec,
    this.typical = const [null, null, null, null, null],
  });
}

class WorkoutDetail {
  final String id, type;
  final Activity activity;
  final int start, end;
  final double? strain;
  final int? calories, avgHr, maxHr;

  /// The heart rate over [from]…[to], a little wider than the session.
  final List<HrPoint> hr;
  final int from, to;

  /// The five zones' lower edges in bpm, or null when no set was banked.
  final List<int>? zoneLo;

  /// Seconds in each zone, and when (epoch-second runs) the session was there.
  final List<int> zoneSec;
  final List<List<(int, int)>> zoneRuns;

  final SportAverage avg;
  final WorkoutRoute? route;

  /// Sessions of this sport ever stored, this one included.
  final int count;

  const WorkoutDetail({
    required this.id,
    required this.type,
    required this.activity,
    required this.start,
    required this.end,
    this.strain,
    this.calories,
    this.avgHr,
    this.maxHr,
    this.hr = const [],
    required this.from,
    required this.to,
    this.zoneLo,
    this.zoneSec = const [0, 0, 0, 0, 0],
    this.zoneRuns = const [[], [], [], [], []],
    this.avg = const SportAverage(),
    this.route,
    this.count = 0,
  });

  int get durationSec => end - start;

  /// Which zone [bpm] is in, 0…4, or -1 under zone 1.
  int zoneOf(double bpm) {
    final lo = zoneLo;
    if (lo == null) return -1;
    for (var i = 4; i >= 0; i--) {
      if (bpm >= lo[i]) return i;
    }
    return -1;
  }

  static Future<WorkoutDetail> load(
    LocalRepository repo,
    Map<String, dynamic> s,
  ) async {
    final id = (s['id'] as String?) ?? '';
    final type = (s['type'] as String?) ?? 'other';
    final a =
        activityByName(type) ??
        Activity(type, LucideIcons.activity, C.purple, Track.duration, 5.0);
    final start = (s['start_ts'] as num?)?.toInt() ?? 0;
    final end =
        (s['end_ts'] as num?)?.toInt() ??
        start + ((s['duration_min'] as num?)?.toInt() ?? 0) * 60;
    var w = <String, dynamic>{};
    try {
      if (id.isNotEmpty) w = await repo.getWorkout(id);
    } catch (_) {}
    num? n(String k) => (w[k] ?? s[k]) as num?;

    // The view: the session and a twelfth of it (a minute at least) either
    // side, so the climb into it and the fall out of it both show.
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pad = math.max(60, (end - start) ~/ 12);
    final from = start - pad, to = math.min(end + pad, nowSec);

    // Zone edges: the set the session was binned with.
    List<int>? lo;
    final bands = w['zone_bands'];
    if (bands is List && bands.length == 5) {
      final l = [
        for (final b in bands)
          if (b is Map && b['lo'] is num) (b['lo'] as num).round(),
      ];
      if (l.length == 5) lo = l;
    }
    int zoneOf(num bpm) {
      if (lo == null) return -1;
      for (var i = 4; i >= 0; i--) {
        if (bpm >= lo[i]) return i;
      }
      return -1;
    }

    // The heart rate: the band's seconds while they are kept, in buckets fine
    // enough to show the shape; the banked minute curve after that.
    var sec = <(int, int)>[];
    try {
      final rows = await LocalDb.hrSamplesInRange(from, to);
      sec = [
        for (final r in rows)
          if (r['rec_ts'] is num && r['hr'] is num)
            ((r['rec_ts'] as num).toInt(), (r['hr'] as num).toInt()),
      ];
    } catch (_) {}
    final hr = <HrPoint>[];
    final zoneSec = [0, 0, 0, 0, 0];
    final runs = <List<(int, int)>>[[], [], [], [], []];
    void addRun(int z, int a, int b) {
      if (z < 0) return;
      final r = runs[z];
      if (r.isNotEmpty && a - r.last.$2 <= 5) {
        r[r.length - 1] = (r.last.$1, b);
      } else {
        r.add((a, b));
      }
    }

    if (sec.isNotEmpty) {
      final bucket = math.max(5, (to - from) ~/ 160);
      var b0 = sec.first.$1 ~/ bucket, sum = 0, cnt = 0;
      for (final (t, v) in sec) {
        final b = t ~/ bucket;
        if (b != b0 && cnt > 0) {
          hr.add((t: b0 * bucket + bucket ~/ 2, v: sum / cnt));
          sum = 0;
          cnt = 0;
        }
        b0 = b;
        sum += v;
        cnt++;
      }
      if (cnt > 0) hr.add((t: b0 * bucket + bucket ~/ 2, v: sum / cnt));
      // Seconds in each zone, inside the session only; a gap of more than
      // five seconds counts as five, not as time spent.
      for (var i = 0; i < sec.length; i++) {
        final (t, v) = sec[i];
        if (t < start || t > end) continue;
        final next = i + 1 < sec.length ? sec[i + 1].$1 : t + 1;
        final dt = (next - t).clamp(0, 5);
        final z = zoneOf(v);
        if (z >= 0) zoneSec[z] += dt;
        addRun(z, t, t + dt);
      }
    } else {
      final curve = w['hr'];
      if (curve is List) {
        for (final e in curve) {
          if (e is Map && e['t'] is num && e['v'] is num) {
            final t = (e['t'] as num).toInt();
            if (t >= from && t <= to) {
              hr.add((t: t, v: (e['v'] as num).toDouble()));
            }
            if (t >= start && t < end) addRun(zoneOf(e['v'] as num), t, t + 60);
          }
        }
      }
      final zm = w['zone_min'] ?? s['zone_min'];
      if (zm is List && zm.length == 5) {
        for (var i = 0; i < 5; i++) {
          zoneSec[i] = (((zm[i] as num?) ?? 0) * 60).round();
        }
      }
    }

    // The same sport over the last thirty days, this session left out.
    var avg = const SportAverage();
    try {
      final rows = (await repo.getWorkouts(range: 'month'))['workouts'];
      final same = [
        for (final r in (rows is List ? rows : const []))
          if (r is Map &&
              r['id'] != id &&
              (r['type'] as String?)?.toLowerCase() == type.toLowerCase())
            r.cast<String, dynamic>(),
      ];
      double? mean(Iterable<num?> xs) {
        final v = [
          for (final x in xs)
            if (x != null) x.toDouble(),
        ];
        return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
      }

      final typical = <(double, double)?>[];
      for (var z = 0; z < 5; z++) {
        final fr = <double>[
          for (final r in same)
            if (r['zone_min'] is List &&
                (r['zone_min'] as List).length == 5 &&
                ((r['duration_min'] as num?) ?? 0) > 0)
              (((r['zone_min'] as List)[z] as num?) ?? 0) /
                  (r['duration_min'] as num),
        ]..sort();
        if (fr.length < 3) {
          typical.add(null);
          continue;
        }
        double q(double p) => fr[((fr.length - 1) * p).round()];
        var a = q(.25), b = q(.75);
        // A range too narrow to see is drawn as a sliver around the middle.
        if (b - a < .04) {
          final m = q(.5);
          a = math.max(0, m - .02);
          b = math.min(1, m + .02);
        }
        typical.add((a.clamp(0.0, 1.0), b.clamp(0.0, 1.0)));
      }
      avg = SportAverage(
        strain: mean(same.map((r) => r['strain'] as num?)),
        calories: mean(same.map((r) => r['calories'] as num?)),
        avgHr: mean(same.map((r) => r['avg_hr'] as num?)),
        maxHr: mean(same.map((r) => r['max_hr'] as num?)),
        durationSec: mean(
          same.map((r) {
            final m = r['duration_min'] as num?;
            return m == null ? null : m * 60;
          }),
        ),
        typical: typical,
      );
    } catch (_) {}

    WorkoutRoute? route;
    try {
      if (id.isNotEmpty) {
        final r = await repo.getWorkoutRoute(id);
        if (r != null && r.hasPath) route = r;
      }
    } catch (_) {}

    var count = 0;
    try {
      count = await LocalDb.sessionCountOfType(type);
    } catch (_) {}

    return WorkoutDetail(
      id: id,
      type: type,
      activity: a,
      start: start,
      end: end,
      strain: n('strain')?.toDouble(),
      calories: n('calories')?.round(),
      avgHr: n('avg_hr')?.round(),
      maxHr: n('max_hr')?.round(),
      hr: hr,
      from: from,
      to: math.max(to, end),
      zoneLo: lo,
      zoneSec: zoneSec,
      zoneRuns: runs,
      avg: avg,
      route: route,
      count: count,
    );
  }
}

/// Opens a session from My Day. Resolves true when it was deleted or edited.
class WorkoutDetailScreen extends StatefulWidget {
  final Map<String, dynamic> session;

  /// Handed in by a test; read from the repository when null.
  final WorkoutDetail? data;

  const WorkoutDetailScreen({super.key, required this.session, this.data});

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  WorkoutDetail? _d;

  /// The zone lit on the chart, 0…4, or null.
  int? _zone;

  /// The chart's view in epoch seconds (the whole of it when null), the time
  /// under the finger, and where a pinch began.
  int? _v0, _v1, _scrubT;
  int _pinchSpan = 1, _pinchFrom = 0;

  (int, int) _view(WorkoutDetail d) => (_v0 ?? d.from, _v1 ?? d.to);

  void _setView(WorkoutDetail d, int from, int span) {
    final full = math.max(1, d.to - d.from);
    span = span.clamp(math.min(120, full), full);
    from = from.clamp(d.from, d.to - span);
    setState(() {
      _v0 = from;
      _v1 = from + span;
    });
  }

  /// Two fingers zoom the chart about where they began, and moving them
  /// together moves the view along: down to a couple of minutes, minute by
  /// minute.
  void _pinch(
    WorkoutDetail d,
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

  /// A finger on the chart: the reading at the nearest sample to it.
  void _scrub(WorkoutDetail d, double f) {
    if (d.hr.isEmpty) return;
    final (a, b) = _view(d);
    final t = a + (f * (b - a)).round();
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
    if (repo == null) return;
    try {
      final d = await WorkoutDetail.load(repo, widget.session);
      if (mounted) setState(() => _d = d);
    } catch (_) {}
  }

  Future<void> _menu(BuildContext c, Offset at) async {
    final size = MediaQuery.sizeOf(c);
    final p = P.of(c);
    final pick = await showMenu<String>(
      context: c,
      color: p.card,
      elevation: 12,
      position: RelativeRect.fromLTRB(at.dx - 120, at.dy, size.width - at.dx, 0),
      shape: RoundedRectangleBorder(
        borderRadius: R.rXxl,
        side: BorderSide(color: C.white.withValues(alpha: .14), width: 1.0),
      ),
      items: [
        PopupMenuItem(
          value: 'share',
          height: S.x12,
          child: Row(
            children: [
              Icon(LucideIcons.share2, size: I.md, color: p.ink2),
              const SizedBox(width: S.x4),
              Text(
                'SHARE',
                style: F.caps.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          height: S.x12,
          child: Row(
            children: [
              Icon(LucideIcons.pencil, size: I.md, color: p.ink2),
              const SizedBox(width: S.x4),
              Text(
                'EDIT',
                style: F.caps.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          height: S.x12,
          child: Row(
            children: [
              Icon(LucideIcons.trash2, size: I.md, color: p.ink2),
              const SizedBox(width: S.x4),
              Text(
                'DELETE',
                style: F.caps.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted || pick == null) return;
    final d = _d;
    switch (pick) {
      case 'share':
        final app = _app();
        if (app == null) return;
        final nav = Navigator.of(context);
        final r = await sessionResultOf(app, widget.session);
        await nav.push(MaterialPageRoute<void>(builder: (_) => ShareSheet(r)));
      case 'edit':
        if (d == null) return;
        await openEditActivity(context, (
          id: d.id,
          activity: d.activity,
          start: DateTime.fromMillisecondsSinceEpoch(d.start * 1000),
          end: DateTime.fromMillisecondsSinceEpoch(d.end * 1000),
        ));
        if (mounted) {
          bumpInsights(context);
          _load();
        }
      case 'delete':
        if (d == null) return;
        final name = d.activity.displayName(context).toLowerCase();
        final ok = await confirmRemove(
          context,
          title: 'Delete this $name?',
          body: 'It disappears from Locus, with its strain and its route.',
          remove: 'Delete',
        );
        if (!ok || !mounted) return;
        final app = _app();
        final nav = Navigator.of(context);
        await app?.deleteWorkout(d.id);
        if (!mounted) return;
        bumpInsights(context);
        nav.pop(true);
    }
  }

  AppState? _app() {
    try {
      return context.read<AppState>();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d;
    final s = widget.session;
    final a =
        d?.activity ??
        activityByName(s['type'] as String?) ??
        Activity('Activity', LucideIcons.activity, C.purple, Track.duration, 5);
    final start = d?.start ?? (s['start_ts'] as num?)?.toInt() ?? 0;
    final end = d?.end ?? (s['end_ts'] as num?)?.toInt() ?? start;
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
              _header(c, p, a, start, end),
              Expanded(
                child: d == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: EdgeInsets.only(bottom: S.navClear(c)),
                        children: [
                          _strain(c, p, d),
                          const SizedBox(height: S.x2),
                          _chart(c, p, d),
                          const SizedBox(height: S.x6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: S.x4),
                            child: Column(
                              children: [
                                _legend(p, d),
                                const SizedBox(height: S.x4),
                                for (var z = 4; z >= 0; z--) ...[
                                  _zoneCard(c, p, d, z),
                                  const SizedBox(height: S.x2 + S.half),
                                ],
                                if (d.route != null) ...[
                                  const SizedBox(height: S.x6),
                                  _RouteCard(d: d, onShare: () => _share()),
                                ],
                                if (d.type.toLowerCase().contains('run') ||
                                    a.name.toLowerCase() == 'running') ...[
                                  const SizedBox(height: S.x6),
                                  RunningWorkoutComparisonCard(
                                    detail: d,
                                    units:
                                        unitsOf(c) ??
                                        UnitsController.seed(UnitSystem.metric),
                                  ),
                                ],
                                const SizedBox(height: S.x8),
                                _keyStatsHead(p),
                                const SizedBox(height: S.x4),
                              ],
                            ),
                          ),
                          _keyStats(c, p, d),
                          if (d.count > 0) ...[
                            const SizedBox(height: S.x5),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: S.x4,
                              ),
                              child: _milestone(p, d),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share() async {
    final app = _app();
    if (app == null) return;
    final nav = Navigator.of(context);
    final r = await sessionResultOf(app, widget.session);
    await nav.push(MaterialPageRoute<void>(builder: (_) => ShareSheet(r)));
  }

  // ── the header ──────────────────────────────────────────────────────────
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

  Widget _header(BuildContext c, P p, Activity a, int start, int end) {
    final s = DateTime.fromMillisecondsSinceEpoch(start * 1000);
    final e = DateTime.fromMillisecondsSinceEpoch(end * 1000);
    final when =
        '${_mo[s.month - 1]} ${s.day}, ${s.year} '
        '${formatClock(s.hour, s.minute)} to ${formatClock(e.hour, e.minute)}';
    final menuKey = GlobalKey();
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x3, S.x2),
      child: Row(
        children: [
          Pressable(
            onTap: () => Navigator.of(c).maybePop(),
            semanticLabel: 'Back',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Center(
                child: BoldChevron(left: true, height: S.x5 * 0.9, color: p.ink),
              ),
            ),
          ),
          const SizedBox(width: S.x2),
          Icon(a.icon, size: I.lg + S.x1, color: p.ink),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.displayName(c).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.cap.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    when,
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
              final at = box == null
                  ? Offset(MediaQuery.sizeOf(c).width, S.x16)
                  : box.localToGlobal(Offset(0, box.size.height));
              _menu(c, at);
            },
            semanticLabel: 'More',
            child: SizedBox(
              width: S.tap + S.x2,
              height: S.tap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: S.x1 * 0.9),
                    Container(
                      width: (S.x2 + S.half) * 0.9,
                      height: (S.x2 + S.half) * 0.9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: p.ink, width: S.half * 0.9),
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

  // ── the strain, against the sport's month ──────────────────────────────
  // While a finger is on the chart this row is the reading under it instead:
  // the beats a minute and the time, in the strain's place and size.
  Widget _strain(BuildContext c, P p, WorkoutDetail d) {
    final v = d.strain;
    final avg = d.avg.strain;
    final t = _scrubT;
    HrPoint? at;
    if (t != null) {
      for (final e in d.hr) {
        if (e.t == t) at = e;
      }
    }
    final label = F.over.copyWith(
      color: p.ink3,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      child: SizedBox(
        height: S.x16,
        child: at != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${at.v.round()}',
                        style: F.n34.copyWith(
                          color: C.dialStrain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: S.x2),
                      Text(
                        'bpm',
                        style: F.body.copyWith(
                          color: C.dialStrain,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _clockAt(at.t),
                    style: F.num(F.cap).copyWith(color: p.ink3),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        v == null ? '--' : v.toStringAsFixed(1),
                        style: F.n34.copyWith(
                          color: C.dialStrain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (v != null && avg != null) ...[
                        const SizedBox(width: S.x3),
                        _VsPill(up: v >= avg, text: avg.toStringAsFixed(1)),
                      ],
                    ],
                  ),
                  Text('ACTIVITY STRAIN', style: label),
                ],
              ),
      ),
    );
  }

  static String _clockAt(int t) {
    final x = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return formatClock(x.hour, x.minute);
  }

  // ── the heart rate: touch to read, pinch to zoom ───────────────────────
  Widget _chart(BuildContext c, P p, WorkoutDetail d) {
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
          label: 'Heart rate through the activity',
          describe: (f) => _clockAt(v0 + (f * (v1 - v0)).round()),
          child: _WorkoutChart(
            d: d,
            zone: _zone,
            v0: v0,
            v1: v1,
            scrubT: _scrubT,
          ),
        ),
        if (zoomed)
          Positioned(
            right: S.x3,
            top: S.x2,
            child: Pressable(
              onTap: () => setState(() {
                _v0 = _v1 = null;
              }),
              semanticLabel: 'Show the whole activity',
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
                    Text(
                      'RESET',
                      style: F.over.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── the legend over the zones ───────────────────────────────────────────
  Widget _legend(P p, WorkoutDetail d) => Row(
    children: [
      SizedBox(
        width: S.x5,
        height: S.x6,
        child: CustomPaint(
          painter: _TypicalBox(p.ink2, p.ink.withValues(alpha: .12)),
        ),
      ),
      const SizedBox(width: S.x4),
      Text(
        'TYPICAL RANGE',
        style: F.caps.copyWith(
          color: p.ink2,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
      const Spacer(),
      Text(
        'DURATION ',
        style: F.caps.copyWith(
          color: p.ink2,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
      Text(
        _hms(d.durationSec),
        style: F.num(F.t2).copyWith(color: p.ink, fontWeight: FontWeight.w700),
      ),
    ],
  );

  // ── one zone ────────────────────────────────────────────────────────────
  Widget _zoneCard(BuildContext c, P p, WorkoutDetail d, int z) {
    final secs = d.zoneSec[z];
    final active = secs > 0;
    final lo = d.zoneLo;
    final range = lo == null
        ? ''
        : z == 4
        ? '${lo[4]}+ BPM'
        : '${lo[z]}-${lo[z + 1] - 1} BPM';
    final pct = d.durationSec <= 0 ? 0 : (secs / d.durationSec * 100).round();
    final picking = _zone != null;
    final on = _zone == z;
    final dim = active ? 1.0 : .28;
    final ink = p.ink.withValues(alpha: dim);
    final pctColor = !active
        ? ink
        : picking && !on
        ? p.ink2
        : _zoneColors[z];
    final (hm, ss) = _hmParts(secs);
    final card = Container(
      padding: EdgeInsets.fromLTRB(
        (S.x4 + S.half) * 0.9,
        S.x5 * 0.9,
        (S.x4 + S.half) * 0.9,
        S.x5 * 0.9,
      ),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: R.rLg,
        border: Border.all(
          color: on ? p.ink.withValues(alpha: .7) : p.card,
          width: S.half / 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'ZONE ${z + 1}',
                style: F.caps.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: S.x3 * 0.9),
              Flexible(
                child: Text(
                  range,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.caps.copyWith(
                    color: active ? p.ink2 : ink,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: S.x3 * 0.9),
              Text(
                '$pct%',
                style: F.caps.copyWith(
                  color: pctColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                ),
              ),
              const Spacer(),
              Text(
                hm,
                style: F.num(F.head).copyWith(
                  color: ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                ':$ss',
                style: F.num(F.cap).copyWith(
                  color: active ? p.ink3 : ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: S.x3 * 0.9),
            SizedBox(
              height: (S.x6 * 0.9).roundToDouble(),
              child: CustomPaint(
                painter: _ZoneBar(
                  frac: d.durationSec <= 0 ? 0 : secs / d.durationSec,
                  color: _zoneColors[z],
                  typical: picking ? null : d.avg.typical[z],
                  runs: picking
                      ? [
                          for (final (a, b) in d.zoneRuns[z])
                            (
                              (a - d.start) / math.max(1, d.durationSec),
                              (b - d.start) / math.max(1, d.durationSec),
                            ),
                        ]
                      : null,
                  runColor: on ? _zoneColors[z] : p.ink.withValues(alpha: .78),
                  hatch: p.ink.withValues(alpha: .14),
                  box: p.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (!active) return card;
    return Pressable(
      onTap: () => setState(() => _zone = on ? null : z),
      semanticLabel: 'Zone ${z + 1}, $pct percent. Show it on the chart',
      child: card,
    );
  }

  // ── key statistics ──────────────────────────────────────────────────────
  Widget _keyStatsHead(P p) => Row(
    children: [
      Text(
        'KEY STATISTICS',
        style: F.body.copyWith(
          color: p.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
        ),
      ),
      const Spacer(),
      Text(
        'VS. 30 DAY AVERAGE',
        style: F.caps.copyWith(
          color: p.ink3,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    ],
  );

  Widget _keyStats(BuildContext c, P p, WorkoutDetail d) {
    final dur = d.durationSec;
    final (dm, ds) = _hmParts(dur);
    final cards = [
      _Stat(
        LucideIcons.flame,
        'CALORIES',
        d.calories == null ? '--' : '${d.calories}',
        'cals',
        null,
        d.calories == null || d.avg.calories == null
            ? null
            : (
                d.calories! >= d.avg.calories!,
                '${d.avg.calories!.round()}cals',
              ),
      ),
      _Stat(
        LucideIcons.heart,
        'AVG HR',
        d.avgHr == null ? '--' : '${d.avgHr}',
        'bpm',
        null,
        d.avgHr == null || d.avg.avgHr == null
            ? null
            : (d.avgHr! >= d.avg.avgHr!, '${d.avg.avgHr!.round()}bpm'),
      ),
      _Stat(
        LucideIcons.heartPulse,
        'MAX HR',
        d.maxHr == null ? '--' : '${d.maxHr}',
        'bpm',
        null,
        d.maxHr == null || d.avg.maxHr == null
            ? null
            : (d.maxHr! >= d.avg.maxHr!, '${d.maxHr!.round()}bpm'),
      ),
      _Stat(
        LucideIcons.timer,
        'DURATION',
        dm,
        '',
        ':$ds',
        d.avg.durationSec == null
            ? null
            : (dur >= d.avg.durationSec!, _hms(d.avg.durationSec!.round())),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _statCard(p, cards[0])),
              const SizedBox(width: S.x3),
              Expanded(child: _statCard(p, cards[1])),
            ],
          ),
          const SizedBox(height: S.x3),
          Row(
            children: [
              Expanded(child: _statCard(p, cards[2])),
              const SizedBox(width: S.x3),
              Expanded(child: _statCard(p, cards[3])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(P p, _Stat s) => Container(
    padding: const EdgeInsets.fromLTRB(S.x4, S.x3 + S.half, S.x3, S.x3 + S.half),
    decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(s.icon, size: I.md * 0.9, color: p.ink),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text(
                s.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.over.copyWith(
                  color: p.ink3,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              s.value,
              style: F.n24.copyWith(
                color: p.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (s.small != null)
              Text(
                s.small!,
                style: F.num(
                  F.head,
                ).copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (s.unit.isNotEmpty) ...[
              const SizedBox(width: S.x1),
              Text(
                s.unit,
                style: F.cap.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: S.x2),
        if (s.vs != null) _VsPill(up: s.vs!.$1, text: s.vs!.$2),
      ],
    ),
  );

  // ── the sport's count ───────────────────────────────────────────────────
  Widget _milestone(P p, WorkoutDetail d) {
    const steps = [5, 10, 25, 50, 100, 150, 200, 250, 300, 400, 500, 750, 1000];
    final next = steps.firstWhere(
      (s) => s > d.count,
      orElse: () => (d.count ~/ 500 + 1) * 500,
    );
    final prev = steps.lastWhere((s) => s <= d.count, orElse: () => 0);
    final frac = ((d.count - prev) / math.max(1, next - prev)).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x6),
      decoration: BoxDecoration(
        borderRadius: R.rXl,
        border: Border.all(color: p.ink.withValues(alpha: .16), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: S.x16 + S.x2,
            height: S.x16 + S.x2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: C.char,
              border: Border.all(
                color: C.lavender.withValues(alpha: .8),
                width: S.half,
              ),
            ),
            child: Icon(d.activity.icon, size: I.lg, color: C.lavender),
          ),
          const SizedBox(width: S.x5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${d.count}',
                        style: F.num(F.n24).copyWith(
                          color: C.dialStrain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: '/$next',
                        style: F.num(
                          F.n24,
                        ).copyWith(color: p.ink, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: S.x1),
                Text(
                  '${next - d.count} more until your next milestone',
                  style: F.body.copyWith(color: p.ink),
                ),
                const SizedBox(height: S.x3),
                ClipRRect(
                  borderRadius: R.rPill,
                  child: SizedBox(
                    height: S.x2,
                    child: Stack(
                      children: [
                        Container(color: p.ink.withValues(alpha: .12)),
                        FractionallySizedBox(
                          widthFactor: frac,
                          child: Container(color: C.dialSleep),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: I.md, color: p.ink3),
        ],
      ),
    );
  }
}

class _Stat {
  final IconData icon;
  final String label, value, unit;
  final String? small;

  /// Above the average, and the average as written.
  final (bool, String)? vs;
  const _Stat(
    this.icon,
    this.label,
    this.value,
    this.unit,
    this.small,
    this.vs,
  );
}

/// "▼ 6.9": the sport's average, and which side of it this session landed.
class _VsPill extends StatelessWidget {
  final bool up;
  final String text;
  const _VsPill({required this.up, required this.text});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: S.x2 + S.half,
        vertical: S.x1,
      ),
      decoration: BoxDecoration(
        color: p.ink.withValues(alpha: .1),
        borderRadius: R.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DeltaTriangle(up: up, color: p.ink2, size: S.x3),
          const SizedBox(width: S.x2),
          Text(
            text,
            style: F.num(
              F.body,
            ).copyWith(color: p.ink2, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

String _hms(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// "0:02" and "13": hours and minutes, and the seconds apart.
(String, String) _hmParts(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  return ('$h:${m.toString().padLeft(2, '0')}', s.toString().padLeft(2, '0'));
}

// ── the heart rate chart ───────────────────────────────────────────────────

class _WorkoutChart extends StatelessWidget {
  final WorkoutDetail d;
  final int? zone;

  /// The seconds in view, and the sample under a finger.
  final int v0, v1;
  final int? scrubT;
  const _WorkoutChart({
    required this.d,
    required this.zone,
    required this.v0,
    required this.v1,
    required this.scrubT,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SizedBox(
      height: S.x16 * 3 + S.x4,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ChartPaint(
          d: d,
          zone: zone,
          v0: v0,
          v1: v1,
          scrubT: scrubT,
          ink: p.ink,
          ink3: p.ink3,
          grid: p.ink.withValues(alpha: .1),
          ground: Color.alphaBlend(p.ink.withValues(alpha: .04), p.bg),
        ),
      ),
    );
  }
}

class _ChartPaint extends CustomPainter {
  final WorkoutDetail d;
  final int? zone;
  final int v0, v1;
  final int? scrubT;
  final Color ink, ink3, grid, ground;
  _ChartPaint({
    required this.d,
    required this.zone,
    required this.v0,
    required this.v1,
    required this.scrubT,
    required this.ink,
    required this.ink3,
    required this.grid,
    required this.ground,
  });

  static const _foot = S.x8;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(0, S.x2, size.width, size.height - _foot);
    final bgPaint = Paint()
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
      );
    canvas.drawRect(plot, bgPaint);
    final span = math.max(1, v1 - v0);
    double xOf(num t) => (t - v0) / span * size.width;
    // What is in view, with a sample either side so the trace runs off the edge.
    final all = d.hr;
    var a = 0, b = all.length;
    while (a + 1 < b && all[a + 1].t < v0) {
      a++;
    }
    while (b - 2 > a && all[b - 2].t > v1) {
      b--;
    }
    final pts = all.sublist(a, b);
    // The scale stays the session's own, so a zoom changes the width only.
    var lo = 75.0, hi = 150.0;
    if (all.isNotEmpty) {
      final vs = all.map((e) => e.v);
      lo = ((vs.reduce(math.min) - 4) / 25).floor() * 25.0;
      hi = ((vs.reduce(math.max) + 4) / 25).ceil() * 25.0;
      if (hi - lo < 50) hi = lo + 50;
    }
    double yOf(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;

    // The grid: a line every 25 bpm, and the width in quarters.
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = plot.width * i / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gp);
    }
    for (var v = lo + 25; v < hi; v += 25) {
      canvas.drawLine(Offset(0, yOf(v)), Offset(size.width, yOf(v)), gp);
    }

    canvas.save();
    canvas.clipRect(plot.inflate(2));
    if (pts.length >= 2) {
      final line = Path()..moveTo(xOf(pts.first.t), yOf(pts.first.v));
      for (final e in pts.skip(1)) {
        line.lineTo(xOf(e.t), yOf(e.v));
      }
      final z = zone;
      if (z == null) {
        // The whole trace, filled to the floor.
        final fill = Path.from(line)
          ..lineTo(xOf(pts.last.t), plot.bottom)
          ..lineTo(xOf(pts.first.t), plot.bottom)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, plot.top),
              Offset(0, plot.bottom),
              [
                C.dialStrain.withValues(alpha: .42),
                C.dialStrain.withValues(alpha: .02),
              ],
            ),
        );
        canvas.drawPath(
          line,
          Paint()
            ..color = C.dialStrain
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round,
        );
      } else {
        // One zone lit: the trace grey, and each stretch in the zone filled
        // in its colour, each run apart from the next by a thin dark line.
        final col = _zoneColors[z];
        canvas.drawPath(
          line,
          Paint()
            ..color = ink3
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        final shade = Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, plot.top),
            Offset(0, plot.bottom),
            [col.withValues(alpha: .85), col.withValues(alpha: .08)],
          );
        final edge = Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        for (final (ra, rb) in d.zoneRuns[z]) {
          if (rb < v0 || ra > v1) continue;
          final seg = [
            for (final e in pts)
              if (e.t >= ra && e.t <= rb) e,
          ];
          if (seg.isEmpty) continue;
          final x0 = xOf(ra), x1 = math.max(xOf(rb), x0 + 1.5);
          final top = Path()..moveTo(x0, yOf(seg.first.v));
          for (final e in seg) {
            top.lineTo(xOf(e.t), yOf(e.v));
          }
          top.lineTo(x1, yOf(seg.last.v));
          final area = Path.from(top)
            ..lineTo(x1, plot.bottom)
            ..lineTo(x0, plot.bottom)
            ..close();
          canvas.drawPath(area, shade);
          canvas.drawPath(top, edge);
          canvas.drawLine(
            Offset(x1, plot.top),
            Offset(x1, plot.bottom),
            Paint()
              ..color = ground
              ..strokeWidth = 1.5,
          );
        }
      }
    }
    canvas.restore();

    // Labels on the left, over the grid.
    for (var v = lo + 25; v < hi; v += 25) {
      _text(
        canvas,
        '${v.round()}',
        Offset(S.x1, yOf(v) - S.x2),
        ink3,
        F.num(F.cap),
      );
    }

    // Where the session starts and ends: dashed lines, dots at the foot, and
    // the clock times under them, for whichever of them is in view.
    for (final (t, left) in [(d.start, true), (d.end, false)]) {
      if (t < v0 || t > v1) continue;
      final x = xOf(t);
      final dash = Paint()
        ..color = ink.withValues(alpha: .8)
        ..strokeWidth = 1.5;
      for (var y = plot.top; y < plot.bottom; y += S.x2) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + S.x1, plot.bottom)),
          dash,
        );
      }
      canvas.drawCircle(Offset(x, plot.bottom), S.x1, Paint()..color = ink);
      final at = DateTime.fromMillisecondsSinceEpoch(t * 1000);
      final tp = _layout(
        formatClock(at.hour, at.minute),
        F.num(F.cap).copyWith(color: ink, fontWeight: FontWeight.w700),
      );
      final tx = left ? x : x - tp.width;
      tp.paint(
        canvas,
        Offset(tx.clamp(0, size.width - tp.width), plot.bottom + S.x2),
      );
    }

    // The finger: a dotted line down the chart, and a dot on the reading.
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
      for (var y = S.x1; y < plot.bottom + S.x2; y += S.x2) {
        canvas.drawLine(Offset(x, y), Offset(x, y + S.x1), dot);
      }
      if (hit != null) {
        canvas.drawCircle(
          Offset(x, yOf(hit.v)),
          S.x2 + S.half,
          Paint()..color = ink,
        );
        canvas.drawCircle(
          Offset(x, yOf(hit.v)),
          S.x2,
          Paint()..color = C.dialStrain,
        );
      }
    }
  }

  TextPainter _layout(String s, TextStyle st) => TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
  )..layout();

  void _text(Canvas canvas, String s, Offset at, Color color, TextStyle st) =>
      _layout(s, st.copyWith(color: color)).paint(canvas, at);

  @override
  bool shouldRepaint(_ChartPaint o) =>
      o.d != d ||
      o.zone != zone ||
      o.ink != ink ||
      o.v0 != v0 ||
      o.v1 != v1 ||
      o.scrubT != scrubT;
}

/// One zone's bar: its share filled over a hatched track and the sport's
/// typical range as a dashed box — or, with a zone lit, when the session was
/// in this zone, laid along the session's own length.
class _ZoneBar extends CustomPainter {
  final double frac;
  final Color color, runColor, hatch, box;
  final (double, double)? typical;
  final List<(double, double)>? runs;
  _ZoneBar({
    required this.frac,
    required this.color,
    required this.typical,
    required this.runs,
    required this.runColor,
    required this.hatch,
    required this.box,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height * .3);
    final track = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.save();
    canvas.clipRRect(track);
    final hp = Paint()
      ..color = hatch
      ..strokeWidth = 2;
    for (var x = -size.height; x < size.width + size.height; x += 6) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), hp);
    }
    canvas.restore();

    final rs = runs;
    if (rs != null) {
      for (final (a, b) in rs) {
        final x0 = a.clamp(0.0, 1.0) * size.width;
        final x1 = math.max(b.clamp(0.0, 1.0) * size.width, x0 + 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x0, 0, x1, size.height),
            const Radius.circular(S.half),
          ),
          Paint()..color = runColor,
        );
      }
      return;
    }
    if (frac > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            0,
            0,
            math.max(size.height * .6, frac * size.width),
            size.height,
          ),
          r,
        ),
        Paint()..color = color,
      );
    }
    final t = typical;
    if (t != null) {
      final x0 = t.$1 * size.width, x1 = math.max(t.$2 * size.width, x0 + 4);
      final rect = Rect.fromLTRB(x0, -S.x1, x1, size.height + S.x1);
      canvas.drawRect(rect, Paint()..color = box.withValues(alpha: .12));
      final dp = Paint()
        ..color = box.withValues(alpha: .85)
        ..strokeWidth = 1.2;
      for (final x in [x0, x1]) {
        for (var y = rect.top; y < rect.bottom; y += 5) {
          canvas.drawLine(
            Offset(x, y),
            Offset(x, math.min(y + 2.5, rect.bottom)),
            dp,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ZoneBar o) =>
      o.frac != frac ||
      o.runs != runs ||
      o.typical != typical ||
      o.runColor != runColor;
}

/// The legend's key: a dashed-sided box.
class _TypicalBox extends CustomPainter {
  final Color line, fill;
  _TypicalBox(this.line, this.fill);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    final p = Paint()
      ..color = line
      ..strokeWidth = 1.2;
    for (final x in [0.6, size.width - .6]) {
      for (var y = 0.0; y < size.height; y += 4) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + 2, size.height)),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TypicalBox o) => o.line != line;
}

// ── the route ──────────────────────────────────────────────────────────────

class _RouteCard extends StatefulWidget {
  final WorkoutDetail d;
  final VoidCallback onShare;
  const _RouteCard({required this.d, required this.onShare});

  @override
  State<_RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<_RouteCard> {
  final _view = TransformationController();
  RouteMosaic? _mosaic;
  bool _asked = false;
  double? _builtFor;

  @override
  void dispose() {
    _view.dispose();
    _mosaic?.dispose();
    super.dispose();
  }

  Future<void> _build(
    double w,
    double h,
    double dpr,
    Color bg,
    Color ink,
  ) async {
    if (_builtFor == w) return;
    _builtFor = w;
    final geo = [for (final pt in widget.d.route!.points) (pt.lat, pt.lng)];
    final m = await buildRouteMosaic(
      geo,
      width: (w * dpr).round(),
      height: (h * dpr).round(),
      bg: bg,
      ink: ink,
      pad: .12,
    );
    if (!mounted) {
      m?.dispose();
      return;
    }
    setState(() {
      _mosaic?.dispose();
      _mosaic = m;
    });
  }

  void _zoom(double by) {
    final m = _view.value.clone();
    final s = (m.getMaxScaleOnAxis() * by).clamp(1.0, 5.0);
    final box = context.size;
    final cx = (box?.width ?? 0) / 2, cy = (_mapH) / 2;
    final scene = _view.toScene(Offset(cx, cy));
    final next = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
    setState(() => _view.value = next);
  }

  static const _mapH = S.x16 * 5;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = widget.d.route!;
    final imperial = unitsOf(c)?.isImperial ?? false;
    final km = r.distanceMeters / 1000;
    final dist = imperial ? km / 1.609344 : km;
    final hours = widget.d.durationSec / 3600;
    final speed = hours <= 0 ? null : dist / hours;
    final gain = _elevationGain(r.points);
    final ground = Color.alphaBlend(p.ink.withValues(alpha: .06), C.char);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
      child: Column(
        children: [
          SizedBox(
            height: _mapH,
            child: LayoutBuilder(
              builder: (c, box) {
                final w = box.maxWidth;
                if (mapTilesAllowed) {
                  _build(
                    w,
                    _mapH,
                    MediaQuery.devicePixelRatioOf(c),
                    ground,
                    p.ink,
                  );
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRect(
                        child: InteractiveViewer(
                          transformationController: _view,
                          minScale: 1,
                          maxScale: 5,
                          child: CustomPaint(
                            size: Size(w, _mapH),
                            painter: _RoutePaint(
                              points: r.points,
                              mosaic: _mosaic,
                              ground: ground,
                              line: C.dialStrain,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: S.x5,
                      top: S.x5,
                      child: Text(
                        'ROUTE',
                        style: F.body.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                    Positioned(
                      right: S.x5,
                      top: S.x5,
                      child: Pressable(
                        onTap: widget.onShare,
                        semanticLabel: 'Share',
                        child: Container(
                          width: S.x12 + S.x1,
                          height: S.x12 + S.x1,
                          decoration: BoxDecoration(
                            color: C.char,
                            borderRadius: R.rMd,
                          ),
                          child: const Icon(
                            LucideIcons.share2,
                            size: I.lg,
                            color: C.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: S.x4,
                      bottom: S.x5,
                      child: Container(
                        decoration: BoxDecoration(
                          color: C.cream.withValues(alpha: .85),
                          borderRadius: R.rSm,
                        ),
                        child: Column(
                          children: [
                            for (final (icon, by, name) in [
                              (LucideIcons.plus, 1.6, 'Zoom in'),
                              (LucideIcons.minus, 1 / 1.6, 'Zoom out'),
                            ])
                              Pressable(
                                onTap: () => _zoom(by),
                                semanticLabel: name,
                                child: SizedBox(
                                  width: S.tap + S.x2,
                                  height: S.tap + S.x2,
                                  child: Icon(icon, size: I.xl, color: C.n500),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_mosaic != null)
                      Positioned(
                        left: S.x4,
                        bottom: S.x3,
                        child: Text(
                          kOsmAttribution,
                          style: F.over.copyWith(color: p.ink2),
                        ),
                      )
                    else if (!mapTilesAllowed && !_asked)
                      Positioned(
                        left: S.x3,
                        bottom: S.x2,
                        child: TextAction('Show the map', () {
                          // Drawing the basemap asks openstreetmap.org for the
                          // tiles around the route: a tap here is the user saying
                          // it may, the same switch the share sheet sets.
                          setMapTilesAllowed(true);
                          setState(() {
                            _asked = true;
                            _builtFor = null;
                          });
                        }),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x6, S.x8, S.x4, S.x8),
            child: Row(
              children: [
                _routeStat(
                  p,
                  dist.toStringAsFixed(2),
                  imperial ? 'mi' : 'km',
                  'DISTANCE',
                ),
                _routeStat(
                  p,
                  speed == null ? '--' : speed.toStringAsFixed(1),
                  imperial ? 'mph' : 'kph',
                  'SPEED',
                ),
                _routeStat(
                  p,
                  gain == null
                      ? '--'
                      : '${(imperial ? gain * 3.28084 : gain).round()}',
                  imperial ? 'ft' : 'm',
                  'ELEV. GAIN',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeStat(P p, String v, String unit, String label) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              v,
              style: F.num(
                F.n34,
              ).copyWith(color: p.ink, fontWeight: FontWeight.w700),
            ),
            Text(
              unit,
              style: F.head.copyWith(color: p.ink, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: S.x1),
        Text(
          label,
          style: F.caps.copyWith(
            color: p.ink3,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ],
    ),
  );
}

/// Metres climbed: each rise counted once it clears three metres above the
/// lowest point since the last one, so GPS altitude jitter is not a climb.
/// Null when the route carries no altitude.
double? _elevationGain(List<RoutePoint> pts) {
  final alts = [
    for (final p in pts)
      if (p.alt != null) p.alt!,
  ];
  if (alts.length < 2) return null;
  var gain = 0.0, base = alts.first;
  for (final a in alts.skip(1)) {
    if (a < base) {
      base = a;
    } else if (a - base >= 3) {
      gain += a - base;
      base = a;
    }
  }
  return gain;
}

class _RoutePaint extends CustomPainter {
  final List<RoutePoint> points;
  final RouteMosaic? mosaic;
  final Color ground, line;
  _RoutePaint({
    required this.points,
    required this.mosaic,
    required this.ground,
    required this.line,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final m = mosaic;
    List<Offset> path;
    if (m != null) {
      canvas.drawImageRect(
        m.image,
        Rect.fromLTWH(0, 0, m.width, m.height),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
      final sx = size.width / m.width, sy = size.height / m.height;
      path = [for (final o in m.path) Offset(o.dx * sx, o.dy * sy)];
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = ground);
      path = _project(size);
    }
    if (path.length < 2) return;
    final pp = Path()..moveTo(path.first.dx, path.first.dy);
    for (final o in path.skip(1)) {
      pp.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      pp,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // The start: a dark disc ringed in white. The finish: a chequered disc.
    const r = S.x4 + S.half;
    canvas.drawCircle(path.first, r, Paint()..color = C.char);
    canvas.drawCircle(
      path.first,
      r,
      Paint()
        ..color = C.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final f = path.last;
    canvas.drawCircle(f, r, Paint()..color = C.white);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: f, radius: r - 3)));
    const sq = 4.0;
    for (var i = -5; i < 5; i++) {
      for (var j = -5; j < 5; j++) {
        if ((i + j).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(f.dx + i * sq, f.dy + j * sq, sq, sq),
            Paint()..color = C.char,
          );
        }
      }
    }
    canvas.restore();
  }

  /// No basemap: the route projected onto the card, north up.
  List<Offset> _project(Size size) {
    var loLat = points.first.lat, hiLat = loLat;
    var loLng = points.first.lng, hiLng = loLng;
    for (final p in points) {
      loLat = math.min(loLat, p.lat);
      hiLat = math.max(hiLat, p.lat);
      loLng = math.min(loLng, p.lng);
      hiLng = math.max(hiLng, p.lng);
    }
    final k = math.cos((loLat + hiLat) / 2 * math.pi / 180);
    final w = math.max(1e-9, (hiLng - loLng) * k),
        h = math.max(1e-9, hiLat - loLat);
    final pad = S.x12;
    final scale = math.min(
      (size.width - pad * 2) / w,
      (size.height - pad * 2) / h,
    );
    final ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2;
    return [
      for (final p in points)
        Offset(ox + (p.lng - loLng) * k * scale, oy + (hiLat - p.lat) * scale),
    ];
  }

  @override
  bool shouldRepaint(_RoutePaint o) => o.mosaic != mosaic || o.points != points;
}
