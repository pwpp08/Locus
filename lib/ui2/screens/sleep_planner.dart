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

import 'package:flutter/material.dart';

import '../../state/prefs.dart';
import '../profile/alarm.dart' show AlarmArmState, AlarmScreen;
import '../ui2.dart';
import 'home_screen.dart' show alarmArmOfContext, clock, go, pad, repoOf;

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
  int? get debtMin => needMin == null || baselineMin == null
      ? null
      : needMin! - baselineMin! - (strainMin ?? 0) + (napMin ?? 0);

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

/// The wake time the planner plans to: the one you set here, else your armed
/// alarm, else your usual wake time.
int? plannedWakeMin(SleepPlan plan, (DateTime?, AlarmArmState)? alarm) {
  final set = Prefs.getInt(Prefs.sleepPlannerWakeMin, -1);
  if (set >= 0) return set;
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

  Future<void> _pickWake(int? current) async {
    final t = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 7, minute: 0)
          : TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: 'WAKE TIME',
    );
    if (t == null || !mounted) return;
    Prefs.setInt(Prefs.sleepPlannerWakeMin, t.hour * 60 + t.minute);
    setState(() {});
  }

  void _resetWake() {
    Prefs.setInt(Prefs.sleepPlannerWakeMin, -1);
    setState(() {});
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final plan = _plan ?? const SleepPlan();
    final alarm = alarmArmOfContext(c);
    final alarmAt = alarm?.$1;
    final wake = plannedWakeMin(plan, alarm);
    final bed = plan.bedtimeFor(wake);
    final custom = Prefs.getInt(Prefs.sleepPlannerWakeMin, -1) >= 0;

    Widget tile(String label, String value, VoidCallback onTap) => Expanded(
          child: Surface(
            onTap: onTap,
            semanticLabel: '$label $value',
            pad: const EdgeInsets.symmetric(vertical: S.x5, horizontal: S.x3),
            child: Column(children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: F.over.copyWith(
                      color: p.ink2,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: S.x2),
              Text(value,
                  style: F.n24.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
            ]),
          ),
        );

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(padding: pad, children: [
          NavBar(
            'Sleep Planner',
            trailing: Pressable(
              onTap: () => go(c, const AlarmScreen()),
              semanticLabel: 'My schedule',
              child: Container(
                width: S.tap,
                height: S.tap,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: p.ink3, width: S.half),
                ),
                child: Icon(LucideIcons.calendarClock, size: I.md, color: p.ink),
              ),
            ),
          ),
          const SizedBox(height: S.x6),
          Center(
            child: Text('RECOMMENDED BEDTIME',
                style: F.caps.copyWith(color: p.ink2)),
          ),
          const SizedBox(height: S.x2),
          Center(
            child: Text(bed == null ? '--' : clock(bed),
                style: F.n64.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: S.x2),
          Center(
            child: Text(
              plan.needMin == null
                  ? 'Sleep Planner needs a few nights to learn your sleep need.'
                  : wake == null
                      ? 'Set a wake time to plan tonight.'
                      : 'For ${hMm(plan.needMin)} of sleep, waking at ${clock(wake)}',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink3),
            ),
          ),
          const SizedBox(height: S.x8),
          // Time in bed: tap for the arithmetic.
          Surface(
            onTap: () => showSleepRecommendation(c, plan),
            semanticLabel: 'Recommended time in bed ${hMm(plan.inBedMin)}. '
                'Show how it is calculated',
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('RECOMMENDED TIME IN BED',
                      style: F.over.copyWith(
                          color: p.ink2,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: S.x2),
                  Text(hMm(plan.inBedMin),
                      style: F.n34.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: S.x1),
                  Text('Sleep need plus your usual time awake in bed',
                      style: F.cap.copyWith(color: p.ink3)),
                ]),
              ),
              Icon(LucideIcons.info, size: I.md, color: p.ink2),
            ]),
          ),
          const SizedBox(height: S.x3),
          Row(children: [
            tile('ALARM SET TO',
                alarmAt == null ? 'OFF' : clock(alarmAt.hour * 60 + alarmAt.minute),
                () => go(c, const AlarmScreen())),
            const SizedBox(width: S.x3),
            tile('WAKE TIME SET TO', wake == null ? '--' : clock(wake),
                () => _pickWake(wake)),
          ]),
          if (custom) ...[
            const SizedBox(height: S.x2),
            Center(
              child: TextAction(
                  alarmAt != null ? 'Plan to my alarm' : 'Use my usual wake time',
                  _resetWake),
            ),
          ],
        ]),
      ),
    );
  }
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
