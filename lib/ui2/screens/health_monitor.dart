// HEALTH MONITOR — the heart rate over a faint grid, then the four overnight
// vitals in a two-column grid, each against your own usual range, then a card
// that shares them as text.
//
// Every tile has three states and only three: a value inside your range, a
// value far out on the harmful side (WHOOP's rule, whoopMonitorReading), and
// "No data". A dash is the absence — the overnight block is refused when it
// is a held-over night rather than today's ([overnightMetric]), so a tile never
// shows last week's reading as this morning's.
//
// No blood oxygen tile: none of the bands Locus pairs with serves one (the
// WHOOP SpO2 byte is recorded for research only), so it could only ever say
// "No data".
//
// The number is the live beat while the band streams, and the heart beats
// with it. Without one it is the last heart rate the day actually recorded,
// labelled with its time, or a dash — never a guess — and the line lies flat.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../compute/whoop_scores.dart'
    show kWhoopMonitorMinNights, whoopMonitorReading;
import '../../data/day_label.dart';
import '../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'calibration.dart' show CalibrationStrip, Milestone;
import 'home_screen.dart';
import 'metric_detail.dart';
import 'trend_view.dart'
    show TrendViewScreen, kSkinTempTrend, trendMetricOf;

typedef _Range = ({double lo, double hi, bool flagged});

/// One vital's reading and where it sits against the usual range.
class _Vital {
  final String key, label, value, unit;
  final Widget Function(Color) icon;

  /// Null: no reading. Otherwise inside / above / below the usual range, or
  /// null [side] when there is a reading but no range to hold it against yet.
  final bool present;
  final Side? side;

  /// The usual range the verdict was read against, and the reading in the
  /// range's own units ([raw]) with how many places it is written to.
  final _Range? range;
  final double? raw;
  final int places;

  /// The range is held in another unit than the value is shown in (skin
  /// temperature shown in °C, ranged in SD): the pill names the verdict and
  /// writes no numbers, rather than numbers in a unit the tile never shows.
  final bool rangeElsewhere;

  /// A signed range, written "−0.6 to +0.7".
  final bool signed;

  const _Vital(this.key, this.label, this.icon,
      {this.value = '',
      this.unit = '',
      this.present = false,
      this.side,
      this.range,
      this.raw,
      this.places = 0,
      this.rangeElsewhere = false,
      this.signed = false});

  /// The pill's words.
  String get verdict {
    final r = range, x = raw;
    if (!present) return 'No data';
    if (r == null || x == null) return 'No baseline';
    String n(double v) =>
        '${signed ? (v < 0 ? '−' : '+') : (v < 0 ? '−' : '')}'
        '${v.abs().toStringAsFixed(places)}';
    if (rangeElsewhere) {
      return x > r.hi ? 'elevated' : x < r.lo ? 'low' : 'within usual range';
    }
    if (x > r.hi) return 'elevated > ${n(r.hi)}';
    if (x < r.lo) return 'low < ${n(r.lo)}';
    return signed
        ? 'within ${n(r.lo)} to ${n(r.hi)}'
        : 'within ${n(r.lo)} - ${n(r.hi)}';
  }
}

const _respLabel = 'Respiratory Rate';
const _skinLabel = 'Skin Temp\n(from baseline)';

/// The four tiles with nothing in them, in their order.
final List<_Vital> _emptyVitals = [
  _Vital('resp_rate', _respLabel, (c) => _Glyph(_lungs, c)),
  _Vital('resting_hr', 'RHR', (c) => _Glyph(_restingHeart, c)),
  _Vital('hrv', 'HRV', (c) => _Glyph(_pulse, c)),
  _Vital('skin_temp', _skinLabel, (c) => _Glyph(_thermometer, c)),
];

class _MonitorData {
  final List<_Vital> vitals;

  /// Nights of resting heart rate before today: the usual ranges need
  /// [kWhoopMonitorMinNights] of them. Null when nothing was read.
  final int? nights;
  const _MonitorData({this.vitals = const [], this.nights});

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

