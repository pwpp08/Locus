// WORKOUT — the interaction domain. Not "here are your numbers", but "what do
// you want to do, and what did you do".
//
// Three tabs. There is deliberately no Programs tab: a training programme is a
// data model this app does not have (UI_WIRING §2c), and a tab of four fake
// plans with fake progress bars is the exact thing the absence contract
// exists to stop.
//
// Everything numeric here comes from `AppState.repo`. Where the repo has
// nothing — and for training load it very often has nothing, because CTL/ATL
// need fourteen days — the card is a StatusCard that says which, why and what
// fixes it.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../lucide.dart';

import '../../data/db.dart';
import '../../gps/gps_source.dart';
import '../../gps/route_models.dart';
import '../../health/health_workout_import.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart' show formatClockOf;
import '../activity/catalogue.dart';
import '../activity/live.dart';
import '../activity/summary.dart';
import '../theme.dart';
import '../../data/day_label.dart' show calendarDaysBetween;

// ── the app seam ───────────────────────────────────────────────────────────
// Top-level, not methods: the live-session bar in `app.dart` reopens a
// minimised workout from outside this screen, and it needs the same session
// lifecycle rather than a second copy of it.

/// Everything the activity screens need from the app.
///
/// [history] is the user's own previous/best per lift. Absent is honest — the
/// live screen says "First time on this lift" — so the resume path passes what
/// it has rather than blocking on a query.
ActivityHost activityHost(AppState app,
    {Map<String, SetHistory> history = const {}}) {
  // The id of the session this host opened, remembered across calls.
  //
  // `stopWorkout` clears `activeWorkout`, so a RETRY after a failed write —
  // the strength log throwing, say, which leaves the sessions row saved and
  // the sets lost — used to read a null id, return the draft untouched, throw
  // nothing, and be reported to the user as saved.
  String? sessionId;
  return ActivityHost(
    feed: () => _feedOf(app),
    onStart: (a) => _startSession(app, a),
    onFinish: (draft) {
      sessionId ??= app.activeWorkout?.workoutId;
      return _finishSession(app, draft, sessionId);
    },
    onSets: (sets) => _bankSets(app, sets),
    history: history,
    bandConnected: app.isConnected,
  );
}

/// The band, as the live screens see it. Read on every tick rather than
/// subscribed to: there is no stream on `AppState` — `AppState.liveHr` is a
/// getter over the field the engine writes and the UI pulls.
///
/// Six of these ten fields used to be left unset, which is why the zone
/// pill, the zone bar, the live distance and the session average heart rate
/// were all inert. They all have producers; none of them needed new science.
LiveFeed _feedOf(AppState app) {
  final w = app.activeWorkout;
  return LiveFeed(
    // The freshness-checked getter, not `device.liveHr`: the raw field keeps
    // its last value forever after an unintentional drop, which suppressed
    // LiveHeart's "The band is not connected" card exactly when it was true.
    hr: app.liveHr,
    maxHr: (w?.maxHrSeen ?? 0) > 0 ? w!.maxHrSeen : null,
    zone: app.liveZone,
    calories: w?.caloriesOrNull,
    strain: w?.strain,
    steps: app.workoutStepsMeasured,
    zoneMinutes: w?.zoneMinutes() ?? const [],
    // The SET those minutes were binned with, not a second resolution of the
    // anchors: `zoneSet` is pinned at session start precisely so a mid-session
    // anchor change cannot rebrand a split already on screen.
    zoneSource: w?.zoneSet?.source,
    zoneMaxHr: w?.zoneSet?.maxHr,
    zoneLowerBpm: w?.zoneSet == null
        ? null
        : [for (final z in w!.zoneSet!.zones) z.lower.round()],
    // DENSE, not the hole-free variant: this feeds the summary's chart, whose
    // x axis is the session clock. `perMinuteHr()` is for statistics.
    hrCurve: _curveOverSession(w),
    distanceKm: app.liveDistanceKm,
    gpsActive: app.routeTracking,
    bandConnected: app.isConnected,
    // Both were implemented at the state layer and read by nothing, so a
    // location denial showed as an absent map and no sentence at all.
    routeIssue: app.routeLocationIssue,
    onFixRoute: () {
      final issue = app.routeLocationIssue;
      if (issue == null) return;
      // A plain denial can be asked again; the rest can only be fixed in
      // Settings, and re-asking there would do nothing.
      if (issue == GpsPermissionStatus.denied) {
        app.retryRouteTracking();
      } else {
        GpsSource.openSettingsFor(issue);
      }
    },
  );
}

