// SLEEP PLANNER — tonight's recommended bedtime, built backwards from the wake
// time you choose, and the arithmetic behind it.
//
// Nothing here is a new model. Every number comes off `sleep_coach` and
// `sleep_debt` in the cross-day rollup (crossday_pipeline.dart), which already
// computes, from your own nights:
//
//   need       = clamp(baseline + debt + strain bonus − nap credit, 6 h, 11 h)
//   baseline   = your free-night sleep duration, clamped to 7–9.5 h
//   time in bed = need ÷ your usual sleep efficiency
//   bedtime    = wake − time in bed
//
// The planner only swaps "your usual wake time" for the one you pick (or your
// alarm), so bedtime and the breakdown always describe the same night. A part
// the pipeline did not measure is a dash, never a zero.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/alarm_item.dart';
import '../../state/alarm_manager.dart';
import '../../state/alarm_mode.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../profile/alarm.dart' show AlarmArmState, AlarmScreen;
import '../ui2.dart';
import 'alarm_mode_sheet.dart';
import 'home_screen.dart' show alarmArmOfContext, clock, go, repoOf;

/// Tonight's sleep need, its parts, and the time in bed that covers it.
class SleepPlan {
  /// Tonight's need, minutes of SLEEP.
  final int? needMin;

  /// Your personal baseline need (free-night duration, 7–9.5 h).
  final int? baselineMin;

  /// What today's strain added. Null: no strain reading today — not a rest day.
  final int? strainMin;

  /// What today's naps took off. Null: no nap reading today.
  final int? napMin;

  /// Minutes in bed the need takes at your usual efficiency.
  final int? inBedMin;

  /// Your usual wake time, minute of day, as the coach learned it.
  final int? usualWakeMin;

  const SleepPlan({
    this.needMin,
    this.baselineMin,
    this.strainMin,
    this.napMin,
    this.inBedMin,
    this.usualWakeMin,
  });

  /// Sleep debt, as it ACTUALLY landed in [needMin]: the need less every
  /// other part. The pipeline clamps the sum to 6–11 h after adding, so this
  /// is the honest residual rather than the raw debt figure — the rows always
  /// add up to the need printed above them.
  int? get debtMin {
    if (needMin == null || baselineMin == null) return null;
    final residual =
        needMin! - baselineMin! - (strainMin ?? 0) + (napMin ?? 0);
    // A surplus is no debt: 0 or a time, never below.
    return residual < 0 ? 0 : residual;
  }

  /// Average time awake in bed: the gap between time in bed and sleep.
  int? get awakeMin =>
      needMin == null || inBedMin == null ? null : inBedMin! - needMin!;

  /// The bedtime that gives [inBedMin] in bed before [wakeMin].
  int? bedtimeFor(int? wakeMin) =>
      wakeMin == null || inBedMin == null ? null : (wakeMin - inBedMin!) % 1440;

  static int? _min(Object? v) => v is num ? v.round() : null;

  static Map<String, dynamic>? _value(Object? env) {
    if (env is! Map) return null;
    final v = env['value'];
    return v is Map ? v.cast<String, dynamic>() : null;
  }

  /// Read off the cross-day rollup (`getInsights()`).
  static SleepPlan of(Map<String, dynamic> insights) {
    final coach = insights['sleep_coach'];
    if (coach is! Map) return const SleepPlan();
    final needSec = _value(coach['need'])?['need_sec'] as num?;
    final bed = _value(coach['bedtime'])?['bedtime_min_of_day'] as num?;
    final wake = _value(coach['wake'])?['wake_min_of_day'] as num?;
    final osdH = _value(insights['sleep_debt'])?['osd_hours'] as num?;
    return SleepPlan(
      needMin: needSec == null ? null : (needSec / 60).round(),
      // The same clamp the pipeline applies before it builds the need.
      baselineMin:
          osdH == null ? null : (osdH.toDouble().clamp(7.0, 9.5) * 60).round(),
      strainMin: _min(coach['strain_bonus_min']),
      napMin: _min(coach['nap_credit_min']),
      // wake = bedtime + time in bed, by construction (recommendedWake).
      inBedMin: bed == null || wake == null
          ? null
          : ((wake - bed) % 1440).round(),
      usualWakeMin: wake?.round(),
    );
  }
}

