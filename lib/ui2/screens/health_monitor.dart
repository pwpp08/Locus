// HEALTH MONITOR — the live heart rate as a line through a disc, then the four
// overnight vitals, each against your own usual range.
//
// Every tile has three states and only three: a value inside your range, a
// value far out on the harmful side (WHOOP's rule, whoopMonitorReading), and
// "No data". A dash is the absence —
// the overnight block is refused when it is a held-over night rather than
// today's ([overnightMetric]), so a tile never shows last week's reading as
// this morning's.
//
// The disc holds the live beat while the band streams. Without one it holds
// the last heart rate the day actually recorded, labelled with its time, or a
// dash — never a guess — and then the line lies flat and the disc is still.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../compute/whoop_scores.dart' show whoopMonitorReading;
import '../../data/day_label.dart';
import '../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'metric_detail.dart';
import 'start_activity.dart' show HeartPainter;
import 'trend_view.dart'
    show TrendViewScreen, kSkinTempTrend, trendMetricOf;

typedef _Range = ({double lo, double hi, bool flagged});

/// One vital's reading and where it sits against the usual range.
class _Vital {
  final String key, label, value, unit;
  final IconData icon;

  /// Null: no reading. Otherwise inside / above / below the usual range, or
  /// null [side] when there is a reading but no range to hold it against yet.
  final bool present;
  final Side? side;

  /// The usual range the verdict was read against, and the reading in the
  /// range's own units ([raw]) with how many places it is written to.
  final _Range? range;
  final double? raw;
  final int places;

  /// The range's unit when it is not the shown value's (skin temperature is
  /// shown in °C but ranged in SD).
  final String rangeUnit;

  const _Vital(this.key, this.label, this.icon,
      {this.value = '',
      this.unit = '',
      this.present = false,
      this.side,
      this.range,
      this.raw,
      this.places = 0,
      this.rangeUnit = ''});
}

class _MonitorData {
  final List<_Vital> vitals;
  const _MonitorData({this.vitals = const []});

  static Future<_MonitorData> load(BuildContext c) async {
    final repo = repoOf(c);
    if (repo == null) return const _MonitorData();
    final today = await repo.getToday();
    // WHOOP's Health Monitor: only a reading far out on the harmful side is
    // flagged (whoopMonitorReading); just outside the middle half stays green.
    Future<_Range?> rangeOf(String key, double? v, {required bool harmfulUp}) async {
      if (v == null) return null;
      final stored = seriesOf(await repo.getChart(key));
      if (stored.isEmpty) return null;
      return whoopMonitorReading(v, stored.sublist(0, stored.length - 1),
          harmfulUp: harmfulUp);
    }

    Side? sideOf(_Range? r, {required bool harmfulUp}) => r == null
        ? null
        : !r.flagged
            ? Side.inside
            : (harmfulUp ? Side.above : Side.below);

    final daily = today['daily'];
    Metric overnight(Object? raw) => overnightMetric(today, raw);

    final rhr = overnight(daily is Map ? daily['resting_hr'] : null).value;
    final hrvBlock = today['hrv'];
    final hrv = overnightMetric(
            today, hrvBlock is Map ? {...hrvBlock, 'value': hrvBlock['rmssd']} : null)
        .value;
    final resp = overnight(today['resp']).value;
    final skinRaw = today['skin_temp'];
    final skinZ = overnight(skinRaw).value;
    final skinC = skinZ == null
        ? null
        : ((skinRaw is Map ? skinRaw['dev_c'] : null) as num?)?.toDouble();

    String signed(double v, int places) =>
        '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(places)}';

    final respR = await rangeOf('resp_rate', resp?.toDouble(), harmfulUp: true);
    final rhrR = await rangeOf('resting_hr', rhr?.toDouble(), harmfulUp: true);
    final hrvR = await rangeOf('hrv', hrv?.toDouble(), harmfulUp: false);
    final skinR = await rangeOf('skin_temp', skinZ?.toDouble(), harmfulUp: true);

    return _MonitorData(
      vitals: [
        _Vital('resp_rate', 'Respiratory Rate', LucideIcons.wind,
            present: resp != null,
            value: resp == null ? '' : resp.toStringAsFixed(1),
            unit: 'rpm',
            side: sideOf(respR, harmfulUp: true),
            range: respR,
            raw: resp?.toDouble(),
            places: 1),
        _Vital('resting_hr', 'RHR', LucideIcons.heartPulse,
            present: rhr != null,
            value: rhr == null ? '' : '${rhr.round()}',
            unit: 'bpm',
            side: sideOf(rhrR, harmfulUp: true),
            range: rhrR,
            raw: rhr?.toDouble()),
        _Vital('hrv', 'HRV', LucideIcons.activity,
            present: hrv != null,
            value: hrv == null ? '' : '${hrv.round()}',
            unit: 'ms',
            side: sideOf(hrvR, harmfulUp: false),
            range: hrvR,
            raw: hrv?.toDouble()),
        _Vital('skin_temp', 'Skin Temp (from baseline)', LucideIcons.thermometer,
            present: skinZ != null,
            value: skinZ == null
                ? ''
                : skinC != null
                    ? signed(skinC, 1)
                    : signed(skinZ.toDouble(), 2),
            unit: skinC != null ? '°C' : 'SD',
            side: sideOf(skinR, harmfulUp: true),
            range: skinR,
            raw: skinZ?.toDouble(),
            places: 1,
            rangeUnit: skinC != null ? ' SD' : ''),
      ],
    );
  }
}

