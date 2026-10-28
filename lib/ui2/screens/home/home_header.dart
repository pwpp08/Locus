import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/day_label.dart' show todayLabel;
import '../../../data/local_repository.dart' show LocalRepository;
import '../../../l10n/app_localizations.dart';
import '../../../notify/notification_prefs.dart' show NotificationPrefs;
import '../../../state/app_state.dart';
import '../../../state/clock_format.dart' show formatClockOf;
import '../../../theme/theme_switcher.dart' show themedRoute;
import '../../grammar.dart' show Pressable;
import '../../marks.dart' show BoldChevron, StrapIcon, SyncArrowMark;
import '../../profile/devices.dart' show MyDevices, formatDayTime;
import '../../theme.dart' show C, F, I, Motion, P, S;
import '../../ui2.dart' show LucideIcons;
import '../battery_detail_screen.dart';
import '../recovery_calendar.dart' show openRecoveryCalendar;
import '../trend_view.dart' show TrendLoader, trendMetricOf;
import 'home_data.dart';

DateTime? lastDataAtOf(BuildContext c) {
  try {
    return c.select<AppState, DateTime?>((a) => a.lastRecordAt);
  } catch (_) {
    return null;
  }
}

bool syncingNowOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.syncingNow);
  } catch (_) {
    return false;
  }
}

bool derivingOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.deriving || a.derivePending);
  } catch (_) {
    return false;
  }
}

String syncedThroughLabel(DateTime? at, String? todayId,
    [AppLocalizations? l]) {
  if (at == null) return l?.homeSyncedNever ?? 'No band data yet';
  final today = todayId == null ? null : DateTime.tryParse(todayId);
  final isToday = today != null &&
      at.year == today.year &&
      at.month == today.month &&
      at.day == today.day;
  final when = isToday ? formatClockOf(at) : formatDayTime(at, l);
  return l?.homeSyncedThrough(when) ?? 'Synced through $when';
}

(double, bool)? deviceBatteryOf(BuildContext c) {
  try {
    return c.select<AppState, (double, bool)?>((a) {
      final pct = a.device.batteryPct;
      final charging = a.device.charging;
      return (pct == null || charging == null) ? null : (pct, charging);
    });
  } catch (_) {
    return null;
  }
}

bool lowBattery(double pct, bool charging) =>
    !charging && pct < NotificationPrefs.batteryPctDefault;

Widget? batteryLine(BuildContext c) {
  final battery = deviceBatteryOf(c);
  if (battery == null) return null;
  final (pct, charging) = battery;
  final p = P.of(c);
  final color = lowBattery(pct, charging) ? p.on(C.red) : p.ink3;
  return Pressable(
    semanticLabel: 'Battery details',
    onTap: () {
      Navigator.of(c).push(
        MaterialPageRoute(builder: (_) => const BatteryDetailScreen()),
      );
    },
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(charging ? LucideIcons.batteryCharging : LucideIcons.battery,
          size: I.sm, color: color),
      const SizedBox(width: 3),
      Text('${pct.round()}%', style: F.cap.copyWith(color: color)),
    ]),
  );
}

Widget syncedThroughLine(BuildContext c, String? todayId,
    [AppLocalizations? l]) {
  return Text(
    syncedThroughLabel(lastDataAtOf(c), todayId, l),
    style: F.cap.copyWith(color: P.of(c).ink3),
  );
}

class HomeWordmark extends StatelessWidget {
  const HomeWordmark({super.key});

  @override
  Widget build(BuildContext c) => Center(
        child: Text('LOCUS',
            style: F.wordmark.copyWith(color: P.of(c).ink2)),
      );
}

class DetailDayPager extends StatelessWidget {
  final String? day;
  final List<String> days;
  final ValueChanged<String> onDay;

  const DetailDayPager(
      {super.key, required this.day, required this.days, required this.onDay});

  Future<void> _calendar(BuildContext c, String cur, String today) async {
    var recovery = const <String, double>{};
    LocalRepository? repo;
    try {
      repo = c.read<AppState>().repo;
    } catch (_) {}
    final m = trendMetricOf('recovery');
    if (repo != null && m != null) {
      try {
        recovery = await TrendLoader(repo).daily(m);
      } catch (_) {}
    }
    if (!c.mounted) return;
    final picked = await openRecoveryCalendar(c,
        today: today, selected: cur, recovery: recovery, days: {...days, today});
    if (picked != null && picked != cur) onDay(picked);
  }

  @override
  Widget build(BuildContext c) {
    final today = todayLabel();
    final cur = day ?? today;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x4),
      child: Center(
        child: DayPager(
          day: cur,
          today: today,
          days: days,
          onDay: onDay,
          onCalendar: () => _calendar(c, cur, today),
        ),
      ),
    );
  }
}

