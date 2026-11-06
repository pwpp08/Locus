// The live screens.
//
// Same interaction grammar — one shell, one clock, one pause/stop control —
// with a completely different middle. That difference is the point of the
// file: what the user is asked for depends on what nothing can measure.
//
//   MEASURED    route, journey, power        nothing to type; sensors do it
//   ENTERED     strength                     load, reps, RPE, rest
//               laps                         + LAP, pool length, stroke
//               flow                         pose, hold, breath
//               match                        score
//               interval                     rounds run themselves
//
// Nothing in here invents a measurement. [LiveFeed] is the seam to the band —
// every field nullable, and an absent one renders as a StatusCard rather than
// a zero. Calories are the one derived number, and they are derived from the
// activity's published MET and the user's weight (never from nothing), which
// is why they carry estimated confidence everywhere they appear.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../lucide.dart';

// The permission enum only — a pure value type, no geolocator call from this
// file. The rule this file keeps is no AppState and no LocalDb: the live
// screens describe a session, the caller owns it. Prefs is a synchronous
// key/value façade, not the app.
import '../../gps/gps_source.dart' show GpsPermissionStatus;
import '../../l10n/app_localizations.dart';
import '../../l10n/display_text.dart';
import '../../state/prefs.dart';
import '../../state/units_controller.dart';
import '../screens/home_screen.dart' show unitsOf;
import '../charts.dart';
import '../grammar.dart';
import '../paint_activity.dart';
import '../theme.dart';
import 'catalogue.dart';
import '../profile/profile.dart' show SetRow, settingsGroup;
import 'exercise_image.dart';
import 'exercise_picker.dart';
import 'summary.dart';

/// What the band and the phone know right now. Read once per tick.
///
/// There is no `watts`: nothing in this stack measures power (see [Arch]).
class LiveFeed {
  final int? hr;

  /// Spike-suppressed session peak, from the same accumulator the finished
  /// session banks — not `max(hr seen by this screen)`.
  final int? maxHr;
  final int? zone; // 1..5
  final int? calories;
  final double? strain;
  final double? distanceKm;
  final int? steps;
  final List<double> zoneMinutes; // five, Z1..Z5

  /// The stamp on the set [zoneMinutes] is binned with, and the ceiling it is
  /// 100 % of — `LiveWorkoutState.zoneSet`, pinned at session start. Carried so
  /// the summary this screen hands over on stop describes the same anchors the
  /// live bar was drawn against.
  final String? zoneSource;
  final num? zoneMaxHr;

  /// The five lower edges, in bpm, of that same set.
  final List<num>? zoneLowerBpm;

  /// Per-minute mean heart rate for the session so far, DENSE — one slot per
  /// session minute, `null` where the band recorded nothing.
  ///
  /// It has to carry the holes: `ActivityResult.hr` is `List<double?>` and the
  /// painter breaks its line at a null, so a compacted list here drew a band
  /// dropout as continuous and shifted every later reading earlier.
  ///
  /// The average of this IS the session average — a single instantaneous
  /// sample is not.
  final List<double?> hrCurve;
  final List<Offset> route;

  /// Whether a route recorder is actually running and taking fixes. The
  /// catalogue's `gps` flag says an activity DESERVES a route; only this says
  /// one is being recorded.
  final bool gpsActive;

  /// Why no route is being recorded, when the reason is a location permission
  /// the user can still fix. Null when nothing is wrong. Without this a denied
  /// permission simply produced no map and no sentence.
  final GpsPermissionStatus? routeIssue;

  /// What to do about [routeIssue] — re-ask, or open Settings. It rides on the
  /// feed because the feed is the one thing every live screen already has, and
  /// the caller owns which of the two it is.
  final VoidCallback? onFixRoute;

  /// Whether the band is connected right now. An absent heart rate means one
  /// thing when the band is streaming and something else entirely when it
  /// dropped ten minutes ago.
  final bool bandConnected;

  const LiveFeed({
    this.hr,
    this.maxHr,
    this.zone,
    this.calories,
    this.strain,
    this.distanceKm,
    this.steps,
    this.zoneMinutes = const [],
    this.zoneSource,
    this.zoneMaxHr,
    this.zoneLowerBpm,
    this.hrCurve = const [],
    this.route = const [],
    this.gpsActive = false,
    this.routeIssue,
    this.onFixRoute,
    this.bandConnected = false,
  });

  static const none = LiveFeed();

  /// Mean of the per-minute curve — the session's real average heart rate,
  /// null until a full minute has been folded in.
  /// Over the minutes that HAVE a reading. A dropout must not be averaged in
  /// as a zero, and it must not divide by minutes that measured nothing.
  int? get avgHr {
    final v = [for (final x in hrCurve) ?x];
    if (v.isEmpty) return null;
    return (v.reduce((a, b) => a + b) / v.length).round();
  }
}

typedef LiveFeedSource = LiveFeed Function();

/// Ends the session the app started: stops the live engine, persists what the
/// user typed against the session id, and returns the result ENRICHED with
/// whatever the stores now hold (the GPS route, above all).
///
/// It returns a result rather than taking one so this file stays free of
/// `AppState` and `LocalDb` — the live screens describe a session, the caller
/// owns it. A screen built without one still runs; it just does not persist,
/// which is exactly what the widget tests want.
typedef SessionFinish = Future<ActivityResult> Function(ActivityResult draft);

/// Starts a session in the app before the live screen opens. Returns false if
/// the app refused (one is already running).
typedef SessionStart = Future<bool> Function(Activity a);

/// Previous and best set for one exercise — the two references a lifter
/// actually uses. Absent for a lift they have never logged.
class SetHistory {
  final LoggedSet? previous, best;
  const SetHistory({this.previous, this.best});
}

/// Everything the activity screens need FROM the app, in one object.
///
/// Picker → setup → live is three constructors deep, and every one of these
/// used to be an optional parameter that no caller passed — which is how the
/// setup screen ended up saying "No band connected" while the band was
/// streaming. One object, threaded once, and a default that is honest about
/// having no app behind it (tests, previews).
class ActivityHost {
  /// The band and phone, read once per tick.
  final LiveFeedSource? feed;

  /// Opens a real session in the app. False means it refused — one is
  /// already running — and the live screen must not open.
  final SessionStart? onStart;

  /// Closes it, persists what was typed, and enriches the result.
  final SessionFinish? onFinish;

  /// Banks the sets logged SO FAR, on every change. A typed set is the one
  /// thing in a session that no sensor can reproduce, so it is written the
  /// moment it exists rather than at finish — the whole log used to live in
  /// widget state until the user pressed stop.
  final void Function(List<LoggedSet> sets)? onSets;

  /// Previous and best set per exercise key, from the user's own log.
  final Map<String, SetHistory> history;

  /// Whether the band is connected right now.
  final bool bandConnected;

  const ActivityHost({
    this.feed,
    this.onStart,
    this.onFinish,
    this.onSets,
    this.history = const {},
    this.bandConnected = false,
  });

  /// No app behind the screens: they still render, nothing is persisted.
  static const none = ActivityHost();
}

// ══════════════ THE SESSION, ABOVE THE ROUTE ══════════════

/// The running session's own state, held above the screen that draws it.
///
/// The live screen used to own every byte of a session. The header's
/// "Minimise" called `Navigator.maybePop` and an iOS back-swipe did the same,
/// so the sets, laps and score the user had typed died with the route while
/// `AppState.activeWorkout` stayed open — after which the app refused every
/// further workout and offered no way back into the one it was holding.
///
/// The entries live here instead, mirrored into Prefs on every change: a
/// minimised session outlives its route, and a killed process loses the
/// screen rather than the typing. [begin] is called by whoever starts the
/// session (setup), [clear] by whoever ends it. A screen built without a
/// draft — a test, a preview — simply has nothing to restore and nothing to
/// save, which is exactly the old behaviour.
class LiveDraft {
  static const _key = 'live.session_draft';

  /// The catalogue key of the activity being done, so the bar that reopens a
  /// minimised session knows which screen to build.
  final String activityKey;
  final bool private;
  final double? weightKg;
  final DateTime startedAt;

  /// Interval config chosen on the setup screen — null for every archetype
  /// but [Track.interval], where 45/30/8 used to be a constant nothing let
  /// the user change.
  final int? workSec;
  final int? restSec;
  final int? rounds;

  /// Seconds banked in earlier pauses, and when the current pause began. The
  /// clock is wall time minus these, so it stays true across a long
  /// background spell or a relaunch instead of counting screen-on seconds.
  int pausedSec;
  DateTime? pausedAt;

  /// The archetype's own entries — sets, laps, score. Opaque here: whichever
  /// screen wrote a key is the one that reads it back.
  final Map<String, Object?> data;

  LiveDraft._(this.activityKey,
      {required this.startedAt,
      this.private = false,
      this.weightKg,
      this.workSec,
      this.restSec,
      this.rounds,
      this.pausedSec = 0,
      this.pausedAt,
      Map<String, Object?>? data})
      : data = data ?? <String, Object?>{};

  static LiveDraft? _current;
  static bool _loaded = false;

  /// The session in progress, or null. Read from Prefs once per process, so a
  /// relaunch after a kill still finds a workout that was never finished.
  static LiveDraft? get current {
    if (!_loaded) {
      _loaded = true;
      _current = _decode(Prefs.getString(_key, ''));
    }
    return _current;
  }

  /// Open a draft for a session the app has just accepted.
  static LiveDraft begin(Activity a,
      {bool private = false,
      double? weightKg,
      int? workSec,
      int? restSec,
      int? rounds}) {
    _loaded = true;
    _current = LiveDraft._(a.typeKey,
        startedAt: DateTime.now(),
        private: private,
        weightKg: weightKg,
        workSec: workSec,
        restSec: restSec,
        rounds: rounds);
    _save();
    return _current!;
  }

  /// Drop the in-memory copy WITHOUT touching what was written. The next read
  /// comes off Prefs again — which is what a relaunch after a kill does, and
  /// the only way to test that the entries actually survive one.
  @visibleForTesting
  static void debugForget() {
    _loaded = false;
    _current = null;
  }

  /// The session is over (or was never really there).
  static void clear() {
    _loaded = true;
    _current = null;
    Prefs.setString(_key, '');
  }

  /// Wall-clock seconds this session has been running, pauses removed.
  int get elapsedSec {
    final now = DateTime.now();
    final inPause = pausedAt == null ? 0 : now.difference(pausedAt!).inSeconds;
    final v = now.difference(startedAt).inSeconds - pausedSec - inPause;
    return v < 0 ? 0 : v;
  }

  void setPaused(bool on) {
    if (on) {
      pausedAt ??= DateTime.now();
    } else if (pausedAt != null) {
      pausedSec += DateTime.now().difference(pausedAt!).inSeconds;
      pausedAt = null;
    }
    _save();
  }

  /// Record one of the archetype's entries. Written straight through — the
  /// point of the draft is that nothing waits for a "save".
  void put(String key, Object? value) {
    data[key] = value;
    _save();
  }

  static void _save() {
    final d = _current;
    if (d == null) return Prefs.setString(_key, '');
    Prefs.setString(
        _key,
        jsonEncode({
          'a': d.activityKey,
          'private': d.private,
          'weight': d.weightKg,
          'work_sec': d.workSec,
          'rest_sec': d.restSec,
          'rounds': d.rounds,
          'start': d.startedAt.millisecondsSinceEpoch,
          'paused_sec': d.pausedSec,
          'paused_at': d.pausedAt?.millisecondsSinceEpoch,
          'data': d.data,
        }));
  }

