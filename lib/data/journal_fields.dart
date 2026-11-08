// The numeric half of a journal entry — the vocabulary, not the storage.
//
// `journal` holds a tag set and a note, which can only ever answer "did this
// happen today". These fields carry a NUMBER, and the number is usually the
// question: one coffee and five coffees are not the same day, and a tag cannot
// tell them apart.
//
// Built-in fields live in [kJournalFields] as a plain constant table, the same
// shape as the workout-type table — extend it HERE, never with a local map in
// a screen. User-invented fields carry their own [JournalFieldSpec] loaded
// from the database, so a custom field behaves exactly like a built-in one
// everywhere downstream.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../state/clock_format.dart';
import 'day_label.dart';

/// What a field measures, which decides how it is entered and read back.
enum JournalFieldKind {
  /// A subjective 1–5 self-report (mood, sleep quality). Ordinal: the gap
  /// between 3 and 4 is not claimed to equal the gap between 4 and 5, which is
  /// exactly why the correlation over these is rank-based.
  rating,

  /// A physical quantity with a unit (ml, mg, units).
  dose,

  /// Minutes.
  duration,
}

/// One day's value for one field.
@immutable
class JournalMetricValue {
  const JournalMetricValue(this.value, {this.atMinuteOfDay});

  /// The day's total for a dose, or the day's single reading for a rating.
  final double value;

  /// Local minutes past midnight for the LATEST occurrence, or null when the
  /// field has no meaningful time. Held because when a dose landed often
  /// matters more than how big it was — the sleep-relevant fact about caffeine
  /// is the last cup, not the total.
  final int? atMinuteOfDay;

  @override
  bool operator ==(Object other) =>
      other is JournalMetricValue &&
      other.value == value &&
      other.atMinuteOfDay == atMinuteOfDay;

  @override
  int get hashCode => Object.hash(value, atMinuteOfDay);

  @override
  String toString() => 'JournalMetricValue($value, at: $atMinuteOfDay)';
}

@immutable
class JournalFieldSpec {
  const JournalFieldSpec({
    required this.key,
    required this.label,
    required this.kind,
    required this.unit,
    required this.max,
    required this.step,
    this.hasTime = false,
    this.custom = false,
  });

  /// Stored `field` value. Lowercase and stable — renaming one orphans its
  /// history, so labels change freely and keys never do.
  final String key;
  final String label;
  final JournalFieldKind kind;

  /// Shown after the number; empty for ratings.
  final String unit;

  /// Entry ceiling. Not a physiological claim — it exists so a slip on a
  /// stepper cannot enter 40 coffees and quietly dominate every correlation
  /// that field appears in.
  final double max;

  /// Increment for one tap of the stepper.
  final double step;

  /// Whether the field offers a "last one at" time.
  final bool hasTime;

  /// User-invented rather than built in.
  final bool custom;

  bool get isRating => kind == JournalFieldKind.rating;

  /// A per-day yes or no: 1 for yes, 0 for no, nothing for not answered. The
  /// habit shape the wellness tab has always written (a ceiling of one, a step
  /// of one, no unit), so the catalogue's yes/no behaviors and a habit typed in
  /// by hand are the same thing everywhere downstream.
  bool get isYesNo => max == 1 && step == 1 && unit.isEmpty;

  /// Human-readable value, without the unit.
  String format(double v) {
    if (isYesNo) return v >= 1 ? 'Yes' : 'No';
    if (isRating) return v.round().toString();
    // Doses are entered on whole steps, so a trailing .0 is noise.
    return v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(1);
  }

  String formatWithUnit(double v) =>
      unit.isEmpty ? format(v) : '${format(v)} $unit';
}

