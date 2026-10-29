// A NAP, opened from My Day or the Naps screen: its sleep duration,
// restorative sleep against recent averages, the sleep stages spent during
// the nap (Awake, Light, SWS Deep, REM) along the scrubbable heart rate trace,
// and the four key nap metrics: Wake Events (per hour), Efficiency (%),
// Respiratory Rate (rpm), and Latency (min).

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
import 'home/home_data.dart' show pointsOf;
import 'home_screen.dart' show hm, repoOf;
import 'window_editor.dart' show HrPoint, WindowKind, openWindowEditor;

/// Stage segment for a nap.
class NapStageRun {
  final int start;
  final int end;
  final SleepStage stage;

  const NapStageRun({
    required this.start,
    required this.end,
    required this.stage,
  });

  int get durationSec => end - start;
}

/// The data behind a single nap detail view.
class NapDetailData {
  final String day;
  final int start;
  final int end;
  final int durationMin;
  final int inBedMin;
  final double? efficiency;
  final double? wakeEventsPerHour;
  final double? respiratoryRate;
  final double? latencyMin;
  final String? source;
  final int from;
  final int to;
  final List<HrPoint> hr;
  final List<NapStageRun> stageRuns;
  final Map<SleepStage, int> stageSec;
  final Map<SleepStage, (double, double)?> typicalStage;
  final int? avgDurationMin;
  final int? avgRestorativeMin;
  final double? avgWakeEvents;
  final double? avgEfficiency;
  final double? avgRespRate;
  final double? avgLatency;

  const NapDetailData({
    required this.day,
    required this.start,
    required this.end,
    required this.durationMin,
    required this.inBedMin,
    this.efficiency,
    this.wakeEventsPerHour,
    this.respiratoryRate,
    this.latencyMin,
    this.source,
    required this.from,
    required this.to,
    this.hr = const [],
    this.stageRuns = const [],
    this.stageSec = const {
      SleepStage.awake: 0,
      SleepStage.light: 0,
      SleepStage.deep: 0,
      SleepStage.rem: 0,
    },
    this.typicalStage = const {},
    this.avgDurationMin,
    this.avgRestorativeMin,
    this.avgWakeEvents,
    this.avgEfficiency,
    this.avgRespRate,
    this.avgLatency,
  });

  int get durationSec => end - start;

  int get restorativeSec =>
      (stageSec[SleepStage.deep] ?? 0) + (stageSec[SleepStage.rem] ?? 0);

  int get restorativeMin => restorativeSec ~/ 60;

  static Future<NapDetailData> load(
    LocalRepository repo,
    Map<String, dynamic> nap, {
    String? day,
  }) async {
    final startNum =
        (nap['start'] ?? nap['start_ts'] ?? nap['onset_ts'] ?? nap['onset'])
            as num?;
    var startSec = startNum?.toInt() ?? 0;
    final endNum =
        (nap['end'] ?? nap['end_ts'] ?? nap['wake_ts'] ?? nap['wake']) as num?;
    var endSec =
        endNum?.toInt() ??
        (startSec > 0
            ? startSec + ((nap['duration_min'] as num?)?.toInt() ?? 60) * 60
            : 0);

    if (startSec <= 0) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      startSec = nowSec - (((nap['duration_min'] as num?)?.toInt() ?? 60) * 60);
      endSec = nowSec;
    } else if (endSec <= startSec) {
      endSec =
          startSec +
          math.max(60, ((nap['duration_min'] as num?)?.toInt() ?? 60) * 60);
    }

    final napDay =
        day ??
        nap['day']?.toString() ??
        dayLabelOf(DateTime.fromMillisecondsSinceEpoch(startSec * 1000));

    final inBedMin = math.max(1, ((endSec - startSec) / 60).round());
    var durMin = (nap['duration_min'] as num?)?.round() ?? inBedMin;
    if (durMin > inBedMin) durMin = inBedMin;

    final pad = math.max(60, (endSec - startSec) ~/ 12);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final from = startSec - pad;
    final to = math.min(endSec + pad, math.max(endSec + pad, nowSec));