/// What Home's card says: how many of the vitals that have a reading and a
/// usual range sit inside it.
typedef HealthGlance = ({int inside, int total});

/// Reads the vitals once for Home's card. Null when none has both a reading and
/// a range to hold it against: the card says there is no data, never "5/5".
Future<HealthGlance?> healthGlanceOf(BuildContext c) async {
  final d = await _MonitorData.load(c);
  final held = [for (final v in d.vitals) if (v.present && v.side != null) v];
  if (held.isEmpty) return null;
  return (
    inside: held.where((v) => v.side == Side.inside).length,
    total: held.length,
  );
}

/// The newest heart rate the day recorded, and when (epoch seconds). Null
/// when the day holds none.
typedef _Recorded = ({int bpm, int at});

Future<_Recorded?> _lastRecorded(BuildContext c) async {
  final repo = repoOf(c);
  if (repo == null) return null;
  final hr = (await repo.getDayHeart(todayLabel()))['hr'];
  if (hr is! List) return null;
  for (final e in hr.reversed) {
    if (e is Map && e['t'] is num && e['v'] is num && (e['v'] as num) > 0) {
      return (bpm: (e['v'] as num).round(), at: (e['t'] as num).toInt());
    }
  }
  return null;
}

// The page's measured geometry, in dp from the top of the safe area.
const double _barH = S.x10;
const double _heroH = 186;
const double _discY = 111;
const double _lineY = 118.5;
const double _disc = 110;
const double _cardH = 144;
const double _cardPad = S.x4 - S.hair;

class HealthMonitorScreen extends StatefulWidget {
  const HealthMonitorScreen({super.key});

  @override
  State<HealthMonitorScreen> createState() => _HealthMonitorScreenState();
}

class _HealthMonitorScreenState extends State<HealthMonitorScreen> {
  AppState? _liveHrOwner;
  _MonitorData? _d;
  _Recorded? _recorded;

