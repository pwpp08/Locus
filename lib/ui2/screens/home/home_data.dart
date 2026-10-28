import 'dart:ui' show Color;

import 'package:flutter/material.dart' show Locale;
import 'package:intl/intl.dart';

import '../../../compute/findings.dart'
    show
        kReadinessEasyBelow,
        kReadinessGoodFrom,
        kReadinessRestBelow;
import '../../../data/day_label.dart'
    show calendarDaysBetween, dayLabelOf;
import '../../../data/db.dart' show LocalDb;
import '../../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../../data/local_repository.dart'
    show LocalRepository, kDefaultStepGoal;
import '../../../l10n/app_localizations.dart';
import '../../../l10n/date_text.dart';
import '../../../l10n/decimal_text.dart';
import '../../../l10n/display_text.dart';
import '../../../models/metric.dart';
import '../../../models/payloads.dart' show todayHeadlineOf;
import '../../../state/clock_format.dart' show formatClockOf;
import '../../../state/locale_controller.dart';
import '../../theme.dart' show C;
import '../sleep_planner.dart' show SleepPlan;

/// Read a metric envelope. `_scalarMetric` writes the literal string `'—'` for
/// an absent value, so this must never be replaced by `map['value'] as num`.
Metric metricOf(Object? raw) => Metric.parse(raw);

/// "72.4 kg" → `('72.4', 'kg')`.
(String, String) splitUnit(String s) {
  final i = s.lastIndexOf(' ');
  return i < 0 ? (s, '') : (s.substring(0, i), s.substring(i + 1));
}

/// WHICH SENSOR counted the steps, in the two words a card has room for — or
/// null when nothing counted (and on days derived before the ladder existed,
/// whose envelopes name no sensor).
String? stepSensorLabel(Metric m, [AppLocalizations? l]) {
  final used = m.inputsUsed;
  final strap = used.contains('band_pedometer_100hz') ||
      used.contains('band_step_counter');
  final phone = used.contains('phone_pedometer');
  if (strap && phone) return l?.homeStepSensorStrapPhone ?? 'Strap + phone';
  if (strap) return l?.homeStepSensorStrap ?? 'Strap';
  if (phone) return l?.homeStepSensorPhone ?? 'Phone';
  return null;
}

/// The inner object of an envelope whose `value` is a MAP, not a number.
Map<String, dynamic>? envValue(Object? raw) {
  if (raw is! Map) return null;
  final v = raw['value'];
  return v is Map ? v.cast<String, dynamic>() : null;
}

/// The night the overnight block in a `getToday()` result actually came from,
/// when that is NOT today's — otherwise null.
String? heldOverNightOf(Map<String, dynamic> today) {
  final st = today['status'];
  if (st is! Map) return null;
  return st['showing_prior_overnight'] == true
      ? st['overnight_day']?.toString()
      : null;
}

/// Why today has no overnight figures, or null when it has its own.
String? staleOvernightNote(Map<String, dynamic> today, [AppLocalizations? l]) {
  if (heldOverNightOf(today) == null) return null;
  final st = today['status'];
  return (st is Map ? st['overnight_state']?.toString() : null) == 'building'
      ? l?.homeOvernightBuilding ?? 'Last night is still being worked out.'
      : l?.homeOvernightNothingYet ??
          'Nothing from last night has reached the app yet.';
}

/// An overnight envelope, REFUSED when the night behind it is not today's.
Metric overnightMetric(Map<String, dynamic> today, Object? raw,
    [AppLocalizations? l]) {
  final why = staleOvernightNote(today, l);
  return why == null ? metricOf(raw) : Metric(note: why);
}

/// A scalar lifted out of an object-valued envelope, wearing that envelope's
/// honesty (tier, confidence, note).
Metric envMetric(Object? raw, num? scalar, {String? unit}) {
  final m = raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
  final env = Metric.parse({...m, 'value': scalar});
  return scalar == null && env.note == null
      ? Metric(unit: unit, note: m['note']?.toString())
      : Metric(
          value: scalar,
          unit: unit ?? env.unit,
          confidence: env.confidence,
          tier: env.tier,
          inputsUsed: env.inputsUsed,
          note: env.note,
        );
}

/// One stored chart point: `t` is epoch SECONDS, `v` the value.
typedef ChartPoint = ({int t, double v});

/// A `[{t, v}]` point list from `getChart`, timestamps INTACT.
List<ChartPoint> pointsOf(Object? chart) {
  final pts = chart is Map ? chart['points'] : null;
  if (pts is! List) return const [];
  return [
    for (final e in pts)
      if (e is Map && e['v'] is num && e['t'] is num)
        (t: (e['t'] as num).round(), v: (e['v'] as num).toDouble()),
  ];
}

