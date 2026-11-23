import 'dart:async';

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
import '../../profile/device_settings.dart' show DeviceSettings;
import '../../profile/devices.dart' show formatDayTime;
import '../../theme.dart' show C, DC, Ease, F, I, Motion, P, R, S, motion;
import '../../ui2.dart' show LucideIcons;
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
      // The percentage shows as soon as the band reports it. Whether it is
      // charging arrives by a separate event that can come much later (or not
      // at all on a fresh link); until then it counts as not charging rather
      // than hiding the level.
      final pct = a.device.batteryPct;
      return pct == null ? null : (pct, a.device.charging ?? false);
    });
  } catch (_) {
    return null;
  }
}

bool lowBattery(double pct, bool charging) =>
    !charging && pct < NotificationPrefs.batteryPctDefault;

/// The time the band's data reaches: the clock today, a day and time before.
String syncedToText(DateTime at, String todayId, [AppLocalizations? l]) {
  final today = DateTime.tryParse(todayId);
  final isToday = today != null &&
      at.year == today.year &&
      at.month == today.month &&
      at.day == today.day;
  return isToday ? formatClockOf(at) : formatDayTime(at, l);
}

Widget syncedThroughLine(BuildContext c, String? todayId,
    [AppLocalizations? l]) {
  return Text(
    syncedThroughLabel(lastDataAtOf(c), todayId, l),
    style: F.cap.copyWith(color: P.of(c).ink3),
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

  /// The most the pager may take: what is left between whatever sits either
  /// side of it. The label shrinks to fit below that.
  final double? maxWidth;

  /// The day is loading: a spinner stands in for the label, as the
  /// reference shows while it fetches the day it moved to.
  final bool loading;

  const DayPager(
      {super.key,
      required this.day,
      required this.today,
      required this.days,
      required this.onDay,
      required this.onCalendar,
      this.maxWidth,
      this.loading = false});

  /// Measured off the reference (36 pt avatar to scale): a 36 pt track,
  /// 40 pt for each arrow (44 here, the least a tap may be), the label in 12 pt tracked caps with 18 pt either
  /// side inside its lighter pill. The pill hugs the label, so TODAY is
  /// narrower than SAT, NOV 21.
  static const _h = S.x8 + S.x1;
  // 44 pt, not the reference's 40: the least a tap target may be.
  static const _arrow = S.x10 + S.x1;
  static const _pad = S.x4 + S.half;
  static final _r = BorderRadius.circular(S.x3);

  /// The narrowest the pager gets: the arrows round a short label.
  static const base = _arrow * 2 + S.x16 + S.x3;

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

    Widget arrow(bool left, String? to, String what) => Semantics(
          label: what,
          button: true,
          enabled: to != null,
          excludeSemantics: true,
          child: Pressable(
            onTap: to == null ? null : () => onDay(to),
            child: SizedBox(
              width: _arrow,
              height: S.tap,
              child: Center(
                child: BoldChevron(
                    left: left,
                    height: S.x3 + S.half,
                    color: to == null ? p.ink.withValues(alpha: .3) : p.ink),
              ),
            ),
          ),
        );

    final inner = loading
        ? SizedBox.square(
            key: const ValueKey('loading'),
            dimension: S.x4,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: p.ink.withValues(alpha: .6)))
        : Text(label,
            key: ValueKey(label),
            maxLines: 1,
            style: F.caps.copyWith(color: p.ink, height: 1));

    // Never past [maxWidth], which clears the avatar and the battery and band
    // either side; past that the label shrinks.
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: maxWidth ?? double.infinity,
          minHeight: S.tap,
          maxHeight: S.tap),
      child: Center(
        child: Container(
          height: _h,
          decoration: BoxDecoration(
            color: Color.alphaBlend(p.ink.withValues(alpha: .05), p.bg),
            borderRadius: _r,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            arrow(true, older, 'Previous day'),
            Flexible(
              child: Semantics(
                label: 'Open the calendar',
                button: true,
                excludeSemantics: true,
                child: Pressable(
                  onTap: onCalendar,
                  child: AnimatedSize(
                    duration: motion(c, Motion.base),
                    curve: Curves.easeOutCubic,
                    child: Container(
                      height: _h,
                      padding: const EdgeInsets.symmetric(horizontal: _pad),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                            p.ink.withValues(alpha: .14), p.bg),
                        borderRadius: _r,
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AnimatedSwitcher(
                          duration: motion(c, Motion.fast),
                          child: inner,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            arrow(false, newer, 'Next day'),
          ]),
        ),
      ),
    );
  }
}

class HomeDeviceStatus extends StatelessWidget {
  const HomeDeviceStatus({super.key});

  /// Measured off the reference: 13 pt bold figures, a 26 pt band.
  static final _pct = F.cap.copyWith(fontWeight: FontWeight.w700);
  static const _band = S.x6 + S.half;

  /// The widest the status gets: "100%", the gap and the band with its badge.
  static double widestOf(BuildContext c) {
    final tp = TextPainter(
      text: TextSpan(
          text: '100%', style: _pct),
      textDirection: Directionality.of(c),
      textScaler: MediaQuery.textScalerOf(c),
      maxLines: 1,
    )..layout();
    final w = tp.width.ceilToDouble();
    tp.dispose();
    return w + S.x2 + StrapIcon.widthFor(_band) + S.x1;
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final battery = deviceBatteryOf(c);
    var connected = false;
    try {
      connected = c.select<AppState, bool>((a) => a.isConnected);
    } catch (_) {}
    final syncing = syncingNowOf(c);
    return Pressable(
      semanticLabel: [
        'Device settings',
        if (battery != null) 'battery ${battery.$1.round()}%',
        connected ? 'connected' : 'not connected',
      ].join(', '),
      onTap: () {
        // The band's own page; it offers pairing when there is no band.
        Navigator.of(c).push(
            themedRoute((_) => const DeviceSettings(), name: 'DeviceSettings'));
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (battery != null) ...[
          // Never a colour: a blue percentage read as a link.
          Text('${battery.$1.round()}%',
              style: _pct.copyWith(color: p.ink)),
          const SizedBox(width: S.x2),
        ],
        StrapIcon(
          color: p.ink,
          height: _band,
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

/// Minutes after its newest reading that the band's data still counts as
/// caught up when nothing is syncing.
const kCaughtUpMinutes = 30;

enum SyncBarState { catchingUp, caughtUp, behind }

SyncBarState syncBarStateOf({
  required bool syncing,
  required DateTime at,
  required DateTime now,
}) =>
    syncing
        ? SyncBarState.catchingUp
        : now.difference(at).inMinutes < kCaughtUpMinutes
            ? SyncBarState.caughtUp
            : SyncBarState.behind;

/// How long "Caught up" stays once a catch-up has landed, before the bar
/// folds away.
const kCaughtUpShown = Motion.linger;

/// The sync bar as Home shows it, 8 under the header: while the band's data
/// is catching up, and while it is not up to date (both worth a tap). "Caught
/// up" shows only for [kCaughtUpShown] after a catch-up lands, then the bar
/// folds away; opening Home on data that is already current shows nothing.
class HomeSyncBanner extends StatefulWidget {
  final SyncBarState state;
  final String syncedTo;
  final VoidCallback? onTap;
  const HomeSyncBanner({
    super.key,
    required this.state,
    required this.syncedTo,
    this.onTap,
  });

  @override
  State<HomeSyncBanner> createState() => _HomeSyncBannerState();
}

class _HomeSyncBannerState extends State<HomeSyncBanner> {
  bool _landed = false;
  Timer? _fold;

  @override
  void didUpdateWidget(HomeSyncBanner old) {
    super.didUpdateWidget(old);
    if (old.state == SyncBarState.catchingUp &&
        widget.state == SyncBarState.caughtUp) {
      _landed = true;
      _fold?.cancel();
      _fold = Timer(kCaughtUpShown, () {
        if (mounted) setState(() => _landed = false);
      });
    }
  }

  @override
  void dispose() {
    _fold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final show = widget.state != SyncBarState.caughtUp || _landed;
    return AnimatedSize(
      duration: motion(c, Motion.slow),
      curve: Ease.standard,
      alignment: Alignment.topCenter,
      child: show
          ? Padding(
              padding: const EdgeInsets.only(top: S.x2),
              child: HomeSyncBar(
                  state: widget.state,
                  syncedTo: widget.syncedTo,
                  onTap: widget.onTap),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// The black bar under Home's header: whether the band's data has caught up,
/// and the time it is synced to, laid out on its reference: 56 tall, radius
/// 10, 12 in from each end. A 16 cloud in ink3, 12 to the state in white
/// caps; on the right SYNCED TO over the time (amber while catching up),
/// both flush right, 8 to the mark: a turning 24 ring, or a 16 check.
class HomeSyncBar extends StatelessWidget {
  final SyncBarState state;

  /// The newest reading's time, as the user reads clocks ("5:09 PM"), or a day
  /// and time when it is not today's.
  final String syncedTo;
  final VoidCallback? onTap;
  const HomeSyncBar({
    super.key,
    required this.state,
    required this.syncedTo,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final (word, tone) = switch (state) {
      SyncBarState.catchingUp => ('DATA CATCHING UP', C.amber),
      SyncBarState.caughtUp => ('DATA CAUGHT UP', DC.ink),
      SyncBarState.behind => ('DATA NOT UP TO DATE', DC.ink2),
    };
    final caps = F.dLabel.copyWith(color: DC.pure);
    return Pressable(
      onTap: onTap,
      semanticLabel: '${word.toLowerCase()}, synced to $syncedTo',
      child: Container(
        constraints: const BoxConstraints(minHeight: S.x12 + S.x2),
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
        decoration: const BoxDecoration(
          color: DC.syncBar,
          borderRadius: BorderRadius.all(Radius.circular(R.md + S.half)),
        ),
        child: LayoutBuilder(
          builder: (c, box) => Row(children: [
            const Icon(LucideIcons.cloud, size: I.md, color: DC.ink3),
            const SizedBox(width: S.x3),
            // The state takes what the time leaves, and only shortens once
            // the time has had its half.
            Expanded(
              child: Text(word,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: caps),
            ),
            const SizedBox(width: S.x2),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * .5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('SYNCED TO', textAlign: TextAlign.end, style: caps),
                  const SizedBox(height: S.half),
                  Text(syncedTo.toUpperCase(),
                      textAlign: TextAlign.end,
                      style: F.num(caps).copyWith(
                          color: tone,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .3)),
                ],
              ),
            ),
            const SizedBox(width: S.x2),
            switch (state) {
              SyncBarState.catchingUp =>
                const SizedBox.square(dimension: I.lg, child: _SyncRing()),
              SyncBarState.caughtUp => const SizedBox(
                  width: I.lg,
                  child: Icon(LucideIcons.check, size: I.md, color: C.optimal)),
              SyncBarState.behind => const SizedBox(
                  width: I.lg,
                  child: Icon(LucideIcons.refreshCw, size: I.sm, color: DC.ink3)),
            },
          ]),
        ),
      ),
    );
  }
}

/// The catching-up mark: a white quarter turning on a dark ring, 24 across,
/// 2 thick. Still where motion is off.
class _SyncRing extends StatefulWidget {
  const _SyncRing();

  @override
  State<_SyncRing> createState() => _SyncRingState();
}

class _SyncRingState extends State<_SyncRing>
    with SingleTickerProviderStateMixin {
  // A turn restarts the next, as HomeSyncArrow does; the gate stops it.
  late final AnimationController _t =
      AnimationController(vsync: this, duration: Motion.roll)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _t.forward(from: 0);
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
  Widget build(BuildContext c) => RotationTransition(
        turns: _t,
        child: const CustomPaint(painter: _SyncRingPaint()),
      );
}

class _SyncRingPaint extends CustomPainter {
  const _SyncRingPaint();

  @override
  void paint(Canvas canvas, Size size) {
    const w = S.x1 * .75;
    final box = (Offset.zero & size).deflate(w / 2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    canvas.drawOval(box, line..color = DC.syncTrack);
    canvas.drawArc(box, -1.5708, 1.75, false,
        line
          ..color = DC.pure
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_SyncRingPaint old) => false;
}