  static LiveDraft? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final key = m['a'];
      final start = m['start'];
      if (key is! String || start is! num) return null;
      return LiveDraft._(
        key,
        startedAt: DateTime.fromMillisecondsSinceEpoch(start.toInt()),
        private: m['private'] == true,
        weightKg: (m['weight'] as num?)?.toDouble(),
        workSec: (m['work_sec'] as num?)?.toInt(),
        restSec: (m['rest_sec'] as num?)?.toInt(),
        rounds: (m['rounds'] as num?)?.toInt(),
        pausedSec: (m['paused_sec'] as num?)?.toInt() ?? 0,
        pausedAt: (m['paused_at'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (m['paused_at'] as num).toInt()),
        data: (m['data'] as Map?)?.cast<String, Object?>(),
      );
    } catch (_) {
      // A draft we cannot read is a draft we do not have.
      return null;
    }
  }
}

/// The live screen for [a]. One switch, nine archetypes, six screens — route,
/// journey, power and basic all measure rather than ask, so they share one.
Widget liveFor(
  Activity a, {
  bool private = false,
  double? weightKg,
  ActivityHost host = ActivityHost.none,

  /// Explicit interval config, from the setup screen that just chose it.
  /// Null falls back to [LiveDraft.current] (a resume/minimise, where the
  /// screen that reopens the session never chose anything itself) and then
  /// to the old 45/30/8 defaults.
  int? intervalWorkSec,
  int? intervalRestSec,
  int? intervalRounds,
}) {
  final p = private || a.private;
  final feed = host.feed;
  final history = host.history;
  final onFinish = host.onFinish;
  return switch (archOf(a)) {
    Arch.strength => LiveStrength(a,
        feed: feed,
        weightKg: weightKg,
        history: history,
        private: p,
        onFinish: onFinish,
        onSets: host.onSets),
    Arch.laps => LiveSwim(a,
        feed: feed, weightKg: weightKg, private: p, onFinish: onFinish),
    Arch.flow => LiveFlow(a,
        feed: feed, weightKg: weightKg, private: p, onFinish: onFinish),
    Arch.match => LiveMatch(a,
        feed: feed, weightKg: weightKg, private: p, onFinish: onFinish),
    Arch.interval => LiveInterval(a,
        feed: feed,
        weightKg: weightKg,
        private: p,
        onFinish: onFinish,
        workSec: intervalWorkSec ?? LiveDraft.current?.workSec ?? 45,
        restSec: intervalRestSec ?? LiveDraft.current?.restSec ?? 30,
        rounds: intervalRounds ?? LiveDraft.current?.rounds ?? 8),
    _ => LiveMeasured(a,
        feed: feed, weightKg: weightKg, private: p, onFinish: onFinish),
  };
}

// ══════════════ THE SHELL ══════════════

class LiveShell extends StatefulWidget {
  final Activity a;
  final String subtitle;
  final bool private;
  final double? weightKg;

  /// The archetype's middle. Rebuilt every tick with elapsed seconds, unless
  /// [bodyFollowsClock] says it has nothing that changes with the clock.
  final Widget Function(BuildContext c, int elapsed) body;

  /// Whether [body] shows anything that moves with the clock or the band.
  /// False builds it once per rebuild of this shell and leaves the 1 Hz tick
  /// alone: a strength session is entirely typed, so ticking redrew a set list
  /// that cannot have changed, once a second, for the length of the workout.
  final bool bodyFollowsClock;

  /// Anything pinned above the transport controls — the strength logger's
  /// "Log set", for instance. It gets no clock: it is rebuilt when the screen
  /// that owns it changes, not on the tick.
  final Widget Function(BuildContext c)? footer;

  /// What this session became, built when the user stops it.
  final ActivityResult Function(int elapsed) result;

  /// Replaces the activity's name and [subtitle] in the header (the strength
  /// logger names the exercise there), and the button at its right.
  final Widget? headerCenter, trailing;

  /// Hands the finished session to the app to be persisted, and takes back
  /// whatever the stores can add to it. Absent in tests and previews.
  final SessionFinish? onFinish;

  /// Replaces the minimise chevron at the header's left.
  final Widget? leading;

  /// Replaces [footer] and the pause / finish row: the screen draws its own
  /// bottom bar and is handed the shell's finish.
  final Widget Function(BuildContext c, VoidCallback finish)? bottom;

  /// False when [body] scrolls itself (a reorderable list cannot sit inside
  /// the shell's own ListView).
  final bool scrollBody;

  const LiveShell(
    this.a, {
    super.key,
    required this.body,
    required this.result,
    this.bodyFollowsClock = true,
    this.subtitle = '',
    this.private = false,
    this.weightKg,
    this.footer,
    this.onFinish,
    this.headerCenter,
    this.trailing,
    this.leading,
    this.bottom,
    this.scrollBody = true,
  });

  @override
  State<LiveShell> createState() => LiveShellState();
}

class LiveShellState extends State<LiveShell> {
  /// Seeded from the draft, so reopening a minimised session — or relaunching
  /// after a kill — carries on from where the session actually is rather than
  /// from zero.
  ///
  /// A listenable rather than a field behind `setState`: the tick used to
  /// rebuild and re-lay-out this whole screen once a second for the length of
  /// a workout — header, transport controls and all — when the only thing that
  /// moves is the middle.
  late final ValueNotifier<int> clock =
      ValueNotifier<int>(LiveDraft.current?.elapsedSec ?? 0);
  int get elapsed => clock.value;
  late bool paused = LiveDraft.current?.pausedAt != null;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    // The session clock is real time, not motion: it runs whether or not the
    // platform wants animation, and it stops in dispose so nothing outlives
    // the screen. With a draft it is READ from wall time rather than counted
    // in ticks — a screen that was backgrounded for ten minutes must not come
    // back ten minutes behind the session it is drawing.
    _t = Timer.periodic(Motion.tick, (_) {
      if (!mounted) return;
      final d = LiveDraft.current;
      if (d != null) {
        clock.value = d.elapsedSec;
      } else if (!paused) {
        clock.value++;
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    clock.dispose();
    super.dispose();
  }

  bool _finishing = false;

  Future<void> finish() async {
    // Stopping twice would stop the app's session twice and save the strength
    // log twice; the second tap must do nothing at all.
    if (_finishing) return;
    _finishing = true;
    _t?.cancel();
    final draft = widget.result(elapsed);
    // The app writes the session, flushes the GPS tail and hands back what it
    // could add. A failure here must still land the user on their summary —
    // losing the screen is worse than losing the enrichment.
    var result = draft;
    // A throw here is `stopWorkout` or the strength write failing, which means
    // the session is NOT in the database. The summary still opens, because
    // losing the screen is worse — but it is told, so it can say so and offer
    // the retry instead of drawing a plausible summary of nothing.
    final onFinish = widget.onFinish;
    Future<ActivityResult> Function()? retrySave;
    try {
      result = await onFinish?.call(draft) ?? draft;
    } catch (_) {
      result = draft;
      retrySave = onFinish == null ? null : () => onFinish(draft);
    }
    // The session is over: no draft to reopen, and no resume bar.
    LiveDraft.clear();
    if (!mounted) return;
    // Everything under the summary belongs to setting this session up —
    // picker, setup, the live screen itself. Back from a summary used to land
    // on "choose an activity", immediately after finishing one.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        // `justFinished` — TS-09's prompt is asked here and only here. On a
        // failed write `result` is the draft, which carries no session id, so
        // the prompt does not appear over a session that is not in the
        // database.
        builder: (_) => ActivitySummary(result,
            weightKg: widget.weightKg,
            onRetrySave: retrySave,
            justFinished: true),
      ),
      (r) => r.isFirst,
    );
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final a = widget.a;
    // Char in both themes: a workout is watched from arm's length, often
    // outdoors, and this is the one full-bleed dark screen light mode allows.
    // Everything below reads its palette inside the override.
    return AlwaysChar(child: Builder(builder: (c) => _shell(c, P.of(c), l, a)));
  }

  Widget _shell(BuildContext c, P p, AppLocalizations? l, Activity a) {
    return Scaffold(
      backgroundColor: p.bg,
      // The clock reaches the header and the bottom bar too: a strength
      // session draws its timer in the header and its set clock in the pill.
      body: _LiveClock(clock, child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x5),
            child: Row(children: [
              // A real minimise: the session lives on [LiveDraft], not on this
              // route, so leaving the screen — by this chevron, by Android
              // back, or by an iOS edge-swipe — puts it away rather than
              // destroying it. The bar above the tab bar brings it back.
              widget.leading ??
                  RoundIconButton(
                    LucideIcons.chevronDown,
                    () => Navigator.maybePop(c),
                    l?.activityLiveMinimiseLabel ?? 'Minimise',
                  ),
                  Expanded(
                    child: widget.headerCenter ?? Column(
                      children: [
                        Text(
                          a.displayName(c).toUpperCase(),
                          style: F.over.copyWith(color: p.on(a.color)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  if (widget.subtitle.isNotEmpty)
                    Text(widget.subtitle,
                        style: F.over.copyWith(color: p.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ]),
              ),
              // Balances the minimise button, so the title stays centred.
              widget.trailing ??
                  SizedBox(
                    width: S.x12,
                    child: widget.private
                        ? Icon(LucideIcons.lock, size: I.md, color: p.ink3)
                        : null,
                  ),
            ]),
          ),
          Expanded(
            // The tick reaches the body and stops there. A body that does not
            // follow the clock is handed through as `child`, which is the same
            // widget instance on every tick — so its whole subtree is skipped
            // rather than rebuilt — and the parts of it that DO move once a
            // second ask for the tick themselves, through [LiveTick].
            child: _LiveClock(
              clock,
              child: !widget.scrollBody
                  ? Builder(builder: (bc) => widget.body(bc, clock.value))
                  : Builder(
                builder: (bc) => ValueListenableBuilder<int>(
                  valueListenable: clock,
                  child: widget.bodyFollowsClock
                      ? null
                      : widget.body(bc, clock.value),
                  builder: (bc2, e, child) => ListView(
                    padding: const EdgeInsets.fromLTRB(S.x5, 0, S.x5, S.x4),
                    children: [child ?? widget.body(bc2, e)],
                  ),
                ),
              ),
            ),
          ),
          if (widget.bottom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x5, S.x3, S.x5, S.x4),
              child: widget.bottom!(c, finish),
            ),
          if (widget.bottom == null && widget.footer != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x5),
              child: widget.footer!(c),
            ),
          if (widget.bottom == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x5, S.x4, S.x5, S.x5),
            child: Row(children: [
              // A control with no callback is announced as content and does
              // nothing when activated. Locking the screen is not implemented,
              // so the affordance is not drawn.
              //
              // The screen's one primary control, in the START pill's blue,
              // unless the screen has a bigger one above it (Log set), which
              // then keeps the blue to itself.
              Expanded(
                child: Pressable(
                  semanticLabel: paused
                      ? (l?.activityLiveResumeLabel ?? 'Resume')
                      : (l?.activityLivePauseLabel ?? 'Pause'),
                  onTap: () => setState(() {
                    paused = !paused;
                    LiveDraft.current?.setPaused(paused);
                  }),
                  child: Container(
                    height: S.x12 + S.x2,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: widget.footer == null ? C.dialStrain : p.card2,
                        borderRadius: R.rPill),
                    child: Icon(
                        paused ? LucideIcons.play : LucideIcons.pause,
                        size: I.lg,
                        color: widget.footer == null ? C.white : p.ink),
                  ),
                ),
              ),
              const SizedBox(width: S.x4),
              _round(p, LucideIcons.square, p.card2, p.on(C.red),
                  l?.activityLiveFinishSessionLabel ?? 'Finish session',
                  finish),
            ]),
          ),
        ]),
      )),
    );
  }

  Widget _round(P p, IconData i, Color bg, Color fg, String label,
          VoidCallback? onTap) =>
      Pressable(
        semanticLabel: label,
        onTap: onTap,
        child: Container(
          width: S.x12 + S.x2,
          height: S.x12 + S.x2,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(i, size: I.md, color: fg),
        ),
      );
}

