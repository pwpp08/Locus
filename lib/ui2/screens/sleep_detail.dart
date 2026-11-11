// SLEEP — the dial's own screen.
//
// Laid out from the reference recording (sizes at 1.5 px to the dp, see DC):
// the ring and its four contributors, Last Night's Sleep (heart rate over the
// night, stage bars against the typical range), Hours vs. Needed, Sleep
// Consistency, Sleep Efficiency, Sleep Stress, then seven days of each.
//
// Every figure is read from what the derive stored for that night. A figure the
// night has none of is '--', never a stand-in: a stage bar with no minutes is
// empty and a comparison with no history has no triangle. The stage figures are
// the pipeline's point estimates.

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compute/sleep_stress.dart';
import '../../compute/whoop_scores.dart' show whoopStrainSleepMin;
import '../../data/day_label.dart';
import '../../data/db.dart' show LocalDb;
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../profile/devices.dart' show DeviceFilter;
import '../ui2.dart';
import 'dial_parts.dart';
import 'edit_time_in_bed.dart';
import 'home_screen.dart';
import 'metric_detail.dart';
import 'movement_lane.dart';
import 'nap_detail.dart' show NapDetailScreen;
import 'stress_monitor.dart' show StressMonitorScreen, StressSource;
import 'trend_view.dart' show TrendViewScreen, shiftDay;
import 'window_editor.dart';

/// How far back "prior 30 days" reaches.
const _window = 30;

/// Nights of history before a typical range is drawn: below this the quartiles
/// of three or four nights are noise.
const _minNights = 7;

/// The window a "Change the times" correction means. Each picked clock time
/// lands on whichever calendar day puts it nearest the time it corrects, so a
/// bedtime moved across midnight (23:50 → 00:20, or 00:30 → 23:40) stays on
/// the same night instead of jumping a whole day. A wake still at or before
/// the onset becomes the first `up` after it. `day + k` rather than adding a Duration:
/// calendar arithmetic across a possible DST boundary, not elapsed time.
/// A picker left on the measured clock time keeps the measured instant:
/// rebuilding it drops the seconds, and in a DST fall-back hour the local
/// wall time names two instants.
(DateTime, DateTime) correctedSleepWindow(
    DateTime onset, DateTime wake, TimeOfDay bed, TimeOfDay up) {
  DateTime nearest(DateTime ref, TimeOfDay t) {
    if (ref.hour == t.hour && ref.minute == t.minute) return ref;
    DateTime? best;
    for (var k = -1; k <= 1; k++) {
      final c = DateTime(ref.year, ref.month, ref.day + k, t.hour, t.minute);
      if (best == null ||
          c.difference(ref).abs() < best.difference(ref).abs()) {
        best = c;
      }
    }
    return best!;
  }

  final newOnset = nearest(onset, bed);
  var newWake = nearest(wake, up);
  // First occurrence of `up` after the onset, not onset.day + 1: the nearest
  // pick can land a day early (truncated window, wake moved >12h later).
  for (var k = 0; !newWake.isAfter(newOnset); k++) {
    newWake = DateTime(newOnset.year, newOnset.month, newOnset.day + k,
        up.hour, up.minute);
  }
  return (newOnset, newWake);
}

/// A per-second label from the segmenter, or NULL for a second nobody watched.
SleepStage? _stageOf(Object? raw) => switch (raw?.toString()) {
      'wake' || 'awake' => SleepStage.awake,
      'rem' => SleepStage.rem,
      'deep' => SleepStage.deep,
      'light' || 'nrem' => SleepStage.light,
      _ => null,
    };

/// A stretch of one stage, as fractions of the night.
typedef StageRun = ({SleepStage stage, double from, double to});

/// The night's stage changes as runs, onset to wake. Empty with no hypnogram.
List<StageRun> stageRunsOf(Map<String, dynamic> night) {
  final pts = night['hypnogram'];
  final t0 = (night['onset_ts'] as num?)?.toDouble();
  final t1 = (night['wake_ts'] as num?)?.toDouble();
  if (pts is! List || pts.length < 2 || t0 == null || t1 == null || t1 <= t0) {
    return const [];
  }
  final out = <StageRun>[];
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], b = pts[i + 1];
    if (a is! Map || b is! Map || a['t'] is! num || b['t'] is! num) continue;
    final st = _stageOf(a['stage']);
    if (st == null) continue;
    final f0 = (((a['t'] as num) - t0) / (t1 - t0)).clamp(0.0, 1.0);
    final f1 = (((b['t'] as num) - t0) / (t1 - t0)).clamp(0.0, 1.0);
    if (f1 > f0) out.add((stage: st, from: f0, to: f1));
  }
  return out;
}

/// The middle half of [xs], or null below [_minNights].
(double, double)? _iqr(List<double> xs) {
  if (xs.length < _minNights) return null;
  final s = [...xs]..sort();
  double q(double f) => s[((s.length - 1) * f).round()];
  return (q(.25), q(.75));
}

double? _mean(Iterable<double> xs) {
  final l = xs.toList();
  return l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
}

/// A night's need in its parts, read back from the stored series: the strain
/// and nap terms from the day before, the debt from the night before, and the
/// baseline as what is left of the need the score used.
class NeedParts {
  final double baseline, strain, debt, nap;
  const NeedParts(this.baseline, this.strain, this.debt, this.nap);
}

/// Everything under the ring that reaches past tonight's own bundle.
class SleepVitals {
  /// Seven days ending on the night shown, oldest first.
  final List<String> week;

  /// Value per day: performance, minutes asleep, the night's own need, hours
  /// against need in percent, deep, REM, consistency, efficiency, debt.
  final Map<String, double> perf, tst, need, hvn, deep, rem, consistency, eff, debt;

  /// Bed and wake per night, in minutes after noon.
  final Map<String, ({double bed, double wake})> spans;

  /// Heart rate per minute, and where it starts, in epoch seconds.
  final List<({int t, double v})> heart;

  /// Movement under the heart rate, on the same clock.
  final List<MovePoint> movement;

  /// Each stage's typical share of the night, 0–1.
  final Map<SleepStage, (double, double)> typical;
  final NeedParts? needParts;

  const SleepVitals({
    this.week = const [],
    this.perf = const {},
    this.tst = const {},
    this.need = const {},
    this.hvn = const {},
    this.deep = const {},
    this.rem = const {},
    this.consistency = const {},
    this.eff = const {},
    this.debt = const {},
    this.spans = const {},
    this.heart = const [],
    this.movement = const [],
    this.typical = const {},
    this.needParts,
  });

  /// The mean of a series over the [_window] days before [day].
  double? prior(Map<String, double> m, String? day) {
    if (day == null) return null;
    return _mean([
      for (var i = 1; i <= _window; i++) ?m[shiftDay(day, -i)],
    ]);
  }

  double? priorRestorative(String? day) {
    if (day == null) return null;
    return _mean([
      for (var i = 1; i <= _window; i++)
        if (deep[shiftDay(day, -i)] case final d?)
          if (rem[shiftDay(day, -i)] case final r?) d + r,
    ]);
  }
}

class SleepData {
  final String? day;

  /// Every day this install has derived, newest first.
  final List<String> days;

  final Map<String, dynamic> night;
  final Map<String, dynamic> timeline;

  /// The user's own recent nights, LAST NIGHT EXCLUDED, oldest→newest.
  final List<double> tstHistory;

  /// Sleep-onset latency, ONLY on a user-set window.
  final double? solMin;

  const SleepData({
    this.day,
    this.days = const [],
    this.night = const {},
    this.timeline = const {},
    this.tstHistory = const [],
    this.solMin,
    this.deviceNights = const [],
    this.consistency,
    this.performance,
    this.lastNeedMin,
    this.vitals = const SleepVitals(),
    this.stress = const {},
  });

  /// The night's 4-night Sleep Consistency, 0–100. Null until it has three.
  final double? consistency;

  /// This night's Sleep Performance and the need it was scored against, as the
  /// cross-day pass stored them. Null: not scored.
  final double? performance;
  final double? lastNeedMin;
  final SleepVitals vitals;

  /// Sleep stress per night, already read (a fixture); the screen reads the
  /// rest itself after it has drawn.
  final Map<String, SleepStress> stress;

  bool get hasNight => night['duration_min'] is num;

  /// Each paired device's own staging of this night (`getDeviceNights`).
  final List<Map<String, Object?>> deviceNights;

  static List<double> _trailingUntil(Map<String, double> m, String? day) => [
        if (day != null)
          for (var i = _window; i >= 1; i--) ?m[shiftDay(day, -i)],
      ];

  static double? _on(Map<String, double> m, String? day) =>
      day == null ? null : m[day];