/// The alarms on My Schedule, or null where there is no app state to read.
List<AlarmItem>? alarmItemsOf(BuildContext c) {
  try {
    return c.read<AppState>().alarmManager.alarms;
  } catch (_) {
    return null;
  }
}

/// The wake time of the next wake day on [items]: tomorrow's from midday on,
/// today's before it. The earliest of the alarms that cover that day; null
/// when none does (an unscheduled day).
int? scheduledWakeMin(Iterable<AlarmItem> items, DateTime now) {
  final day = now.hour >= 12
      ? DateTime(now.year, now.month, now.day + 1)
      : DateTime(now.year, now.month, now.day);
  int? best;
  for (final a in items) {
    if (!a.enabled) continue;
    final covers = a.days.isEmpty
        ? () {
            final next = a.nextOccurrence(now);
            return next != null &&
                next.year == day.year &&
                next.month == day.month &&
                next.day == day.day;
          }()
        : a.days.contains(day.weekday);
    if (!covers) continue;
    final m = a.hour * 60 + a.minute;
    if (best == null || m < best) best = m;
  }
  return best;
}

/// The wake time the planner plans to: the one you set here, else the one your
/// schedule has for the next wake day, else your usual wake time. On a day the
/// schedule leaves out, the most recent wake time stands and the alarm is off.
int? plannedWakeMin(SleepPlan plan, (DateTime?, AlarmArmState)? alarm,
    {Iterable<AlarmItem>? items, DateTime? now}) {
  final set = Prefs.getInt(Prefs.sleepPlannerWakeMin, -1);
  if (set >= 0) return set;
  if (items != null) {
    final scheduled = scheduledWakeMin(items, now ?? DateTime.now());
    if (scheduled != null) return scheduled;
    return plan.usualWakeMin;
  }
  final at = alarm?.$1;
  if (at != null) return at.hour * 60 + at.minute;
  return plan.usualWakeMin;
}

/// `8:43`; with [sign], `+0:12` / `−0:05`.
String hMm(int? min, {bool sign = false}) {
  if (min == null) return '--';
  final a = min.abs();
  final s = '${a ~/ 60}:${(a % 60).toString().padLeft(2, '0')}';
  if (!sign) return min < 0 ? '−$s' : s;
  return '${min < 0 ? '−' : '+'}$s';
}

/// The id of the alarm the planner sets: one night's wake-up, kept apart from
/// the repeating ones on My Schedule.
const String kPlannerAlarmId = 'planner';

class SleepPlannerScreen extends StatefulWidget {
  const SleepPlannerScreen({super.key});

  @override
  State<SleepPlannerScreen> createState() => _SleepPlannerScreenState();
}