/// The bare values of a point list, for statistics.
List<double> valuesOf(List<ChartPoint> pts) => [for (final p in pts) p.v];

/// [pts] laid out DENSE: one slot per calendar day, [days] slots long, ending today.
List<double?> denseDays(List<ChartPoint> pts, int days) {
  final out = List<double?>.filled(days, null);
  for (final p in pts) {
    final behind = daysBehind(p.t);
    if (behind == null || behind < 0 || behind >= days) continue;
    out[days - 1 - behind] = p.v;
  }
  return out;
}

/// A `[{t, v}]` point list from `getChart` as a plain series.
List<double> seriesOf(Object? chart) => valuesOf(pointsOf(chart));

/// An x-axis label for a stored point.
String axisDay(int? epochSec,
    {String todayWord = 'Today', String unitWord = 'days'}) {
  final behind = daysBehind(epochSec);
  if (behind == null) return '';
  if (behind <= 0) return todayWord;
  return '$behind $unitWord ago';
}

/// Whole calendar days between a stored point and today, or null when absent.
int? daysBehind(int? epochSec) {
  if (epochSec == null) return null;
  return calendarDaysBetween(
      DateTime.fromMillisecondsSinceEpoch(epochSec * 1000), DateTime.now());
}

/// The withheld-rollup reason inside a `getInsights()` result.
Map<String, dynamic>? staleReasonOf(Map<String, dynamic> insights) =>
    insights['stale'] is Map
        ? (insights['stale'] as Map).cast<String, dynamic>()
        : null;

String hm(num? minutes) {
  if (minutes == null) return '';
  final m = minutes.round();
  final l = lookupAppLocalizations(
    Locale(LocaleController.displayLanguageCode),
  );
  return m < 60
      ? l.supplementMinutesValue('$m')
      : l.supplementHoursMinutesValue(
          '${m ~/ 60}',
          (m % 60).toString().padLeft(2, '0'),
        );
}

String thousands(num? v) => v == null
    ? ''
    : NumberFormat.decimalPattern(
        LocaleController.displayLanguageCode,
      ).format(v.round());

/// A metric value at the precision its unit actually carries.
String metricValue(String unit, num? value) {
  if (value == null) return '';
  final v = value.toDouble();
  switch (unit) {
    case 'min':
      return hm(v);
    case 'steps':
    case 'kcal':
      return thousands(v);
    case 'bpm':
    case 'ms':
    case '%':
      return v.round().toString();
    case 'br/min':
    case '°':
      return displayFixed(v, 1);
  }
  if (v.abs() >= 100) return v.round().toString();
  if (v.abs() >= 10) return displayFixed(v, v == v.roundToDouble() ? 0 : 1);
  return displayFixed(v, 1);
}

String unitBeside(String unit) => unit == 'min'
    ? ''
    : localizedText(
        lookupAppLocalizations(Locale(LocaleController.displayLanguageCode)),
        unit,
      );

/// Minute-of-day → "10:40 PM".
String clock(num? minOfDay) =>
    minOfDay == null ? '' : formatMinuteOfDay(minOfDay.round());

