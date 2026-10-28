// HOME — decision-oriented. "What matters today?"
//
// Three rings that decide the day — what the night gave back, what the day has
// cost, what the night was made of — three signals worth a glance under them,
// and the small set of things the app can honestly say are worth doing.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:openstrap_analytics/onehz.dart'
    show readinessCompositeMinBaseline;
import 'package:provider/provider.dart';

import '../../compute/findings.dart' show isRecentFindingDate;
import '../../compute/onehz_pipeline.dart'
    show readinessInputShortfallNote, readinessUnstableBaselineNote;
import '../../data/day_label.dart'
    show dayLabelOf, localDayStartSec, todayLabel;
import '../../data/db.dart' show DbRebuild, LocalDb;
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../state/units_controller.dart';
import '../../theme/theme_switcher.dart' show themedRoute;
import '../activity/day_strain.dart' show DayStrainDetail;
import '../profile/alarm.dart'
    show
        AlarmArmState,
        alarmArmOf,
        alarmDoor;
import '../profile/profile.dart' show ProfileAvatar;
import '../profile/wearable_numbers.dart'
    show WearableCells, kHomeWearableRows;
import '../ui2.dart';
import 'add_activity.dart' show openAddActivity;
import 'day_heart.dart';
import 'detected_activities.dart';
import 'health_monitor.dart'
    show HealthGlance, HealthMonitorScreen, healthGlanceOf;
import 'home/home_cards.dart';
import 'home/home_dashboard_editor.dart';
import 'home/home_data.dart';
import 'home/home_dials.dart';
import 'home/home_header.dart';
import 'home/home_monitors.dart';
import 'home/home_my_day.dart';
import 'home/home_rings.dart';
import 'home/home_tonights_sleep.dart';
import 'journal_compose.dart';
import 'metric_detail.dart' show MetricDetail;
import 'naps.dart' show NapsScreen;
import 'plus_menu.dart';
import 'readiness_detail.dart';
import 'recovery_calendar.dart' show openRecoveryCalendar;
import 'sleep_detail.dart';
import 'sleep_planner.dart'
    show alarmItemsOf, plannedWakeMin;
import 'start_activity.dart';
import 'strain_recovery_card.dart';
import 'strength_trainer.dart';
import 'stress_monitor.dart';
import 'trend_view.dart';
import 'workout_detail.dart';

// Re-export submodules for clean public API and test compatibility.
export 'home/home_cards.dart';
export 'home/home_dashboard_editor.dart';
export 'home/home_data.dart';
export 'home/home_dials.dart';
export 'home/home_header.dart';
export 'home/home_monitors.dart';
export 'home/home_my_day.dart';
export 'home/home_rings.dart';
export 'home/home_tonights_sleep.dart';

// Aliases for private names used throughout Home widgets.
typedef _Dials = HomeDials;
typedef _SectionHead = HomeSectionHead;
typedef _MyDay = HomeMyDay;
typedef _TonightsSleep = HomeTonightsSleep;
typedef _Monitors = HomeMonitors;
typedef _Wordmark = HomeWordmark;
typedef _DeviceStatus = HomeDeviceStatus;

// ═══════════════════ shared plumbing ═══════════════════

/// Page padding. Tab roots replace the bottom with `S.navClear(context)`.
const pad = EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16 + S.x8);

/// Push a detail screen.
void go(BuildContext c, Widget w) => Navigator.of(c)
    .push(themedRoute((_) => w, name: w.runtimeType.toString()));

/// The repo, or null when there is no AppState above us.
LocalRepository? repoOf(BuildContext c) {
  try {
    return c.read<AppState>().repo;
  } catch (_) {
    return null;
  }
}

/// The user's unit system, or null in a golden.
UnitsController? unitsOf(BuildContext c) {
  try {
    return c.watch<UnitsController>();
  } catch (_) {
    return null;
  }
}

/// The band-sync trigger, or null when there is no AppState above us.
VoidCallback? syncOf(BuildContext c) {
  try {
    final app = c.read<AppState>();
    return app.syncNow;
  } catch (_) {
    return null;
  }
}

/// Whether the database had to be rebuilt to start this launch.
DbRebuild? dbRebuiltOf(BuildContext c) {
  try {
    return c.read<AppState>().dbRebuild;
  } catch (_) {
    return null;
  }
}

