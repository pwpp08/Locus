// START ACTIVITY — the screen behind Home's START ACTIVITY button: which
// activity (from the same list Add Activity opens), whether to record the
// route, the band's live heart rate over it, and one button that opens the
// live session. The session itself is the one every other start uses:
// AppState.startWorkout, a LiveDraft, and the activity's own live screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gps/route_types.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart';
import '../activity/live.dart';
import '../ui2.dart';
import 'add_activity.dart' show chooseActivity;
import 'home_screen.dart' show repoOf;
import 'workout_screen.dart' show activityHost, loadSetHistory;

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
  bool _route = true;
  bool _showTarget = false;
  bool _starting = false;
  String? _refused;

  /// Today's strain target, low and high on the 0–21 scale; null until the
  /// day has one.
  (double, double)? _target;
  double? _weightKg;
  AppState? _liveHrOwner;

  @override
  void initState() {
    super.initState();
    try {
      _liveHrOwner = context.read<AppState>()..retainLiveHrView();
    } catch (_) {}
    _load();
  }

  @override
  void dispose() {
    _liveHrOwner?.releaseLiveHrView();
    super.dispose();
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
        _target = lo != null && hi != null && hi > lo ? (lo, hi) : null;
        _weightKg = (profile['weight_kg'] as num?)?.toDouble();
      });
    } catch (_) {}
  }

  Future<void> _pick() async {
    final a = await chooseActivity(context);
    if (a != null && mounted) setState(() => _a = a);
  }

  Future<void> _start() async {
    if (_starting) return;
    AppState app;
    try {
      app = context.read<AppState>();
    } catch (_) {
      return;
    }
    setState(() => (_starting = true, _refused = null));
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

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    int? hr;
    try {
      hr = c.select<AppState, int?>((a) => a.liveHr);
    } catch (_) {}
    final deep = Color.alphaBlend(C.dialStrain.withValues(alpha: .28), C.char);
    final routeable = typeRecordsRoute(_a.typeKey);
    final target = _target;
    return Scaffold(
      backgroundColor: C.char,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [deep, C.char],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            // ── the activity, and the way out ──
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x4, 0),
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
                    onTap: _pick,
                    semanticLabel: 'Activity ${_a.displayName(c)}. Change it',
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_a.icon, size: I.lg, color: C.white),
                      const SizedBox(width: S.x3),
                      Flexible(
                        child: Text(_a.displayName(c),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: F.t2.copyWith(
                                color: C.white, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: S.x2),
                      const Icon(LucideIcons.chevronDown, size: I.md, color: C.white),
                    ]),
                  ),
                ),
              ]),
            ),
            if (routeable)
              Padding(
                padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, 0),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('TRACK ROUTE',
                      style: F.caps.copyWith(color: C.white.withValues(alpha: .6))),
                  const SizedBox(width: S.x3),
                  AppSwitch(_route, (v) => setState(() => _route = v),
                      semanticLabel: 'Track route'),
                ]),
              ),
            // ── the band, and the heart rate it is reading ──
            Expanded(
              child: Center(
                child: Stack(alignment: Alignment.center, children: [
                  StrapIcon(
                      color: C.white.withValues(alpha: .16), height: S.x16 * 4),
                  Container(
                    width: S.x16 * 2 + S.x12,
                    height: S.x16 * 2 + S.x12,
                    decoration: const BoxDecoration(
                        color: C.dialStrain, shape: BoxShape.circle),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.heart, size: I.md, color: C.white),
                          Text(hr == null ? '--' : '$hr',
                              style: F.n64.copyWith(
                                  color: C.white, fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ]),
              ),
            ),
            // ── the dock: the strain target, and the start ──
            Container(
              decoration: BoxDecoration(
                color: p.card,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(R.xxl)),
              ),
              padding: EdgeInsets.fromLTRB(
                  S.x5, S.x3, S.x5, S.x5 + MediaQuery.paddingOf(c).bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: S.x12,
                  height: S.x1,
                  decoration: BoxDecoration(
                      color: p.ink.withValues(alpha: .18), borderRadius: R.rPill),
                ),
                const SizedBox(height: S.x4),
                Row(children: [
                  SizedBox(
                    width: S.x8,
                    height: S.x8,
                    child: CustomPaint(
                      painter: Ring(0, C.dialStrain, p.track,
                          stroke: S.x1,
                          band: _showTarget && target != null
                              ? (target.$1 / 21, target.$2 / 21)
                              : null,
                          bandColor: C.dialStrain),
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Text(
                      _showTarget && target != null
                          ? '${target.$1.toStringAsFixed(1)}–${target.$2.toStringAsFixed(1)}'
                          : '---',
                      style: F.num(F.body)
                          .copyWith(color: p.ink, fontWeight: FontWeight.w800)),
                  const Expanded(child: SizedBox()),
                  Text('STRAIN TARGET', style: F.caps.copyWith(color: p.ink)),
                  const Expanded(child: SizedBox()),
                  AppSwitch(_showTarget, (v) => setState(() => _showTarget = v),
                      semanticLabel: 'Show today’s strain target'),
                  const SizedBox(width: S.x2),
                  SizedBox(
                    width: S.x8,
                    child: Text(_showTarget ? 'ON' : 'OFF',
                        style: F.caps.copyWith(color: p.ink)),
                  ),
                ]),
                if (_showTarget && target == null) ...[
                  const SizedBox(height: S.x2),
                  Text('Today has no strain target yet: it comes with your recovery.',
                      style: F.cap.copyWith(color: p.ink3)),
                ],
                if (_refused != null) ...[
                  const SizedBox(height: S.x3),
                  Text(_refused!, style: F.cap.copyWith(color: C.orange)),
                ],
                const SizedBox(height: S.x4),
                Pressable(
                  onTap: _starting ? null : _start,
                  semanticLabel: 'Start activity',
                  child: Container(
                    height: S.x16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.dialStrain.withValues(alpha: _starting ? .5 : 1),
                      borderRadius: R.rPill,
                    ),
                    child: Text('START ACTIVITY',
                        style: F.body.copyWith(
                            color: C.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
