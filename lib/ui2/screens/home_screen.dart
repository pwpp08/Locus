// HOME — decision-oriented. "What matters today?"
//
// Three rings that decide the day — what the night gave back, what the day has
// cost, what the night was made of — three signals worth a glance under them,
// and the small set of things the app can honestly say are worth doing.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compute/findings.dart' show isRecentFindingDate;
import '../../compute/onehz_pipeline.dart'
    show readinessInputShortfallNote, readinessUnstableBaselineNote;
import '../../data/day_label.dart'
    show dayLabelBefore, dayLabelOf, localDayStartSec, todayLabel;
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
import '../../models/activity_suggestion.dart';
import '../profile/profile.dart' show ProfileAvatar;
import '../profile/wearable_numbers.dart'
    show WearableCells, kHomeWearableRows;
import '../ui2.dart';
import '../../ai/briefing.dart' show BriefingPeriod, currentBriefingPeriod;
import 'add_activity.dart' show openAddActivity;
import 'calibration.dart' show Calibration, CalibrationCard;
import 'coach.dart' show CoachScreen;
import 'coach_workout.dart' show TodayPlanCard;
import '../../coach/workout_plan.dart';
import '../activity/catalogue.dart' show activityByName;
import 'day_heart.dart';
import 'detected_activities.dart';
import 'health_monitor.dart'
    show HealthGlance, HealthMonitorScreen, healthGlanceOf;
import '../../compute/energy_reserve.dart';
import 'home/home_energy.dart';
import 'home/home_card_deck.dart';
import 'home/home_cards.dart';
import 'home/home_daily_cards.dart';
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
import 'nap_detail.dart' show NapDetailScreen;
import 'plus_menu.dart';
import 'readiness_detail.dart';
import 'recovery_calendar.dart' show openRecoveryCalendar;
import 'sleep_detail.dart';
import 'sleep_planner.dart'
    show
        alarmItemsOf,
        armedWakeMin,
        firstAlarmWakeMin,
        plannedBedMin,
        plannedWakeMin;
import 'start_activity.dart';
import 'strain_recovery_card.dart';
import 'strength_trainer.dart';
import 'stress_monitor.dart';
import 'compare_metrics.dart';
import 'trend_view.dart';
import 'workout_detail.dart';

// Re-export submodules for clean public API and test compatibility.
export 'home/home_card_deck.dart';
export 'home/home_cards.dart';
export 'home/home_daily_cards.dart';
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

// ═══════════════════ the screen ═══════════════════

/// A day for Home to show, asked for by another screen (a report's best and
/// worst day). Home takes it and clears it; see [openDayOnHome].
final homeDayRequest = ValueNotifier<String?>(null);