  static Future<SleepData> load(LocalRepository repo, {String? want}) async {
    final today = await repo.getToday();
    // THE NIGHT `getToday` ACTUALLY SERVED. Home's Sleep card is that night, so
    // tapping it has to open that night.
    final days = await repo.availableDays();
    final todayDay = (today['status'] as Map?)?['today_day']?.toString();
    // Today's own night first, as soon as it has one, settled or not.
    Map<String, dynamic>? todayNight;
    if (want == null && todayDay != null && days.contains(todayDay)) {
      final n = await repo.getDaySleepV2(todayDay);
      if (n['has_sleep'] == true) todayNight = n;
    }
    final day = todayNight != null ? todayDay : pickDay(days, want, todayDay);
    if (day == null) return SleepData(days: days);

    final night = todayNight ?? await repo.getDaySleepV2(day);
    var deviceNights = const <Map<String, Object?>>[];
    try {
      deviceNights = await repo.getDeviceNights(day);
    } on UnimplementedError {
      // A repository without per-device nights: ours only.
    }
    final timeline = await repo.getDayTimeline(day);

    final tst = await dialSeries(repo, 'sleep');
    final need = await dialSeries(repo, 'sleep_last_need_min');
    final deep = await dialSeries(repo, 'deep');
    final rem = await dialSeries(repo, 'rem');
    final light = await dialSeries(repo, 'light');
    final perf = await dialSeries(repo, 'sleep_performance');
    final consistency = await dialSeries(repo, 'sleep_consistency');
    final eff = await dialSeries(repo, 'efficiency');
    final debt = await dialSeries(repo, 'sleep_debt_min');
    final strain = await dialSeries(repo, 'strain');
    final naps = await dialSeries(repo, 'nap_min');
    final sol = await dialSeries(repo, 'sol_min');

    // Bed and wake for every recent night, this one included.
    final spans = await bedAndWake(repo, day: day, nights: _window + 8);
    final on = night['onset_ts'], off = night['wake_ts'];
    if (on is num && off is num) {
      if (bedWakeOf(on, off) case final s?) spans[day] = s;
    }
    final inBed = {for (final e in spans.entries) e.key: e.value.wake - e.value.bed};

    // Each stage's usual share of the night, from the nights before it.
    List<double> shares(Map<String, double> m) => [
          for (var i = 1; i <= _window; i++)
            if (m[shiftDay(day, -i)] case final v?)
              if (inBed[shiftDay(day, -i)] case final b? when b > 0) v / b,
        ];
    final awake = <String, double>{
      for (final e in tst.entries)
        if (inBed[e.key] case final b?) e.key: math.max(0.0, b - e.value),
    };
    final typical = <SleepStage, (double, double)>{
      SleepStage.awake: ?_iqr(shares(awake)),
      SleepStage.light: ?_iqr(shares(light)),
      SleepStage.deep: ?_iqr(shares(deep)),
      SleepStage.rem: ?_iqr(shares(rem)),
    };

    final hvn = <String, double>{
      for (final e in tst.entries)
        if (need[e.key] case final n? when n > 0) e.key: e.value / n * 100,
    };

    // The need's parts, by the same arithmetic as the pipeline's chain.
    NeedParts? parts;
    final total = need[day];
    if (total != null) {
      final before = shiftDay(day, -1);
      final s = strain[before];
      final strainMin = s == null ? 0.0 : whoopStrainSleepMin(s);
      final nap = naps[before] ?? 0.0;
      final lastNeed = need[before], lastTst = tst[before];
      final debtMin = lastNeed == null || lastTst == null
          ? 0.0
          : .5 * math.max(0.0, lastNeed - lastTst);
      final base = total - strainMin - debtMin + nap;
      if (base > 0) parts = NeedParts(base, strainMin, debtMin, nap);
    }

    var heart = const <({int t, double v})>[];
    var movement = const <MovePoint>[];
    if (on is num && off is num && off > on) {
      final pad = ((off - on) * .07).round();
      movement = await readMovement(on.toInt() - pad, off.toInt() + pad,
          repo: repo, day: day);
      try {
        final rows = await LocalDb.hrPerMinuteBetween(
            on.toInt() - pad, off.toInt() + pad);
        heart = [
          for (final r in rows)
            if (r['t'] is num && r['v'] is num)
              (t: (r['t'] as num).toInt(), v: (r['v'] as num).toDouble()),
        ];
      } catch (_) {
        // No minute store behind this repository.
      }
      // Past the raw store's retention, the bundle's own curve still has it.
      if (heart.isEmpty) {
        final hr = timeline['hr'];
        heart = [
          if (hr is List)
            for (final p in hr)
              if (p is Map && p['t'] is num && p['v'] is num)
                if ((p['t'] as num) >= on && (p['t'] as num) <= off)
                  (t: (p['t'] as num).toInt(), v: (p['v'] as num).toDouble()),
        ];
      }
    }

    return SleepData(
      day: day,
      days: days,
      night: night,
      timeline: timeline,
      tstHistory: _trailingUntil(tst, day),
      solMin: _on(sol, day),
      deviceNights: deviceNights,
      consistency: _on(consistency, day),
      performance: _on(perf, day),
      lastNeedMin: _on(need, day),
      vitals: SleepVitals(
        week: [for (var i = 6; i >= 0; i--) shiftDay(day, -i)],
        perf: perf,
        tst: tst,
        need: need,
        hvn: hvn,
        deep: deep,
        rem: rem,
        consistency: consistency,
        eff: eff,
        debt: debt,
        spans: spans,
        heart: heart,
        movement: movement,
        typical: typical,
        needParts: parts,
      ),
    );
  }
}

class SleepDetail extends StatefulWidget {
  final SleepData? data;

  /// The night to open. Null means last night.
  final String? day;

  const SleepDetail({super.key, this.data, this.day});

  @override
  State<SleepDetail> createState() => _SleepDetailState();
}

class _SleepDetailState extends State<SleepDetail> {
  SleepData? _d;
  bool _loading = true;
  String? _day;

  /// Sleep stress by night, filled in after the screen has drawn: each night
  /// decodes a dozen days.
  Map<String, SleepStress> _stress = const {};
  StressSource? _stressSource;
  bool _saving = false; // an override write + its forced re-derive is in flight

  /// The stage lit on the chart and the bars, or null.
  SleepStage? _picked;

  /// Whose staging is shown: null for ours, else a device id.
  String? _staging;

  /// Why the last correction did not take. Null when it did.
  String? _overrideFailed;

  @override
  void initState() {
    super.initState();
    _day = widget.day;
    if (widget.data != null) {
      _d = widget.data;
      _stress = widget.data!.stress;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // A second `_load()` can start while one is in flight (after an edit);
  // whichever resolves last would otherwise win and could paint the wrong
  // night. Stamp each call and only apply the result still holding the latest.
  int _loadGen = 0;

  Future<void> _load() async {
    final gen = ++_loadGen;
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted && gen == _loadGen) setState(() => _loading = false);
      return;
    }
    try {
      final d = await SleepData.load(repo, want: _day);
      if (mounted && gen == _loadGen) {
        setState(() => (_d = d, _loading = false));
        unawaited(_loadStress(repo, d, gen));
      }
    } catch (_) {
      if (mounted && gen == _loadGen) setState(() => _loading = false);
    }
  }

  /// The night on screen first, then its week, then the rest of its 30 days.
  Future<void> _loadStress(LocalRepository repo, SleepData d, int gen) async {
    final day = d.day;
    if (day == null || !d.hasNight) return;
    final src = _stressSource ??= StressSource(repo);
    for (var i = 0; i <= _window; i++) {
      final at = shiftDay(day, -i);
      final r = await src.sleepStressOf(at);
      if (!mounted || gen != _loadGen) return;
      if (r != null) setState(() => _stress = {..._stress, at: r});
    }
  }