class _SleepPlannerScreenState extends State<SleepPlannerScreen> {
  SleepPlan? _plan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    var plan = const SleepPlan();
    if (repo != null) {
      try {
        plan = SleepPlan.of(await repo.getInsights());
      } catch (_) {
        // A failed read is an empty plan: every number a dash.
      }
    }
    if (mounted) setState(() => _plan = plan);
  }

  AlarmManager? get _mgr {
    try {
      return context.read<AppState>().alarmManager;
    } catch (_) {
      return null;
    }
  }

  AlarmItem? get _alarm {
    final items = _mgr?.alarms ?? const <AlarmItem>[];
    for (final a in items) {
      if (a.id == kPlannerAlarmId && a.enabled) return a;
    }
    return null;
  }

  /// The wake time, then the question the original asks: just the wake time,
  /// or an alarm too.
  Future<void> _pickWake(int? current) async {
    final t = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 7, minute: 0)
          : TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: 'WAKE TIME',
    );
    if (t == null || !mounted) return;
    final min = t.hour * 60 + t.minute;
    Prefs.setInt(Prefs.sleepPlannerWakeMin, min);
    setState(() {});
    final alarm = await AppSheet.open<bool>(
      context,
      bare: true,
      builder: (_) => _AskAlarm(wake: min),
    );
    if (alarm == true && mounted) await _setAlarm(min);
  }

  /// Arms the planner's alarm for [wake], asking its mode first.
  Future<void> _setAlarm(int wake) async {
    final mode =
        await openAlarmModeSheet(context, current: _alarm?.mode ?? AlarmMode.exact);
    final mgr = _mgr;
    if (mode == null || mgr == null) return;
    final item = AlarmItem(
      id: kPlannerAlarmId,
      hour: wake ~/ 60,
      minute: wake % 60,
      label: 'Sleep Planner',
      mode: mode,
    );
    if (mgr.alarms.any((a) => a.id == kPlannerAlarmId)) {
      await mgr.updateAlarm(item);
    } else {
      await mgr.addAlarm(item);
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleAlarm(bool on, int? wake) async {
    final mgr = _mgr;
    if (mgr == null) return;
    if (!on) {
      await mgr.toggleAlarm(kPlannerAlarmId, false);
      if (mounted) setState(() {});
      return;
    }
    if (wake == null) return _pickWake(null);
    await _setAlarm(wake);
  }

  Future<void> _pickGoal() async {
    final goal = await AppSheet.open<String>(
      context,
      bare: true,
      builder: (_) => const _GoalSheet(),
    );
    if (goal == null) return;
    Prefs.setString(Prefs.sleepPlannerGoal, goal);
    if (mounted) setState(() {});
  }

  /// `11:31 PM`, the way a sentence says a time (the bar keeps the clock's own).
  static String _said(int min) {
    final h = min ~/ 60 % 24, m = min % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final plan = _plan ?? const SleepPlan();
    final alarm = alarmArmOfContext(c);
    final items = _mgr?.alarms ?? const <AlarmItem>[];
    final now = DateTime.now();
    final wake = plannedWakeMin(plan, alarm, items: items);
    final goal = Prefs.getString(Prefs.sleepPlannerGoal, 'optimize');
    final usualWake = plan.usualWakeMin;
    final usualBed = usualWake == null || plan.inBedMin == null
        ? null
        : (usualWake - plan.inBedMin!) % 1440;
    var bed = goal == 'consistent' && usualBed != null
        ? usualBed
        : plan.bedtimeFor(wake);
    // Past the suggested bedtime and still before the wake time: it is now.
    final nowMin = now.hour * 60 + now.minute;
    var isNow = false;
    if (bed != null && wake != null) {
      final late = (nowMin - bed) % 1440;
      final left = (wake - nowMin) % 1440;
      if (late > 0 && late < 360 && left > 0 && left < (wake - bed) % 1440) {
        isNow = true;
        bed = nowMin;
      }
    }
    final inBed = bed == null || wake == null ? null : (wake - bed) % 1440;
    final planAlarm = _alarm;
    final armedAt = planAlarm != null
        ? planAlarm.hour * 60 + planAlarm.minute
        : (alarm?.$1 == null ? null : alarm!.$1!.hour * 60 + alarm.$1!.minute);
    final scheduleOn = items.any((a) => a.enabled && a.id != kPlannerAlarmId);

    final headline = plan.needMin == null || bed == null || wake == null
        ? 'Sleep Planner needs a few nights to learn your sleep need.'
        : isNow
            ? 'Try getting to bed now to achieve 100% Sleep Need by '
                '${_said(wake)}.'
            : 'Try getting to bed by ${_said(bed)} to achieve 100% Sleep '
                'Need by ${_said(wake)}.';

    Widget dockButton(String label, String value, VoidCallback onTap) => Expanded(
          child: Pressable(
            onTap: onTap,
            semanticLabel: '$label $value',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: S.x4),
              decoration: BoxDecoration(
                color: Color.alphaBlend(p.ink.withValues(alpha: .12), p.bg),
                borderRadius: R.rMd,
                border: Border.all(
                    color: C.char.withValues(alpha: .9), width: S.half),
              ),
              child: Column(children: [
                Text(label,
                    textAlign: TextAlign.center,
                    style: F.caps.copyWith(
                        color: p.ink3, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                const SizedBox(height: S.x2),
                Text(value,
                    style: F.num(F.head).copyWith(
                        color: p.ink, fontWeight: FontWeight.w800, letterSpacing: .8)),
              ]),
            ),
          ),
        );

    final h = MediaQuery.sizeOf(c).height;
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        // Two grounds: a lit one over the top of the page, and under it the
        // night, nearly black down to the dock.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: Color.alphaBlend(C.char.withValues(alpha: .55), p.bg)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: h * .39,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(p.ink.withValues(alpha: .17), p.bg),
                  Color.alphaBlend(p.ink.withValues(alpha: .05), p.bg),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Expanded(
              // Sized to sit on one screen with the dock under it: it only
              // scrolls on a phone too short for that.
              child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
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
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('SLEEP PLANNER',
                            style: F.body.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6)),
                        const SizedBox(width: S.x3),
                        Pressable(
                          onTap: () => showSleepRecommendation(c, plan),
                          semanticLabel: 'How the plan is made',
                          child: Container(
                            width: S.x6,
                            height: S.x6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: p.ink3, width: S.half),
                            ),
                            child: Center(
                              child: Text('?',
                                  style: F.cap.copyWith(
                                      color: p.ink3, fontWeight: FontWeight.w800, height: 1)),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  Pressable(
                    onTap: () => go(c, const AlarmScreen()),
                    semanticLabel: 'My schedule',
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: S.x8 + S.x1,
                        height: S.x8 + S.x1,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: p.ink, width: S.half),
                        ),
                        child: Icon(LucideIcons.calendarClock,
                            size: I.sm, color: p.ink),
                      ),
                      const SizedBox(height: S.half),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: S.x2, vertical: S.half),
                        decoration: BoxDecoration(
                          color: p.ink.withValues(alpha: .12),
                          borderRadius: R.rSm,
                        ),
                        child: Text(scheduleOn ? 'ON' : 'OFF',
                            style: F.over.copyWith(
                                color: p.ink3, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
                ]),
                Center(
                  child: Container(
                    width: S.x8 + S.x1,
                    height: S.x8 + S.x1,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: p.ink, width: S.half),
                    ),
                    child: Icon(LucideIcons.moon, size: I.sm, color: p.ink),
                  ),
                ),
                const SizedBox(height: S.x3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Text(headline,
                      textAlign: TextAlign.center,
                      style: F.head.copyWith(
                          color: p.ink, fontWeight: FontWeight.w500, height: 1.25)),
                ),
                const SizedBox(height: S.x5),
                Center(
                  child: Text('TOMORROW I WANT TO',
                      style: F.over.copyWith(
                          color: p.ink3, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                ),
                const SizedBox(height: S.x2),
                Center(
                  child: Pressable(
                    onTap: _pickGoal,
                    semanticLabel: 'Planner goal',
                    child: Container(
                      width: S.x16 * 3 + S.x8 + S.x4,
                      padding: const EdgeInsets.symmetric(vertical: S.x4),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(C.char.withValues(alpha: .4), p.bg),
                        borderRadius: R.rPill,
                        border: Border.all(color: p.ink, width: S.half),
                      ),
                      child: Text(
                          goal == 'consistent' ? 'STAY CONSISTENT' : 'REACH MY SLEEP NEED',
                          textAlign: TextAlign.center,
                          style: F.body.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2)),
                    ),
                  ),
                ),
                const SizedBox(height: S.x6),
                _PlannerBar(
                  bed: bed,
                  wake: wake,
                  bedLabel: isNow ? 'Now' : (bed == null ? '--' : clock(bed)),
                  wakeLabel: wake == null ? '--' : clock(wake),
                  inBedLabel: hMm(inBed),
                  recFrom: usualBed,
                  recTo: usualWake,
                  alarmOn: planAlarm != null,
                  onWake: () => _pickWake(wake),
                ),
                const SizedBox(height: S.x2),
              ]),
            ),
            // The alarm dock.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(S.x3, S.x3, S.x3, S.x3),
              decoration: BoxDecoration(
                color: Color.alphaBlend(p.ink.withValues(alpha: .09), p.bg),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(R.xxl)),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Row(children: [
                  const SizedBox(width: S.x2),
                  StrapIcon(color: p.ink3, height: S.x6),
                  Expanded(
                    child: Center(
                      child: Text('ALARM',
                          style: F.body.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6)),
                    ),
                  ),
                  AppSwitch(
                    planAlarm != null,
                    (v) => _toggleAlarm(v, wake),
                    semanticLabel: 'Alarm',
                  ),
                  const SizedBox(width: S.x2),
                ]),
                const SizedBox(height: S.x3),
                Row(children: [
                  dockButton('ALARM SET TO', armedAt == null ? 'OFF' : clock(armedAt),
                      () => planAlarm != null && wake != null
                          ? _setAlarm(wake)
                          : _toggleAlarm(true, wake)),
                  const SizedBox(width: S.x5),
                  dockButton('WAKE TIME SET TO', wake == null ? '--' : clock(wake),
                      () => _pickWake(wake)),
                ]),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// "Set an alarm too, or just the wake time?"