/// The per-minute curve, padded out to the session's OWN length.
///
/// `perMinuteHrDense` can only pad up to a minute that has a sample in it, and
/// the 1 Hz tick skips `accrueHr` entirely while the band is silent — so a
/// band that dropped at minute 30 of a 45-minute run hands back 30 slots. The
/// summary labels that chart's x axis `Start … 45:00` and spreads whatever it
/// is given across the whole width, so the reading taken at minute 15 was
/// painted under 22:30 and the fifteen-minute dropout was invisible. The tail
/// has to be there as nulls, which is what the painter breaks its line on.
List<double?> _curveOverSession(LiveWorkoutState? w) {
  if (w == null) return const [];
  final out = w.perMinuteHrDense();
  if (out.isEmpty) return out;
  final minutes = w.elapsed.inMinutes + 1;
  // Same sanity bound `_denseMinutes` uses: a clock that is not what we think
  // it is must not allocate a nonsense array.
  if (minutes <= out.length || minutes > 24 * 60) return out;
  return [...out, ...List<double?>.filled(minutes - out.length, null)];
}

/// Open a real session. Until this existed the live screens ran their own
/// clock over an app that had recorded nothing: no `sessions` row, no zone
/// tally, no calorie scoring, no GPS.
Future<bool> _startSession(AppState app, Activity a) async {
  if (app.activeWorkout != null) return false;
  app.startWorkout(type: a.typeKey);
  return app.activeWorkout != null;
}

/// `strength_set` rows for one log. `set_index` counts per exercise; `seq` is
/// the position in the whole session and is [LocalDb.saveStrengthSets]'s own
/// key, which is why re-sending the same log is idempotent.
List<Map<String, Object?>> _setRows(List<LoggedSet> sets) {
  final perExercise = <String, int>{};
  return [
    for (final s in sets)
      {
        'exercise_key': s.exerciseKey,
        'set_index':
            perExercise[s.exerciseKey] = (perExercise[s.exerciseKey] ?? 0) + 1,
        'reps': s.reps,
        'load_kg': s.loadKg,
        'rpe': s.rpe,
        'rest_sec': s.restSec,
        'at_ts': s.at.millisecondsSinceEpoch ~/ 1000,
      },
  ];
}

/// Bank the sets logged so far against the OPEN session. Called on every set,
/// because a typed set is the one thing in a session no sensor can reproduce
/// and it used to live in widget state until the user pressed stop.
Future<void> _bankSets(AppState app, List<LoggedSet> sets) async {
  final id = app.activeWorkout?.workoutId;
  if (id == null || sets.isEmpty) return;
  try {
    await LocalDb.saveStrengthSets(id, _setRows(sets));
  } catch (_) {
    // The draft still holds them, and finish writes the whole log again.
  }
}

/// Close it: finalize the session, persist the sets the user typed and the
/// privacy flag against its id, then hand back the result with the recorded
/// route folded in.
///
/// [id] is passed rather than read here so a retry still has one — see
/// [activityHost].
Future<ActivityResult> _finishSession(
    AppState app, ActivityResult draft, String? id) async {
  // Idempotent: on a retry the session is already stopped and this is a no-op.
  await app.stopWorkout();
  if (id == null) return draft;
  // The row exists from here on, so the summary can carry its id — which is
  // what TS-09's rating is written against. A draft that never reached the
  // database keeps a null id and is never offered the prompt.
  draft = draft.copyWith(sessionId: id);

  // The privacy toggle, finally landing somewhere. `putSession` is
  // INSERT-OR-REPLACE over the whole row and does not carry the flag, so this
  // is its own narrow UPDATE and it has to run AFTER stopWorkout, not before.
  if (draft.private) {
    await app.repo?.setWorkoutPrivate(id, true);
  }

  // Written on every set already; written again here because the last one
  // may have landed while the app was being torn down.
  if (draft.strength.sets.isNotEmpty) {
    await LocalDb.saveStrengthSets(id, _setRows(draft.strength.sets));
  }

  // The GPS tail is flushed by stopWorkout before it returns, so the route
  // read here is the whole route.
  try {
    final route = await app.repo?.getWorkoutRoute(id);
    if (route != null && route.hasPath) return _withRoute(draft, route);
  } catch (_) {
    // A missing map is a missing map; the session itself is already banked.
  }
  return draft;
}