  @override
  Widget build(BuildContext c) {
    final d = _d ?? const SleepData();
    final l = AppLocalizations.of(c);
    final shown = _day ?? d.day;
    final title = dialDayName(shown, l).isEmpty
        ? (l?.sleepDetailNavTitle ?? 'Sleep')
        : dialDayName(shown, l);

    if (_loading && _d == null) {
      return DialScaffold(title: title, children: const [
        SizedBox(height: S.x8),
        Center(child: CircularProgressIndicator()),
      ]);
    }

    if (!d.hasNight) {
      // One answer for every night with nothing scored: none detected, one the
      // user marked as not sleep, or today before any. Each is put right the
      // same way, by entering the night by hand on the heart rate chart.
      final at = shown ?? todayLabel();
      return DialScaffold(title: title, children: [
        const SizedBox(height: S.x2),
        StatusCard(
          'No sleep recorded',
          'Nothing was scored as sleep for this night. Set the times you '
              'slept and it is scored like any other night.',
          fix: 'Set one manually',
          onFix: _saving || _loading ? null : () => _addWindow(at),
          icon: LucideIcons.moon,
        ),
        ..._windowStatus(c),
        // A day with no main-sleep window can still have naps.
        ..._napsButton(c, d),
      ]);
    }

    final n = d.night;
    final staged = _deviceNight(d);
    final night = staged ?? n;
    return DialScaffold(title: title, children: [
      _SleepHero(d: d, stress: _stress[d.day]),
      if (n['provisional'] == true)
        Padding(
          padding: const EdgeInsets.only(top: S.x2),
          child: Center(
            child: Text('Still finishing up: these figures may move a little.',
                style: F.dText.copyWith(color: DC.ink3)),
          ),
        ),
      const SizedBox(height: S.x8 + S.x3),

      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: dialHeading("Last Night's Sleep")),
        Pressable(
          onTap: _saving ? null : () => _openEdit(c, d),
          semanticLabel: 'Edit time in bed',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('EDIT', style: F.dLabel.copyWith(color: DC.ink)),
            const SizedBox(width: S.x3),
            const Icon(LucideIcons.pencil, size: I.sm, color: DC.ink),
            const SizedBox(width: S.x2),
          ]),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: S.x1 + S.hair),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: dialDayName(d.day, l),
              style: F.dText.copyWith(color: DC.ink)),
          TextSpan(
              text: ' vs. prior 30 days',
              style: F.dText.copyWith(color: DC.ink2)),
        ])),
      ),
      const SizedBox(height: S.x5 + S.hair),

      // Ours, or any paired device's own staging of the same night — shown
      // side by side as alternatives, never merged.
      if (d.deviceNights.isNotEmpty) ...[
        DeviceFilter(
          allLabel: 'Locus',
          showWithOne: true,
          options: [
            for (final dn in d.deviceNights)
              (
                deviceId: dn['device_id'] as String,
                label: (dn['label'] as String?) ?? 'Device',
                selectable: true,
                reason: null,
              ),
          ],
          selected: _staging,
          onSelect: (id) => setState(() {
            _staging = id;
            _picked = null;
          }),
        ),
        if (_stagedBy(d) case final who?) ...[
          const SizedBox(height: S.x1),
          Text(who, style: F.dText.copyWith(color: DC.ink2)),
        ],
        const SizedBox(height: S.x2),
      ],

      _NightCard(
        d: d,
        night: night,
        device: staged != null,
        picked: _picked,
        onPick: (s) => setState(() => _picked = _picked == s ? null : s),
      ),
      ..._windowStatus(c),
      ..._napsButton(c, d),
      const SizedBox(height: S.x4 + S.hair + S.hair),
      _HoursVsNeededCard(d: d),
      const SizedBox(height: S.x4 + S.hair + S.hair),
      _ConsistencyCard(d: d),
      const SizedBox(height: S.x4 + S.hair + S.hair),
      _EfficiencyCard(d: d, night: night),
      const SizedBox(height: S.x4 + S.hair + S.hair),
      _StressCard(d: d, stress: _stress),
      const SizedBox(height: S.x12 + S.hair),
      dialHeading('Weekly Trends'),
      const SizedBox(height: S.x8 + S.half),
      _SleepWeek(d: d, stress: _stress),
    ]);
  }

  /// The door to the naps screen — only on a day that has naps.
  List<Widget> _napsButton(BuildContext c, SleepData d) {
    final day = d.day;
    if (day == null) return const [];
    final naps =
        (d.timeline['naps'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (naps.isEmpty) return const [];
    return [
      const SizedBox(height: S.x4),
      for (final nap in naps)
        Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: Pressable(
            onTap: _saving || _loading
                ? null
                : () async {
                    final changed = await Navigator.of(c).push<bool>(
                      MaterialPageRoute<bool>(
                          builder: (_) => NapDetailScreen(nap: nap, day: day)),
                    );
                    if (changed == true && mounted) _load();
                  },
            semanticLabel: 'View nap details',
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: kDialPad, vertical: S.x3),
              decoration: dialCard(),
              child: Row(children: [
                const Icon(LucideIcons.sun, size: I.sm, color: DC.ink2),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(
                    '${clockOfTs(((nap['start'] ?? nap['start_ts']) as num?) ?? 0)} – '
                    '${clockOfTs(((nap['end'] ?? nap['end_ts']) as num?) ?? 0)}',
                    style: F.dText.copyWith(color: DC.ink),
                  ),
                ),
                Text(clockDur(nap['duration_min'] as num?),
                    style: F.nRow.copyWith(color: DC.ink)),
                const SizedBox(width: S.x2),
                const Icon(LucideIcons.chevronRight, size: I.sm, color: DC.ink2),
              ]),
            ),
          ),
        ),
    ];
  }

  /// Progress and failure of a window correction, under the card.
  List<Widget> _windowStatus(BuildContext c) {
    final l = AppLocalizations.of(c);
    return [
      if (_saving) ...[
        const SizedBox(height: S.x2),
        Text(l?.sleepDetailReanalysing ?? 'Re-analysing the night…',
            style: F.dText.copyWith(color: DC.ink2)),
      ],
      if (!_saving && _overrideFailed != null) ...[
        const SizedBox(height: S.x3),
        StatusCard(
          l?.sleepDetailCorrectionFailedTitle ??
              'That correction has not been applied',
          _overrideFailed!,
          icon: LucideIcons.triangleAlert,
        ),
      ],
    ];
  }

  /// The Edit Time in Bed sheet, seeded with the night's own window.
  Future<void> _openEdit(BuildContext c, SleepData d) async {
    final day = d.day;
    final t0 = (d.night['onset_ts'] as num?)?.round();
    final t1 = (d.night['wake_ts'] as num?)?.round();
    if (day == null || t0 == null || t1 == null) return;
    final r = await openEditTimeInBed(
      c,
      day: day,
      start: DateTime.fromMillisecondsSinceEpoch(t0 * 1000),
      end: DateTime.fromMillisecondsSinceEpoch(t1 * 1000),
    );
    if (!mounted) return;
    switch (r) {
      case EditTimeDeleted():
        await _runOverride(
          day,
          () => context.read<AppState>().rejectSleep(day),
          applied: (n) =>
              n['sleep_source'] == 'rejected' && n['has_sleep'] != true,
        );
      case EditTimeSaved(:final start, :final end):
        await _applyWindow(day, start, end);
      case null:
        break;
    }
  }

  /// "Set one manually" on a night with nothing scored: the editor over the
  /// heart rate, seeded with eight hours ending 07:00 on [day] (or now, on a
  /// morning that has not reached 07:00 yet).
  Future<void> _addWindow(String day) async {
    final d = DateTime.tryParse(day);
    if (d == null) return;
    final now = DateTime.now();
    var end = DateTime(d.year, d.month, d.day, 7);
    if (end.isAfter(now)) {
      end = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    }
    final start =
        DateTime(end.year, end.month, end.day, end.hour - 8, end.minute);
    final r = await openWindowEditor(
      context,
      kind: WindowKind.sleep,
      title: 'Set sleep',
      start: start,
      end: end,
      save: 'Save sleep',
    );
    if (r == null || !mounted) return;
    await _applyWindow(day, r.$1, r.$2);
  }

  /// The night is stored under the day it ENDS on, whichever day the screen
  /// was showing, so a wake moved across midnight lands where the derive will
  /// look for it; a hand-set window left behind on the old day is cleared so
  /// one night is not stored twice.
  Future<void> _applyWindow(String day, DateTime newOnset, DateTime newWake) async {
    final target = dayLabelOf(newWake);
    final handSet = _source == 'manual' || _source == 'confirmed';
    final app = context.read<AppState>();
    if (target != _day) setState(() => _day = target);
    // Applied = the stored night IS the chosen window. The source alone can't
    // say: re-timing a night that is already manual leaves it unchanged, and
    // a window erased by the derive comes back as a different source.
    bool near(Object? ts, DateTime t) =>
        ts is num &&
        (ts.round() - t.millisecondsSinceEpoch ~/ 1000).abs() <= 120;
    await _runOverride(
      target,
      () async {
        if (target != day && handSet) await LocalDb.deleteSleepOverride(day);
        await app.setSleepOverride(target, newOnset, newWake);
      },
      applied: (n) =>
          n['sleep_source'] == 'manual' &&
          near(n['onset_ts'], newOnset) &&
          near(n['wake_ts'], newWake),
    );
  }

  /// Every override path is the same shape: write it, wait for the forced
  /// re-derive, then reload the screen from what the engine produced. The
  /// screen must not keep drawing the old night's numbers under a new window.
  ///
  /// [applied] reads the reloaded night and says whether the edit took.
  Future<void> _runOverride(
    String day,
    Future<void> Function() write, {
    required bool Function(Map<String, dynamic> night) applied,
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _overrideFailed = null;
    });
    String? failed;
    try {
      await write();
    } catch (e) {
      failed = '$e';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) {
      _stress = const {};
      await _load();
    }
    if (!mounted) return;
    // EVERY failure below this screen is silent: the forced re-derive catches
    // and logs its own throw, and it returns at its first line when another
    // re-analysis is already running. Both leave the write in the database and
    // the night on screen unchanged — indistinguishable from a correction that
    // worked. So the reloaded night is checked against what the edit asked for.
    if (failed == null && _d?.day != day) return;
    final took = applied(_d?.night ?? const <String, dynamic>{});
    if (failed != null || !took) {
      final l = AppLocalizations.of(context);
      setState(() => _overrideFailed = failed ??
          l?.sleepDetailReanalyseFailed ??
          'The night wasn’t re-analysed; another run was busy or it failed. Your times are saved: open Your data and tap Re-analyze everything.');
    }
  }

  String? get _source => (_d?.night['sleep_source'] as String?) ?? 'auto';

  /// Whose staging is on screen and which stages it cannot report, or null when
  /// it is ours.
  String? _stagedBy(SleepData d) {
    final id = _staging;
    if (id == null) return null;
    for (final dn in d.deviceNights) {
      if (dn['device_id'] != id) continue;
      final mins = (dn['stage_min'] as Map?) ?? const {};
      final label = (dn['label'] as String?) ?? 'Device';
      final missing = [
        if (mins['light'] == null) 'light',
        if (mins['deep'] == null) 'deep',
        if (mins['rem'] == null) 'REM',
      ];
      return missing.isEmpty
          ? 'Staged by $label.'
          : 'Staged by $label, which does not report ${missing.join(' or ')}.';
    }
    return null;
  }

  /// The selected device's night as a stage map, or null when ours is shown.
  Map<String, dynamic>? _deviceNight(SleepData d) {
    final id = _staging;
    if (id == null) return null;
    for (final dn in d.deviceNights) {
      if (dn['device_id'] == id) {
        final m = Map<String, dynamic>.from(dn);
        final mins = (m['stage_min'] as Map?) ?? const {};
        return {
          ...d.night,
          ...m,
          'awake_min': mins['wake'],
          'light_min': mins['light'],
          'deep_min': mins['deep'],
          'rem_min': mins['rem'],
        };
      }
    }
    return null;
  }
}

// ── The ring and its contributors ───────────────────────────────────────────

/// Poor below 70, sufficient 70–84, optimal 85 and over.
int _tierOf(double v, [double optimal = 85, double sufficient = 70]) =>
    v >= optimal ? 2 : (v >= sufficient ? 1 : 0);

class _SleepHero extends StatelessWidget {
  final SleepData d;
  final SleepStress? stress;
  const _SleepHero({required this.d, this.stress});

  @override
  Widget build(BuildContext c) {
    final n = d.night;
    final perf = d.performance;
    final tst = (n['duration_min'] as num?)?.toDouble();
    final need = d.lastNeedMin;
    final hvn = tst == null || need == null || need <= 0
        ? null
        : (tst / need * 100).clamp(0, 100).toDouble();
    final eff = (n['efficiency'] as num?)?.toDouble();
    final stressPct = stress?.pct;

    void trend(String id) => Navigator.of(c).push(MaterialPageRoute(
        builder: (_) => TrendViewScreen(initial: id)));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DialRing(
        fraction: perf == null ? 0 : perf / 100,
        color: C.dialSleep,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Wordmark(color: DC.ink3),
          const SizedBox(height: S.x1 + S.hair),
          dialFigure(perf, DC.ink),
          const SizedBox(height: S.x2),
          Text('SLEEP\nPERFORMANCE',
              textAlign: TextAlign.center,
              style: F.dHero.copyWith(color: DC.ink)),
          const SizedBox(height: S.x4 + S.half),
          TierBar(perf == null ? null : _tierOf(perf)),
        ]),
      ),
      const SizedBox(height: S.x6 + S.half + S.hair),
      CaretPanel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.x4 + S.hair, 0, S.x4 + S.hair, 0),
          child: Column(children: [
            _ContributorRow(
                mark: StatMark.hoursNeeded,
                label: 'Hours vs. needed',
                value: hvn,
                tier: hvn == null ? null : _tierOf(hvn),
                onTap: () => trend('hvn_pct')),
            const _Hair(),
            _ContributorRow(
                mark: StatMark.consistency,
                label: 'Sleep consistency',
                value: d.consistency,
                tier: d.consistency == null
                    ? null
                    : _tierOf(d.consistency!, 80, 70),
                onTap: () => trend('consistency')),
            const _Hair(),
            _ContributorRow(
                mark: StatMark.efficiency,
                label: 'Sleep efficiency',
                value: eff == null ? null : eff * 100,
                tier: eff == null ? null : _tierOf(eff * 100, 90, 80),
                onTap: () => trend('efficiency')),
            const _Hair(),
            _ContributorRow(
                mark: StatMark.sleepStress,
                label: 'High sleep stress',
                value: stressPct,
                tier: stressPct == null
                    ? null
                    : (stressPct < 1 ? 2 : (stressPct <= 5 ? 1 : 0)),
                onTap: () => Navigator.of(c).push(MaterialPageRoute(
                    builder: (_) => const StressMonitorScreen()))),
            const SizedBox(height: S.x3 + S.half),
            Container(
              height: S.x8,
              padding: const EdgeInsets.symmetric(horizontal: S.x3 + S.half),
              alignment: Alignment.centerLeft,
              decoration:
                  const BoxDecoration(color: DC.well, borderRadius: R.rMd),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final (t, label) in const [
                  (0, 'Poor'),
                  (1, 'Sufficient'),
                  (2, 'Optimal'),
                ]) ...[
                  Container(
                    width: S.x3 + S.hair,
                    height: S.x1,
                    decoration: BoxDecoration(
                      color: TierBar.colorOf(t),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(S.hair)),
                    ),
                  ),
                  const SizedBox(width: S.x2 + S.half),
                  Text(label, style: F.dLegend.copyWith(color: DC.ink2)),
                  const SizedBox(width: S.x5),
                ],
              ]),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _Hair extends StatelessWidget {
  const _Hair();
  @override
  Widget build(BuildContext c) =>
      const Divider(height: S.hair, thickness: S.hair, color: DC.line);
}

