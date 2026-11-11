// The band alarm screen — Google Clock style multi-alarm list, repeat scheduling,
// system alarm sync, and instant strap confirmation.

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart' show calendarDaysBetween;
import '../../l10n/app_localizations.dart';
import '../../models/alarm_item.dart';
import '../../state/alarm_manager.dart';
import '../../state/alarm_mode.dart';
import '../../state/alarm_schedule.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart' show formatClock;
import '../screens/home_screen.dart' show go, weekdayShortName;
import '../screens/alarm_mode_sheet.dart' show openAlarmModeSheet;
import '../screens/journal_compose.dart' show OsTextField;
import '../screens/metric_detail.dart' show detailLinkRow;
import '../ui2.dart';
import 'profile.dart' show SetRow;

/// What we actually know about the armed alarm.
enum AlarmArmState {
  /// Nothing armed.
  none,

  /// Written to the band; its confirmation event may still be in flight.
  pending,

  /// The band confirmed receipt of the alarm.
  confirmed,

  /// Armed, but unconfirmed.
  unknown,
}

/// The armed instant and what we know about it. Shared by this screen and
/// Home's door so the two can never disagree. Reading it arms nothing.
(DateTime?, AlarmArmState) alarmArmOf(AppState app) {
  final plan = app.alarmManager.computeNextArmedPlan(DateTime.now());
  if (plan != null) {
    return (
      plan.time,
      app.alarmConfirmed
          ? AlarmArmState.confirmed
          : app.alarmPending
              ? AlarmArmState.pending
              : AlarmArmState.unknown,
    );
  }
  final epoch = app.alarmEpoch;
  if (epoch == null) return (null, AlarmArmState.none);
  return (
    DateTime.fromMillisecondsSinceEpoch(epoch * 1000),
    app.alarmConfirmed
        ? AlarmArmState.confirmed
        : app.alarmPending
            ? AlarmArmState.pending
            : AlarmArmState.unknown,
  );
}

/// Home's door onto the alarm: the next armed day and time plus its state,
/// or "Set an alarm".
Widget alarmDoor(BuildContext c, DateTime? at, AlarmArmState state,
        {DateTime? now}) =>
    _AlarmTick.wrap(at, now, (n) {
      final l = AppLocalizations.of(c);
      final String sub;
      if (at == null) {
        sub = l?.alarmSetAnAlarm ?? 'Set an alarm';
      } else {
        final what = at.isAfter(n)
            ? AlarmScreenView._localizedStateLabel(c, state)
            : (l?.alarmInThePast ??
                'In the past — it has already fired or been missed');
        sub = '${AlarmScreenView._dayAndTime(c, at)} · $what';
      }
      return detailLinkRow(c, LucideIcons.alarmClock,
          l?.alarmNavTitle ?? 'Alarm', sub, () => go(c, const AlarmScreen()));
    });

/// The same facts as [alarmDoor], as an "At a glance" tile.
Widget alarmGlanceCard(BuildContext c, DateTime? at, AlarmArmState state,
        {DateTime? now}) =>
    _AlarmTick.wrap(at, now, (n) {
      final l = AppLocalizations.of(c);
      return SignalCard(
        LucideIcons.alarmClock,
        AlarmScreenView._stateColor(state),
        l?.alarmNavTitle ?? 'Alarm',
        at == null
            ? (l?.alarmStateNotSet ?? 'Not set')
            : AlarmScreenView._hhmm(at),
        sub: at == null
            ? (l?.alarmSetAnAlarm ?? 'Set an alarm')
            : at.isAfter(n)
                ? '${AlarmScreenView._whichDay(c, at, n)} · '
                    '${AlarmScreenView._localizedStateLabel(c, state)}'
                : (l?.alarmGlanceInThePast ?? 'Fired or missed'),
        onTap: () => go(c, const AlarmScreen()),
      );
    });

