// STRESS MONITOR — a 0–3 reading for every minute of the day, from heart rate
// and HRV against your own last 14 days, with motion taken out (see
// `compute/stress_monitor.dart` for the arithmetic).
//
// The gauge reads the end of the day, or the minute under your finger. The
// chart is the day: sleep shaded, workouts marked, the line coloured by how
// high it is. Under it, how long the day spent at each level against a typical
// one. When there is no baseline yet the screen says so; it does not guess.

import '../../state/duration_format.dart';
import 'dart:async';
import 'dart:isolate';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compute/sleep_stress.dart';
import '../../compute/stress_monitor.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart' show activityByName, kUnknownActivityIcon;
import '../../state/clock_format.dart';
import '../ui2.dart';
import 'calibration.dart' show CalibrationStrip, Milestone;
import 'home_screen.dart' show go, monthShortName, pad, repoOf, weekdayShortName;
import 'trend_view.dart' show TrendViewScreen, shiftDay;

/// The colour of a score: blue when calm, through green and a warm yellow, to
/// orange at the top of the scale.
Color stressColor(double score) {
  const stops = [C.stressLow, C.stressMedium, C.stressWarm, C.stressHigh];
  final t = score.clamp(0.0, 3.0);
  final i = math.min(2, t.floor());
  return Color.lerp(stops[i], stops[i + 1], t - i)!;
}

/// A level's colour, on every screen that splits stress into three.
Color stressLevelColor(StressLevel l) => switch (l) {
      StressLevel.low => C.stressLow,
      StressLevel.medium => C.stressMedium,
      StressLevel.high => C.stressHigh,
    };

String _levelName(StressLevel l) => switch (l) {
      StressLevel.low => 'LOW',
      StressLevel.medium => 'MEDIUM',
      StressLevel.high => 'HIGH',
    };

String _clock(int minuteOfDay) => formatAxisClock(minuteOfDay);

/// A workout on the day, in minutes since midnight.
class StressSession {
  final int from, to;
  final String type;
  const StressSession(this.from, this.to, this.type);
}

/// Everything the screen draws for one day.
class StressMonitorData {
  final String day;

  /// One score per minute; null where there is no heart rate or no baseline.
  final List<double?> scores;
  final StressBaseline? baseline;

  /// Sleep, as [from, to) minute ranges.
  final List<(int, int)> sleep;
  final List<StressSession> sessions;
  final ({int low, int medium, int high}) minutes;

  /// The average day's minutes at each level over the days before, or null
  /// with fewer than three days to average.
  final ({double low, double medium, double high})? typical;

  /// With no baseline yet: how many of the days before it could use, out of
  /// [kStressBaselineDays].
  final int usableDays;

  const StressMonitorData({
    required this.day,
    required this.scores,
    required this.baseline,
    this.sleep = const [],
    this.sessions = const [],
    this.minutes = (low: 0, medium: 0, high: 0),
    this.typical,
    this.usableDays = 0,
  });

  /// The last minute that has a score: where the day "is" for the gauge.
  int? get last {
    for (var i = scores.length - 1; i >= 0; i--) {
      if (scores[i] != null) return i;
    }
    return null;
  }
}

/// Minutes a day needs scored before its share of high stress (or its mean) is
/// read: the same six hours the typical-day split asks for.
const kStressDayMinScored = 360;

double _highPct(List<double?> scores) {
  final m = stressMinutes(scores);
  return m.high / (m.low + m.medium + m.high) * 100;
}

double _meanScore(List<double?> scores) {
  final xs = [for (final s in scores) ?s];
  return xs.reduce((a, b) => a + b) / xs.length;
}

/// A day's scores as every screen reads them: awake minutes against the waking
/// baseline, minutes asleep against the sleeping one ([sleepStress]), so the
/// Stress Monitor's night and Sleep stress are the same curve. [nights] is
/// keyed by wake day. A night that cannot be judged keeps the waking scores.
/// [asleep], when given, is marked for every minute a night replaced.
List<double?> _dayScores(StressDayInput d, StressBaseline base,
    Map<String, NightWindow> nights, Map<String, StressDayInput> days,
    [List<bool>? asleep]) {
  final out = stressScores(d, base);
  // The night that ended on this day, and the one starting on its evening.
  for (final wake in [d.day, shiftDay(d.day, 1)]) {
    final night = nights[wake];
    if (night == null) continue;
    final s = sleepStress(
        night,
        [for (var i = 1; i <= 10; i++) ?nights[shiftDay(wake, -i)]],
        days);
    if (s == null) continue;
    for (var i = s.curveLead; i < s.curve.length; i++) {
      final ts = night.onset + (i - s.curveLead) * 60;
      if (ts >= night.wake) break;
      final at = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      if (dayLabelOf(at) != d.day) continue;
      final k = at.hour * 60 + at.minute;
      out[k] = s.curve[i];
      asleep?[k] = true;
    }
  }
  return out;
}