/// Epoch seconds → "11:08 PM" / "23:08" in device zone.
String clockOfTs(num? ts) {
  if (ts == null) return '';
  return formatClockOf(DateTime.fromMillisecondsSinceEpoch(ts.round() * 1000));
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String monthName(int month, AppLocalizations? l) {
  if (l == null) return _months[month - 1];
  return [
    l.homeMonthJanuary, l.homeMonthFebruary, l.homeMonthMarch,
    l.homeMonthApril, l.homeMonthMay, l.homeMonthJune,
    l.homeMonthJuly, l.homeMonthAugust, l.homeMonthSeptember,
    l.homeMonthOctober, l.homeMonthNovember, l.homeMonthDecember,
  ][month - 1];
}

const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String monthShortName(int month, AppLocalizations? l) {
  if (l == null) return _monthsShort[month - 1];
  return [
    l.homeMonthJanuaryShort, l.homeMonthFebruaryShort, l.homeMonthMarchShort,
    l.homeMonthAprilShort, l.homeMonthMayShort, l.homeMonthJuneShort,
    l.homeMonthJulyShort, l.homeMonthAugustShort, l.homeMonthSeptemberShort,
    l.homeMonthOctoberShort, l.homeMonthNovemberShort, l.homeMonthDecemberShort,
  ][month - 1];
}

const _weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String weekdayShortName(int weekday, AppLocalizations? l) {
  if (l == null) return _weekdaysShort[weekday - 1];
  return [
    l.wellnessMon, l.wellnessTue, l.wellnessWed,
    l.wellnessThu, l.wellnessFri, l.wellnessSat, l.wellnessSun,
  ][weekday - 1];
}

/// 'YYYY-MM-DD' → "Saturday, 20 May".
String prettyDay(String? dayId, [AppLocalizations? l]) {
  final d = dayId == null ? null : DateTime.tryParse(dayId);
  if (d == null) return '';
  return localizedDate(
    d,
    l?.localeName ?? LocaleController.displayLanguageCode,
    weekday: true,
  );
}

/// The recovery dial's traffic light: green 67–99, yellow 34–66, red 1–33.
Color recoveryColor(num v) =>
    v >= 67 ? C.recGreen : (v >= 34 ? C.recYellow : C.recRed);

/// Minutes → "7:06".
String hMinutes(num minutes) {
  final m = minutes.round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

/// The readiness band.
({String label, Color color, int tier}) readinessBand(num? v,
    [AppLocalizations? l]) {
  if (v == null) {
    return (label: l?.homeReadinessNotScored ?? 'Not scored', color: C.n400, tier: -1);
  }
  if (v >= kReadinessGoodFrom) {
    return (label: l?.homeReadinessGoodToGo ?? 'Good to go', color: recoveryColor(v), tier: 3);
  }
  if (v >= kReadinessEasyBelow) {
    return (label: l?.homeReadinessSteady ?? 'Steady', color: recoveryColor(v), tier: 2);
  }
  if (v >= kReadinessRestBelow) {
    return (label: l?.homeReadinessTakeItEasy ?? 'Take it easy', color: recoveryColor(v), tier: 1);
  }
  return (label: l?.homeReadinessRestToday ?? 'Rest today', color: recoveryColor(v), tier: 0);
}

const driverLabels = {
  'hrv': 'HRV',
  'rhr': 'Resting heart rate',
  'resp': 'Breathing rate',
  'temp': 'Skin temperature',
};

String driverLabel(Object? key, [AppLocalizations? l]) {
  final k = key?.toString() ?? '';
  final known = switch (k) {
    'hrv' => l?.homeDriverHrv ?? driverLabels['hrv'],
    'rhr' => l?.homeDriverRhr ?? driverLabels['rhr'],
    'resp' => l?.homeDriverResp ?? driverLabels['resp'],
    'temp' => l?.homeDriverTemp ?? driverLabels['temp'],
    _ => null,
  };
  if (known != null) return known;
  if (k.isEmpty) return '';
  final words = k.replaceAll('_', ' ').trim();
  return words.isEmpty
      ? ''
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

/// Consecutive days with data, ending today or yesterday.
int streakOf(List<String> days, String today) {
  final have = days.toSet();
  var d = DateTime.tryParse(today);
  if (d == null) return 0;
  if (!have.contains(today)) d = DateTime(d.year, d.month, d.day - 1);
  var n = 0;
  while (have.contains(dayLabelOf(d!))) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// A day that has only just begun.
bool newDayNothingYet({
  required bool bare,
  required bool isToday,
  required bool hasHistory,
  required DateTime? lastData,
  required DateTime now,
}) =>
    bare &&
    isToday &&
    hasHistory &&
    lastData != null &&
    now.millisecondsSinceEpoch - lastData.millisecondsSinceEpoch <
        6 * 3600 * 1000;

/// HOME DATA: represents the parsed/materialized day payload for the Home screen.
class HomeData {
  final String? name;
  final String? dayId;
  final Metric readiness;
  final List<Map<String, dynamic>> drivers;
  final Metric sleepMin, rhr, steps, calories, caloriesTotal;
  final Metric strain;
  final int stepGoal;
  final Metric sleepNeedMin;
  final Metric bedtime;
  final SleepPlan plan;
  final Map<String, dynamic>? strainTarget;
  final Map<String, dynamic>? insightsStale;
  final String? heldOverNight;
  final String? illnessState;
  final String? illnessDay;
  final double? illnessZ;
  final Map<String, dynamic>? absentDiag;
  final String? recoveryState;
  final Map<String, dynamic>? readinessUpdate;

  const HomeData({
    this.name,
    this.dayId,
    this.readiness = Metric.empty,
    this.drivers = const [],
    this.sleepMin = Metric.empty,
    this.rhr = Metric.empty,
    this.steps = Metric.empty,
    this.calories = Metric.empty,
    this.caloriesTotal = Metric.empty,
    this.strain = Metric.empty,
    this.stepGoal = kDefaultStepGoal,
    this.sleepNeedMin = Metric.empty,
    this.bedtime = Metric.empty,
    this.plan = const SleepPlan(),
    this.strainTarget,
    this.heldOverNight,
    this.illnessState,
    this.illnessDay,
    this.illnessZ,
    this.insightsStale,
    this.absentDiag,
    this.recoveryState,
    this.readinessUpdate,
  });

  HomeData copyOrIllness(String? state, String? day, double? z) => HomeData(
        name: name,
        dayId: dayId,
        readiness: readiness,
        drivers: drivers,
        sleepMin: sleepMin,
        rhr: rhr,
        steps: steps,
        calories: calories,
        caloriesTotal: caloriesTotal,
        strain: strain,
        stepGoal: stepGoal,
        sleepNeedMin: sleepNeedMin,
        bedtime: bedtime,
        plan: plan,
        strainTarget: strainTarget,
        heldOverNight: heldOverNight,
        illnessState: state,
        illnessDay: day,
        illnessZ: z,
        insightsStale: insightsStale,
        absentDiag: absentDiag,
        recoveryState: recoveryState,
        readinessUpdate: readinessUpdate,
      );

  static Future<HomeData> loadForDay(LocalRepository repo, String date,
      [AppLocalizations? l]) async {
    final profile = await repo.getProfile();
    final overview = await repo.getDayOverview(date);
    final strain = await repo.getDayStrain(date);
    final sleep = await repo.getDaySleepV2(date);
    final readiness = metricOf(overview['readiness']);
    final absentDiag = readiness.value != null
        ? null
        : await LocalDb.readinessAbsentDiag(date);
    return HomeData(
      name: profile['name']?.toString(),
      dayId: date,
      readiness: readiness,
      absentDiag: absentDiag,
      rhr: metricOf(overview['resting_hr']),
      strain: metricOf(strain['strain']),
      steps: metricOf(strain['steps']),
      calories: metricOf(strain['calories']),
      caloriesTotal: metricOf(strain['calories_total']),
      sleepMin: metricOf(sleep['duration_min']),
      stepGoal: (profile['step_goal'] as num?)?.toInt() ?? kDefaultStepGoal,
    );
  }

  static Future<HomeData> load(LocalRepository repo, [AppLocalizations? l]) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final profile = await repo.getProfile();

    final daily = today['daily'];
    final sleep = today['sleep'];
    Object? d(String k) => daily is Map ? daily[k] : null;
    Object? s(String k) => sleep is Map ? sleep[k] : null;

    final gb = cd['readiness_glassbox'];
    final gbDrivers = gb is Map ? gb['drivers'] : null;

    final coach = cd['sleep_coach'];
    final needEnv = coach is Map ? coach['need'] : null;
    final bedEnv = coach is Map ? coach['bedtime'] : null;
    final needSec = (envValue(needEnv)?['need_sec'] as num?);

    final strain = today['coach'];

    final heldOver = heldOverNightOf(today);
    final illness = today['illness'];

    final head = todayHeadlineOf(today);
    final recoveryState = head['recovery_state'] as String?;
    final readiness = recoveryState == 'provisional'
        ? metricOf(d('readiness_provisional'))
        : overnightMetric(today, d('readiness'), l);
    final absentDiag = readiness.value != null
        ? null
        : await LocalDb.readinessAbsentDiag(
            (today['status'] as Map?)?['today_day']?.toString());

    return HomeData(
      name: profile['name']?.toString(),
      dayId: (today['status'] as Map?)?['today_day']?.toString(),
      heldOverNight: heldOver,
      illnessState: illness is Map ? illness['state']?.toString() : null,
      illnessDay: illness is Map ? illness['date']?.toString() : null,
      illnessZ: illness is Map ? (illness['z'] as num?)?.toDouble() : null,
      readiness: readiness,
      absentDiag: absentDiag,
      recoveryState: recoveryState,
      readinessUpdate: (head['recovery_update'] as Map?)?.cast<String, dynamic>(),
      drivers: [
        for (final e in (gbDrivers is List ? gbDrivers : const []))
          if (e is Map) e.cast<String, dynamic>(),
      ],
      strain: metricOf(d('strain')),
      sleepMin: today['sleep_provisional'] is Map
          ? metricOf((today['sleep_provisional'] as Map)['duration_min'])
          : overnightMetric(today, s('duration_min'), l),
      rhr: overnightMetric(today, d('resting_hr'), l),
      steps: metricOf(d('steps')),
      calories: metricOf(d('calories')),
      caloriesTotal: metricOf(d('calories_total')),
      stepGoal: (today['step_goal'] as num?)?.toInt() ?? kDefaultStepGoal,
      sleepNeedMin: envMetric(needEnv, needSec == null ? null : needSec / 60,
          unit: 'min'),
      bedtime: envMetric(
          bedEnv, envValue(bedEnv)?['bedtime_min_of_day'] as num?),
      strainTarget: strain is Map && strain['strain_target'] is Map
          ? (strain['strain_target'] as Map).cast<String, dynamic>()
          : null,
      plan: SleepPlan.of(cd),
      insightsStale: staleReasonOf(cd),
    );
  }
}