/// The built-in fields, in the order the editor shows them.
///
/// Ratings run 1–5 rather than 1–10: a ten-point self-report is not ten
/// distinguishable states, and the extra resolution is noise that a rank
/// correlation then has to see through.
const kJournalFields = <JournalFieldSpec>[
  JournalFieldSpec(
    key: 'mood',
    label: 'Mood',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'sleep_quality',
    label: 'Sleep quality',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'energy',
    label: 'Energy',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'stress',
    label: 'Stress',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'soreness',
    label: 'Soreness',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'water_ml',
    label: 'Water',
    kind: JournalFieldKind.dose,
    unit: 'ml',
    max: 6000,
    step: 250,
  ),
  // Caffeine is the field the timing support exists for. A 200 mg morning
  // coffee and a 200 mg evening one are the same dose and a completely
  // different night, and collapsing them loses the only part that predicts
  // anything.
  JournalFieldSpec(
    key: 'caffeine_mg',
    label: 'Caffeine',
    kind: JournalFieldKind.dose,
    unit: 'mg',
    max: 1000,
    step: 25,
    hasTime: true,
  ),
  JournalFieldSpec(
    key: 'alcohol_units',
    label: 'Alcohol',
    kind: JournalFieldKind.dose,
    unit: 'units',
    max: 20,
    step: 1,
    hasTime: true,
  ),
  JournalFieldSpec(
    key: 'screens_min',
    label: 'Screens before bed',
    kind: JournalFieldKind.duration,
    unit: 'min',
    max: 480,
    step: 15,
  ),
  // MT-03 — WEIGHT AS A SERIES, not a profile field.
  //
  // HealthKit/Health Connect WEIGHT is read once at profile import and
  // collapsed to a single scalar, so Mifflin BMR is pinned to whatever you
  // weighed on install day forever. `journal_metric` is already (date, field,
  // value) with a field-first index and CSV export, so this one row gets
  // storage, editor, chart and correlation without a table.
  //
  // ENTERED, NEVER MEASURED, and labelled that way wherever it appears. Read
  // the ceiling before building anything on it: this is the most
  // eating-disorder-adjacent surface in the app and it must never EMIT.
  //   * Render [weightTrendEwma], NOT the raw readings — day-to-day scale
  //     noise is water and glycogen at ±1-2 kg and a raw line makes that read
  //     as change.
  //   * Show gaps. Never interpolate one.
  //   * No goal weight, no daily prompt, no red/green, no "you gained"
  //     notification, no body fat, no lean mass, no metabolic age.
  //   * BMR keeps reading the onboarding scalar for now — see the note on
  //     [weightTrendEwma].
  JournalFieldSpec(
    key: 'weight_kg',
    label: 'Weight',
    kind: JournalFieldKind.dose,
    unit: 'kg',
    max: 400,
    step: 0.1,
  ),
];

/// Half-life of the weight trend, in days.
///
/// A week is long enough that a salty dinner does not move the line and short
/// enough that a real four-week change is visible by the end of it.
const double kWeightTrendHalfLifeDays = 7;

/// The EWMA trend through a set of dated weight readings — THE thing to draw.
///
/// [byDay] is keyed by 'YYYY-MM-DD'. The output has one entry per day that
/// actually had a reading, in date order: gaps stay gaps, because a smoothed
/// line drawn across a fortnight nobody weighed is a fortnight of invented
/// data. The decay is by ELAPSED DAYS, not by position in the list, so two
/// readings a month apart do not smooth into each other the way two
/// consecutive ones do.
///
/// NOT WIRED TO BMR, deliberately. Changing the BMR input recomputes every
/// historical calorie number in the app, so that lands on its own commit where
/// a regression is attributable. And the calorie-model calibration from a
/// weight-drift residual is DROPPED, not deferred: the noise band on a weekly
/// delta (~±1 kg) is several times the signal a 2 400 kcal weekly imbalance
/// produces (~0.3 kg), so "your balance says −2 400 and you didn't move, so
/// the model is off for you" would be false more often than true.
Map<String, double> weightTrendEwma(
  Map<String, double> byDay, {
  double halfLifeDays = kWeightTrendHalfLifeDays,
}) {
  final days = byDay.keys.toList()..sort();
  final out = <String, double>{};
  double? ewma;
  DateTime? prev;
  for (final day in days) {
    final d = DateTime.tryParse(day);
    final v = byDay[day];
    if (d == null || v == null || !v.isFinite) continue;
    if (ewma == null || prev == null) {
      ewma = v;
    } else {
      // Calendar days: a spring-forward day is 23 h, which inDays floors to 0
      // and gives the new reading no weight at all.
      final gap =
          calendarDaysBetween(prev, d).abs().clamp(0, 3650).toDouble();
      // Weight of the new reading after `gap` days of decay. One day at a
      // 7-day half-life is ~0.094; a month is ~0.95, i.e. after a long gap the
      // trend restarts from the reading rather than dragging the old one in.
      final w = 1 - math.pow(0.5, gap / halfLifeDays).toDouble();
      ewma = ewma + w * (v - ewma);
    }
    prev = d;
    out[day] = ewma;
  }
  return out;
}

/// Built-ins by key, for a lookup that does not walk the list.
final Map<String, JournalFieldSpec> kJournalFieldsByKey = {
  for (final f in kJournalFields) f.key: f,
};