/// Reads and scores days, keeping each day's series so paging back and forth
/// does not decode the same bundle twice.

class StressSource {
  final LocalRepository repo;
  StressSource(this.repo);

  final _inputs = <String, Future<StressDayInput?>>{};
  final _timelines = <String, Future<Map<String, dynamic>?>>{};

  Future<Map<String, dynamic>?> _timeline(String day) =>
      _timelines[day] ??= () async {
        try {
          final t = await repo.getDayTimeline(day);
          // A bundle served in place of the day asked for is not that day.
          return t['date'] == day ? t : null;
        } catch (e) {
          // Not kept: a read that failed while a sync was writing (the first
          // open after waking) would otherwise stay empty for as long as the
          // source lives.
          debugPrint('[OpenStrap] [stress] $day read failed: $e');
          forget(day);
          return null;
        }
      }();

  /// Drops what was read for [day], so the next read sees what has been
  /// stored since: a day still being recorded changes under a long-lived
  /// source (Home keeps one), and a stale copy read as NO DATA all day.
  void forget(String day) {
    _inputs.remove(day);
    _timelines.remove(day);
  }

  Future<StressDayInput?> _input(String day) => _inputs[day] ??= () async {
        final t = await _timeline(day);
        return t == null ? null : StressDayInput.fromTimeline(day, t);
      }();

  /// The night that ended on [day], or null.
  Future<NightWindow?> _night(String day) async {
    final w = ((await _timeline(day))?['sleep'] as List?)?.whereType<Map>().firstOrNull;
    final on = w?['onset_ts'], off = w?['wake_ts'];
    if (on is! num || off is! num || off <= on) return null;
    return (onset: on.toInt(), wake: off.toInt());
  }

  /// The nights that ended on any of [days], by wake day.
  Future<Map<String, NightWindow>> _nights(Iterable<String> days) async {
    final got = await Future.wait([for (final d in days) _night(d)]);
    return {
      for (final (i, d) in days.indexed) d: ?got[i],
    };
  }

  /// High sleep stress for the night that ended on [day], against the nights
  /// before it. Null when it cannot be said (see [sleepStress]).
  Future<SleepStress?> sleepStressOf(String day) async {
    try {
      final back = [for (var i = 1; i <= 10; i++) shiftDay(day, -i)];
      // Every day the nights touch: each wake day and the evening before it.
      final all = {day, shiftDay(day, -1), for (final d in back) ...[d, shiftDay(d, -1)]};
      final got = await Future.wait([for (final d in all) _input(d)]);
      final days = {
        for (final (i, d) in all.indexed) if (got[i] != null) d: got[i]!,
      };
      final night = await _night(day);
      if (night == null) return null;
      final prior = [
        for (final w in await Future.wait([for (final d in back) _night(d)])) ?w,
      ];
      return sleepStress(night, prior, days);
    } catch (_) {
      return null;
    }
  }

  /// The share of each of [days] in the high stress zone, 0–100, each against
  /// the two weeks before it. A day with too little scored is left out. The
  /// scoring runs off the UI isolate: this is a season of minutes.
  Future<Map<String, double>> highPctByDay(List<String> days) =>
      _perDay(days, _highPct);

  /// Each of [days]' mean score, 0–3, on the same terms as [highPctByDay].
  Future<Map<String, double>> avgByDay(List<String> days) =>
      _perDay(days, _meanScore);

  /// Each of [days]' minutes at each level, on the same terms as
  /// [highPctByDay]: Trend View's total-day stress.
  Future<Map<String, ({int low, int medium, int high})>> minutesByDay(
          List<String> days) =>
      _perDay(days, stressMinutes);

  Future<Map<String, T>> _perDay<T>(
      List<String> days, T Function(List<double?>) read) async {
    final inputs = <String, StressDayInput>{};
    final need = {
      for (final d in days)
        for (var i = -1; i <= 14; i++) shiftDay(d, -i),
    };
    for (final d in need) {
      final got = await _input(d);
      if (got != null) inputs[d] = got;
    }
    final nights = await _nights(need);
    final want = [...days];
    final prior = {
      for (final d in want)
        d: [for (var i = 1; i <= 14; i++) shiftDay(d, -i)],
    };
    return Isolate.run(() {
      final out = <String, T>{};
      for (final d in want) {
        final today = inputs[d];
        if (today == null) continue;
        final base = stressBaseline([for (final p in prior[d]!) ?inputs[p]]);
        if (base == null) continue;
        final scores = _dayScores(today, base, nights, inputs);
        if (scores.where((s) => s != null).length >= kStressDayMinScored) {
          out[d] = read(scores);
        }
      }
      return out;
    });
  }