    final e = _emptyVitals;
    var nights = 0;
    try {
      nights = math.max(0, seriesOf(await repo.getChart('resting_hr')).length - 1);
    } catch (_) {}
    return _MonitorData(
      nights: nights,
      vitals: [
        _Vital('resp_rate', _respLabel, e[0].icon,
            present: resp != null,
            value: resp == null ? '' : resp.toStringAsFixed(1),
            unit: 'rpm',
            side: sideOf(respR, harmfulUp: true),
            range: respR,
            raw: resp?.toDouble(),
            places: 1),
        _Vital('resting_hr', 'RHR', e[1].icon,
            present: rhr != null,
            value: rhr == null ? '' : '${rhr.round()}',
            unit: 'bpm',
            side: sideOf(rhrR, harmfulUp: true),
            range: rhrR,
            raw: rhr?.toDouble()),
        _Vital('hrv', 'HRV', e[2].icon,
            present: hrv != null,
            value: hrv == null ? '' : '${hrv.round()}',
            unit: 'ms',
            side: sideOf(hrvR, harmfulUp: false),
            range: hrvR,
            raw: hrv?.toDouble()),
        _Vital('skin_temp', _skinLabel, e[3].icon,
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
            signed: true,
            rangeElsewhere: skinC != null),
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

/// The zone table's lower edges (zones 1..5), or null without one.
Future<List<int>?> _zoneEdges(BuildContext c) async {
  try {
    final z = (await repoOf(c)?.getZones())?['zones'];
    if (z is! List || z.length != 5) return null;
    return [for (final e in z) ((e as Map)['lo'] as num).round()];
  } catch (_) {
    return null;
  }
}

/// 0 below zone 1, else the zone whose lower edge [bpm] has reached.
int _zoneOf(int bpm, List<int> edges) {
  var z = 0;
  for (var i = 0; i < edges.length; i++) {
    if (bpm >= edges[i]) z = i + 1;
  }
  return z;
}

// The page's measured geometry, in dp (3 px to the dp on the reference).
const double _barH = S.x16;
const double _heroH = 168.7;
const double _gridTop = 7, _gridBottom = 142, _cell = 15;
const double _lineY = 88.3;
const double _dotFromRight = 32.7;
const double _dashTop = 14.3, _dashBottom = 131;
const double _tilePadX = S.x2 + S.half;
const double _tileRadius = S.x2 + S.half;

class HealthMonitorScreen extends StatefulWidget {
  const HealthMonitorScreen({super.key});

  @override
  State<HealthMonitorScreen> createState() => _HealthMonitorScreenState();
}

class _HealthMonitorScreenState extends State<HealthMonitorScreen> {
  AppState? _liveHrOwner;
  _MonitorData? _d;
  _Recorded? _recorded;
  List<int>? _zones;

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
      if (!mounted) return;
      if (r != null) setState(() => _recorded = r);
      final z = await _zoneEdges(context);
      if (mounted && z != null) setState(() => _zones = z);
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
    final vitals = loaded.isNotEmpty ? loaded : _emptyVitals;
    return AlwaysChar(
      child: Scaffold(
        backgroundColor: HM.foot,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: HM.pageStops,
              colors: HM.page,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.only(bottom: S.x16),
              children: [
                const _Bar(),
                _Hero(recorded: _recorded, zones: _zones),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Column(children: [
                    if (_d?.nights case final n?
                        when n < kWhoopMonitorMinNights &&
                            !vitals.any((v) => v.range != null)) ...[
                      CalibrationStrip(Milestone(
                        title: 'Health monitor',
                        about: '',
                        icon: LucideIcons.heartPulse,
                        need: kWhoopMonitorMinNights,
                        have: n,
                        done: false,
                      )),
                      const SizedBox(height: S.x4),
                    ],
                    for (var i = 0; i < vitals.length; i += 2) ...[
                      if (i > 0) const SizedBox(height: S.x3),
                      _TileRow(vitals.sublist(i, math.min(i + 2, vitals.length))),
                    ],
                    const SizedBox(height: S.x10),
                    _ShareCard(vitals: vitals, recorded: _recorded),
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

/// The back chevron and the title, centred in tracked capitals.
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
            semanticLabel: 'Back',
            child: const Icon(LucideIcons.chevronLeft,
                size: S.x10 + S.x1, color: DC.pure),
          ),
        ),
        Text('HEALTH MONITOR', style: HM.title.copyWith(color: DC.pure)),
      ]),
    );
  }
}

/// The beat's clock: how far through the current beat the heart is, and how
/// far the line has slid since the newest reading. One ticker feeds it; the
/// painters listen, so a frame repaints the hero and nothing else.
class _Clock extends ChangeNotifier {
  double beat = 0, slide = 0;
  void set(double b, double s) {
    beat = b;
    slide = s;
    notifyListeners();
  }
}

/// HEART RATE, the heart, the number, BPM and the zone, over the grid and
/// its line.
class _Hero extends StatefulWidget {
  final _Recorded? recorded;
  final List<int>? zones;
  const _Hero({this.recorded, this.zones});

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
    // Under the number: the live zone, else when the shown rate was recorded,
    // else why there is none.
    final edges = widget.zones;
    final String note;
    if (hr != null) {
      note = edges == null ? '' : 'Zone ${_zoneOf(hr, edges)}';
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
    final zone = hr != null && edges != null ? _zoneOf(hr, edges) : 0;

    return SizedBox(
      height: _heroH,
      child: Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GridPaint(
                trace: hr == null ? const [] : trace,
                clock: _clock,
                live: moving,
              ),
            ),
          ),
        ),
        Positioned(
          left: S.x6,
          right: S.x4,
          top: _HeroText.labelTop,
          child: Semantics(
            label: shown == null
                ? 'Heart rate: no reading. $note'
                : 'Heart rate $shown beats per minute. $note',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('HEART RATE', style: HM.kicker.copyWith(color: DC.pure)),
              const SizedBox(height: _HeroText.labelToHeart),
              Transform.translate(
                offset: const Offset(_HeroText.heartNudge, 0),
                child: SizedBox(
                  width: _HeroText.heartW,
                  height: _HeroText.heartH,
                  child: CustomPaint(painter: _BeatingHeart(_clock, moving)),
                ),
              ),
              const SizedBox(height: _HeroText.heartToValue),
              Text(shown == null ? '--' : '$shown',
                  style: HM.value.copyWith(color: DC.pure)),
              const SizedBox(height: _HeroText.valueToBpm),
              Text('BPM', style: HM.caps.copyWith(color: HM.caption)),
              const SizedBox(height: _HeroText.bpmToNote),
              Text(note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HM.zone.copyWith(color: HM.caption)),
            ]),
          ),
        ),
        Positioned(
          left: S.x6,
          top: _gridBottom,
          child: _ZoneBars(zone),
        ),
      ]),
    );
  }
}

