// STRESS MONITOR — a 0–3 reading for every minute of the day, from heart rate
// and HRV against your own last 14 days, with motion taken out (see
// `compute/stress_monitor.dart` for the arithmetic).
//
// The gauge reads the end of the day, or the minute under your finger. The
// chart is the day: sleep shaded, workouts marked, the line coloured by how
// high it is. Under it, how long the day spent at each level against a typical
// one. When there is no baseline yet the screen says so; it does not guess.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../compute/stress_monitor.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../activity/catalogue.dart' show activityByName;
import '../ui2.dart';
import 'home_screen.dart' show monthShortName, pad, repoOf, weekdayShortName;
import 'trend_view.dart' show shiftDay;

/// The colour of a score: blue when calm, through green and a warm yellow, to
/// orange at the top of the scale.
Color stressColor(double score) {
  const stops = [C.stressLow, C.stressMedium, C.stressWarm, C.stressHigh];
  final t = score.clamp(0.0, 3.0);
  final i = math.min(2, t.floor());
  return Color.lerp(stops[i], stops[i + 1], t - i)!;
}

Color _levelColor(StressLevel l) => switch (l) {
      StressLevel.low => C.stressLow,
      StressLevel.medium => C.stressMedium,
      StressLevel.high => C.stressHigh,
    };

String _levelName(StressLevel l) => switch (l) {
      StressLevel.low => 'LOW',
      StressLevel.medium => 'MEDIUM',
      StressLevel.high => 'HIGH',
    };

String _clock(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

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

  const StressMonitorData({
    required this.day,
    required this.scores,
    required this.baseline,
    this.sleep = const [],
    this.sessions = const [],
    this.minutes = (low: 0, medium: 0, high: 0),
    this.typical,
  });

  /// The last minute that has a score: where the day "is" for the gauge.
  int? get last {
    for (var i = scores.length - 1; i >= 0; i--) {
      if (scores[i] != null) return i;
    }
    return null;
  }
}

/// Reads and scores days, keeping each day's series so paging back and forth
/// does not decode the same bundle twice.
class StressSource {
  final LocalRepository repo;
  StressSource(this.repo);

  final _inputs = <String, Future<StressDayInput?>>{};

  Future<StressDayInput?> _input(String day) => _inputs[day] ??= () async {
        try {
          final t = await repo.getDayTimeline(day);
          // A bundle served in place of the day asked for is not that day.
          if (t['date'] != day) return null;
          return StressDayInput.fromTimeline(day, t);
        } catch (_) {
          return null;
        }
      }();

  Future<StressMonitorData> load(String day) async {
    final fetched = await Future.wait([
      _input(day),
      for (var i = 1; i <= 14; i++) _input(shiftDay(day, -i)),
    ]);
    final today = fetched.first;
    final prior = [for (final d in fetched.skip(1)) ?d];
    final baseline = stressBaseline(prior);
    if (today == null || baseline == null) {
      return StressMonitorData(day: day, scores: List.filled(1440, null), baseline: baseline);
    }
    final scores = stressScores(today, baseline);

    // How a typical day splits, from the days before, on the same baseline.
    final spent = [
      for (final d in prior)
        if (stressScores(d, baseline).where((s) => s != null).length >= 360)
          stressMinutes(stressScores(d, baseline)),
    ];
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
      final on = i < 1440 && today.asleep[i];
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
  const StressMonitorScreen({super.key, this.source, this.today});

  @override
  State<StressMonitorScreen> createState() => _StressMonitorScreenState();
}

class _StressMonitorScreenState extends State<StressMonitorScreen> {
  StressSource? _source;
  late String _day = widget.today ?? todayLabel();
  StressMonitorData? _data;
  String? _loaded;
  bool _zoom = false;

  /// The minute under a finger, or null at rest.
  int? _at;