/// The armed alarm and its state, or null when absent.
(DateTime?, AlarmArmState)? alarmArmOfContext(BuildContext c) {
  try {
    return c.select<AppState, (DateTime?, AlarmArmState)>(alarmArmOf);
  } catch (_) {
    return null;
  }
}

/// Whether a live workout is open, or false in a golden.
bool workoutLiveOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.activeWorkout != null);
  } catch (_) {
    return false;
  }
}

/// Whether cycle tracking is on, or false in a golden.
bool cycleTrackingOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.cycleTrackingEnabled);
  } catch (_) {
    return false;
  }
}

// ═══════════════════ the screen ═══════════════════

class HomeScreen extends StatefulWidget {
  final HomeData? data;
  final int? hour;
  final bool? workoutLive;
  final DateTime? now;
  final Map<String, dynamic>? night;
  final List<Map<String, dynamic>>? sessions;
  final Map<String, List<ChartPoint>>? charts;

  const HomeScreen(
      {super.key,
      this.data,
      this.hour,
      this.workoutLive,
      this.now,
      this.night,
      this.sessions,
      this.charts});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RevisionReload {
  HomeData? _d;
  bool _loading = true;
  String? _day;
  List<String> _days = const [];
  bool _failed = false;
  bool _syncTapped = false;
  Timer? _syncTapTimer;

  final _scroll = ScrollController();
  final _stackKey = GlobalKey();
  final _dialKeys = {for (final k in kDialOrder) k: GlobalKey()};
  final _dialRest = <HomeRingKind, (Offset, double)>{};

  void _measureDials() {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || stack == null || !stack.attached) return;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    for (final k in kDialOrder) {
      final rb = _dialKeys[k]!.currentContext?.findRenderObject() as RenderBox?;
      if (rb == null || !rb.attached || !rb.hasSize) {
        _dialRest.remove(k);
        continue;
      }
      final top = stack.globalToLocal(rb.localToGlobal(Offset.zero));
      _dialRest[k] = (
        Offset(top.dx + rb.size.width / 2, top.dy + rb.size.height / 2 + offset),
        rb.size.width,
      );
    }
  }

  static const _tapGrace = Duration(seconds: 20);

  void _tapSync(VoidCallback sync) {
    sync();
    setState(() => _syncTapped = true);
    _syncTapTimer?.cancel();
    _syncTapTimer = Timer(_tapGrace, () {
      if (mounted) setState(() => _syncTapped = false);
    });
  }

