// Energy reserve on Home: what is left today, and what charged and drained it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../compute/energy_reserve.dart';
import '../../../models/activity_suggestion.dart';
import '../../../state/clock_format.dart';
import '../../activity/catalogue.dart' show activityByName;
import '../../ui2.dart';

Color _tone(double level) => level >= 67
    ? C.recGreen
    : level >= 34
        ? C.recYellow
        : C.recRed;

/// The local midnight after [midnight] (epoch seconds), by the calendar, so a
/// clock-change day is as long as it really is.
int _nextMidnight(int midnight) {
  final d = DateTime.fromMillisecondsSinceEpoch(midnight * 1000);
  return DateTime(d.year, d.month, d.day + 1).millisecondsSinceEpoch ~/ 1000;
}

String _clockOf(int ts) =>
    formatClockOf(DateTime.fromMillisecondsSinceEpoch(ts * 1000));

/// Seconds either side of an activity that still count as inside it: the
/// effort the heart rate shows starts a little after the workout is started,
/// and runs on a little after it ends.
const int _kNameSlackSec = 5 * 60;

/// [events] each named after the activity it fell inside: a saved session
/// (started in Locus, or added later) first, then one the band found and has
/// not had named. Effort no activity explains keeps no name.
List<EnergyEvent> nameEnergyEvents(
  List<EnergyEvent> events,
  List<Map<String, dynamic>> sessions,
  List<ActivitySuggestion> detected,
) {
  String? origin(Map<String, dynamic> s) {
    final src = s['source']?.toString() ?? '';
    if (src == 'manual') return 'Added later';
    if (src.contains('auto') || src.contains('detect')) return 'Found by your band';
    return 'Started in Locus';
  }

  EnergyEvent named(EnergyEvent e) {
    for (final s in sessions) {
      final a = (s['start_ts'] as num?)?.toInt();
      final b = (s['end_ts'] as num?)?.toInt() ?? a;
      if (a == null || b == null) continue;
      if (e.ts >= a - _kNameSlackSec && e.ts <= b + _kNameSlackSec) {
        final act = activityByName(s['type']?.toString());
        return EnergyEvent(e.ts, e.delta,
            name: act?.name ?? s['title']?.toString() ?? 'Activity',
            origin: origin(s));
      }
    }
    for (final d in detected) {
      if (e.ts >= d.startTs - _kNameSlackSec &&
          e.ts <= d.endTs + _kNameSlackSec) {
        final act = activityByName(d.sport);
        return EnergyEvent(e.ts, e.delta,
            name: act == null ? 'Activity' : '${act.name}?',
            origin: 'Found by your band');
      }
    }
    return e;
  }

  return [for (final e in events) named(e)];
}

class EnergyReserveCard extends StatefulWidget {
  final EnergyReserve data;
  final int midnight;
  const EnergyReserveCard({
    super.key,
    required this.data,
    required this.midnight,
  });

  @override
  State<EnergyReserveCard> createState() => _EnergyReserveCardState();
}

class _EnergyReserveCardState extends State<EnergyReserveCard> {
  /// The second under the finger on the chart, or null at rest.
  int? _scrub;
  int _lastBucket = -1;

  EnergyReserve get data => widget.data;
  int get midnight => widget.midnight;

  /// The chart's left gutter, as the painter lays it.
  static const double _left = S.x8;

  /// The reserve at [t]: the line between the two readings around it.
  double _levelAt(int t) {
    final pts = data.points;
    if (t <= pts.first.$1) return pts.first.$2;
    for (var i = 1; i < pts.length; i++) {
      if (pts[i].$1 >= t) {
        final (t0, v0) = pts[i - 1];
        final (t1, v1) = pts[i];
        return t1 == t0 ? v1 : v0 + (v1 - v0) * (t - t0) / (t1 - t0);
      }
    }
    return pts.last.$2;
  }