/// The shell's clock, offered to the body without subscribing anyone to it.
/// Looked up with `getInheritedWidgetOfExactType` (see [LiveTick]) rather than
/// depended on, because depending on it is the 1 Hz whole-screen rebuild this
/// exists to avoid.
class _LiveClock extends InheritedWidget {
  final ValueNotifier<int> clock;
  const _LiveClock(this.clock, {required super.child});

  @override
  bool updateShouldNotify(_LiveClock old) => old.clock != clock;
}

/// The one part of a body that does follow the clock, in a body that mostly
/// does not. Outside a [LiveShell] it builds once at zero, which is what a
/// preview or a widget test wants.
class LiveTick extends StatelessWidget {
  final Widget Function(BuildContext c, int elapsed) builder;
  const LiveTick(this.builder, {super.key});

  @override
  Widget build(BuildContext c) {
    final clock = c.getInheritedWidgetOfExactType<_LiveClock>()?.clock;
    return clock == null
        ? builder(c, 0)
        : ValueListenableBuilder<int>(
            valueListenable: clock,
            builder: (bc, e, _) => builder(bc, e));
  }
}

// ══════════════ SHARED PIECES ══════════════

/// The one big number. [F.n48] and no bigger — a display size that only
/// exists on one screen is how seven type steps became forty.
/// Speak a transition. A haptic reaches a wrist and nothing else — the two
/// moments a paced session actually has to announce (rest is over, work
/// begins) were buzz-only, so a screen-reader user driving an interval workout
/// had no signal at all.
void say(BuildContext c, String what) =>
    SemanticsService.sendAnnouncement(View.of(c), what, TextDirection.ltr);

/// [ExcludeSemantics] because it is rebuilt every second for the length of a
/// workout: left in the tree it re-announces itself at 1 Hz, which makes a
/// screen reader unusable for exactly as long as the session lasts. The
/// elapsed time is on the shell's own label; the moments worth hearing are
/// announced explicitly (see [say]).
Widget bigNum(P p, String v, String unit) => ExcludeSemantics(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
            child: Text(v,
                style: F.n48.copyWith(color: p.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
        if (unit.isNotEmpty) ...[
          const SizedBox(width: S.x2),
          Text(unit, style: F.t2.copyWith(color: p.ink3)),
        ],
      ],
    ));

/// Up to three supporting numbers. A stat with nothing behind it is omitted,
/// never rendered as a dash — and an entirely empty row is no row.
Widget statRow(P p, List<(String, String)> items) => items.isEmpty
    ? const SizedBox.shrink()
    : Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(width: 1, height: 36, color: p.line),
          Expanded(
            child: Column(children: [
              Text(items[i].$1, style: F.n24.copyWith(color: p.ink)),
              const SizedBox(height: S.x1),
              Text(items[i].$2,
                  style: F.over.copyWith(color: p.ink3),
                  textAlign: TextAlign.center),
            ]),
          ),
        ],
      ],
      );

Widget counterButton(P p, IconData i, Color col, String label,
        VoidCallback onTap,
        {double size = 56}) =>
    Pressable(
      semanticLabel: label,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: p.card2, shape: BoxShape.circle),
        child: Icon(i, size: size * .42, color: col),
      ),
    );

/// The live heart-rate block, or an honest absence.
class LiveHeart extends StatelessWidget {
  final LiveFeed feed;
  const LiveHeart(this.feed, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    if (feed.hr == null) {
      // One card used to cover both, and it told a user whose band had
      // dropped mid-session to adjust the fit of a band that was not there.
      return feed.bandConnected
          ? StatusCard(
              l?.activityLiveNoHrYetTitle ?? 'No heart rate yet',
              l?.activityLiveNoHrYetBody ??
                  'The band is connected but has not reported a beat, so it '
                      'needs to be snug, a finger-width above the wrist bone.',
              icon: LucideIcons.heartPulse,
            )
          : StatusCard(
              l?.activityLiveNoHrTitle ?? 'No heart rate',
              l?.activityLiveNoHrBody ??
                  'The band is not connected, so nothing is arriving for '
                      'this session.',
              icon: LucideIcons.heartPulse,
            );
    }
    final z = feed.zone;
    return Column(children: [
      // A Wrap, not a Row: the beat, its unit and the zone pill fit one line
      // at a normal text size and overflowed the live screen by 64 px at an
      // accessibility one. Two lines is the honest answer; a clipped heart
      // rate on a screen the user is exercising in front of is not.
      //
      // The heart rate is the screen's hero, at n64 — scaled down inside
      // the line rather than clipped when an accessibility size makes it wider
      // than the phone.
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: S.x2,
        runSpacing: S.x1,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Icon(LucideIcons.heart, size: I.lg, color: p.ink),
                  const SizedBox(width: S.x2),
                  Text('${feed.hr}', style: F.n64.copyWith(color: p.ink)),
                  const SizedBox(width: S.x1),
                  Text(l?.activityLiveBpmUnit ?? 'bpm',
                      style: F.body.copyWith(color: p.ink3)),
                ]),
          ),
          if (z != null)
            // The zone's OWN colour, the one the bar underneath paints it in. A
            // fixed green said "zone 5" and "zone 1" in the same breath.
            Pill(l?.activityLiveZoneLabel(z) ?? 'Zone $z',
                ZoneRows.pigment[(z - 1).clamp(0, 4)]),
        ],
      ),
      // The session so far, minute by minute, in coral: the live line. A
      // shape under the number, not a chart to read values off — the summary
      // is where the curve gets its axis. Gaps stay gaps (the painter breaks
      // at a null), and with fewer than two minutes there is no line.
      if (feed.hrCurve.whereType<double>().length >= 2) ...[
        const SizedBox(height: S.x3),
        ExcludeSemantics(
          child: SizedBox(
            height: S.x16,
            child: CustomPaint(
              size: Size.infinite,
              painter: LineChart(feed.hrCurve, p.on(C.coral),
                  fill: false, dotInk: p.bg),
            ),
          ),
        ),
      ],
      if (feed.zoneMinutes.length == 5) ...[
        const SizedBox(height: S.x4),
        ZoneRows(feed.zoneMinutes,
            lowerBpm: feed.zoneLowerBpm,
            title: l?.activityLiveTimeInZonesTitle ?? 'Time in zones'),
      ],
    ]);
  }

}

/// Why this session is being recorded without a route, and the one thing that
/// would fix it. The session keeps running either way — a missing map is not a
/// reason to stop a run — but it is named rather than left blank.
Widget? _routeIssueCard(
    BuildContext c, GpsPermissionStatus? issue, VoidCallback? onFix) {
  final l = AppLocalizations.of(c);
  return switch (issue) {
    null => null,
    // Title and action, no body. The body was cut as slop; the AFFORDANCE is
    // not slop — denied is the one branch a user can actually resolve from
    // here, and dropping the whole card left them with a missing map and no
    // way to fix it.
    GpsPermissionStatus.denied => StatusCard(
        l?.activityLiveNoRouteNotAllowedTitle ??
            'No route: location not allowed',
        '',
        fix: l?.activityLiveAllowLocation ?? 'Allow location',
        onFix: onFix,
        icon: LucideIcons.mapPin,
      ),
    GpsPermissionStatus.serviceOff => StatusCard(
        l?.activityLiveNoRouteOffTitle ?? 'No route: location is off',
        l?.activityLiveNoRouteOffBody ??
            'Location services are off on this phone, so no fixes are '
                'arriving.',
        fix: l?.activityLiveTurnOnLocation ?? 'Turn on location',
        onFix: onFix,
        icon: LucideIcons.mapPin,
      ),
    GpsPermissionStatus.deniedForever => StatusCard(
        l?.activityLiveNoRouteNotAllowedTitle ??
            'No route: location not allowed',
        l?.activityLiveDeniedForeverBody ??
            'Location is denied for this app, which only Settings can '
                'change.',
        fix: l?.activityLiveOpenSettings ?? 'Open Settings',
        onFix: onFix,
        icon: LucideIcons.mapPin,
      ),
    // `granted` cannot reach here: it is never stored as an issue.
    _ => StatusCard(
        l?.activityLiveNoRouteFailedTitle ?? 'No route: location failed',
        l?.activityLiveNoRouteFailedBody ??
            'The phone returned an error when asked for a fix.',
        fix: l?.activityLiveTryAgain ?? 'Try again',
        onFix: onFix,
        icon: LucideIcons.mapPin,
      ),
  };
}

/// MET-derived calories for the elapsed time, or the feed's own figure when
/// the band produced one. Null when body weight is unknown — the whole point
/// of the MET formula is that it needs a mass.
int? _kcal(Activity a, LiveFeed feed, double? weightKg, int elapsed) =>
    feed.calories ?? a.kcal(weightKg, (elapsed / 60).round());

/// The distance/pace pair plus the common three-up, in the user's units.
///
/// PACE IS OMITTED, never dashed, when there isn't one yet: at the start of a
/// run a few metres of GPS jitter divided into real elapsed time reads as
/// something like 1000 min/km, which [UnitsController.formatPace] refuses by
/// returning null. A stat that has no value is not drawn.
List<Widget> _distanceStats(BuildContext ctx, P p, LiveFeed f, Activity a,
    double? weightKg, int elapsed) {
  final u = unitsOf(ctx);
  final km = f.distanceKm;
  final meters = km == null ? null : km * 1000;
  final value = meters == null
      ? null
      : (u == null ? meters / 1000 : u.distanceValue(meters));
  final unit = u?.distanceUnit ?? 'km';
  final pacePerUnit = (meters == null || meters <= 0)
      ? null
      : UnitsController.formatPace(
          elapsed / (u == null ? meters / 1000 : u.distanceValue(meters)));
  return [
    statRow(p, [
      if (value != null) (value.toStringAsFixed(2), unit),
      if (pacePerUnit != null) (pacePerUnit, '/$unit'),
      ..._commonStats(ctx, a, f, weightKg, elapsed),
    ].take(3).toList()),
  ];
}

/// "5.24 km" / "3.25 mi" for a distance already known to exist.
String _distanceText(BuildContext c, double km) {
  final u = unitsOf(c);
  return u == null
      ? '${km.toStringAsFixed(2)} km'
      : u.distance(km * 1000)!; // non-null in, non-null out
}

String _distanceUnit(BuildContext c) => unitsOf(c)?.distanceUnit ?? 'km';

/// Display text for a swim stroke — [key] stays the canonical English value
/// stored on the session (see [LiveSwim]'s `strokes` and [_baseResult]'s
/// `stroke:`); only what the user reads is translated.
String _strokeLabel(BuildContext c, String key) {
  final l = AppLocalizations.of(c);
  return switch (key) {
    'Free' => l?.activityLiveStrokeFree ?? 'Free',
    'Back' => l?.activityLiveStrokeBack ?? 'Back',
    'Breast' => l?.activityLiveStrokeBreast ?? 'Breast',
    'Fly' => l?.activityLiveStrokeFly ?? 'Fly',
    _ => key,
  };
}