/// How long until [at] rings, read off [now]: "Rings in 7 h 32 min". Rounded
/// up to the minute, so it never says "0 min" while a minute is left.
String alarmCountdownText(DateTime at, DateTime now) {
  final secs = at.difference(now).inSeconds;
  if (secs <= 0) return 'Ringing now';
  final m = (secs / 60).ceil();
  if (m < 60) return 'Rings in $m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? 'Rings in $h h' : 'Rings in $h h $r min';
}

/// The time left until the next alarm, kept current to the minute; "No alarm
/// set" without one. On top of My Schedule and on the start-sleep card.
class AlarmCountdown extends StatefulWidget {
  final DateTime? at;
  final TextStyle style;
  final TextAlign align;

  /// The clock, for a test; the real one when null (and then it ticks).
  final DateTime? now;

  const AlarmCountdown(this.at,
      {super.key, required this.style, this.align = TextAlign.start, this.now});

  @override
  State<AlarmCountdown> createState() => _AlarmCountdownState();
}

class _AlarmCountdownState extends State<AlarmCountdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _next();
  }

  /// Wake on the next whole minute, when the figure changes.
  void _next() {
    _t?.cancel();
    if (widget.now != null || widget.at == null) return;
    final now = clock.now();
    final edge = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _t = Timer(edge.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _next();
    });
  }

  @override
  void didUpdateWidget(AlarmCountdown old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at) _next();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final at = widget.at;
    return Text(
      at == null
          ? 'No alarm set'
          : alarmCountdownText(at, widget.now ?? clock.now()),
      textAlign: widget.align,
      style: widget.style,
    );
  }
}

class _AlarmTick extends StatefulWidget {
  final DateTime? at;
  final Widget Function(DateTime now) build;

  const _AlarmTick(this.at, this.build);

  static Widget wrap(DateTime? at, DateTime? now,
          Widget Function(DateTime now) build) =>
      now != null ? build(now) : _AlarmTick(at, build);

  @override
  State<_AlarmTick> createState() => _AlarmTickState();
}

class _AlarmTickState extends State<_AlarmTick> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_AlarmTick old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at) _schedule();
  }

  void _schedule() {
    final now = clock.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final at = widget.at;
    final next =
        at != null && at.isAfter(now) && at.isBefore(midnight) ? at : midnight;
    _t?.cancel();
    _t = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  Widget build(BuildContext c) => widget.build(clock.now());

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final (armedAt, state) = alarmArmOf(app);
    return AlarmScreenView(
      armedAt: armedAt,
      state: state,
      firedAt: app.alarmFiredAt,
      connected: app.isConnected,
      schedule: app.alarmSchedule,
      alarmManager: app.alarmManager,
      onToggleDay: (weekday, enabled) =>
          app.setScheduleDay(weekday: weekday, enabled: enabled),
      onSetDayTime: (weekday, hour, minute) =>
          app.setScheduleDay(weekday: weekday, hour: hour, minute: minute),
      onSetSmartWindow: (weekday, minutes) =>
          app.setScheduleDay(weekday: weekday, smartWindowMinutes: minutes),
      onTest: app.testAlarmBuzz,
      onCancel: app.disableAlarm,
    );
  }
}

class AlarmScreenView extends StatefulWidget {
  final DateTime? armedAt;
  final AlarmArmState state;
  final bool connected;
  final DateTime? firedAt;
  final DateTime? now;
  final List<AlarmScheduleEntry> schedule;
  final AlarmManager? alarmManager;

  final Future<void> Function(int weekday, bool enabled)? onToggleDay;
  final Future<void> Function(int weekday, int hour, int minute)? onSetDayTime;
  final Future<void> Function(int weekday, int minutes)? onSetSmartWindow;
  final Future<void> Function()? onTest, onCancel;

  const AlarmScreenView({
    super.key,
    this.armedAt,
    this.state = AlarmArmState.none,
    this.connected = false,
    this.firedAt,
    this.now,
    this.schedule = const [],
    this.alarmManager,
    this.onToggleDay,
    this.onSetDayTime,
    this.onSetSmartWindow,
    this.onTest,
    this.onCancel,
  });