  void _onScrub(double f, double width) {
    final plot = width - _left;
    if (plot <= 0 || data.points.length < 2) return;
    final day = _nextMidnight(midnight) - midnight;
    final x = (f * width - _left).clamp(0.0, plot);
    final t = (midnight + x / plot * day).round();
    // Held to where the line has been: nothing is read past the last reading.
    final clamped =
        t.clamp(data.points.first.$1, data.points.last.$1).toInt();
    final bucket = clamped ~/ 900;
    if (bucket != _lastBucket) {
      _lastBucket = bucket;
      HapticFeedback.selectionClick();
    }
    setState(() => _scrub = clamped);
  }

  /// The activity the scrubbed second falls inside, if any.
  EnergyEvent? _activityAt(int t) {
    for (final a in data.activities) {
      if ((a.ts - t).abs() <= 10 * 60) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final tone = _tone(data.level);
    // Today only: the card is drawn on today's Home and nowhere else.
    final projected = projectEnergy(data, _nextMidnight(midnight));
    Widget tile(String label, String value, Color colour) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: S.x3,
          vertical: S.x3,
        ),
        decoration: BoxDecoration(
          color: p.ink.withValues(alpha: .08),
          borderRadius: R.rLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: F.n24.copyWith(color: colour)),
            ),
          ],
        ),
      ),
    );
    return Surface(
      pad: const EdgeInsets.all(S.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ENERGY RESERVE',
                  style: F.caps.copyWith(color: p.ink),
                ),
              ),
              Pressable(
                semanticLabel: 'About energy reserve',
                onTap: () => showInfoSheet(
                  c,
                  'Energy reserve',
                  'An estimate of how much you have left today. Your '
                  'recovery sets the level you wake with, sleep charges it, '
                  'and raised heart rate drains it, effort most of all. '
                  'Time off the wrist changes nothing.\n\n'
                  'It is a guide built from your heart rate, not a '
                  'measurement.',
                  accent: infoAccent('energy'),
                ),
                child: Icon(LucideIcons.info, size: I.md, color: p.ink2),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Row(
            children: [
              Text(
                '${data.level.round()}%',
                style: F.n24.copyWith(color: p.ink),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, S.x5),
                  painter: _TicksPainter(
                    data.level,
                    tone,
                    p.ink.withValues(alpha: .14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x1),
          Text(
            'Woke at ${_clockOf(data.wokeTs)} with ${data.wokeLevel.round()}%',
            style: F.cap.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x3),
          // What the finger is on: the time and the reserve there, and the
          // activity if it falls in one. Holds its height at rest.
          SizedBox(
            height: S.x5,
            child: _scrub == null
                ? null
                : Builder(builder: (c) {
                    final t = _scrub!;
                    final at = _activityAt(t);
                    return Row(children: [
                      Text(_clockOf(t),
                          style: F.cap.copyWith(color: p.ink2)),
                      const SizedBox(width: S.x2),
                      Text('${_levelAt(t).round()}%',
                          style: F.n17.copyWith(color: _tone(_levelAt(t)))),
                      if (at?.name != null) ...[
                        const SizedBox(width: S.x3),
                        Flexible(
                          child: Text(at!.name!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: F.cap.copyWith(color: C.strainDown)),
                        ),
                      ],
                    ]);
                  }),
          ),
          LayoutBuilder(builder: (c, box) {
            final width = box.maxWidth;
            return Scrubber(
              value: _scrub == null
                  ? null
                  : (_left +
                          (_scrub! - midnight) /
                              (_nextMidnight(midnight) - midnight) *
                              (width - _left)) /
                      width,
              onChanged: (f) => _onScrub(f, width),
              onLift: () => setState(() {
                _scrub = null;
                _lastBucket = -1;
              }),
              yieldToScroll: true,
              label: 'Energy reserve through the day',
              describe: (f) {
                final plot = width - _left;
                final day = _nextMidnight(midnight) - midnight;
                final t = (midnight +
                        ((f * width - _left).clamp(0.0, plot)) / plot * day)
                    .round();
                return '${_clockOf(t)}, ${_levelAt(t).round()} percent';
              },
              child: CustomPaint(
                size: const Size(double.infinity, S.x16 * 1.6),
                painter: _ChartPainter(
                  data,
                  midnight,
                  projected: projected,
                  axis: p.ink3,
                  grid: p.ink.withValues(alpha: .1),
                  dotRing: p.bg,
                  scrub: _scrub,
                  scrubLevel: _scrub == null ? null : _levelAt(_scrub!),
                  guide: p.ink.withValues(alpha: .35),
                ),
              ),
            );
          }),
          if (projected != null) ...[
            const SizedBox(height: S.x2),
            Text(
              'Dotted: about ${projected.last.$2.round()}% by midnight if the '
              'rest of the day goes like today so far, without workouts',
              style: F.over.copyWith(color: p.ink3),
            ),
          ],
          const SizedBox(height: S.x4),
          Row(
            children: [
              tile('CHARGED', '+${data.charged}', C.recGreen),
              const SizedBox(width: S.x3),
              tile('DRAINED', '-${data.drained}', C.strainDown),
            ],
          ),
          if (data.activities.isNotEmpty) ...[
            const SizedBox(height: S.x3),
            _ActivitiesStrip(data.activities),
          ],
        ],
      ),
    );
  }
}