/// Previous and best per lift, from this user's own log.
Future<Map<String, SetHistory>> loadSetHistory() async {
  final history = <String, SetHistory>{};
  try {
    final candidates = await LocalDb.strengthHistoryCandidates();
    final previous = <String, LoggedSet>{};
    final best = <String, LoggedSet>{};
    for (final row in candidates.previous) {
      final key = row['exercise_key'] as String?;
      if (key == null || previous.containsKey(key)) continue;
      previous[key] = _logFrom([row]).sets.single;
    }
    for (final row in candidates.best) {
      final key = row['exercise_key'] as String?;
      if (key == null || best.containsKey(key)) continue;
      best[key] = _logFrom([row]).sets.single;
    }
    for (final key in {...previous.keys, ...best.keys}) {
      history[key] = SetHistory(previous: previous[key], best: best[key]);
    }
  } catch (_) {
    // No history is the normal state on day one.
  }
  return history;
}

// ── the route seam ─────────────────────────────────────────────────────────

/// Fold a recorded route into a session: the line, the distance, the climb
/// and the per-kilometre splits. All of this already sat in `workout_route`
/// and `getWorkoutRoute`; none of it had ever reached the summary screen.
ActivityResult _withRoute(ActivityResult r, WorkoutRoute route) {
  final pts = route.points;
  final alt = [for (final p in pts) p.alt];
  final haveAlt = alt.every((a) => a != null) && alt.length > 1;
  double? gain, loss;
  if (haveAlt) {
    var up = 0.0, down = 0.0;
    for (var i = 1; i < alt.length; i++) {
      final d = alt[i]! - alt[i - 1]!;
      // A one-metre deadband: GPS altitude jitters by about that standing
      // still, and summing the jitter over an hour invents a mountain.
      if (d > 1) {
        up += d;
      } else if (d < -1) {
        down -= d;
      }
    }
    gain = up;
    loss = down;
  }
  final speeds = [for (final p in pts) p.speed];
  final haveSpeed = speeds.every((s) => s != null && s >= 0);
  return r.copyWith(
    route: _normalise(pts),
    geo: [for (final p in pts) (p.lat, p.lng)],
    routePace: haveSpeed ? _spread([for (final s in speeds) s!]) : null,
    distanceKm: route.distanceMeters / 1000,
    elevationM: haveAlt ? [for (final a in alt) a!] : const [],
    gainM: gain,
    lossM: loss,
    splits: [
      for (final s in route.splitsKm)
        KmSplit(s.meters / 1000, s.durationSec, avgHr: s.avgHr?.round()),
    ],
  );
}

/// Latitude/longitude → the 0…1 box `RouteMap` draws in, origin top-left.
/// One shared span for both axes so the shape is the shape you ran, and a
/// cosine on longitude because a degree of it is not a degree of latitude.
List<Offset> _normalise(List<RoutePoint> pts) {
  if (pts.length < 2) return const [];
  var loLat = pts.first.lat, hiLat = loLat;
  var loLng = pts.first.lng, hiLng = loLng;
  for (final p in pts) {
    loLat = math.min(loLat, p.lat);
    hiLat = math.max(hiLat, p.lat);
    loLng = math.min(loLng, p.lng);
    hiLng = math.max(hiLng, p.lng);
  }
  final k = math.cos((loLat + hiLat) / 2 * math.pi / 180).abs().clamp(.01, 1.0);
  final w = (hiLng - loLng) * k, h = hiLat - loLat;
  final span = math.max(w, h);
  if (span <= 0) return const [];
  final dx = (1 - w / span) / 2, dy = (1 - h / span) / 2;
  return [
    for (final p in pts)
      Offset(dx + (p.lng - loLng) * k / span, dy + (hiLat - p.lat) / span),
  ];
}

