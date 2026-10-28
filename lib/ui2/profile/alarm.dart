// The band alarm screen — Google Clock style multi-alarm list, repeat scheduling,
// system alarm sync, and instant strap confirmation.

import 'dart:async';
import 'dart:math' as math;

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
        AlarmArmState.confirmed => C.green,
        AlarmArmState.pending => C.blue,
        AlarmArmState.unknown => C.orange,
        AlarmArmState.none => C.blue,
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

  Future<void> _editAlarm(BuildContext context, AlarmItem alarm) async {
    final mgr = widget.alarmManager;
    if (mgr == null) return;

    TimeOfDay pickedTime = TimeOfDay(hour: alarm.hour, minute: alarm.minute);
    Set<int> selectedDays = Set.from(alarm.days);
    final labelCtrl = TextEditingController(text: alarm.label);
    int smartMin = alarm.smartWindowMinutes;
    var mode = alarm.mode;
    var on = alarm.enabled;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final p = P.of(ctx);
          return Container(
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xxl)),
            ),
            padding: EdgeInsets.fromLTRB(
              S.x4,
              S.x4,
              S.x4,
              MediaQuery.of(ctx).viewInsets.bottom + S.x6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.ink3.withValues(alpha: 0.3),
                        borderRadius: R.rPill,
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('EDIT ALARM', style: F.caps.copyWith(color: p.ink)),
                      Pressable(
                        semanticLabel: 'Delete this alarm',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await mgr.deleteAlarm(alarm.id);
                        },
                        child: Icon(LucideIcons.trash2,
                            size: I.lg, color: p.on(C.red)),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x3),
                  // Time Picker Display
                  Center(
                    child: Pressable(
                      onTap: () async {
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: pickedTime,
                        );
                        if (t != null) {
                          setSheetState(() => pickedTime = t);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: S.x6, vertical: S.x4),
                        decoration: BoxDecoration(
                          color: p.wash(C.blue),
                          borderRadius: R.rMd,
                        ),
                        child: Text(
                          formatClock(pickedTime.hour, pickedTime.minute),
                          style: F.n48.copyWith(
                            color: C.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x4),
                  // Recurrence preset chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildPresetChip(
                          'Ring once',
                          selectedDays.isEmpty,
                          () => setSheetState(() => selectedDays.clear()),
                          p,
                        ),
                        const SizedBox(width: S.x2),
                        _buildPresetChip(
                          'Weekdays',
                          selectedDays.length == 5 &&
                              !selectedDays.contains(6) &&
                              !selectedDays.contains(7),
                          () => setSheetState(
                              () => selectedDays = {1, 2, 3, 4, 5}),
                          p,
                        ),
                        const SizedBox(width: S.x2),
                        _buildPresetChip(
                          'Every day',
                          selectedDays.length == 7,
                          () => setSheetState(
                              () => selectedDays = {1, 2, 3, 4, 5, 6, 7}),
                          p,
                        ),
                        const SizedBox(width: S.x2),
                        _buildPresetChip(
                          'Custom',
                          selectedDays.isNotEmpty &&
                              selectedDays.length != 5 &&
                              selectedDays.length != 7,
                          null,
                          p,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x4),
                  // Day circles row: S M T W T F S
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDayCircle(7, 'S', selectedDays, setSheetState, p),
                      _buildDayCircle(1, 'M', selectedDays, setSheetState, p),
                      _buildDayCircle(2, 'T', selectedDays, setSheetState, p),
                      _buildDayCircle(3, 'W', selectedDays, setSheetState, p),
                      _buildDayCircle(4, 'T', selectedDays, setSheetState, p),
                      _buildDayCircle(5, 'F', selectedDays, setSheetState, p),
                      _buildDayCircle(6, 'S', selectedDays, setSheetState, p),
                    ],
                  ),
                  const SizedBox(height: S.x4),
                  OsTextField(
                    controller: labelCtrl,
                    label: 'Alarm Label',
                    hint: 'Wake up',
                  ),
                  const SizedBox(height: S.x4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Alarm on',
                          style: F.body.copyWith(
                              fontWeight: FontWeight.w600, color: p.ink)),
                      AppSwitch(on, (v) => setSheetState(() => on = v),
                          semanticLabel: 'Alarm on'),
                    ],
                  ),
                  const SizedBox(height: S.x4),
                  // What the alarm waits for.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Alarm mode',
                              style: F.body.copyWith(
                                  fontWeight: FontWeight.w600, color: p.ink)),
                          Text(mode.blurb, style: F.cap.copyWith(color: p.ink3)),
                        ],
                      ),
                      TextAction(mode.title, () async {
                        final m = await openAlarmModeSheet(ctx, current: mode);
                        if (m != null) setSheetState(() => mode = m);
                      }),
                    ],
                  ),
                  const SizedBox(height: S.x4),
                  // Smart wake option: for an exact alarm only; the goal
                  // modes have a window of their own.
                  if (mode == AlarmMode.exact)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Smart wake early window',
                              style: F.body.copyWith(
                                  fontWeight: FontWeight.w600, color: p.ink)),
                          Text('Buzzes during light sleep',
                              style: F.cap.copyWith(color: p.ink3)),
                        ],
                      ),
                      DropdownButton<int>(
                        value: smartMin,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Off')),
                          DropdownMenuItem(value: 15, child: Text('15 min early')),
                          DropdownMenuItem(value: 30, child: Text('30 min early')),
                          DropdownMenuItem(value: 45, child: Text('45 min early')),
                        ],
                        onChanged: (v) {
                          if (v != null) setSheetState(() => smartMin = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x4),
                  const SizedBox(height: S.x6),
                  BigButton(
                    'Save Alarm',
                    icon: LucideIcons.check,
                    color: C.blue,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final updated = alarm.copyWith(
                        hour: pickedTime.hour,
                        minute: pickedTime.minute,
                        label: labelCtrl.text.trim().isNotEmpty
                            ? labelCtrl.text.trim()
                            : 'Alarm',
                        days: selectedDays,
                        smartWindowMinutes: smartMin,
                        mode: mode,
                        enabled: on,
                      );
                      await mgr.updateAlarm(updated);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresetChip(
      String label, bool selected, VoidCallback? onTap, P p) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
        decoration: BoxDecoration(
          color: selected ? C.blue : p.wash(p.ink3),
          borderRadius: R.rMd,
        ),
        child: Text(
          label,
          style: F.cap.copyWith(
            color: selected ? p.inkOn(C.blue) : p.ink,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildDayCircle(
      int dayNumber, String label, Set<int> days, StateSetter setSheetState, P p) {
    final active = days.contains(dayNumber);
    return Pressable(
      onTap: () {
        setSheetState(() {
          if (active) {
            days.remove(dayNumber);
          } else {
            days.add(dayNumber);
          }
        });
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? C.blue : p.wash(p.ink3),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: F.cap.copyWith(
            color: active ? p.inkOn(C.blue) : p.ink2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
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
        padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x4),
        decoration: BoxDecoration(
          color: Color.alphaBlend(p.ink.withValues(alpha: .2), p.bg),
          borderRadius: BorderRadius.circular(S.x5),
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
                        color: p.ink3, fontWeight: FontWeight.w800, letterSpacing: .9)),
              ],
            ]),
            const SizedBox(height: S.x3),
            Row(children: [
              Expanded(
                child: Text(formatClock(alarm.hour, alarm.minute),
                    style: F.n34.copyWith(
                        color: p.ink, fontWeight: FontWeight.w700, letterSpacing: .4)),
              ),
              Transform.rotate(
                  angle: math.pi / 2,
                  child: BoldChevron(left: false, height: S.x4, color: p.ink)),
            ]),
            const SizedBox(height: S.x3),
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: () => _pickMode(c, alarm),
                semanticLabel: 'Alarm mode ${alarm.mode.title}',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: S.x3, vertical: S.x2 + S.half),
                  decoration: BoxDecoration(
                    color: p.ink.withValues(alpha: .1),
                    borderRadius: R.rSm,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.vibrate, size: I.md, color: p.ink),
                    const SizedBox(width: S.x2),
                    Text(alarm.mode.title,
                        style: F.caps.copyWith(
                            color: p.ink, fontWeight: FontWeight.w800, letterSpacing: .9)),
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
              const SizedBox(height: S.x8),
              if (fired != null && calendarDaysBetween(fired, now) == 0) ...[
                Center(
                  child: Pill(
                      l?.alarmFiredAt(AlarmScreenView._hhmm(fired)) ??
                          'Fired at ${AlarmScreenView._hhmm(fired)}',
                      C.green,
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
                      borderRadius: R.rPill,
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
                        const BoxDecoration(color: C.orange, shape: BoxShape.circle),
                    child: Text('!',
                        style: F.body.copyWith(
                            color: C.char, fontWeight: FontWeight.w900, height: 1)),
                  ),
                  const SizedBox(width: S.x3),
                  Text('You have unscheduled days',
                      style: F.body.copyWith(
                          color: C.orange, fontWeight: FontWeight.w500)),
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
                    color: C.blue,
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
                    color: C.red,
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