  Future<StressMonitorData> load(String day) async {
    final wanted = [
      day,
      shiftDay(day, 1), // the night starting this evening ends there
      for (var i = 1; i <= 14; i++) shiftDay(day, -i),
    ];
    final fetched = await Future.wait([for (final d in wanted) _input(d)]);
    final today = fetched.first;
    final prior = [for (final d in fetched.skip(2)) ?d];
    final baseline = stressBaseline(prior);
    if (today == null || baseline == null) {
      return StressMonitorData(
          day: day,
          scores: List.filled(1440, null),
          baseline: baseline,
          usableDays: stressUsableDays(prior));
    }
    final days = {
      for (final d in fetched)
        if (d != null) d.day: d, // ignore: use_null_aware_elements
    };
    final nights = await _nights(wanted);
    final asleep = [...today.asleep];
    final scores = _dayScores(today, baseline, nights, days, asleep);

    // How a typical day splits, from the days before, on the same baselines.
    // ponytail: the oldest few of these days have fewer than three earlier
    // nights in hand, so their sleep stays on the waking baseline; fetch ten
    // more days here if the typical split ever needs to be exact.
    final spent = [
      for (final d in prior)
        _dayScores(d, baseline, nights, days),
    ]
        .where((s) => s.where((x) => x != null).length >= kStressDayMinScored)
        .map(stressMinutes)
        .toList();
    final typical = spent.length < 3
        ? null
        : (
            low: spent.fold<double>(0, (a, m) => a + m.low) / spent.length,
            medium: spent.fold<double>(0, (a, m) => a + m.medium) / spent.length,
            high: spent.fold<double>(0, (a, m) => a + m.high) / spent.length,
          );

    final sleep = <(int, int)>[];
    int? from;
    for (var i = 0; i <= 1440; i++) {
      final on = i < 1440 && asleep[i];
      if (on && from == null) from = i;
      if (!on && from != null) {
        sleep.add((from, i));
        from = null;
      }
    }

    return StressMonitorData(
      day: day,
      scores: scores,
      baseline: baseline,
      sleep: sleep,
      sessions: await _sessions(day),
      minutes: stressMinutes(scores),
      typical: typical,
    );
  }