/// Spread a series across 0…1 for a colour ramp. A flat series lands in the
/// middle rather than at an extreme it never reached.
List<double> _spread(List<double> v) {
  final lo = v.reduce(math.min), hi = v.reduce(math.max);
  if (hi - lo < 1e-9) return [for (var i = 0; i < v.length; i++) .5];
  return [for (final x in v) (x - lo) / (hi - lo)];
}

/// The stored `[{t, v}]` heart-rate curve as one slot per MINUTE of the
/// session, `null` where nothing was recorded.
///
/// The store emits a point only for minutes that had samples, so dropping `t`
/// and keeping the values closed every dropout up: a band that lost the link
/// for ten minutes drew a trace that ran straight across them, under an axis
/// labelled `Start … 47:20`. The x position of a sample is its index, so the
/// index has to be the minute.
/// [session] pads the TAIL out to the session's own length, for the same
/// reason [_curveOverSession] does on the live path: the store's last point is
/// the last minute that had samples, so a band that dropped at minute 30 of a
/// 45-minute session ends the line there and the chart stretches it across an
/// axis that says 45:00.
List<double?> _denseMinutes(Object? hr, [Duration? session]) {
  final pts = <(int, double)>[
    for (final e in (hr as List? ?? const []))
      if (e is Map && e['t'] is num && e['v'] is num)
        ((e['t'] as num).toInt(), (e['v'] as num).toDouble()),
  ];
  if (pts.isEmpty) return const [];
  final t0 = pts.first.$1;
  final n = (pts.last.$1 - t0) ~/ 60 + 1;
  // A session longer than a day, or timestamps that are not what we think they
  // are: fall back to the values rather than allocating a nonsense array.
  if (n < 1 || n > 24 * 60) return [for (final p in pts) p.$2];
  final want = session == null ? n : session.inMinutes + 1;
  final out = List<double?>.filled(
      want > n && want <= 24 * 60 ? want : n, null);
  for (final p in pts) {
    final i = (p.$1 - t0) ~/ 60;
    if (i >= 0 && i < n) out[i] = p.$2;
  }
  return out;
}

/// Zone 5 of a persisted `zone_bands` list — the row carrying the set's own
/// `source` stamp and, as its `hi`, the ceiling the whole set is a percentage
/// of. Null for a session that banked no split, and then the footnote says the
/// estimate: the one claim that stands with no ceiling to name.
Map<String, dynamic>? _topBand(Object? bands) {
  if (bands is! List || bands.length != 5) return null;
  final top = bands.last;
  return top is Map ? top.cast<String, dynamic>() : null;
}

/// The five `lo` edges off `zone_bands`, or null unless all five are numbers.
List<num>? _lowerEdges(Object? bands) {
  if (bands is! List || bands.length != 5) return null;
  final out = [
    for (final b in bands)
      if (b is Map && b['lo'] is num) b['lo'] as num,
  ];
  return out.length == 5 ? out : null;
}

/// `zone_min` comes back from the repo as raw decoded JSON — guard the type
/// once here so a non-`List` value (or a non-numeric entry) never throws in
/// either read path.
List<double> _decodeZoneMinutes(Object? raw) => [
      for (final z in (raw is List ? raw : const []))
        if (z is num) z.toDouble(),
    ];

/// A session row as served by `getSessions` / `getWorkouts`, read into the
/// summary's full result the way History opens one: what Share sends.
Future<ActivityResult> sessionResultOf(AppState app, Map<String, dynamic> r) {
  final a = activityByName(r['type'] as String?) ??
      Activity(importedWorkoutTitle(r['type']), LucideIcons.activity, C.dialStrain,
          Track.duration, 5.0);
  final ts = (r['start_ts'] as num?)?.toInt() ?? 0;
  return _detailOf(
      app,
      _PastWorkout(
        (r['id'] as String?) ?? '',
        a,
        DateTime.fromMillisecondsSinceEpoch(ts * 1000),
        Motion.tick * 60 * ((r['duration_min'] as num?)?.toInt() ?? 0),
        strain: (r['strain'] as num?)?.toDouble(),
        calories: (r['calories'] as num?)?.round(),
        avgHr: (r['avg_hr'] as num?)?.round(),
        maxHr: (r['max_hr'] as num?)?.toInt(),
        hrr60: (r['hrr60'] as num?)?.round(),
        vo2max: (r['vo2max_estimate'] as num?)?.toDouble(),
        steps: (r['steps'] as num?)?.toInt(),
        zoneMinutes: _decodeZoneMinutes(r['zone_min']),
        private: r['private'] == true,
      ));
}

