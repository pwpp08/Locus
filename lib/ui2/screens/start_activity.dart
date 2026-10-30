// START ACTIVITY — the screen behind Home's START ACTIVITY button: which
// activity (from the same list Add Activity opens, sleep and nap included),
// whether to record the route, the band's live heart rate in a pulsing disc,
// a strain target to set by dragging round a dial, and one button that opens
// the live session. The session itself is the one every other start uses:
// AppState.startWorkout, a LiveDraft, and the activity's own live screen.
//
// A sleep or a nap is not a workout: starting one notes the time
// (Prefs.restPending), and ending it writes the window the way Add Activity's
// Sleep tab does. The screen reopens on that running rest until it is ended
// or thrown away.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gps/route_types.dart';
import '../../models/alarm_item.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart';
import '../../state/prefs.dart';
import '../activity/catalogue.dart';
import '../activity/live.dart';
import '../profile/alarm.dart' show AlarmScreen;
import '../ui2.dart';
import 'add_activity.dart' show chooseActivity, saveRestWindow;
import 'home_screen.dart' show go, repoOf;
import 'window_editor.dart' show WindowKind, windowProblem;
import 'workout_screen.dart' show activityHost, loadSetHistory;

/// The strain scale the target sits on.
const double kStrainScale = 21;

/// What a strain reads as, in the words of its band.
String strainLevelOf(double s) => s > 18
    ? 'all-out'
    : s > 14
        ? 'strenuous'
        : s > 10
            ? 'moderate'
            : 'light';

/// The collapsed strain-target dock: a handle and one row.
const double _kDock = 89;

class StartActivityScreen extends StatefulWidget {
  /// The activity to open on; running when null.
  final Activity? initial;
  const StartActivityScreen({super.key, this.initial});

  @override
  State<StartActivityScreen> createState() => _StartActivityScreenState();
}

class _StartActivityScreenState extends State<StartActivityScreen> {
  late Activity _a =
      widget.initial ?? activityByName('Running') ?? allActivities.first;

  /// A sleep or a nap chosen in place of an activity, and when it began once it
  /// has.
  WindowKind? _rest;
  DateTime? _restSince;
  Timer? _tick;

  bool _route = true;
  bool _open = false;
  bool _starting = false;
  String? _refused;

  /// The strain goal: on or off, and where the dial is.
  bool _on = false;
  double _goal = 10;

  /// Today's recommended strain, the middle of its range; null until the day
  /// has one.
  double? _recommended;
  double? _weightKg;
  AppState? _liveHrOwner;