/// Back to the Home tab, showing [day] as its pager would.
void openDayOnHome(BuildContext c, String day) {
  homeDayRequest.value = day;
  final app = c.read<AppState?>();
  if (app != null) {
    // Tab 0 is Home; the shell pops to itself and switches.
    app.navRequest.value = 0;
  } else {
    Navigator.of(c).popUntil((r) => r.isFirst);
  }
}

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

  /// Where each dial rests, in scroll-content coordinates. Measured AFTER a
  /// frame (layout and offset agree then) — on every home build and after
  /// every scroll frame — and kept when a dial is scrolled out of the list:
  /// dropping it snapped the flying rings straight into the bar, and
  /// measuring only on a home build left them starting from where the dials
  /// sat before a card above them loaded. Both read as a jumpy fold.
  void _measureDials() {
    _measureQueued = false;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || stack == null || !stack.attached) return;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    var moved = false;
    for (final k in kDialOrder) {
      final rb = _dialKeys[k]!.currentContext?.findRenderObject() as RenderBox?;
      if (rb == null || !rb.attached || !rb.hasSize) continue;
      final top = stack.globalToLocal(rb.localToGlobal(Offset.zero));
      final rest = (
        Offset(top.dx + rb.size.width / 2, top.dy + rb.size.height / 2 + offset),
        rb.size.width,
      );
      final was = _dialRest[k];
      if (was == null ||
          (was.$1 - rest.$1).distance > .5 ||
          (was.$2 - rest.$2).abs() > .5) {
        moved = true;
      }
      _dialRest[k] = rest;
    }
    // The fold is drawn from these; a changed rest must redraw it now.
    if (moved && _scroll.hasClients && _scroll.offset > .5) setState(() {});
  }

  bool _measureQueued = false;

  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureDials());
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
    homeDayRequest.removeListener(_dayAsked);
    _syncTapTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  String? _takeAsked() {
    final d = homeDayRequest.value;
    if (d != null) homeDayRequest.value = null;
    return d;
  }

  /// Taken after the frame, and only while still mounted: switching tabs from
  /// code re-keys the shell, and the Home being replaced must not eat the
  /// request the new one opens on.
  void _dayAsked() {
    if (homeDayRequest.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final d = _takeAsked();
      if (d != null) _goDay(d);
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_queueMeasure);
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
    _day = _takeAsked();
    homeDayRequest.addListener(_dayAsked);
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
  List<ActivitySuggestion> _detected = const [];
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
  Set<String> _expanded = dashboardExpandedOf();

  Future<void> _loadExtras(LocalRepository repo, HomeData d) async {
    final day = d.dayId ?? _day ?? todayLabel();
    var night = const <String, dynamic>{};
    var sessions = const <Map<String, dynamic>>[];
    var naps = const <Map<String, dynamic>>[];
    var detected = const <ActivitySuggestion>[];
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
      detected = [
        for (final s in await repo.pendingActivities())
          if (s.kind == ActivityKind.workout &&
              dayLabelOf(DateTime.fromMillisecondsSinceEpoch(s.startTs * 1000)) ==
                  day)
            s,
      ];
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
    // What the expanded cards draw besides the daily figure: the layers of a
    // stacked or paired metric, and bed and wake for nights on a clock.
    final layers = <String, List<Map<String, double>>>{};
    Map<String, ({double bed, double wake})>? spans;
    for (final k in _tiles) {
      final m = trendMetricOf(k);
      if (m == null) continue;
      if (m.kind == TrendKind.stacked || m.kind == TrendKind.dual) {
        layers[k] = await loader.layers(m);
      } else if (m.kind == TrendKind.floating) {
        spans ??= await loader.sleepSpans();
      }
    }
    final first = await loader.firstDay();
    // Today's cards only: a past day has nothing left to act on.
    var cards = const <DailyCard>[];
    if (day == todayLabel()) {
      try {
        cards = await loadDailyCards(d, loader.series);
      } catch (_) {}
    }
    EnergyReserve? energy;
    final midnightAt = DateTime.parse(day);
    final midnight = midnightAt.millisecondsSinceEpoch ~/ 1000;
    if (day == todayLabel()) {
      try {
        energy = await _energyFor(repo, day, daily, naps, midnight);
      } catch (_) {}
    }
    if (!mounted) return;
    _energy = energy;
    _energyMidnight = midnight;
    _cards = cards;
    _layers = layers;
    _spans = spans;
    _loader = loader;
    _night = night;
    _sessions = sessions;
    _naps = naps;
    _detected = detected;
    _daily = daily;
    _firstDay = first;
    _loadStress(repo, day);
    unawaited(healthGlanceOf(context).then((h) {
      if (mounted) setState(() => _health = h);
    }).catchError((Object _) {}));
  }

  /// Today's energy reserve, carried over from yesterday's: yesterday's run
  /// to last night's onset gives the level the night starts from, as the
  /// battery-style scores do. Without a yesterday, the morning is anchored on
  /// today's recovery instead.
  Future<EnergyReserve?> _energyFor(
    LocalRepository repo,
    String day,
    Map<String, Map<String, double>> daily,
    List<Map<String, dynamic>> naps,
    int midnight,
  ) async {
    final src = _stressSource ??= StressSource(repo);
    final custom = Prefs.getInt('custom_max_hr', 0);

    List<(int, double)> hrOf(Map<String, dynamic> timeline) => [
          for (final e in (timeline['hr'] as List?) ?? const [])
            if (e is Map && e['t'] is num && e['v'] is num)
              ((e['t'] as num).round(), (e['v'] as num).toDouble()),
        ];

    Future<List<(int, double)>> scoresOf(String d) async {
      final start = localDayStartSec(d);
      if (start == null) return const [];
      try {
        final data = await src.load(d);
        return [
          for (var i = 0; i < data.scores.length; i++)
            if (data.scores[i] != null) (start + i * 60, data.scores[i]!),
        ];
      } catch (_) {
        return const [];
      }
    }

    final timeline = await repo.getDayTimeline(day);
    final strain = await repo.getDayStrain(day);
    final overview = await repo.getDayOverview(day);
    final sleep = await repo.getDaySleepV2(day);
    final hasNight = sleep['has_sleep'] == true;
    final onset = hasNight ? (sleep['onset_ts'] as num?)?.round() : null;
    final wake = hasNight ? (sleep['wake_ts'] as num?)?.round() : null;
    final restingHr = (overview['resting_hr'] as num?)?.toDouble();
    final maxHr = custom > 0
        ? custom.toDouble()
        : (strain['max_hr_used'] as num?)?.toDouble();
    final todayHr = hrOf(timeline);
    final todayScores = await scoresOf(day);

    // Yesterday, run up to last night's onset.
    double? onsetLevel;
    final yday = dayLabelBefore(day, 1);
    if (onset != null && yday != null) {
      try {
        final ySleep = await repo.getDaySleepV2(yday);
        final yOverview = await repo.getDayOverview(yday);
        final yStrain = await repo.getDayStrain(yday);
        final yHasNight = ySleep['has_sleep'] == true;
        final yRun = energyReserve(
          hr: [...hrOf(await repo.getDayTimeline(yday)), ...todayHr],
          onsetTs: yHasNight ? (ySleep['onset_ts'] as num?)?.round() : null,
          wakeTs: yHasNight ? (ySleep['wake_ts'] as num?)?.round() : null,
          recovery: daily['recovery']?[yday],
          restingHr: (yOverview['resting_hr'] as num?)?.toDouble() ?? restingHr,
          maxHr: custom > 0
              ? custom.toDouble()
              : (yStrain['max_hr_used'] as num?)?.toDouble() ?? maxHr,
          midnight: localDayStartSec(yday) ?? midnight,
          stress: [...await scoresOf(yday), ...todayScores],
          until: onset,
        );
        onsetLevel = yRun?.level;
      } catch (_) {}
    }

    return energyReserve(
      hr: todayHr,
      onsetTs: onset,
      wakeTs: wake,
      recovery: daily['recovery']?[day],
      restingHr: restingHr,
      maxHr: maxHr,
      midnight: midnight,
      naps: [
        for (final n in naps)
          if (n['start'] is num && n['end'] is num)
            ((n['start'] as num).round(), (n['end'] as num).round()),
      ],
      stress: todayScores,
      onsetLevel: onsetLevel,
    );
  }

  EnergyReserve? _energy;
  int _energyMidnight = 0;
  Map<String, Map<String, double>> _daily = const {};
  List<DailyCard> _cards = const [];
  Map<String, List<Map<String, double>>> _layers = const {};
  Map<String, ({double bed, double wake})>? _spans;
  TrendLoader? _loader;
  String? _firstDay;

  Widget _header(BuildContext c, String? dayId) {
    final today = todayLabel(widget.now);
    final cur = _day ?? dayId ?? today;
    return Padding(
      padding: const EdgeInsets.only(top: S.x3, bottom: S.x4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(alignment: Alignment.center, children: [
          DayPager(
            day: cur,
            today: today,
            days: _days,
            onDay: _goDay,
            onCalendar: () => _openCalendar(c, cur),
          ),
          const Align(
              alignment: AlignmentDirectional.centerStart,
              child: ProfileAvatar(accent: C.dialStrain, size: S.x12 * 0.8)),
          const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _DeviceStatus()),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final d = _d;

    if (d == null) {
      return _scrolling(padding: pad.copyWith(bottom: S.navClear(c)), children: [
        _header(c, null),
        const SizedBox(height: S.x5),
        const SizedBox(height: S.x3),
        const DetectedActivitiesCard(),
        if (_loading)
          // The mark drawing itself while the day is read (a long first read
          // after an update runs the migrations and the re-derive).
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x8),
            child: Column(children: [
              const LocusMark(loop: true, size: S.x16 + S.x8),
              const SizedBox(height: S.x3),
              Text('Getting your day ready',
                  style: F.cap.copyWith(color: P.of(c).ink3)),
            ]),
          )
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
          CalibrationCard(Calibration.of(days: _days.length)),
        ],
        // Not over the mark: a read that failed still reaches the alarm.
        if (!_loading && (_day == null || _day == todayLabel()))
          if (alarmArmOfContext(c) case final (DateTime?, AlarmArmState) a) ...[
            const SizedBox(height: S.x3),
            alarmDoor(c, a.$1, a.$2),
          ],
      ]);
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

    final cal = Calibration.of(
      days: _days.length,
      baselineNights: baselineCountsFromNote(d.readiness.note)?.have,
      sleep: d.sleepMin.value != null,
      strain: !d.strain.isEmpty,
      stress: switch (_stress) { final s? => s.baseline != null, null => null },
      stressDays: _stress?.usableDays,
      recovery: !d.readiness.isEmpty,
      health: _health != null,
    );
    final firstWeeks = isToday && widget.data == null && !cal.complete;

    final rebuilt = dbRebuiltCard(dbRebuiltOf(c), l);
    void openDial(HomeRingKind k) => go(
        c,
        switch (k) {
          HomeRingKind.recovery => ReadinessDetail(day: isToday ? null : _day),
          HomeRingKind.strain => DayStrainDetail(day: isToday ? null : _day),
          HomeRingKind.sleep => SleepDetail(day: isToday ? null : _day),
        });
    final dialsShown = (!bare && RingTrio.has(d)) || quietDay;

    _queueMeasure();
    return Stack(key: _stackKey, children: [
     _scrolling(
        controller: _scroll,
        padding: pad.copyWith(bottom: S.navClear(c)),
        children: [
      _header(c, d.dayId),
      // Today's sync bar, once the band has sent anything at all.
      if (isToday)
        if (lastDataAtOf(c) case final at?)
          HomeSyncBanner(
            key: const ValueKey('sync-banner'),
            state: syncBarStateOf(
                syncing: syncingNowOf(c), at: at, now: DateTime.now()),
            syncedTo: syncedToText(at, todayLabel(widget.now), l),
            onTap: switch (syncOf(c)) {
              final sync? => () => _tapSync(sync),
              null => null,
            },
          ),
      if (rebuilt != null) ...[rebuilt, const SizedBox(height: S.x3)],
      ...?_bodyWatch(c, d, todayLabel(widget.now)),
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
          CalibrationCard(cal),
        ],
      ] else ...[
        if (dialsShown) ...[
          _Dials(
              d: d,
              onOpen: openDial,
              keys: _dialKeys,
              scroll: _scroll,
              note: quietDay ? 'No sleep yet today.' : null),
          if (isToday) ...[
            DailyCardDeck(cards: _cards, day: todayLabel()),
            _Monitors(
              health: _health,
              stress: _stress,
              healthCalibrating: cal.health ? null : cal.milestones[4],
              onHealth: () => go(c, const HealthMonitorScreen()),
              onStress: () => go(c, const StressMonitorScreen()),
            ),
          ],
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
        if (firstWeeks) ...[
          const SizedBox(height: S.x3),
          CalibrationCard(cal),
        ],
      ],

      if (widget.data == null) ...[
        const SizedBox(height: S.x3),
        WearableCells(kHomeWearableRows, date: isToday ? null : _day),
      ],

      // A past day has no cards or monitors under its dials, so the dials'
      // own foot is gap enough before what follows.
      if (isToday) const SizedBox(height: S.x3),
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
      if (isToday)
        Builder(builder: (c) {
          final period = currentBriefingPeriod(DateTime.now());
          return DailyOutlookRow(
            name: d.name,
            evening: period == BriefingPeriod.evening,
            onOutlook: () => go(c, CoachScreen(outlook: period)),
          );
        }),
      // The workout committed in the coach for today, ready to start.
      if (isToday)
        ValueListenableBuilder<int>(
          valueListenable: WorkoutPlanStore.changed,
          builder: (c, _, _) {
            final plan = WorkoutPlanStore.forDay(todayLabel());
            if (plan == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: S.x3),
              child: TodayPlanCard(
                plan,
                onDrop: WorkoutPlanStore.clear,
                onStart: () {
                  // The plan's strain is the session's goal on Start.
                  Prefs.setString(Prefs.activityStrainTarget,
                      plan.strain?.toStringAsFixed(1) ?? '');
                  go(c, StartActivityScreen(
                      initial: activityByName(plan.sport)));
                },
              ),
            );
          },
        ),
      _MyDay(
        day: d.dayId ?? _day ?? todayLabel(),
        night: _night,
        sessions: _sessions,
        naps: _naps,
        detected: _detected,
        onDetected: (s) async {
          if (await identifyDetected(c, s) && mounted) _load();
        },
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
        onNap: (nap) async {
          final changed = await Navigator.of(c).push<bool>(themedRoute(
              (_) => NapDetailScreen(nap: nap, day: isToday ? null : _day),
              name: 'NapDetailScreen'));
          if (changed == true && mounted) _load();
        },
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
          // The wake time is the first alarm when one is set (the same rule
          // the Sleep Planner plans by), else the recommended one.
          final items = alarmItemsOf(c);
          final now = DateTime.now();
          final first = firstAlarmWakeMin(alarm, items: items, now: now);
          final wake = plannedWakeMin(d.plan, alarm, items: items, now: now);
          // The band's alarm only when it is this night's: after a skipped
          // morning it already holds the next one.
          final tonight =
              first != null && armedWakeMin(alarm, now) != null ? alarm : null;
          return _TonightsSleep(
            bedtimeMin: plannedBedMin(d.plan, wake) ?? d.bedtime.value?.round(),
            wakeMin: tonight == null ? wake : null,
            wakeIsAlarm: first != null,
            alarm: tonight,
          );
        }),
      ],

      if (isToday && _energy != null) ...[
        const SizedBox(height: S.x3),
        EnergyReserveCard(data: _energy!, midnight: _energyMidnight),
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
        expanded: _expanded,
        daily: _daily,
        layers: _layers,
        spans: _spans,
        today: d.dayId ?? todayLabel(widget.now),
        firstDay: _firstDay,
        onOpen: (k) => go(c, TrendViewScreen(initial: k)),
        tiles: {
          if (_loader != null)
            kCompareTile: CompareMetricsCard(
              loader: _loader!,
              today: d.dayId ?? todayLabel(widget.now),
              firstDay: _firstDay,
              onOpen: () =>
                  go(c, const TrendViewScreen(initial: kCompareTile)),
            ),
          kStrainRecoveryTile: StrainRecoveryCard(
            days: [
              for (var i = 6; i >= 0; i--)
                shiftDay(d.dayId ?? _day ?? todayLabel(widget.now), -i),
            ],
            strain: _daily['strain'] ?? const {},
            recovery: _daily['recovery'] ?? const {},
            calibrating: isToday && !cal.recovery ? cal.milestones[3] : null,
          ),
        },
      ),
    ]),
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
                            band: target?.band,
                            bandColor: Color.alphaBlend(
                                p.ink.withValues(alpha: .24), p.track),
                            tick: target?.optimal,
                            tickColor: p.ink,
                            tickWidth: .26),
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
    final next = await AppSheet.open<DashboardChoice>(
      context,
      scroll: true,
      builder: (_) =>
          HomeDashboardEditor(selected: _tiles, expanded: _expanded),
    );
    if (next == null || !mounted) return;
    Prefs.setString(Prefs.dashboardTiles, next.tiles.join(','));
    Prefs.setString(Prefs.dashboardExpanded, next.expanded.join(','));
    Prefs.setBool(Prefs.dashboardChartChosen, true);
    setState(() {
      _tiles = next.tiles;
      _expanded = next.expanded;
    });
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

  /// The page: the pull-down mark first ([LocusPullRefresh]), then the list.
  Widget _scrolling({
    ScrollController? controller,
    required EdgeInsets padding,
    required List<Widget> children,
  }) =>
      CustomScrollView(
        controller: controller,
        physics: kPullPhysics,
        slivers: [
          LocusPullRefresh(onRefresh: _pullToSync),
          SliverPadding(
            padding: padding,
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
        ],
      );

  Future<void> _pullToSync() async {
    AppState? app;
    try {
      app = context.read<AppState>();
    } catch (_) {}
    final isToday = _day == null || _day == todayLabel();
    if (app != null && app.isPaired && isToday && widget.data == null) {
      _tapSync(() {});
      // The sync runs on in the background (its own indicator says so, and the
      // page re-reads when it lands). The pull waits only for the quick read
      // below, so the word always goes back up when its animation is done
      // instead of hanging down for as long as a slow band takes.
      unawaited(app
          .syncNow()
          .timeout(const Duration(seconds: 90))
          .then<void>((_) {}, onError: (Object _) {}));
    }
    await _load();
  }
}