/// The hero's text rhythm, measured off the reference's cap heights.
abstract final class _HeroText {
  static const labelTop = S.x2 + S.hair;
  static const labelToHeart = 8.7;
  // The heart's own size and its small step left of the text's edge, as
  // traced (22.28 x 19.1 dp, 1.27 dp left of the label).
  static const heartW = 22.28, heartH = 19.1, heartNudge = -1.27;
  static const heartToValue = 6.2;
  static const valueToBpm = S.x1 - S.hair;
  static const bpmToNote = S.x3;
}

/// The heart, swelling a little on each beat while the beat is live.
class _BeatingHeart extends CustomPainter {
  final _Clock clock;
  final bool live;
  _BeatingHeart(this.clock, this.live) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    final e = live ? .5 - .5 * math.cos(clock.beat * 2 * math.pi) : 0.0;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(1 + .08 * e);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawPath(_heartShape(size), Paint()..color = HM.heart);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BeatingHeart old) => old.live != live || old.clock != clock;
}

/// The hero's heart, traced off the reference: its right half from the notch
/// round to the tip, in its own box (0..1 across and down). The left half is
/// the mirror. Within 0.4 px of the trace at 3x.
const _heartHalf = [
    (0.500, 0.166),
    (0.525, 0.158),
    (0.606, 0.065),
    (0.660, 0.023),
    (0.687, 0.011),
    (0.715, 0.006),
    (0.766, 0.012),
    (0.801, 0.028),
    (0.832, 0.051),
    (0.871, 0.088),
    (0.906, 0.131),
    (0.956, 0.202),
    (0.978, 0.241),
    (0.993, 0.284),
    (0.997, 0.330),
    (0.996, 0.361),
    (0.987, 0.408),
    (0.976, 0.437),
    (0.951, 0.478),
    (0.874, 0.579),
    (0.783, 0.691),
    (0.748, 0.743),
    (0.688, 0.819),
    (0.570, 0.960),
    (0.549, 0.983),
    (0.537, 0.991),
    (0.500, 1.000),
];