  @override
  void initState() {
    super.initState();
    // This screen owns the realtime-HR stream while it is open.
    try {
      _liveHrOwner = context.read<AppState>()..retainLiveHrView();
    } catch (_) {
      // No AppState (goldens): no stream to own.
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final d = await _MonitorData.load(context).catchError((_) => const _MonitorData());
      if (!mounted) return;
      setState(() => _d = d);
      final r = await _lastRecorded(context).catchError((_) => null);
      if (mounted && r != null) setState(() => _recorded = r);
    });
  }

  @override
  void dispose() {
    _liveHrOwner?.releaseLiveHrView();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    // No repository (goldens) loads no vitals: the four tiles still stand,
    // each saying it has no data.
    final loaded = _d?.vitals ?? const [];
    final vitals = loaded.isNotEmpty
        ? loaded
        : const [
          _Vital('resp_rate', 'Respiratory Rate', LucideIcons.wind),
          _Vital('resting_hr', 'RHR', LucideIcons.heartPulse),
          _Vital('hrv', 'HRV', LucideIcons.activity),
          _Vital('skin_temp', 'Skin Temp (from baseline)', LucideIcons.thermometer),
        ];
    return AlwaysChar(
      child: Scaffold(
        backgroundColor: HM.bgFoot,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, .33, .6, 1],
              colors: [HM.bgTop, HM.bgMid, HM.bgLow, HM.bgFoot],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.only(bottom: S.x16),
              children: [
                const _Bar(),
                _Hero(recorded: _recorded),
                const _Kicker(),
                const SizedBox(height: S.x3 + S.half),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Column(children: [
                    for (var i = 0; i < vitals.length; i += 2) ...[
                      if (i > 0) const SizedBox(height: S.x3),
                      IntrinsicHeight(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _VitalTile(vitals[i])),
                              const SizedBox(width: S.x3),
                              Expanded(
                                  child: i + 1 < vitals.length
                                      ? _VitalTile(vitals[i + 1])
                                      : const SizedBox.shrink()),
                            ]),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The close × and the title, centred in tracked capitals.
class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext c) {
    return SizedBox(
      height: _barH,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(
          left: S.x4,
          child: Pressable(
            onTap: () => Navigator.of(c).maybePop(),
            semanticLabel: 'Close',
            child: const Icon(LucideIcons.x, size: I.xl, color: DC.pure),
          ),
        ),
        Text('HEALTH MONITOR', style: HM.title.copyWith(color: DC.pure)),
      ]),
    );
  }
}

/// The beat's clock: how far through the current beat the disc is, and how far
/// the line has slid since the newest reading. One ticker feeds it; the
/// painter listens, so a frame repaints the hero and nothing else.
class _Clock extends ChangeNotifier {
  double beat = 0, slide = 0;
  void set(double b, double s) {
    beat = b;
    slide = s;
    notifyListeners();
  }
}

/// The line, the disc and the number in it.
class _Hero extends StatefulWidget {
  final _Recorded? recorded;
  const _Hero({this.recorded});

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _clock = _Clock();
  Duration _last = Duration.zero, _sampleAt = Duration.zero;
  double _beat = 0;
  int? _bpm, _rev;