/// One past session, opened from history — built from what the stores hold
/// rather than from the six columns the list row carries.
Future<ActivityResult> _detailOf(AppState app, _PastWorkout w) async {
  var out = w.toResult();
  final repo = app.repo;
  if (repo == null) return out;
  try {
    final b = await repo.getWorkout(w.id);
    final band = _topBand(b['zone_bands']);
    // The bundle's own split — and whether it is the one that ends up on
    // screen. A short or absent `zone_min` falls back to the list row's split
    // rather than blanking the bars, but that is a different read from a
    // different moment, so it is one more case where the bands beside it
    // describe a different set.
    final decoded = _decodeZoneMinutes(b['zone_min']);
    final usedBundleSplit = decoded.length == 5;
    // …and whether that split was binned by the pass that produced the bands.
    final rebinned = usedBundleSplit && b['zone_min_rebinned'] != false;
    out = out.copyWith(
      hr: _denseMinutes(b['hr'], w.duration),
      // The session's own mean, computed over its heart-rate stream.
      avgHr: (b['avg_hr'] as num?)?.round(),
      maxHr: (b['max_hr'] as num?)?.round(),
      // How much of the window the trace behind those numbers actually covers.
      // Sessions past `rawRetentionDays` are served from the frozen trace, and
      // one frozen mid-dropout has to read as partial rather than draw a
      // confident line across the gap.
      traceCoveragePct: (b['trace_coverage_pct'] as num?)?.toInt(),
      // TS-04 — the anchors the bands on this card were binned against, read
      // off the bands themselves. `_zoneBands` stamps every row with the set's
      // `source`, and zone 5's `hi` IS the ceiling (both `zonesFromMaxHr` and
      // `reserveZones` put 100 % of the anchor there), so the footnote needs no
      // second read and cannot describe a different set from the bars.
      //
      // …EXCEPT WHEN IT WOULD. The bands are recomputed from the current
      // anchors on every open, while the minutes below can be a KEPT LIVE
      // split: a session the band only partly handed over keeps whichever side
      // saw more minutes, and that side was binned against whatever ceiling was
      // current when it was written. `zone_min_rebinned` is false exactly
      // there, and then this card has no ceiling it can name for these bars —
      // so it names none, and the footnote falls back to the estimate, the one
      // claim that stands without one. Understating the bars to match the
      // bands instead would put them at odds with the strain, calories and
      // duration beside them, which are the kept values too.
      // `band?['source'] as String?` / `as num?` would THROW on a
      // wrong-typed (not just missing) field, and the catch below is
      // best-effort for the WHOLE enrichment — one bad band field must not
      // also blank the hr/avgHr/zoneMinutes reads beside it. `is`-checks
      // degrade to null instead of throwing.
      zoneSource:
          rebinned && band?['source'] is String ? band!['source'] as String : null,
      zoneMaxHr: rebinned && band?['hi'] is num ? band!['hi'] as num : null,
      // The edges the bands were cut at, under the same rebinned rule.
      zoneLowerBpm: rebinned ? _lowerEdges(b['zone_bands']) : null,
      // …and the MINUTES from the same read, not from the list row. Opening a
      // session rescores it (`_rescoreSessionFromSubstrate`), so the row loaded
      // with the month list can be a split binned before that correction — and
      // pairing those bars with the provenance of the bands just recomputed
      // beside them is the exact mismatch this card is being fixed for.
      //
      // The list row is still the fallback for a split this read could not
      // produce: five zones or nothing, because a partial vector would draw
      // bars for the zones it has and silently drop the rest. When it fires,
      // `rebinned` is false above and no ceiling is named — which is what the
      // objection to falling back here was actually about.
      zoneMinutes: usedBundleSplit ? decoded : out.zoneMinutes,
    );
  } catch (_) {
    // Enrichment is best-effort; the scalars on the row still render.
  }
  // TS-09 — the session's own rating. `getWorkout` is the derived bundle and
  // does not carry the column, so this is one primary-key read of the row.
  try {
    final rpe = (await LocalDb.session(w.id))?['rpe'] as num?;
    if (rpe != null) out = out.copyWith(rpe: rpe.toDouble());
  } catch (_) {
    // An unrated session and an unreadable row both render as unrated.
  }
  try {
    final sets = await LocalDb.strengthSets(w.id);
    if (sets.isNotEmpty) out = out.copyWith(strength: _logFrom(sets));
  } catch (_) {
    /* no sets is a normal session */
  }
  try {
    final route = await repo.getWorkoutRoute(w.id);
    if (route != null && route.hasPath) out = _withRoute(out, route);
  } catch (_) {
    /* no route is a normal session */
  }
  return out;
}