class _AskAlarm extends StatelessWidget {
  final int wake;
  const _AskAlarm({required this.wake});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Color.alphaBlend(p.ink.withValues(alpha: .08), p.bg),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      padding: EdgeInsets.fromLTRB(
          S.gutter, S.x8, S.gutter, S.x6 + MediaQuery.paddingOf(c).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Wake time set to ${clock(wake)}',
            textAlign: TextAlign.center,
            style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.w500)),
        const SizedBox(height: S.x2),
        Text('Do you want an alarm too, or only to plan your night around it?',
            textAlign: TextAlign.center,
            style: F.body.copyWith(color: p.ink2, fontWeight: FontWeight.w400)),
        const SizedBox(height: S.x6),
        BigButton('SET AN ALARM', color: C.white, onTap: () => Navigator.of(c).pop(true)),
        const SizedBox(height: S.x3),
        BigButton('WAKE TIME ONLY',
            color: C.white, soft: true, onTap: () => Navigator.of(c).pop(false)),
      ]),
    );
  }
}

/// What the plan is for.
class _GoalSheet extends StatelessWidget {
  const _GoalSheet();

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final current = Prefs.getString(Prefs.sleepPlannerGoal, 'optimize');
    Widget option(String id, String title, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: Pressable(
            onTap: () => Navigator.of(c).pop(id),
            semanticLabel: '$title. $sub',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: S.x4, vertical: S.x6),
              decoration: BoxDecoration(
                color: Color.alphaBlend(C.char.withValues(alpha: .35), p.bg),
                borderRadius: R.rMd,
                border: Border.all(
                    color: id == current ? p.ink : C.char.withValues(alpha: .9),
                    width: S.half),
              ),
              child: Column(children: [
                Text(title,
                    style: F.head.copyWith(
                        color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                const SizedBox(height: S.x2),
                Text(sub,
                    textAlign: TextAlign.center,
                    style: F.body.copyWith(color: p.ink2, fontWeight: FontWeight.w400)),
              ]),
            ),
          ),
        );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Color.alphaBlend(p.ink.withValues(alpha: .08), p.bg),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      padding: EdgeInsets.fromLTRB(
          S.gutter, S.x6, S.gutter, S.x8 + MediaQuery.paddingOf(c).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Tomorrow I want to',
            style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.w500)),
        const SizedBox(height: S.x5),
        option('optimize', 'REACH MY SLEEP NEED',
            'Bed early enough to get your full sleep need'),
        option('consistent', 'STAY CONSISTENT',
            'Bed at your usual time, from your own nights'),
      ]),
    );
  }
}