/// Display text for a yoga pose — [key] stays the canonical English value
/// stored in [LiveFlow]'s `poses` and passed to [_baseResult]'s `poses:`.
String _poseLabel(BuildContext c, String key) {
  final l = AppLocalizations.of(c);
  return switch (key) {
    'Mountain' => l?.activityLivePoseMountain ?? 'Mountain',
    'Forward fold' => l?.activityLivePoseForwardFold ?? 'Forward fold',
    'Plank' => l?.activityLivePosePlank ?? 'Plank',
    'Warrior II' => l?.activityLivePoseWarriorTwo ?? 'Warrior II',
    'Triangle' => l?.activityLivePoseTriangle ?? 'Triangle',
    'Chair' => l?.activityLivePoseChair ?? 'Chair',
    'Pigeon' => l?.activityLivePosePigeon ?? 'Pigeon',
    'Bridge' => l?.activityLivePoseBridge ?? 'Bridge',
    "Child's pose" => l?.activityLivePoseChildsPose ?? "Child's pose",
    'Savasana' => l?.activityLivePoseSavasana ?? 'Savasana',
    _ => key,
  };
}

/// The three-up row every live screen ends with.
List<(String, String)> _commonStats(
    BuildContext c, Activity a, LiveFeed feed, double? weightKg, int elapsed) {
  final l = AppLocalizations.of(c);
  final kcal = _kcal(a, feed, weightKg, elapsed);
  final goal = double.tryParse(Prefs.getString(Prefs.activityStrainTarget, ''));
  return [
    if (kcal != null) ('$kcal', l?.activityLiveKcalEstUnit ?? 'kcal · est'),
    if (feed.strain != null)
      (
        // Against the goal set on Start Activity, when there is one.
        goal == null
            ? feed.strain!.toStringAsFixed(1)
            : '${feed.strain!.toStringAsFixed(1)}/${goal.toStringAsFixed(1)}',
        l?.activityLiveStrainUnit ?? 'strain'
      ),
    if (feed.steps != null) ('${feed.steps}', l?.activityLiveStepsUnit ?? 'steps'),
  ];
}

ActivityResult _baseResult(
  Activity a,
  LiveFeed feed,
  double? weightKg,
  int elapsed,
  bool private, {
  StrengthLog strength = StrengthLog.empty,
  List<int> lapSecs = const [],
  int? poolLengthM,
  String? stroke,
  List<IntervalRound> rounds = const [],
  List<String> poses = const [],
  List<(int, int)> gameScore = const [],
}) =>
    ActivityResult(
      a,
      // When the session was really started. Derived from the elapsed clock
      // only without a draft (tests, previews) — and that derivation is wrong
      // for a paused session, which began earlier than `now - elapsed`.
      //
      // `Motion.tick * elapsed` rather than a literal: theme.dart is the only
      // file allowed to spell a Duration, and one second times N seconds is
      // exactly what this is.
      start: LiveDraft.current?.startedAt ??
          DateTime.now().subtract(Motion.tick * elapsed),
      duration: Motion.tick * elapsed,
      private: private,
      // The AVERAGE, from the per-minute curve. This used to be `feed.hr` —
      // the single instantaneous sample that happened to be on screen when
      // the user pressed stop, labelled "Avg HR" on the summary.
      avgHr: feed.avgHr,
      maxHr: feed.maxHr,
      calories: _kcal(a, feed, weightKg, elapsed),
      strain: feed.strain,
      hr: feed.hrCurve,
      zoneMinutes: feed.zoneMinutes,
      zoneSource: feed.zoneSource,
      zoneMaxHr: feed.zoneMaxHr,
      zoneLowerBpm: feed.zoneLowerBpm,
      // The same count the live screen has printed all session, carried onto
      // the summary it hands over to. Null stays null: `stopWorkout` only banks
      // `sessions.steps` when there is one, so an unmeasured session reads the
      // same before and after it is stored.
      steps: feed.steps,
      route: feed.route,
      distanceKm: feed.distanceKm,
      strength: strength,
      lapSecs: lapSecs,
      poolLengthM: poolLengthM,
      stroke: stroke,
      rounds: rounds,
      poses: poses,
      gameScore: gameScore,
    );

// ══════════════ MEASURED — route, journey, power, basic ══════════════

class LiveMeasured extends StatelessWidget {
  final Activity a;
  final LiveFeedSource? feed;
  final double? weightKg;
  final bool private;
  final SessionFinish? onFinish;

  const LiveMeasured(this.a,
      {super.key,
      this.feed,
      this.weightKg,
      this.private = false,
      this.onFinish});

  @override
  Widget build(BuildContext c) {
    return LiveShell(
      a,
      private: private,
      weightKg: weightKg,
      onFinish: onFinish,
      result: (elapsed) =>
          _baseResult(a, feed?.call() ?? LiveFeed.none, weightKg, elapsed,
              private),
      body: (ctx, elapsed) {
        final p = P.of(ctx);
        final l = AppLocalizations.of(ctx);
        final f = feed?.call() ?? LiveFeed.none;
        return Column(children: [
          const SizedBox(height: S.x6),
          Text(l?.activityLiveDurationHeader ?? 'DURATION',
              style: F.over.copyWith(color: p.ink3)),
          const SizedBox(height: S.x3),
          bigNum(p, clock(elapsed), ''),
          // Only once fixes are actually arriving. The catalogue's `gps` flag
          // says a route is WORTH recording, not that one is being recorded —
          // it claimed "GPS ACTIVE" with location denied.
          if (f.gpsActive) ...[
            const SizedBox(height: S.x3),
            Pill(l?.activityLiveRecordingRoute ?? 'Recording route', C.green,
                icon: LucideIcons.mapPin),
          ] else if (_routeIssueCard(ctx, f.routeIssue, f.onFixRoute)
              case final card?) ...[
            const SizedBox(height: S.x4),
            card,
          ],
          const SizedBox(height: S.x8),
          // The user's own unit system, not km hardcoded. `unitsOf` is null in
          // a golden, and the metric fallback there is what the store holds.
          ..._distanceStats(ctx, p, f, a, weightKg, elapsed),
          const SizedBox(height: S.x8),
          LiveHeart(f),
          if (f.route.length > 1) ...[
            const SizedBox(height: S.x5),
            ChartFrame(
              title: l?.activityLiveRouteSoFarTitle ?? 'Route so far',
              unit: _distanceUnit(ctx),
              height: 150,
              footnote: f.distanceKm == null
                  ? (l?.activityLiveRouteFootnoteNoDistance ??
                      'Start pinned; distance appears once the fixes settle.')
                  : (l?.activityLiveRouteFootnoteWithDistance(
                          _distanceText(ctx, f.distanceKm!)) ??
                      '${_distanceText(ctx, f.distanceKm!)} from the fixes '
                          'recorded so far.'),
              child: ClipRRect(
                borderRadius: R.rLg,
                child: Container(
                  color: p.card2,
                  child: CustomPaint(
                      size: Size.infinite,
                      painter: RouteMap(f.route,
                          slow: p.on(a.color),
                          fast: p.on(a.color),
                          pinStart: p.on(C.green),
                          pinEnd: p.on(C.red),
                          pinInk: p.card)),
                ),
              ),
            ),
          ],
          if (private) ...[
            const SizedBox(height: S.x5),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(LucideIcons.lock, size: I.sm, color: p.ink3),
              const SizedBox(width: S.x1),
              Text(l?.activityLivePrivateSession ?? 'Private session',
                  style: F.over.copyWith(color: p.ink3)),
            ]),
          ],
        ]);
      },
    );
  }
}

// ══════════════ STRENGTH — everything here is typed ══════════════

class LiveStrength extends StatefulWidget {
  final Activity a;
  final LiveFeedSource? feed;
  final double? weightKg;
  final bool private;
  final Map<String, SetHistory> history;
  final SessionFinish? onFinish;

  /// Banks the log on every change. See [ActivityHost.onSets].
  final void Function(List<LoggedSet>)? onSets;

  const LiveStrength(this.a,
      {super.key,
      this.feed,
      this.weightKg,
      this.private = false,
      this.history = const {},
      this.onFinish,
      this.onSets});

  @override
  State<LiveStrength> createState() => _LiveStrengthState();
}

class _LiveStrengthState extends State<LiveStrength> {
  /// The exercises this session has touched, in the order they were added.
  final plan = <String>[];
  int index = 0;

  int rpe = 7;

  final logged = <LoggedSet>[];

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Plan and sets written before this screen was rebuilt — the session was
  /// minimised, or the process was killed and relaunched.
  void _restore() {
    final draft = LiveDraft.current;
    if (draft == null) return;
    final savedPlan = draft.data['exercise_plan'];
    if (savedPlan is List) {
      for (final value in savedPlan) {
        if (value is String && value.isNotEmpty && !plan.contains(value)) {
          plan.add(value);
        }
      }
    }
    final saved = draft.data['sets'];
    if (saved is List) {
      for (final e in saved) {
        if (e is! Map) continue;
        final k = e['k'];
        if (k is! String) continue;
        logged.add(LoggedSet(
          k,
          (e['reps'] as num?)?.toInt() ?? 0,
          loadKg: (e['kg'] as num?)?.toDouble(),
          rpe: (e['rpe'] as num?)?.toInt(),
          restSec: (e['rest'] as num?)?.toInt(),
          at: DateTime.fromMillisecondsSinceEpoch(
              (e['at'] as num?)?.toInt() ?? 0),
        ));
        if (!plan.contains(k)) plan.add(k);
      }
    }
    if (plan.isEmpty) return;
    final savedIndex = (draft.data['exercise_index'] as num?)?.toInt();
    if (savedIndex != null && savedIndex >= 0 && savedIndex < plan.length) {
      index = savedIndex;
    } else if (logged.isNotEmpty) {
      index = plan.indexOf(logged.last.exerciseKey);
    }
  }

  /// Write the log through — to the draft, so minimising cannot lose it, and
  /// to the app, which banks it against the open session row. Called on every
  /// change rather than at finish: `saveStrengthSets` replaces by sequence, so
  /// re-sending the whole log is the same rows every time.
  void _persist() {
    LiveDraft.current?.put('sets', [
      for (final s in logged)
        {
          'k': s.exerciseKey,
          'reps': s.reps,
          'kg': s.loadKg,
          'rpe': s.rpe,
          'rest': s.restSec,
          'at': s.at.millisecondsSinceEpoch,
        },
    ]);
    _persistPlan();
    widget.onSets?.call(List.of(logged));
  }

  void _persistPlan() {
    LiveDraft.current?.put('exercise_plan', List<String>.of(plan));
    LiveDraft.current?.put('exercise_index', index);
  }

  String get key => plan[index];
  ExerciseDef? get def => exerciseByKey(key);
  List<LoggedSet> get setsHere =>
      [for (final s in logged) if (s.exerciseKey == key) s];
  StrengthLog get log => StrengthLog(logged);

  void goExercise(int i) {
    if (i < 0 || i >= plan.length) return;
    setState(() => index = i);
    _persistPlan();
  }

