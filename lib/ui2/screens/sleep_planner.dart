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
import 'dial_parts.dart' show dialCard, kDialMargin, kDialPad;
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

  /// Your actual bedtime and wake time: the medians of your last seven
  /// recorded nights (three at least). Null under that.
  final int? habitBedMin, habitWakeMin;

  const SleepPlan({
    this.needMin,
    this.baselineMin,
    this.strainMin,
    this.napMin,
    this.inBedMin,
    this.usualWakeMin,
    this.habitBedMin,
    this.habitWakeMin,
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

  /// The optimal night: in bed early enough to cover the whole need before
  /// your usual wake time.
  int? get optimalBedMin => bedtimeFor(usualWakeMin);

  /// Your usual bedtime, the one "stay consistent" keeps: the time you really
  /// go to bed. Until a few nights give one, the optimal one.
  int? get usualBedMin => habitBedMin ?? optimalBedMin;

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
      habitBedMin: _min(coach['habit_bed_min']),
      habitWakeMin: _min(coach['habit_wake_min']),
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

/// The first alarm of the next wake day: the earliest on My Schedule, else
/// the one the band has armed. Null with no alarm at all.
int? firstAlarmWakeMin((DateTime?, AlarmArmState)? alarm,
    {Iterable<AlarmItem>? items, DateTime? now}) {
  if (items != null) {
    final scheduled = scheduledWakeMin(items, now ?? DateTime.now());
    if (scheduled != null) return scheduled;
  }
  final at = alarm?.$1;
  return at == null ? null : at.hour * 60 + at.minute;
}

/// The wake time the planner plans to. An alarm wins: the first one set is
/// the wake time, on the planner and on Home alike (a wake time typed here
/// used to override the alarm, so the two screens planned different nights).
/// With no alarm, the one typed here, else your usual wake time.
int? plannedWakeMin(SleepPlan plan, (DateTime?, AlarmArmState)? alarm,
    {Iterable<AlarmItem>? items, DateTime? now}) {
  final first = firstAlarmWakeMin(alarm, items: items, now: now);
  if (first != null) return first;
  final set = Prefs.getInt(Prefs.sleepPlannerWakeMin, -1);
  if (set >= 0) return set;
  return plan.usualWakeMin;
}

/// Whether the planner's goal is to keep the usual schedule rather than to
/// reach the sleep need.
bool get plannerKeepsConsistent =>
    Prefs.getString(Prefs.sleepPlannerGoal, 'optimize') == 'consistent';

/// Tonight's bedtime for the planner's goal: the usual one to stay consistent,
/// else the one that covers the sleep need before [wake]. The planner and Home
/// both read it, so they never suggest two bedtimes.
int? plannedBedMin(SleepPlan plan, int? wake) =>
    plannerKeepsConsistent ? plan.usualBedMin : plan.bedtimeFor(wake);

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
  /// The page's natural height above the dock: below this it scales down.
  static const double _minBodyH = 500;

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
    final t = await pickTime(
      context,
      initial: current == null
          ? const TimeOfDay(hour: 7, minute: 0)
          : TimeOfDay(hour: current ~/ 60, minute: current % 60),
      title: 'Wake time',
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
    final consistent = plannerKeepsConsistent;
    final usualWake = plan.usualWakeMin;
    final usualBed = plan.usualBedMin;
    var bed = plannedBedMin(plan, wake);
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

    // How much of the need the night in bed covers, at your usual efficiency.
    final covers = inBed == null || plan.inBedMin == null || plan.inBedMin! <= 0
        ? null
        : (inBed / plan.inBedMin! * 100).round();
    final String headline;
    if (consistent) {
      final needPart = covers == null || wake == null
          ? ''
          : covers >= 100
              ? ' It covers your full Sleep Need by ${_said(wake)}.'
              : ' It covers $covers% of your Sleep Need by ${_said(wake)}.';
      headline = usualBed == null || bed == null
          ? 'Sleep Planner needs a few nights to learn your usual bedtime.'
          : isNow
              ? 'Try getting to bed now to stay close to your usual bedtime '
                  'of ${_said(usualBed)}.$needPart'
              : 'Try getting to bed by ${_said(bed)}, your usual time, to '
                  'stay consistent.$needPart';
    } else {
      headline = plan.needMin == null || bed == null || wake == null
          ? 'Sleep Planner needs a few nights to learn your sleep need.'
          : isNow
              ? 'Try getting to bed now to achieve 100% Sleep Need by '
                  '${_said(wake)}.'
              : 'Try getting to bed by ${_said(bed)} to achieve 100% Sleep '
                  'Need by ${_said(wake)}.';
    }

    Widget dockButton(String label, String value, VoidCallback onTap) => Expanded(
          child: Pressable(
            onTap: onTap,
            semanticLabel: '$label $value',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: S.x3, vertical: S.x3),
              decoration: BoxDecoration(
                color: Color.alphaBlend(C.slate.withValues(alpha: .35), p.bg),
                borderRadius: R.rSm,
                border: Border.all(
                    color: C.char.withValues(alpha: .7), width: S.half),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(label,
                      textAlign: TextAlign.center,
                      style: F.caps.copyWith(
                          color: p.ink3,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2)),
                  const SizedBox(height: S.x2),
                  Text(value,
                      style: F.head.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5)),
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        // Full screen deep slate-to-obsidian gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(C.slate.withValues(alpha: .45), p.bg),
                  Color.alphaBlend(C.char.withValues(alpha: .6), p.bg),
                  p.bg,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Expanded(
              // One fixed page. The spare height is shared between the
              // groups; a phone too short for it scales the page down rather
              // than scrolling it.
              child: LayoutBuilder(builder: (c, box) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: box.maxWidth,
                  height: box.maxHeight < _minBodyH ? _minBodyH : box.maxHeight,
                  child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Column(children: [
                Row(children: [
                  Pressable(
                    onTap: () => Navigator.of(c).maybePop(),
                    semanticLabel: 'Back',
                    child: SizedBox(
                      width: S.tap,
                      height: S.tap,
                      child: Center(
                          child: BoldChevron(left: true, height: S.x4 + S.half, color: p.ink)),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text('SLEEP PLANNER',
                          style: F.body.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6)),
                    ),
                  ),
                  Pressable(
                    onTap: () => go(c, const AlarmScreen()),
                    semanticLabel: 'My schedule',
                    // The ring sits on the title's own line; ON / OFF hangs
                    // under it without taking any of the row's height.
                    child: SizedBox(
                      width: S.tap,
                      height: S.tap,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // The calendar with a moon in it: the nightly
                          // schedule.
                          Container(
                            width: S.x8 + S.x1,
                            height: S.x8 + S.x1,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: p.ink, width: S.half),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(LucideIcons.calendar,
                                    size: I.md, color: p.ink),
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: S.x1 + S.half),
                                  child: Icon(LucideIcons.moon,
                                      size: S.x3, color: p.ink),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: S.tap - S.x1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: S.x2, vertical: S.half / 2),
                              decoration: BoxDecoration(
                                color: p.ink.withValues(alpha: .12),
                                borderRadius: R.rSm,
                              ),
                              child: Text(scheduleOn ? 'ON' : 'OFF',
                                  style: F.over.copyWith(
                                      color: p.ink3,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: S.x2),
                Center(
                  child: Container(
                    width: S.x8 + S.x1,
                    height: S.x8 + S.x1,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: p.ink, width: S.half),
                    ),
                    padding: const EdgeInsets.all(S.half),
                    child: CustomPaint(
                        painter: LocusMarkPainter(ink: p.ink)),
                  ),
                ),
                const SizedBox(height: S.x4),
                // Three lines high whatever it says, so what is under it does
                // not move when the sentence changes length.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: S.x16 + S.x2),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: S.x6),
                    child: Text(headline,
                        textAlign: TextAlign.center,
                        style: F.head.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w500,
                            height: 1.3)),
                  ),
                ),
                const Spacer(flex: 1),
                Center(
                  child: Text('TOMORROW I WANT TO',
                      style: F.over.copyWith(
                          color: p.ink3, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                ),
                const SizedBox(height: S.x2),
                Center(
                  child: Pressable(
                    onTap: _pickGoal,
                    semanticLabel: 'Planner goal',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: S.x8, vertical: S.x3),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(C.char.withValues(alpha: .5), p.bg),
                        borderRadius: R.rPill,
                        border: Border.all(color: p.ink, width: S.half),
                      ),
                      child: Text(
                          consistent ? 'STAY CONSISTENT' : 'REACH MY SLEEP NEED',
                          textAlign: TextAlign.center,
                          style: F.caps.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2)),
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                _PlannerBar(
                  bed: bed,
                  wake: wake,
                  bedLabel: isNow ? 'Now' : (bed == null ? '--' : clock(bed)),
                  wakeLabel: wake == null ? '--' : clock(wake),
                  inBedLabel: hMm(inBed),
                  recFrom: plan.optimalBedMin,
                  recTo: usualWake,
                  alarmOn: planAlarm != null,
                  onWake: () => _pickWake(wake),
                  onInBed: () => showSleepRecommendation(c, plan),
                ),
                const Spacer(flex: 2),
              ]),
                  ),
                ),
              )),
            ),
            // The alarm dock.
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  S.x3, S.x3, S.x3, S.x3 + MediaQuery.paddingOf(c).bottom),
              decoration: BoxDecoration(
                color: Color.alphaBlend(C.slate.withValues(alpha: .45), p.bg),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(R.xl)),
                border: Border(
                  top: BorderSide(
                    color: p.ink.withValues(alpha: .08),
                    width: S.half,
                  ),
                ),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Row(children: [
                  StrapIcon(color: p.ink, height: S.x5),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text('ALARM',
                        style: F.body.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6)),
                  ),
                  if (armedAt != null && alarm?.$2 == AlarmArmState.confirmed) ...[
                    Icon(LucideIcons.badgeCheck, size: I.sm, color: C.optimal),
                    const SizedBox(width: S.x1),
                    Text('CONFIRMED',
                        style: F.over.copyWith(
                            color: C.optimal, fontWeight: FontWeight.w800)),
                    const SizedBox(width: S.x3),
                  ],
                  AppSwitch(
                    planAlarm != null,
                    (v) => _toggleAlarm(v, wake),
                    semanticLabel: 'Alarm',
                  ),
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
/// under it the optimal window your own nights give. It slides a little under
/// a finger and springs back to the time in bed, centred, when let go.
class _PlannerBar extends StatefulWidget {
  final int? bed, wake, recFrom, recTo;
  final String bedLabel, wakeLabel, inBedLabel;
  final bool alarmOn;
  final VoidCallback onWake, onInBed;

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
    required this.onInBed,
  });

  // Where the two ends of the night stand across the screen, and where the
  // times written over them are centred (a little inside the ends).
  static const _lo = .125, _hi = .875, _loText = .19, _hiText = .81;

  // Down the bar, from the top of the times.
  static const _labelsH = 72.0, _barTop = 100.0, _barH = 34.0, _height = 190.0;

  /// The furthest the bar slides: it gives less the further it is pulled.
  static const _reach = S.x16;

  /// How far before bedtime a time still reads as "before bed" on the bar,
  /// rather than as late the next day.
  static const _leadMin = 6 * 60;

  @override
  State<_PlannerBar> createState() => _PlannerBarState();
}