/// Resolve a stored field key to its spec, preferring built-ins.
///
/// Returns null for a key with no definition at all — a field whose custom
/// definition was deleted while its history remained. Callers must render
/// those as raw values rather than inventing a unit for them.
JournalFieldSpec? journalFieldSpec(
  String key, {
  List<JournalFieldSpec> custom = const [],
}) {
  final builtIn = kJournalFieldsByKey[key] ?? kJournalBehaviorFieldsByKey[key];
  if (builtIn != null) return builtIn;
  for (final c in custom) {
    if (c.key == key) return c;
  }
  return null;
}

/// A stable storage key for a user-invented field name.
///
/// Prefixed so a custom field can never collide with a built-in one, present
/// or future: adding `magnesium` to [kJournalFields] later must not silently
/// adopt somebody's existing custom column and reinterpret its units.
String customJournalFieldKey(String label) {
  final slug = label
      .toLowerCase()
      // Any script's letters/digits (and combining marks, which Devanagari
      // vowels are). ASCII-only collapsed every non-Latin name to `custom_`.
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'custom_$slug';
}

/// Local minutes past midnight → "7:05 AM" or "07:05", per the user's clock
/// format ([formatClockMinute]).
String formatMinuteOfDay(int minuteOfDay) => formatClockMinute(minuteOfDay);

// ══════════════════════════ THE BEHAVIOR CATALOGUE ══════════════════════════
//
// What the journal can ask, grouped the way the SELECT BEHAVIORS sheet tabs
// it. An entry either names a field above (Mood, Caffeine, Weight — the
// number stays the number) or is a yes/no of its own, stored like a habit:
// 1 for yes, 0 for no, nothing for not answered. Keys never change; names and
// questions may. Generic names only — no product or brand is a behavior.

/// The sheet's tabs after All, in order. [custom] holds what the user wrote.
enum JournalBehaviorCategory {
  custom('Custom Behaviors'),
  drugs('Drugs & Medication'),
  hormonal('Hormonal Health'),
  lifestyle('Lifestyle'),
  mental('Mental Wellbeing'),
  nutrition('Nutrition'),
  recovery('Recovery'),
  sleep('Sleep'),
  training('Training');

  const JournalBehaviorCategory(this.label);
  final String label;
}

/// One thing the journal can ask.
@immutable
class JournalBehavior {
  const JournalBehavior(
    this.key,
    this.name,
    this.question,
    this.category, {
    this.tag,
  });

  /// The `journal_metric` field it writes.
  final String key;
  final String name;
  final String question;
  final JournalBehaviorCategory category;

  /// The preset journal tag that meant the same thing before this catalogue
  /// existed. Answering the question keeps the tag in step, so the tag's
  /// history and everything reading tags carry on without a seam.
  final String? tag;

  /// A user-written field as a catalogue entry: its name is its question.
  factory JournalBehavior.custom(JournalFieldSpec spec) => JournalBehavior(
        spec.key,
        spec.label,
        spec.isYesNo
            ? (spec.label.endsWith('?') ? spec.label : '${spec.label}?')
            : spec.label,
        JournalBehaviorCategory.custom,
      );
}

const _d = JournalBehaviorCategory.drugs;
const _h = JournalBehaviorCategory.hormonal;
const _l = JournalBehaviorCategory.lifestyle;
const _m = JournalBehaviorCategory.mental;
const _n = JournalBehaviorCategory.nutrition;
const _r = JournalBehaviorCategory.recovery;
const _s = JournalBehaviorCategory.sleep;
const _t = JournalBehaviorCategory.training;