class _ContributorRow extends StatelessWidget {
  final StatMark mark;
  final String label;
  final double? value;
  final int? tier;
  final VoidCallback onTap;
  const _ContributorRow({
    required this.mark,
    required this.label,
    required this.value,
    required this.tier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    return Pressable(
      onTap: onTap,
      semanticLabel:
          '$label ${value == null ? 'not measured' : '${value!.round()}%'}',
      child: SizedBox(
        height: S.x12 + S.half,
        child: Row(children: [
          const SizedBox(width: S.x1 + S.hair),
          StatIcon(mark, color: DC.ink2, size: S.x5 + S.hair),
          const SizedBox(width: S.x2 + S.hair + S.hair),
          Expanded(
            flex: 3,
            child: Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.dLabel.copyWith(color: DC.ink)),
          ),
          // Aligned right so the bar sits against the value: a loose Flexible
          // alone leaves its unused share at the row's end.
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, child: TierBar(tier)),
            ),
          ),
          const SizedBox(width: S.x3),
          Padding(
            padding: const EdgeInsets.only(top: S.half),
            child: Text(value == null ? '--' : '${value!.round()}%',
                style: F.nRow.copyWith(color: DC.ink)),
          ),
          const SizedBox(width: S.x2 + S.hair),
        ]),
      ),
    );
  }
}

// ── Last night: the heart rate and the stages ───────────────────────────────

const _stageOrder = [
  SleepStage.awake,
  SleepStage.light,
  SleepStage.deep,
  SleepStage.rem,
];

Color _stageColor(SleepStage s) => switch (s) {
      SleepStage.awake => DC.stageAwake,
      SleepStage.light => DC.stageLight,
      SleepStage.deep => DC.stageDeep,
      SleepStage.rem => DC.stageRem,
    };

String _stageLabel(SleepStage s) => switch (s) {
      SleepStage.awake => 'AWAKE',
      SleepStage.light => 'LIGHT',
      SleepStage.deep => 'SWS (DEEP)',
      SleepStage.rem => 'REM',
    };

num? _stageMinutes(Map<String, dynamic> n, SleepStage s) => switch (s) {
      SleepStage.awake => n['awake_min'] as num?,
      SleepStage.light => n['light_min'] as num?,
      SleepStage.deep => n['deep_min'] as num?,
      SleepStage.rem => n['rem_min'] as num?,
    };

class _NightCard extends StatefulWidget {
  final SleepData d;
  final Map<String, dynamic> night;
  final bool device;
  final SleepStage? picked;
  final ValueChanged<SleepStage> onPick;
  const _NightCard({
    required this.d,
    required this.night,
    required this.device,
    required this.picked,
    required this.onPick,
  });

  @override
  State<_NightCard> createState() => _NightCardState();
}

class _NightCardState extends State<_NightCard> {
  /// 0…1 across the night under the finger, or null.
  double? _scrub;

  @override
  Widget build(BuildContext c) {
    final d = widget.d;
    final n = widget.night;
    final tst = (n['duration_min'] as num?)?.toDouble();
    final t0 = (n['onset_ts'] as num?)?.toDouble();
    final t1 = (n['wake_ts'] as num?)?.toDouble();
    final v = d.vitals;
    final avg = d.tstHistory.isEmpty
        ? null
        : d.tstHistory.reduce((a, b) => a + b) / d.tstHistory.length;

    // The minute under the finger, on the padded axis the chart draws.
    final span = t0 == null || t1 == null ? 0.0 : t1 - t0;
    final from = t0 == null ? 0.0 : t0 - span * .07;
    final to = t1 == null ? 1.0 : t1 + span * .07;
    ({int t, double v})? at;
    final scrub = _scrub;
    if (scrub != null && v.heart.isNotEmpty) {
      final want = from + (to - from) * scrub;
      at = v.heart.reduce((a, b) =>
          (a.t - want).abs() <= (b.t - want).abs() ? a : b);
    }

    final runs = stageRunsOf(n);
    final stages = {for (final s in _stageOrder) s: _stageMinutes(n, s)};
    final total = stages.values
        .fold<double>(0, (a, m) => a + (m?.toDouble() ?? 0));

    return Container(
      decoration: dialCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kDialPad, S.x1 + S.hair, S.x4, 0),
          child: dialCardTitle('Hours of sleep',
              trailing: const DialInfo(
                  'Hours of sleep',
                  'How long you were asleep, with your heart rate through the '
                      'night. Under it is what the night was made of, each '
                      'stage against the middle half of your own recent nights.')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kDialPad),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: S.x10 + S.half),
            child: at != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('${at.v.round()}',
                                style: F.nCard.copyWith(color: C.dialSleep)),
                            const SizedBox(width: S.x1),
                            Text('bpm',
                                style: F.dBody
                                    .copyWith(color: C.dialSleep, height: 1)),
                          ],
                        ),
                        const SizedBox(height: S.hair),
                        Text(clockOfTs(at.t),
                            style: F.nTiny.copyWith(color: DC.ink2)),
                      ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        ValueDelta(clockDur(tst),
                            style: F.nCard,
                            v: tst,
                            usual: avg),
                        const SizedBox(height: S.hair),
                        Text(clockDur(avg),
                            style: F.nTiny.copyWith(color: DC.ink2)),
                      ]),
          ),
        ),
        const SizedBox(height: S.x2 + S.hair),
        Scrubber(
          value: _scrub,
          onChanged: (x) => setState(() => _scrub = x),
          onLift: () => setState(() => _scrub = null),
          yieldToScroll: true,
          label: 'Heart rate through the night',
          describe: (x) {
            if (v.heart.isEmpty) return 'No heart rate recorded';
            final want = from + (to - from) * x;
            final p = v.heart.reduce((a, b) =>
                (a.t - want).abs() <= (b.t - want).abs() ? a : b);
            return '${clockOfTs(p.t)}, ${p.v.round()} beats per minute';
          },
          child: CustomPaint(
            size: Size(
                double.infinity, _NightPaint.heightOf(v.movement.isNotEmpty)),
            painter: _NightPaint(
              heart: v.heart,
              movement: v.movement,
              from: from,
              to: to,
              onset: t0,
              wake: t1,
              onsetLabel: clockOfTs(n['onset_ts'] as num?),
              wakeLabel: clockOfTs(n['wake_ts'] as num?),
              runs: runs,
              picked: widget.picked,
              scrub: _scrub,
              scaler: MediaQuery.textScalerOf(c),
            ),
          ),
        ),
        const SizedBox(height: S.x3),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              S.x8 - S.hair, 0, S.x6 + S.hair, 0),
          child: Row(children: [
            CustomPaint(
                size: const Size(S.x4, S.x4 + S.hair),
                painter: _TypicalKeyPaint()),
            const SizedBox(width: S.x3),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: S.x2,
                children: [
                  Text('TYPICAL RANGE',
                      style: F.dLabel.copyWith(color: DC.ink2)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('DURATION',
                          style: F.dLabel.copyWith(color: DC.ink2)),
                      const SizedBox(width: S.x2),
                      Text(clockDur(total <= 0 ? null : total),
                          style: F.nRow.copyWith(color: DC.ink)),
                    ]),
                  ),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: S.x6 + S.hair),
        for (final s in _stageOrder)
          _StageRow(
            stage: s,
            minutes: stages[s]?.toDouble(),
            share: total <= 0 ? null : (stages[s]?.toDouble() ?? 0) / total,
            runs: [
              for (final r in runs)
                if (r.stage == s) r,
            ],
            typical: widget.device ? null : v.typical[s],
            picked: widget.picked,
            onPick: () => widget.onPick(s),
          ),
        const SizedBox(height: S.x2 + S.half),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: S.x3 + S.hair),
          child: _Hair(),
        ),
        const SizedBox(height: S.x5),
        _KeyedRow(
          swatch: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [DC.stageDeep, DC.stageRem]),
          label: 'Restorative sleep',
          trailing: _restorative(d, n),
        ),
        const SizedBox(height: S.x6 + S.x1),
        _KeyedRow(
          swatch: const LinearGradient(
              colors: [DC.stageAwake, DC.stageAwake]),
          label: 'Sleep latency',
          // Only on a window the user set themselves: an auto window's onset is
          // the stager's guess, so nothing can be measured back from it.
          trailing: Text(
              clockDur(const {'manual', 'confirmed'}.contains(n['sleep_source'])
                  ? d.solMin
                  : null),
              style: F.nRow.copyWith(color: DC.ink)),
        ),
        const SizedBox(height: S.x6 + S.hair),
      ]),
    );
  }

  Widget _restorative(SleepData d, Map<String, dynamic> n) {
    final deep = (n['deep_min'] as num?)?.toDouble();
    final rem = (n['rem_min'] as num?)?.toDouble();
    final v = deep == null || rem == null ? null : deep + rem;
    final avg = d.vitals.priorRestorative(d.day);
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      ValueDelta(clockDur(v), style: F.nRow, v: v, usual: avg),
      if (avg != null) ...[
        const SizedBox(height: S.x1),
        Text(clockDur(avg), style: F.nTiny.copyWith(color: DC.ink2)),
      ],
    ]);
  }
}

/// A row with a small square key, its capitals, and a figure on the right.
class _KeyedRow extends StatelessWidget {
  final Gradient swatch;
  final String label;
  final Widget trailing;
  const _KeyedRow(
      {required this.swatch, required this.label, required this.trailing});

  @override
  Widget build(BuildContext c) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: S.x5 + S.hair + S.hair),
      child: Row(children: [
        Container(
          width: S.x3 + S.hair,
          height: S.x3 + S.hair,
          decoration: BoxDecoration(
              gradient: swatch,
              borderRadius: const BorderRadius.all(Radius.circular(S.half))),
        ),
        const SizedBox(width: S.x2 + S.hair),
        Expanded(
          child: Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.dLabel.copyWith(color: DC.ink)),
        ),
        // Flush right: a Flexible alone left the figure mid-row.
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
          ),
        ),
      ]),
    );
  }
}