/// The night as a bar: where it starts and ends, the time in bed between, and
/// under it the window your own nights recommend.
class _PlannerBar extends StatelessWidget {
  final int? bed, wake, recFrom, recTo;
  final String bedLabel, wakeLabel, inBedLabel;
  final bool alarmOn;
  final VoidCallback onWake;

  const _PlannerBar({
    required this.bed,
    required this.wake,
    required this.bedLabel,
    required this.wakeLabel,
    required this.inBedLabel,
    required this.recFrom,
    required this.recTo,
    required this.alarmOn,
    required this.onWake,
  });

  // Where the two ends of the night stand across the screen, and where the
  // times written over them are centred (a little inside the ends).
  static const _lo = .125, _hi = .875, _loText = .19, _hiText = .81;

  // Down the bar, from the top of the times.
  static const _labelsH = 72.0, _barTop = 100.0, _barH = 34.0, _height = 190.0;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return LayoutBuilder(builder: (c, box) {
      final w = box.maxWidth + S.gutter * 2;
      // In this widget's own coordinates (the screen's, less the gutter).
      double x(double f) => w * f - S.gutter;
      final xl = x(_lo), xr = x(_hi);
      final span = bed == null || wake == null ? null : (wake! - bed!) % 1440;
      // A time on the bar's own scale; null off the plan.
      double? xAt(int? t) {
        if (t == null || span == null || span == 0) return null;
        final rel = ((t - bed! + 720) % 1440) - 720;
        return xl + rel / span * (xr - xl);
      }

      Widget time(String t, String caption, double cx, {VoidCallback? onTap}) =>
          Positioned(
            left: cx - S.x16,
            width: S.x16 * 2,
            top: 0,
            height: _labelsH,
            child: Pressable(
              onTap: onTap,
              semanticLabel: '$caption $t',
              child: Column(children: [
                Text(t,
                    style: F.n34.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
                const SizedBox(height: S.x2),
                Text(caption,
                    textAlign: TextAlign.center,
                    style: F.over.copyWith(
                        color: p.ink3, fontWeight: FontWeight.w800, letterSpacing: .9)),
              ]),
            ),
          );

      final from = xAt(recFrom), to = xAt(recTo);
      final haveRec = from != null && to != null && to > from;
      final muted = C.dialSleep.withValues(alpha: .85);
      return SizedBox(
        height: _height,
        child: Stack(clipBehavior: Clip.none, children: [
          time(bedLabel, 'SUGGESTED\nTIME TO BED', x(_loText)),
          time(wakeLabel, 'YOUR\nWAKE TIME', x(_hiText), onTap: onWake),
          Positioned(
            left: -S.gutter,
            right: -S.gutter,
            top: 0,
            height: _height,
            child: CustomPaint(
              painter: _BarPaint(
                ink: p.ink,
                stripe: p.ink.withValues(alpha: .3),
                band: Color.alphaBlend(C.char.withValues(alpha: .85), p.bg),
                dash: p.ink3,
                xl: w * _lo,
                xr: w * _hi,
                from: haveRec ? from + S.gutter : null,
                to: haveRec ? to + S.gutter : null,
                barTop: _barTop,
                barH: _barH,
                dropFrom: _labelsH + S.half,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: _barTop - 22,
            child: Text('TIME IN BED',
                textAlign: TextAlign.center,
                style: F.over.copyWith(
                    color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: _barTop - S.x1 - S.half,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: S.x5, vertical: S.x2 + S.x1),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(C.char.withValues(alpha: .95), p.bg),
                  borderRadius: R.rPill,
                  border: Border.all(color: p.ink, width: S.half),
                ),
                child: Text(inBedLabel,
                    style: F.n24.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          if (alarmOn)
            Positioned(
              left: xr - S.x4 - S.half,
              top: _barTop - S.x8 - S.x2,
              child: Container(
                width: S.x8,
                height: S.x8,
                decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
                child: Center(child: StrapIcon(color: C.char, height: S.x4)),
              ),
            ),
          // What your own nights recommend, or why there is nothing yet.
          Positioned(
            left: 0,
            right: 0,
            top: _barTop + _barH + S.x4,
            child: Center(
              child: haveRec
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('RECOMMENDED',
                          style: F.caps.copyWith(
                              color: muted, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      const SizedBox(height: S.x1),
                      Text('${clock(recFrom!)} - ${clock(recTo!)}',
                          style: F.num(F.cap).copyWith(color: p.ink3)),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('OPTIMAL',
                          style: F.caps.copyWith(
                              color: muted, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      const SizedBox(height: S.x2),
                      Text(
                          'Three consecutive nights of sleep needed to\ncalculate optimal bed and wake times.',
                          textAlign: TextAlign.center,
                          style: F.over.copyWith(
                              color: muted, fontWeight: FontWeight.w500, height: 1.5)),
                    ]),
            ),
          ),
        ]),
      );
    });
  }
}

class _BarPaint extends CustomPainter {
  final Color ink, stripe, band, dash;
  final double xl, xr, barTop, barH, dropFrom;
  final double? from, to;
  _BarPaint({
    required this.ink,
    required this.stripe,
    required this.band,
    required this.dash,
    required this.xl,
    required this.xr,
    required this.from,
    required this.to,
    required this.barTop,
    required this.barH,
    required this.dropFrom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    void dashed(Path path, Paint paint, double on, double off) {
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += on + off) {
          canvas.drawPath(m.extractPath(d, d + on), paint);
        }
      }
    }

    final line = Paint()
      ..color = dash
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // The dashed drops from the times to the ends of the bar.
    for (final x in [xl, xr]) {
      dashed(Path()..moveTo(x, dropFrom)..lineTo(x, barTop), line, S.x1, S.x1);
    }
    // The band, edge to edge, hatched between the two ends.
    canvas.drawRect(Rect.fromLTWH(0, barTop, size.width, barH), Paint()..color = band);
    const inset = S.x1 + S.half;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(xl, barTop + inset, xr, barTop + barH - inset));
    final hatch = Paint()
      ..color = stripe
      ..strokeWidth = 2;
    final h = barH - inset * 2;
    for (var x = xl - h; x < xr; x += S.x2 + S.x1) {
      canvas.drawLine(Offset(x, barTop + barH - inset), Offset(x + h, barTop + inset), hatch);
    }
    canvas.restore();
    final end = Paint()
      ..color = ink
      ..strokeWidth = 3;
    for (final x in [xl, xr]) {
      canvas.drawLine(Offset(x, barTop + inset), Offset(x, barTop + barH - inset), end);
    }

    final f = from, t = to;
    final top = barTop + barH + S.x2;
    final y = top + S.x5;
    final mid = size.width / 2, gap = S.x16 + S.x2;
    if (f != null && t != null) {
      // The recommended window: a dashed bracket under the bar.
      const r = S.x3;
      final left = Path()
        ..moveTo(f, top)
        ..lineTo(f, y - r)
        ..quadraticBezierTo(f, y, f + r, y)
        ..lineTo(math.max(f + r, mid - gap), y);
      final right = Path()
        ..moveTo(math.min(t - r, mid + gap), y)
        ..lineTo(t - r, y)
        ..quadraticBezierTo(t, y, t, y - r)
        ..lineTo(t, top);
      dashed(left, line, S.x1, S.x1);
      dashed(right, line, S.x1, S.x1);
    } else {
      // Nothing to recommend yet: a dashed rule each side of the word.
      dashed(Path()..moveTo(xl, y)..lineTo(mid - S.x10, y), line, S.x1, S.x1);
      dashed(Path()..moveTo(mid + S.x10, y)..lineTo(xr, y), line, S.x1, S.x1);
    }
  }

  @override
  bool shouldRepaint(_BarPaint old) =>
      old.xl != xl || old.xr != xr || old.from != from || old.to != to;
}

/// YOUR SLEEP RECOMMENDATION: the sheet behind the time in bed.
Future<void> showSleepRecommendation(BuildContext c, SleepPlan plan) =>
    showDialog<void>(
      context: c,
      builder: (_) => _RecommendationDialog(plan),
    );

class _RecommendationDialog extends StatelessWidget {
  final SleepPlan plan;
  const _RecommendationDialog(this.plan);

  @override
  Widget build(BuildContext c) {
    final caps = F.caps.copyWith(color: C.char);
    final sub = F.caps.copyWith(color: C.n500);
    final val = F.body.copyWith(color: C.char, fontWeight: FontWeight.w700);
    final subNum = F.body.copyWith(color: C.n500, fontWeight: FontWeight.w600);

    Widget row(String label, String value, {bool minor = false}) => Padding(
          padding: EdgeInsets.only(
              left: minor ? S.x2 : 0, top: S.x2, bottom: S.x2),
          child: Row(children: [
            Expanded(child: Text(label, style: minor ? sub : caps)),
            Text(value, style: minor ? subNum : val),
          ]),
        );

    return Dialog(
      backgroundColor: C.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: S.x4),
      shape: const RoundedRectangleBorder(borderRadius: R.rXl),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(S.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: S.x3),
                  child: Text('YOUR SLEEP RECOMMENDATION', style: caps),
                ),
              ),
              Pressable(
                onTap: () => Navigator.of(c).pop(),
                semanticLabel: 'Close',
                child: const SizedBox(
                  width: S.tap,
                  height: S.tap,
                  child: Icon(LucideIcons.x, size: I.lg, color: C.char),
                ),
              ),
            ]),
            const SizedBox(height: S.x4),
            Text(
              'Locus uses your own nights — how long you sleep when nothing '
              'cuts it short, and how efficiently you sleep — to set a time in '
              'bed that covers tonight’s sleep need, including what today’s '
              'strain, recent sleep debt and naps add or take away.',
              style: F.body.copyWith(color: C.n400, height: 1.4),
            ),
            const SizedBox(height: S.x5),
            Container(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x4),
              decoration: const BoxDecoration(color: C.mint, borderRadius: R.rSm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                row('SLEEP NEED', hMm(plan.needMin)),
                const _Dashes(),
                row('BASELINE', hMm(plan.baselineMin), minor: true),
                row('RECENT STRAIN', hMm(plan.strainMin, sign: true), minor: true),
                row('SLEEP DEBT', hMm(plan.debtMin, sign: true), minor: true),
                // A nap credit takes sleep OFF the need.
                row('RECENT NAPS',
                    plan.napMin == null ? '--' : '−${hMm(plan.napMin)}',
                    minor: true),
                const _Dashes(),
                row('SLEEP GOAL', hMm(plan.needMin)),
                row('AVERAGE AWAKE TIME', hMm(plan.awakeMin, sign: true)),
                const SizedBox(height: S.x2),
                Container(height: S.half, color: C.char),
                const SizedBox(height: S.x4),
                Row(children: [
                  Expanded(child: Text('RECOMMENDED\nTIME IN BED', style: caps)),
                  Text(hMm(plan.inBedMin),
                      style: F.n34.copyWith(color: C.char, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dashed rule across the panel.
class _Dashes extends StatelessWidget {
  const _Dashes();

  @override
  Widget build(BuildContext c) => const Padding(
        padding: EdgeInsets.symmetric(vertical: S.x1),
        child: SizedBox(
          height: S.half,
          width: double.infinity,
          child: CustomPaint(painter: _DashPainter(C.n400)),
        ),
      );
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    const dash = S.x2, gap = S.x1;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset((x + dash).clamp(0, size.width), size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