  Future<void> addExercise() async {
    final picked = await showExercisePicker(
      context,
      mode: plan.isEmpty ? ExercisePickMode.choose : ExercisePickMode.add,
      selectedKeys: plan.toSet(),
      recentKeys: _recentKeys,
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (!plan.contains(picked)) plan.add(picked);
      index = plan.indexOf(picked);
    });
    _persistPlan();
  }

  /// Replace an empty slot; once it has sets, switch/add instead so logged
  /// sets keep their exercise.
  Future<void> changeExercise() async {
    if (plan.isEmpty) return addExercise();
    final oldIndex = index;
    final mayReplace = setsHere.isEmpty;
    final picked = await showExercisePicker(
      context,
      mode: ExercisePickMode.change,
      selectedKeys: plan.toSet(),
      recentKeys: _recentKeys,
    );
    if (!mounted || picked == null || picked == plan[oldIndex]) return;
    setState(() {
      final existing = plan.indexOf(picked);
      if (mayReplace) {
        if (existing < 0) {
          plan[oldIndex] = picked;
          index = oldIndex;
        } else {
          plan.removeAt(oldIndex);
          index = plan.indexOf(picked);
        }
      } else {
        if (existing < 0) plan.add(picked);
        index = plan.indexOf(picked);
      }
    });
    _persistPlan();
  }

  void skipExercise() {
    if (setsHere.isEmpty && plan.length > 1) {
      setState(() {
        plan.removeAt(index);
        if (index >= plan.length) index = plan.length - 1;
      });
      _persistPlan();
      } else if (index < plan.length - 1) {
      goExercise(index + 1);
    }
  }

  List<String> get _recentKeys {
    final entries = widget.history.entries.toList()
      ..sort((a, b) {
        final aa = a.value.previous?.at.millisecondsSinceEpoch ?? 0;
        final bb = b.value.previous?.at.millisecondsSinceEpoch ?? 0;
        return bb.compareTo(aa);
      });
    return [for (final entry in entries) entry.key];
  }

  // ── THE SESSION AS A LIST OF EXERCISE CARDS ──────────────────────────────
  // Every exercise is a card with its own set table (reps, weight, ▶ per
  // row); the row being lifted is outlined. START SET opens a set and starts
  // its clock, FINISH SET logs it. Cards reorder by their handle mid-session,
  // and a card's planned rows are edited in place. Sizes follow the compact
  // reference: 36 pt inputs, 32 pt row controls, one 44 pt pill.

  /// 0 the live session, 1 the exercise list.
  int _tab = 0;

  /// When the open set began; null between sets.
  DateTime? _setStartedAt;

  /// The planned rows per exercise, editable until logged.
  final _rows = <String, List<_SetRow>>{};
  final _ctrls = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final t in _ctrls.values) {
      t.dispose();
    }
    super.dispose();
  }

  int _done(String k) => logged.where((s) => s.exerciseKey == k).length;

  /// A built workout's plan, else last time's set three times, else 8 reps at
  /// 40 kg (or bodyweight for a bodyweight lift) — the old stepper's start.
  List<_SetRow> _rowsFor(String k) => _rows.putIfAbsent(k, () {
        final all = LiveDraft.current?.data['planned'];
        final list = all is Map ? all[k] : null;
        if (list is List && list.isNotEmpty) {
          return [
            for (final e in list)
              if (e is Map)
                _SetRow((e['reps'] as num?)?.toInt() ?? 8,
                    (e['kg'] as num?)?.toDouble()),
          ];
        }
        final prev = widget.history[k]?.previous;
        final bw = prev != null
            ? prev.loadKg == null
            : exerciseByKey(k)?.bodyweight ?? false;
        final kg0 = bw ? null : (prev?.loadKg ?? 40.0);
        return [for (var i = 0; i < 3; i++) _SetRow(prev?.reps ?? 8, kg0)];
      });

  int _rowCount(String k) => math.max(_rowsFor(k).length, _done(k));

  void _persistRows() {
    final all = LiveDraft.current?.data['planned'];
    LiveDraft.current?.put('planned', {
      if (all is Map) ...all,
      for (final e in _rows.entries)
        e.key: [for (final r in e.value) {'reps': r.reps, 'kg': r.kg}],
    });
  }

  /// Start the set on the current exercise, or finish (log) the open one.
  void _startOrFinish() {
    if (plan.isEmpty) {
      addExercise();
      return;
    }
    if (_setStartedAt != null) {
      _finishSet();
      return;
    }
    // A finished exercise hands over to the next one with rows left.
    if (_done(key) >= _rowCount(key)) {
      final next = plan.indexWhere((k) => _done(k) < _rowCount(k));
      if (next >= 0) {
        index = next;
      } else {
        _rowsFor(key).add(_rowsFor(key).last.copy());
        _persistRows();
      }
    }
    HapticFeedback.selectionClick();
    setState(() => _setStartedAt = DateTime.now());
    _persistPlan();
  }

  void _finishSet() {
    final k = key;
    final i = _done(k);
    final rows = _rowsFor(k);
    if (i >= rows.length) rows.add(rows.last.copy());
    final r = rows[i];
    HapticFeedback.mediumImpact();
    final now = DateTime.now();
    // The rest ACTUALLY taken before this set, not a target.
    final prior = logged.isEmpty ? null : logged.last.at;
    setState(() {
      logged.add(LoggedSet(k, r.reps,
          loadKg: r.kg,
          rpe: rpe,
          restSec: prior == null ? null : now.difference(prior).inSeconds,
          at: now));
      _setStartedAt = null;
      if (_done(k) >= _rowCount(k)) {
        final next = plan.indexWhere((x) => _done(x) < _rowCount(x));
        if (next >= 0) index = next;
      }
    });
    _persistRows();
    _persist();
  }

  /// A row's ▶: the open row finishes, another exercise's next row starts.
  void _play(String k) {
    if (_setStartedAt != null && k == key) return _finishSet();
    if (_setStartedAt != null) _finishSet();
    setState(() => index = plan.indexOf(k));
    _startOrFinish();
  }

  void _reorder(int from, int to) {
    if (to > from) to--;
    if (from == to) return;
    final current = key;
    setState(() {
      plan.insert(to, plan.removeAt(from));
      index = plan.indexOf(current);
    });
    _persistPlan();
  }

  void _removeExercise(String k) {
    if (_done(k) > 0 || plan.length < 2) return;
    final current = key;
    setState(() {
      plan.remove(k);
      _rows.remove(k);
      index = math.max(0, plan.indexOf(current));
    });
    _persistPlan();
    _persistRows();
  }

  void _addRow(String k) {
    final rows = _rowsFor(k);
    setState(() => rows.add(rows.isEmpty ? _SetRow(8, null) : rows.last.copy()));
    _persistRows();
  }

  void _dropRow(String k) {
    final rows = _rowsFor(k);
    if (rows.length <= math.max(1, _done(k))) return;
    setState(() => rows.removeLast());
    _persistRows();
  }

  TextEditingController _ctrl(String id, String text) =>
      _ctrls.putIfAbsent(id, () => TextEditingController(text: text));

  @override
  Widget build(BuildContext c) {
    return LiveShell(
      widget.a,
      private: widget.private,
      weightKg: widget.weightKg,
      onFinish: widget.onFinish,
      result: (elapsed) => _baseResult(widget.a,
          widget.feed?.call() ?? LiveFeed.none, widget.weightKg, elapsed,
          widget.private,
          strength: log),
      leading: _iconButton(c, LucideIcons.ellipsis, 'More', _more),
      headerCenter: Builder(builder: _header),
      trailing: _iconButton(c, LucideIcons.plus,
          AppLocalizations.of(c)?.activityLiveAddExerciseTitle ?? 'Add exercise',
          addExercise),
      bodyFollowsClock: false,
      scrollBody: false,
      body: (ctx, _) => _body(ctx),
      bottom: _bottom,
    );
  }

  /// A bare 40 pt glyph button, as the reference's header draws them.
  Widget _iconButton(BuildContext c, IconData i, String label, VoidCallback f) =>
      Pressable(
        semanticLabel: label,
        onTap: f,
        child: SizedBox.square(
          dimension: S.x10,
          child: Icon(i, size: I.lg, color: P.of(c).ink),
        ),
      );

  Widget _header(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final name = LiveDraft.current?.data['workout_name'];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
          (name is String && name.isNotEmpty ? name : widget.a.displayName(c))
              .toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
      LiveTick((tc, e) {
        final hr = plan.isEmpty ? null : (widget.feed?.call() ?? LiveFeed.none).hr;
        return Text.rich(TextSpan(children: [
          TextSpan(
              text: _hms(e),
              style: F.body.copyWith(
                  color: p.ink2,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          // Only while the band reads: no heart rate is an empty space.
          if (hr != null) ...[
            TextSpan(
                text: '  $hr',
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
            TextSpan(
                text: ' ${l?.activityLiveBpmUnit.toUpperCase() ?? 'BPM'}',
                style: F.over.copyWith(color: p.ink3)),
          ],
        ]));
      }),
    ]);
  }

  static String _hms(int sec) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(sec ~/ 3600)}:${two(sec % 3600 ~/ 60)}:${two(sec % 60)}';
  }

  Widget _bottom(BuildContext c, VoidCallback finish) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final open = _setStartedAt;
    final label = plan.isEmpty
        ? (l?.activityExercisePickerChooseTitle ?? 'Choose exercise')
        : open == null
            ? 'Start set'
            : 'Finish set';
    return Row(children: [
      Expanded(
        child: Pressable(
          semanticLabel: label,
          onTap: _startOrFinish,
          child: Container(
            height: S.x10 + S.x1,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: open == null ? null : C.optimal.withValues(alpha: .14),
              border: Border.all(color: C.optimal, width: 1.5),
              borderRadius: R.rPill,
            ),
            child: open == null
                ? Text(label.toUpperCase(),
                    style: F.caps.copyWith(
                        color: C.optimal, fontWeight: FontWeight.w800))
                : LiveTick((_, _) {
                    final s = DateTime.now().difference(open).inSeconds;
                    return Text(
                        '${label.toUpperCase()} · ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
                        style: F.caps.copyWith(
                            color: C.optimal, fontWeight: FontWeight.w800));
                  }),
          ),
        ),
      ),
      const SizedBox(width: S.x3),
      Pressable(
        semanticLabel: l?.activityLiveFinishSessionLabel ?? 'Finish session',
        onTap: finish,
        child: Container(
          width: S.x10 + S.x1,
          height: S.x10 + S.x1,
          decoration: BoxDecoration(color: p.card2, shape: BoxShape.circle),
          child: Icon(LucideIcons.square, size: I.sm, color: p.on(C.red)),
        ),
      ),
    ]);
  }

  Widget _body(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    Widget tab(String label, int i) => Expanded(
          child: Pressable(
            semanticLabel: label,
            onTap: () => setState(() => _tab = i),
            child: Container(
              height: S.x10,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: _tab == i ? C.optimal : p.line,
                      width: _tab == i ? 2 : 1),
                ),
              ),
              child: Text(label,
                  style: F.caps.copyWith(
                      color: _tab == i ? p.ink : p.ink3,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.x5),
        child: Row(children: [tab('LIVE SESSION', 0), tab('EXERCISES', 1)]),
      ),
      Expanded(
        child: plan.isEmpty
            ? ListView(padding: const EdgeInsets.all(S.x5), children: [
                StatusCard(
                  l?.activityExercisePickerChooseTitle ?? 'Choose exercise',
                  l?.activityLiveChooseExerciseBody ??
                      'Pick the first exercise before logging a set.',
                  icon: LucideIcons.dumbbell,
                ),
              ])
            : ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(S.x5, S.x3, S.x5, S.x4),
                itemCount: plan.length,
                onReorder: _reorder,
                itemBuilder: (bc, i) => _tab == 0
                    ? _card(bc, i, key: ValueKey('card-${plan[i]}'))
                    : _listRow(bc, i, key: ValueKey('row-${plan[i]}')),
              ),
      ),
    ]);
  }

  /// One exercise of the session: its picture, name and set count, the set
  /// table, and the row controls under it.
  Widget _card(BuildContext c, int i, {required Key key}) {
    final p = P.of(c);
    final u = unitsOf(c);
    final k = plan[i];
    final d = exerciseByKey(k);
    final rows = _rowsFor(k);
    final done = _done(k);
    final count = _rowCount(k);
    final current = i == index;
    final unit = uiText(c, u?.weightUnit ?? 'kg').toUpperCase();
    final dumbbell =
        d?.equipment.any((e) => e.toLowerCase().contains('dumbbell')) ?? false;
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: S.x3),
      padding: const EdgeInsets.all(S.x3),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ExerciseImage(
              def: d, width: S.x10 + S.x1, height: S.x10 + S.x1, radius: R.rMd),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d?.labelFor(Localizations.localeOf(c).languageCode) ?? k,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              Text('$count ${count == 1 ? 'Set' : 'Sets'}',
                  style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          ReorderableDragStartListener(
            index: i,
            child: Semantics(
              label: 'Reorder',
              child: SizedBox.square(
                dimension: S.x8,
                child: Icon(LucideIcons.gripVertical, size: I.md, color: p.ink3),
              ),
            ),
          ),
        ]),
        const SizedBox(height: S.x3),
        Row(children: [
          SizedBox(
              width: S.x8,
              child: Text('SET', style: F.over.copyWith(color: p.ink3))),
          Expanded(
              child: Text('REPS',
                  textAlign: TextAlign.center,
                  style: F.over.copyWith(color: p.ink3))),
          const SizedBox(width: S.x2),
          Expanded(
              child: Text('WEIGHT ($unit)',
                  textAlign: TextAlign.center,
                  style: F.over.copyWith(color: p.ink3))),
          const SizedBox(width: S.x8),
        ]),
        const SizedBox(height: S.x1),
        for (var r = 0; r < count; r++)
          _setRowView(c, k, r,
              row: r < rows.length ? rows[r] : null,
              set: r < done
                  ? logged.where((s) => s.exerciseKey == k).elementAt(r)
                  : null,
              outlined: current && r == done),
        const SizedBox(height: S.x2),
        Row(children: [
          _mini(c, LucideIcons.minus, 'Remove a set', () => _dropRow(k)),
          const SizedBox(width: S.x2),
          _mini(c, LucideIcons.plus, 'Add a set', () => _addRow(k)),
          const Spacer(),
          if (done == 0 && plan.length > 1)
            _mini(c, LucideIcons.trash2, 'Remove exercise',
                () => _removeExercise(k)),
        ]),
        if (dumbbell) ...[
          const SizedBox(height: S.x2),
          Text('If lifting two dumbbells, enter the combined weight of both.',
              style: F.cap.copyWith(color: p.ink3)),
        ],
      ]),
    );
  }

  /// SET · REPS · WEIGHT · ▶ — a logged row reads back what was lifted.
  Widget _setRowView(BuildContext c, String k, int r,
      {_SetRow? row, LoggedSet? set, required bool outlined}) {
    final p = P.of(c);
    final u = unitsOf(c);
    String w(double? kg) => kg == null ? '' : _fmt(kg, u);
    final running = outlined && _setStartedAt != null;
    final next = set == null && r == _done(k);
    Widget box(String id, String value, void Function(String) onChanged) =>
        Container(
          height: S.x8 + S.x1,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
          child: set != null
              ? Text(value,
                  style: F.body.copyWith(color: p.ink2, fontWeight: FontWeight.w700))
              : AppField(
                  bare: true,
                  controller: _ctrl(id, value),
                  onChanged: onChanged,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textStyle: F.body.copyWith(fontWeight: FontWeight.w700),
                  hint: '—',
                ),
        );
    return Container(
      margin: const EdgeInsets.only(top: S.x1),
      padding: const EdgeInsets.symmetric(vertical: S.x1),
      decoration: BoxDecoration(
        borderRadius: R.rMd,
        border: Border.all(
            color: outlined ? C.optimal : Colors.transparent, width: 1.5),
      ),
      child: Row(children: [
        SizedBox(
          width: S.x8,
          child: Text('${r + 1}',
              textAlign: TextAlign.center,
              style: F.body.copyWith(
                  color: set != null ? p.ink3 : p.ink,
                  fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: box('$k|$r|r', '${set?.reps ?? row?.reps ?? ''}', (t) {
            final v = int.tryParse(t.trim());
            if (v != null && v > 0 && row != null) row.reps = v;
            _persistRows();
          }),
        ),
        const SizedBox(width: S.x2),
        Expanded(
          child: box('$k|$r|w', set != null ? (set.loadKg == null ? 'BW' : w(set.loadKg)) : w(row?.kg), (t) {
            if (row == null) return;
            final txt = t.trim();
            row.kg = txt.isEmpty
                ? null
                : (u?.weightToKg(txt) ?? double.tryParse(txt.replaceAll(',', '.')));
            _persistRows();
          }),
        ),
        SizedBox(
          width: S.x8,
          child: set != null
              ? Icon(LucideIcons.check, size: I.md, color: C.optimal)
              : Pressable(
                  semanticLabel: running ? 'Finish set ${r + 1}' : 'Start set ${r + 1}',
                  onTap: next ? () => _play(k) : null,
                  child: Icon(running ? LucideIcons.square : LucideIcons.play,
                      size: I.md, color: next ? C.optimal : p.ink3),
                ),
        ),
      ]),
    );
  }

  Widget _mini(BuildContext c, IconData i, String label, VoidCallback f) {
    final p = P.of(c);
    return Pressable(
      semanticLabel: label,
      onTap: f,
      child: Container(
        width: S.x8,
        height: S.x8,
        decoration: BoxDecoration(color: p.card2, shape: BoxShape.circle),
        child: Icon(i, size: I.sm, color: p.ink2),
      ),
    );
  }

  /// The EXERCISES tab: the order at a glance, reorderable, tap to go there.
  Widget _listRow(BuildContext c, int i, {required Key key}) {
    final p = P.of(c);
    final k = plan[i];
    final d = exerciseByKey(k);
    final done = _done(k), count = _rowCount(k);
    return Pressable(
      key: key,
      semanticLabel: d?.label ?? k,
      onTap: () => setState(() {
        index = i;
        _tab = 0;
        _persistPlan();
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: S.x2),
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: R.rLg,
          border: i == index ? Border.all(color: C.optimal, width: 1.5) : null,
        ),
        child: Row(children: [
          ExerciseImage(def: d, width: S.x8 + S.x1, height: S.x8 + S.x1, radius: R.rSm),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(d?.labelFor(Localizations.localeOf(c).languageCode) ?? k,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
          ),
          Text('$done/$count', style: F.cap.copyWith(color: p.ink3)),
          if (done >= count)
            Padding(
              padding: const EdgeInsets.only(left: S.x2),
              child: Icon(LucideIcons.check, size: I.sm, color: C.optimal),
            ),
          ReorderableDragStartListener(
            index: i,
            child: SizedBox.square(
              dimension: S.x8,
              child: Icon(LucideIcons.gripVertical, size: I.md, color: p.ink3),
            ),
          ),
        ]),
      ),
    );
  }

  /// Minimise first, then the exercise and set options.
  void _more() {
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    AppSheet.show<void>(
      context,
      title: 'Workout',
      child: StatefulBuilder(builder: (sheet, setSheet) {
        final p = P.of(sheet);
        void then(VoidCallback go) {
          Navigator.of(sheet).pop();
          go();
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          settingsGroup(sheet, 'Session', [
            // The session lives on [LiveDraft], so leaving the screen puts it
            // away; the bar above the tab bar brings it back.
            SetRow(LucideIcons.chevronDown, C.blue,
                l?.activityLiveMinimiseLabel ?? 'Minimise',
                onTap: () => then(() => nav.maybePop())),
          ]),
          if (plan.isNotEmpty)
            settingsGroup(sheet, 'Exercise', [
              SetRow(LucideIcons.repeat, C.blue, 'Swap exercise',
                  onTap: () => then(changeExercise)),
              SetRow(LucideIcons.plus, C.blue,
                  l?.activityLiveAddExerciseTitle ?? 'Add exercise',
                  onTap: () => then(addExercise)),
              if (plan.length > 1)
                SetRow(LucideIcons.skipForward, C.blue, 'Skip exercise',
                    onTap: () => then(skipExercise)),
              SetRow(LucideIcons.scale, C.blue, 'Log the rest as bodyweight',
                  onTap: () => then(() {
                        final rows = _rowsFor(key);
                        setState(() {
                          for (var r = _done(key); r < rows.length; r++) {
                            rows[r].kg = null;
                            _ctrls.remove('$key|$r|w')?.dispose();
                          }
                        });
                        _persistRows();
                      })),
            ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x1, S.x2, S.x1, S.x2),
            child: Text(l?.activityLiveEffortRpeHeader ?? 'EFFORT (RPE)',
                style: F.over.copyWith(color: p.ink3)),
          ),
          Row(children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: S.x2),
              Expanded(
                child: Pressable(
                  semanticLabel: 'RPE ${i + 6}',
                  onTap: () {
                    setState(() => rpe = i + 6);
                    setSheet(() {});
                  },
                  child: Container(
                    height: S.x8 + S.x1,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rpe == i + 6
                          ? p.ink
                          : p.ink.withValues(alpha: .08),
                      borderRadius: R.rSm,
                    ),
                    child: Text('${i + 6}',
                        style: F.cap.copyWith(
                            color: rpe == i + 6 ? p.bg : p.ink2,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: S.x3),
        ]);
      }),
    );
  }

  /// [d] is always in kg (storage unit); [u] converts + rounds for display
  /// the same way its edit-field does. Null [u] (a golden, or no unit
  /// context) shows metric untouched.
  String _fmt(double d, [UnitsController? u]) =>
      u?.weightField(d) ??
      (d == d.roundToDouble() ? d.round().toString() : d.toStringAsFixed(1));
}

// ══════════════ SWIMMING — laps are counted, not measured ══════════════

class LiveSwim extends StatefulWidget {
  final Activity a;
  final LiveFeedSource? feed;
  final double? weightKg;
  final bool private;
  final SessionFinish? onFinish;
  const LiveSwim(this.a,
      {super.key,
      this.feed,
      this.weightKg,
      this.private = false,
      this.onFinish});

  @override
  State<LiveSwim> createState() => _LiveSwimState();
}

class _LiveSwimState extends State<LiveSwim> {
  int poolLen = 25;
  int stroke = 0;
  final lapAt = <int>[]; // elapsed seconds at each lap
  static const strokes = ['Free', 'Back', 'Breast', 'Fly'];
  static const pools = [20, 25, 33, 50];

  /// One lap per tap. A separate counter beside the timestamps is how this
  /// screen and the summary came to report different distances for the same
  /// swim.
  int get laps => lapAt.length;

  /// Seconds per lap, from the taps. The FIRST lap is measured from the start
  /// of the session; taking only the gaps between taps produced one time
  /// fewer than there were laps, and the summary — which counts these — then
  /// reported every swim one lap and one pool length short.
  ///
  /// Real units: the relative bar heights are derived from these on the way to
  /// the painter, not stored instead of them.
  List<int> get lapSecs => [
        for (var i = 0; i < lapAt.length; i++)
          lapAt[i] - (i == 0 ? 0 : lapAt[i - 1]),
      ];

  @override
  void initState() {
    super.initState();
    // Laps are counted by hand — nothing can recount them. Restore whatever
    // was tapped before this screen was rebuilt.
    final d = LiveDraft.current;
    if (d == null) return;
    for (final e in (d.data['lap_at'] as List? ?? const [])) {
      if (e is num) lapAt.add(e.toInt());
    }
    poolLen = (d.data['pool'] as num?)?.toInt() ?? poolLen;
    stroke = (d.data['stroke'] as num?)?.toInt() ?? stroke;
  }

  void _persist() {
    final d = LiveDraft.current;
    if (d == null) return;
    d.put('lap_at', List<int>.of(lapAt));
    d.put('pool', poolLen);
    d.put('stroke', stroke);
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    return LiveShell(
      widget.a,
      subtitle: l?.activityLivePoolSubtitle(
              poolLen, _strokeLabel(c, strokes[stroke]).toUpperCase()) ??
          '${poolLen}M POOL · ${strokes[stroke].toUpperCase()}',
      private: widget.private,
      weightKg: widget.weightKg,
      onFinish: widget.onFinish,
      result: (elapsed) => _baseResult(widget.a,
          widget.feed?.call() ?? LiveFeed.none, widget.weightKg, elapsed,
          widget.private,
          lapSecs: lapSecs,
          poolLengthM: poolLen,
          stroke: strokes[stroke]),
      body: (ctx, elapsed) {
        final p = P.of(ctx);
        final l = AppLocalizations.of(ctx);
        final f = widget.feed?.call() ?? LiveFeed.none;
        return Column(children: [
          const SizedBox(height: S.x5),
          bigNum(p, '${laps * poolLen}', 'm'),
          const SizedBox(height: S.x2),
          Text(
              l?.activityLiveLapsCount(laps, _strokeLabel(ctx, strokes[stroke])) ??
                  '$laps ${laps == 1 ? 'lap' : 'laps'} · ${strokes[stroke]}',
              style: F.body.copyWith(color: p.ink3)),
          const SizedBox(height: S.x6),
          statRow(p, [
            (clock(elapsed), l?.activityLiveTimeUnit ?? 'time'),
            if (laps > 0)
              (clock(elapsed ~/ laps), l?.activityLivePerLapUnit ?? 'per lap'),
            ..._commonStats(ctx, widget.a, f, widget.weightKg, elapsed),
          ].take(3).toList()),
          const SizedBox(height: S.x8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            counterButton(p, LucideIcons.minus, p.ink,
                l?.activityLiveOneLapFewer ?? 'One lap fewer', () {
              if (lapAt.isEmpty) return;
              setState(() => lapAt.removeLast());
              _persist();
            }),
            const SizedBox(width: S.x6),
            Pressable(
              semanticLabel: l?.activityLiveAddALap ?? 'Add a lap',
              onTap: () {
                HapticFeedback.mediumImpact();
                setState(() => lapAt.add(elapsed));
                _persist();
              },
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                    color: p.fill(C.blue), shape: BoxShape.circle),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.plus, size: I.xl, color: p.inkOn(p.fill(C.blue))),
                      Text(l?.activityLiveLapButtonLabel ?? 'LAP',
                          style: F.over.copyWith(color: p.inkOn(p.fill(C.blue)))),
                    ]),
              ),
            ),
            const SizedBox(width: S.x6),
            counterButton(p, LucideIcons.repeat2, p.ink,
                l?.activityLiveChangeStroke ?? 'Change stroke', () {
              setState(() => stroke = (stroke + 1) % strokes.length);
              _persist();
            }),
          ]),
          const SizedBox(height: S.x6),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final len in pools) ...[
                  Pressable(
                    semanticLabel:
                        l?.activityLiveMetrePoolLabel(len) ?? '$len metre pool',
                    onTap: () {
                      setState(() => poolLen = len);
                      _persist();
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: S.x1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: S.x3, vertical: S.x2),
                      decoration: BoxDecoration(
                          color:
                              poolLen == len ? p.wash(C.blue) : p.card2,
                          borderRadius: R.rSm),
                      child: Text(
                        '$len ${uiText(context, 'm')}',
                          style: F.cap.copyWith(
                              color: poolLen == len
                                  ? p.on(C.blue)
                                  : p.ink2)),
                    ),
                  ),
                ],
              ]),
          const SizedBox(height: S.x5),
          Builder(builder: (_) {
            final secs = lapSecs;
            if (secs.isEmpty) return const SizedBox.shrink();
            final fastest = secs.reduce((x, y) => x < y ? x : y);
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                child: Text(l?.activityLiveLapsChartTitle ?? 'Laps',
                    style: F.cap.copyWith(
                        color: p.ink, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: S.x3),
              LapRows(secs, C.blue),
              const SizedBox(height: S.x3),
              Text(
                  l?.activityLiveLapsFootnote(clock(fastest)) ??
                      'Fastest ${clock(fastest)} · bar length is speed '
                          'against it.',
                  style: F.cap.copyWith(color: p.ink3)),
            ]);
          }),
          const SizedBox(height: S.x5),
          LiveHeart(f),
        ]);
      },
    );
  }
}