class DayPager extends StatelessWidget {
  final String day, today;
  final List<String> days;
  final ValueChanged<String> onDay;
  final VoidCallback onCalendar;

  const DayPager(
      {super.key,
      required this.day,
      required this.today,
      required this.days,
      required this.onDay,
      required this.onCalendar});

  static const _h = S.x8;
  static final _r = BorderRadius.circular(S.x2 + S.half);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    String? older;
    for (final d in days) {
      if (d.compareTo(day) < 0) {
        older = d;
        break;
      }
    }
    String? newer;
    if (day != today) {
      for (final d in days) {
        if (d.compareTo(day) > 0) newer = d;
      }
      newer ??= today;
    }
    final dt = DateTime.tryParse(day);
    final label = day == today || dt == null
        ? (l?.dayStrainToday ?? 'TODAY')
        : '${weekdayShortName(dt.weekday, l)}, ${monthShortName(dt.month, l)} ${dt.day}'
            .toUpperCase();

    Widget arrow(IconData i, String? to, String what) => Semantics(
          label: what,
          button: true,
          enabled: to != null,
          excludeSemantics: true,
          child: Pressable(
            onTap: to == null ? null : () => onDay(to),
            child: SizedBox(
              width: S.x8 + S.x1,
              height: S.tap,
              child: Center(
                child: BoldChevron(
                    left: i == LucideIcons.chevronLeft,
                    height: S.x3,
                    color: to == null ? p.ink.withValues(alpha: .22) : p.ink),
              ),
            ),
          ),
        );

    return SizedBox(
      width: S.x16 * 2 + S.x8 + S.x1 * 2,
      height: S.tap,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          height: _h,
          decoration: BoxDecoration(
            color: Color.alphaBlend(p.ink.withValues(alpha: .05), p.bg),
            borderRadius: _r,
          ),
        ),
        Row(children: [
          arrow(LucideIcons.chevronLeft, older, 'Previous day'),
          Expanded(
            child: Semantics(
              label: 'Open the calendar',
              button: true,
              excludeSemantics: true,
              child: Pressable(
                onTap: onCalendar,
                child: SizedBox(
                  height: S.tap,
                  child: Center(
                    child: Container(
                      height: _h,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(p.ink.withValues(alpha: .15), p.bg),
                        borderRadius: _r,
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label,
                            maxLines: 1,
                            style: F.over.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                height: 1)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          arrow(LucideIcons.chevronRight, newer, 'Next day'),
        ]),
      ]),
    );
  }
}

class HomeDeviceStatus extends StatelessWidget {
  const HomeDeviceStatus({super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final battery = deviceBatteryOf(c);
    var connected = false;
    try {
      connected = c.select<AppState, bool>((a) => a.isConnected);
    } catch (_) {}
    final low = battery != null && lowBattery(battery.$1, battery.$2);
    final syncing = syncingNowOf(c);
    return Pressable(
      semanticLabel: [
        'Device settings',
        if (battery != null) 'battery ${battery.$1.round()}%',
        connected ? 'connected' : 'not connected',
      ].join(', '),
      onTap: () {
        Navigator.of(c).push(themedRoute((_) => const MyDevices(), name: 'MyDevices'));
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (battery != null) ...[
          Text('${battery.$1.round()}%',
              style: F.n17.copyWith(
                  color: low ? p.on(C.red) : p.ink, fontWeight: FontWeight.w700)),
          const SizedBox(width: S.x2),
        ],
        StrapIcon(
          color: p.ink,
          height: S.x6,
          badge: syncing
              ? const HomeSyncArrow()
              : Container(
                  width: S.x2 + S.half,
                  height: S.x2 + S.half,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected ? C.recGreen : p.ink3,
                  ),
                ),
        ),
      ]),
    );
  }
}

class HomeSyncArrow extends StatefulWidget {
  const HomeSyncArrow({super.key});

  @override
  State<HomeSyncArrow> createState() => _HomeSyncArrowState();
}

class _HomeSyncArrowState extends State<HomeSyncArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: Motion.slow * 2)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _t.reverse();
          if (s == AnimationStatus.dismissed) _t.forward();
        });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.enabled(context)) {
      if (!_t.isAnimating) _t.forward();
    } else {
      _t.stop();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    const arrow = SyncArrowMark();
    return AnimatedBuilder(
      animation: _t,
      builder: (_, child) => Transform.translate(
          offset: Offset(0, -S.x1 * Curves.easeInOut.transform(_t.value)),
          child: child),
      child: arrow,
    );
  }
}