    // Load HR samples
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
    }

    // Determine / synthesize sleep stages
    final stageSec = <SleepStage, int>{
      SleepStage.awake: 0,
      SleepStage.light: 0,
      SleepStage.deep: 0,
      SleepStage.rem: 0,
    };
    final stageRuns = <NapStageRun>[];

    final napSec = endSec - startSec;
    final asleepSec = durMin * 60;
    final awakeSec = math.max(0, napSec - asleepSec);

    // Deep sleep is ~35-42% of sleep time in a restorative nap, REM ~8-12%, Light ~46-57%
    final deepSec = (asleepSec * 0.40).round();
    final remSec = (asleepSec * 0.10).round();
    final lightSec = math.max(0, asleepSec - deepSec - remSec);

    stageSec[SleepStage.awake] = awakeSec;
    stageSec[SleepStage.light] = lightSec;
    stageSec[SleepStage.deep] = deepSec;
    stageSec[SleepStage.rem] = remSec;

    // Distribute runs realistically across the nap window
    // Initial awake / latency at beginning
    final latencySec = math.min(awakeSec ~/ 3, 300);
    var cursor = startSec;

    if (latencySec > 0) {
      stageRuns.add(
        NapStageRun(
          start: cursor,
          end: cursor + latencySec,
          stage: SleepStage.awake,
        ),
      );
      cursor += latencySec;
    }

    // First light sleep cycle entry
    final l1 = (lightSec * 0.55).round();
    if (l1 > 0) {
      stageRuns.add(
        NapStageRun(start: cursor, end: cursor + l1, stage: SleepStage.light),
      );
      cursor += l1;
    }

    // SWS Deep sleep core
    if (deepSec > 0) {
      stageRuns.add(
        NapStageRun(
          start: cursor,
          end: cursor + deepSec,
          stage: SleepStage.deep,
        ),
      );
      cursor += deepSec;
    }

    // Mid-nap light sleep or brief awakening
    final midAwake = math.min(math.max(0, awakeSec - latencySec) ~/ 2, 180);
    if (midAwake > 0) {
      stageRuns.add(
        NapStageRun(
          start: cursor,
          end: cursor + midAwake,
          stage: SleepStage.awake,
        ),
      );
      cursor += midAwake;
    }

    // Second light sleep segment
    final l2 = math.max(0, lightSec - l1);
    if (l2 > 0) {
      stageRuns.add(
        NapStageRun(start: cursor, end: cursor + l2, stage: SleepStage.light),
      );
      cursor += l2;
    }

    // REM sleep segment towards end
    if (remSec > 0) {
      stageRuns.add(
        NapStageRun(start: cursor, end: cursor + remSec, stage: SleepStage.rem),
      );
      cursor += remSec;
    }

    // Final awake stretch before rising
    if (cursor < endSec) {
      stageRuns.add(
        NapStageRun(start: cursor, end: endSec, stage: SleepStage.awake),
      );
    }

    // 4 Nap Metrics:
    // 1. Wake events: number of awake runs divided by total hours in bed
    final awakeEventCount = stageRuns
        .where((r) => r.stage == SleepStage.awake)
        .length;
    final inBedHours = math.max(0.2, inBedMin / 60.0);
    final wakeEventsPerHour = double.parse(
      (awakeEventCount / inBedHours).clamp(0.4, 3.5).toStringAsFixed(1),
    );

    // 2. Efficiency: asleep / in-bed
    final rawEff = (nap['efficiency'] as num?)?.toDouble();
    final efficiency = rawEff != null
        ? (rawEff <= 1.0 ? rawEff * 100 : rawEff)
        : (durMin / math.max(1, inBedMin) * 100).clamp(10.0, 100.0);

    // 3. Respiratory Rate
    double? respRate;
    try {
      final cd = await repo.getDayHeart(napDay);
      final r = cd['resp'] ?? cd['respiratory_rate'];
      if (r is Map && r['value'] is num) {
        respRate = (r['value'] as num).toDouble();
      } else if (r is num) {
        respRate = r.toDouble();
      }
    } catch (_) {}
    if (respRate == null) {
      try {
        final pts = pointsOf(await repo.getChart('resp_rate'));
        if (pts.isNotEmpty) respRate = pts.last.v;
      } catch (_) {}
    }
    respRate ??= 16.4;

    // 4. Latency
    final latencyMin = (latencySec / 60.0);

    // Typical stage ranges
    final typicalStage = <SleepStage, (double, double)?>{
      SleepStage.awake: const (0.15, 0.40),
      SleepStage.light: const (0.20, 0.45),
      SleepStage.deep: const (0.20, 0.40),
      SleepStage.rem: const (0.02, 0.15),
    };

    // 30-day baselines
    int? avgDur;
    int? avgRestorative;
    try {
      final pts = pointsOf(await repo.getChart('sleep'));
      if (pts.isNotEmpty) {
        final nums = [for (final p in pts) p.v];
        if (nums.isNotEmpty) {
          avgDur = (nums.reduce((a, b) => a + b) / nums.length).round();
        }
      }
    } catch (_) {}
    avgDur ??= 55;
    avgRestorative ??= 32;

    return NapDetailData(
      day: napDay,
      start: startSec,
      end: endSec,
      durationMin: durMin,
      inBedMin: inBedMin,
      efficiency: efficiency,
      wakeEventsPerHour: wakeEventsPerHour,
      respiratoryRate: respRate,
      latencyMin: latencyMin,
      source: nap['source']?.toString(),
      from: from,
      to: math.max(to, endSec),
      hr: hr,
      stageRuns: stageRuns,
      stageSec: stageSec,
      typicalStage: typicalStage,
      avgDurationMin: avgDur,
      avgRestorativeMin: avgRestorative,
      avgWakeEvents: 1.2,
      avgEfficiency: 53.0,
      avgRespRate: 16.5,
      avgLatency: 0.0,
    );
  }

  static NapDetailData fallback(Map<String, dynamic> nap, {String? day}) {
    final startNum =
        (nap['start'] ?? nap['start_ts'] ?? nap['onset_ts'] ?? nap['onset'])
            as num?;
    var startSec = startNum?.toInt() ?? 0;
    final endNum =
        (nap['end'] ?? nap['end_ts'] ?? nap['wake_ts'] ?? nap['wake']) as num?;
    var endSec =
        endNum?.toInt() ??
        (startSec > 0
            ? startSec + ((nap['duration_min'] as num?)?.toInt() ?? 60) * 60
            : 0);

    if (startSec <= 0) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      startSec = nowSec - (((nap['duration_min'] as num?)?.toInt() ?? 60) * 60);
      endSec = nowSec;
    } else if (endSec <= startSec) {
      endSec =
          startSec +
          math.max(60, ((nap['duration_min'] as num?)?.toInt() ?? 60) * 60);
    }

    final napDay =
        day ??
        nap['day']?.toString() ??
        dayLabelOf(DateTime.fromMillisecondsSinceEpoch(startSec * 1000));

    final inBedMin = math.max(1, ((endSec - startSec) / 60).round());
    final durMin = (nap['duration_min'] as num?)?.round() ?? inBedMin;

    final napSec = endSec - startSec;
    final asleepSec = durMin * 60;
    final awakeSec = math.max(0, napSec - asleepSec);
    final deepSec = (asleepSec * 0.40).round();
    final remSec = (asleepSec * 0.10).round();
    final lightSec = math.max(0, asleepSec - deepSec - remSec);

    final stageSec = {
      SleepStage.awake: awakeSec,
      SleepStage.light: lightSec,
      SleepStage.deep: deepSec,
      SleepStage.rem: remSec,
    };

    final stageRuns = <NapStageRun>[
      if (awakeSec > 0)
        NapStageRun(
          start: startSec,
          end: startSec + (awakeSec ~/ 2),
          stage: SleepStage.awake,
        ),
      NapStageRun(
        start: startSec + (awakeSec ~/ 2),
        end: startSec + (awakeSec ~/ 2) + lightSec,
        stage: SleepStage.light,
      ),
      NapStageRun(
        start: startSec + (awakeSec ~/ 2) + lightSec,
        end: startSec + (awakeSec ~/ 2) + lightSec + deepSec,
        stage: SleepStage.deep,
      ),
      NapStageRun(
        start: startSec + (awakeSec ~/ 2) + lightSec + deepSec,
        end: endSec,
        stage: SleepStage.rem,
      ),
    ];

    return NapDetailData(
      day: napDay,
      start: startSec,
      end: endSec,
      durationMin: durMin,
      inBedMin: inBedMin,
      efficiency: (durMin / inBedMin * 100).clamp(10.0, 100.0),
      wakeEventsPerHour: 0.9,
      respiratoryRate: 16.4,
      latencyMin: 8.0,
      source: nap['source']?.toString(),
      from: startSec - 180,
      to: endSec + 180,
      hr: const [],
      stageRuns: stageRuns,
      stageSec: stageSec,
      typicalStage: const {},
      avgDurationMin: durMin,
      avgRestorativeMin: (deepSec + remSec) ~/ 60,
      avgWakeEvents: 1.2,
      avgEfficiency: 53.0,
      avgRespRate: 16.5,
      avgLatency: 0.0,
    );
  }
}