// ══════════════ FLOW — poses are stepped, breath is paced ══════════════

class LiveFlow extends StatefulWidget {
  final Activity a;
  final LiveFeedSource? feed;
  final double? weightKg;
  final bool private;
  final SessionFinish? onFinish;
  const LiveFlow(this.a,
      {super.key,
      this.feed,
      this.weightKg,
      this.private = false,
      this.onFinish});

  @override
  State<LiveFlow> createState() => _LiveFlowState();
}

class _LiveFlowState extends State<LiveFlow>
    with SingleTickerProviderStateMixin {
  static const poses = [
    'Mountain', 'Forward fold', 'Plank', 'Warrior II', 'Triangle',
    'Chair', 'Pigeon', 'Bridge', 'Child\'s pose', 'Savasana',
  ];

  int pose = 0;

  /// The furthest pose this session actually reached.
  ///
  /// The record used to be `poses.sublist(0, pose + 1)` off the LIVE index,
  /// so stepping back to hold Bridge again deleted the two poses after it from
  /// a session in which they were done — and going back to Mountain at the end
  /// recorded '1 poses'.
  int reached = 0;
  int hold = 30;
  Timer? _hold;

  /// The breath ring's phase. Owned here, not by the painter, and it only
  /// runs while the platform allows animation — the ring is a pacer, so with
  /// motion off it simply rests open instead of looping invisibly.
  late final AnimationController breath =
      AnimationController(vsync: this, duration: Motion.breath)
        ..addStatusListener((s) {
          if (!mounted) return;
          if (s == AnimationStatus.completed) breath.reverse();
          if (s == AnimationStatus.dismissed) breath.forward();
        });

  @override
  void initState() {
    super.initState();
    pose = (LiveDraft.current?.data['pose'] as num?)?.toInt() ?? 0;
    reached = (LiveDraft.current?.data['pose_max'] as num?)?.toInt() ?? pose;
    // No `setState`: this body follows the shell's clock, which already
    // rebuilds it once a second, so the wrapper only bought a second rebuild
    // of the same subtree at the same rate.
    //
    // WHICH IS WHY THE PAUSE CHECK IS HERE. A paused session stops advancing
    // `elapsedSec`, so the shell stops repainting — and a hold that kept
    // counting behind a frozen screen would sit there wrong and then jump on
    // resume. It is a pacer for a pose being held; a paused session is not
    // holding anything.
    _hold = Timer.periodic(Motion.tick, (_) {
      if (!mounted || LiveDraft.current?.pausedAt != null) return;
      hold = hold > 0 ? hold - 1 : 30;
    });
  }

  /// Where in the sequence the session is. The hold countdown is not saved —
  /// it is a pacer, and restarting it on resume is honest.
  void _go(int to) {
    setState(() {
      pose = to.clamp(0, poses.length - 1);
      if (pose > reached) reached = pose;
      hold = 30;
    });
    LiveDraft.current?.put('pose', pose);
    LiveDraft.current?.put('pose_max', reached);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Both directions. The gate used to guard only the START, so turning
    // reduced motion on mid-session left the ring looping anyway — and there is
    // no way to turn it back off from inside a yoga flow.
    final on = Motion.enabled(context);
    if (on && !breath.isAnimating) {
      breath.forward();
    } else if (!on && breath.isAnimating) {
      breath.stop();
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    return LiveShell(
      widget.a,
      subtitle: l?.activityLivePoseOf(pose + 1, poses.length) ??
          'POSE ${pose + 1} OF ${poses.length}',
      private: widget.private,
      weightKg: widget.weightKg,
      onFinish: widget.onFinish,
      result: (elapsed) => _baseResult(widget.a,
          widget.feed?.call() ?? LiveFeed.none, widget.weightKg, elapsed,
          widget.private,
          poses: poses.sublist(0, reached + 1)),
      body: (ctx, elapsed) {
        final p = P.of(ctx);
        final l = AppLocalizations.of(ctx);
        final f = widget.feed?.call() ?? LiveFeed.none;
        return Column(children: [
          const SizedBox(height: S.x4),
          bigNum(p, clock(elapsed), ''),
          const SizedBox(height: S.x6),
          Container(
            height: 210,
            decoration: BoxDecoration(
                borderRadius: R.rXl, color: p.wash(C.teal)),
            child: Stack(alignment: Alignment.center, children: [
              AnimatedBuilder(
                animation: breath,
                // Through `animate`, or reduced motion draws the pacer
                // PERMANENTLY COLLAPSED: `forward()` never runs, the value
                // stays 0, and `BreathRing` bottoms out at 55% of its radius.
                // Reduced motion made the ring wrong, not still.
                builder: (_, _) => CustomPaint(
                    size: const Size(170, 170),
                    painter: BreathRing(
                        animate(ctx, Curves.easeInOut.transform(breath.value)),
                        p.on(C.teal))),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.personStanding,
                    size: I.hero, color: p.on(C.teal)),
                const SizedBox(height: S.x2),
                Text(_poseLabel(ctx, poses[pose]),
                    style: F.t2.copyWith(color: p.ink)),
                const SizedBox(height: S.x1),
                Text(l?.activityLiveHoldTime(clock(hold)) ??
                    'Hold · ${clock(hold)}',
                    style: F.cap.copyWith(color: p.on(C.teal))),
              ]),
            ]),
          ),
          const SizedBox(height: S.x4),
          Row(children: [
            Expanded(
              child: BigButton(l?.activityLivePreviousLabel ?? 'Previous',
                  icon: LucideIcons.chevronLeft,
                  color: C.teal,
                  soft: true,
                  onTap: () => _go(pose - 1)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: BigButton(l?.activityLiveNextPose ?? 'Next pose',
                  icon: LucideIcons.chevronRight,
                  color: C.teal,
                  onTap: () => _go(pose + 1)),
            ),
          ]),
          const SizedBox(height: S.x5),
          Row(
            children: List.generate(
                poses.length,
                (i) => Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                            right: i == poses.length - 1 ? 0 : 3),
                        height: 5,
                        decoration: BoxDecoration(
                            color: i <= pose ? p.on(C.teal) : p.track,
                            borderRadius: R.rPill),
                      ),
                    )),
          ),
          const SizedBox(height: S.x6),
          LiveHeart(f),
        ]);
      },
    );
  }
}