  @override
  State<AlarmScreenView> createState() => _AlarmScreenViewState();

  @visibleForTesting
  static String stateLabel(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => 'Confirmed',
        AlarmArmState.pending => 'Waiting',
        AlarmArmState.unknown => 'Not confirmed',
        AlarmArmState.none => 'Not set',
      };

  static String _localizedStateLabel(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed => l?.alarmStateConfirmed ?? 'Confirmed',
      AlarmArmState.pending => l?.alarmStateWaiting ?? 'Waiting',
      AlarmArmState.unknown => l?.alarmStateNotConfirmed ?? 'Not confirmed',
      AlarmArmState.none => l?.alarmStateNotSet ?? 'Not set',
    };
  }

  static Color _stateColor(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => C.optimal,
        AlarmArmState.pending => C.dialStrain,
        AlarmArmState.unknown => C.strainDown,
        AlarmArmState.none => C.dialStrain,
      };

  static IconData _stateIcon(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => LucideIcons.badgeCheck,
        AlarmArmState.pending => LucideIcons.loader,
        AlarmArmState.unknown => LucideIcons.circleHelp,
        AlarmArmState.none => LucideIcons.alarmClock,
      };

  static String _hhmm(DateTime d) => _hhmmOf(d.hour, d.minute);

  static String _hhmmOf(int hour, int minute) => formatClock(hour, minute);

  static String _dayAndTime(BuildContext c, DateTime at) =>
      '${weekdayShortName(at.weekday, AppLocalizations.of(c))} ${_hhmm(at)}';

  static String _whichDay(BuildContext c, DateTime d, DateTime now) {
    final l = AppLocalizations.of(c);
    final days = calendarDaysBetween(now, d);
    if (days < 0) {
      return l?.alarmInThePast ??
          'In the past — it has already fired or been missed';
    }
    if (days == 0) return l?.alarmLaterToday ?? 'Later today';
    if (days == 1) return l?.alarmTomorrow ?? 'Tomorrow';
    return l?.alarmInDays(days) ?? 'In $days days';
  }
}

class _AlarmScreenViewState extends State<AlarmScreenView> {
  /// The options under the schedule: phone clock, shake, test and cancel.
  bool _options = false;