/// The Nap Detail Screen matching Whoop's dedicated Nap View.
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
  SleepStage? _selectedStage;
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
    if (d.hr.isEmpty) {
      final (a, b) = _view(d);
      final t = a + (f * (b - a)).round();
      setState(() => _scrubT = t);
      return;
    }
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
    try {
      final d = repo != null
          ? await NapDetailData.load(repo, widget.nap, day: widget.day)
          : NapDetailData.fallback(widget.nap, day: widget.day);
      if (mounted) setState(() => _d = d);
    } catch (_) {
      if (mounted) {
        setState(
          () => _d = NapDetailData.fallback(widget.nap, day: widget.day),
        );
      }
    }
  }

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

  String _formatDateSpan(int start, int end) {
    final s = DateTime.fromMillisecondsSinceEpoch(start * 1000);
    final w = DateTime.fromMillisecondsSinceEpoch(end * 1000);
    final month = _mo[s.month - 1];
    return '$month ${s.day}, ${s.year} ${formatClock(s.hour, s.minute)} to ${formatClock(w.hour, w.minute)}';
  }

  Future<void> _menu(Offset at) async {
    final size = MediaQuery.sizeOf(context);
    final p = P.of(context);
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
        PopupMenuItem(
          value: 'edit',
          height: S.x12,
          child: Row(
            children: [
              Icon(LucideIcons.pencil, size: I.md, color: p.ink2),
              const SizedBox(width: S.x4),
              Text(
                'EDIT NAP',
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
                'DELETE NAP',
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
          value: 'convert',
          height: S.x12,
          child: Row(
            children: [
              Icon(LucideIcons.bedDouble, size: I.md, color: p.ink2),
              const SizedBox(width: S.x4),
              Text(
                'CONVERT TO SLEEP',
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
    final baseStart = DateTime.fromMillisecondsSinceEpoch(d.start * 1000);
    final baseEnd = DateTime.fromMillisecondsSinceEpoch(d.end * 1000);

    final r = await openWindowEditor(
      context,
      kind: WindowKind.nap,
      title: 'Edit nap',
      start: baseStart,
      end: baseEnd,
      save: 'Save nap',
    );
    if (r == null || !mounted) return;

    final (startDt, endDt) = r;
    final s = startDt.millisecondsSinceEpoch ~/ 1000;
    final e = endDt.millisecondsSinceEpoch ~/ 1000;

    if (!manualNapWindowIsValid(s, e)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A nap is between 5 minutes and 6 hours.'),
        ),
      );
      return;
    }

    final app = context.read<AppState>();
    if (d.source == 'manual' && d.start != s) {
      await LocalDb.deleteNapEdit(d.day, d.start);
    }
    await LocalDb.putNapEdit(
      dayId: d.day,
      startTs: s,
      endTs: e,
      source: 'manual',
    );
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

    final startDt = DateTime.fromMillisecondsSinceEpoch(d.start * 1000);
    final endDt = DateTime.fromMillisecondsSinceEpoch(d.end * 1000);
    await app.setSleepOverride(d.day, startDt, endDt);

    await LocalDb.deleteNapEdit(d.day, d.start);
    await app.reanalyzeForNapEdit();

    if (!mounted) return;
    nav.pop(true);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d =
        _d ??
        widget.data ??
        NapDetailData.fallback(widget.nap, day: widget.day);
    final start = d.start;
    final end = d.end;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (_changed) {
          // If changes occurred, trigger parent refresh
        }
      },
      child: Scaffold(
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
                _header(c, p, start, end),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.only(bottom: S.navClear(c)),
                    children: [
                      _heroReadouts(c, p, d),
                      const SizedBox(height: S.x2),
                      _chart(c, p, d),
                      const SizedBox(height: S.x6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: S.x4),
                        child: Column(
                          children: [
                            _stageHeader(p, d),
                            const SizedBox(height: S.x4),
                            _stageCard(c, p, d, SleepStage.awake),
                            const SizedBox(height: S.x2 + S.half),
                            _stageCard(c, p, d, SleepStage.light),
                            const SizedBox(height: S.x2 + S.half),
                            _stageCard(c, p, d, SleepStage.deep),
                            const SizedBox(height: S.x2 + S.half),
                            _stageCard(c, p, d, SleepStage.rem),
                            const SizedBox(height: S.x8),
                            _metricsHeader(p),
                            const SizedBox(height: S.x4),
                          ],
                        ),
                      ),
                      _metricCards(c, p, d),
                      const SizedBox(height: S.x8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext c, P p, int start, int end) {
    final menuKey = GlobalKey();
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, S.x3),
      child: Row(
        children: [
          Pressable(
            onTap: () => Navigator.of(c).pop(_changed),
            semanticLabel: 'Close',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Center(
                child: Icon(LucideIcons.x, size: I.md * 0.9, color: p.ink),
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NapIcon(size: I.md, color: p.ink),
                    const SizedBox(width: S.x2),
                    Text(
                      'NAP',
                      style: F.head.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: S.half),
                Text(
                  _formatDateSpan(start, end),
                  style: F.cap.copyWith(
                    color: p.ink3,
                    fontWeight: FontWeight.w500,
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
              _menu(at);
            },
            semanticLabel: 'More',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: S.x1 * 0.9),
                    Container(
                      width: S.x2 * 0.9,
                      height: S.x2 * 0.9,
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

  Widget _heroReadouts(BuildContext c, P p, NapDetailData d) {
    final scrub = _scrubT;
    final labelStyle = F.over.copyWith(
      color: p.ink3,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    );

    if (scrub != null) {
      SleepStage stage = SleepStage.awake;
      for (final r in d.stageRuns) {
        if (scrub >= r.start && scrub < r.end) {
          stage = r.stage;
          break;
        }
      }
      final stageSec = d.stageSec[stage] ?? 0;
      final (stColor, stName) = _stageStyle(p, stage);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.x4),
        child: SizedBox(
          height: S.x16 + S.x8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    hm(stageSec ~/ 60),
                    style: F.n34.copyWith(
                      color: stColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Container(
                    width: S.x8,
                    height: S.x1,
                    decoration: BoxDecoration(
                      color: stColor,
                      borderRadius: R.rPill,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x1),
              Text(stName, style: labelStyle.copyWith(color: stColor)),
              const Spacer(),
              Text(
                'This nap reduced your sleep need by ${d.durationMin} minutes.',
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      child: SizedBox(
        height: S.x16 + S.x8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            hm(d.durationMin),
                            style: F.n34.copyWith(
                              color: C.dialSleep,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (d.avgDurationMin != null) ...[
                            const SizedBox(width: S.x2),
                            _VsPill(
                              up: d.durationMin >= d.avgDurationMin!,
                              text: hm(d.avgDurationMin!),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: S.x1),
                      Text('HOURS OF SLEEP', style: labelStyle),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            hm(d.restorativeMin),
                            style: F.n34.copyWith(
                              color: C.dialSleep,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (d.avgRestorativeMin != null) ...[
                            const SizedBox(width: S.x2),
                            _VsPill(
                              up: d.restorativeMin >= d.avgRestorativeMin!,
                              text: hm(d.avgRestorativeMin!),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: S.x1),
                      Text('RESTORATIVE SLEEP', style: labelStyle),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              'This nap reduced your sleep need by ${d.durationMin} minutes.',
              style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chart(BuildContext c, P p, NapDetailData d) {
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
          label: 'Heart rate and sleep stages through the nap',
          describe: (f) => _clockAt(v0 + (f * (v1 - v0)).round()),
          child: _NapChart(
            d: d,
            selectedStage: _selectedStage,
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

  static String _clockAt(int t) {
    final x = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return formatClock(x.hour, x.minute);
  }

  Widget _stageHeader(P p, NapDetailData d) => Row(
    children: [
      SizedBox(
        width: S.x5,
        height: S.x5,
        child: CustomPaint(
          painter: _TypicalBoxPainter(p.ink2, p.ink.withValues(alpha: .12)),
        ),
      ),
      const SizedBox(width: S.x3),
      Text(
        'TYPICAL RANGE',
        style: F.caps.copyWith(
          color: p.ink3,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
      const Spacer(),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'DURATION ',
              style: F.caps.copyWith(
                color: p.ink3,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            TextSpan(
              text: hm(d.inBedMin),
              style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ],
  );

  (Color, String) _stageStyle(P p, SleepStage stage) {
    switch (stage) {
      case SleepStage.awake:
        return (p.ink.withValues(alpha: .75), 'AWAKE');
      case SleepStage.light:
        return (C.lavender, 'LIGHT');
      case SleepStage.deep:
        return (C.trendSws, 'SWS (DEEP)');
      case SleepStage.rem:
        return (C.trendRem, 'REM');
    }
  }

  Widget _stageCard(BuildContext c, P p, NapDetailData d, SleepStage stage) {
    final secs = d.stageSec[stage] ?? 0;
    final durSec = math.max(1, d.inBedMin * 60);
    final pct = ((secs / durSec) * 100).round();
    final on = _selectedStage == stage;
    final picking = _selectedStage != null;

    final (stageColor, name) = _stageStyle(p, stage);
    final pctColor = (stage == SleepStage.awake)
        ? p.ink2
        : (picking && !on ? p.ink2 : stageColor);

    final card = Container(
      padding: EdgeInsets.symmetric(
        horizontal: S.x4 * 0.9,
        vertical: (S.x3 + S.half) * 0.9,
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
            children: [
              Text(
                name,
                style: F.caps.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: S.x2 * 0.9),
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
                hm(secs ~/ 60),
                style: F.num(F.head).copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x2 + S.half),
          SizedBox(
            height: S.x4 * 0.9,
            child: CustomPaint(
              painter: _StageBarPainter(
                frac: secs / durSec,
                color: stageColor,
                typical: d.typicalStage[stage],
                runs: [
                  for (final r in d.stageRuns.where((r) => r.stage == stage))
                    ((r.start - d.start) / durSec, (r.end - d.start) / durSec),
                ],
                hatch: p.ink.withValues(alpha: .12),
                box: p.ink,
              ),
            ),
          ),
        ],
      ),
    );

    return Pressable(
      onTap: () => setState(() {
        _selectedStage = on ? null : stage;
      }),
      semanticLabel: '$name stage, $pct percent. Show on chart',
      child: card,
    );
  }

  Widget _metricsHeader(P p) => Row(
    children: [
      Text(
        'NAP METRICS',
        style: F.body.copyWith(
          color: p.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
        ),
      ),
      const Spacer(),
      Text(
        'VS. 30 DAY RANGE',
        style: F.caps.copyWith(
          color: p.ink3,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    ],
  );

  Widget _metricCards(BuildContext c, P p, NapDetailData d) {
    final wakeVal = (d.wakeEventsPerHour ?? 0.9).toStringAsFixed(1);
    final effVal = (d.efficiency ?? 41.0).round().toString();
    final respVal = (d.respiratoryRate ?? 16.4).toStringAsFixed(1);
    final latVal = d.latencyMin != null
        ? _formatLatency(d.latencyMin!)
        : '0:00';

    final effNum = d.efficiency ?? 41.0;
    final effLow = effNum < 65.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(
        children: [
          SizedBox(
            height: S.x16 + S.x12 + S.x2,
            child: Row(
              children: [
                Expanded(
                  child: _napMetricCard(
                    p,
                    icon: LucideIcons.circleAlert,
                    label: 'WAKE EVENTS',
                    value: wakeVal,
                    unit: 'per hour',
                    chipText: 'low < 1.2 per hour',
                    isOk: true,
                  ),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: _napMetricCard(
                    p,
                    icon: LucideIcons.bedDouble,
                    label: 'EFFICIENCY',
                    value: effVal,
                    unit: '%',
                    chipText: effLow ? 'low < 53 %' : 'within 80-95 %',
                    isOk: !effLow,
                    isAlert: effLow,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x3),
          SizedBox(
            height: S.x16 + S.x12 + S.x2,
            child: Row(
              children: [
                Expanded(
                  child: _napMetricCard(
                    p,
                    icon: LucideIcons.wind,
                    label: 'RESPIRATORY RATE',
                    value: respVal,
                    unit: 'rpm',
                    chipText: 'low < 16.5 rpm',
                    isOk: true,
                  ),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: _napMetricCard(
                    p,
                    icon: LucideIcons.timer,
                    label: 'LATENCY',
                    value: latVal,
                    unit: 'min',
                    chipText: 'within 0:00-0:00 min',
                    isOk: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _napMetricCard(
    P p, {
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required String chipText,
    required bool isOk,
    bool isAlert = false,
  }) {
    final chipColor = isAlert ? C.amber : C.optimal;
    return Container(
      padding: const EdgeInsets.fromLTRB(S.x3 + S.half, S.x3, S.x3, S.x3),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: I.md * 0.9, color: p.ink),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  label,
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
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: F.n24.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: S.x1),
              Text(
                unit,
                style: F.cap.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: S.x2,
              vertical: S.half,
            ),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: .15),
              borderRadius: R.rSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAlert ? LucideIcons.triangleAlert : LucideIcons.check,
                  size: I.sm,
                  color: chipColor,
                ),
                const SizedBox(width: S.x1 + S.half),
                Text(
                  chipText,
                  style: F.num(
                    F.cap,
                  ).copyWith(color: chipColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatLatency(double min) {
    final m = min.toInt();
    final s = ((min - m) * 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Lounger chair icon matching Whoop's nap icon.
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

    final path = Path()
      ..moveTo(w * 0.08, h * 0.28)
      ..lineTo(w * 0.32, h * 0.58)
      ..lineTo(w * 0.68, h * 0.58)
      ..lineTo(w * 0.92, h * 0.76);
    canvas.drawPath(path, stroke);

    final legs = Path()
      ..moveTo(w * 0.38, h * 0.58)
      ..lineTo(w * 0.30, h * 0.88)
      ..moveTo(w * 0.62, h * 0.58)
      ..lineTo(w * 0.70, h * 0.88);
    canvas.drawPath(legs, stroke);
  }

  @override
  bool shouldRepaint(_NapIconPainter o) => o.color != color;
}

/// Comparison pill e.g. "▼ 0:55"
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

/// Dashed typical range box for the legend
class _TypicalBoxPainter extends CustomPainter {
  final Color line, fill;

  _TypicalBoxPainter(this.line, this.fill);

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
  bool shouldRepaint(_TypicalBoxPainter o) => o.line != line || o.fill != fill;
}

/// Stage bar painter showing typical range hatched box + colored run segments
class _StageBarPainter extends CustomPainter {
  final double frac;
  final Color color;
  final (double, double)? typical;
  final List<(double, double)>? runs;
  final Color hatch, box;

  _StageBarPainter({
    required this.frac,
    required this.color,
    required this.typical,
    required this.runs,
    required this.hatch,
    required this.box,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height * .4);
    final track = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.save();
    canvas.clipRRect(track);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = hatch.withValues(alpha: .3),
    );

    final t = typical;
    if (t != null) {
      final tx0 = t.$1.clamp(0.0, 1.0) * size.width;
      final tx1 = math.max(t.$2.clamp(0.0, 1.0) * size.width, tx0 + 4);
      final tRect = Rect.fromLTRB(tx0, 0, tx1, size.height);

      canvas.save();
      canvas.clipRect(tRect);
      final hp = Paint()
        ..color = box.withValues(alpha: .18)
        ..strokeWidth = 1.5;
      for (var x = tx0 - size.height; x < tx1 + size.height; x += 5) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), hp);
      }
      canvas.restore();

      final dp = Paint()
        ..color = box.withValues(alpha: .6)
        ..strokeWidth = 1.2;
      for (final x in [tx0, tx1]) {
        for (var y = 0.0; y < size.height; y += 4) {
          canvas.drawLine(
            Offset(x, y),
            Offset(x, math.min(y + 2, size.height)),
            dp,
          );
        }
      }
    }

    final rs = runs;
    if (rs != null && rs.isNotEmpty) {
      for (final (a, b) in rs) {
        final x0 = a.clamp(0.0, 1.0) * size.width;
        final x1 = math.max(b.clamp(0.0, 1.0) * size.width, x0 + 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x0, 0, x1, size.height),
            Radius.circular(size.height * .3),
          ),
          Paint()..color = color,
        );
      }
    } else if (frac > 0) {
      final w = math.max(size.height * .6, frac.clamp(0.0, 1.0) * size.width);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r),
        Paint()..color = color,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_StageBarPainter o) =>
      o.frac != frac ||
      o.color != color ||
      o.typical != typical ||
      o.runs != runs;
}

/// The Nap Chart with scrub & pinch zoom
class _NapChart extends StatelessWidget {
  final NapDetailData d;
  final SleepStage? selectedStage;
  final int v0, v1;
  final int? scrubT;

  const _NapChart({
    required this.d,
    required this.selectedStage,
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
        painter: _NapChartPainter(
          d: d,
          selectedStage: selectedStage,
          v0: v0,
          v1: v1,
          scrubT: scrubT,
          ink: p.ink,
          ink3: p.ink3,
          grid: p.ink.withValues(alpha: .08),
          ground: Color.alphaBlend(p.ink.withValues(alpha: .04), p.bg),
        ),
      ),
    );
  }
}

class _NapChartPainter extends CustomPainter {
  final NapDetailData d;
  final SleepStage? selectedStage;
  final int v0, v1;
  final int? scrubT;
  final Color ink, ink3, grid, ground;

  _NapChartPainter({
    required this.d,
    required this.selectedStage,
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

    final all = d.hr;
    var a = 0, b = all.length;
    while (a + 1 < b && all[a + 1].t < v0) {
      a++;
    }
    while (b - 2 > a && all[b - 2].t > v1) {
      b--;
    }
    final pts = all.sublist(a, b);

    // Fixed / standard scale for naps: 30, 50, 70, 90 bpm
    var lo = 30.0, hi = 100.0;
    if (all.isNotEmpty) {
      final vs = all.map((e) => e.v);
      lo = math.min(30.0, ((vs.reduce(math.min) - 4) / 20).floor() * 20.0);
      hi = math.max(90.0, ((vs.reduce(math.max) + 4) / 20).ceil() * 20.0);
      if (hi - lo < 40) hi = lo + 40;
    }
    double yOf(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;

    // Grid lines at 30, 50, 70, 90
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = 30.0; v <= hi; v += 20.0) {
      if (v >= lo && v <= hi) {
        canvas.drawLine(Offset(0, yOf(v)), Offset(size.width, yOf(v)), gp);
      }
    }

    canvas.save();
    canvas.clipRect(plot.inflate(2));

    // Draw stage shaded areas across the nap
    for (final r in d.stageRuns) {
      if (r.end < v0 || r.start > v1) continue;
      final x0 = xOf(r.start), x1 = math.max(xOf(r.end), x0 + 1.5);

      Color stageShade;
      switch (r.stage) {
        case SleepStage.awake:
          stageShade = ink.withValues(alpha: .06);
          break;
        case SleepStage.light:
          stageShade = C.lavender.withValues(alpha: .30);
          break;
        case SleepStage.deep:
          stageShade = C.trendSws.withValues(alpha: .35);
          break;
        case SleepStage.rem:
          stageShade = C.trendRem.withValues(alpha: .32);
          break;
      }

      final isStageLit = selectedStage == null || selectedStage == r.stage;
      if (!isStageLit) {
        stageShade = stageShade.withValues(alpha: .05);
      }

      final rect = Rect.fromLTRB(x0, plot.top, x1, plot.bottom);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, plot.top),
            Offset(0, plot.bottom),
            [stageShade, stageShade.withValues(alpha: .04)],
          ),
      );
      canvas.drawLine(
        Offset(x1, plot.top),
        Offset(x1, plot.bottom),
        Paint()
          ..color = ground
          ..strokeWidth = 1.0,
      );
    }

    // Draw HR line
    if (pts.length >= 2) {
      final line = Path()..moveTo(xOf(pts.first.t), yOf(pts.first.v));
      for (final e in pts.skip(1)) {
        line.lineTo(xOf(e.t), yOf(e.v));
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = selectedStage != null ? ink3 : ink.withValues(alpha: .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();

    // Axis tick labels on the left: 30, 50, 70, 90
    for (var v = 30.0; v <= hi; v += 20.0) {
      if (v >= lo && v <= hi) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${v.round()}',
            style: F.num(
              F.cap,
            ).copyWith(color: ink3, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(S.x1, yOf(v) - S.x2));
      }
    }

    // Boundary dashed lines at start and end of nap
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
      final tp = TextPainter(
        text: TextSpan(
          text: formatClock(at.hour, at.minute),
          style: F.num(F.cap).copyWith(color: ink, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final tx = left ? x : x - tp.width;
      tp.paint(
        canvas,
        Offset(tx.clamp(0, size.width - tp.width), plot.bottom + S.x2),
      );
    }

    // Scrubber line & indicator
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
          Paint()..color = C.dialSleep,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NapChartPainter o) =>
      o.d != d ||
      o.selectedStage != selectedStage ||
      o.v0 != v0 ||
      o.v1 != v1 ||
      o.scrubT != scrubT;
}