  Future<List<StressSession>> _sessions(String day) async {
    final a = localDayStartSec(day), b = localDayEndSec(day);
    if (a == null || b == null) return const [];
    try {
      final rows = await repo.getSessions(from: a, to: b - 1, includeDetected: false);
      return [
        for (final r in rows)
          if (r['start_ts'] is num && r['end_ts'] is num)
            StressSession(
              ((r['start_ts'] as num).toInt() - a) ~/ 60,
              ((r['end_ts'] as num).toInt() - a) ~/ 60,
              (r['type'] ?? 'Workout').toString(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

class StressMonitorScreen extends StatefulWidget {
  /// Injected by tests; production builds its own from the repo.
  final StressSource? source;
  final String? today;

  /// The day it opens on; today when null.
  final String? day;
  const StressMonitorScreen({super.key, this.source, this.today, this.day});

  @override
  State<StressMonitorScreen> createState() => _StressMonitorScreenState();
}

class _StressMonitorScreenState extends State<StressMonitorScreen>
    with RevisionReload {
  StressSource? _source;
  late String _day = widget.day ?? _today;
  StressMonitorData? _data;
  String? _loaded;
  bool _zoom = false;
  int? _zoomOffset;
  int _pinchStartFrom = 0;

  /// The minute under a finger, or null at rest.
  int? _at;

  String get _today => widget.today ?? todayLabel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      // Looking at it now: pull what the band has banked since the last
      // offload, which can be a quarter of an hour old. The derive that
      // follows lands in [reload].
      if (widget.source == null && mounted && _day == _today) {
        try {
          unawaited(context.read<AppState>().foregroundCatchUp());
        } catch (_) {
          // No AppState above a golden or the gallery.
        }
      }
    });
  }

  /// A sync or a derive wrote newer minutes: read the day again, in place.
  @override
  void reload() {
    for (var i = -1; i <= 1; i++) {
      _source?.forget(shiftDay(_day, i));
    }
    _load();
  }

  Future<void> _load() async {
    if (_source == null) {
      final repo = widget.source == null ? repoOf(context) : null;
      if (widget.source == null && repo == null) {
        if (mounted) setState(() => _loaded = _day);
        return;
      }
      _source = widget.source ?? StressSource(repo!);
    }
    final day = _day;
    final ask = beginRead(#day);
    final d = await _source!.load(day);
    if (!stillNewest(#day, ask) || day != _day) return;
    setState(() {
      _data = d;
      _loaded = day;
    });
  }

  void _page(int by) {
    setState(() {
      _day = shiftDay(_day, by);
      _at = null;
      _zoom = false;
      _data = null;
      _loaded = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = _loaded == _day ? _data : null;
    final loading = _loaded != _day;
    final last = d?.last;
    final shown = _at ?? last;
    final score = shown == null ? null : d?.scores[shown];
    final date = DateTime.parse(_day);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(padding: pad, children: [
          NavBar('Stress Monitor'),
          const SizedBox(height: S.x2),
          _pager(p, date, l),
          const SizedBox(height: S.x4),
          _Gauge(
            score: score,
            time: shown == null ? null : formatClockMinute(shown),
            onInfo: () => _info(c, d),
          ),
          const SizedBox(height: S.x6),
          if (loading)
            const SizedBox(
                height: S.x16 * 3, child: Center(child: CircularProgressIndicator()))
          else ...[
            if (d == null)
              const StatusCard('No data', 'Nothing is stored for this day yet.',
                  fix: '', icon: LucideIcons.brain)
            else if (d.baseline == null)
              Surface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CALIBRATING',
                          style: F.caps.copyWith(
                              color: p.ink, fontWeight: FontWeight.w800)),
                      const SizedBox(height: S.x2),
                      Text(
                          'Stress is read against your own last 14 days, so '
                          'it needs at least three of them with quiet, awake '
                          'heart rate and HRV.',
                          style: F.cap.copyWith(color: p.ink2)),
                      const SizedBox(height: S.x4),
                      CalibrationStrip(Milestone(
                        title: 'Stress monitor',
                        about: '',
                        icon: LucideIcons.brain,
                        need: kStressBaselineDays,
                        have: d.usableDays,
                        days: true,
                        done: false,
                      )),
                    ]),
              )
            else if (last == null)
              const StatusCard('No heart rate on this day',
                  'The band recorded no heart rate, so there is nothing to score.',
                  fix: '', icon: LucideIcons.heartOff)
            else
              _chart(p, d, last),
            if (_source != null) ...[
              const SizedBox(height: S.x8),
              StressTrendCard(
                key: ValueKey(_day),
                source: _source!,
                day: _day,
                today: _today,
              ),
            ],
            if (d != null && d.baseline != null && last != null) ...[
              const SizedBox(height: S.x8),
              _totalDay(p, d, date, l),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _pager(P p, DateTime date, AppLocalizations? l) {
    final label =
        '${weekdayShortName(date.weekday, l)}, ${monthShortName(date.month, l)} ${date.day}'
            .toUpperCase();
    Widget arrow(IconData i, String name, VoidCallback? tap) => Pressable(
          onTap: tap,
          semanticLabel: name,
          child: SizedBox(
            width: S.x12,
            height: S.tap,
            child: Icon(i, size: I.md, color: tap == null ? p.track : p.ink),
          ),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      arrow(LucideIcons.chevronLeft, 'Earlier day', () => _page(-1)),
      SizedBox(
        width: S.x16 * 2.5,
        child: Text(label,
            textAlign: TextAlign.center,
            style: F.caps.copyWith(color: p.ink)),
      ),
      arrow(LucideIcons.chevronRight, 'Later day',
          _day == _today ? null : () => _page(1)),
    ]);
  }

  void _pinch(PinchPhase phase, double scale, double focal, double pan, int last) {
    if (!_zoom) return;
    final maxFrom = math.max(0, last - 180);
    switch (phase) {
      case PinchPhase.start:
        _pinchStartFrom = _zoomOffset ?? maxFrom;
      case PinchPhase.update:
        final shifted = (_pinchStartFrom - (pan * 180).round()).clamp(0, maxFrom);
        setState(() {
          _zoomOffset = shifted;
        });
      case PinchPhase.end:
        break;
    }
  }

  // ── the chart ────────────────────────────────────────────────────────────
  Widget _chart(P p, StressMonitorData d, int last) {
    final maxFrom = math.max(0, last - 180);
    final from = _zoom ? (_zoomOffset ?? maxFrom).clamp(0, maxFrom) : 0;
    final to = _zoom ? math.min(last, from + 180) : last;
    final n = to - from + 1;
    final values = d.scores.sublist(from, to + 1);
    final labelMinutes = <int>{
      if (!_zoom) ...[0, 360, 720, 1080].where((m) => last - m > 100),
      if (_zoom) ...[for (var m = (from ~/ 60 + 1) * 60; m < to - 20; m += 60) m],
    };
    final xLabels = [
      for (var i = 0; i < n; i++)
        i == n - 1
            ? _clock(to)
            : i == 0
                ? _clock(from)
                : labelMinutes.contains(from + i)
                    ? _clock(from + i)
                    : '',
    ];
    const gutter = S.x10;
    final line = ScrubLine(
      values: values,
      xLabels: xLabels,
      lo: -.08,
      hi: 3,
      ticks: const [0, 1, 2, 3],
      tickText: (t) => t.toStringAsFixed(1),
      color: C.stressMedium,
      colorAt: stressColor,
      fill: false,
      markers: false,
      slots: false,
      gap: 12,
      highlight: to == last ? n - 1 : null,
      height: S.x16 * 3 + S.x10,
      gutter: gutter,
      label: 'Stress through the day',
      onPinch: _zoom ? (phase, scale, focal, pan) => _pinch(phase, scale, focal, pan, last) : null,
      describe: (i) => '${formatClockMinute(from + i)}: '
          '${values[i] == null ? 'no reading' : values[i]!.toStringAsFixed(1)}',
      onScrub: (i) => setState(() => _at = i == null ? null : from + i),
      paintUnder: (canvas, plot, xOf, yOf) {
        // Sleep: a soft block with a bar along its top.
        for (final (a, b) in d.sleep) {
          final x1 = xOf(math.max(a, from) - from), x2 = xOf(math.min(b, to) - from);
          if (b <= from || a > to || x2 <= x1) continue;
          canvas.drawRect(Rect.fromLTRB(x1, plot.top, x2, plot.bottom),
              Paint()..color = p.ink.withValues(alpha: .05));
          canvas.drawLine(Offset(x1, plot.top), Offset(x2, plot.top),
              Paint()..color = C.stressLow..strokeWidth = 2);
        }
        // Workouts: a faint span, marked above in blue.
        for (final s in d.sessions) {
          if (s.to < from || s.from > to) continue;
          final x1 = xOf(math.max(s.from, from) - from), x2 = xOf(math.min(s.to, to) - from);
          canvas.drawRect(Rect.fromLTRB(x1, plot.top, math.max(x2, x1 + 2), plot.bottom),
              Paint()..color = C.dialStrain.withValues(alpha: .10));
          canvas.drawLine(Offset(x1, plot.top - 3), Offset(math.max(x2, x1 + 2), plot.top - 3),
              Paint()..color = C.dialStrain..strokeWidth = 3);
        }
      },
      paintOver: (canvas, plot, xOf, yOf) {
        // Where the day is now: a dashed line down to a dot on the reading if visible.
        if (last < from || last > to) return;
        final x = xOf(last - from);
        final dash = Paint()
          ..color = p.ink
          ..strokeWidth = 1.5;
        for (var y = plot.top; y < plot.bottom; y += S.x2) {
          canvas.drawLine(Offset(x, y), Offset(x, math.min(y + S.x1, plot.bottom)), dash);
        }
        final v = values[last - from];
        if (v != null) canvas.drawCircle(Offset(x, yOf(v)), S.x1, Paint()..color = p.ink);
      },
    );

    return LayoutBuilder(builder: (c, box) {
      final plotW = box.maxWidth - gutter - S.x2;
      double xAt(int minute) => gutter + (minute - from) / math.max(1, n - 1) * plotW;
      final marks = [
        for (final (a, b, icon) in [
          for (final (a, b) in d.sleep) (a, b, LucideIcons.moon),
          for (final s in d.sessions)
            (s.from, s.to, activityByName(s.type)?.icon ?? kUnknownActivityIcon),
        ])
          if (b > from && a <= to)
            (
              x: (xAt(math.max(a, from)) + xAt(math.min(b, to))) / 2,
              icon: icon,
            ),
      ];
      return Stack(children: [
        line,
        for (final g in clusterMarks(marks, (m) => m.x, gap: I.md + S.x1))
          Positioned(
            left: (g.map((m) => m.x).reduce((a, b) => a + b) / g.length -
                    I.md / 2)
                .clamp(gutter - I.md / 2, box.maxWidth - I.md),
            top: 0,
            child: g.length == 1
                ? Icon(g.first.icon, size: I.md, color: p.ink)
                : MarkCount(g.length, color: p.ink),
          ),
        Positioned(
          right: S.x3,
          bottom: S.x10,
          child: Pressable(
            onTap: () => setState(() {
              _zoom = !_zoom;
              _zoomOffset = null;
              _at = null;
            }),
            semanticLabel: _zoom ? 'Show the whole day' : 'Zoom to the last three hours',
            child: Container(
              width: S.x10,
              height: S.x10,
              decoration: BoxDecoration(color: C.char, borderRadius: R.rMd),
              child: Icon(_zoom ? LucideIcons.zoomOut : LucideIcons.zoomIn,
                  size: I.md, color: C.white),
            ),
          ),
        ),
      ]);
    });
  }

  // ── the day by level, against a typical one ──────────────────────────────
  Widget _totalDay(P p, StressMonitorData d, DateTime date, AppLocalizations? l) {
    final m = d.minutes;
    final t = d.typical;
    final bands = [
      (StressLevel.low, m.low, t?.low),
      (StressLevel.medium, m.medium, t?.medium),
      (StressLevel.high, m.high, t?.high),
    ];
    Widget bar(List<double> parts, {required double alpha}) {
      final total = parts.fold<double>(0, (a, b) => a + b);
      return SizedBox(
        height: S.x3,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < 3; i++)
            if (parts[i] > 0) ...[
              Expanded(
                flex: math.max(1, (parts[i] / total * 1000).round()),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: stressLevelColor(StressLevel.values[i]).withValues(alpha: alpha),
                    borderRadius: BorderRadius.circular(R.sm / 3),
                  ),
                ),
              ),
              const SizedBox(width: S.half),
            ],
        ]),
      );
    }

    String hm(int min) => durationText(min);

    return Container(
      padding: const EdgeInsets.all(S.x5),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.gauge, size: I.md, color: p.ink2),
          const SizedBox(width: S.x3),
          Text('TOTAL DAY',
              style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: S.x5),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: '${weekdayShortName(date.weekday, l)}, ${monthShortName(date.month, l)} ${date.day} STRESS '
                  .toUpperCase(),
              style: F.over.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          TextSpan(
              text: t == null ? '' : 'VS. TYPICAL DAY',
              style: F.over.copyWith(color: p.ink3, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(height: S.x3),
        if (m.low + m.medium + m.high > 0)
          bar([m.low.toDouble(), m.medium.toDouble(), m.high.toDouble()], alpha: 1),
        if (t != null) ...[
          const SizedBox(height: S.x2),
          bar([t.low, t.medium, t.high], alpha: .4),
        ],
        const SizedBox(height: S.x5),
        Row(children: [
          for (final (lvl, mins, typ) in bands)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hm(mins),
                    style: F.n24.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: S.x1),
                Text(_levelName(lvl),
                    style: F.over.copyWith(color: stressLevelColor(lvl), fontWeight: FontWeight.w700)),
                if (typ != null && typ > 0) ...[
                  const SizedBox(height: S.x2),
                  _VsTypical(today: mins.toDouble(), typical: typ),
                ],
              ]),
            ),
        ]),
        const SizedBox(height: S.x5),
        // Its trend: the share of each day at each level, week by week.
        Pressable(
          semanticLabel: 'See total day stress trends',
          onTap: () => go(context, const TrendViewScreen(initial: 'day_stress')),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('SEE TRENDS',
                style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
            const SizedBox(width: S.x2),
            Icon(LucideIcons.arrowRight, size: I.md, color: p.ink),
          ]),
        ),
      ]),
    );
  }

  void _info(BuildContext c, StressMonitorData? d) {
    final p = P.of(c);
    final b = d?.baseline;
    AppSheet.show<void>(
      c,
      title: 'How stress is measured',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'A reading from 0 (calm) to 3 (your highest) for every minute. It '
          'compares your heart rate and your HRV, in that minute, with what is '
          'usual for you: the last 14 days of quiet, awake minutes. Movement '
          'is taken into account so exercise is not read as stress. Under 1 is '
          'low, 1 to 2 medium, 2 and over high.',
          style: F.body.copyWith(color: p.ink2, height: 1.4),
        ),
        if (b != null) ...[
          const SizedBox(height: S.x4),
          Text(
            'Your baseline: heart rate ${b.hr.round()} bpm, from '
            '${b.days} days.'
            '${b.motionKnown ? '' : ' This strap gave no motion reading, so a '
                'hard workout can raise the score.'}',
            style: F.cap.copyWith(color: p.ink3, height: 1.4),
          ),
        ],
      ]),
    );
  }
}