/// Every built-in behavior. A `bhv_` key is a yes/no; any other key is one of
/// [kJournalFields].
const kJournalBehaviors = <JournalBehavior>[
  // Drugs & Medication
  JournalBehavior('bhv_adhd_meds', 'ADHD Medication', 'Took ADHD medication?', _d),
  JournalBehavior('bhv_antidepressant', 'Antidepressant', 'Took an antidepressant?', _d),
  JournalBehavior('bhv_antihistamine', 'Antihistamine', 'Took an antihistamine?', _d),
  JournalBehavior('bhv_antibiotics', 'Antibiotics', 'Took antibiotics?', _d),
  JournalBehavior('bhv_blood_pressure_meds', 'Blood Pressure Medication', 'Took blood pressure medication?', _d),
  JournalBehavior('bhv_cannabis', 'Cannabis', 'Used cannabis?', _d),
  JournalBehavior('bhv_creatine', 'Creatine', 'Took creatine?', _d),
  JournalBehavior('bhv_electrolytes', 'Electrolytes', 'Had electrolytes?', _d),
  JournalBehavior('bhv_inhaler', 'Inhaler', 'Used an inhaler?', _d),
  JournalBehavior('bhv_magnesium', 'Magnesium', 'Took magnesium?', _d),
  JournalBehavior('bhv_meds', 'Medication', 'Took medication?', _d, tag: 'meds'),
  JournalBehavior('bhv_melatonin', 'Melatonin', 'Took melatonin?', _d),
  JournalBehavior('bhv_multivitamin', 'Multivitamin', 'Took a multivitamin?', _d),
  JournalBehavior('bhv_nicotine', 'Nicotine', 'Used nicotine?', _d),
  JournalBehavior('bhv_omega3', 'Omega-3', 'Took omega-3 or fish oil?', _d),
  JournalBehavior('bhv_pain_reliever', 'Pain Reliever', 'Took a pain reliever?', _d),
  JournalBehavior('bhv_protein_supplement', 'Protein Supplement', 'Had a protein shake?', _d),
  JournalBehavior('bhv_sleep_aid', 'Sleep Aid', 'Took a sleep aid?', _d),
  JournalBehavior('bhv_vitamin_d', 'Vitamin D', 'Took vitamin D?', _d),
  // Hormonal Health
  JournalBehavior('bhv_birth_control', 'Hormonal Birth Control', 'Took hormonal birth control?', _h),
  JournalBehavior('bhv_breastfeeding', 'Breastfeeding', 'Breastfed or pumped?', _h),
  JournalBehavior('bhv_cramps', 'Menstrual Cramps', 'Had menstrual cramps?', _h),
  JournalBehavior('bhv_hormone_therapy', 'Hormone Therapy', 'Took hormone therapy?', _h),
  JournalBehavior('bhv_hot_flashes', 'Hot Flashes', 'Had hot flashes?', _h),
  JournalBehavior('bhv_ovulation', 'Ovulation', 'Ovulating today?', _h),
  JournalBehavior('bhv_period', 'Period', 'On your period?', _h),
  JournalBehavior('bhv_pms', 'PMS Symptoms', 'Had PMS symptoms?', _h),
  JournalBehavior('bhv_sexual_activity', 'Sexual Activity', 'Were you sexually active?', _h),
  // Lifestyle
  JournalBehavior('bhv_air_travel', 'Air Travel', 'Traveled on a plane?', _l),
  JournalBehavior('alcohol_units', 'Alcohol', 'How many drinks did you have?', _l),
  JournalBehavior('bhv_blood_donation', 'Blood Donation', 'Donated blood?', _l),
  JournalBehavior('bhv_camping', 'Camping', 'Camped outdoors?', _l),
  JournalBehavior('bhv_car_train', 'Car or Train Travel', 'Traveled by car or train?', _l),
  JournalBehavior('bhv_caregiving', 'Caregiving', 'Cared for someone?', _l),
  JournalBehavior('bhv_long_commute', 'Long Commute', 'Had a long commute?', _l),
  JournalBehavior('bhv_outdoors', 'Outdoor Time', 'Spent time outdoors?', _l),
  JournalBehavior('bhv_pets', 'Time with Pets', 'Spent time with a pet?', _l),
  JournalBehavior('bhv_reading', 'Reading', 'Read a book?', _l),
  JournalBehavior('bhv_sedentary', 'Sedentary Day', 'Sat for most of the day?', _l),
  JournalBehavior('bhv_social', 'Social Time', 'Spent time with friends or family?', _l, tag: 'social'),
  JournalBehavior('bhv_sunlight', 'Morning Sunlight', 'Got sunlight in the morning?', _l),
  JournalBehavior('bhv_travel', 'Travel', 'Traveled away from home?', _l, tag: 'travel'),
  JournalBehavior('bhv_video_games', 'Video Games', 'Played video games?', _l),
  JournalBehavior('weight_kg', 'Weight', 'What did you weigh?', _l),
  JournalBehavior('bhv_work_from_home', 'Worked from Home', 'Worked from home?', _l),
  JournalBehavior('bhv_worked_late', 'Worked Late', 'Worked late?', _l),
  // Mental Wellbeing
  JournalBehavior('bhv_anxiety', 'Anxiety', 'Felt nervous or anxious?', _m),
  JournalBehavior('bhv_breathwork', 'Breathwork', 'Did breathwork?', _m),
  JournalBehavior('bhv_conflict', 'Conflict', 'Had an argument or conflict?', _m),
  JournalBehavior('bhv_control', 'In Control', 'Felt in control of your day?', _m),
  JournalBehavior('bhv_deadline', 'Deadline', 'Worked to a deadline?', _m),
  JournalBehavior('bhv_down', 'Feeling Down', 'Felt down or low?', _m),
  JournalBehavior('bhv_flow', 'Flow State', 'Lost track of time doing something?', _m),
  JournalBehavior('bhv_gratitude', 'Gratitude', 'Practiced gratitude?', _m),
  JournalBehavior('bhv_journaling', 'Journaling', 'Wrote down your thoughts?', _m),
  JournalBehavior('bhv_lonely', 'Loneliness', 'Felt lonely?', _m),
  JournalBehavior('bhv_meditation', 'Meditation', 'Meditated?', _m),
  JournalBehavior('mood', 'Mood', 'How was your mood?', _m),
  JournalBehavior('stress', 'Stress', 'How stressed were you?', _m),
  JournalBehavior('bhv_therapy', 'Therapy', 'Went to therapy?', _m),
  // Nutrition
  JournalBehavior('bhv_added_sugar', 'Added Sugar', 'Had added sugar?', _n),
  JournalBehavior('bhv_breakfast', 'Breakfast', 'Ate breakfast?', _n),
  JournalBehavior('caffeine_mg', 'Caffeine', 'How much caffeine did you have?', _n),
  JournalBehavior('bhv_dairy', 'Dairy', 'Had dairy?', _n),
  JournalBehavior('bhv_energy_drink', 'Energy Drink', 'Had an energy drink?', _n),
  JournalBehavior('bhv_fasting', 'Fasting', 'Went 14 hours or more without eating?', _n),
  JournalBehavior('bhv_fast_food', 'Fast Food', 'Ate fast food?', _n),
  JournalBehavior('bhv_fruit_veg', 'Fruit and Vegetables', 'Ate fruit and vegetables?', _n),
  JournalBehavior('bhv_gluten', 'Gluten', 'Had gluten?', _n),
  JournalBehavior('bhv_hydrated', 'Hydration', 'Felt well hydrated?', _n),
  JournalBehavior('bhv_large_dinner', 'Large Dinner', 'Had a large dinner?', _n),
  JournalBehavior('bhv_late_caffeine', 'Late Caffeine', 'Had caffeine after 2 PM?', _n),
  JournalBehavior('bhv_late_meal', 'Late Meal', 'Ate within two hours of bed?', _n, tag: 'late meal'),
  JournalBehavior('bhv_morning_snack', 'Morning Snack', 'Snacked before lunch?', _n),
  JournalBehavior('bhv_plant_based', 'Plant-Based Day', 'Ate only plant-based food?', _n),
  JournalBehavior('bhv_processed_food', 'Processed Food', 'Ate processed food?', _n),
  JournalBehavior('bhv_red_meat', 'Red Meat', 'Ate red meat?', _n),
  JournalBehavior('bhv_spicy_food', 'Spicy Food', 'Ate spicy food?', _n),
  JournalBehavior('water_ml', 'Water', 'How much water did you drink?', _n),
  // Recovery
  JournalBehavior('bhv_allergies', 'Allergies', 'Had allergy symptoms?', _r),
  JournalBehavior('bhv_cold', 'Cold Exposure', 'Took a cold plunge or cold shower?', _r, tag: 'cold plunge'),
  JournalBehavior('energy', 'Energy', 'How was your energy?', _r),
  JournalBehavior('bhv_foam_rolling', 'Foam Rolling', 'Foam rolled?', _r),
  JournalBehavior('bhv_headache', 'Headache', 'Had a headache?', _r),
  JournalBehavior('bhv_hot_bath', 'Hot Bath', 'Took a hot bath?', _r),
  JournalBehavior('bhv_sick', 'Illness', 'Felt sick?', _r, tag: 'sick'),
  JournalBehavior('bhv_injury', 'Injury', 'Dealt with an injury?', _r),
  JournalBehavior('bhv_massage', 'Massage', 'Got a massage?', _r),
  JournalBehavior('bhv_nap', 'Nap', 'Took a nap?', _r),
  JournalBehavior('bhv_recovered', 'Recovery', 'Felt recovered?', _r),
  JournalBehavior('bhv_rest_day', 'Rest Day', 'Took a rest day?', _r, tag: 'rest day'),
  JournalBehavior('bhv_sauna', 'Sauna', 'Used a sauna?', _r, tag: 'sauna'),
  JournalBehavior('soreness', 'Soreness', 'How sore were you?', _r),
  JournalBehavior('bhv_stretching', 'Stretching', 'Stretched?', _r),
  // Sleep
  JournalBehavior('bhv_alarm', 'Alarm', 'Woke up to an alarm?', _s),
  JournalBehavior('bhv_cool_room', 'Cool Bedroom', 'Slept in a cool room?', _s),
  JournalBehavior('bhv_usual_bedtime', 'Usual Bedtime', 'Went to bed at your usual time?', _s),
  JournalBehavior('bhv_earplugs', 'Earplugs', 'Slept with earplugs?', _s),
  JournalBehavior('bhv_eye_mask', 'Eye Mask', 'Wore an eye mask?', _s),
  JournalBehavior('bhv_late_night', 'Late Night', 'Stayed up past midnight?', _s),
  JournalBehavior('bhv_mouth_tape', 'Mouth Tape', 'Taped your mouth for sleep?', _s),
  JournalBehavior('bhv_read_before_bed', 'Read Before Bed', 'Read before bed?', _s),
  JournalBehavior('bhv_shared_bed', 'Shared Bed', 'Shared your bed?', _s),
  JournalBehavior('sleep_quality', 'Sleep Quality', 'How well did you sleep?', _s),
  JournalBehavior('bhv_screen_in_bed', 'Screen Time in Bed', 'Used a screen in bed?', _s, tag: 'screens late'),
  JournalBehavior('screens_min', 'Screens Before Bed', 'How long on screens before bed?', _s),
  JournalBehavior('bhv_white_noise', 'White Noise', 'Slept with white noise?', _s),
  JournalBehavior('bhv_woke_at_night', 'Woke at Night', 'Woke up during the night?', _s),
  // Training
  JournalBehavior('bhv_active_commute', 'Active Commute', 'Walked or cycled to get somewhere?', _t),
  JournalBehavior('bhv_cardio', 'Cardio', 'Did cardio?', _t),
  JournalBehavior('bhv_evening_workout', 'Evening Workout', 'Trained after 6 PM?', _t),
  JournalBehavior('bhv_hard_workout', 'Hard Workout', 'Pushed hard in a workout?', _t),
  JournalBehavior('bhv_mobility', 'Mobility', 'Did mobility work?', _t),
  JournalBehavior('bhv_morning_workout', 'Morning Workout', 'Trained before noon?', _t),
  JournalBehavior('bhv_sport', 'Sport', 'Played a sport?', _t),
  JournalBehavior('bhv_strength', 'Strength Training', 'Did strength training?', _t),
  JournalBehavior('bhv_walk', 'Walk', 'Went for a walk?', _t),
  JournalBehavior('bhv_workout', 'Workout', 'Worked out?', _t, tag: 'workout'),
  JournalBehavior('bhv_yoga', 'Yoga', 'Did yoga?', _t),
];