  String get _today => widget.today ?? todayLabel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
    final d = await _source!.load(day);
    if (!mounted || day != _day) return;
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
            time: shown == null ? null : _clock(shown),
            onInfo: () => _info(c, d),
          ),
          const SizedBox(height: S.x6),
          if (loading)
            const SizedBox(
                height: S.x16 * 3, child: Center(child: CircularProgressIndicator()))
          else if (d == null)
            const StatusCard('No data', 'Nothing is stored for this day yet.',
                fix: '', icon: LucideIcons.brain)
          else if (d.baseline == null)
            const StatusCard(
              'Building your baseline',
              'Stress is read against your own last 14 days, so it needs at '
                  'least three of them with quiet, awake heart rate and HRV. '
                  'Wear the band through a few more days and it will appear.',
              fix: '',
              icon: LucideIcons.brain,
            )
          else if (last == null)
            const StatusCard('No heart rate on this day',
                'The band recorded no heart rate, so there is nothing to score.',
                fix: '', icon: LucideIcons.heartOff)
          else ...[
            _chart(p, d, last),
            const SizedBox(height: S.x8),
            _totalDay(p, d, date, l),
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

  // ── the chart ────────────────────────────────────────────────────────────
  Widget _chart(P p, StressMonitorData d, int last) {
    final from = _zoom ? math.max(0, last - 180) : 0;
    final n = last - from + 1;
    final values = d.scores.sublist(from, last + 1);
    final labelMinutes = <int>{
      if (!_zoom) ...[0, 360, 720, 1080].where((m) => last - m > 100),
      if (_zoom) ...[for (var m = (from ~/ 60 + 1) * 60; m < last - 20; m += 60) m],
    };
    final xLabels = [
      for (var i = 0; i < n; i++)
        i == n - 1
            ? _clock(last)
            : labelMinutes.contains(from + i)
                ? _clock(from + i)
                : '',
    ];
    const gutter = S.x10;
    final line = ScrubLine(
      values: values,
      xLabels: xLabels,
      // A little under zero, so a calm minute sits just off the floor of the
      // chart rather than on it.
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
      highlight: n - 1,
      height: S.x16 * 3 + S.x10,
      gutter: gutter,
      label: 'Stress through the day',
      describe: (i) => '${_clock(from + i)}: '
          '${values[i] == null ? 'no reading' : values[i]!.toStringAsFixed(1)}',
      onScrub: (i) => setState(() => _at = i == null ? null : from + i),
      paintUnder: (canvas, plot, xOf, yOf) {
        // Sleep: a soft block with a bar along its top.
        for (final (a, b) in d.sleep) {
          final x1 = xOf(math.max(a, from) - from), x2 = xOf(math.min(b, last) - from);
          if (b <= from || a > last || x2 <= x1) continue;
          canvas.drawRect(Rect.fromLTRB(x1, plot.top, x2, plot.bottom),
              Paint()..color = p.ink.withValues(alpha: .05));
          canvas.drawLine(Offset(x1, plot.top), Offset(x2, plot.top),
              Paint()..color = C.stressLow..strokeWidth = 2);
        }
        // Workouts: a faint span, marked above in blue.
        for (final s in d.sessions) {
          if (s.to < from || s.from > last) continue;
          final x1 = xOf(math.max(s.from, from) - from), x2 = xOf(math.min(s.to, last) - from);
          canvas.drawRect(Rect.fromLTRB(x1, plot.top, math.max(x2, x1 + 2), plot.bottom),
              Paint()..color = C.dialStrain.withValues(alpha: .10));
          canvas.drawLine(Offset(x1, plot.top - 3), Offset(math.max(x2, x1 + 2), plot.top - 3),
              Paint()..color = C.dialStrain..strokeWidth = 3);
        }
      },
      paintOver: (canvas, plot, xOf, yOf) {
        // Where the day is now: a dashed line down to a dot on the reading.
        final x = xOf(n - 1);
        final dash = Paint()
          ..color = p.ink
          ..strokeWidth = 1.5;
        for (var y = plot.top; y < plot.bottom; y += S.x2) {
          canvas.drawLine(Offset(x, y), Offset(x, math.min(y + S.x1, plot.bottom)), dash);
        }
        final v = values[n - 1];
        if (v != null) canvas.drawCircle(Offset(x, yOf(v)), S.x1, Paint()..color = p.ink);
      },
    );

    return LayoutBuilder(builder: (c, box) {
      final plotW = box.maxWidth - gutter - S.x2;
      double xAt(int minute) => gutter + (minute - from) / math.max(1, n - 1) * plotW;
      // What each marked stretch was, over the middle of it: a moon for
      // sleep, the activity's own icon for a workout. Marks that would sit on
      // top of each other become one ring with how many there are; zooming
      // in spreads them apart again.
      final marks = [
        for (final (a, b, icon) in [
          for (final (a, b) in d.sleep) (a, b, LucideIcons.moon),
          for (final s in d.sessions)
            (s.from, s.to, activityByName(s.type)?.icon ?? LucideIcons.activity),
        ])
          if (b > from && a <= last)
            (
              x: (xAt(math.max(a, from)) + xAt(math.min(b, last))) / 2,
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
                    color: _levelColor(StressLevel.values[i]).withValues(alpha: alpha),
                    borderRadius: BorderRadius.circular(R.sm / 3),
                  ),
                ),
              ),
              const SizedBox(width: S.half),
            ],
        ]),
      );
    }

    String hm(int min) => '${min ~/ 60}:${(min % 60).toString().padLeft(2, '0')}';

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
                    style: F.over.copyWith(color: _levelColor(lvl), fontWeight: FontWeight.w700)),
                if (typ != null && typ > 0) ...[
                  const SizedBox(height: S.x2),
                  _VsTypical(today: mins.toDouble(), typical: typ),
                ],
              ]),
            ),
        ]),
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
                          color: _levelColor(level), fontWeight: FontWeight.w700)),
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