// ══════════════ MATCH — the score is the parameter ══════════════

class LiveMatch extends StatefulWidget {
  final Activity a;
  final LiveFeedSource? feed;
  final double? weightKg;
  final bool private;
  final SessionFinish? onFinish;
  const LiveMatch(this.a,
      {super.key,
      this.feed,
      this.weightKg,
      this.private = false,
      this.onFinish});

  @override
  State<LiveMatch> createState() => _LiveMatchState();
}

class _LiveMatchState extends State<LiveMatch> {
  int me = 0, them = 0;
  final sets = <(int, int)>[];

  @override
  void initState() {
    super.initState();
    // The score is typed, so it restores with the session. Stored flat —
    // [me, them, me, them, …] — because JSON has no tuples.
    final d = LiveDraft.current;
    if (d == null) return;
    final v = [
      for (final e in (d.data['score'] as List? ?? const []))
        if (e is num) e.toInt(),
    ];
    for (var i = 0; i + 1 < v.length; i += 2) {
      sets.add((v[i], v[i + 1]));
    }
    me = (d.data['me'] as num?)?.toInt() ?? 0;
    them = (d.data['them'] as num?)?.toInt() ?? 0;
  }

  /// Change the score and bank it in the same breath.
  void _score(VoidCallback change) {
    setState(change);
    _persist();
  }