  void _tick(Duration now) {
    final bpm = _bpm ?? 0;
    final dt = (now - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = now;
    _beat = (_beat + dt * bpm / 60) % 1;
    final slide =
        ((now - _sampleAt).inMicroseconds / Motion.tick.inMicroseconds).clamp(0.0, 1.0);
    _clock.set(_beat, slide);
  }

  /// Runs only while there is a live beat AND motion is allowed.
  void _run(bool on) {
    if (on && !_ticker.isActive) {
      _last = _sampleAt = Duration.zero;
      _ticker.start();
    } else if (!on && _ticker.isActive) {
      _ticker.stop();
      _clock.set(0, 0);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    int? hr;
    var paired = false, connected = false;
    var trace = const <int>[];
    try {
      hr = c.select<AppState, int?>((a) => a.liveHr);
      paired = c.select<AppState, bool>((a) => a.isPaired);
      connected = c.select<AppState, bool>((a) => a.isConnected);
      final rev = c.select<AppState, int>((a) => a.liveHrTraceRev);
      if (hr != null) trace = c.read<AppState>().liveHrTrace();
      if (rev != _rev) {
        _rev = rev;
        _sampleAt = _last;
      }
    } catch (_) {
      // No AppState (goldens): the disconnected state.
    }
    _bpm = hr;
    final moving = hr != null && Motion.enabled(c);
    _run(moving);

    final rec = widget.recorded;
    final shown = hr ?? rec?.bpm;
    final String note;
    if (hr != null) {
      note = '';
    } else if (rec != null) {
      final at = DateTime.fromMillisecondsSinceEpoch(rec.at * 1000);
      final day = dayLabelOf(at) == todayLabel()
          ? ''
          : '${weekdayShortName(at.weekday, null)} ';
      note = 'Last recorded $day${formatMinuteOfDay(at.hour * 60 + at.minute)}';
    } else {
      note = !paired
          ? 'No Device Paired'
          : !connected
              ? 'Device Disconnected'
              : 'Waiting for a reading';
    }

    return SizedBox(
      height: _heroH,
      child: Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _HeroPaint(
                trace: hr == null ? const [] : trace,
                clock: _clock,
                live: moving,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: _discY - HM.hr.fontSize! / 2,
          child: Semantics(
            label: shown == null
                ? 'Heart rate: no reading. $note'
                : 'Heart rate $shown beats per minute. $note',
            excludeSemantics: true,
            child: Column(children: [
              Text(shown == null ? '--' : '$shown',
                  style: HM.hr.copyWith(color: DC.pure)),
              const SizedBox(height: S.half),
              Text('BPM', style: HM.caps.copyWith(color: HM.bpm)),
            ]),
          ),
        ),
        if (note.isNotEmpty)
          Positioned(
            left: S.x4,
            right: S.x4,
            top: _discY + _disc / 2 + S.x1,
            child: Text(note,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.over.copyWith(color: DC.ink3, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

/// The glow under the line, the line (the live trace, or flat), and the
/// disc with its heart, swelling on each beat.
class _HeroPaint extends CustomPainter {
  final List<int> trace;
  final _Clock clock;
  final bool live;
  _HeroPaint({required this.trace, required this.clock, required this.live})
      : super(repaint: clock);

  /// Readings across the full width, and the most a reading moves the line.
  static const _slots = 40;
  static const _reach = S.x2 + S.half;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.clipRect(Offset.zero & size);
    final glow = Rect.fromLTWH(0, _lineY, w, S.x16);
    canvas.drawRect(
        glow,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, .55, 1],
            colors: [HM.glow, HM.glow, Color(0x00000000)],
          ).createShader(glow));

    final line = Paint()
      ..color = HM.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = S.hair + S.hair / 2
      ..strokeCap = StrokeCap.round;
    if (trace.length < 2) {
      canvas.drawLine(Offset(0, _lineY), Offset(w, _lineY), line);
    } else {
      final t = trace.length > _slots + 1
          ? trace.sublist(trace.length - _slots - 1)
          : trace;
      final mean = t.reduce((a, b) => a + b) / t.length;
      final step = w / _slots;
      final n = t.length;
      final pts = [
        for (var i = 0; i < n; i++)
          Offset(w - (n - 1 - i + (live ? clock.slide : 0)) * step,
              _lineY - ((t[i] - mean) * .8).clamp(-_reach, _reach)),
      ];
      final path = Path()
        ..moveTo(0, _lineY)
        ..lineTo(math.max(0, pts.first.dx - step), _lineY);
      var prev = Offset(math.max(0, pts.first.dx - step), _lineY);
      for (final p in pts) {
        final mid = Offset((prev.dx + p.dx) / 2, (prev.dy + p.dy) / 2);
        path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
        prev = p;
      }
      path.lineTo(prev.dx, prev.dy);
      if (prev.dx < w) path.lineTo(w, prev.dy);
      canvas.drawPath(path, line);
    }

    // A beat swells fast and settles: half the beat out, half back.
    final e = live ? .5 - .5 * math.cos(clock.beat * 2 * math.pi) : 0.0;
    final c = Offset(w / 2, _discY);
    if (live) {
      canvas.drawCircle(
          c,
          _disc / 2 * (1 + .38 * e),
          Paint()
            ..color = HM.line.withValues(alpha: .16 * (1 - e))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, S.x1));
    }
    canvas.drawCircle(
        c,
        _disc / 2 + S.x1,
        Paint()
          ..color = HM.discShade
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, S.x1 + S.half));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1 + .035 * e);
    canvas.drawCircle(Offset.zero, _disc / 2, Paint()..color = HM.disc);
    const heart = S.x4 + S.x1 - S.hair;
    canvas.translate(-heart / 2, -_disc / 2 + S.x4);
    HeartPainter(HM.heart).paint(canvas, const Size.square(heart));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeroPaint old) =>
      !identical(old.trace, trace) || old.live != live || old.clock != clock;
}

/// LAST NIGHT'S READINGS, and the (?) that says what the ranges are.
class _Kicker extends StatelessWidget {
  const _Kicker();

  @override
  Widget build(BuildContext c) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const SizedBox(width: S.x3 - S.hair),
      Text("LAST NIGHT'S READINGS", style: HM.kicker.copyWith(color: DC.pure)),
      Pressable(
        onTap: () => AppSheet.show<void>(c,
            title: 'Health Monitor',
            child: Text(
                'Each reading is last night\'s, held against your own usual '
                'range: the middle half of your last 30 nights. A reading a '
                'little outside it stays green; only one far out on the '
                'harmful side is marked. A range needs 14 nights first.',
                style: F.dBody.copyWith(color: P.of(c).ink2))),
        semanticLabel: 'About these readings',
        child: const Icon(LucideIcons.circleHelp,
            size: I.md, color: DC.ink3),
      ),
    ]);
  }
}