/// Catalogue entries by key.
final Map<String, JournalBehavior> kJournalBehaviorsByKey = {
  for (final b in kJournalBehaviors) b.key: b,
};

/// The spec behind every yes/no catalogue entry — the habit shape.
final Map<String, JournalFieldSpec> kJournalBehaviorFieldsByKey = {
  for (final b in kJournalBehaviors)
    if (!kJournalFieldsByKey.containsKey(b.key))
      b.key: JournalFieldSpec(
        key: b.key,
        label: b.name,
        kind: JournalFieldKind.rating,
        unit: '',
        max: 1,
        step: 1,
      ),
};

/// What a journal shows before its owner has picked anything: one question of
/// each kind it can ask.
const kJournalStarterBehaviors = [
  'mood',
  'bhv_late_meal',
  'caffeine_mg',
  'alcohol_units',
  'bhv_screen_in_bed',
  'bhv_outdoors',
];

/// The catalogue entry that a preset journal tag now answers to, if any.
JournalBehavior? journalBehaviorForTag(String tag) {
  for (final b in kJournalBehaviors) {
    if (b.tag == tag) return b;
  }
  return null;
}

/// Questions about the night that ended on the morning they are asked, whose
/// answer lands on that same morning's Recovery rather than the next one.
const kJournalSameMorning = {'bhv_alarm', 'bhv_woke_at_night', 'bhv_recovered'};
