// HEALTH MONITOR — the live heart rate over a grid, then the four overnight
// vitals, each against your own usual range.
//
// Every tile has three states and only three: a value inside your range, a
// value outside it (and which side), and "No data". A dash is the absence —
// the overnight block is refused when it is a held-over night rather than
// today's ([overnightMetric]), so a tile never shows last week's reading as
// this morning's.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../compute/hr_max.dart' show estimatedMaxHr;
import '../../data/day_label.dart' show todayLabel;
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'metric_detail.dart';

/// One vital's reading and where it sits against the usual range.
class _Vital {
  final String key, label, value, unit;
  final IconData icon;

  /// Null: no reading. Otherwise inside / above / below the usual range, or
  /// null [side] when there is a reading but no range to hold it against yet.
  final bool present;
  final Side? side;

  const _Vital(this.key, this.label, this.icon,
      {this.value = '', this.unit = '', this.present = false, this.side});
}

class _MonitorData {
  final List<_Vital> vitals;
  final double? maxHr;
  const _MonitorData({this.vitals = const [], this.maxHr});

  static Future<_MonitorData> load(BuildContext c) async {
    final repo = repoOf(c);
    if (repo == null) return const _MonitorData();
    final today = await repo.getToday();
    final profile = await repo.getProfile();
    Map<String, dynamic> heart = const {};
    try {
      heart = await repo.getDayHeart(todayLabel());
    } catch (_) {
      // A repository without the heart block: no usual ranges, still values.
    }
    final baselines = heart['baselines'] is Map
        ? (heart['baselines'] as Map).cast<String, dynamic>()
        : null;

    Future<Side?> sideOf(String key, double? v) async {
      if (v == null) return null;
      final stored = seriesOf(await repo.getChart(key));
      return usualRangeFor(key, stored, baselines)?.side(v);
    }

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

    return _MonitorData(
      maxHr: estimatedMaxHr(profile['age'] as num?, null,
          manualMaxHr: profile['max_hr'] as num?),
      vitals: [
        _Vital('resp_rate', 'Respiratory Rate', LucideIcons.wind,
            present: resp != null,
            value: resp == null ? '' : resp.toStringAsFixed(1),
            unit: 'rpm',
            side: await sideOf('resp_rate', resp?.toDouble())),
        _Vital('resting_hr', 'RHR', LucideIcons.heartHandshake,
            present: rhr != null,
            value: rhr == null ? '' : '${rhr.round()}',
            unit: 'bpm',
            side: await sideOf('resting_hr', rhr?.toDouble())),
        _Vital('hrv', 'HRV', LucideIcons.activity,
            present: hrv != null,
            value: hrv == null ? '' : '${hrv.round()}',
            unit: 'ms',
            side: await sideOf('hrv', hrv?.toDouble())),
        _Vital('skin_temp', 'Skin Temp (from baseline)', LucideIcons.thermometer,
            present: skinZ != null,
            value: skinZ == null
                ? ''
                : skinC != null
                    ? signed(skinC, 1)
                    : signed(skinZ.toDouble(), 2),
            unit: skinC != null ? '°C' : 'SD',
            side: await sideOf('skin_temp', skinZ?.toDouble())),
      ],
    );
  }
}

class HealthMonitorScreen extends StatefulWidget {
  const HealthMonitorScreen({super.key});

  @override
  State<HealthMonitorScreen> createState() => _HealthMonitorScreenState();
}