  @override
  void dispose() {
    _syncTapTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _d = widget.data;
      _night = widget.night ?? const {};
      _sessions = widget.sessions ?? const [];
      _daily = {
        for (final e in (widget.charts ?? const <String, List<ChartPoint>>{}).entries)
          e.key: {
            for (final p in e.value)
              dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)): p.v,
          },
      };
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  bool get revisionReloads => widget.data == null;

  @override
  void reload() => _load();

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final t = beginRead(#home);
    try {
      final day = _day;
      final l = AppLocalizations.of(context);
      final d = day == null || day == todayLabel()
          ? await HomeData.load(repo, l)
          : await HomeData.loadForDay(repo, day, l);
      final days = await repo.availableDays();
      await _loadExtras(repo, d);
      if (stillNewest(#home, t)) {
        setState(() => (_d = d, _days = days, _loading = false, _failed = false));
      }
    } catch (_) {
      if (stillNewest(#home, t)) {
        setState(() => (_loading = false, _failed = true));
      }
    }
  }

  Future<void> _openCalendar(BuildContext c, String cur) async {
    final today = todayLabel(widget.now);
    final day = await openRecoveryCalendar(c,
        today: today,
        selected: cur,
        recovery: _daily['recovery'] ?? const {},
        days: {..._days, today});
    if (day != null && mounted) _goDay(day);
  }

  void _goDay(String day) {
    setState(() {
      _day = day;
      _loading = true;
    });
    _load();
  }

  Widget? _phaseStatusCard(BuildContext c, AppLocalizations? l,
      {bool sleepComputed = false, bool firstRun = true}) {
    final syncing = syncingNowOf(c);
    final deriving = derivingOf(c);
    if ((syncing || deriving) && _syncTapped) {
      _syncTapped = false;
      _syncTapTimer?.cancel();
    }
    if (!deriving && !syncing && !_syncTapped) return null;
    if (!syncing && _syncTapped) {
      _syncTapped = false;
      _syncTapTimer?.cancel();
    }
    final spinner = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: P.of(c).ink3),
    );

    if (deriving && !sleepComputed && firstRun) {
      return StatusCard(
        l?.homeAnalyzingTitle ?? 'Crunching last night\'s numbers',
        l?.homeAnalyzingBody ?? 'The data is in — sleep, recovery and strain '
            'are next.',
        leading: spinner,
      );
    }
    if (_syncTapped) {
      return StatusCard(
        l?.homeConnectingTitle ?? 'Connecting to your band',
        l?.homeConnectingBody ?? 'Hang on — this usually takes a few seconds.',
        leading: spinner,
      );
    }
    return null;
  }

  Widget _bareStatusCard(BuildContext c, HomeData d, AppLocalizations? l,
      {required bool pastDay}) {
    if (pastDay) {
      return const StatusCard(
        'No data for this day',
        'Nothing was recorded on this day.',
        fix: '',
        icon: LucideIcons.calendarOff,
      );
    }
    final phase = _phaseStatusCard(c, l, firstRun: d.heldOverNight == null);
    if (phase != null) return phase;

    final sync = syncOf(c);
    return StatusCard(
      d.heldOverNight == null
          ? (l?.homeNothingDerivedTitle ?? 'No nights scored yet')
          : (l?.homeNothingTodayTitle ?? 'Nothing recorded for today'),
      d.heldOverNight == null
          ? (l?.homeNothingDerivedBody ?? 'Wear the band tonight and open the app in the morning.')
          : (l?.homeNothingTodayBody(prettyDay(d.heldOverNight, l)) ??
              'The last night this app scored was '
                  '${prettyDay(d.heldOverNight, l)}. Nothing has reached it since.'),
      fix: sync == null ? '' : (l?.homeSyncBand ?? 'Sync the band'),
      icon: LucideIcons.watch,
      onFix: sync == null ? null : () => _tapSync(sync),
    );
  }

  Map<String, dynamic> _night = const {};
  List<Map<String, dynamic>> _sessions = const [];
  List<Map<String, dynamic>> _naps = const [];
  StressMonitorData? _stress;
  HealthGlance? _health;
  StressSource? _stressSource;

  Future<void> _loadStress(LocalRepository repo, String day) async {
    try {
      final d = await (_stressSource ??= StressSource(repo)).load(day);
      if (mounted) setState(() => _stress = d);
    } catch (_) {}
  }

  List<String> _tiles = dashboardTilesOf();

  Future<void> _loadExtras(LocalRepository repo, HomeData d) async {
    final day = d.dayId ?? _day ?? todayLabel();
    var night = const <String, dynamic>{};
    var sessions = const <Map<String, dynamic>>[];
    var naps = const <Map<String, dynamic>>[];
    try {
      night = await repo.getDaySleepV2(day);
    } catch (_) {}
    try {
      final start = localDayStartSec(day);
      final dd = DateTime.tryParse(day);
      final end = dd == null
          ? null
          : localDayStartSec(dayLabelOf(DateTime(dd.year, dd.month, dd.day + 1)));
      if (start != null && end != null) {
        sessions = [
          ...await repo.getSessions(from: start, to: end, includeDetected: false)
        ]..sort((a, b) => ((a['start_ts'] as num?) ?? 0)
            .compareTo((b['start_ts'] as num?) ?? 0));
      }
    } catch (_) {}
    try {
      final nd = await repo.getDayNaps(day);
      final raw = (nd['naps'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final manualEdits = await LocalDb.napEdits(day);
      final merged = <Map<String, dynamic>>[...raw];
      for (final e in manualEdits) {
        if (e['source'] == 'manual') {
          final start = e['start_ts'] as int?;
          final end = e['end_ts'] as int?;
          if (start != null &&
              end != null &&
              !merged.any((m) => m['start'] == start && m['end'] == end)) {
            merged.add({
              'start': start,
              'end': end,
              'duration_min': ((end - start) / 60).round(),
              'source': 'manual',
            });
          }
        }
      }
      naps = merged..sort((a, b) =>
          ((a['start'] as num?) ?? 0).compareTo((b['start'] as num?) ?? 0));
    } catch (_) {}
    final loader = TrendLoader(repo);
    final daily = <String, Map<String, double>>{};
    for (final k in {..._tiles, 'strain', 'recovery'}) {
      final m = trendMetricOf(k);
      if (m != null) daily[k] = await loader.daily(m);
    }
    final first = await loader.firstDay();
    if (!mounted) return;
    _night = night;
    _sessions = sessions;
    _naps = naps;
    _daily = daily;
    _firstDay = first;
    _loadStress(repo, day);
    unawaited(healthGlanceOf(context).then((h) {
      if (mounted) setState(() => _health = h);
    }).catchError((Object _) {}));
  }

  Map<String, Map<String, double>> _daily = const {};
  String? _firstDay;

  Widget _header(BuildContext c, String? dayId) {
    final today = todayLabel(widget.now);
    final cur = _day ?? dayId ?? today;
    return Padding(
      padding: const EdgeInsets.only(top: S.x3, bottom: S.x4),
      child: Stack(alignment: Alignment.center, children: [
        DayPager(
          day: cur,
          today: today,
          days: _days,
          onDay: _goDay,
          onCalendar: () => _openCalendar(c, cur),
        ),
        const Align(
            alignment: AlignmentDirectional.centerStart,
            child: ProfileAvatar(accent: C.domHome, size: S.x12 * 0.8)),
        const Align(
            alignment: AlignmentDirectional.centerEnd, child: _DeviceStatus()),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final d = _d;

    if (d == null) {
      return _refreshable(ListView(padding: pad.copyWith(bottom: S.navClear(c)), children: [
        _header(c, null),
        const _Wordmark(),
        const SizedBox(height: S.x5),
        const SizedBox(height: S.x3),
        const DetectedActivitiesCard(),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_failed)
          StatusCard(
            l?.homeLoadFailedTitle ?? 'Today could not be read',
            l?.homeLoadFailedBody ??
                'The stored day failed to load. Nothing was deleted — this is a '
                'read that went wrong, not missing data.',
            fix: l?.homeTryAgain ?? 'Try again',
            icon: LucideIcons.databaseZap,
            onFix: () {
              setState(() => (_loading = true, _failed = false));
              _load();
            },
          )
        else
          Builder(builder: (c) {
            final phase = _phaseStatusCard(c, l);
            if (phase != null) return phase;
            final sync = syncOf(c);
            return StatusCard(
              l?.homeNothingDerivedTitle ?? 'No nights scored yet',
              l?.homeNothingDerivedBody ?? 'Wear the band tonight and open the app in the morning.',
              fix: sync == null ? '' : (l?.homeSyncBand ?? 'Sync the band'),
              icon: LucideIcons.watch,
              onFix: sync == null ? null : () => _tapSync(sync),
            );
          }),
        if (!_loading && !_failed && widget.data == null) ...[
          const SizedBox(height: S.x3),
          firstWeekCard(c, days: _days.length, strainScored: false),
        ],
        if (_day == null || _day == todayLabel())
          if (alarmArmOfContext(c) case final (DateTime?, AlarmArmState) a) ...[
            const SizedBox(height: S.x3),
            alarmDoor(c, a.$1, a.$2),
          ],
      ]));
    }

    final bare = d.readiness.isEmpty &&
        d.sleepMin.isEmpty &&
        d.strain.isEmpty &&
        d.rhr.isEmpty &&
        d.steps.value == null &&
        d.calories.isEmpty;

    final isToday = _day == null || _day == todayLabel();
    final quietDay = newDayNothingYet(
        bare: bare,
        isToday: isToday,
        hasHistory: d.heldOverNight != null,
        lastData: lastDataAtOf(c),
        now: DateTime.now());
    final showBare = bare && !quietDay;

    final recoveryNightsLeft = needMoreNightsFromNote(d.readiness.note);
    final firstWeeks = isToday &&
        widget.data == null &&
        d.readiness.isEmpty &&
        (_days.length <= readinessCompositeMinBaseline ||
            recoveryNightsLeft != null);

    final stale = staleInsightsCard(d.insightsStale, syncOf(c), l);
    final rebuilt = dbRebuiltCard(dbRebuiltOf(c), l);
    void openDial(HomeRingKind k) => go(
        c,
        switch (k) {
          HomeRingKind.recovery => ReadinessDetail(day: isToday ? null : _day),
          HomeRingKind.strain => DayStrainDetail(day: isToday ? null : _day),
          HomeRingKind.sleep => SleepDetail(day: isToday ? null : _day),
        });
    final dialsShown = (!bare && RingTrio.has(d)) || quietDay;

    WidgetsBinding.instance.addPostFrameCallback((_) => _measureDials());
    return Stack(key: _stackKey, children: [
     _refreshable(ListView(
        controller: _scroll,
        padding: pad.copyWith(bottom: S.navClear(c)),
        children: [
      _header(c, d.dayId),
      if (rebuilt != null) ...[rebuilt, const SizedBox(height: S.x3)],
      ...?_bodyWatch(c, d, todayLabel(widget.now)),
      const _Wordmark(),
      const SizedBox(height: S.x5),

      if (!bare && isToday)
        if (_phaseStatusCard(
          c,
          l,
          sleepComputed: d.sleepMin.value != null || d.readiness.value != null,
          firstRun: d.heldOverNight == null,
        ) case final phase?) ...[
          phase,
          const SizedBox(height: S.x3),
        ],

      if (showBare) ...[
        isToday && (widget.workoutLive ?? workoutLiveOf(c))
            ? workoutHoldCard(l)
            : _bareStatusCard(c, d, l, pastDay: !isToday),
        if (firstWeeks) ...[
          const SizedBox(height: S.x3),
          firstWeekCard(c,
              days: _days.length,
              strainScored: false,
              recoveryNightsLeft: recoveryNightsLeft),
        ],
      ] else ...[
        if (dialsShown) ...[
          _Dials(
              d: d,
              onOpen: openDial,
              keys: _dialKeys,
              scroll: _scroll,
              note: quietDay ? 'No sleep yet today.' : null),
          _Monitors(
            health: _health,
            stress: _stress,
            onHealth: () => go(c, const HealthMonitorScreen()),
            onStress: () => go(c, const StressMonitorScreen()),
          ),
        ] else
          Builder(builder: (c) {
            final need = needMessageFromNote(d.readiness.note);
            final shortfall = need == null
                ? readinessInputShortfallNote(d.absentDiag) ??
                    readinessUnstableBaselineNote(
                        d.absentDiag?['note']?.toString())
                : null;
            return StatusCard(
              l?.homeReadinessNotScoredTitle ?? 'Recovery is not scored today',
              need != null
                  ? (l?.homeReadinessNeedBody(need) ??
                      '$need to know what normal looks like for you.')
                  : shortfall ??
                      whyFromNote(d.readiness.note) ??
                      (l?.homeReadinessNoReason ?? 'Nothing recorded says why.'),
              fix: l?.homeSeeWhatWasMissing ?? 'See what was missing',
              icon: LucideIcons.batteryCharging,
              onFix: () => go(c, const ReadinessDetail()),
            );
          }),
        if (stale != null) ...[const SizedBox(height: S.x3), stale],
        if (firstWeeks) ...[
          const SizedBox(height: S.x3),
          firstWeekCard(c,
              days: _days.length,
              strainScored: !d.strain.isEmpty,
              recoveryNightsLeft: recoveryNightsLeft),
        ],
      ],

      if (widget.data == null) ...[
        const SizedBox(height: S.x3),
        WearableCells(kHomeWearableRows, date: isToday ? null : _day),
      ],

      const SizedBox(height: S.x3),
      const DetectedActivitiesCard(),

      _SectionHead(
        'My Day',
        trailing: Builder(builder: (b) {
          return PlusButton(onTap: () async {
            final box = b.findRenderObject() as RenderBox?;
            if (box == null) return;
            final at = box.localToGlobal(Offset.zero) & box.size;
            final pick = await showPlusMenu(c, at);
            if (pick == null || !c.mounted) return;
            switch (pick) {
              case PlusChoice.start:
                go(c, const StartActivityScreen());
              case PlusChoice.add:
                if (await openAddActivity(c) == true) _load();
              case PlusChoice.strength:
                go(c, const StrengthTrainerScreen());
              case PlusChoice.journal:
                go(c, const JournalCompose());
            }
          });
        }),
      ),
      _MyDay(
        day: d.dayId ?? _day ?? todayLabel(),
        night: _night,
        sessions: _sessions,
        naps: _naps,
        onExpand: () => go(
            c,
            DayHeartScreen(
              day: d.dayId ?? _day ?? todayLabel(),
              night: _night,
              sessions: _sessions,
              naps: _naps,
              strain: d.strain.value?.toDouble(),
            )),
        onSleep: () => go(c, SleepDetail(day: isToday ? null : _day)),
        onNap: (nap) => go(c, NapsScreen(day: isToday ? null : _day)),
        onSession: (s) async {
          final changed = await Navigator.of(c).push<bool>(themedRoute(
              (_) => WorkoutDetailScreen(session: s),
              name: 'WorkoutDetailScreen'));
          if (changed == true && mounted) _load();
        },
        onAdd: () async {
          if (await openAddActivity(c) == true) _load();
        },
        onStart: isToday ? () => go(c, const StartActivityScreen()) : null,
      ),
      if (isToday) ...[
        const SizedBox(height: S.x3),
        Builder(builder: (c) {
          final alarm = alarmArmOfContext(c);
          return _TonightsSleep(
            bedtimeMin: d.plan.bedtimeFor(plannedWakeMin(d.plan, alarm, items: alarmItemsOf(c))) ??
                d.bedtime.value?.round(),
            alarm: alarm,
          );
        }),
      ],

      _SectionHead(
        'My Dashboard',
        trailing: Pressable(
          onTap: _editDashboard,
          semanticLabel: 'Customize My Dashboard',
          child: SizedBox(
            height: S.tap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('CUSTOMIZE',
                  style: F.caps.copyWith(color: P.of(c).ink)),
              const SizedBox(width: S.x2),
              Icon(LucideIcons.pencil, size: I.md, color: P.of(c).ink),
            ]),
          ),
        ),
      ),
      DashboardRows(
        ids: _tiles,
        daily: _daily,
        today: d.dayId ?? todayLabel(widget.now),
        firstDay: _firstDay,
        onOpen: (k) => go(c, TrendViewScreen(initial: k)),
        tiles: {
          kStrainRecoveryTile: StrainRecoveryCard(
            days: [
              for (var i = 6; i >= 0; i--)
                shiftDay(d.dayId ?? _day ?? todayLabel(widget.now), -i),
            ],
            strain: _daily['strain'] ?? const {},
            recovery: _daily['recovery'] ?? const {},
          ),
        },
      ),
    ])),
      if (dialsShown) _foldedDials(c, d, openDial),
    ]);
  }

  Widget _foldedDials(
      BuildContext c, HomeData d, void Function(HomeRingKind) open) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: _scroll,
        builder: (c, _) {
          final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
          final offset = _scroll.hasClients ? _scroll.offset : 0.0;
          if (stack == null || !stack.attached || offset <= .5) {
            return const SizedBox.shrink();
          }
          final w = stack.size.width;
          const ring = S.x8, barH = ring + S.x3 * 2, barY = barH / 2;
          final colW = (w - S.gutter * 2) / 3;

          double progress(HomeRingKind k) {
            final rest = _dialRest[k];
            if (rest == null) return 1;
            return (offset / math.max(1, rest.$1.dy - barY)).clamp(0.0, 1.0);
          }

          final all = kDialOrder.map(progress).reduce(math.max);
          final bar = ((all - .35) / .65).clamp(0.0, 1.0);
          final names = ((all - .75) / .25).clamp(0.0, 1.0);

          final rings = <Widget>[];
          final labels = <Widget>[];
          for (var i = 0; i < kDialOrder.length; i++) {
            final k = kDialOrder[i];
            final r = ringOf(k, d, l);
            final (value, suffix, frac, arc) = dialFace(r, d, p);
            final rest = _dialRest[k];
            final t = progress(k);
            final e = Curves.easeInOutCubic.transform(t);
            final slotX = S.gutter + colW * i + ring / 2;
            final x = rest == null ? slotX : lerpDouble(rest.$1.dx, slotX, e)!;
            final y = rest == null ? barY : lerpDouble(rest.$1.dy - offset, barY, e)!;
            final size = rest == null ? ring : lerpDouble(rest.$2, ring, e)!;
            final stroke = size * lerpDouble(.058, .125, e)!;
            final target = k == HomeRingKind.strain && e < .5 ? strainBand(d) : null;
            rings.add(Positioned(
              left: x - size / 2,
              top: y - size / 2,
              width: size,
              height: size,
              child: IgnorePointer(
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(
                    size: Size.infinite,
                    painter: r.calibrating
                        ? DashedRing(frac ?? 0, p.ink3, p.track,
                            stroke: stroke, segments: r.need ?? 24)
                        : Ring(frac ?? 0, arc, p.track,
                            stroke: stroke,
                            solid: true,
                            flatStart: true,
                            band: target,
                            bandColor: Color.alphaBlend(
                                p.ink.withValues(alpha: .24), p.track),
                            tick: target?.$1,
                            tickColor: p.ink),
                  ),
                  Opacity(
                    opacity: (1 - e * 2.4).clamp(0.0, 1.0),
                    child: Padding(
                      padding: EdgeInsets.all(size * .2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('$value$suffix',
                            style: F.n34.copyWith(
                                color: r.provisional ? p.ink3 : p.ink,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ]),
              ),
            ));
            labels.add(Positioned(
              left: S.gutter + colW * i,
              top: 0,
              width: colW,
              height: barH,
              child: IgnorePointer(
                ignoring: all < .99,
                child: Pressable(
                  onTap: () => open(k),
                  semanticLabel:
                      '${dialName(k, l)}. ${r.measured ? '$value$suffix' : r.value}',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: ring + S.x2),
                      child: Opacity(
                        opacity: names,
                        child: Text(dialName(k, l).toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: F.caps.copyWith(
                                color: p.ink, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ),
              ),
            ));
          }

          return Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: barH,
              child: Opacity(
                opacity: bar,
                child: Transform.translate(
                  offset: Offset(0, -(1 - bar) * S.x2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          p.bgTop,
                          Color.alphaBlend(p.bg.withValues(alpha: .5), p.bgTop),
                        ],
                      ),
                      border: Border(bottom: BorderSide(color: p.line)),
                    ),
                  ),
                ),
              ),
            ),
            ...labels,
            ...rings,
          ]);
        },
      ),
    );
  }

  Future<void> _editDashboard() async {
    final next = await AppSheet.open<List<String>>(
      context,
      scroll: true,
      builder: (_) => HomeDashboardEditor(selected: _tiles),
    );
    if (next == null || !mounted) return;
    Prefs.setString(Prefs.dashboardTiles, next.join(','));
    Prefs.setBool(Prefs.dashboardChartChosen, true);
    setState(() => _tiles = next);
    _load();
  }

  static List<Widget>? _bodyWatch(BuildContext c, HomeData d, String today) {
    final state = d.illnessState;
    if (state == null || state == 'green') return null;
    final day = d.illnessDay;
    if (day == null || !isRecentFindingDate(day, today: today)) return null;
    final l = AppLocalizations.of(c);

    final sameNight = day == today;
    final z = d.illnessZ;
    final zAbs = z == null ? '' : z.abs().toStringAsFixed(1);

    return [
      Observation(
        state == 'red'
            ? (l?.homeIllnessRedTitle ?? 'Recent nights add up to a raised resting heart rate')
            : sameNight
                ? (l?.homeIllnessAmberSameNight ?? 'Last night sat outside your normal range')
                : (l?.homeIllnessAmberOtherNight(prettyDay(d.illnessDay, l)) ??
                    '${prettyDay(d.illnessDay, l)} sat outside your normal range'),
        z == null
            ? (l?.homeIllnessBodyNoZ ??
                'Your resting heart rate has run above your usual over recent nights. This tracks one signal, so it shows a pattern, not a cause.')
            : (z >= 0
                ? (l?.homeIllnessBodyAbove(zAbs) ??
                    'Recent nights put your resting heart rate above your usual. That night was $zAbs× your normal night-to-night swing above it. A pattern, not a cause.')
                : (l?.homeIllnessBodyBelow(zAbs) ??
                    'Recent nights together put your resting heart rate above your usual, even though that night on its own was $zAbs× your normal night-to-night swing below it. A pattern, not a cause.')),
        advice: l?.homeIllnessAdvice ?? 'Worth noting if it continues past a couple of days.',
        onTap: () => go(c, const MetricDetail('resting_hr')),
      ),
      const SizedBox(height: S.x3),
    ];
  }

  Widget _refreshable(Widget list) =>
      RefreshIndicator(onRefresh: _pullToSync, child: list);

  Future<void> _pullToSync() async {
    AppState? app;
    try {
      app = context.read<AppState>();
    } catch (_) {}
    final isToday = _day == null || _day == todayLabel();
    if (app != null && app.isPaired && isToday && widget.data == null) {
      _tapSync(() {});
      try {
        await app.syncNow().timeout(const Duration(seconds: 90));
      } catch (_) {}
    }
    await _load();
  }
}