class _PlannerBarState extends State<_PlannerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(vsync: this)
    ..addListener(() => setState(() {
          _dx = _from * (1 - Ease.emphasized.transform(_back.value));
        }));
  double _pull = 0, _dx = 0, _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _drag(double dx) {
    _pull += dx;
    // Rubber band: follows the finger at first, then stiffens to _reach.
    const r = _PlannerBar._reach;
    setState(() => _dx = r * (2 / (1 + math.exp(-2 * _pull / r)) - 1));
  }

  void _release(double _) {
    _pull = 0;
    // A cancel also comes as the page closes: nothing to spring back then.
    if (_dx == 0) return;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final bed = widget.bed, wake = widget.wake;
    _back.duration = motion(c, Motion.slow);
    return SideDrag(
      onStart: _back.stop,
      onDrag: _drag,
      onRelease: _release,
      child: Transform.translate(
        offset: Offset(_dx, 0),
        child: LayoutBuilder(builder: (c, box) {
          final w = box.maxWidth + S.gutter * 2;
          // In this widget's own coordinates (the screen's, less the gutter).
          double x(double f) => w * f - S.gutter;
          final xl = x(_PlannerBar._lo), xr = x(_PlannerBar._hi);
          final span = bed == null || wake == null ? null : (wake - bed) % 1440;
          // A time on the bar's own scale: minutes after bedtime, or up to
          // _leadMin before it. Kept on screen.
          double? xAt(int? t) {
            if (t == null || span == null || span == 0) return null;
            var rel = (t - bed!) % 1440;
            if (rel > 1440 - _PlannerBar._leadMin) rel -= 1440;
            return (xl + rel / span * (xr - xl))
                .clamp(S.x2 - S.gutter, w - S.gutter - S.x2);
          }

          Widget time(String t, String caption, double cx,
                  {VoidCallback? onTap}) =>
              Positioned(
                left: cx - S.x16,
                width: S.x16 * 2,
                top: 0,
                height: _PlannerBar._labelsH,
                child: Pressable(
                  onTap: onTap,
                  semanticLabel: '$caption $t',
                  child: Column(children: [
                    Text(t,
                        style: F.n34
                            .copyWith(color: p.ink, fontWeight: FontWeight.w800)),
                    const SizedBox(height: S.x2),
                    Text(caption,
                        textAlign: TextAlign.center,
                        style: F.over.copyWith(
                            color: p.ink3,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .9)),
                  ]),
                ),
              );

          final from = xAt(widget.recFrom), to = xAt(widget.recTo);
          final haveRec = from != null && to != null && to > from;
          final muted = C.dialSleep.withValues(alpha: .85);
          const barTop = _PlannerBar._barTop, barH = _PlannerBar._barH;
          return SizedBox(
            height: _PlannerBar._height,
            child: Stack(clipBehavior: Clip.none, children: [
              time(widget.bedLabel, 'SUGGESTED\nTIME TO BED',
                  x(_PlannerBar._loText)),
              time(widget.wakeLabel, 'YOUR\nWAKE TIME', x(_PlannerBar._hiText),
                  onTap: widget.onWake),
              Positioned(
                left: -S.gutter,
                right: -S.gutter,
                top: 0,
                height: _PlannerBar._height,
                child: CustomPaint(
                  painter: _BarPaint(
                    ink: p.ink,
                    stripe: p.ink.withValues(alpha: .3),
                    band: Color.alphaBlend(C.char.withValues(alpha: .85), p.bg),
                    dash: p.ink3,
                    xl: w * _PlannerBar._lo,
                    xr: w * _PlannerBar._hi,
                    from: haveRec ? from + S.gutter : null,
                    to: haveRec ? to + S.gutter : null,
                    barTop: barTop,
                    barH: barH,
                    dropFrom: _PlannerBar._labelsH + S.half,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: barTop - S.x5 - S.half,
                child: Text('TIME IN BED',
                    textAlign: TextAlign.center,
                    style: F.over.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
              ),
              // The time in bed opens what it is made of.
              Positioned(
                left: 0,
                right: 0,
                top: barTop - S.x1 - S.half,
                child: Center(
                  child: Pressable(
                    onTap: widget.onInBed,
                    semanticLabel:
                        'Time in bed ${widget.inBedLabel}. How it is made',
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(
                          S.x5, S.x2, S.x4, S.x2),
                      decoration: BoxDecoration(
                        color:
                            Color.alphaBlend(C.char.withValues(alpha: .95), p.bg),
                        borderRadius: R.rPill,
                        border: Border.all(color: p.ink, width: S.half),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(widget.inBedLabel,
                            style: F.n24.copyWith(
                                color: p.ink, fontWeight: FontWeight.w800)),
                        const SizedBox(width: S.x2),
                        Icon(LucideIcons.info, size: I.sm, color: p.ink3),
                      ]),
                    ),
                  ),
                ),
              ),
              if (widget.alarmOn)
                Positioned(
                  left: xr - S.x4 - S.half,
                  top: barTop - S.x8 - S.x2,
                  child: Container(
                    width: S.x8,
                    height: S.x8,
                    decoration:
                        BoxDecoration(color: p.ink, shape: BoxShape.circle),
                    child: Center(child: StrapIcon(color: C.char, height: S.x4)),
                  ),
                ),
              // The optimal night your own nights give, or why there is none.
              Positioned(
                left: 0,
                right: 0,
                top: barTop + barH + S.x4,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('OPTIMAL',
                        style: F.caps.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                    const SizedBox(height: S.x1),
                    if (haveRec)
                      Text(
                          '${clock(widget.recFrom!)} - ${clock(widget.recTo!)}',
                          style: F.num(F.cap).copyWith(color: p.ink3))
                    else
                      Text(
                          'Three nights of sleep needed to calculate\n'
                          'optimal bed and wake times.',
                          textAlign: TextAlign.center,
                          style: F.over.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w500,
                              height: 1.5)),
                  ]),
                ),
              ),
            ]),
          );
        }),
      ),
    );
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
    final run = Rect.fromLTRB(-size.width, barTop, size.width * 2, barTop + barH);
    canvas.drawRect(run, Paint()..color = band);
    final edge = Paint()
      ..color = ink.withValues(alpha: .16)
      ..strokeWidth = 1;
    for (final y in [barTop, barTop + barH]) {
      canvas.drawLine(Offset(run.left, y), Offset(run.right, y), edge);
    }
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