/// The activities that drained the day, tucked into one strip: its summary
/// shows, a tap opens the list downward.
class _ActivitiesStrip extends StatefulWidget {
  final List<EnergyEvent> events;
  const _ActivitiesStrip(this.events);

  @override
  State<_ActivitiesStrip> createState() => _ActivitiesStripState();
}

class _ActivitiesStripState extends State<_ActivitiesStrip> {
  bool _open = false;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ev = widget.events;
    final total = ev.fold<int>(0, (a, e) => a + e.delta);
    return Container(
      decoration: BoxDecoration(
        color: p.ink.withValues(alpha: .08),
        borderRadius: R.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            semanticLabel:
                _open ? 'Hide the activities' : 'Show the activities',
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: S.x3, vertical: S.x3),
              child: Row(children: [
                Expanded(
                  child: Text(
                    ev.length == 1 ? '1 ACTIVITY' : '${ev.length} ACTIVITIES',
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ),
                Text('$total', style: F.n17.copyWith(color: C.strainDown)),
                const SizedBox(width: S.x2),
                AnimatedRotation(
                  turns: _open ? .5 : 0,
                  duration: motion(c, Motion.base),
                  curve: Ease.standard,
                  child: Icon(LucideIcons.chevronDown, size: I.md, color: p.ink2),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: motion(c, Motion.base),
            curve: Ease.standard,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        S.x3, 0, S.x3, S.x3),
                    child: Column(children: [
                      for (final a in ev)
                        Padding(
                          padding: const EdgeInsets.only(top: S.x1),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.name ?? 'Raised heart rate',
                                        style: F.cap.copyWith(color: p.ink)),
                                    Text(
                                        a.origin == null
                                            ? _clockOf(a.ts)
                                            : '${_clockOf(a.ts)} · ${a.origin}',
                                        style: F.over.copyWith(color: p.ink3)),
                                  ]),
                            ),
                            Text('${a.delta}',
                                style: F.cap.copyWith(color: p.ink2)),
                          ]),
                        ),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  final double level;
  final Color on, off;
  const _TicksPainter(this.level, this.on, this.off);

  @override
  void paint(Canvas canvas, Size s) {
    const n = 46;
    final paint = Paint()
      ..strokeWidth = S.half
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final x = i / (n - 1) * s.width;
      paint.color = (i + .5) / n * 100 <= level ? on : off;
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), paint);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter o) =>
      o.level != level || o.on != on || o.off != off;
}

class _ChartPainter extends CustomPainter {
  final EnergyReserve d;
  final int midnight;
  final Color axis, grid, dotRing, guide;
  final List<(int, double)>? projected;