/// The key beside TYPICAL RANGE: a hatched square, dashed down its sides.
class _TypicalKeyPaint extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = DC.typical);
    final dash = Paint()
      ..color = DC.ink2
      ..strokeWidth = S.hair;
    for (final x in [0.5, size.width - .5]) {
      for (var y = 0.0; y < size.height; y += S.x1) {
        canvas.drawLine(Offset(x, y), Offset(x, y + S.half), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_TypicalKeyPaint old) => false;
}

/// The heart rate over the night, the full width of the card: 170 to 30 in
/// steps of 20, dashed down the left and right at the onset and the wake.
class _NightPaint extends CustomPainter {
  static const _top = S.x2;
  static const _step = S.x6 - S.hair;
  static const _plotFoot = _top + _step * 7;
  static const _laneTop = _plotFoot + S.x1;
  static const _laneH = S.x8;

  /// Where the dashes end: under the movement lane when there is one.
  static double footOf(bool lane) =>
      lane ? _laneTop + _laneH + S.hair : _plotFoot + S.x1 - S.hair;
  static double heightOf(bool lane) => footOf(lane) + S.x6 + S.x1 + S.hair;

  final List<({int t, double v})> heart;
  final List<MovePoint> movement;
  final double from, to;
  final double? onset, wake;
  final String onsetLabel, wakeLabel;
  final List<StageRun> runs;
  final SleepStage? picked;
  final double? scrub;
  final TextScaler scaler;
  _NightPaint({
    required this.heart,
    required this.movement,
    required this.from,
    required this.to,
    required this.onset,
    required this.wake,
    required this.onsetLabel,
    required this.wakeLabel,
    required this.runs,
    required this.picked,
    required this.scrub,
    required this.scaler,
  });

  TextPainter _tp(String s, TextStyle st) => TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
      textScaler: scaler)
    ..layout();

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    final len = (b - a).distance;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += S.x1 + S.hair) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + S.half, len), p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final lane = movement.isNotEmpty;
    final dashFoot = footOf(lane);
    double xOf(num t) => w * (t - from) / (to - from);
    double yOf(double bpm) =>
        _top + _step * 7 * (1 - ((bpm - 30) / 140).clamp(0.0, 1.0));

    // The ground darkens toward the foot of the chart, then fades out again
    // under it, into the stages below.
    final ground = Offset.zero & size;
    canvas.drawRect(
        ground,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [_plotFoot * .45 / size.height, dashFoot / size.height, 1],
            colors: const [Color(0x00000000), DC.shade, Color(0x00000000)],
          ).createShader(ground));

    final lit = picked;
    final dimmed = lit != null || scrub != null;

    // The picked stage's stretches, shaded from the line down to the foot:
    // never above the heart rate itself.
    if (lit != null && onset != null && wake != null) {
      final c = _stageColor(lit);
      final span = wake! - onset!;
      for (final r in runs) {
        if (r.stage != lit) continue;
        final t0 = onset! + span * r.from, t1 = onset! + span * r.to;
        final pts = [
          for (final e in heart)
            if (e.t >= t0 && e.t <= t1) Offset(xOf(e.t), yOf(e.v)),
        ];
        if (pts.isEmpty) continue;
        final area = Path()
          ..moveTo(xOf(t0), dashFoot)
          ..lineTo(xOf(t0), pts.first.dy);
        for (final o in pts) {
          area.lineTo(o.dx, o.dy);
        }
        area
          ..lineTo(xOf(t1), pts.last.dy)
          ..lineTo(xOf(t1), dashFoot)
          ..close();
        final box = area.getBounds();
        canvas.drawPath(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.withValues(alpha: .3), c.withValues(alpha: .05)],
              ).createShader(box));
      }
    }

    // What lies beyond the onset and wake lines is faded, so the bpm axis
    // reads through it and the night is plainly the part being looked at.
    void windowed(VoidCallback draw) {
      if (onset == null || wake == null) return draw();
      paintWindowed(canvas, Rect.fromLTWH(0, 0, w, dashFoot), xOf(onset!),
          xOf(wake!), draw);
    }

    // Movement, on the same clock, under the 30 line.
    if (lane) {
      windowed(() => paintMovement(
          canvas,
          Rect.fromLTRB(0, _laneTop, w, _laneTop + _laneH),
          movement,
          xOf,
          DC.ink.withValues(alpha: dimmed ? .2 : .4)));
      final tp = _tp('MOVEMENT',
          F.num(F.over).copyWith(color: DC.ink3, fontWeight: FontWeight.w600));
      tp.paint(canvas, Offset((w - tp.width) / 2, _laneTop));
      tp.dispose();
    }

    // The line, broken where nothing was recorded.
    Path pathOf(bool Function(int t) keep) {
      final p = Path();
      int? last;
      for (final e in heart) {
        if (!keep(e.t)) {
          last = null;
          continue;
        }
        final o = Offset(xOf(e.t.toDouble()), yOf(e.v));
        if (last == null || e.t - last > 300) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
        last = e.t;
      }
      return p;
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = S.hair + .2
      ..strokeJoin = StrokeJoin.round;
    windowed(() => canvas.drawPath(pathOf((_) => true),
        stroke..color = dimmed ? DC.dim : C.dialSleep));
    if (lit != null && onset != null && wake != null) {
      final span = wake! - onset!;
      bool inRun(int t) {
        final f = (t - onset!) / span;
        return runs.any((r) => r.stage == lit && f >= r.from && f <= r.to);
      }
      canvas.drawPath(pathOf(inRun), stroke..color = _stageColor(lit));
    }

    // The bpm axis.
    final tick = F.nTiny.copyWith(color: DC.ink2);
    for (var i = 0; i < 8; i++) {
      final tp = _tp('${170 - i * 20}', tick);
      tp.paint(
          canvas,
          Offset(S.x5 - S.hair - tp.width,
              _top + _step * i - tp.height / 2));
      tp.dispose();
    }

    // Onset and wake.
    final dash = Paint()
      ..color = DC.ink
      ..strokeWidth = S.hair;
    final dot = Paint()..color = DC.ink;
    final labelStyle = F.nTiny.copyWith(color: DC.ink);
    if (onset != null) {
      final x = xOf(onset!);
      _dashed(canvas, Offset(x, 0), Offset(x, dashFoot), dash);
      canvas.drawCircle(Offset(x, dashFoot), S.half, dot);
      final tp = _tp(onsetLabel, labelStyle);
      tp.paint(canvas, Offset(x + S.x1, dashFoot + S.x2 + S.hair));
      tp.dispose();
    }
    if (wake != null) {
      final x = xOf(wake!);
      _dashed(canvas, Offset(x, 0), Offset(x, dashFoot), dash);
      canvas.drawCircle(Offset(x, dashFoot), S.half, dot);
      final tp = _tp(wakeLabel, labelStyle);
      tp.paint(canvas, Offset(x - tp.width, dashFoot + S.x2 + S.hair));
      tp.dispose();
    }

    // The finger.
    final s = scrub;
    if (s != null && heart.isNotEmpty) {
      final want = from + (to - from) * s;
      final p = heart.reduce(
          (a, b) => (a.t - want).abs() <= (b.t - want).abs() ? a : b);
      final x = xOf(p.t.toDouble());
      _dashed(canvas, Offset(x, -S.half), Offset(x, dashFoot + S.x1), dash);
      final o = Offset(x, yOf(p.v));
      canvas.drawCircle(o, S.x1 + S.hair + S.hair, Paint()..color = DC.well);
      canvas.drawCircle(o, S.x1, Paint()..color = C.dialSleep);
    }
  }

  @override
  bool shouldRepaint(_NightPaint old) => true;
}

/// One stage: the round button, its name and share, its figure, and its bar.
class _StageRow extends StatelessWidget {
  final SleepStage stage;
  final double? minutes, share;
  final List<StageRun> runs;
  final (double, double)? typical;
  final SleepStage? picked;
  final VoidCallback onPick;
  const _StageRow({
    required this.stage,
    required this.minutes,
    required this.share,
    required this.runs,
    required this.typical,
    required this.picked,
    required this.onPick,
  });

  @override
  Widget build(BuildContext c) {
    final me = picked == stage;
    final color = _stageColor(stage);
    return Pressable(
      onTap: runs.isEmpty ? null : onPick,
      semanticLabel:
          '${_stageLabel(stage)} ${clockDur(minutes)}, show on the chart',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x6 + S.hair, 0, S.x6 + S.hair, S.x6 - S.hair),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: S.x6 + S.half + S.hair,
            child: Row(children: [
              _Radio(me),
              const SizedBox(width: S.x2 - S.hair),
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(_stageLabel(stage),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.dLabel.copyWith(color: DC.ink)),
                  ),
                  const SizedBox(width: S.x2),
                  Flexible(
                    child: Text(share == null ? '' : '${(share! * 100).round()}%',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: F.nTiny.copyWith(
                            color: picked == null || me ? color : DC.ink2)),
                  ),
                ]),
              ),
              Text(clockDur(minutes), style: F.nRow.copyWith(color: DC.ink)),
            ]),
          ),
          const SizedBox(height: S.x2),
          TweenAnimationBuilder<double>(
            tween: Tween(end: picked == null ? 0 : 1),
            duration: motion(c, Motion.base),
            curve: Curves.easeInOut,
            builder: (_, t, _) => CustomPaint(
              size: const Size(double.infinity, S.x4 + S.half),
              painter: _StageBarPaint(
                share: share ?? 0,
                runs: runs,
                color: picked == null || me ? color : DC.stageAwake,
                t: t,
                typical: typical,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool on;
  const _Radio(this.on);

  @override
  Widget build(BuildContext c) {
    return Container(
      width: S.x6 + S.half + S.hair,
      height: S.x6 + S.half + S.hair,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? DC.ink : const Color(0x00000000),
        border: Border.all(color: DC.ink, width: S.hair + .2),
      ),
      child: on
          ? Center(
              child: Container(
                width: S.x2,
                height: S.x2,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: DC.well),
              ),
            )
          : null,
    );
  }
}