/// `strength_set` rows → the log the summary renders. `load_kg` stays null
/// when it was null: a bodyweight set is not a zero-kilo set.
StrengthLog _logFrom(List<Map<String, Object?>> rows) => StrengthLog([
      for (final r in rows)
        LoggedSet(
          (r['exercise_key'] as String?) ?? '',
          (r['reps'] as num?)?.toInt() ?? 0,
          loadKg: (r['load_kg'] as num?)?.toDouble(),
          rpe: (r['rpe'] as num?)?.toInt(),
          restSec: (r['rest_sec'] as num?)?.toInt(),
          at: DateTime.fromMillisecondsSinceEpoch(
              ((r['at_ts'] as num?)?.toInt() ?? 0) * 1000),
        ),
    ]);

// ── the data this screen reads ─────────────────────────────────────────────

class _PastWorkout {
  final String id;
  final Activity activity;
  final DateTime start;
  final Duration duration;
  final double? strain;
  final int? calories, avgHr, maxHr;

  /// `sessions.hrr_bpm` — the bpm drop in the 60 s after the session. Carried
  /// from the list row because that is where the repository already serves it.
  final int? hrr60;

  /// `sessions.vo2max_estimate` — submax estimate from one completed km route
  /// split. Carried for the same reason [hrr60] is: opening the detail screen
  /// converts this row straight to an `ActivityResult`.
  final double? vo2max;

  /// `sessions.steps` — banked at finish from the live 100 Hz pedometer and
  /// never recomputed. It is a COLUMN, so unlike the trace it does not depend
  /// on the 1 Hz substrate and does not go blank when that is pruned; a session
  /// that never measured one reads NULL forever, which is the truth for it.
  final int? steps;
  final List<double> zoneMinutes;

  /// The user's "keep this one off the shared surfaces" flag, read back from
  /// `sessions.private`.
  final bool private;

  const _PastWorkout(this.id, this.activity, this.start, this.duration,
      {this.strain,
      this.calories,
      this.avgHr,
      this.maxHr,
      this.hrr60,
      this.vo2max,
      this.steps,
      this.zoneMinutes = const [],
      this.private = false});

  String when(AppLocalizations? loc) {
    final days = calendarDaysBetween(start, DateTime.now());
    final names = [
      loc?.workoutWeekdayAbbrMon ?? 'Mon',
      loc?.workoutWeekdayAbbrTue ?? 'Tue',
      loc?.workoutWeekdayAbbrWed ?? 'Wed',
      loc?.workoutWeekdayAbbrThu ?? 'Thu',
      loc?.workoutWeekdayAbbrFri ?? 'Fri',
      loc?.workoutWeekdayAbbrSat ?? 'Sat',
      loc?.workoutWeekdayAbbrSun ?? 'Sun',
    ];
    final t = formatClockOf(start);
    if (days == 0) return loc?.workoutWhenToday(t) ?? 'Today, $t';
    if (days == 1) return loc?.workoutWhenYesterday(t) ?? 'Yesterday, $t';
    if (days < 7) return '${names[start.weekday - 1]}, $t';
    return '${start.day}/${start.month}, $t';
  }

  ActivityResult toResult() => ActivityResult(
        activity,
        start: start,
        duration: duration,
        private: private,
        // TS-09 — the id travels so the summary can write a rating against
        // it; the rating itself is read on open by `_detailOf`, not carried on
        // this row (the list does not show it).
        sessionId: id,
        strain: strain,
        calories: calories,
        avgHr: avgHr,
        maxHr: maxHr,
        hrr60: hrr60,
        vo2max: vo2max,
        steps: steps,
        zoneMinutes: zoneMinutes,
      );
}