  /// The second under the finger and the reserve there; null at rest.
  final int? scrub;
  final double? scrubLevel;
  const _ChartPainter(
    this.d,
    this.midnight, {
    this.projected,
    this.scrub,
    this.scrubLevel,
    required this.axis,
    required this.grid,
    required this.dotRing,
    required this.guide,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = S.x8, bottom = S.x6;
    final h = size.height - bottom;
    final w = size.width - left;
    // The day's own length: 23 or 25 hours on a clock-change day.
    final day = _nextMidnight(midnight) - midnight;
    final start = DateTime.fromMillisecondsSinceEpoch(midnight * 1000);
    double x(int t) => left + (t - midnight) / day * w;
    double y(double v) => S.x1 + (h - S.x2) * (1 - v / 100);

    void label(String s, Offset at, {bool centre = false}) {
      final t = TextPainter(
        text: TextSpan(text: s, style: F.cap.copyWith(color: axis)),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(canvas, at - Offset(centre ? t.width / 2 : 0, t.height / 2));
      t.dispose();
    }

    final dash = Paint()
      ..color = grid
      ..strokeWidth = S.hair;
    for (final v in const [100, 67, 33]) {
      for (var a = left; a < size.width; a += S.x2) {
        canvas.drawLine(
          Offset(a, y(v.toDouble())),
          Offset(a + S.x1, y(v.toDouble())),
          dash,
        );
      }
      label('$v', Offset(0, y(v.toDouble())));
    }
    for (final hour in const [0, 6, 12, 18]) {
      label(
        formatAxisClock(hour * 60),
        Offset(
            x(DateTime(start.year, start.month, start.day, hour)
                        .millisecondsSinceEpoch ~/
                    1000) +
                (hour == 0 ? S.x4 : 0),
            h + S.x4),
        centre: true,
      );
    }

    final pts = d.points;
    if (pts.length < 2) return;
    final fill = Path()..moveTo(x(pts.first.$1), h);
    for (final (t, v) in pts) {
      fill.lineTo(x(t), y(v));
    }
    fill
      ..lineTo(x(pts.last.$1), h)
      ..close();
    final tone = _tone(d.level);
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tone.withValues(alpha: .28), tone.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    final line = Paint()
      ..strokeWidth = S.half
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < pts.length; i++) {
      line.color = _tone((pts[i - 1].$2 + pts[i].$2) / 2);
      canvas.drawLine(
        Offset(x(pts[i - 1].$1), y(pts[i - 1].$2)),
        Offset(x(pts[i].$1), y(pts[i].$2)),
        line,
      );
    }
    double levelAt(int t) {
      for (var i = 1; i < pts.length; i++) {
        if (pts[i].$1 >= t) return pts[i].$2;
      }
      return pts.last.$2;
    }

    for (final a in d.activities) {
      canvas.drawCircle(
        Offset(x(a.ts), y(levelAt(a.ts))),
        S.x1,
        Paint()..color = C.strainDown,
      );
    }
    // The projection, dotted as on the strain chart: round dots one stroke
    // wide, two strokes apart, the first a gap clear of the line's end.
    final pr = projected;
    if (pr != null && pr.length > 1) {
      final path = Path()..moveTo(x(pr.first.$1), y(pr.first.$2));
      for (final (t, v) in pr.skip(1)) {
        path.lineTo(x(t), y(v));
      }
      const gap = S.half * 2;
      final dot = Paint()..color = _tone(pr.last.$2);
      for (final m in path.computeMetrics()) {
        for (var a = gap; a <= m.length; a += gap) {
          final at = m.getTangentForOffset(a);
          if (at != null) canvas.drawCircle(at.position, S.half / 2, dot);
        }
      }
    }
    final end = Offset(x(pts.last.$1), y(pts.last.$2));
    canvas.drawCircle(end, S.x1 + S.half, Paint()..color = dotRing);
    canvas.drawCircle(end, S.x1, Paint()..color = tone);
    // The finger: a guide down the chart and a ringed dot on the line.
    final st = scrub, sl = scrubLevel;
    if (st != null && sl != null) {
      final gx = x(st);
      canvas.drawLine(
          Offset(gx, 0),
          Offset(gx, h),
          Paint()
            ..color = guide
            ..strokeWidth = S.hair);
      final dot = Offset(gx, y(sl));
      canvas.drawCircle(dot, S.x1 + S.half, Paint()..color = dotRing);
      canvas.drawCircle(dot, S.x1, Paint()..color = _tone(sl));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.d != d ||
      o.midnight != midnight ||
      o.projected != projected ||
      o.scrub != scrub;
}