/// A stage's bar. At rest its stretches are gathered into one solid bar, its
/// share of the night, with the typical range marked; picking a stage spreads
/// them out to where in the night they happened.
class _StageBarPaint extends CustomPainter {
  final double share;
  final List<StageRun> runs;
  final Color color;
  final double t;
  final (double, double)? typical;
  _StageBarPaint({
    required this.share,
    required this.runs,
    required this.color,
    required this.t,
    required this.typical,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    paintHatch(canvas, Offset.zero & size);
    final range = typical;
    final a = (1 - t).clamp(0.0, 1.0);
    final box = range == null || t >= 1
        ? null
        : Rect.fromLTRB(w * range.$1, -S.x1,
            math.max(w * range.$2, w * range.$1 + S.x1), size.height + S.x1);
    final fill = Paint()..color = color;
    final barW = w * share.clamp(0.0, 1.0);
    if (t <= 0 || runs.isEmpty) {
      if (barW > 0) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(0, 0, math.max(barW, S.x1), size.height),
                const Radius.circular(S.x1)),
            fill);
      }
    } else {
      final sum = runs.fold<double>(0, (a, r) => a + r.to - r.from);
      var stacked = 0.0;
      for (final r in runs) {
        final len = sum <= 0 ? 0.0 : (r.to - r.from) / sum * barW;
        final x0 = stacked + (r.from * w - stacked) * t;
        final x1 = stacked + len + (r.to * w - (stacked + len)) * t;
        stacked += len;
        canvas.drawRect(
            Rect.fromLTRB(x0, 0, math.max(x1, x0 + S.hair), size.height), fill);
      }
    }
    // The typical range lies over the bar, veiling what it covers.
    if (box != null) {
      canvas.drawRect(
          box, Paint()..color = DC.typical.withValues(alpha: DC.typical.a * a));
      final dash = Paint()
        ..color = DC.ink2.withValues(alpha: a)
        ..strokeWidth = S.hair;
      for (final x in [box.left, box.right]) {
        for (var y = box.top; y < box.bottom; y += S.x1) {
          canvas.drawLine(Offset(x, y), Offset(x, y + S.half), dash);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_StageBarPaint old) =>
      old.t != t ||
      old.color != color ||
      old.share != share ||
      old.typical != typical ||
      !identical(old.runs, runs);
}

// ── Hours vs. Needed ────────────────────────────────────────────────────────

/// A card's headline: the figure and triangle over the 30-day average.
class _CardHead extends StatelessWidget {
  final String title, about;
  final String value;
  final String? average;
  final double? v, usual;
  final bool higherBetter;
  final Widget? beside;
  const _CardHead({
    required this.title,
    required this.about,
    required this.value,
    required this.average,
    required this.v,
    required this.usual,
    this.higherBetter = true,
    this.beside,
  });

  @override
  Widget build(BuildContext c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kDialPad, S.x1 + S.hair, S.x4, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        dialCardTitle(title, trailing: DialInfo(title, about)),
        ValueDelta(value,
            style: F.nCard, v: v, usual: usual, higherBetter: higherBetter),
        const SizedBox(height: S.hair),
        Row(children: [
          Text(average ?? '', style: F.nTiny.copyWith(color: DC.ink2)),
          const Spacer(),
          if (beside case final b?)
            Flexible(
              flex: 8,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: b),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _HoursVsNeededCard extends StatelessWidget {
  final SleepData d;
  const _HoursVsNeededCard({required this.d});

  @override
  Widget build(BuildContext c) {
    final tst = (d.night['duration_min'] as num?)?.toDouble();
    final need = d.lastNeedMin;
    final hvn = tst == null || need == null || need <= 0
        ? null
        : (tst / need * 100);
    final avg = d.vitals.prior(d.vitals.hvn, d.day);
    final parts = d.vitals.needParts;
    return Container(
      decoration: dialCard(),
      padding: const EdgeInsets.only(bottom: S.x4 - S.hair),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardHead(
          title: 'Hours vs. needed',
          about:
              'How long you slept against how long you needed, which is your '
              'baseline plus what yesterday’s strain added plus part of the '
              'night before’s shortfall, less any naps.',
          value: hvn == null ? '--' : '${hvn.round()}%',
          average: avg == null ? null : '${avg.round()}%',
          v: hvn,
          usual: avg,
        ),
        const SizedBox(height: S.x3 - S.hair),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x5 + S.x1 - S.hair),
          child: LayoutBuilder(builder: (c, box) {
            final w = box.maxWidth;
            final scale = need == null || need <= 0 ? 0.0 : w / need;
            final sleepW = math.min(w, (tst ?? 0) * scale);
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: sleepW, maxWidth: w),
                      child: IntrinsicWidth(
                        child: Row(children: [
                          Expanded(
                            child: Text('HOURS OF SLEEP',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: F.dLabel.copyWith(color: DC.ink2)),
                          ),
                          const SizedBox(width: S.x2),
                          Text(clockDur(tst),
                              style: F.nRow.copyWith(color: DC.ink)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x1 + S.hair),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: sleepW,
                      height: S.x4 + S.half,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(S.half)),
                        gradient: LinearGradient(colors: [
                          C.dialSleep.withValues(alpha: .25),
                          C.dialSleep.withValues(alpha: .8),
                          C.dialSleep,
                        ], stops: const [0, .6, 1]),
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x3 + S.hair),
                  SizedBox(
                    height: S.x4 + S.half,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(S.half)),
                      child: parts == null
                        ? Container(
                            decoration: const BoxDecoration(
                                gradient: LinearGradient(colors: [
                            DC.hatchBase,
                            DC.needMin,
                          ])))
                        : Row(children: [
                            Expanded(
                              flex: math.max(1, parts.baseline.round()),
                              child: Container(
                                decoration: const BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                  DC.hatchBase,
                                  DC.needMin,
                                ])),
                              ),
                            ),
                            if (parts.strain >= 1)
                              Expanded(
                                flex: parts.strain.round(),
                                child: Container(color: C.dialStrain),
                              ),
                            if (parts.debt >= 1) ...[
                              const SizedBox(width: S.hair),
                              Expanded(
                                flex: parts.debt.round(),
                                child: Container(color: DC.stageAwake),
                              ),
                            ],
                          ]),
                    ),
                  ),
                  const SizedBox(height: S.x2),
                  Row(children: [
                    Expanded(
                      child: Text('SLEEP NEEDED',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: F.dLabel.copyWith(color: DC.ink2)),
                    ),
                    Text(clockDur(need), style: F.nRow.copyWith(color: DC.ink)),
                  ]),
                ]);
          }),
        ),
        const SizedBox(height: S.x3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x3 + S.hair),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: S.x3 + S.hair, vertical: S.x2 + S.hair),
            decoration:
                const BoxDecoration(color: DC.inset, borderRadius: R.rLg),
            child: Column(children: [
              _NeedRow(DC.needMin, 'Healthy Minimum',
                  clockDur(parts?.baseline), false),
              _NeedRow(C.dialStrain, 'Recent Strain',
                  parts == null ? '--' : '+${clockDur(parts.strain)}', true),
              _NeedRow(DC.stageAwake, 'Sleep Debt',
                  parts == null ? '--' : '+${clockDur(parts.debt)}', true),
              if (parts != null && parts.nap >= 1)
                _NeedRow(DC.stageLight, 'Naps', '-${clockDur(parts.nap)}', true),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _NeedRow extends StatelessWidget {
  final Color color;
  final String label, value;
  final bool bold;
  const _NeedRow(this.color, this.label, this.value, this.bold);

  @override
  Widget build(BuildContext c) {
    return SizedBox(
      height: S.x6 + S.half,
      child: Row(children: [
        Container(
          width: S.x3 + S.hair,
          height: S.x3 + S.hair,
          decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.all(Radius.circular(S.half))),
        ),
        const SizedBox(width: S.x2 + S.hair + S.hair),
        Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.dText.copyWith(color: bold ? DC.ink : DC.ink2))),
        Text(value,
            style: bold
                ? F.nSmall.copyWith(color: DC.ink)
                : F.nSmall.copyWith(color: DC.ink2)),
      ]),
    );
  }
}

// ── Sleep Consistency ───────────────────────────────────────────────────────

class _ConsistencyCard extends StatelessWidget {
  final SleepData d;
  const _ConsistencyCard({required this.d});

  @override
  Widget build(BuildContext c) {
    final v = d.vitals;
    final avg = v.prior(v.consistency, d.day);
    final day = d.day;
    final days = day == null
        ? const <String>[]
        : [for (var i = 4; i >= 0; i--) shiftDay(day, -i)];
    return Container(
      decoration: dialCard(),
      padding: const EdgeInsets.only(bottom: S.x8 - S.hair),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardHead(
          title: 'Sleep consistency',
          about:
              'How closely last night’s bed and wake times match the nights '
              'before it. The dashed lines are the average of the three nights '
              'before each one.',
          value: d.consistency == null ? '--' : '${d.consistency!.round()}%',
          average: avg == null ? null : '${avg.round()}%',
          v: d.consistency,
          usual: avg,
          beside: Row(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(
                size: const Size(S.x5 + S.hair, S.hair),
                painter: _DashKeyPaint()),
            const SizedBox(width: S.x1 + S.hair),
            Text('Optimal Bed/Waketime',
                style: F.dLegend.copyWith(color: DC.ink2)),
            const SizedBox(width: S.x3 + S.hair),
          ]),
        ),
        const SizedBox(height: S.x1 + S.hair),
        CustomPaint(
          size: const Size(double.infinity, _ConsistencyPaint.height),
          painter: _ConsistencyPaint(
            days: days,
            spans: v.spans,
            names: [
              for (final s in days)
                weekdayShortName(DateTime.parse(s).weekday,
                    AppLocalizations.of(c)),
            ],
            onset: clockOfTs(d.night['onset_ts'] as num?),
            wake: clockOfTs(d.night['wake_ts'] as num?),
            scaler: MediaQuery.textScalerOf(c),
          ),
        ),
      ]),
    );
  }
}

class _DashKeyPaint extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = DC.ink2
      ..strokeWidth = S.hair + S.hair;
    for (var x = 0.0; x < size.width; x += S.x1 + S.hair) {
      canvas.drawLine(Offset(x, 0), Offset(x + S.x1 - S.hair, 0), p);
    }
  }

  @override
  bool shouldRepaint(_DashKeyPaint old) => false;
}

class _ConsistencyPaint extends CustomPainter {
  static const height = S.x16 * 3 - S.x4;
  static const _step = S.x8 + S.x1 + S.half + S.hair;
  static const _top = S.x2;

  final List<String> days;
  final Map<String, ({double bed, double wake})> spans;
  final List<String> names;
  final String onset, wake;
  final TextScaler scaler;
  _ConsistencyPaint({
    required this.days,
    required this.spans,
    required this.names,
    required this.onset,
    required this.wake,
    required this.scaler,
  });