  @override
  void initState() {
    super.initState();
    try {
      _liveHrOwner = context.read<AppState>()..retainLiveHrView();
    } catch (_) {}
    final saved = double.tryParse(Prefs.getString(Prefs.activityStrainTarget, ''));
    if (saved != null) {
      _on = true;
      _goal = saved.clamp(0.0, kStrainScale);
    }
    final parts = Prefs.getString(Prefs.restPending, '').split('|');
    final ms = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (ms != null && (parts[0] == 'sleep' || parts[0] == 'nap')) {
      _rest = parts[0] == 'sleep' ? WindowKind.sleep : WindowKind.nap;
      _restSince = DateTime.fromMillisecondsSinceEpoch(ms);
      _startTick();
    }
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _liveHrOwner?.releaseLiveHrView();
    super.dispose();
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(Motion.tick, (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final today = await repo.getToday();
      final profile = await repo.getProfile();
      final coach = today['coach'];
      final t = coach is Map ? coach['strain_target'] : null;
      final lo = t is Map ? (t['low'] as num?)?.toDouble() : null;
      final hi = t is Map ? (t['high'] as num?)?.toDouble() : null;
      if (!mounted) return;
      setState(() {
        _recommended = lo != null && hi != null && hi > lo ? (lo + hi) / 2 : null;
        _weightKg = (profile['weight_kg'] as num?)?.toDouble();
      });
    } catch (_) {}
  }

  Future<void> _pick() async {
    if (_restSince != null) return;
    final r = await chooseActivity(context);
    if (r == null || !mounted) return;
    setState(() {
      _rest = r.sleep;
      if (r.activity != null) _a = r.activity!;
      _refused = null;
    });
  }

  void _setGoal(double v) {
    setState(() {
      _goal = (v.clamp(0.0, kStrainScale) * 10).round() / 10;
      _on = true;
    });
    _saveGoal();
  }

  void _saveGoal() => Prefs.setString(
      Prefs.activityStrainTarget, _on ? _goal.toStringAsFixed(1) : '');

  void _toggleGoal(bool v) {
    if (v) _goal = _recommended ?? _goal;
    setState(() => _on = v);
    _saveGoal();
  }

  Future<void> _start() async {
    if (_starting) return;
    final rest = _rest;
    if (rest != null) {
      final now = DateTime.now();
      Prefs.setString(Prefs.restPending,
          '${rest == WindowKind.sleep ? 'sleep' : 'nap'}|${now.millisecondsSinceEpoch}');
      setState(() {
        _restSince = now;
        _refused = null;
      });
      _startTick();
      return;
    }
    AppState app;
    try {
      app = context.read<AppState>();
    } catch (_) {
      return;
    }
    setState(() {
      _starting = true;
      _refused = null;
    });
    final nav = Navigator.of(context);
    if (app.activeWorkout != null) {
      setState(() {
        _starting = false;
        _refused = 'A session is already running. Only one can be live at a time.';
      });
      return;
    }
    final history = await loadSetHistory();
    app.startWorkout(type: _a.typeKey, trackRoute: _route);
    if (app.activeWorkout == null) {
      if (mounted) {
        setState(() {
          _starting = false;
          _refused = 'The session could not start. Try again.';
        });
      }
      return;
    }
    LiveDraft.begin(_a, private: _a.private, weightKg: _weightKg);
    await nav.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => liveFor(_a,
          private: _a.private,
          weightKg: _weightKg,
          host: activityHost(app, history: history)),
    ));
  }

  /// Ends the running sleep or nap: the window from its start to now.
  Future<void> _end() async {
    final k = _rest, since = _restSince;
    if (k == null || since == null || _starting) return;
    final now = DateTime.now();
    final bad = windowProblem(k, since, now, now);
    if (bad != null) {
      setState(() => _refused = bad);
      return;
    }
    AppState? app;
    try {
      app = context.read<AppState>();
    } catch (_) {}
    final nav = Navigator.of(context);
    setState(() {
      _starting = true;
      _refused = null;
    });
    try {
      await saveRestWindow(app, k, since, now);
      Prefs.setString(Prefs.restPending, '');
      if (mounted) nav.pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _starting = false;
          _refused = 'Could not save that. Try again.';
        });
      }
    }
  }

  void _discard() {
    Prefs.setString(Prefs.restPending, '');
    _tick?.cancel();
    setState(() {
      _restSince = null;
      _refused = null;
    });
  }

  String get _restName => _rest == WindowKind.sleep ? 'Sleep' : 'Nap';

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    int? hr;
    try {
      hr = c.select<AppState, int?>((a) => a.liveHr);
    } catch (_) {}
    final rest = _rest;
    final running = _restSince != null;
    final routeable = rest == null && typeRecordsRoute(_a.typeKey);
    final inset = MediaQuery.paddingOf(c);
    final headerH = inset.top + S.x2 + S.tap;
    final barH = S.x16 + S.x3 * 2 + inset.bottom;
    final head = Color.alphaBlend(C.dialStrain.withValues(alpha: .12), C.char);
    final lit = Color.alphaBlend(C.dialStrain.withValues(alpha: .26), C.char);
    return Scaffold(
      backgroundColor: C.char,
      body: LayoutBuilder(builder: (_, box) {
        final sheetFull = box.maxHeight - headerH - barH;
        return Stack(children: [
          // ── the ground: a darker header, then blue falling off to near black ──
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [lit, C.char],
                  stops: const [0, .8],
                ),
              ),
            ),
          ),
          Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: headerH,
              child: ColoredBox(color: head)),
          // ── the activity, and the way out ──
          Positioned(
            left: 0,
            right: 0,
            top: inset.top + S.x2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(S.x2, 0, S.x4, 0),
              child: Row(children: [
                Pressable(
                  onTap: () => Navigator.of(c).maybePop(),
                  semanticLabel: 'Close',
                  child: const SizedBox(
                    width: S.tap,
                    height: S.tap,
                    child: Icon(LucideIcons.x, size: I.lg, color: C.white),
                  ),
                ),
                const SizedBox(width: S.x2),
                Flexible(
                  child: Pressable(
                    onTap: running ? null : _pick,
                    semanticLabel:
                        'Activity ${rest != null ? _restName : _a.displayName(c)}. Change it',
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          rest == null
                              ? _a.icon
                              : (rest == WindowKind.sleep
                                  ? LucideIcons.moon
                                  : LucideIcons.sun),
                          size: I.lg,
                          color: C.white),
                      const SizedBox(width: S.x3),
                      Flexible(
                        child: Text(rest != null ? _restName : _a.displayName(c),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: F.t2.copyWith(
                                color: C.white, fontWeight: FontWeight.w600)),
                      ),
                      if (!running) ...[
                        const SizedBox(width: S.x2),
                        const Icon(LucideIcons.chevronDown,
                            size: I.md, color: C.white),
                      ],
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          if (routeable)
            Positioned(
              right: S.x4,
              top: headerH + S.x4,
              child: Row(children: [
                Text('TRACK ROUTE',
                    style: F.caps.copyWith(color: C.white.withValues(alpha: .5))),
                const SizedBox(width: S.x3),
                AppSwitch(_route, (v) => setState(() => _route = v),
                    semanticLabel: 'Track route'),
              ]),
            ),
          // ── the pulse: the band's heart rate, beating ──
          Positioned(
            left: 0,
            right: 0,
            top: headerH,
            bottom: barH + (rest == null ? _kDock : 0),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _Pulse(hr: hr, d: math.min(box.maxWidth * .375, S.x16 * 2.6)),
                if (running) ...[
                  const SizedBox(height: S.x4),
                  Text(_clock(DateTime.now().difference(_restSince!)),
                      style: F.n48
                          .copyWith(color: C.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: S.x2),
                  Text(
                      '${_restName.toUpperCase()} · SINCE ${formatClockOf(_restSince!)}',
                      style: F.caps.copyWith(color: C.white.withValues(alpha: .6))),
                ],
              ]),
            ),
          ),
          // ── the dock: the strain target, swiped up to set ──
          if (rest == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: barH,
              child: AnimatedContainer(
                duration: motion(c, Motion.slow),
                curve: Ease.standard,
                height: _open ? sheetFull : _kDock,
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(R.xxl + S.x3)),
                ),
                child: _sheet(c, p, sheetFull),
              ),
            ),
          if (rest != null)
            Positioned(
              left: S.gutter,
              right: S.gutter,
              bottom: barH + S.x2,
              child: _restAlarmCard(c, p, rest),
            ),
          // ── the start ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barH,
            child: ColoredBox(
              color: p.card,
              child: Padding(
                padding: EdgeInsets.fromLTRB(S.x5, S.x3, S.x5, S.x3 + inset.bottom),
                child: Column(children: [
                  if (_refused != null)
                    Text(_refused!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: F.cap.copyWith(color: C.orange)),
                  Expanded(
                    child: Row(children: [
                      if (running) ...[
                        Pressable(
                          onTap: _starting ? null : _discard,
                          semanticLabel: 'Throw this away',
                          child: SizedBox(
                            width: S.x16,
                            height: S.x16,
                            child: Center(
                              child: Text('DISCARD',
                                  style: F.cap.copyWith(
                                      color: C.white.withValues(alpha: .7),
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                        const SizedBox(width: S.x2),
                      ],
                      Expanded(
                        child: Pressable(
                          onTap: _starting ? null : (running ? _end : _start),
                          semanticLabel: running
                              ? 'End ${_restName.toLowerCase()}'
                              : 'Start activity',
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: C.dialStrain
                                  .withValues(alpha: _starting ? .5 : 1),
                              borderRadius: R.rPill,
                            ),
                            child: Text(
                                running
                                    ? 'END ${_restName.toUpperCase()}'
                                    : (rest == null
                                        ? 'START ACTIVITY'
                                        : 'START ${_restName.toUpperCase()}'),
                                style: F.body.copyWith(
                                    color: C.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.6)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  static String _clock(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Widget _restAlarmCard(BuildContext c, P p, WindowKind rest) {
    final app = context.watch<AppState?>();
    if (app == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final plan = app.alarmManager.computeNextArmedPlan(now);
    final isSleep = rest == WindowKind.sleep;

    // For nap, an alarm is relevant if it's within the next 4 hours
    final isNapAlarmUpcoming =
        !isSleep && plan != null && plan.time.difference(now).inHours < 4;
    final hasAlarm = isSleep ? plan != null : isNapAlarmUpcoming;

    final alarmTime = plan?.time;

    return Container(
      padding: const EdgeInsets.all(S.x3),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: .95),
        borderRadius: R.rXl,
        border: Border.all(color: p.line.withValues(alpha: .4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(
              hasAlarm ? LucideIcons.alarmClockCheck : LucideIcons.bellOff,
              size: I.md,
              color: hasAlarm ? C.optimal : p.ink3,
            ),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text(
                hasAlarm
                    ? (isSleep
                        ? 'Alarm set for ${formatClock(alarmTime!.hour, alarmTime.minute)}'
                        : 'Nap alarm: ${formatClock(alarmTime!.hour, alarmTime.minute)} (${alarmTime.difference(now).inMinutes}m)')
                    : (isSleep
                        ? 'No alarm set for tomorrow'
                        : 'No alarm set for this nap'),
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Pressable(
              onTap: () async {
                if (hasAlarm) {
                  go(c, const AlarmScreen());
                } else {
                  final initial = isSleep
                      ? const TimeOfDay(hour: 7, minute: 0)
                      : TimeOfDay.fromDateTime(
                          now.add(const Duration(minutes: 30)));
                  final picked =
                      await showTimePicker(context: c, initialTime: initial);
                  if (picked != null) {
                    var target = DateTime(
                        now.year, now.month, now.day, picked.hour, picked.minute);
                    if (target.isBefore(now)) {
                      target = target.add(const Duration(days: 1));
                    }
                    await app.alarmManager.addAlarm(AlarmItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      hour: picked.hour,
                      minute: picked.minute,
                      label: isSleep ? 'Wake up' : 'Nap alarm',
                      enabled: true,
                      days: const {},
                    ));
                    if (mounted) setState(() {});
                  }
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
                decoration: BoxDecoration(
                  color: p.wash(p.ink).withValues(alpha: .08),
                  borderRadius: R.rSm,
                ),
                child: Text(
                  hasAlarm ? 'CHANGE' : 'SET ALARM',
                  style: F.caps.copyWith(
                    color: hasAlarm ? p.ink2 : C.dialStrain,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ]),
          if (!isSleep && !hasAlarm) ...[
            const SizedBox(height: S.x2),
            Row(
              children: [
                Text(
                  'QUICK NAP:',
                  style: F.caps.copyWith(color: p.ink3),
                ),
                const SizedBox(width: S.x2),
                for (final mins in [20, 30, 45, 60]) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: S.x1),
                    child: Pressable(
                      onTap: () async {
                        final target = now.add(Duration(minutes: mins));
                        await app.alarmManager.addAlarm(AlarmItem(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          hour: target.hour,
                          minute: target.minute,
                          label: 'Nap $mins min',
                          enabled: true,
                          days: const {},
                        ));
                        if (mounted) setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: S.x2, vertical: S.half),
                        decoration: BoxDecoration(
                          color: C.dialSleep.withValues(alpha: .2),
                          borderRadius: R.rSm,
                          border: Border.all(
                              color: C.dialSleep.withValues(alpha: .4)),
                        ),
                        child: Text(
                          '${mins}m',
                          style: F.cap.copyWith(
                              color: p.ink, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── the strain target ────────────────────────────────────────────────────
  Widget _sheet(BuildContext c, P p, double full) {
    final goal = _on ? _goal : null;
    final body = math.max(0.0, full - _kDock);
    return Column(children: [
      SwipeHandle(
        onSwipe: (up) => setState(() => _open = up),
        onTap: () => setState(() => _open = !_open),
        semanticLabel: _open ? 'Close the strain target' : 'Open the strain target',
        child: SizedBox(
          height: _kDock,
          child: Column(children: [
            const SizedBox(height: S.x3),
            Container(
              width: S.x12 + S.x4,
              height: S.x1,
              decoration: BoxDecoration(
                  color: p.ink.withValues(alpha: .22), borderRadius: R.rPill),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x5),
                child: Row(children: [
                  SizedBox(
                    width: S.x10 + S.x6,
                    child: _open
                        ? Pressable(
                            onTap: () => _explain(c),
                            semanticLabel: 'What is a strain target?',
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Icon(LucideIcons.circleHelp,
                                  size: I.xl, color: p.ink),
                            ),
                          )
                        : Row(children: [
                            SizedBox(
                              width: S.x8,
                              height: S.x8,
                              child: CustomPaint(
                                painter: Ring(
                                    goal == null ? 0 : goal / kStrainScale,
                                    C.dialStrain,
                                    p.track,
                                    stroke: S.x1,
                                    solid: true),
                              ),
                            ),
                            const SizedBox(width: S.x3),
                            Flexible(
                              child: Text(
                                  goal == null ? '---' : goal.toStringAsFixed(1),
                                  maxLines: 1,
                                  style: F.num(F.body).copyWith(
                                      color: p.ink, fontWeight: FontWeight.w800)),
                            ),
                          ]),
                  ),
                  Expanded(
                    child: Center(
                        child: Text('STRAIN TARGET',
                            style: F.caps.copyWith(
                                color: p.ink, fontWeight: FontWeight.w700))),
                  ),
                  AppSwitch(_on, _toggleGoal, semanticLabel: 'Use a strain target'),
                  SizedBox(
                    width: S.x10,
                    child: Padding(
                      padding: const EdgeInsets.only(left: S.x2),
                      child: Text(_on ? 'ON' : 'OFF',
                          style: F.caps.copyWith(color: p.ink)),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
      Expanded(
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: body,
            child: SizedBox(height: body, child: _dial(c, p, body)),
          ),
        ),
      ),
    ]);
  }

  void _explain(BuildContext c) => AppSheet.show<void>(c,
      title: 'Strain target',
      child: Text(
          'A goal for the strain of this activity, on the same 0–21 scale as '
          'your day. Drag the dial round to set it. The live screen shows '
          'your strain against it as you go.',
          style: F.body.copyWith(color: P.of(c).ink2, height: 1.45)));

  Widget _dial(BuildContext c, P p, double h) {
    final w = MediaQuery.sizeOf(c).width;
    final d = math.max(S.x16 * 2, math.min(w * .69, h * .6));
    final goal = _on ? _goal : null;
    final frac = (goal ?? 0) / kStrainScale;
    const knob = (S.x12 + S.x4) * 0.65;
    final big = d > S.x16 * 4;
    // The ring's stroke and the knob's track on it.
    final stroke = d * .0625;
    final tr = d / 2 - stroke / 2;
    final a = frac * 2 * math.pi;
    return Column(children: [
      const SizedBox(height: S.x6),
      DialScrubber(
        value: goal == null ? null : frac,
        onChanged: (f) => _setGoal(f * kStrainScale),
        label: 'Strain target',
        describe: (f) => '${(f * kStrainScale).toStringAsFixed(1)} strain',
        step: 1 / (kStrainScale * 2),
        child: SizedBox(
          width: d,
          height: d,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Positioned.fill(
                child: CustomPaint(painter: _TargetRing(frac, goal != null, p.track))),
            // The knob rides the ring at the angle of the goal.
            Positioned(
              left: d / 2 + tr * math.sin(a) - knob / 2,
              top: d / 2 - tr * math.cos(a) - knob / 2,
              child: Container(
                width: knob,
                height: knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.ink.withValues(alpha: .92),
                  boxShadow: [
                    BoxShadow(
                        color: p.ink.withValues(alpha: .18),
                        blurRadius: S.x4,
                        spreadRadius: S.x1),
                  ],
                ),
                child: Icon(
                    goal == null ? LucideIcons.rotateCw : LucideIcons.activity,
                    size: I.md,
                    color: p.bg),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('ACTIVITY STRAIN',
                  style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
              SizedBox(height: big ? S.x6 : S.x3),
              Text(goal == null ? '---' : goal.toStringAsFixed(1),
                  style: (big ? F.n80 : F.n64)
                      .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              const SizedBox(height: S.x3),
              Text(goal == null ? 'SET GOAL' : strainLevelOf(goal).toUpperCase(),
                  style: F.caps.copyWith(color: p.ink3, fontWeight: FontWeight.w700)),
              const SizedBox(height: S.x3),
              Pressable(
                onTap: () => _setGoal(_recommended ?? 10),
                semanticLabel: _recommended == null
                    ? 'Reset the goal to 10'
                    : 'Reset the goal to today’s recommended strain',
                child: Container(
                  width: S.x8,
                  height: S.x8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: p.ink3.withValues(alpha: .6), width: 1.5),
                  ),
                  child: Icon(LucideIcons.rotateCcw, size: I.md, color: p.ink3),
                ),
              ),
            ]),
          ]),
        ),
      ),
      const Spacer(),
      if (goal != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x6),
          child: Row(children: [
            Container(
              width: S.x10 + S.x2,
              height: S.x10 + S.x2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.ink, width: 1.5),
              ),
              child: Icon(LucideIcons.activity, size: I.lg, color: p.ink),
            ),
            const SizedBox(width: S.x5),
            Expanded(
              child: Text(
                  'A ${goal.toStringAsFixed(1)} Activity Strain represents '
                  '${strainLevelOf(goal)} cardiovascular exertion.',
                  style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
    ]);
  }
}

/// The dial's ring: a track all the way round and, from twelve o'clock to
/// [frac] of a turn, an arc that deepens towards the knob.
class _TargetRing extends CustomPainter {
  final double frac;
  final bool on;
  final Color track;
  _TargetRing(this.frac, this.on, this.track);

  @override
  void paint(Canvas cv, Size s) {
    final stroke = s.width * .0625;
    final r = math.min(s.width, s.height) / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: Offset(s.width / 2, s.height / 2), radius: r);
    cv.drawCircle(
        rect.center,
        r,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    if (!on || frac <= 0) return;
    final sweep = frac * 2 * math.pi;
    cv.save();
    cv.translate(rect.center.dx, rect.center.dy);
    cv.rotate(-math.pi / 2);
    cv.translate(-rect.center.dx, -rect.center.dy);
    cv.drawArc(
        rect,
        0,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: math.max(sweep, .01),
            colors: [
              Color.alphaBlend(C.char.withValues(alpha: .55), C.dialStrain),
              C.dialStrain,
            ],
          ).createShader(rect));
    cv.restore();
  }

  @override
  bool shouldRepaint(_TargetRing old) =>
      old.frac != frac || old.on != on || old.track != track;
}

/// The heart-rate disc: a blue circle with a heart and the reading, that
/// swells with each beat and sends a soft ring out. A controller of its own
/// swings out and back at the beat's pace (no `.repeat(`); with reduced motion
/// it sits still.
class _Pulse extends StatefulWidget {
  final int? hr;
  final double d;
  const _Pulse({required this.hr, required this.d});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _t.reverse();
      if (s == AnimationStatus.dismissed) _t.forward();
    });

  /// One beat is a swell and a fall: half of it each way. With no reading the
  /// disc breathes at a resting pace.
  Duration get _half {
    final hr = widget.hr;
    final ms = hr == null || hr <= 0 ? 500 : (30000 / hr).clamp(240, 700).round();
    return Motion.fast * (ms / 120);
  }

  void _sync() {
    if (!Motion.enabled(context)) {
      _t.stop();
      return;
    }
    _t.duration = _half;
    if (!_t.isAnimating) _t.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    _t.duration = _half;
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final d = widget.d;
    final hr = widget.hr;
    return SizedBox(
      width: d * 1.5,
      height: d * 1.5,
      child: AnimatedBuilder(
        animation: _t,
        builder: (_, child) {
          final t = Curves.easeInOut.transform(_t.value);
          return Stack(alignment: Alignment.center, children: [
            Container(
              width: d * (1 + .38 * t),
              height: d * (1 + .38 * t),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: C.dialStrain.withValues(alpha: .16 * (1 - t)),
              ),
            ),
            Transform.scale(scale: 1 + .035 * t, child: child),
          ]);
        },
        child: Container(
          width: d,
          height: d,
          decoration:
              const BoxDecoration(color: C.dialStrain, shape: BoxShape.circle),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CustomPaint(
                size: const Size.square(I.lg), painter: _HeartPainter(C.white)),
            const SizedBox(height: S.x1),
            Text(hr == null ? '--' : '$hr',
                style: F.n64.copyWith(color: C.white, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// A filled heart on a 24-unit grid, the same outline the stat icons draw,
/// for the pulse disc (Lucide has no filled glyph).
class _HeartPainter extends CustomPainter {
  final Color color;
  _HeartPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
        Path()
          ..moveTo(12, 20.6)
          ..cubicTo(12, 20.6, 2.6, 15.4, 2.6, 8.9)
          ..cubicTo(2.6, 5.9, 4.8, 3.9, 7.4, 3.9)
          ..cubicTo(9.3, 3.9, 11, 4.9, 12, 6.6)
          ..cubicTo(13, 4.9, 14.7, 3.9, 16.6, 3.9)
          ..cubicTo(19.2, 3.9, 21.4, 5.9, 21.4, 8.9)
          ..cubicTo(21.4, 15.4, 12, 20.6, 12, 20.6)
          ..close(),
        Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.color != color;
}