class _HealthMonitorScreenState extends State<HealthMonitorScreen> {
  AppState? _liveHrOwner;
  _MonitorData? _d;

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
      if (mounted) setState(() => _d = d);
    });
  }

  @override
  void dispose() {
    _liveHrOwner?.releaseLiveHrView();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d;
    final vitals = d?.vitals ??
        const [
          _Vital('resp_rate', 'Respiratory Rate', LucideIcons.wind),
          _Vital('resting_hr', 'RHR', LucideIcons.heartHandshake),
          _Vital('hrv', 'HRV', LucideIcons.activity),
          _Vital('skin_temp', 'Skin Temp (from baseline)', LucideIcons.thermometer),
        ];
    return Scaffold(
      backgroundColor: p.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [p.bgTop, p.bg],
          ),
        ),
        child: SafeArea(
          child: Stack(children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16 + S.x8),
              children: [
                const NavBar('Health Monitor'),
                _LiveHeart(maxHr: d?.maxHr),
                const SizedBox(height: S.x4),
                for (var i = 0; i < vitals.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: S.x4),
                  IntrinsicHeight(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _VitalTile(vitals[i])),
                          const SizedBox(width: S.x4),
                          Expanded(
                              child: i + 1 < vitals.length
                                  ? _VitalTile(vitals[i + 1])
                                  : const SizedBox.shrink()),
                        ]),
                  ),
                ],
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// HEART RATE over the grid: the live number or a dash, what the link is
/// doing, and five zone segments lit up to the zone the beat is in.
class _LiveHeart extends StatelessWidget {
  final double? maxHr;
  const _LiveHeart({this.maxHr});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    int? hr;
    var paired = false, connected = false;
    try {
      hr = c.select<AppState, int?>((a) => a.liveHr);
      paired = c.select<AppState, bool>((a) => a.isPaired);
      connected = c.select<AppState, bool>((a) => a.isConnected);
    } catch (_) {
      // No AppState (goldens): the disconnected state.
    }
    final status = !paired
        ? 'No Device Paired'
        : !connected
            ? 'Device Disconnected'
            : hr == null
                ? 'Waiting for a reading'
                : 'Live';
    // Zones are 50–60 … 90–100 % of max. With no max there is no zone, so
    // nothing lights rather than a guess.
    final max = maxHr;
    final zone = hr == null || max == null || max <= 0
        ? -1
        : (((hr / max) - .5) / .1).floor().clamp(-1, 4);

    return CustomPaint(
      painter: _Grid(p.line.withValues(alpha: .45)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x2, S.x6, S.x2, S.x8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('HEART RATE', style: F.t2.copyWith(color: p.ink, letterSpacing: .9)),
          const SizedBox(height: S.x3),
          Icon(connected ? LucideIcons.bluetoothConnected : LucideIcons.bluetooth,
              size: I.xl, color: p.ink3),
          const SizedBox(height: S.x4),
          Text(hr == null ? '--' : '$hr',
              style: F.n64.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: S.x4),
          Text('BPM', style: F.caps.copyWith(color: p.ink2)),
          const SizedBox(height: S.x3),
          Text(status, style: F.head.copyWith(color: p.ink2, fontWeight: FontWeight.w400)),
          const SizedBox(height: S.x3),
          Row(children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: S.x1),
              Container(
                width: S.x12,
                height: S.x1,
                decoration: BoxDecoration(
                  color: i <= zone ? p.ink : p.track,
                  borderRadius: R.rPill,
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _Grid extends CustomPainter {
  final Color color;
  _Grid(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = S.x6;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_Grid old) => old.color != color;
}

class _VitalTile extends StatelessWidget {
  final _Vital v;
  const _VitalTile(this.v);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final (String word, Color dot) = !v.present
        ? ('No data', p.ink)
        : switch (v.side) {
            Side.inside => ('Within range', C.recGreen),
            Side.above => ('Above range', C.recYellow),
            Side.below => ('Below range', C.recYellow),
            null => ('No baseline', p.ink3),
          };
    return Surface(
      color: p.card,
      onTap: () => go(c, MetricDetail(v.key)),
      semanticLabel: '${v.label}. ${v.present ? '${v.value} ${v.unit}. ' : ''}$word',
      pad: const EdgeInsets.all(S.x4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(v.icon, size: I.md, color: p.ink3),
          const SizedBox(width: S.x2),
          // Small, tracked caps that wrap on word breaks: the long names
          // ("Respiratory Rate") used to split mid-word at the larger size.
          Expanded(
              child: Text(v.label.toUpperCase(),
                  style: F.over.copyWith(
                      color: p.ink2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .7))),
        ]),
        const SizedBox(height: S.x8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(v.present ? v.value : '--',
                    style: F.n34.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              ),
            ),
            if (v.present && v.unit.isNotEmpty) ...[
              const SizedBox(width: S.x1),
              Text(v.unit, style: F.cap.copyWith(color: p.ink3)),
            ],
          ],
        ),
        const SizedBox(height: S.x4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: S.x2 + S.half,
              height: S.x2 + S.half,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: S.x2),
            Flexible(
              child: Text(word,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ]),
    );
  }
}