Path _heartShape(Size size) {
  final w = size.width, h = size.height;
  final right = [for (final (x, y) in _heartHalf) Offset(x * w, y * h)];
  final path = Path()..moveTo(right.first.dx, right.first.dy);
  for (final o in right.skip(1)) {
    path.lineTo(o.dx, o.dy);
  }
  for (final o in right.reversed.skip(1)) {
    path.lineTo(w - o.dx, o.dy);
  }
  return path..close();
}

/// Five segments, the current zone's lit in its own colour.
class _ZoneBars extends StatelessWidget {
  final int zone;
  const _ZoneBars(this.zone);

  static const _zoneColors = [
    C.refZone1, C.refZone2, C.refZone3, C.refZone4, C.refZone5,
  ];

  @override
  Widget build(BuildContext c) {
    return Row(children: [
      for (var i = 0; i < 5; i++) ...[
        if (i > 0) const SizedBox(width: S.half),
        Container(
          width: S.x5,
          height: S.half,
          color: zone == i + 1 ? _zoneColors[i] : HM.segment,
        ),
      ],
    ]);
  }
}

/// The grid, the glow under the line, the line (the live trace, or flat) up
/// to the dot, and the dashed line through the dot.
class _GridPaint extends CustomPainter {
  final List<int> trace;
  final _Clock clock;
  final bool live;
  _GridPaint({required this.trace, required this.clock, required this.live})
      : super(repaint: clock);

  /// Readings across the line, and the most a reading moves it.
  static const _slots = 40;
  static const _reach = S.x3;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final grid = Paint()
      ..color = HM.grid
      ..strokeWidth = S.hair;
    for (var x = 0.0; x <= w; x += _cell) {
      canvas.drawLine(Offset(x, _gridTop), Offset(x, _gridBottom), grid);
    }
    for (var y = _gridTop; y <= _gridBottom + .1; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    final dotX = w - _dotFromRight;
    // The line fades in from the left, under the text.
    final fade = LinearGradient(
      // Only the mask's alpha is read.
      colors: const [Color(0x00000000), DC.scrim],
      stops: const [.17, .38],
    ).createShader(Rect.fromLTWH(0, 0, w, size.height));

    final pts = <Offset>[];
    if (trace.length < 2) {
      pts.addAll([Offset(0, _lineY), Offset(dotX, _lineY)]);
    } else {
      final t = trace.length > _slots + 1
          ? trace.sublist(trace.length - _slots - 1)
          : trace;
      final mean = t.reduce((a, b) => a + b) / t.length;
      final step = dotX / _slots;
      final n = t.length;
      pts.add(Offset(0, _lineY));
      for (var i = 0; i < n; i++) {
        pts.add(Offset(
            math.max(0, dotX - (n - 1 - i + (live ? clock.slide : 0)) * step),
            _lineY - ((t[i] - mean) * .8).clamp(-_reach, _reach)));
      }
      pts.add(Offset(dotX, pts.last.dy));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    var prev = pts.first;
    for (final p in pts.skip(1)) {
      final mid = Offset((prev.dx + p.dx) / 2, (prev.dy + p.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
      prev = p;
    }
    path.lineTo(prev.dx, prev.dy);

    canvas.saveLayer(Offset.zero & size, Paint());
    final under = Path.from(path)
      ..lineTo(dotX, _lineY + S.x10 + S.x1)
      ..lineTo(0, _lineY + S.x10 + S.x1)
      ..close();
    canvas.drawPath(
        under,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [HM.glow, Color(0x00000000)],
          ).createShader(
              Rect.fromLTWH(0, _lineY, w, S.x10 + S.x1)));
    canvas.drawPath(
        path,
        Paint()
          ..color = HM.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = S.half
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.drawRect(Offset.zero & size, Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = fade);
    canvas.restore();

    final dash = Paint()
      ..color = HM.dash
      ..strokeWidth = S.hair * .7;
    for (var y = _dashTop; y < _dashBottom; y += S.x1 + S.hair) {
      canvas.drawLine(Offset(dotX, y), Offset(dotX, math.min(y + S.x1 - S.hair, _dashBottom)), dash);
    }
    canvas.drawCircle(Offset(dotX, prev.dy), S.x1, Paint()..color = DC.pure);
  }

  @override
  bool shouldRepaint(_GridPaint old) =>
      !identical(old.trace, trace) || old.live != live || old.clock != clock;
}

/// Two tiles side by side, as tall as the taller. A one-line label beside a
/// wrapped one sits level with the middle of it; every number then sits a
/// fixed step under its own label, as on the reference.
class _TileRow extends StatelessWidget {
  final List<_Vital> pair;
  const _TileRow(this.pair);

  @override
  Widget build(BuildContext c) {
    final besideWrap = pair.any((v) => v.label.contains('\n'));
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _VitalTile(pair[0], besideWrap: besideWrap)),
        const SizedBox(width: S.x3),
        Expanded(
            child: pair.length > 1
                ? _VitalTile(pair[1], besideWrap: besideWrap)
                : const SizedBox.shrink()),
      ]),
    );
  }
}