  /// The alarm's own sheet: the time as the page's one big number (tap to
  /// change it) with how long until it rings, how often it repeats, then its
  /// label, what it waits for and whether it is on, grouped as the settings
  /// rows are. Save is the sheet's one primary action; deleting is a quiet
  /// coral action under it, never a trash can beside the title.
  Future<void> _editAlarm(BuildContext context, AlarmItem alarm) async {
    final mgr = widget.alarmManager;
    if (mgr == null) return;

    var picked = TimeOfDay(hour: alarm.hour, minute: alarm.minute);
    var days = Set<int>.from(alarm.days);
    final labelCtrl = TextEditingController(text: alarm.label);
    var smartMin = alarm.smartWindowMinutes;
    var mode = alarm.mode;
    var on = alarm.enabled;
    const early = [0, 15, 30, 45];

    await AppSheet.open<void>(
      context,
      scroll: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final p = P.of(ctx);
          final l = AppLocalizations.of(ctx);
          // Rings in…, for what is on screen now: the next time this time and
          // these days come round, read as the alarm itself would.
          final next = AlarmItem(
            id: alarm.id,
            hour: picked.hour,
            minute: picked.minute,
            label: '',
            enabled: true,
            days: days,
          ).nextOccurrence(clock.now());
          final preset = days.isEmpty
              ? 0
              : (days.length == 5 && !days.contains(6) && !days.contains(7))
                  ? 1
                  : days.length == 7
                      ? 2
                      : -1;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              S.gutter,
              S.x3,
              S.gutter,
              MediaQuery.viewInsetsOf(ctx).bottom +
                  MediaQuery.paddingOf(ctx).bottom +
                  S.x5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: S.x10,
                    height: S.x1,
                    decoration:
                        BoxDecoration(color: p.line, borderRadius: R.rPill),
                  ),
                ),
                const SizedBox(height: S.x3),
                Semantics(
                  header: true,
                  child: Text('Edit alarm', style: F.t2.copyWith(color: p.ink)),
                ),
                // The time itself is the control: no box drawn round it.
                Pressable(
                  semanticLabel:
                      '${formatClock(picked.hour, picked.minute)}. Change the time',
                  onTap: () async {
                    final t = await pickTime(ctx,
                        initial: picked, title: 'Alarm time');
                    if (t != null) setS(() => picked = t);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x1),
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatClock(picked.hour, picked.minute),
                            style: F.n80.copyWith(color: p.ink),
                          ),
                        ),
                        Text(
                          next == null
                              ? 'Not scheduled'
                              : alarmCountdownText(next, clock.now()),
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: S.x3),
                Text('REPEAT', style: F.over.copyWith(color: p.ink3)),
                const SizedBox(height: S.x2),
                RangeSegments(
                  const ['Once', 'Weekdays', 'Every day'],
                  preset,
                  (i) => setS(() => days = switch (i) {
                        0 => <int>{},
                        1 => {1, 2, 3, 4, 5},
                        _ => {1, 2, 3, 4, 5, 6, 7},
                      }),
                  width: null,
                ),
                const SizedBox(height: S.x2),
                Row(
                  children: [
                    for (final (n, d) in const [
                      (7, 'S'),
                      (1, 'M'),
                      (2, 'T'),
                      (3, 'W'),
                      (4, 'T'),
                      (5, 'F'),
                      (6, 'S'),
                    ])
                      Expanded(
                        child: Pressable(
                          semanticLabel: const {
                            1: 'Monday',
                            2: 'Tuesday',
                            3: 'Wednesday',
                            4: 'Thursday',
                            5: 'Friday',
                            6: 'Saturday',
                            7: 'Sunday',
                          }[n]!,
                          onTap: () => setS(() {
                            days.contains(n) ? days.remove(n) : days.add(n);
                          }),
                          child: Center(
                            child: Container(
                              width: S.x10,
                              height: S.x10,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: days.contains(n)
                                    ? p.fill(C.dialStrain)
                                    : p.card2,
                              ),
                              child: Text(
                                d,
                                style: F.cap.copyWith(
                                  color: days.contains(n)
                                      ? p.inkOn(p.fill(C.dialStrain))
                                      : p.ink2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: S.x3),
                OsTextField(
                  controller: labelCtrl,
                  label: 'Alarm label',
                  hint: 'Wake up',
                ),
                const SizedBox(height: S.x3),
                Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Column(
                    children: [
                      SetRow(
                        LucideIcons.power,
                        C.dialStrain,
                        'Alarm on',
                        chevron: false,
                        trailing: AppSwitch(
                            on, (v) => setS(() => on = v),
                            semanticLabel: 'Alarm on'),
                      ),
                      SetRow(
                        LucideIcons.alarmClock,
                        C.dialStrain,
                        'Alarm mode',
                        value: mode.title,
                        onTap: () async {
                          final m =
                              await openAlarmModeSheet(ctx, current: mode);
                          if (m != null) setS(() => mode = m);
                        },
                      ),
                      // Smart wake is for an exact alarm only; the goal modes
                      // have a window of their own.
                      if (mode == AlarmMode.exact)
                        SetRow(
                          LucideIcons.waves,
                          C.dialStrain,
                          'Smart wake',
                          value: smartMin == 0 ? 'Off' : '$smartMin min',
                          onTap: () async {
                            final m = await _pickSmartWake(ctx, smartMin, early);
                            if (m != null) setS(() => smartMin = m);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: S.x4),
                BigButton(
                  l?.actionSave ?? 'Save alarm',
                  icon: LucideIcons.check,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await mgr.updateAlarm(alarm.copyWith(
                      hour: picked.hour,
                      minute: picked.minute,
                      label: labelCtrl.text.trim().isNotEmpty
                          ? labelCtrl.text.trim()
                          : 'Alarm',
                      days: days,
                      smartWindowMinutes: smartMin,
                      mode: mode,
                      enabled: on,
                    ));
                  },
                ),
                Center(
                  child: TextAction(
                    'Delete alarm',
                    () async {
                      Navigator.pop(ctx);
                      await mgr.deleteAlarm(alarm.id);
                    },
                    icon: LucideIcons.trash2,
                    tone: ButtonTone.danger,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    labelCtrl.dispose();
  }

  /// How early smart wake may buzz, from the editor's one-line row.
  Future<int?> _pickSmartWake(BuildContext c, int current, List<int> options) {
    final p = P.of(c);
    return AppSheet.show<int>(
      c,
      title: 'SMART WAKE',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Buzzes during light sleep, up to this long before the time.',
            style: F.cap.copyWith(color: p.ink3, height: 1.4)),
        const SizedBox(height: S.x2),
        for (final m in options)
          Pressable(
            onTap: () => Navigator.of(c).pop(m),
            semanticLabel: m == 0 ? 'Off' : '$m minutes',
            child: SizedBox(
              height: S.x12,
              child: Row(children: [
                Expanded(
                  child: Text(m == 0 ? 'Off' : '$m min',
                      style: F.body.copyWith(color: p.ink)),
                ),
                if (m == current)
                  Icon(LucideIcons.check, size: I.md, color: p.ink),
              ]),
            ),
          ),
      ]),
    );
  }

  /// "Thu 7 Nov" for a skip that is still ahead, else null.
  String? _skippedLabel(AlarmItem a) {
    final key = a.skipDay;
    if (key == null) return null;
    final d = DateTime.tryParse(key);
    final now = widget.now ?? clock.now();
    if (d == null || d.isBefore(DateTime(now.year, now.month, now.day))) {
      return null;
    }
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
      'Oct', 'Nov', 'Dec'];
    return '${wd[d.weekday - 1]} ${d.day} ${mo[d.month - 1]}';
  }

  /// A card's switch. Turning off a REPEATING alarm asks first: skip only its
  /// next morning, or turn the whole schedule off.
  Future<void> _toggle(BuildContext c, AlarmItem alarm, bool on) async {
    final mgr = widget.alarmManager;
    if (mgr == null) return;
    if (on || alarm.isRingOnce) {
      await mgr.toggleAlarm(alarm.id, on);
      if (on) await mgr.clearSkip(alarm.id);
      return;
    }
    final now = widget.now ?? clock.now();
    final next = alarm.nextUnskipped(now);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final skipText = next != null &&
            next.year == tomorrow.year &&
            next.month == tomorrow.month &&
            next.day == tomorrow.day
        ? 'Skip tomorrow'
        : next == null
            ? null
            : 'Skip ${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][next.weekday - 1]}';
    final pick = await AppSheet.show<String>(
      c,
      title: 'TURN OFF RECURRING ALARM?',
      child: _ChoiceList([
        if (skipText != null) ('skip', skipText),
        ('off', 'Turn off recurring alarm'),
        ('cancel', 'Cancel'),
      ]),
    );
    if (pick == 'skip') await mgr.skipNext(alarm.id, now);
    if (pick == 'off') await mgr.toggleAlarm(alarm.id, false);
  }

  Future<void> _createNewAlarm(BuildContext context) async {
    final mgr = widget.alarmManager;
    if (mgr == null) return;
    final newAlarm = AlarmItem(
      id: 'alarm_${DateTime.now().millisecondsSinceEpoch}',
      hour: 7,
      minute: 0,
      label: 'Wake up',
      enabled: true,
      days: {1, 2, 3, 4, 5},
    );
    await mgr.addAlarm(newAlarm);
    if (context.mounted) {
      await _editAlarm(context, newAlarm);
    }
  }

  /// The weekdays an enabled repeating alarm covers.
  static Set<int> _covered(List<AlarmItem> alarms) => {
        for (final a in alarms)
          if (a.enabled) ...a.days,
      };

  static const _dayNames = {
    1: 'MON',
    2: 'TUE',
    3: 'WED',
    4: 'THU',
    5: 'FRI',
    6: 'SAT',
    7: 'SUN',
  };

  Future<void> _pickMode(BuildContext c, AlarmItem alarm) async {
    final mgr = widget.alarmManager;
    final mode = await openAlarmModeSheet(c, current: alarm.mode);
    if (mode == null || mgr == null) return;
    await mgr.updateAlarm(alarm.copyWith(mode: mode));
  }

  /// One schedule: the days it runs, its time, and what it waits for.
  Widget _scheduleCard(BuildContext c, P p, AlarmItem alarm) {
    final dim = alarm.enabled ? 1.0 : .5;
    final days = alarm.days.toList()..sort();
    final names = days.isEmpty
        ? const ['ONE NIGHT']
        : [for (final d in days) _dayNames[d] ?? ''];
    return Pressable(
      onTap: () => _editAlarm(c, alarm),
      semanticLabel:
          '${formatClock(alarm.hour, alarm.minute)}, ${alarm.repeatSummary()}, ${alarm.mode.title}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: R.rLg,
          border: Border.all(color: p.ink.withValues(alpha: .08)),
        ),
        child: Opacity(
          opacity: dim,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (var i = 0; i < names.length; i++) ...[
                if (i > 0)
                  Container(
                    width: S.x1,
                    height: S.x1,
                    margin: const EdgeInsets.symmetric(horizontal: S.x2),
                    decoration: BoxDecoration(
                        color: p.ink3.withValues(alpha: .7), shape: BoxShape.circle),
                  ),
                Text(names[i],
                    style: F.over.copyWith(
                        color: p.ink3, letterSpacing: .6)),
              ],
            ]),
            const SizedBox(height: S.x2),
            Row(children: [
              Expanded(
                child: Text(formatClock(alarm.hour, alarm.minute),
                    style: F.n24.copyWith(
                        color: p.ink, fontWeight: FontWeight.w700)),
              ),
              AppSwitch(alarm.enabled, (v) => _toggle(c, alarm, v),
                  semanticLabel: 'Alarm ${formatClock(alarm.hour, alarm.minute)} on'),
            ]),
            if (alarm.enabled ? _skippedLabel(alarm) : null case final skipped?) ...[
              const SizedBox(height: S.x1),
              Row(children: [
                Text('Skipping $skipped',
                    style: F.cap.copyWith(color: p.ink2)),
                const SizedBox(width: S.x2),
                TextAction('Undo', () => widget.alarmManager?.clearSkip(alarm.id)),
              ]),
            ],
            const SizedBox(height: S.x2),
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: () => _pickMode(c, alarm),
                semanticLabel: 'Alarm mode ${alarm.mode.title}',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: S.x2 + S.half, vertical: S.x1),
                  decoration: BoxDecoration(
                    color: p.ink.withValues(alpha: .07),
                    borderRadius: R.rSm,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.vibrate, size: I.sm, color: p.ink2),
                    const SizedBox(width: S.x1 + S.half),
                    Text(alarm.mode.title,
                        style: F.over.copyWith(
                            color: p.ink2, letterSpacing: .5)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final at = widget.armedAt;
    final fired = widget.firedAt;
    final now = widget.now ?? DateTime.now();
    final mgr = widget.alarmManager;
    final alarms = mgr?.alarms ?? const <AlarmItem>[];
    final unscheduled = _covered(alarms).length < 7;

    Widget more(IconData icon, String title, String sub, Widget trailing) =>
        Row(children: [
          Icon(icon, size: I.lg, color: p.ink2),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: F.body.copyWith(fontWeight: FontWeight.w600, color: p.ink)),
              Text(sub, style: F.cap.copyWith(color: p.ink3, height: 1.4)),
            ]),
          ),
          const SizedBox(width: S.x2),
          trailing,
        ]);

    return Scaffold(
      backgroundColor: p.bg,
      body: Container(
        decoration: BoxDecoration(
          // The page gradient every tab draws (DESIGN.md §2.1).
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [p.bgTop, p.bg],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x16),
            children: [
              Row(children: [
                Pressable(
                  onTap: () => Navigator.of(c).maybePop(),
                  semanticLabel: 'Back',
                  child: SizedBox(
                    width: S.tap,
                    height: S.tap,
                    child: Center(
                        child: BoldChevron(left: true, height: S.x5, color: p.ink)),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Semantics(
                      header: true,
                      child: Text('MY SCHEDULE',
                          style: F.body.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.8)),
                    ),
                  ),
                ),
                AppSwitch(
                  alarms.any((a) => a.enabled),
                  (v) async {
                    for (final a in alarms) {
                      await mgr?.toggleAlarm(a.id, v);
                    }
                  },
                  semanticLabel: 'Schedule on',
                ),
              ]),
              const SizedBox(height: S.x4),
              // Always here: how long until the next alarm rings.
              AlarmCountdown(
                at != null && at.isAfter(now) ? at : null,
                now: widget.now,
                align: TextAlign.center,
                style: F.num(F.head).copyWith(
                    color: at != null && at.isAfter(now) ? p.ink : p.ink3,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: S.x4),
              if (fired != null && calendarDaysBetween(fired, now) == 0) ...[
                Center(
                  child: Pill(
                      l?.alarmFiredAt(AlarmScreenView._hhmm(fired)) ??
                          'Fired at ${AlarmScreenView._hhmm(fired)}',
                      C.optimal,
                      icon: LucideIcons.alarmClockCheck),
                ),
                const SizedBox(height: S.x6),
              ] else
                const SizedBox(height: S.x8),
              for (final alarm in alarms) ...[
                _scheduleCard(c, p, alarm),
                const SizedBox(height: S.x3),
              ],
              const SizedBox(height: S.x5),
              Center(
                child: Pressable(
                  onTap: () => _createNewAlarm(c),
                  semanticLabel: 'Create schedule',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: S.x8, vertical: S.x4),
                    decoration: BoxDecoration(
                      borderRadius: R.rMd,
                      border: Border.all(color: p.ink, width: S.half),
                    ),
                    child: Text('CREATE SCHEDULE',
                        style: F.body.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6)),
                  ),
                ),
              ),
              if (unscheduled) ...[
                const SizedBox(height: S.x6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: S.x6 + S.x1,
                    height: S.x6 + S.x1,
                    alignment: Alignment.center,
                    decoration:
                        const BoxDecoration(color: C.strainDown, shape: BoxShape.circle),
                    child: Text('!',
                        style: F.body.copyWith(
                            color: C.char, fontWeight: FontWeight.w900, height: 1)),
                  ),
                  const SizedBox(width: S.x3),
                  Text('You have unscheduled days',
                      style: F.body.copyWith(
                          color: C.strainDown, fontWeight: FontWeight.w500)),
                ]),
                const SizedBox(height: S.x5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x3),
                  child: Text(
                    'On unscheduled days, Sleep Planner will default to your '
                    'most recent wake time and set your alarm to off',
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(
                        color: p.ink3, fontWeight: FontWeight.w400, height: 1.4),
                  ),
                ),
              ],
              const SizedBox(height: S.x8),
              Center(
                child: TextAction(
                    _options ? 'Hide alarm options' : 'Alarm options',
                    () => setState(() => _options = !_options)),
              ),
              if (_options) ...[
              const SizedBox(height: S.x4),
              if (at != null) ...[
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l?.alarmNextLabel ?? 'ARMED ON STRAP',
                          style: F.over.copyWith(color: p.ink3)),
                      const SizedBox(height: S.x1),
                      Text(
                          '${AlarmScreenView._dayAndTime(c, at)} · '
                          '${AlarmScreenView._whichDay(c, at, now)}',
                          style: F.body.copyWith(color: p.ink)),
                    ]),
                  ),
                  Pill(
                    AlarmScreenView._localizedStateLabel(c, widget.state),
                    AlarmScreenView._stateColor(widget.state),
                    icon: AlarmScreenView._stateIcon(widget.state),
                  ),
                ]),
                const SizedBox(height: S.x6),
              ],
              more(
                LucideIcons.smartphone,
                'Sync with system alarms',
                mgr?.syncSystem == true && mgr?.systemAlarmTime != null
                    ? 'Next: ${AlarmScreenView._hhmm(mgr!.systemAlarmTime!)}'
                    : 'Auto-sync from your phone\'s Clock app',
                AppSwitch(mgr?.syncSystem ?? false, (v) => mgr?.setSyncSystem(v),
                    semanticLabel: 'Sync with system alarms'),
              ),
              if (mgr != null) ...[
                const SizedBox(height: S.x5),
                more(
                  LucideIcons.vibrate,
                  'Shake to stop',
                  'Shake your wrist a few times to silence the buzz. Needs the '
                      'phone near and connected at alarm time; a double tap on '
                      'the band always works.',
                  AppSwitch(mgr.shakeToStop, (v) => mgr.setShakeToStop(v),
                      semanticLabel: 'Shake to stop'),
                ),
                if (mgr.shakeToStop && mgr.lastShakeWatch != null) ...[
                  const SizedBox(height: S.x1),
                  Padding(
                    padding: const EdgeInsets.only(left: I.lg + S.x4),
                    child: Text('Last alarm: ${mgr.lastShakeWatch}',
                        style: F.cap.copyWith(color: p.ink3)),
                  ),
                ],
              ],
              const SizedBox(height: S.x6),
              if (!widget.connected)
                StatusCard(
                  l?.alarmNotConnectedTitle ?? 'The band is not connected',
                  l?.alarmNotConnectedBody ??
                      'Changing, testing or cancelling the alarm needs a live connection. An alarm that is already set still works; it lives on the band.',
                  icon: LucideIcons.bluetoothOff,
                )
              else ...[
                if (at != null) ...[
                  BigButton(
                    l?.alarmTestTheBuzz ?? 'Test the buzz',
                    icon: LucideIcons.vibrate,
                    color: C.dialStrain,
                    soft: true,
                    onTap: () => _runAction(c, widget.onTest,
                        l?.alarmBuzzingTheBand ?? 'Buzzing the band'),
                  ),
                  const SizedBox(height: S.x3),
                ],
                if (at != null || alarms.any((a) => a.enabled))
                  BigButton(
                    l?.alarmCancelTheAlarm ?? 'Cancel the alarm',
                    icon: LucideIcons.bellOff,
                    color: C.dialStrain,
                    soft: true,
                    onTap: () => _runAction(c, widget.onCancel,
                        l?.alarmCancelled ?? 'Alarm cancelled'),
                  ),
              ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _runAction(
      BuildContext c, Future<void> Function()? action, String ok) async {
    if (action == null) return;
    try {
      await action();
      if (c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(ok)));
      }
    } catch (e) {
      if (c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(
            SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
  }
}

/// Stacked one-line choices in a sheet, hairlines between them; pops the
/// chosen id. Compact rows, like a system action sheet.
class _ChoiceList extends StatelessWidget {
  final List<(String, String)> choices;
  const _ChoiceList(this.choices);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < choices.length; i++) ...[
        if (i > 0) Divider(height: 1, color: p.line),
        Pressable(
          onTap: () => Navigator.of(c).pop(choices[i].$1),
          semanticLabel: choices[i].$2,
          child: SizedBox(
            height: S.x12,
            width: double.infinity,
            child: Center(
              child: Text(choices[i].$2,
                  style: F.body.copyWith(
                      color: choices[i].$1 == 'cancel' ? p.ink2 : p.ink,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    ]);
  }
}