  void _text(Canvas canvas, String s, TextStyle st, Offset centre) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        textScaler: scaler)
      ..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  /// A night's optimal bed and wake: the mean of the three nights before it.
  ({double bed, double wake})? _optimal(String day) {
    final prior = [
      for (var i = 1; i <= 3; i++) ?spans[shiftDay(day, -i)],
    ];
    if (prior.isEmpty) return null;
    return (
      bed: prior.map((s) => s.bed).reduce((a, b) => a + b) / prior.length,
      wake: prior.map((s) => s.wake).reduce((a, b) => a + b) / prior.length,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 19:00 to 11:00 the next morning, in steps of four hours. In minutes after
    // noon; the range grows a step for a night that falls outside it.
    var lo = 420.0, hi = 1380.0;
    for (final d in days) {
      final s = spans[d];
      if (s == null) continue;
      // Last night carries its clocks over and under the bar: keep them off
      // the top line and the day names.
      final room = d == days.last ? 100 : 0;
      while (s.bed - room < lo) {
        lo -= 240;
      }
      while (s.wake + room > hi) {
        hi += 240;
      }
    }
    final rows = ((hi - lo) / 240).round();
    final unit = _step * 4 / (hi - lo) * (rows / 4) * (4 / rows);
    double yOf(double m) => _top + (m - lo) * unit;
    const left = S.x12 + S.x1 + S.hair;
    final right = size.width - S.x5 - S.half;

    final grid = Paint()
      ..color = DC.grid
      ..strokeWidth = S.hair;
    final axis = F.nTiny.copyWith(color: DC.ink2);
    for (var i = 0; i <= rows; i++) {
      final m = lo + 240 * i;
      final y = yOf(m);
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
      final h = ((m + 720) ~/ 60) % 24;
      _text(canvas, '${h.toString().padLeft(2, '0')}:00', axis,
          Offset(S.x8 - S.x1 + S.hair, y));
    }

    const firstX = S.x16 + S.x10;
    final dx = days.length < 2
        ? 0.0
        : (right - S.x12 - S.hair - S.hair - firstX) / (days.length - 1);
    double xOf(int i) => firstX + dx * i;

    // The optimal bed and wake, through the nights.
    final dash = Paint()
      ..color = DC.ink3
      ..strokeWidth = S.hair + S.hair
      ..style = PaintingStyle.stroke;
    for (final pick in [
      (({double bed, double wake}) o) => o.bed,
      (({double bed, double wake}) o) => o.wake,
    ]) {
      final pts = <Offset>[];
      for (var i = 0; i < days.length; i++) {
        final o = _optimal(days[i]);
        if (o != null) pts.add(Offset(xOf(i), yOf(pick(o))));
      }
      if (pts.length < 2) continue;
      // Smoothed through the midpoints of the nights.
      final line = Path()
        ..moveTo(pts.first.dx - S.x8 - S.x1 - S.half - S.hair, pts.first.dy)
        ..lineTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1], b = pts[i];
        final mid = (a.dx + b.dx) / 2;
        line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
      }
      line.lineTo(pts.last.dx + S.x8 + S.x1 + S.half + S.hair, pts.last.dy);
      for (final m in line.computeMetrics()) {
        for (var a = 0.0; a < m.length; a += S.x1 + S.hair) {
          canvas.drawPath(m.extractPath(a, a + S.x1 - S.hair), dash);
        }
      }
    }

    for (var i = 0; i < days.length; i++) {
      final me = i == days.length - 1;
      final s = spans[days[i]];
      final x = xOf(i);
      if (s != null) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(x - S.x1 - S.x1 / 2, yOf(s.bed),
                    x + S.x1 + S.x1 / 2, yOf(s.wake)),
                const Radius.circular(S.hair + S.hair)),
            Paint()..color = me ? C.dialSleep : DC.pastBar);
        if (me) {
          final lab = F.nTiny.copyWith(color: C.dialSleep);
          _text(canvas, onset, lab, Offset(x, yOf(s.bed) - S.x2 - S.hair));
          _text(canvas, wake, lab, Offset(x, yOf(s.wake) + S.x2 + S.hair));
        }
      }
      _text(
          canvas,
          names[i],
          F.dTiny.copyWith(
              color: me ? DC.ink : DC.ink3,
              fontWeight: me ? FontWeight.w700 : FontWeight.w500),
          Offset(x, yOf(hi) + S.x3));
    }
  }

  @override
  bool shouldRepaint(_ConsistencyPaint old) => true;
}

// ── Sleep Efficiency ────────────────────────────────────────────────────────

class _EfficiencyCard extends StatelessWidget {
  final SleepData d;
  final Map<String, dynamic> night;
  const _EfficiencyCard({required this.d, required this.night});

  @override
  Widget build(BuildContext c) {
    final eff = (night['efficiency'] as num?)?.toDouble();
    final pct = eff == null ? null : eff * 100;
    final avg = d.vitals.prior(d.vitals.eff, d.day);
    final runs = stageRunsOf(night);
    final awake = [
      for (final r in runs)
        if (r.stage == SleepStage.awake) r,
    ];
    // Whatever stage it was: the stretches between wakings, as one.
    final asleep = <StageRun>[];
    for (final r in runs) {
      if (r.stage == SleepStage.awake) continue;
      if (asleep.isNotEmpty && asleep.last.to >= r.from) {
        final last = asleep.removeLast();
        asleep.add((stage: last.stage, from: last.from, to: r.to));
      } else {
        asleep.add(r);
      }
    }
    return Container(
      decoration: dialCard(),
      padding: const EdgeInsets.only(bottom: S.x6 + S.x1),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardHead(
          title: 'Sleep efficiency',
          about: 'How much of your time in bed you were actually asleep.',
          value: pct == null ? '--' : '${pct.round()}%',
          average: avg == null ? null : '${avg.round()}%',
          v: pct,
          usual: avg,
        ),
        const SizedBox(height: S.x3 - S.hair),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x5 + S.x1 - S.hair),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text('ASLEEP',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.dLabel.copyWith(color: DC.ink2))),
              Text(clockDur(night['duration_min'] as num?),
                  style: F.nRow.copyWith(color: DC.ink)),
            ]),
            const SizedBox(height: S.x1 + S.hair),
            _Raster(asleep, C.dialSleep),
            const SizedBox(height: S.x3 + S.hair),
            _Raster(awake, DC.stageAwake),
            const SizedBox(height: S.x1 + S.half),
            Row(children: [
              Expanded(
                  child: Text('AWAKE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.dLabel.copyWith(color: DC.ink2))),
              Text(clockDur(night['awake_min'] as num?),
                  style: F.nRow.copyWith(color: DC.ink)),
            ]),
          ]),
        ),
        const SizedBox(height: S.x2 + S.hair),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: S.x3 + S.hair),
          child: _Hair(),
        ),
        const SizedBox(height: S.x5 + S.half),
        _KeyedRow(
          swatch: const LinearGradient(colors: [DC.stageAwake, DC.stageAwake]),
          label: 'Wake events',
          trailing: Text(runs.isEmpty ? '--' : '${awake.length}',
              style: F.nRow.copyWith(color: DC.ink)),
        ),
      ]),
    );
  }
}

class _Raster extends StatelessWidget {
  final List<StageRun> runs;
  final Color color;
  const _Raster(this.runs, this.color);

  @override
  Widget build(BuildContext c) {
    return ClipRRect(
      borderRadius: R.rSm,
      child: CustomPaint(
        size: const Size(double.infinity, S.x4 + S.half),
        painter: _StageBarPaint(
          share: 0,
          runs: runs,
          color: color,
          t: 1,
          typical: null,
        ),
      ),
    );
  }
}

// ── Sleep Stress ────────────────────────────────────────────────────────────

class _StressCard extends StatelessWidget {
  final SleepData d;
  final Map<String, SleepStress> stress;
  const _StressCard({required this.d, required this.stress});

  @override
  Widget build(BuildContext c) {
    final s = stress[d.day];
    final day = d.day;
    final avg = day == null
        ? null
        : _mean([
            for (var i = 1; i <= _window; i++)
              if (stress[shiftDay(day, -i)] case final x?) x.pct,
          ]);
    final t0 = (d.night['onset_ts'] as num?)?.toInt();
    final t1 = (d.night['wake_ts'] as num?)?.toInt();
    return Container(
      decoration: dialCard(),
      padding: const EdgeInsets.only(bottom: S.x8 + S.hair),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardHead(
          title: 'Sleep stress',
          about:
              'The share of the night your heart ran hotter, or your HRV lower, '
              'than is usual for you asleep. It needs a few earlier nights to '
              'compare with.',
          value: s == null ? '--' : '${s.pct.round()}%',
          average: avg == null ? null : '${avg.round()}%',
          v: s?.pct,
          usual: avg,
          higherBetter: false,
        ),
        if (s != null && s.curve.isNotEmpty && t0 != null && t1 != null)
          CustomPaint(
            size: const Size(double.infinity, _StressPaint.height),
            painter: _StressPaint(
              curve: s.curve,
              lead: s.curveLead,
              onset: t0,
              wake: t1,
              scaler: MediaQuery.textScalerOf(c),
            ),
          ),
        if (s != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x6 + S.hair, S.x5, S.x6 + S.hair, 0),
            child: Column(children: [
              _StressRow('HIGH', s.high, s.scored, C.poor),
              _StressRow('MEDIUM', s.medium, s.scored, C.optimal),
              _StressRow('LOW', s.low, s.scored, DC.line2, last: true),
            ]),
          ),
      ]),
    );
  }
}

class _StressRow extends StatelessWidget {
  final String label;
  final int minutes, scored;
  final Color color;
  final bool last;
  const _StressRow(this.label, this.minutes, this.scored, this.color,
      {this.last = false});

  @override
  Widget build(BuildContext c) {
    final share = scored <= 0 ? 0.0 : minutes / scored;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : S.x8 - S.hair),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.dLabel.copyWith(color: DC.ink)),
              ),
              const SizedBox(width: S.x2),
              Flexible(
                child: Text('${(share * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: F.nTiny.copyWith(color: color)),
              ),
            ]),
          ),
          Text(clockDur(minutes), style: F.nRow.copyWith(color: DC.ink)),
        ]),
        const SizedBox(height: S.x1 + S.hair),
        HatchBar(share, color),
      ]),
    );
  }
}

class _StressPaint extends CustomPainter {
  static const height = S.x16 * 3 + S.x3 + S.hair;
  static const _top = S.x4 + S.half;
  static const _step = S.x12 + S.half + S.hair;

  final List<double?> curve;
  final int lead, onset, wake;
  final TextScaler scaler;
  _StressPaint({
    required this.curve,
    required this.lead,
    required this.onset,
    required this.wake,
    required this.scaler,
  });