class _VitalTile extends StatelessWidget {
  final _Vital v;
  final bool besideWrap;
  const _VitalTile(this.v, {required this.besideWrap});

  @override
  Widget build(BuildContext c) {
    final r = v.range, raw = v.raw;
    final word = v.verdict;
    final wraps = v.label.contains('\n');
    final (Color ink, Color chip, bool check) = !v.present || r == null || raw == null
        ? (DC.ink3, HM.noneChip, false)
        : r.flagged
            ? (C.poor, DC.hurtChip, false)
            : (HM.within, HM.withinChip, true);
    return Pressable(
      // The chart Home's dashboard row opens for the same metric; skin
      // temperature has a trend of its own that only this tile opens.
      onTap: () => go(
              c,
              trendMetricOf(v.key) != null || v.key == kSkinTempTrend.id
                  ? TrendViewScreen(initial: v.key)
                  : MetricDetail(v.key)),
      semanticLabel: '${v.label.replaceAll('\n', ' ')}. '
          '${v.present ? '${v.value} ${v.unit}. ' : ''}$word',
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            _tilePadX, S.x2, _tilePadX, S.x2 + S.half),
        decoration: const BoxDecoration(
          color: HM.card,
          borderRadius: BorderRadius.all(Radius.circular(_tileRadius)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!wraps)
              SizedBox(height: besideWrap ? _Tile.besideWrap : _Tile.alone),
            Row(children: [
              SizedBox(width: I.md, child: Center(child: v.icon(HM.icon))),
              const SizedBox(width: S.x2),
              Expanded(
                  child: Text(v.label.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HM.name.copyWith(color: HM.label))),
            ]),
            SizedBox(height: wraps ? _Tile.wrapToValue : _Tile.headerToValue),
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
                  const SizedBox(width: S.x1),
                  Text(v.unit,
                      style: (v.unit == '%' ? HM.percent : HM.unit)
                          .copyWith(color: DC.pure)),
                ],
              ],
            ),
            const SizedBox(height: _Tile.valueToChip),
            Container(
              height: _Tile.chip,
              padding: EdgeInsets.fromLTRB(check ? S.half + S.hair : S.x1 + S.hair, 0,
                  S.x1 + S.hair, 0),
              decoration: BoxDecoration(
                  color: chip,
                  borderRadius: const BorderRadius.all(Radius.circular(S.half + S.hair))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (check) ...[
                  Icon(LucideIcons.check, size: I.sm - S.x1 - S.hair, color: ink),
                  const SizedBox(width: S.half),
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

/// A tile's rhythm, measured off the reference.
abstract final class _Tile {
  /// Above a one-line label: alone in its row, and beside a wrapped one.
  static const alone = S.half + S.hair;
  static const besideWrap = S.x1 + S.hair;
  static const headerToValue = S.x4 + S.half;
  static const wrapToValue = S.x4;
  static const valueToChip = S.x4 + S.hair;
  static const chip = S.x4 + S.half;
}

/// SHARE YOUR HEALTH REPORT: the readings as text, through the system sheet.
class _ShareCard extends StatelessWidget {
  final List<_Vital> vitals;
  final _Recorded? recorded;
  const _ShareCard({required this.vitals, this.recorded});

  String _report() {
    final lines = [
      'Health report, ${todayLabel()}',
      '',
      for (final v in vitals)
        '${v.label.replaceAll('\n', ' ')}: '
            '${v.present ? '${v.value} ${v.unit} (${v.verdict})' : 'no data'}',
      if (recorded != null) 'Heart rate: last recorded ${recorded!.bpm} bpm',
      '',
      'Each reading is last night\'s, held against my own usual range (the '
          'middle half of my last 30 nights). Measured by a consumer '
          'wearable; not a medical device.',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Pressable(
        onTap: () => Share.share(_report(), subject: 'Health report'),
        semanticLabel: 'Share your health report',
        child: Container(
          height: S.x12 + S.x2,
          padding: const EdgeInsets.symmetric(horizontal: S.x4 - S.hair),
          decoration: const BoxDecoration(
            color: HM.card,
            borderRadius: BorderRadius.all(Radius.circular(_tileRadius)),
          ),
          child: Row(children: [
            const _Glyph(_share, HM.shareIcon, size: S.x6 + S.half),
            const SizedBox(width: S.x4 - S.hair),
            Expanded(
              child: Text('SHARE YOUR HEALTH REPORT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HM.share.copyWith(color: DC.pure)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: S.x3),
      Padding(
        padding: const EdgeInsets.only(left: S.hair),
        child: Text('These readings as text, to send to your doctor',
            style: HM.note.copyWith(color: HM.footnote)),
      ),
    ]);
  }
}

/// A line icon drawn on a 24-unit square, in the reference's hand: strokes
/// 1.4 units wide, round ends and joins.
class _Glyph extends StatelessWidget {
  final void Function(Canvas, Paint) draw;
  final Color color;
  final double size;
  const _Glyph(this.draw, this.color, {this.size = I.md});

  @override
  Widget build(BuildContext c) =>
      CustomPaint(size: Size.square(size), painter: _GlyphPaint(draw, color));
}

class _GlyphPaint extends CustomPainter {
  final void Function(Canvas, Paint) draw;
  final Color color;
  _GlyphPaint(this.draw, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    draw(
        canvas,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPaint old) => old.color != color || old.draw != draw;
}

/// Two lobes either side of a windpipe that forks into them.
void _lungs(Canvas c, Paint p) {
  Path lobe(double Function(double) x) => Path()
    ..moveTo(x(10), 7.6)
    ..cubicTo(x(10), 6, x(9.2), 5, x(8), 5)
    ..cubicTo(x(6.6), 5, x(5.8), 6.2, x(5.2), 7.6)
    ..cubicTo(x(3.6), 10.6, x(1.8), 13.6, x(1.8), 16.8)
    ..cubicTo(x(1.8), 19.2, x(3.2), 20.4, x(5.6), 20.4)
    ..cubicTo(x(8.4), 20.4, x(10), 19.4, x(10), 17.2)
    ..close();
  double id(double v) => v;
  double mirror(double v) => 24 - v;
  c.drawPath(lobe(id), p);
  c.drawPath(lobe(mirror), p);
  c.drawLine(const Offset(12, 3.4), const Offset(12, 10.6), p);
  for (final x in [id, mirror]) {
    c.drawPath(
        Path()
          ..moveTo(x(12), 9.6)
          ..quadraticBezierTo(x(12), 11.4, x(7.8), 14),
        p);
    c.drawLine(Offset(x(7.4), 11.8), Offset(x(10), 11.8), p);
  }
}

/// A heart with an arrow down beside it, cut clear of the arrow's head.
void _restingHeart(Canvas c, Paint p) {
  c.saveLayer(const Rect.fromLTWH(-2, -2, 28, 28), Paint());
  // Lobes of radius r; the sides run tangent from them to the tip.
  const l = 1.2, t = 6.0, r = 3.9, cx = l + 2 * r;
  const back = math.pi + math.pi / 4 - math.pi / 12;
  c.drawPath(
      Path()
        ..moveTo(cx, t + r * .7)
        ..arcTo(Rect.fromCircle(center: const Offset(l + r, t + r), radius: r),
            -math.pi / 12, -back, false)
        ..lineTo(cx, t + r * (2 + math.sqrt2))
        ..arcTo(
            Rect.fromCircle(center: const Offset(l + 3 * r, t + r), radius: r),
            math.pi / 4, -back, false)
        ..close(),
      p);
  final arrow = Path()
    ..moveTo(19.4, 9.4)
    ..lineTo(19.4, 19.4)
    ..moveTo(15.6, 15.6)
    ..lineTo(19.4, 19.4)
    ..lineTo(23.2, 15.6);
  c.drawPath(
      arrow,
      Paint.from(p)
        ..strokeWidth = p.strokeWidth * 3
        ..blendMode = BlendMode.clear);
  c.drawPath(arrow, p);
  c.restore();
}

/// A beat traced as a hollow ribbon: flat, a dip, a spike, flat again.
void _pulse(Canvas c, Paint p) {
  final line = Path()
    ..moveTo(2.4, 12)
    ..lineTo(7.4, 12)
    ..lineTo(8.8, 18.6)
    ..lineTo(16.2, 5.2)
    ..lineTo(17.2, 12)
    ..lineTo(21.6, 12);
  c.saveLayer(const Rect.fromLTWH(-2, -2, 28, 28), Paint());
  c.drawPath(line, Paint.from(p)..strokeWidth = 4.6);
  c.drawPath(
      line,
      Paint.from(p)
        ..strokeWidth = 4.6 - 2 * p.strokeWidth
        ..blendMode = BlendMode.clear);
  c.restore();
}

/// A tube into a bulb, the column of mercury down its middle.
void _thermometer(Canvas c, Paint p) {
  const cx = 12.0, hw = 2.8, top = 1.8, by = 18.2, br = 4.9;
  final dy = math.sqrt(br * br - hw * hw);
  final a = math.atan2(-dy, hw);
  c.drawPath(
      Path()
        ..moveTo(cx - hw, by - dy)
        ..lineTo(cx - hw, top + hw)
        ..arcToPoint(const Offset(cx + hw, top + hw),
            radius: const Radius.circular(hw))
        ..lineTo(cx + hw, by - dy)
        ..arcTo(Rect.fromCircle(center: const Offset(cx, by), radius: br), a,
            math.pi - 2 * a, false)
        ..close(),
      p);
  c.drawLine(const Offset(cx, 8.6), const Offset(cx, by - 1.2), p);
  c.drawCircle(const Offset(cx, by), 1.1, p);
}

/// An open-topped box with an arrow rising out of it.
void _share(Canvas c, Paint p) {
  const l = 2.6, r = 21.4, t = 9.2, b = 22.6;
  const k = Radius.circular(2.4);
  c.drawPath(
      Path()
        ..moveTo(7.2, t)
        ..lineTo(l + 2.4, t)
        ..arcToPoint(const Offset(l, t + 2.4), radius: k, clockwise: false)
        ..lineTo(l, b - 2.4)
        ..arcToPoint(const Offset(l + 2.4, b), radius: k, clockwise: false)
        ..lineTo(r - 2.4, b)
        ..arcToPoint(const Offset(r, b - 2.4), radius: k, clockwise: false)
        ..lineTo(r, t + 2.4)
        ..arcToPoint(const Offset(r - 2.4, t), radius: k, clockwise: false)
        ..lineTo(16.8, t),
      p);
  c.drawPath(
      Path()
        ..moveTo(12, 15.4)
        ..lineTo(12, 1.6)
        ..moveTo(7.6, 6)
        ..lineTo(12, 1.6)
        ..lineTo(16.4, 6),
      p);
}