/// YOUR SLEEP RECOMMENDATION: what the time in bed is made of, opened from
/// the time in bed itself. A dial sheet: the need, its parts under it, the
/// time awake, and the time in bed they add up to.
Future<void> showSleepRecommendation(BuildContext c, SleepPlan plan) =>
    AppSheet.open<void>(
      c,
      bare: true,
      scroll: true,
      builder: (_) => _RecommendationSheet(plan),
    );

class _RecommendationSheet extends StatelessWidget {
  final SleepPlan plan;
  const _RecommendationSheet(this.plan);

  @override
  Widget build(BuildContext c) {
    Widget row(String label, String value,
            {bool minor = false, bool last = false}) =>
        Container(
          constraints: BoxConstraints(minHeight: minor ? S.x10 : S.x12),
          padding: EdgeInsets.only(left: minor ? S.x4 : 0),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(
                    bottom: BorderSide(color: DC.line, width: S.hair)),
          ),
          child: Row(children: [
            Expanded(
              child: Text(label,
                  style: F.dLabel.copyWith(color: minor ? DC.ink3 : DC.ink2)),
            ),
            Text(value,
                style: F.dText.copyWith(
                    color: minor ? DC.ink2 : DC.ink,
                    fontWeight: FontWeight.w600)),
          ]),
        );

    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [DC.sheetTop, DC.sheetFoot],
        ),
      ),
      padding: EdgeInsets.fromLTRB(kDialMargin, S.x4 + S.half + S.hair,
          kDialMargin, S.x6 + MediaQuery.paddingOf(c).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: S.x16 + S.x2,
                height: S.x1 + S.hair,
                decoration:
                    const BoxDecoration(color: DC.grab, borderRadius: R.rPill),
              ),
            ),
            const SizedBox(height: S.x6),
            Semantics(
              header: true,
              child: Text('YOUR SLEEP RECOMMENDATION',
                  textAlign: TextAlign.center,
                  style: F.dLabel.copyWith(color: DC.ink2)),
            ),
            const SizedBox(height: S.x2),
            Text(hMm(plan.inBedMin),
                textAlign: TextAlign.center,
                style: F.n34.copyWith(color: DC.ink)),
            const SizedBox(height: S.x1),
            Text('TIME IN BED',
                textAlign: TextAlign.center,
                style: F.dTiny.copyWith(color: DC.ink3)),
            const SizedBox(height: S.x6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: kDialPad),
              decoration: dialCard(),
              child: Column(children: [
                row('SLEEP NEED', hMm(plan.needMin)),
                row('BASELINE', hMm(plan.baselineMin), minor: true),
                row('RECENT STRAIN', hMm(plan.strainMin, sign: true),
                    minor: true),
                row('SLEEP DEBT', hMm(plan.debtMin, sign: true), minor: true),
                // A nap credit takes sleep OFF the need.
                row('RECENT NAPS',
                    plan.napMin == null ? '--' : '−${hMm(plan.napMin)}',
                    minor: true),
                row('AVERAGE AWAKE TIME', hMm(plan.awakeMin, sign: true),
                    last: true),
              ]),
            ),
            const SizedBox(height: S.x4),
            Text(
              'Your sleep need is your baseline, the sleep you get on nights '
              'nothing cuts short, plus what today’s strain and recent sleep '
              'debt add, less your naps. Time in bed adds the time you usually '
              'lie awake.',
              style: F.dText.copyWith(color: DC.body, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