  TextPainter _tp(String s, TextStyle st) => TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
      textScaler: scaler)
    ..layout();

  @override
  void paint(Canvas canvas, Size size) {
    const left = S.x12 + S.x1 + S.hair;
    final right = size.width - S.x5 - S.half;
    const lineStart = S.x16 + S.hair;
    final lineEnd = size.width - S.x8 - S.half - S.hair;
    final n = curve.length;
    double xAt(double minute) =>
        lineStart + (lineEnd - lineStart) * (minute / math.max(1, n - 1));
    double yOf(double v) => _top + _step * (3 - v.clamp(0.0, 3.0));
    final plotBottom = _top + _step * 3;

    final grid = Paint()
      ..color = DC.grid
      ..strokeWidth = S.hair;
    final axis = F.nTiny.copyWith(color: DC.ink2);
    for (var i = 0; i <= 3; i++) {
      final y = yOf(i.toDouble());
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
      final tp = _tp(i.toDouble().toStringAsFixed(1), axis);
      tp.paint(canvas, Offset(S.x5 + S.hair, y - tp.height / 2));
      tp.dispose();
    }

    // The night itself: a lit band under a blue lid, with the moon over it.
    final bandL = xAt(lead.toDouble());
    final bandR = xAt((wake - onset) / 60 + lead);
    final band = Rect.fromLTRB(bandL, yOf(3), bandR, plotBottom);
    canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              C.dialSleep.withValues(alpha: .18),
              C.dialSleep.withValues(alpha: 0),
            ],
          ).createShader(band));
    canvas.drawLine(
        Offset(bandL, yOf(3)),
        Offset(bandR, yOf(3)),
        Paint()
          ..color = C.dialSleep
          ..strokeWidth = S.hair + S.hair);
    final mid = Offset((bandL + bandR) / 2, yOf(3) - S.x4 - S.hair);
    canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: mid, radius: S.x2)),
          Path()
            ..addOval(Rect.fromCircle(
                center: mid + const Offset(S.x1, -S.x1 + S.hair), radius: S.x2)),
        ),
        Paint()..color = DC.ink);

    // The clock under it, on the whole-hour lines.
    final startTs = onset - lead * 60;
    final endTs = startTs + (n - 1) * 60;
    final tickLine = Paint()
      ..color = DC.line
      ..strokeWidth = S.hair;
    final first = DateTime.fromMillisecondsSinceEpoch(startTs * 1000);
    final lab = F.nTiny.copyWith(color: DC.ink2);
    void bottomText(String s, double x, TextStyle st) {
      final tp = _tp(s, st);
      tp.paint(canvas, Offset(x - tp.width / 2, plotBottom + S.x2));
      tp.dispose();
    }

    bottomText(clockOfTs(startTs), lineStart - S.half, lab);
    var mark = DateTime(first.year, first.month, first.day, first.hour + 1);
    while (mark.hour % 3 != 1) {
      mark = DateTime(mark.year, mark.month, mark.day, mark.hour + 1);
    }
    while (mark.millisecondsSinceEpoch ~/ 1000 < endTs - 3600) {
      final x = xAt((mark.millisecondsSinceEpoch ~/ 1000 - startTs) / 60);
      canvas.drawLine(Offset(x, yOf(3)), Offset(x, plotBottom), tickLine);
      bottomText(clockOfTs(mark.millisecondsSinceEpoch ~/ 1000), x + S.x2, lab);
      mark = DateTime(mark.year, mark.month, mark.day, mark.hour + 3);
    }
    bottomText(clockOfTs(endTs), lineEnd - S.x3 - S.hair,
        lab.copyWith(color: DC.ink, fontWeight: FontWeight.w700));

    // The score, coloured by how high it is.
    final trace = Path();
    var pen = false;
    for (var i = 0; i < n; i++) {
      final v = curve[i];
      if (v == null) {
        pen = false;
        continue;
      }
      final o = Offset(xAt(i.toDouble()), yOf(v));
      pen ? trace.lineTo(o.dx, o.dy) : trace.moveTo(o.dx, o.dy);
      pen = true;
    }
    final plot = Rect.fromLTRB(0, yOf(3), size.width, plotBottom);
    canvas.drawPath(
        trace,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = S.hair + .4
          ..strokeJoin = StrokeJoin.round
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, .3, .5, .75, 1],
            colors: [
              C.poor,
              Color.lerp(C.poor, C.optimal, .55)!,
              C.optimal,
              Color.lerp(C.optimal, DC.line2, .6)!,
              DC.line2,
            ],
          ).createShader(plot));

    // The end of the window, dashed down to a dot.
    final dash = Paint()
      ..color = DC.ink
      ..strokeWidth = S.hair;
    for (var y = yOf(3); y < plotBottom - S.x1; y += S.x1 + S.hair) {
      canvas.drawLine(
          Offset(lineEnd, y), Offset(lineEnd, y + S.half), dash);
    }
    canvas.drawCircle(
        Offset(lineEnd, plotBottom - S.x1), S.half, Paint()..color = DC.ink);
  }

  @override
  bool shouldRepaint(_StressPaint old) => true;
}

// ── Weekly Trends ───────────────────────────────────────────────────────────

class _SleepWeek extends StatelessWidget {
  final SleepData d;
  final Map<String, SleepStress> stress;
  const _SleepWeek({required this.d, required this.stress});

  @override
  Widget build(BuildContext c) {
    final v = d.vitals;
    final week = v.week;
    if (week.isEmpty) return const SizedBox.shrink();

    List<WeekColumn> percent(Map<String, double> m) => [
          for (final day in week)
            if (m[day] case final x?)
              WeekColumn(hi: x, top: '${x.round()}%', color: C.dialSleep)
            else
              const WeekColumn(),
        ];

    final debtMax = week.fold<double>(
        0, (a, day) => math.max(a, (v.debt[day] ?? 0).clamp(0, 1e9).toDouble()));
    final restMax = week.fold<double>(0,
        (a, day) => math.max(a, (v.deep[day] ?? 0) + (v.rem[day] ?? 0)));
    final needMax = week.fold<double>(0,
        (a, day) => math.max(a, math.max(v.need[day] ?? 0, v.tst[day] ?? 0)));
    final effLine = [for (final day in week) v.eff[day]];
    // 19:00 to 11:00, widened by the hour so a bar's clocks never meet the
    // top line or the day names.
    var bedLo = 420.0, bedHi = 1380.0;
    for (final day in week) {
      if (v.spans[day] case final s?) {
        bedLo = math.min(bedLo, ((s.bed - 120) / 60).floorToDouble() * 60);
        bedHi = math.max(bedHi, ((s.wake + 120) / 60).ceilToDouble() * 60);
      }
    }
    final (effLo, effHi) = weekLineAxis(effLine);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WeekCard(
        title: 'Sleep performance',
        metricId: 'sleep_perf',
        chart: WeekChart(days: week, columns: percent(v.perf), lo: 0, hi: 100),
      ),
      WeekCard(
        title: 'Hours vs. needed (hours)',
        metricId: 'hvn_hours',
        legend: weekLegend(const [
          ('Hours of sleep', C.dialSleep),
          ('Sleep needed', C.optimal),
        ], dots: true),
        chart: WeekChart(
          days: week,
          lo: 0,
          hi: needMax <= 0 ? 1 : needMax * 1.064,
          lines: [
            WeekLine(
              values: [for (final day in week) v.need[day]],
              labels: [for (final day in week) v.need[day] == null ? '' : clockDur(v.need[day])],
              color: C.optimal,
            ),
            WeekLine(
              values: [for (final day in week) v.tst[day]],
              labels: [for (final day in week) v.tst[day] == null ? '' : clockDur(v.tst[day])],
              color: C.dialSleep,
              below: true,
            ),
          ],
        ),
      ),
      WeekCard(
        title: 'Hours vs. needed (%)',
        metricId: 'hvn_pct',
        chart: WeekChart(days: week, columns: percent(v.hvn), lo: 0, hi: 100),
      ),
      WeekCard(
        title: 'Restorative sleep (hours)',
        metricId: 'restorative_hours',
        legend: weekLegend(const [
          ('Deep sleep', DC.stageDeep),
          ('REM sleep', DC.stageRem),
        ]),
        chart: WeekChart(
          days: week,
          lo: 0,
          hi: restMax <= 0 ? 1 : restMax * 1.37,
          columns: [
            for (final day in week)
              if (v.deep[day] != null && v.rem[day] != null)
                WeekColumn(
                  hi: v.deep[day]! + v.rem[day]!,
                  stack: [(v.rem[day]!, DC.stageRem), (v.deep[day]!, DC.stageDeep)],
                  top: clockDur(v.deep[day]! + v.rem[day]!),
                  topColor: DC.ink,
                  floatLabel: true,
                )
              else
                const WeekColumn(),
          ],
        ),
      ),
      WeekCard(
        title: 'Sleep consistency',
        metricId: 'consistency',
        chart: WeekChart(
            days: week, columns: percent(v.consistency), lo: 0, hi: 100),
      ),
      WeekCard(
        title: 'Time in bed',
        metricId: 'time_in_bed',
        chart: WeekChart(
          days: week,
          lo: bedLo,
          hi: bedHi,
          inverted: true,
          columns: [
            for (final day in week)
              if (v.spans[day] case final s?)
                WeekColumn(
                  lo: s.wake,
                  hi: s.bed,
                  top: _afterNoon(s.bed),
                  bottom: _afterNoon(s.wake),
                  color: C.dialSleep,
                )
              else
                const WeekColumn(),
          ],
        ),
      ),
      WeekCard(
        title: 'Sleep efficiency',
        metricId: 'efficiency',
        chart: WeekChart(
          days: week,
          lo: effLo,
          hi: effHi,
          lines: [
            WeekLine(
              values: effLine,
              labels: [for (final x in effLine) x == null ? '' : '${x.round()}%'],
              color: C.dialSleep,
            ),
          ],
        ),
      ),
      WeekCard(
        title: 'Sleep debt',
        metricId: 'sleep_debt',
        chart: WeekChart(
          days: week,
          lo: 0,
          hi: debtMax <= 0 ? 1 : debtMax * 1.41,
          columns: [
            for (final day in week)
              if (v.debt[day] case final x?)
                WeekColumn(
                    hi: math.max(0, x),
                    top: clockDur(math.max(0, x)),
                    color: C.dialSleep)
              else
                const WeekColumn(),
          ],
        ),
      ),
      WeekCard(
        title: 'Sleep stress',
        metricId: 'sleep_debt',
        onOpen: () => Navigator.of(c).push(MaterialPageRoute(
            builder: (_) => const StressMonitorScreen())),
        legend: weekLegend(const [
          ('High', C.poor),
          ('Medium', C.optimal),
          ('Low', DC.line2),
        ]),
        chart: WeekChart(
          days: week,
          lo: 0,
          hi: 100,
          columns: [
            for (final day in week)
              if (stress[day] case final s? when s.scored > 0)
                WeekColumn(
                  hi: 100,
                  stack: [
                    (s.low / s.scored * 100, DC.line2),
                    (s.medium / s.scored * 100, C.optimal),
                    (s.high / s.scored * 100, C.poor),
                  ],
                  top: clockDur(s.high),
                  topColor: C.poor,
                )
              else
                const WeekColumn(),
          ],
        ),
      ),
    ]);
  }
}

/// Minutes after noon as a clock time.
String _afterNoon(double m) {
  final t = (m.round() + 720) % 1440;
  final h = t ~/ 60;
  return '${h.toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
}
