// The band's battery: where it stands now, the last day or week as a line, and
// how fast it is draining. Every figure is read off the stored battery samples;
// with too few of them the drain is not estimated, not guessed.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../notify/battery_forecast.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart';
import '../ui2.dart';
import 'home/home_data.dart' show weekdayShortName;
import 'metric_detail.dart' show detailScaffold;

enum BatteryTimeRange { day, week }

/// Below this the battery reads as low, as the low-battery alert does.
const _lowPct = 20;

class BatteryDetailScreen extends StatefulWidget {
  const BatteryDetailScreen({super.key});

  @override
  State<BatteryDetailScreen> createState() => _BatteryDetailScreenState();
}

class _BatteryDetailScreenState extends State<BatteryDetailScreen> {
  BatteryTimeRange _range = BatteryTimeRange.day;
  List<BatterySample> _samples = const [];
  bool _loading = true;
  BatteryForecast? _forecast;
  int? _at;
  late DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final rows = await LocalDb.bandBatteryRange(
      startSec: nowSec - 7 * 86400,
      endSec: nowSec,
    );
    final samples = <BatterySample>[
      for (final r in rows)
        if (r['battery_pct'] is num && r['ts'] is num)
          BatterySample(
            tsSec: (r['ts'] as num).toInt(),
            pct: (r['battery_pct'] as num).toDouble(),
            charging: (r['charging'] as num?)?.toInt() == 1,
          ),
    ];
    final f = const BatteryForecaster().forecast(
      samples: samples,
      now: now,
      // Only the drain rate and the empty time are shown; the wake-time
      // projection is not, so its time is immaterial.
      wakeAt: DateTime(now.year, now.month, now.day, now.hour + 1),
    );
    if (!mounted) return;
    setState(() {
      _now = now;
      _samples = samples;
      _forecast = f;
      _loading = false;
      _at = null;
    });
  }

  // ── the chart's slots ────────────────────────────────────────────────────
  /// A day is 96 slots of 15 minutes, a week 168 of an hour.
  int get _slotSec => _range == BatteryTimeRange.day ? 900 : 3600;
  int get _slotCount => _range == BatteryTimeRange.day ? 96 : 168;

  int get _startSec =>
      _now.millisecondsSinceEpoch ~/ 1000 - _slotCount * _slotSec;

  DateTime _slotTime(int i) => DateTime.fromMillisecondsSinceEpoch(
    (_startSec + (i + 1) * _slotSec) * 1000,
  );

  /// Each slot's last reading, and whether the band charged in it.
  ({List<double?> pct, List<bool> charging}) get _slots {
    final pct = List<double?>.filled(_slotCount, null);
    final charging = List<bool>.filled(_slotCount, false);
    for (final s in _samples) {
      final i = (s.tsSec - _startSec) ~/ _slotSec;
      if (i < 0 || i >= _slotCount) continue;
      pct[i] = s.pct;
      if (s.charging) charging[i] = true;
    }
    return (pct: pct, charging: charging);
  }

  /// A label where a slot starts a new day (a week) or a new six hours (a day).
  List<String> _xLabels(AppLocalizations? l) => [
    for (var i = 0; i < _slotCount; i++)
      () {
        final a = DateTime.fromMillisecondsSinceEpoch(
          (_startSec + i * _slotSec) * 1000,
        );
        final b = _slotTime(i);
        if (_range == BatteryTimeRange.week) {
          return a.day != b.day ? weekdayShortName(b.weekday, l) : '';
        }
        final crosses = a.day != b.day || a.hour ~/ 6 != b.hour ~/ 6;
        return crosses
            ? formatClockOf(
                DateTime(b.year, b.month, b.day, b.hour - b.hour % 6),
              )
            : '';
      }(),
  ];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final app = context.watch<AppState>();
    final f = _forecast;
    final now =
        app.device.batteryPct ??
        (_samples.isNotEmpty ? _samples.last.pct : null);
    final charging = app.device.charging == true;
    final low = now != null && !charging && now <= _lowPct;
    final empty = f?.predictedEmptyAt;
    final hoursLeft = empty == null
        ? null
        : math.max(0, empty.difference(DateTime.now()).inMinutes / 60);
    final status = charging
        ? 'Charging'
        : hoursLeft == null
        ? null
        : hoursLeft < 1
        ? 'Less than an hour left'
        : 'About ${hoursLeft.round()} h left';
    final fill = charging
        ? C.recGreen
        : low
        ? C.strainDown
        : p.ink;

    final slots = _slots;
    final at = _at;
    final shown = at == null ? now : slots.pct[at];

    return detailScaffold(c, 'Band battery', [
      const SizedBox(height: S.x2),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScrubReadout(
              caption: 'Battery now',
              value: now == null ? '--' : '${now.round()}',
              unit: now == null ? null : '%',
            ),
            const SizedBox(height: S.x4),
            ClipRRect(
              borderRadius: R.rPill,
              child: SizedBox(
                height: S.x2,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: p.track)),
                    FractionallySizedBox(
                      widthFactor: ((now ?? 0) / 100).clamp(0.0, 1.0),
                      child: ColoredBox(color: fill),
                    ),
                  ],
                ),
              ),
            ),
            if (status != null) ...[
              const SizedBox(height: S.x3),
              Text(
                status,
                style: F.cap.copyWith(
                  color: low ? p.on(C.strainDown) : p.ink2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: S.x6),
      RangeSegments(
        const ['DAY', 'WEEK'],
        _range.index,
        (i) => setState(() {
          _range = BatteryTimeRange.values[i];
          _at = null;
        }),
        width: null,
      ),
      const SizedBox(height: S.x4),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScrubReadout(
              caption: at == null
                  ? (_range == BatteryTimeRange.day
                        ? 'Last 24 hours'
                        : 'Last 7 days')
                  : _range == BatteryTimeRange.day
                  ? formatClockOf(_slotTime(at))
                  : '${weekdayShortName(_slotTime(at).weekday, l)} '
                        '${formatClockOf(_slotTime(at))}',
              value: shown == null ? '--' : '${shown.round()}',
              unit: shown == null ? null : '%',
              big: false,
            ),
            const SizedBox(height: S.x3),
            if (_loading)
              const SizedBox(
                height: S.x16 * 3,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (slots.pct.every((v) => v == null))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: S.x8),
                child: Center(
                  child: NoData(
                    message:
                        'No battery readings yet. The band reports '
                        'its battery each time it syncs.',
                  ),
                ),
              )
            else
              ScrubLine(
                values: slots.pct,
                xLabels: _xLabels(l),
                lo: 0,
                hi: 100,
                ticks: const [0, 50, 100],
                tickText: (t) => '${t.round()}%',
                color: C.dialStrain,
                markers: false,
                slots: false,
                // An hour without a reading breaks the line.
                gap: _range == BatteryTimeRange.day ? 4 : 2,
                height: S.x16 * 3,
                label: 'Battery level',
                describe: (i) => slots.pct[i] == null
                    ? '${formatClockOf(_slotTime(i))}, no reading'
                    : '${formatClockOf(_slotTime(i))}, '
                          '${slots.pct[i]!.round()} percent',
                paintUnder: (cv, plot, xOf, yOf) {
                  // Charging stretches, shaded as the activities are on Strain.
                  final paint = Paint()
                    ..color = C.recGreen.withValues(alpha: .16);
                  for (var i = 0; i < _slotCount; i++) {
                    if (!slots.charging[i]) continue;
                    final x0 = xOf(i);
                    final x1 = i + 1 < _slotCount ? xOf(i + 1) : plot.right;
                    cv.drawRect(
                      Rect.fromLTRB(x0, plot.top, x1, plot.bottom),
                      paint,
                    );
                  }
                },
                onScrub: (i) => setState(() => _at = i),
              ),
            if (slots.charging.contains(true)) ...[
              const SizedBox(height: S.x2),
              Row(
                children: [
                  Container(
                    width: S.x3,
                    height: S.x3,
                    decoration: BoxDecoration(
                      color: C.recGreen.withValues(alpha: .4),
                      borderRadius: R.rSm,
                    ),
                  ),
                  const SizedBox(width: S.x2),
                  Text(
                    'CHARGING',
                    style: F.over.copyWith(
                      color: p.ink2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: S.x4),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DRAIN', style: F.caps.copyWith(color: p.ink)),
            const SizedBox(height: S.x3),
            if (f == null || !f.isUsable)
              Text(
                'Not enough readings off the charger yet to say how fast the '
                'battery drains. It needs a few over at least two hours.',
                style: F.body.copyWith(color: p.ink2, height: 1.4),
              )
            else ...[
              _row(
                p,
                'Draining at',
                '${f.drainPctPerHour!.toStringAsFixed(1)}% an hour',
              ),
              Divider(color: p.line),
              _row(p, 'About a day', '${(f.drainPctPerHour! * 24).round()}%'),
              if (empty != null && !charging) ...[
                Divider(color: p.line),
                _row(
                  p,
                  'Runs out',
                  '${weekdayShortName(empty.weekday, l)} '
                      '${formatClockOf(empty)}',
                ),
              ],
            ],
          ],
        ),
      ),
    ]);
  }

  Widget _row(P p, String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: S.tap),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: F.body.copyWith(color: p.ink2)),
        ),
        const SizedBox(width: S.x3),
        Text(
          value,
          style: F.num(
            F.body,
          ).copyWith(color: p.ink, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
