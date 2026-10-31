// Nutrition — the Macros page.
//
// One page, top to bottom, in the order a person uses it: which day (a week
// strip, paged back through weeks), how that day stands (energy against the
// target, the three macros against theirs), four ways to log (photo, barcode,
// describe, search), the meals themselves, water, and the week's energy.
//
// Three things this screen refuses to do, and they shape everything else:
//
//   1. It never shows a total it cannot stand behind. A day where any occasion
//      has no energy attached is a FLOOR, labelled "at least", and it is
//      excluded from every average.
//   2. Partial days are detected, not declared. There is no "I logged
//      everything" checkbox, because nobody ticks it and every average then
//      quietly rots.
//   3. One day of intake is noise, seven is a habit: the week's mean sits under
//      the day and is built only from complete days.
//
// Water is NOT re-invented here: it is the existing `water_ml` journal field
// (`lib/data/journal_fields.dart`), read and written through the repo.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/nutrition_store.dart';
import '../../models/metric.dart';
import '../../data/journal_fields.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'food_ai_sheet.dart';
import 'home/home_data.dart' show monthShortName, weekdayShortName;
import 'journal_compose.dart' show OsTextField;
import 'log_food.dart';
import 'trend_view.dart' show TrendMetric, TrendGroup, TrendFmt, trendAxis;

/// The week chart's scale: energy eaten, in kcal, columns from zero.
const _eatenMetric = TrendMetric(
  'kcal_eaten',
  'Eaten',
  TrendGroup.strain,
  LucideIcons.utensils,
  TrendFmt.grouped,
  unit: 'kcal',
);

class NutritionScreen extends StatefulWidget {
  /// Pushed from the Activity tab rather than shown as a tab: a page with a
  /// back arrow. Nutrition is a section of Activity now; the band measures
  /// nothing about food, so it no longer holds a tab of its own.
  final bool page;
  const NutritionScreen({super.key, this.page = false});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> with RevisionReload {
  /// Weeks back from this one. The strip and the chart page together.
  int _weekBack = 0;

  /// The day the page is about, or null for today. Read through [_date] on
  /// every use, never captured once: the shell keeps this page alive, so a
  /// stored "today" would still be yesterday after midnight and an occasion
  /// logged at 00:05 would land on the wrong day.
  String? _picked;
  String get _date => _picked ?? todayLabel();
  bool get _isToday => _date == todayLabel();

  /// The bar the finger is on in the week chart, or null.
  int? _scrub;

  /// "More nutrients" open under the macros.
  bool _more = false;

  NutritionWindow? _week;

  /// What the body spent on [_date]: today's live figure, or the day's stored
  /// total for a past one. Null when it was never measured.
  double? _burned;
  double? _waterMl;

  /// The day [_waterMl] was read for. Past midnight on a page nobody reloaded
  /// it is still yesterday's, and a full yesterday disabled today's + button.
  String? _waterDate;
  bool _loading = true;

  /// The local profile map, read once per load. Targets live here rather than
  /// in a new table: they are numbers the user typed, the same shape as
  /// `step_goal` next to them.
  Map<String, dynamic> _profile = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Burned calories and water come from the derived store and the journal,
  /// both of which are written from elsewhere in the app — an import, a derive
  /// after a sync, water logged on Wellness. This page is never disposed, so
  /// without this it showed launch-time figures all day.
  @override
  void reload() => _load();

  /// The last day of the week on show: today, or a Sunday-to-Saturday-free
  /// seven days ending [_weekBack] weeks ago.
  DateTime get _weekEnd {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day - 7 * _weekBack);
  }

