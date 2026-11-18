// The band's battery, on the Device settings page's ground: where it stands
// now beside the same charge bar, how fast it drains, and the last day or
// week as a line. Every figure is read off the stored battery samples;
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
import '../profile/profile.dart' show setRowTitle;

enum BatteryTimeRange { day, week }

/// Below this the battery reads as low, as the low-battery alert does.
const _lowPct = 20;

class BatteryDetailScreen extends StatefulWidget {
  /// Injected by renders and tests; production reads `band_battery`.
  final List<BatterySample>? samples;
  const BatteryDetailScreen({super.key, this.samples});

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
    final samples = widget.samples ??
        <BatterySample>[
          for (final r in await LocalDb.bandBatteryRange(
            startSec: nowSec - 7 * 86400,
            endSec: nowSec,
          ))
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
    AppState? app;
    try {
      app = context.watch<AppState>();
    } catch (_) {
      // No AppState (renders): the stored samples say it all.
    }
    final f = _forecast;
    final now =
        app?.device.batteryPct ??
        (_samples.isNotEmpty ? _samples.last.pct : null);
    final charging = app?.device.charging == true;
    final low = now != null && !charging && now <= _lowPct;
    final empty = f?.predictedEmptyAt;
    final hoursLeft = empty == null
        ? null
        : math.max(0, empty.difference(DateTime.now()).inMinutes / 60);
    final status = charging
        ? 'CHARGING'
        : hoursLeft == null
        ? 'NOT ENOUGH READINGS TO FORECAST'
        : hoursLeft < 1
        ? 'LESS THAN AN HOUR LEFT'
        : hoursLeft < 36
        ? 'ABOUT ${hoursLeft.round()} H LEFT'
        : 'ABOUT ${(hoursLeft / 24).round()} DAYS LEFT';
    final tone = now == null
        ? p.ink3
        : charging || now >= 50
        ? C.recGreen
        : now >= _lowPct
        ? C.recYellow
        : C.recRed;

    final slots = _slots;
    final at = _at;
    final shown = at == null ? now : slots.pct[at];
    final usable = f != null && f.isUsable;

    Widget card(Widget child, {EdgeInsets pad = const EdgeInsets.all(S.x4)}) =>
        Container(
          padding: pad,
          decoration: const BoxDecoration(color: DS.card, borderRadius: R.rXl),
          child: child,
        );

    return Scaffold(
      backgroundColor: DS.foot,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: DS.page,
            stops: DS.pageStops,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SizedBox(
                height: S.x12 + S.x2,
                child: Row(
                  children: [
                    Pressable(
                      semanticLabel: 'Back',
                      onTap: () => Navigator.of(c).maybePop(),
                      child: SizedBox.square(
                        dimension: S.tap + S.x4,
                        child: Icon(
                          LucideIcons.chevronLeft,
                          size: I.xl,
                          color: p.ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'BAND BATTERY',
                        textAlign: TextAlign.center,
                        style: setRowTitle(p).copyWith(letterSpacing: 1),
                      ),
                    ),
                    const SizedBox(width: S.tap + S.x4),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    S.x4,
                    S.x4,
                    S.x4,
                    S.x10 + MediaQuery.viewPaddingOf(c).bottom,
                  ),
                  children: [
                    // ── now: the charge, its bar, and how long it lasts ──
                    Semantics(
                      label: now == null
                          ? 'Battery unknown'
                          : 'Battery ${now.round()} percent. ${status.toLowerCase()}',
                      excludeSemantics: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'BATTERY NOW',
                                style: DS.kicker.copyWith(color: DS.syncLabel),
                              ),
                              const SizedBox(height: S.x2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  if (charging) ...[
                                    Icon(LucideIcons.zap, size: I.md, color: tone),
                                    const SizedBox(width: S.x1),
                                  ],
                                  Text(
                                    now == null ? '--' : '${now.round()}',
                                    style: HM.value.copyWith(color: p.ink),
                                  ),
                                  const SizedBox(width: S.x1 + S.half),
                                  Text(
                                    '%',
                                    style: F.n17.copyWith(color: p.ink),
                                  ),
                                ],
                              ),
                              const SizedBox(height: S.x2),
                              Text(
                                status,
                                style: DS.kicker.copyWith(
                                  color: low ? C.recRed : DS.sub,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: S.x5),
                          // The charge as the Device settings bar, filled
                          // from the foot.
                          Container(
                            width: S.x1 + S.half,
                            height: S.x16 + S.x4,
                            decoration: const BoxDecoration(
                              color: DS.track,
                              borderRadius: R.rPill,
                            ),
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: ((now ?? 0) / 100).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: tone,
                                  borderRadius: R.rPill,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: S.x8),
                    // ── how fast it drains ──
                    card(
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            _Fact(
                              'DRAIN',
                              usable
                                  ? '${f.drainPctPerHour!.toStringAsFixed(1)}%'
                                  : '--',
                              'an hour',
                            ),
                            const VerticalDivider(color: DS.track, width: 1),
                            _Fact(
                              'PER DAY',
                              usable
                                  ? '${(f.drainPctPerHour! * 24).round()}%'
                                  : '--',
                              'at this rate',
                            ),
                            const VerticalDivider(color: DS.track, width: 1),
                            _Fact(
                              'RUNS OUT',
                              empty != null && !charging
                                  ? formatClockOf(empty)
                                  : '--',
                              empty != null && !charging
                                  ? weekdayShortName(empty.weekday, l)
                                  : charging
                                  ? 'charging'
                                  : '',
                            ),
                          ],
                        ),
                      ),
                      pad: const EdgeInsets.symmetric(vertical: S.x4),
                    ),
                    if (!usable) ...[
                      const SizedBox(height: S.x2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: S.x1),
                        child: Text(
                          'The drain is read once the band has been off the '
                          'charger for a couple of hours with a few readings.',
                          style: F.cap.copyWith(color: DS.sub, height: 1.4),
                        ),
                      ),
                    ],
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
                    // ── the history ──
                    card(
                      Column(
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
                              paintOver: (cv, plot, xOf, yOf) {
                                // The line itself turns green over a slot
                                // the band spent on the charger.
                                final paint = Paint()
                                  ..color = C.recGreen
                                  ..strokeWidth = S.half + S.hair
                                  ..strokeCap = StrokeCap.round;
                                for (var i = 1; i < _slotCount; i++) {
                                  final a = slots.pct[i - 1], b = slots.pct[i];
                                  if (!slots.charging[i] || a == null || b == null) {
                                    continue;
                                  }
                                  cv.drawLine(Offset(xOf(i - 1), yOf(a)),
                                      Offset(xOf(i), yOf(b)), paint);
                                }
                              },
                              onScrub: (i) => setState(() => _at = i),
                            ),
                          if (slots.charging.contains(true)) ...[
                            const SizedBox(height: S.x2),
                            Row(
                              children: [
                                Container(
                                  width: S.x4,
                                  height: S.half + S.hair,
                                  decoration: const BoxDecoration(
                                    color: C.recGreen,
                                    borderRadius: R.rPill,
                                  ),
                                ),
                                const SizedBox(width: S.x2),
                                Text(
                                  'CHARGING',
                                  style: DS.kicker.copyWith(color: DS.sub),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One drain fact: a tracked label, the figure, a word under it.
class _Fact extends StatelessWidget {
  final String label, value, sub;
  const _Fact(this.label, this.value, this.sub);

  @override
  Widget build(BuildContext c) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: DS.kicker.copyWith(color: DS.sub)),
        const SizedBox(height: S.x2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: F.n24.copyWith(color: P.of(c).ink),
          ),
        ),
        const SizedBox(height: S.x1),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: F.over.copyWith(color: DS.sub),
        ),
      ],
    ),
  );
}