  /// Every point and every closed set, the moment it is entered.
  void _persist() {
    final d = LiveDraft.current;
    if (d == null) return;
    d.put('score', [for (final s in sets) ...[s.$1, s.$2]]);
    d.put('me', me);
    d.put('them', them);
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    return LiveShell(
      widget.a,
      subtitle: l?.activityLiveMatchSetSubtitle(sets.length + 1) ??
          'SET ${sets.length + 1}',
      private: widget.private,
      weightKg: widget.weightKg,
      onFinish: widget.onFinish,
      result: (elapsed) => _baseResult(widget.a,
          widget.feed?.call() ?? LiveFeed.none, widget.weightKg, elapsed,
          widget.private,
          gameScore: [...sets, if (me > 0 || them > 0) (me, them)]),
      body: (ctx, elapsed) {
        final p = P.of(ctx);
        final l = AppLocalizations.of(ctx);
        final f = widget.feed?.call() ?? LiveFeed.none;
        return Column(children: [
          const SizedBox(height: S.x4),
          bigNum(p, clock(elapsed), ''),
          const SizedBox(height: S.x6),
          Row(children: [
            Expanded(
                child: _side(ctx, p, l?.activityLiveYouLabel ?? 'YOU', me,
                    p.on(widget.a.color),
                    () => _score(() => me++),
                    () => _score(() => me = (me - 1).clamp(0, 99)))),
            Container(width: 1, height: 120, color: p.line),
            Expanded(
                child: _side(ctx, p, l?.activityLiveOpponentLabel ?? 'OPPONENT',
                    them, p.ink2,
                    () => _score(() => them++),
                    () => _score(() => them = (them - 1).clamp(0, 99)))),
          ]),
          const SizedBox(height: S.x5),
          BigButton(l?.activityLiveEndSet ?? 'End set',
              color: widget.a.color,
              soft: true,
              onTap: () => _score(() {
                    sets.add((me, them));
                    me = 0;
                    them = 0;
                  })),
          const SizedBox(height: S.x5),
          if (sets.isNotEmpty) ...[
            Align(
                alignment: Alignment.centerLeft,
                child: Text(l?.activityLiveSetsListHeader ?? 'SETS',
                    style: F.over.copyWith(color: p.ink3))),
            const SizedBox(height: S.x3),
            Surface(
              pad: const EdgeInsets.symmetric(horizontal: S.x4),
              child: Column(children: [
                for (var i = 0; i < sets.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x3),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              l?.activityLiveSetNumber(i + 1) ?? 'Set ${i + 1}',
                              style: F.body.copyWith(color: p.ink3))),
                      Text('${sets[i].$1} — ${sets[i].$2}',
                          style: F.n17.copyWith(
                              color: sets[i].$1 > sets[i].$2
                                  ? p.on(widget.a.color)
                                  : p.ink3)),
                    ]),
                  ),
                  if (i < sets.length - 1) Divider(color: p.line, height: 1),
                ],
              ]),
            ),
            const SizedBox(height: S.x5),
          ],
          LiveHeart(f),
        ]);
      },
    );
  }

  Widget _side(BuildContext c, P p, String label, int v, Color col,
      VoidCallback up, VoidCallback down) {
    final l = AppLocalizations.of(c);
    return Column(children: [
        Text(label, style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x3),
        Pressable(
          semanticLabel: l?.activityLivePointLabel(label) ?? '$label point',
          onTap: () {
            HapticFeedback.mediumImpact();
            up();
          },
          child: Text('$v', style: F.n48.copyWith(color: col)),
        ),
        const SizedBox(height: S.x3),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          counterButton(p, LucideIcons.minus, p.ink2,
              l?.activityLiveDecrease(label) ?? '$label down', down,
              size: 40),
          const SizedBox(width: S.x3),
          counterButton(p, LucideIcons.plus, col,
              l?.activityLiveIncrease(label) ?? '$label up', up, size: 40),
        ]),
      ]);
  }
}

// ══════════════ INTERVAL — the rounds run themselves ══════════════

class LiveInterval extends StatefulWidget {
  final Activity a;
  final LiveFeedSource? feed;
  final double? weightKg;
  final bool private;
  final SessionFinish? onFinish;

  /// Chosen on the setup screen (defaults match the old hardcoded values —
  /// nothing to migrate for a draft that predates this).
  final int workSec;
  final int restSec;
  final int rounds;
  const LiveInterval(this.a,
      {super.key,
      this.feed,
      this.weightKg,
      this.private = false,
      this.onFinish,
      this.workSec = 45,
      this.restSec = 30,
      this.rounds = 8});

  @override
  State<LiveInterval> createState() => _LiveIntervalState();
}

class _LiveIntervalState extends State<LiveInterval> {
  // ponytail: the round position is not written to the draft — minimising a
  // HIIT session restarts it at round 1. Nothing here is typed, so nothing is
  // LOST; it is a timer, and a timer that keeps running while the screen is
  // gone needs the countdown to live on the draft's clock. Do that if anyone
  // actually minimises intervals.
  /// [widget.rounds] is how many pips the row starts with, NOT a plan the
  /// session runs to: nothing stops this timer at that round, so a session
  /// that keeps going simply grows the row.
  int round = 1;
  late int left;
  bool work = true;
  final done = <IntervalRound>[];
  Timer? _t;

  /// Heart-rate samples taken during the CURRENT round, so each finished
  /// round carries a real mean rather than the reading that happened to be on
  /// screen when it ended.
  final _roundHr = <int>[];

  @override
  void initState() {
    super.initState();
    left = widget.workSec;
    _t = Timer.periodic(Motion.tick, (_) {
      if (!mounted) return;
      // PAUSE STOPS THE INTERVAL ENGINE. Without this the countdown kept
      // running while the session was paused: it buzzed and announced
      // "Work"/"Rest" at a phone in your pocket, advanced the round pips, and
      // BANKED IntervalRounds you never performed — so a five-minute pause
      // wrote four rounds of 45 s work into the summary while the elapsed
      // clock, which does subtract pauses, said the session was shorter than
      // the rounds it listed.
      //
      // The heart-rate sample is skipped too: readings taken while you stand
      // still would drag the round's mean down toward resting.
      if (LiveDraft.current?.pausedAt != null) return;
      final hr = widget.feed?.call().hr;
      if (hr != null && hr > 0) _roundHr.add(hr);
      setState(() {
        if (left > 0) {
          left--;
          return;
        }
        HapticFeedback.mediumImpact();
        final l = AppLocalizations.of(context);
        say(
            context,
            work
                ? (l?.activityLiveRestWord ?? 'Rest')
                : (l?.activityLiveWorkWord ?? 'Work'));
        if (work) {
          work = false;
          left = widget.restSec;
        } else {
          done.add(IntervalRound(widget.workSec, widget.restSec,
              avgHr: _roundHr.isEmpty
                  ? null
                  : (_roundHr.reduce((x, y) => x + y) / _roundHr.length)
                      .round()));
          _roundHr.clear();
          work = true;
          left = widget.workSec;
          // UNCAPPED. `done` is unconditional and the timer never stops at the
          // configured round count, so `if (round < widget.rounds) round++`
          // froze the live counter while the summary counted more — two
          // screens, one session, two round counts. [widget.rounds] is the
          // pip row's floor now, not a limit the session has.
          round++;
        }
      });
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    return LiveShell(
      widget.a,
      subtitle: l?.activityLiveIntervalSubtitle(widget.workSec, widget.restSec) ??
          '${widget.workSec} S WORK · ${widget.restSec} S REST',
      private: widget.private,
      weightKg: widget.weightKg,
      onFinish: widget.onFinish,
      result: (elapsed) => _baseResult(widget.a,
          widget.feed?.call() ?? LiveFeed.none, widget.weightKg, elapsed,
          widget.private,
          rounds: done),
      body: (ctx, elapsed) {
        final p = P.of(ctx);
        final l = AppLocalizations.of(ctx);
        final f = widget.feed?.call() ?? LiveFeed.none;
        final col = work ? C.red : C.teal;
        // At least [widget.rounds] the row is drawn for, and more once the
        // session has done more. '/ 8' was a denominator nothing enforced.
        final pips = round > widget.rounds ? round : widget.rounds;
        return Column(children: [
          const SizedBox(height: S.x5),
          Text(l?.activityLiveRoundLabel(round) ?? 'ROUND $round',
              style: F.over.copyWith(color: p.ink3)),
          const SizedBox(height: S.x4),
          Text(clock(left), style: F.n48.copyWith(color: p.on(col))),
          const SizedBox(height: S.x2),
          Text(
              (work
                      ? (l?.activityLiveWorkWord ?? 'Work')
                      : (l?.activityLiveRestWord ?? 'Rest'))
                  .toUpperCase(),
              style: F.t2.copyWith(color: p.on(col), letterSpacing: 3)),
          const SizedBox(height: S.x5),
          ClipRRect(
            borderRadius: R.rPill,
            child: LinearProgressIndicator(
                value: left / (work ? widget.workSec : widget.restSec),
                minHeight: 10,
                backgroundColor: p.track,
                valueColor: AlwaysStoppedAnimation(p.on(col))),
          ),
          const SizedBox(height: S.x6),
          Surface(
            child: Row(children: [
              Text(l?.activityLiveNextLabel ?? 'NEXT',
                  style: F.over.copyWith(color: p.ink3)),
              const Spacer(),
              Text(
                  work
                      ? (l?.activityLiveNextRest(clock(widget.restSec)) ??
                          'Rest · ${clock(widget.restSec)}')
                      : (l?.activityLiveNextWork(clock(widget.workSec)) ??
                          'Work · ${clock(widget.workSec)}'),
                  style: F.body
                      .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: S.x5),
          Row(
            children: List.generate(
                pips,
                (i) => Expanded(
                      child: Container(
                        margin:
                            EdgeInsets.only(right: i == pips - 1 ? 0 : S.x1),
                        height: 6,
                        decoration: BoxDecoration(
                            color: i < round ? p.on(C.red) : p.track,
                            borderRadius: R.rPill),
                      ),
                    )),
          ),
          const SizedBox(height: S.x6),
          statRow(p, _commonStats(ctx, widget.a, f, widget.weightKg, elapsed)),
          const SizedBox(height: S.x6),
          LiveHeart(f),
        ]);
      },
    );
  }
}

/// One planned row of a strength card: what the next set will be logged as.
class _SetRow {
  int reps;
  double? kg;
  _SetRow(this.reps, this.kg);
  _SetRow copy() => _SetRow(reps, kg);
}