class _VitalTile extends StatelessWidget {
  final _Vital v;
  const _VitalTile(this.v);

  String _n(double x) =>
      '${x < 0 ? '−' : ''}${x.abs().toStringAsFixed(v.places)}';

  @override
  Widget build(BuildContext c) {
    final r = v.range, raw = v.raw;
    final (String word, Color ink, Color chip, bool check) = !v.present
        ? ('No data', DC.ink3, HM.noneChip, false)
        : r == null || raw == null
            ? ('No baseline', DC.ink3, HM.noneChip, false)
            : (
                raw > r.hi
                    ? 'elevated > ${_n(r.hi)}${v.rangeUnit}'
                    : raw < r.lo
                        ? 'low < ${_n(r.lo)}${v.rangeUnit}'
                        : 'within ${_n(r.lo)} - ${_n(r.hi)}${v.rangeUnit}',
                r.flagged ? C.poor : C.optimal,
                r.flagged ? DC.hurtChip : DC.helpChip,
                !r.flagged,
              );
    return Pressable(
      // The chart Home's dashboard row opens for the same metric; skin
      // temperature has a trend of its own that only this tile opens.
      onTap: () => go(
          c,
          trendMetricOf(v.key) != null || v.key == kSkinTempTrend.id
              ? TrendViewScreen(initial: v.key)
              : MetricDetail(v.key)),
      semanticLabel: '${v.label}. ${v.present ? '${v.value} ${v.unit}. ' : ''}$word',
      child: Container(
        constraints: const BoxConstraints(minHeight: _cardH),
        padding: const EdgeInsets.all(_cardPad),
        decoration: BoxDecoration(
          color: HM.card,
          borderRadius: R.rSm,
          border: Border.all(color: HM.edge, width: S.hair),
          boxShadow: const [
            BoxShadow(color: HM.rim, blurRadius: S.half, spreadRadius: S.hair / 2),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(v.icon, size: I.lg, color: HM.label),
                const SizedBox(width: S.x3 - S.hair),
                Expanded(
                    child: Text(v.label.toUpperCase(),
                        style: HM.name.copyWith(color: HM.label))),
              ]),
              const SizedBox(height: S.x3 + S.half),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(v.present ? v.value : '--',
                          style: HM.value.copyWith(color: DC.pure)),
                    ),
                  ),
                  if (v.present && v.unit.isNotEmpty) ...[
                    const SizedBox(width: S.hair),
                    Text(v.unit, style: HM.unit.copyWith(color: DC.pure)),
                  ],
                ],
              ),
            ]),
            const SizedBox(height: S.x4),
            Container(
              height: S.x5 + S.half,
              padding: const EdgeInsets.symmetric(horizontal: S.x2),
              decoration: BoxDecoration(
                  color: chip,
                  borderRadius: const BorderRadius.all(Radius.circular(S.half))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (check) ...[
                  Icon(LucideIcons.check, size: I.sm - S.x1, color: ink),
                  const SizedBox(width: S.x1 + S.hair),
                ],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(word,
                        maxLines: 1, style: HM.verdict.copyWith(color: ink)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