  Future<void> _load() async {
    final t = beginRead(#nutrition);
    final app = context.read<AppState>();
    final db = await LocalDb.instance;
    final today = todayLabel();
    final week = await NutritionDb.window(
      db,
      days: 7,
      now: _weekEnd,
      today: today,
    );
    double? burned;
    double? water;
    final date = _date;
    final repo = app.repo;
    if (repo != null) {
      if (date == today) {
        final daily = (await repo.getToday())['daily'];
        if (daily is Map) {
          burned = Metric.parse(daily['calories_total']).value?.toDouble();
        }
      } else {
        burned = ((await repo.getDayStrain(date))['calories_total'] as num?)
            ?.toDouble();
      }
      water = (await repo.getJournalMetrics(date))['water_ml']?.value;
    }
    if (!stillNewest(#nutrition, t)) return;
    setState(() {
      _week = week;
      _burned = burned;
      _waterMl = water;
      _waterDate = date;
      _profile = {...?app.user};
      _loading = false;
    });
  }

  NutritionDay? get _day {
    for (final d in _week?.days ?? const <NutritionDay>[]) {
      if (d.date == _date) return d;
    }
    return null;
  }

  void _pickDay(String date) {
    if (date == _date) return;
    setState(() => _picked = date == todayLabel() ? null : date);
    _load();
  }

  /// A week back or forward. The page lands on the same weekday position it
  /// was on — the last day of the window — so the strip never shows a week
  /// with nothing picked in it.
  void _pageWeek(int dir) {
    setState(() {
      _weekBack = math.max(0, _weekBack - dir);
      _scrub = null;
      _picked = _weekBack == 0 ? null : dayLabelOf(_weekEnd);
    });
    _load();
  }

  /// The meal a log from here starts on: the hour's meal today, and a snack
  /// for a past day (nobody knows which meal they are back-filling).
  String get _defaultMeal =>
      _isToday ? mealForHour(DateTime.now().hour) : 'snack';

  Future<void> _logFood({String? meal, bool scan = false}) async {
    final ok = await LogFoodSheet.show(
      context,
      date: _date,
      meal: meal ?? _defaultMeal,
      scan: scan,
    );
    if (ok == true) await _load();
  }

  Future<void> _logAi({required bool camera}) async {
    final ok = await openFoodAi(
      context,
      date: _date,
      meal: _defaultMeal,
      camera: camera,
    );
    if (ok == true) await _load();
  }

  /// One tap's worth of water, from the field spec that performs the tap.
  static JournalFieldSpec get _waterSpec => kJournalFieldsByKey['water_ml']!;

  /// One write at a time. `_stepWater` reads the day, then awaits, then writes
  /// it back — and `postJournalMetrics` replaces the whole day — so two taps
  /// during that await both read the same map and the second write silently
  /// eats the first tap. Same guard the wellness screen already uses for its
  /// journal fields.
  bool _writingWater = false;

  /// Step the day's water up or down, in place. Same ladder as the journal's
  /// own stepper — a step down off the last glass lands on a logged ZERO
  /// ("none today"), and a step down from zero clears the field, because
  /// absence and zero are different answers.
  Future<void> _stepWater(int dir) async {
    final repo = context.read<AppState>().repo;
    if (repo == null || _writingWater) return;
    _writingWater = true;
    try {
      // Inside the try, not before it: the READ can throw too, and with the
      // guard already set that left both buttons dead until the screen was
      // rebuilt — the flag outliving the operation it was protecting.
      //
      // Step from what is stored for the day, not from `_waterMl`: that is the
      // last load's figure, and on a page left open past midnight it is still
      // yesterday's total, so the first tap wrote yesterday + 250 ml to today.
      //
      // Drop the key rather than omitting it from a spread: `putJournalMetrics`
      // clears the day and re-inserts what it is handed, so leaving `water_ml`
      // out is what "no answer today" looks like on disk — and spreading the
      // old map back in is exactly what made this un-clearable.
      final date = _date;
      final fields = {...await repo.getJournalMetrics(date)};
      final v = fields.remove('water_ml')?.value;
      final spec = _waterSpec;
      double? next;
      if (dir > 0) {
        next = ((v ?? 0) + spec.step).clamp(0, spec.max).toDouble();
      } else {
        final down = (v ?? 0) - spec.step;
        next = down <= 0 ? (v == null || v == 0 ? null : 0.0) : down;
      }
      if (mounted) {
        setState(() {
          _waterMl = next;
          _waterDate = date;
        });
      }
      if (next != null) fields['water_ml'] = JournalMetricValue(next);
      await repo.postJournalMetrics(date, fields);
      await _load();
    } finally {
      // Cleared unconditionally; the setState is only for the repaint. Gating
      // the assignment on `mounted` would strand it again on the path where
      // the screen goes away mid-write.
      _writingWater = false;
      if (mounted) setState(() {});
    }
  }

  /// Edit an entry — amount, meal, time — or remove it from the same sheet.
  Future<void> _editFood(FoodEntry e) async {
    final ok = await LogFoodSheet.show(context, entry: e);
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final logFood = Pressable(
      semanticLabel: l?.nutritionLogFood ?? 'Log food',
      onTap: _logFood,
      child: Icon(
        LucideIcons.circlePlus,
        size: I.md,
        color: P.of(c).on(C.domFood),
      ),
    );
    final list = ListView(
      padding: EdgeInsets.fromLTRB(S.x4, widget.page ? 0 : S.x4, S.x4, S.x16),
      children: [
        if (!widget.page)
          ScreenTitle(l?.nutritionTitle ?? 'Nutrition', trailing: logFood),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: S.x10),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ..._page(c),
      ],
    );
    if (!widget.page) return list;
    return Scaffold(
      backgroundColor: P.of(c).bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(
                l?.nutritionTitle ?? 'Nutrition',
                trailing: logFood,
              ),
            ),
            Expanded(child: list),
          ],
        ),
      ),
    );
  }

  List<Widget> _page(BuildContext c) {
    final l = AppLocalizations.of(c);
    final w = _week;
    final day = _day;
    return [
      if (w != null)
        _DayStrip(
          week: w,
          picked: _date,
          kcalTarget: _target('kcal_target'),
          onPick: _pickDay,
          onEarlier: () => _pageWeek(-1),
          onLater: _weekBack == 0 ? null : () => _pageWeek(1),
        ),
      const SizedBox(height: S.x3),
      _EnergyCard(
        date: _date,
        today: _isToday,
        day: day,
        burned: _burned,
        target: _target,
        more: _more,
        onMore: () => setState(() => _more = !_more),
        onTargets: _editTargets,
      ),
      const SizedBox(height: S.x3),
      _LogDock(
        onPhoto: () => _logAi(camera: true),
        onBarcode: () => _logFood(scan: true),
        onDescribe: () => _logAi(camera: false),
        onSearch: _logFood,
      ),
      Section(
        l?.nutritionOccasionsSection ?? 'Occasions',
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(
            children: [
              for (final m in kMeals) ...[
                MealRow(
                  meal: m,
                  entries: day?.mealEntries(m) ?? const [],
                  onTap: () => _logFood(meal: m),
                ),
                // The individual entries, indented under the occasion they
                // belong to, each one editable and removable. A mistyped
                // 2,000 kcal used to be permanent and it silently poisoned
                // every seven-day mean it fell into.
                for (final e in day?.mealEntries(m) ?? const <FoodEntry>[])
                  Padding(
                    padding: const EdgeInsets.only(left: S.x8),
                    child: FoodRow(
                      entry: e,
                      trailing: LucideIcons.pencil,
                      onTap: () => _editFood(e),
                    ),
                  ),
              ],
            ],
          ),
        ),
        action: l?.nutritionAddAction ?? 'Add',
        onAction: _logFood,
      ),
      const SizedBox(height: S.x3),
      // Gated on the repository too: with no repo `_stepWater` returns at
      // its first line, so an enabled + button was a control that did
      // nothing — worse than a disabled one, which at least says so.
      Builder(
        builder: (bc) {
          final live =
              bc.select<AppState, bool>((a) => a.repo != null) &&
              !_writingWater;
          final ml = _waterDate == _date ? _waterMl : null;
          return _WaterRow(
            ml: ml,
            onDown: (!live || ml == null) ? null : () => _stepWater(-1),
            onUp: (!live || (ml ?? 0) >= _waterSpec.max)
                ? null
                : () => _stepWater(1),
          );
        },
      ),
      if (day != null && day.logged && day.kcal.isFloor) ...[
        const SizedBox(height: S.x3),
        StatusCard(
          l?.nutritionFloorTitle ?? 'Today\'s energy is a floor, not a total',
          l?.nutritionFloorBody(day.kcal.unknown, day.entries.length) ??
              '${day.kcal.unknown} of ${day.entries.length} occasions were '
                  'logged without an energy figure, so the number above is '
                  'the least you ate rather than what you ate.',
          fix: l?.nutritionAddNumbersFix ?? 'Add the numbers to an occasion',
          icon: LucideIcons.circleDashed,
          onFix: _logFood,
        ),
      ],
      if (w != null) Section('This week', _weekCard(c, w)),
      if (w != null && _partialDays(w) > 0) ...[
        const SizedBox(height: S.x3),
        Observation(
          l?.nutritionDaysNotCounted(_partialDays(w), w.span) ??
              '${_partialDays(w)} of the last ${w.span} days could not be '
                  'counted',
          l?.nutritionDayCountsRule ??
              'A day counts once every occasion carries an energy figure.',
        ),
      ],
    ];
  }

  // ── WEEK ─────────────────────────────────────────────────────────────────

  /// Logged days that are genuinely partial. Today is deliberately not one of
  /// them — it is unfinished, not incomplete.
  static int _partialDays(NutritionWindow w) =>
      w.days.where((d) => d.state == DayLogState.partial).length;

  /// The week's energy as columns, the picked day banded, and the mean of the
  /// complete days over them. A day with nothing logged draws no bar rather
  /// than a zero — zero kcal is a claim, an unlogged day is an absence. A
  /// PARTIAL day still draws, because its total is a real floor; the line
  /// under the chart says it is one and that the mean left it out.
  Widget _weekCard(BuildContext c, NutritionWindow w) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final vals = [for (final d in w.days) d.kcal.value];
    final real = [
      for (final v in vals)
        if (v != null && v > 0) v,
    ];
    final axis = trendAxis(_eatenMetric, real, line: false);
    final mean = w.meanKcal;
    final s = _scrub;
    final scrubbed = s == null ? null : w.days[s];
    final partial = _partialDays(w);
    final big = scrubbed != null
        ? (scrubbed.kcal.value == null
              ? (scrubbed.logged
                    ? (l?.nutritionNotRecorded ?? 'Not recorded')
                    : (l?.nutritionNotLogged ?? 'Not logged'))
              : '${scrubbed.kcal.isFloor ? '≥ ' : ''}${_grouped(scrubbed.kcal.value!)}')
        : (mean.value == null
              ? (l?.nutritionNotCounted ?? 'Not counted')
              : _grouped(mean.value!));
    final hasNumber = scrubbed != null
        ? scrubbed.kcal.value != null
        : mean.value != null;
    final caption = scrubbed != null
        ? _longDay(scrubbed.date, l).toUpperCase()
        : (mean.value == null
              ? 'NO COMPLETE DAY THIS WEEK'
              : 'DAILY MEAN · ${mean.days} COMPLETE DAY${mean.days == 1 ? '' : 'S'}');
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: F.over.copyWith(color: p.ink3)),
          const SizedBox(height: S.x1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                big,
                style: hasNumber
                    ? F.n34.copyWith(color: p.ink)
                    : F.head.copyWith(color: p.ink2),
              ),
              if (hasNumber) ...[
                const SizedBox(width: S.x1),
                Text('kcal', style: F.cap.copyWith(color: p.ink3)),
              ],
            ],
          ),
          const SizedBox(height: S.x3),
          if (real.isEmpty)
            SizedBox(
              height: S.x16 * 2,
              child: NoData(
                message: w.daysLogged == 0
                    ? (l?.nutritionNothingLoggedYet ?? 'Nothing logged yet')
                    : (l?.nutritionNoEnergyFiguresYet ??
                          'No energy figures yet'),
              ),
            )
          else
            ScrubColumns(
              values: [for (final v in vals) (v ?? 0) > 0 ? v : null],
              xLabels: [
                for (final d in w.days)
                  () {
                    final dt = DateTime.parse(d.date);
                    return '${weekdayShortName(dt.weekday, l)}\n${dt.day}';
                  }(),
              ],
              lo: axis.lo,
              hi: axis.hi,
              ticks: axis.ticks,
              tickText: (t) => t >= 1000
                  ? '${(t / 1000).toStringAsFixed(t % 1000 == 0 ? 0 : 1)}k'
                  : '${t.round()}',
              avg: mean.value,
              color: C.domFood,
              highlight: w.days.indexWhere((d) => d.date == _date),
              height: S.x16 * 3,
              label: l?.nutritionEnergyLoggedTitle ?? 'Energy logged',
              describe: (i) {
                final v = vals[i];
                return '${_longDay(w.days[i].date, l)}: '
                    '${v == null ? 'not logged' : '${v.round()} kcal'}';
              },
              onScrub: (i) => setState(() => _scrub = i),
            ),
          if (partial > 0) ...[
            const SizedBox(height: S.x2),
            Text(
              l?.nutritionPartialFootnote(partial) ??
                  '$partial partial, left out of the averages below.',
              style: F.cap.copyWith(color: p.ink3, height: 1.4),
            ),
          ],
          const SizedBox(height: S.x3),
          _Mean(
            l?.nutritionLabelProtein ?? 'Protein',
            w.meanProtein,
            'g',
            C.red,
          ),
          _Mean(l?.nutritionLabelCarbs ?? 'Carbs', w.meanCarbs, 'g', C.orange),
          _Mean(l?.nutritionLabelFat ?? 'Fat', w.meanFat, 'g', C.yellow),
          _Mean(l?.nutritionLabelFibre ?? 'Fibre', w.meanFibre, 'g', C.green),
        ],
      ),
    );
  }

  // ── TARGETS ──────────────────────────────────────────────────────────────

  /// Targets the user TYPES. Adaptive targets need weight history and ~21
  /// complete days and stay deferred; a typed one needs no science at all.
  static List<(String, String, String, Color)> _goalSpecs(BuildContext c) {
    final l = AppLocalizations.of(c);
    return [
      (
        'kcal_target',
        l?.nutritionDailyEnergy ?? 'Daily energy',
        'kcal',
        C.domFood,
      ),
      (
        'protein_target',
        l?.nutritionDailyProtein ?? 'Daily protein',
        'g',
        C.red,
      ),
      ('carbs_target', 'Daily carbs', 'g', C.orange),
      ('fat_target', 'Daily fat', 'g', C.yellow),
    ];
  }

  double? _target(String key) {
    final v = (_profile[key] as num?)?.toDouble();
    return v == null || v <= 0 ? null : v;
  }

  Future<void> _editTargets() async {
    final specs = _goalSpecs(context);
    final ctrls = {
      for (final g in specs)
        g.$1: TextEditingController(
          text: _target(g.$1)?.round().toString() ?? '',
        ),
    };
    final saved = await AppSheet.open<bool>(
      context,
      builder: (s) {
        final l = AppLocalizations.of(s);
        return Padding(
          padding: EdgeInsets.only(
            left: S.x5,
            right: S.x5,
            top: S.x5,
            bottom: MediaQuery.of(s).viewInsets.bottom + S.x5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l?.nutritionYourTargetsSection ?? 'Your targets',
                style: F.head.copyWith(color: P.of(s).ink),
              ),
              const SizedBox(height: S.x4),
              for (final g in specs) ...[
                OsTextField(
                  controller: ctrls[g.$1]!,
                  label: '${g.$2} (${g.$3})',
                  hint: l?.nutritionHintNone ?? 'none',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: S.x3),
              ],
              const SizedBox(height: S.x2),
              BigButton(
                l?.actionSave ?? 'Save',
                color: C.domFood,
                onTap: () => Navigator.of(s).pop(true),
              ),
            ],
          ),
        );
      },
      scroll: true,
    );
    // Blank clears the target; a typo does NOT. "2,000" used to clear it and
    // the sheet closed as if it had saved.
    final typed = {for (final g in specs) g.$1: Typed.of(ctrls[g.$1]!.text)};
    final fields = {for (final g in specs) g.$1: typed[g.$1]!.value};
    for (final ctrl in ctrls.values) {
      ctrl.dispose();
    }
    if (saved != true || !mounted) return;
    final bad = [
      for (final g in specs)
        if (typed[g.$1]!.bad) g.$2,
    ];
    if (bad.isNotEmpty) {
      sayUnreadable(context, bad);
      return;
    }
    await context.read<AppState>().updateProfile(fields);
    await _load();
  }
}