/// Today's minutes at a level against a typical day's, as a percentage.
class _VsTypical extends StatelessWidget {
  final double today, typical;
  const _VsTypical({required this.today, required this.typical});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final pct = ((today - typical) / typical * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (pct != 0) ...[
          DeltaTriangle(up: pct > 0, color: p.ink2, size: S.x3),
          const SizedBox(width: S.x1),
        ],
        Text('${pct.abs()}%',
            style: F.cap.copyWith(color: p.ink2, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// The arc, its needle, and the reading in the middle.
class _Gauge extends StatelessWidget {
  final double? score;
  final String? time;
  final VoidCallback onInfo;
  const _Gauge({required this.score, required this.time, required this.onInfo});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final level = score == null ? null : stressLevel(score!);
    return LayoutBuilder(builder: (c, box) {
      // Smaller than the width it could take, so the chart under it has the
      // room. The height is the arc's own: its top, and its two ends.
      final w = math.min(box.maxWidth, S.x16 * 5.6) * .78;
      final h = w * _GaugePainter.heightFor;
      return Center(
        child: SizedBox(
          width: w,
          // Room under the arc's two ends for 0.0 and 3.0.
          height: h + S.x6,
          child: Stack(alignment: Alignment.center, children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: h,
              child: CustomPaint(
                painter: _GaugePainter(
                  value: score,
                  track: p.track,
                  needle: p.ink,
                ),
              ),
            ),
            Positioned(
              top: w * .2,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(score == null ? '--' : score!.toStringAsFixed(1),
                    style: F.n64.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
                if (level != null)
                  Text(_levelName(level),
                      style: F.caps.copyWith(
                          color: stressLevelColor(level), fontWeight: FontWeight.w700)),
                if (time != null) ...[
                  const SizedBox(height: S.x2),
                  Text(time!, style: F.cap.copyWith(color: p.ink2)),
                ],
              ]),
            ),
            Positioned(
              left: w * .02,
              bottom: 0,
              child: Text('0.0', style: F.n24.copyWith(color: p.ink3, fontWeight: FontWeight.w600)),
            ),
            Positioned(
              right: w * .02,
              bottom: 0,
              child: Text('3.0', style: F.n24.copyWith(color: p.ink3, fontWeight: FontWeight.w600)),
            ),
            // Under the middle, between the two ends of the arc: out of its way.
            Positioned(
              bottom: -S.x1,
              child: Pressable(
                onTap: onInfo,
                semanticLabel: 'How stress is measured',
                child: SizedBox(
                  width: S.tap,
                  height: S.tap,
                  child: Icon(LucideIcons.info, size: I.lg, color: p.ink2),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

class _GaugePainter extends CustomPainter {
  final double? value;
  final Color track, needle;
  _GaugePainter({required this.value, required this.track, required this.needle});

  // The arc runs from the lower left, over the top, to the lower right.
  static const _start = 146 * math.pi / 180;
  static const _sweep = 248 * math.pi / 180;

  static const _r = .44, _stroke = .035;

  /// Height over width that holds the whole arc: the top of the ring and its
  /// caps, down to the two ends (sin 146° of the radius under the centre).
  static final heightFor = _r + _stroke + _r * math.sin(_start) + _stroke;

  /// The gradient begins this far before the arc, so the round cap at its
  /// start reads the first colour. Begun exactly at the arc, the cap fell
  /// before the gradient and took the LAST colour: orange at the lower left.
  static const _lead = .2;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * _stroke;
    final r = size.width * _r;
    final c = Offset(size.width / 2, r + stroke);
    final rect = Rect.fromCircle(center: c, radius: r);

    // Blue → green → warm → orange, dimmer at both ends where the arc runs out.
    // Drawn from angle 0 and turned into place: the arc ends past a full turn
    // (146 + 248 degrees), and a sweep gradient does not run on through 360,
    // which left the lower right end without its colour.
    final shader = SweepGradient(
      startAngle: _lead,
      endAngle: _lead + _sweep,
      colors: [
        C.stressLow.withValues(alpha: .35),
        C.stressLow,
        C.stressMedium,
        C.stressMedium,
        C.stressWarm.withValues(alpha: .55),
        C.stressHigh.withValues(alpha: .55),
        C.stressHigh.withValues(alpha: .3),
      ],
      stops: const [0, .08, .3, .5, .72, .9, 1],
      transform: const GradientRotation(_start - _lead),
    ).createShader(rect);
    canvas.drawArc(
        rect,
        _start,
        _sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = shader);

    final v = value;
    if (v == null) return;
    // The needle: a white tick across the arc, and a soft wedge trailing in
    // toward the middle.
    final a = _start + _sweep * (v / 3).clamp(0.0, 1.0);
    Offset at(double radius) => c + Offset(math.cos(a), math.sin(a)) * radius;
    final wedge = Path()
      ..moveTo(at(r - stroke * 1.2).dx, at(r - stroke * 1.2).dy)
      ..lineTo(at(r * .62).dx + math.cos(a + math.pi / 2) * stroke * .5,
          at(r * .62).dy + math.sin(a + math.pi / 2) * stroke * .5)
      ..lineTo(at(r * .62).dx - math.cos(a + math.pi / 2) * stroke * .5,
          at(r * .62).dy - math.sin(a + math.pi / 2) * stroke * .5)
      ..close();
    canvas.drawPath(
      wedge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [needle.withValues(alpha: .4), needle.withValues(alpha: 0)],
        ).createShader(Rect.fromPoints(at(r - stroke), at(r * .62))),
    );
    canvas.drawLine(
        at(r - stroke * 1.1),
        at(r + stroke * 1.1),
        Paint()
          ..color = needle
          ..strokeWidth = stroke * .9
          ..strokeCap = StrokeCap.butt);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.track != track || old.needle != needle;
}

/// The 30 days up to the day shown: each day's mean score as a column in its
/// level's colour (low, medium, high), their average dashed behind them. A day with too little
/// scored is a gap. Today, still running, stays out of the average.
class StressTrendCard extends StatefulWidget {
  final StressSource? source;
  final String day, today;

  /// Each day's mean score, handed in by a test in place of [source].
  final Map<String, double>? data;
  const StressTrendCard({
    super.key,
    this.source,
    required this.day,
    required this.today,
    this.data,
  });

  static const days = 30;

  @override
  State<StressTrendCard> createState() => _StressTrendCardState();
}

class _StressTrendCardState extends State<StressTrendCard> {
  late final List<String> _days = [
    for (var i = StressTrendCard.days - 1; i >= 0; i--) shiftDay(widget.day, -i),
  ];
  late final Future<Map<String, double>> _avg = widget.data != null
      ? Future.value(widget.data!)
      : widget.source?.avgByDay(_days) ?? Future.value(const {});
  int? _at;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return FutureBuilder<Map<String, double>>(
      future: _avg,
      builder: (c, snap) {
        final byDay = snap.data;
        if (byDay == null || byDay.isEmpty) return const SizedBox.shrink();
        final values = [for (final d in _days) byDay[d]];
        final running = widget.day == widget.today && byDay[widget.today] != null;
        final counted = [
          for (final d in _days)
            if (!(running && d == widget.today)) ?byDay[d],
        ];
        final avg = counted.isEmpty
            ? null
            : counted.reduce((a, b) => a + b) / counted.length;
        final at = _at;
        final date = DateTime.parse(_days[at ?? 0]);
        final shown = at == null ? avg : values[at];
        final last = _days.length - 1;
        final today = DateTime.parse(widget.today);
        final squeeze = StressAxis.of([...counted, ...values.nonNulls]);
        return Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('30-DAY TREND',
                    style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              ),
              Pressable(
                onTap: () => _info(c),
                semanticLabel: 'About the 30-day trend',
                child: SizedBox(
                  width: S.tap,
                  height: S.tap,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Icon(LucideIcons.info, size: I.lg, color: p.ink2),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: S.x1),
            ScrubReadout(
              caption: at == null
                  ? 'Average'
                  : '${weekdayShortName(date.weekday, l)}, '
                      '${monthShortName(date.month, l)} ${date.day}',
              value: shown == null ? '--' : shown.toStringAsFixed(1),
            ),
            const SizedBox(height: S.x3),
            ScrubColumns(
              values: values,
              xLabels: [
                for (var i = 0; i <= last; i++)
                  (last - i) % 7 == 0
                      ? () {
                          final d = DateTime.parse(_days[i]);
                          return '${monthShortName(d.month, l)}\n${d.day}';
                        }()
                      : '',
              ],
              lo: 0,
              hi: 3,
              ticks: const [0, 1, 2, 3],
              tickText: (t) => t.toStringAsFixed(1),
              avg: avg,
              color: C.stressMedium,
              // One colour per level, as the gauge's legend has them: a
              // blend between stops made a calm day and a medium one two
              // shades of the same teal.
              colorOf: (_, v) => stressLevelColor(stressLevel(v)),
              fraction: squeeze.fraction,
              height: ScrubColumns.chrome +
                  (S.x16 * 3 + S.x10 - ScrubColumns.chrome) * squeeze.share,
              label: 'Average stress, last 30 days',
              describe: (i) {
                final d = DateTime.parse(_days[i]);
                return '${monthShortName(d.month, l)} ${d.day}: '
                    '${values[i] == null ? 'no reading' : values[i]!.toStringAsFixed(1)}';
              },
              onScrub: (i) => setState(() => _at = i),
            ),
            if (running) ...[
              const SizedBox(height: S.x2),
              Text(
                'Average does not include today '
                '(${monthShortName(today.month, l)} ${today.day})',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
          ]),
        );
      },
    );
  }

  void _info(BuildContext c) {
    final p = P.of(c);
    AppSheet.show<void>(
      c,
      title: '30-day trend',
      child: Text(
        'Each column is one day\'s average stress, 0 to 3, across the minutes '
        'it could be scored, in its level’s colour: blue low, green medium, '
        'orange high. A day needs six hours '
        'scored to be shown. The dashed line is the average of the days shown.',
        style: F.body.copyWith(color: p.ink2, height: 1.4),
      ),
    );
  }
}

/// The 30-day chart's stress axis, 0–3, with the levels no day reaches
/// squeezed: each whole level (0–1, 1–2, 2–3) the data never gets into
/// takes [squeezed] of a full one, so a calm month is a short chart.
class StressAxis {
  /// Per level, its share of a full level's height.
  final List<double> weights;
  const StressAxis(this.weights);

  static const double squeezed = .3;

  /// The axis for [values]: a level counts as used once a value is above its
  /// floor. The bottom level is always full.
  factory StressAxis.of(Iterable<double> values) {
    final top = values.fold<double>(0, math.max);
    return StressAxis(
        [for (var k = 0; k < 3; k++) k == 0 || top > k ? 1.0 : squeezed]);
  }

  /// The plot's height as a share of an even 0–3 axis.
  double get share => weights.fold<double>(0, (a, b) => a + b) / 3;

  /// Where [v] sits up the plot, 0 to 1.
  double fraction(double v) {
    var up = 0.0;
    for (var k = 0; k < weights.length; k++) {
      up += (v - k).clamp(0.0, 1.0) * weights[k];
    }
    return up / (share * 3);
  }
}