/// 1,240 — energy reads in thousands often enough to want the comma.
String _grouped(double v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// "Sat, Oct 25" from a `YYYY-MM-DD` label.
String _longDay(String ymd, AppLocalizations? l) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return '${weekdayShortName(d.weekday, l)}, ${monthShortName(d.month, l)} ${d.day}';
}

/// A nutrient summed over [es], with how many entries did and did not report
/// it — the same rule as the day's own totals, for the ones a day does not
/// roll up (sugar, saturated fat, sodium).
NutrientTotal _sumOf(List<FoodEntry> es, double? Function(FoodEntry) pick) {
  var total = 0.0;
  var known = 0, unknown = 0;
  for (final e in es) {
    final v = pick(e);
    if (v == null) {
      unknown++;
    } else {
      total += v;
      known++;
    }
  }
  return NutrientTotal(known == 0 ? null : total, known, unknown);
}

// ── the page's parts ───────────────────────────────────────────────────────

/// Seven days, the picked one filled, each with a thin ring of its energy
/// against the target (or a dot when it was logged with no target to fill).
/// The pager above steps back and forward a week.
class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.week,
    required this.picked,
    required this.kcalTarget,
    required this.onPick,
    this.onEarlier,
    this.onLater,
  });

  final NutritionWindow week;
  final String picked;
  final double? kcalTarget;
  final ValueChanged<String> onPick;
  final VoidCallback? onEarlier, onLater;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final first = DateTime.parse(week.days.first.date);
    final last = DateTime.parse(week.days.last.date);
    final today = todayLabel();
    return Surface(
      pad: const EdgeInsets.fromLTRB(S.x2, S.x1, S.x2, S.x3),
      child: Column(
        children: [
          WindowPager(
            '${monthShortName(first.month, l)} ${first.day} - '
            '${monthShortName(last.month, l)} ${last.day}',
            onEarlier: onEarlier,
            onLater: onLater,
          ),
          const SizedBox(height: S.x1),
          Row(
            children: [
              for (final d in week.days)
                Expanded(
                  child: () {
                    final dt = DateTime.parse(d.date);
                    final on = d.date == picked;
                    final v = d.kcal.value;
                    final frac = kcalTarget == null || v == null
                        ? null
                        : (v / kcalTarget!).clamp(0, 1).toDouble();
                    return Pressable(
                      onTap: () => onPick(d.date),
                      semanticLabel: _longDay(d.date, l),
                      child: Column(
                        children: [
                          Text(
                            weekdayShortName(
                              dt.weekday,
                              l,
                            ).substring(0, 1).toUpperCase(),
                            style: F.over.copyWith(
                              color: d.date == today ? p.on(C.domFood) : p.ink3,
                            ),
                          ),
                          const SizedBox(height: S.x1),
                          SizedBox(
                            width: S.x10,
                            height: S.x10,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (on)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: p.wash(C.domFood),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                CustomPaint(
                                  size: Size.infinite,
                                  painter: Ring(
                                    frac ?? 0,
                                    p.fill(C.domFood),
                                    p.track,
                                    stroke: 3,
                                    solid: true,
                                  ),
                                ),
                                Text(
                                  '${dt.day}',
                                  style: F.cap.copyWith(
                                    color: on ? p.ink : p.ink2,
                                    fontWeight: on
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: S.x1),
                          // Logged at all: a dot, so a day with one-tap
                          // occasions and no energy still shows it was kept.
                          Opacity(
                            opacity: d.logged ? 1 : 0,
                            child: Container(
                              width: S.x1,
                              height: S.x1,
                              decoration: BoxDecoration(
                                color: p.fill(C.domFood),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The day: a ring of energy eaten against the target, what is left and what
/// was burned beside it, then protein, carbs and fat as bars against theirs,
/// and the rest of the label folded away under "More nutrients".
class _EnergyCard extends StatelessWidget {
  const _EnergyCard({
    required this.date,
    required this.today,
    required this.day,
    required this.burned,
    required this.target,
    required this.more,
    required this.onMore,
    required this.onTargets,
  });

  final String date;
  final bool today;
  final NutritionDay? day;
  final double? burned;
  final double? Function(String key) target;
  final bool more;
  final VoidCallback onMore, onTargets;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final d = day;
    final k = d?.kcal;
    final eaten = k?.value;
    final kt = target('kcal_target');
    final logged = d != null && d.logged;
    final floor = k?.isFloor ?? false;
    final atLeast = l?.nutritionAtLeastPrefix ?? 'at least ';
    final entries = d?.entries ?? const <FoodEntry>[];

    final Widget centre;
    if (eaten != null) {
      centre = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (floor)
            Text(
              atLeast.trim().toUpperCase(),
              style: F.over.copyWith(color: p.on(C.yellow)),
            ),
          Text(_grouped(eaten), style: F.n34.copyWith(color: p.ink)),
          Text(
            kt == null ? 'kcal eaten' : 'of ${_grouped(kt)} kcal',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      );
    } else if (logged) {
      // With no energy anywhere in the day, the occasion count IS the
      // measurement. A dash here would read as a failure to record when the
      // day was in fact recorded exactly as designed.
      centre = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${entries.length}', style: F.n34.copyWith(color: p.ink)),
          Text(
            l?.nutritionOccasionsUnit(entries.length) ??
                'occasion${entries.length == 1 ? '' : 's'}',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      );
    } else {
      centre = Text(
        l?.nutritionNotLogged ?? 'Not logged',
        textAlign: TextAlign.center,
        style: F.cap.copyWith(color: p.ink3),
      );
    }

    final left = eaten == null || kt == null ? null : kt - eaten;
    final stats = <(String, String, Color?)>[
      if (left != null)
        (
          left >= 0 ? 'LEFT' : 'OVER',
          // A floor's "left" is at most this: more may have been eaten.
          '${floor && left >= 0 ? '≤ ' : ''}${_grouped(left.abs())}',
          left >= 0 ? C.domFood : C.red,
        ),
      (
        l?.nutritionLabelBurned ?? 'BURNED',
        burned == null
            ? (l?.nutritionNotMeasured ?? 'Not measured')
            : _grouped(burned!),
        burned == null ? null : C.purple,
      ),
      if (eaten != null && burned != null)
        (
          // Eaten is a FLOOR when occasions were logged without an energy
          // figure, so eaten minus burned is a floor too: the balance is AT
          // LEAST this, never at most.
          floor
              ? (l?.nutritionLabelBalanceAtLeast ?? 'BALANCE AT LEAST')
              : (l?.nutritionLabelBalance ?? 'BALANCE'),
          '${eaten - burned! > 0 ? '+' : ''}${_grouped(eaten - burned!)}',
          C.teal,
        ),
    ];

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  today
                      ? (l?.nutritionTabToday ?? 'Today').toUpperCase()
                      : _longDay(date, l).toUpperCase(),
                  style: F.over.copyWith(color: p.ink3),
                ),
              ),
              Pressable(
                onTap: onTargets,
                semanticLabel: l?.nutritionYourTargetsSection ?? 'Your targets',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.target, size: I.sm, color: p.ink2),
                    const SizedBox(width: S.x1),
                    Text(
                      kt == null
                          ? (l?.nutritionSetTargetFix ?? 'Set a target')
                          : (l?.nutritionEditAction ?? 'Edit'),
                      style: F.cap.copyWith(
                        color: p.ink2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x4),
          Row(
            children: [
              SizedBox(
                width: S.x16 * 2,
                height: S.x16 * 2,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.infinite,
                      painter: Ring(
                        eaten == null || kt == null
                            ? 0
                            : (eaten / kt).clamp(0, 1).toDouble(),
                        eaten != null && kt != null && eaten > kt
                            ? p.fill(C.red)
                            : p.fill(C.domFood),
                        p.track,
                        stroke: S.x3,
                        solid: !floor,
                        t: animate(c, 1),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(S.x4),
                      child: FittedBox(fit: BoxFit.scaleDown, child: centre),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: S.x5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, s) in stats.indexed) ...[
                      if (i > 0) const SizedBox(height: S.x3),
                      Text(s.$1, style: F.over.copyWith(color: p.ink3)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              s.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: s.$3 == null
                                  ? F.body.copyWith(color: p.ink2)
                                  : F.n24.copyWith(color: p.ink),
                            ),
                          ),
                          if (s.$3 != null) ...[
                            const SizedBox(width: S.x1),
                            Text('kcal', style: F.cap.copyWith(color: p.ink3)),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x5),
          _MacroBar(
            l?.nutritionLabelProtein ?? 'Protein',
            d?.protein,
            target('protein_target'),
            C.red,
            logged: logged,
          ),
          const SizedBox(height: S.x3),
          _MacroBar(
            l?.nutritionLabelCarbs ?? 'Carbs',
            d?.carbs,
            target('carbs_target'),
            C.orange,
            logged: logged,
          ),
          const SizedBox(height: S.x3),
          _MacroBar(
            l?.nutritionLabelFat ?? 'Fat',
            d?.fat,
            target('fat_target'),
            C.yellow,
            logged: logged,
          ),
          const SizedBox(height: S.x2),
          Pressable(
            onTap: onMore,
            semanticLabel: 'More nutrients',
            child: SizedBox(
              height: S.tap,
              child: Row(
                children: [
                  Text('MORE NUTRIENTS', style: F.over.copyWith(color: p.ink2)),
                  const SizedBox(width: S.x1),
                  AnimatedRotation(
                    turns: more ? .5 : 0,
                    duration: motion(c, Motion.fast),
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: I.sm,
                      color: p.ink2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: motion(c, Motion.base),
            curve: Ease.standard,
            alignment: Alignment.topCenter,
            child: !more
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      for (final n in [
                        (l?.nutritionLabelFibre ?? 'Fibre', d?.fibre, 'g'),
                        ('Sugar', _sumOf(entries, (e) => e.sugarG), 'g'),
                        (
                          'Saturated fat',
                          _sumOf(entries, (e) => e.satFatG),
                          'g',
                        ),
                        ('Sodium', _sumOf(entries, (e) => e.sodiumMg), 'mg'),
                      ])
                        _NutrientLine(n.$1, n.$2, n.$3, logged: logged),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One macro: what was eaten, out of the target, as a bar, with what is left.
/// No target draws the figure alone. No figure says so — never a 0 g bar.
class _MacroBar extends StatelessWidget {
  const _MacroBar(
    this.label,
    this.total,
    this.target,
    this.color, {
    required this.logged,
  });

  final String label;
  final NutrientTotal? total;
  final double? target;
  final Color color;
  final bool logged;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final v = total?.value;
    final t = target;
    final floor = total?.isFloor ?? false;
    final String sub;
    if (!logged) {
      sub = '';
    } else if (v == null) {
      sub = l?.nutritionNotRecorded ?? 'Not recorded';
    } else if (t == null) {
      sub = floor ? (l?.nutritionAtLeast ?? 'At least') : '';
    } else {
      // Rounded up: 99.6 of 100 g is still 1 g to go, never "reached". A
      // floor that has not reached the target cannot say how far is left.
      final left = (t - v).ceil();
      sub = left > 0
          ? (floor
                ? (l?.nutritionAtLeast ?? 'At least')
                : (l?.nutritionProteinToGo(left) ?? '$left g to go'))
          : (l?.nutritionTargetReached ?? 'Target reached');
    }
    final frac = v == null || t == null ? 0.0 : (v / t).clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // Its own centred row: inside the baseline row the dot, which
            // has no baseline, sat on top of the label.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: S.x2,
                  height: S.x2,
                  decoration: BoxDecoration(
                    color: p.fill(color),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: S.x2),
                Text(label.toUpperCase(),
                    style: F.over.copyWith(color: p.ink2)),
              ],
            ),
            const Spacer(),
            Text(
              v == null ? '' : '${v.round()} g',
              style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700),
            ),
            if (t != null)
              Text(' / ${t.round()} g', style: F.cap.copyWith(color: p.ink3)),
          ],
        ),
        const SizedBox(height: S.x1 + S.half),
        ClipRRect(
          borderRadius: R.rPill,
          child: SizedBox(
            height: S.x1 + S.half,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: p.track)),
                FractionallySizedBox(
                  widthFactor: frac,
                  heightFactor: 1,
                  child: ColoredBox(
                    color: floor
                        ? p.fill(color).withValues(alpha: .55)
                        : p.fill(color),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: S.x1),
          Text(sub, style: F.cap.copyWith(color: p.ink3)),
        ],
      ],
    );
  }
}

/// One of the folded-away nutrients: name, and the day's figure or why there
/// is none.
class _NutrientLine extends StatelessWidget {
  const _NutrientLine(
    this.label,
    this.total,
    this.unit, {
    required this.logged,
  });
  final String label;
  final NutrientTotal? total;
  final String unit;
  final bool logged;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final t = total;
    final v = t?.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x1 + S.half),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: F.body.copyWith(color: p.ink2)),
          ),
          Text(
            !logged
                ? ''
                : v == null
                ? (l?.nutritionNotRecorded ?? 'Not recorded')
                : '${t!.isFloor ? '≥ ' : ''}'
                      '${unit == 'mg' ? v.round() : v.toStringAsFixed(v < 10 ? 1 : 0)} $unit',
            style: v == null
                ? F.cap.copyWith(color: p.ink3)
                : F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Four ways in, one tap each: a photo the AI reads, a barcode, a sentence the
/// AI reads, or a search of what you have logged before.
class _LogDock extends StatelessWidget {
  const _LogDock({
    required this.onPhoto,
    required this.onBarcode,
    required this.onDescribe,
    required this.onSearch,
  });

  final VoidCallback onPhoto, onBarcode, onDescribe, onSearch;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget tile(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: Surface(
          pad: const EdgeInsets.symmetric(vertical: S.x3),
          child: Column(
            children: [
              Container(
                width: S.x10,
                height: S.x10,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.wash(C.domFood),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: I.md, color: p.on(C.domFood)),
              ),
              const SizedBox(height: S.x2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.cap.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Row(
      children: [
        tile(LucideIcons.camera, 'Photo', onPhoto),
        const SizedBox(width: S.x2),
        tile(LucideIcons.scanBarcode, 'Barcode', onBarcode),
        const SizedBox(width: S.x2),
        tile(LucideIcons.sparkles, 'Describe', onDescribe),
        const SizedBox(width: S.x2),
        tile(LucideIcons.search, 'Search', onSearch),
      ],
    );
  }
}

// ── components ─────────────────────────────────────────────────────────────

/// Today's energy, with its honesty state on the face of it. `at least` is not
/// a hedge — it is arithmetic: a total that summed past unknown values is a
/// lower bound and nothing more.
class DayEnergyCard extends StatelessWidget {
  const DayEnergyCard({super.key, required this.day, this.burned});

  final NutritionDay day;
  final Metric? burned;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final k = day.kcal;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  k.value == null
                      ? (l?.nutritionLoggedToday ?? 'LOGGED TODAY')
                      : (l?.nutritionEatenToday ?? 'EATEN TODAY'),
                  style: F.over.copyWith(color: p.ink3),
                ),
              ),
              if (k.isFloor)
                Flexible(
                  child: Pill(l?.nutritionAtLeast ?? 'At least', C.yellow),
                ),
            ],
          ),
          const SizedBox(height: S.x2),
          // With no energy anywhere in the day, the occasion count IS the
          // measurement. A dash here would read as a failure to record when
          // the day was in fact recorded exactly as designed.
          // A Wrap rather than a Row with a Spacer: `2,310 kcal` beside the
          // occasion count overflowed by 168 px at 3.1x, which is a day's
          // energy pushed off the card for the people who chose that size.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: S.x1,
            runSpacing: S.x1,
            children: [
              Text(
                k.value == null
                    ? day.entries.length.toString()
                    : k.value!.round().toString(),
                style: F.n34.copyWith(color: p.ink),
              ),
              Text(
                k.value == null
                    ? (l?.nutritionOccasionsUnit(day.entries.length) ??
                          'occasion${day.entries.length == 1 ? '' : 's'}')
                    : 'kcal',
                style: F.cap.copyWith(color: p.ink3),
              ),
              if (k.value != null)
                Text(
                  '· ${l?.nutritionOccasionsCount(day.entries.length) ?? '${day.entries.length} occasion'
                          '${day.entries.length == 1 ? '' : 's'}'}',
                  style: F.cap.copyWith(color: p.ink2),
                ),
            ],
          ),
          if (burned?.value != null) ...[
            const SizedBox(height: S.x4),
            InlineMetrics([
              (
                l?.nutritionLabelBurned ?? 'BURNED',
                '${burned!.value!.round()} kcal',
                C.purple,
              ),
              if (k.value != null)
                (
                  // Eaten is a FLOOR when occasions were logged without an
                  // energy figure, so eaten minus burned is a floor too: the
                  // balance is AT LEAST this, never at most. The pill on this
                  // same card says "At least".
                  k.isFloor
                      ? (l?.nutritionLabelBalanceAtLeast ?? 'BALANCE AT LEAST')
                      : (l?.nutritionLabelBalance ?? 'BALANCE'),
                  '${(k.value! - burned!.value!).round()} kcal',
                  C.teal,
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// One meal slot. An empty slot is an invitation, not a gap — the row never
/// implies you failed to log something you may simply not have eaten.
class MealRow extends StatelessWidget {
  const MealRow({
    super.key,
    required this.meal,
    required this.entries,
    this.onTap,
  });

  final String meal;
  final List<FoodEntry> entries;
  final VoidCallback? onTap;

  static const _icons = {
    'breakfast': LucideIcons.eggFried,
    'lunch': LucideIcons.salad,
    'dinner': LucideIcons.beef,
    'snack': LucideIcons.apple,
  };

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final known = [
      for (final e in entries)
        if (e.kcal != null) e.kcal!,
    ];
    final total = known.isEmpty ? null : known.reduce((a, b) => a + b);
    final anyUnknown = entries.any((e) => e.kcal == null);
    return Pressable(
      onTap: onTap,
      semanticLabel: _mealLabel(c, meal),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
              child: Icon(
                _icons[meal] ?? LucideIcons.utensils,
                size: I.sm,
                color: p.ink2,
              ),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mealLabel(c, meal),
                    style: F.body.copyWith(color: p.ink),
                  ),
                  Text(
                    entries.isEmpty
                        ? (l?.nutritionNotLogged ?? 'Not logged')
                        : total == null
                        ? (l?.nutritionLoggedNoEnergy(entries.length) ??
                              '${entries.length} logged · energy not recorded')
                        : '${anyUnknown ? (l?.nutritionAtLeastPrefix ?? 'at least ') : ''}'
                              '${total.round()} kcal',
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ],
              ),
            ),
            Icon(
              entries.isEmpty
                  ? LucideIcons.circlePlus
                  : LucideIcons.circleCheck,
              size: I.md,
              color: entries.isEmpty ? p.ink3 : p.on(C.green),
            ),
          ],
        ),
      ),
    );
  }
}

String _mealLabel(BuildContext c, String m) {
  final l = AppLocalizations.of(c);
  return switch (m) {
    'breakfast' => l?.nutritionMealBreakfast ?? 'Breakfast',
    'lunch' => l?.nutritionMealLunch ?? 'Lunch',
    'dinner' => l?.nutritionMealDinner ?? 'Dinner',
    _ => l?.nutritionMealSnacks ?? 'Snacks',
  };
}

/// One nutrient's seven-day mean, with its own denominator.
///
/// The denominator is the nutrient's, not the window's: a day counts toward the
/// ENERGY average on complete kcal alone, so protein can be a floor on a day
/// that qualified. Those days are excluded and NAMED here — a mean built on
/// floors is understated, and printing it beside the energy mean as though both
/// were measured the same way is the failure this row exists to prevent. There
/// is deliberately no "at least" pill: the gated mean is not a floor, so a floor
/// marker would be as wrong as the understatement it replaced.
class _Mean extends StatelessWidget {
  const _Mean(this.label, this.mean, this.unit, this.color);
  final String label;
  final NutrientMean mean;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final n = mean.days;
    final floors = mean.floorDays;
    final v = mean.value;
    final up = label.toUpperCase();
    final sub = v == null
        ? (floors > 0
            ? (l?.nutritionEveryDayNoFigure(up) ??
                'EVERY COMPLETE DAY HAD AN OCCASION WITH NO $up FIGURE')
            : (l?.nutritionNoDayRecorded(up) ?? 'NO COMPLETE DAY RECORDED $up'))
        : (l?.nutritionMeanOfCompleteDaysCaps(n) ??
                'MEAN OF $n COMPLETE DAY${n == 1 ? '' : 'S'}') +
            (floors == 0
                ? ''
                : (l?.nutritionLeftOutAsFloor(floors) ??
                    ' · $floors LEFT OUT AS A FLOOR'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      child: Row(
        children: [
          Container(
            width: S.x2,
            height: S.x2,
            decoration:
                BoxDecoration(color: p.fill(color), shape: BoxShape.circle),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: F.body.copyWith(color: p.ink)),
                Text(sub, style: F.over.copyWith(color: p.ink3)),
              ],
            ),
          ),
          const SizedBox(width: S.x3),
          Text(
            v == null
                ? (floors > 0
                    ? (l?.nutritionNotCounted ?? 'Not counted')
                    : (l?.nutritionNotRecorded ?? 'Not recorded'))
                : '${v.round()} $unit',
            style: v == null
                ? F.cap.copyWith(color: p.ink3)
                : F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Water, with the plus and minus ON the tile — `− 1.8 L +`.
///
/// A separate widget only because the shared [MetricRow] carries one tap for
/// the whole row, and water needs two targets pointing opposite ways. Nothing
/// else about it departs from that row's shape.
class _WaterRow extends StatelessWidget {
  const _WaterRow({required this.ml, this.onDown, this.onUp});

  /// Null is NOT logged, which is a different answer from a logged zero and
  /// reads differently here: "Not logged" against "0.0 L".
  final double? ml;
  final VoidCallback? onDown, onUp;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    return Surface(
      child: Row(
        children: [
          Icon(LucideIcons.glassWater, size: I.md, color: p.ink),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l?.nutritionWaterLabel ?? 'Water',
                  style: F.body.copyWith(color: p.ink),
                ),
                Text(
                  ml == null
                      ? (l?.nutritionNotLogged ?? 'Not logged')
                      : (l?.nutritionTapToChange ?? 'Tap − or + to change'),
                  style: F.over.copyWith(color: p.ink3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _WaterStep(LucideIcons.minus, onDown),
          // Fixed width so the number does not shove the buttons sideways as it
          // steps through 0.8 → 1.0 → 1.2.
          SizedBox(
            width: 78,
            child: Text(
              // NEVER a bare em-dash. An absent value says the word; a dash is a
              // shrug the reader has to interpret, and the suite pins this.
              ml == null
                  ? (l?.nutritionNoneYet ?? 'None yet')
                  : '${(ml! / 1000).toStringAsFixed(1)} L',
              textAlign: TextAlign.center,
              style: ml == null
                  ? F.cap.copyWith(color: p.ink3)
                  : F.n24.copyWith(color: p.ink),
              maxLines: 1,
            ),
          ),
          _WaterStep(LucideIcons.plus, onUp),
        ],
      ),
    );
  }
}

class _WaterStep extends StatelessWidget {
  const _WaterStep(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final on = onTap != null;
    return Pressable(
      onTap: onTap,
      semanticLabel: icon == LucideIcons.plus
          ? (l?.nutritionAddWater ?? 'Add water')
          : (l?.nutritionRemoveWater ?? 'Remove water'),
      child: Container(
        width: S.tap,
        height: S.tap,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? p.wash(C.blue) : p.card2,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: I.md, color: on ? p.on(C.blue) : p.ink3),
      ),
    );
  }
}
