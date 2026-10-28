// The activity vocabulary — ~70 things a person actually does, in eight
// groups, each carrying a published MET value except the one row that names
// no activity at all.
//
// Why MET and not a made-up "intensity": a calorie figure has to come from
// somewhere, and "somewhere" is Ainsworth et al., Compendium of Physical
// Activities (2011 update, Med Sci Sports Exerc 43(8):1575-81). The arithmetic
// is one line — kcal = MET × 3.5 × kg / 200 × minutes — and it needs body
// weight, which the app may not have. So [Activity.kcal] returns null rather
// than a number, and the screens say so. A fabricated calorie count is worse
// than no calorie count, because it looks the same as a measured one.
//
// The app's stored workout vocabulary is the free-form `sessions.type` TEXT
// column, so this table needs no schema of its own: [byName] maps a stored
// type back to its entry, and an unknown type simply falls through to null.

import 'package:flutter/widgets.dart';
import '../lucide.dart';

import '../../l10n/app_localizations.dart';
import '../theme.dart';

part 'wger_exercises.g.dart';
part 'free_exercises.g.dart';

/// How a session is tracked — which decides which live screen it opens, and
/// therefore which parameters the user is asked for.
enum Track {
  /// Strength — reps, load, rest. Entered, never measured.
  sets,

  /// Running, cycling, swimming, rowing — distance and pace.
  distance,

  /// Sports and classes — anything simply timed.
  duration,

  /// HIIT, circuits, tabata — work/rest rounds.
  interval,

  /// Yoga, stretching, breathwork — time, breath, stillness.
  stillness,
}

class Activity {
  final String name;
  final IconData icon;
  final Color color;
  final Track track;

  /// Metabolic equivalent of task — the honest basis for a calorie estimate.
  /// Compendium of Physical Activities, Ainsworth et al.
  ///
  /// NULL for a row the compendium cannot price. 'General workout' means the
  /// user did not say what they did, and the compendium prices named
  /// activities; 'Padel' is named but has no compendium row at all. Every number that could go here
  /// would be a stand-in — which is the 'Custom activity' mistake below,
  /// whose MET of 4.0 was invented. So [kcal] returns null, the picker and
  /// the setup screen show no estimate, and the session still gets a REAL
  /// calorie figure afterwards: the post-session estimator in
  /// `compute/manual_session.dart` works from heart rate and never reads a
  /// MET. The guess is what is missing, not the calories.
  final double? met;

  /// Whether a route is worth recording. GPS activities get the map.
  final bool gps;

  /// Defaults the session's privacy toggle on. Not a different kind of
  /// activity — a different default, which the user can flip either way.
  final bool private;

  /// Locomotion on foot, so the strap's 100 Hz pedometer may count its steps.
  ///
  /// NOT the same question as [gps] — cycling records a route and takes no
  /// steps; a treadmill takes steps and records nothing. Default false: an
  /// activity is only gait when someone has said so, because the failure is
  /// silent and expensive. Wrist step error is UNBOUNDED ABOVE on rhythmic arm
  /// work (OxWalk: +199.5% worst case at the wrist against +5.3% at the hip),
  /// so rowing or boxing admitted here would bank hundreds of steps nobody
  /// took. `kGaitStepTypeKeys` is derived from this flag and pinned to it in
  /// both directions by test/gait_step_types_test.dart.
  final bool gait;

  const Activity(this.name, this.icon, this.color, this.track, this.met,
      {this.gps = false, this.private = false, this.gait = false});

  /// kcal = MET × 3.5 × kg / 200 × minutes.
  ///
  /// Null when body weight is unknown, and null when the activity carries no
  /// MET. There is no default for either: both numbers would be
  /// indistinguishable from a real one on screen.
  int? kcal(double? kg, int minutes) => kg == null || kg <= 0 || met == null
      ? null
      : (met! * 3.5 * kg / 200 * minutes).round();

  /// The stored `sessions.type` for this activity.
  String get typeKey => name.toLowerCase().replaceAll(' ', '_');

  /// Localized display only; stored names and keys remain unchanged.
  String displayName(BuildContext c) => localizedName(AppLocalizations.of(c));

  String localizedName(AppLocalizations? l) => catalogueName(l, name);
}

class ActGroup {
  final String name;
  final IconData icon;
  final List<Activity> items;
  const ActGroup(this.name, this.icon, this.items);

  String displayName(BuildContext c) => localizedName(AppLocalizations.of(c));

  String localizedName(AppLocalizations? l) => catalogueName(l, name);
}

String catalogueName(AppLocalizations? l, String name) =>
    l?.activityCatalogueName(
      'k${name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '')}',
      name,
    ) ??
    name;

const activityLibrary = <ActGroup>[
  ActGroup('Cardio', LucideIcons.heartPulse, [
    Activity('Running', LucideIcons.footprints, C.dialStrain, Track.distance, 9.8,
        gps: true, gait: true),
    Activity(
        'Trail running', LucideIcons.mountain, C.dialStrain, Track.distance, 10.5,
        gps: true, gait: true),
    Activity('Walking', LucideIcons.footprints, C.dialStrain, Track.distance, 3.5,
        gps: true, gait: true),
    Activity('Hiking', LucideIcons.mountainSnow, C.dialStrain, Track.distance, 6.0,
        gps: true, gait: true),
    Activity('Cycling', LucideIcons.bike, C.dialStrain, Track.distance, 8.0,
        gps: true),
    Activity('Indoor bike', LucideIcons.bike, C.dialStrain, Track.duration, 7.0),
    Activity('Rowing', LucideIcons.sailboat, C.dialStrain, Track.distance, 7.0),
    Activity('Swimming', LucideIcons.waves, C.dialStrain, Track.distance, 8.3),
    Activity('Elliptical', LucideIcons.activity, C.dialStrain, Track.duration, 5.0),
    Activity(
        'Stair climber', LucideIcons.trendingUp, C.dialStrain, Track.duration, 9.0),
    // Tracked by duration, not distance: a treadmill belt reports nothing to
    // this app and a wrist cannot measure indoor distance, so the session is
    // its heart rate and its clock.
    Activity('Treadmill', LucideIcons.footprints, C.dialStrain, Track.duration, 8.3, gait: true),
    Activity('Jump rope', LucideIcons.circleDashed, C.dialStrain, Track.interval, 12.3),
  ]),
  ActGroup('Strength', LucideIcons.dumbbell, [
    Activity('Weight training', LucideIcons.dumbbell, C.dialStrain, Track.sets, 6.0),
    Activity('Powerlifting', LucideIcons.dumbbell, C.dialStrain, Track.sets, 6.0),
    Activity(
        'Bodyweight', LucideIcons.personStanding, C.dialStrain, Track.sets, 4.5),
    Activity(
        'Calisthenics', LucideIcons.personStanding, C.dialStrain, Track.sets, 5.0),
    Activity('Kettlebell', LucideIcons.dumbbell, C.dialStrain, Track.interval, 8.0),
    Activity('CrossFit', LucideIcons.flame, C.dialStrain, Track.interval, 9.0),
    Activity('HIIT', LucideIcons.zap, C.dialStrain, Track.interval, 10.0),
    Activity(
        'Circuit training', LucideIcons.repeat2, C.dialStrain, Track.interval, 7.5),
    Activity('Functional', LucideIcons.boxes, C.dialStrain, Track.sets, 5.5),
  ]),
  ActGroup('Sports', LucideIcons.trophy, [
    Activity('Football', LucideIcons.volleyball, C.dialStrain, Track.duration, 8.0),
    Activity('Basketball', LucideIcons.volleyball, C.dialStrain, Track.duration, 8.0),
    Activity('Cricket', LucideIcons.target, C.dialStrain, Track.duration, 5.0),
    Activity('Tennis', LucideIcons.volleyball, C.dialStrain, Track.duration, 7.3),
    Activity('Badminton', LucideIcons.volleyball, C.dialStrain, Track.duration, 5.5),
    Activity(
        'Table tennis', LucideIcons.volleyball, C.dialStrain, Track.duration, 4.0),
    Activity('Squash', LucideIcons.volleyball, C.dialStrain, Track.duration, 12.0),
    // No MET: the compendium has no padel row. Tennis doubles and paddleball
    // are different games, and borrowing either would be a stand-in. The
    // post-session estimate still works from heart rate.
    Activity('Padel', LucideIcons.volleyball, C.dialStrain, Track.duration, null),
    Activity('Volleyball', LucideIcons.volleyball, C.dialStrain, Track.duration, 6.0),
    Activity('Hockey', LucideIcons.target, C.dialStrain, Track.duration, 8.0),
    Activity('Baseball', LucideIcons.target, C.dialStrain, Track.duration, 5.0),
    Activity('Rugby', LucideIcons.volleyball, C.dialStrain, Track.duration, 8.3),
    Activity('Golf', LucideIcons.flag, C.dialStrain, Track.duration, 4.8, gps: true),
    // Compendium 15092, "bowling, indoor, bowling alley". This row IS the
    // alley — that assumption is the choice being made here, not a fact about
    // what users do — because the alternative is two near-identical rows. The
    // bare 15090 "bowling" is 3.0, and neither number is the measured one.
    Activity('Bowling', LucideIcons.circleDot, C.dialStrain, Track.duration, 3.8),
    Activity('Boxing', LucideIcons.hand, C.dialStrain, Track.interval, 12.8),
    Activity('Martial arts', LucideIcons.hand, C.dialStrain, Track.duration, 10.3),
    Activity('Wrestling', LucideIcons.users, C.dialStrain, Track.duration, 6.0),
    Activity('Climbing', LucideIcons.mountain, C.dialStrain, Track.duration, 8.0),
  ]),
  ActGroup('Athletics', LucideIcons.medal, [
    Activity('Sprinting', LucideIcons.zap, C.dialStrain, Track.interval, 23.0),
    Activity('Track intervals', LucideIcons.timer, C.dialStrain, Track.interval, 11.8),
    Activity(
        'Cross country', LucideIcons.mountain, C.dialStrain, Track.distance, 9.0,
        gps: true, gait: true),
    Activity('Hurdles', LucideIcons.zap, C.dialStrain, Track.interval, 10.0),
    Activity('Long jump', LucideIcons.moveUpRight, C.dialStrain, Track.duration, 6.0),
    Activity('Shot put', LucideIcons.circle, C.dialStrain, Track.duration, 4.0),
    Activity('Javelin', LucideIcons.moveUpRight, C.dialStrain, Track.duration, 4.0),
    Activity('Pole vault', LucideIcons.moveUp, C.dialStrain, Track.duration, 6.0),
  ]),
  ActGroup('Outdoor', LucideIcons.trees, [
    Activity('Mountain biking', LucideIcons.bike, C.dialStrain, Track.distance, 8.5,
        gps: true),
    Activity('Kayaking', LucideIcons.sailboat, C.dialStrain, Track.distance, 5.0,
        gps: true),
    Activity('Surfing', LucideIcons.waves, C.dialStrain, Track.duration, 5.0),
    Activity('Paddleboard', LucideIcons.sailboat, C.dialStrain, Track.distance, 6.0,
        gps: true),
    Activity('Skiing', LucideIcons.snowflake, C.dialStrain, Track.distance, 7.0,
        gps: true),
    Activity(
        'Snowboarding', LucideIcons.snowflake, C.dialStrain, Track.distance, 5.3,
        gps: true),
    Activity('Skating', LucideIcons.circleDashed, C.dialStrain, Track.distance, 7.0,
        gps: true),
    // Compendium 15580, "skateboarding, general, moderate effort". Timed, not
    // a route: a park session goes nowhere, and cruising is the longboard rows.
    Activity(
        'Skateboarding', LucideIcons.circleDashed, C.dialStrain, Track.duration, 5.0),
    Activity('Horse riding', LucideIcons.rabbit, C.dialStrain, Track.duration, 5.5),
  ]),
  ActGroup('Mind & body', LucideIcons.leaf, [
    Activity('Yoga', LucideIcons.personStanding, C.dialStrain, Track.stillness, 3.0),
    Activity('Pilates', LucideIcons.personStanding, C.dialStrain, Track.stillness, 3.8),
    Activity(
        'Stretching', LucideIcons.personStanding, C.dialStrain, Track.stillness, 2.3),
    Activity(
        'Mobility', LucideIcons.personStanding, C.dialStrain, Track.stillness, 3.0),
    Activity('Tai chi', LucideIcons.wind, C.dialStrain, Track.stillness, 3.0),
    Activity('Breathwork', LucideIcons.wind, C.dialStrain, Track.stillness, 1.5),
    Activity('Meditation', LucideIcons.brain, C.dialStrain, Track.stillness, 1.3),
  ]),
  ActGroup('Everyday', LucideIcons.house, [
    Activity('Housework', LucideIcons.house, C.n500, Track.duration, 3.3),
    Activity('Gardening', LucideIcons.sprout, C.dialStrain, Track.duration, 3.8),
    Activity('Dog walking', LucideIcons.dog, C.dialStrain, Track.distance, 3.0,
        gps: true, gait: true),
    Activity('Childcare', LucideIcons.baby, C.dialStrain, Track.duration, 3.0),
    Activity('DIY', LucideIcons.hammer, C.dialStrain, Track.duration, 4.5),
    Activity('Shopping', LucideIcons.shoppingBag, C.n500, Track.duration, 2.3),
    Activity('Stairs', LucideIcons.trendingUp, C.dialStrain, Track.duration, 8.0),
  ]),
  ActGroup('Other', LucideIcons.ellipsis, [
    // The catch-all: nothing in the catalogue matched, or hunting for the
    // match was not worth it. NO MET, and that is the whole design of the row
    // — see [Activity.met]. 02060 "health club exercise, general" was the
    // near miss, and it prices a gym session, which is not what this row
    // means. Tracked by duration because the clock and the heart-rate trace
    // are everything the app knows about a workout nobody named.
    Activity('General workout', LucideIcons.activity, C.dialStrain,
        Track.duration, null),
    Activity('Dancing', LucideIcons.music, C.dialStrain, Track.duration, 7.8),
    // A normal entry with a real MET and a privacy default, exactly as Apple
    // Health carries it. Coyness here would be its own kind of judgement.
    Activity('Intimacy', LucideIcons.heart, C.dialStrain, Track.duration, 5.8,
        private: true),
    Activity(
        'Physiotherapy', LucideIcons.stethoscope, C.dialStrain, Track.duration, 3.0),
    Activity('Sauna', LucideIcons.thermometer, C.dialStrain, Track.stillness, 1.5),
    Activity('Cold plunge', LucideIcons.snowflake, C.dialStrain, Track.stillness, 2.0),
    // There is no 'Custom activity' row. It carried a MET of 4.0, which is not
    // in the compendium and could not be — the whole point of a custom entry
    // is that the app does not know what it is — and every session made with
    // it banked a specific-looking calorie figure derived from nothing about
    // what the user did, under one shared type key, with no name field
    // anywhere to say what it had been.
  ]),
];

/// What the app has to say about a calorie figure, in one place because it was
/// said in four and drifted: one site kept quoting a "±15%" error bar that no
/// estimator computes, long after the others dropped it.
const kCalorieWhy = 'MET value × your weight, refined by heart rate — or '
    'heart rate alone, for an activity that carries no MET.';

/// TS-03 — what every zone chart in the app has to admit about its own edges.
///
/// The five bands are percentages of a ceiling nobody measured on this user:
/// `estimatedMaxHr(age, family)`, Tanaka's age line for the strap that recorded
/// it. At 30 that is 187 and a real ceiling can sit 20 bpm either side of it,
/// so every boundary drawn off it moves with it. Saying that on the chart is a
/// materially different claim from printing five confident bpm ranges, and it
/// is the claim we can actually support.
///
/// One string because two screens draw a full zone chart (the session summary
/// and the day-strain detail) and it has to say the same thing on both. The
/// compact bar on a history row does not carry it — that row taps straight
/// through to the summary, which does.
///
/// Never "fat burning zone", never "aerobic threshold": these are convention
/// edges on a guessed ceiling, not measurements of anything metabolic.
/// NOT "your age and your strap": [estimatedMaxHr] takes `deviceFamily` and
/// DELIBERATELY IGNORES IT (hr_max.dart) — Tanaka is a population regression on
/// age alone, and swapping the strap does not move it by one bpm. The sentence
/// named an input that provably has no effect on the number it describes.
const kZonesWhy = 'Zone edges are percentages of a maximum heart rate '
    'estimated from your age — not one measured on you.';

/// English, non-localized fallback/test seam — see [zonesWhyFootnote] and
/// [zonesWhy] for the localized callers actually used by the UI.
String zonesWhyFootnote([AppLocalizations? l]) => l?.catalogueZonesWhy ?? kZonesWhy;

/// THE sentence a zone chart carries, for the anchors THAT chart was banded on.
///
/// [source] is the set's own stamp (`karvonen` · `observed` · `tanaka`) and
/// [maxHr] the ceiling it is 100 % of. One function because the day-strain
/// detail and a session's summary card draw the same bands off the same
/// `trainingZones` set, and only one of them was reading the stamp: the summary
/// hard-coded [kZonesWhy] and so told a user whose zones were banded on a
/// MEASURED ceiling that they came from their age. A card that reports 13
/// minutes above a boundary its own footnote misattributes is unanswerable —
/// there is no number on screen to check it against.
///
/// [kZonesWhy] (via [zonesWhyFootnote]) is the fallback rather than a fourth
/// branch: an unknown stamp and a measured stamp with no ceiling to name are
/// both "we cannot say this was measured on you", which is what the estimate
/// sentence already says. [l] is optional so the non-UI test seam
/// (`hr_ceiling_zones_test.dart`) can call this with the plain English copy.
String zonesWhy(String? source, num? maxHr, [AppLocalizations? l]) => maxHr == null
    ? zonesWhyFootnote(l)
    : switch (source) {
        'karvonen' =>
          l?.dayStrainZoneFootnoteKarvonen(maxHr.round()) ??
              'Zone edges span the gap between your measured resting heart rate '
                  'and the highest we have seen (${maxHr.round()} bpm). Both '
                  'measured on you.',
        'observed' =>
          l?.dayStrainZoneFootnoteObserved(maxHr.round()) ??
              'Zone edges are percentages of the highest heart rate we have seen '
                  '(${maxHr.round()} bpm) — measured, not estimated.',
        _ => zonesWhyFootnote(l),
      };

/// The row that means most people never open the catalogue.
const quickStart = <Activity>[
  Activity('Running', LucideIcons.footprints, C.dialStrain, Track.distance, 9.8,
      gps: true, gait: true),
  Activity('Weight training', LucideIcons.dumbbell, C.dialStrain, Track.sets, 6.0),
  Activity('Cycling', LucideIcons.bike, C.dialStrain, Track.distance, 8.0, gps: true),
  Activity('Walking', LucideIcons.footprints, C.dialStrain, Track.distance, 3.5,
      gps: true, gait: true),
  Activity('Football', LucideIcons.volleyball, C.dialStrain, Track.duration, 8.0),
  Activity('Yoga', LucideIcons.personStanding, C.dialStrain, Track.stillness, 3.0),
];

final List<Activity> allActivities = [
  for (final g in activityLibrary) ...g.items,
];

final Map<String, Activity> _byKey = {
  for (final a in allActivities) a.typeKey: a,
};

/// Resolve a stored `sessions.type` (or a display name) back to its entry.
/// Null for a type this build does not know — the caller renders the row with
/// what it has rather than guessing an icon and a MET.
Activity? activityByName(String? type) =>
    type == null ? null : _byKey[type.toLowerCase().replaceAll(' ', '_')];

// ── EXERCISES ──────────────────────────────────────────────────────────────
// The strength catalogue. The hand-written list keeps the strength_set keys
// already in use; the generated tail is a wger snapshot (see
// tool/update_wger_exercises.dart).

class ExerciseCredit {
  final String licenseName;
  final String licenseUrl;
  final String author;

  const ExerciseCredit(this.licenseName, this.licenseUrl, this.author);
}

class ExerciseDef {
  final String key;
  final String label;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final String category;
  final List<String> equipment;
  final List<String> aliases;

  /// Upstream translations for wger rows, hand-written for the core lifts;
  /// missing falls back to [label].
  final Map<String, String> localizedLabels;

  /// The plate/dumbbell increment this lift is normally loaded in, kg. A
  /// barbell moves in 2.5, a dumbbell in 2 — a single global step is what
  /// makes every strength app feel like a spreadsheet.
  final double step;

  /// wger rows only. Base data and each translation carry their own credit.
  final String? sourceId;
  final String? sourceUpdatedAt;
  final List<ExerciseCredit> sourceCredits;

  /// Done with the body as the load. With no history to seed from, the set
  /// starts as bodyweight instead of inheriting the last lift's kilos.
  final bool bodyweight;

  /// The Free Exercise DB photos bundled for this lift
  /// (assets/exercises/ID_N.jpg) and how many of the two there are.
  final String? imageId;
  final int imageFrames;

  /// The asset of [frame] (0 or 1), never past the last one there is.
  String? imagePath(int frame) => imageId == null
      ? null
      : 'assets/exercises/${imageId}_${frame >= imageFrames ? imageFrames - 1 : frame}.jpg';

  const ExerciseDef(
    this.key,
    this.label,
    this.primaryMuscles, {
    this.secondaryMuscles = const [],
    this.category = '',
    this.equipment = const [],
    this.aliases = const [],
    this.localizedLabels = const {},
    this.step = 2.5,
    this.sourceId,
    this.sourceUpdatedAt,
    this.sourceCredits = const [],
    this.bodyweight = false,
    this.imageId,
    this.imageFrames = 0,
  });

  bool get fromWger => sourceId != null;

  /// The upstream record with its authors and licenses.
  String? get sourceUrl => sourceId == null
      ? null
      : 'https://wger.de/api/v2/exerciseinfo/?uuid=$sourceId';

  String labelFor(String languageCode) => languageCode == 'ru'
      ? _russianExerciseLocalizations.exerciseCatalogueName(
          'k${key.replaceAll(RegExp('[^A-Za-z0-9_]'), '')}',
          label,
        )
      : localizedLabels[languageCode] ?? label;

  bool matches(String query, String languageCode) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return <String>{
      labelFor(languageCode),
      label,
      ...localizedLabels.values,
      ...aliases,
      ...primaryMuscles,
      ...secondaryMuscles,
      ...equipment,
      category,
    }.any((v) => v.toLowerCase().contains(q));
  }
}

final _russianExerciseLocalizations = lookupAppLocalizations(
  const Locale('ru'),
);

const _edgeExerciseLibrary = <ExerciseDef>[
  ExerciseDef(
    'bench_press',
    'Bench press',
    ['chest', 'triceps', 'shoulders'],
    category: 'Chest',
    equipment: ['Barbell', 'Bench'],
    aliases: ['flat bench', 'flat bench press', 'barbell bench press'],
    imageId: 'Barbell_Bench_Press_-_Medium_Grip',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Bankdrücken',
      'es': 'Press de banca',
      'fr': 'Développé couché',
    },
  ),
  ExerciseDef(
    'incline_db_press',
    'Incline DB press',
    ['chest', 'shoulders', 'triceps'],
    category: 'Chest',
    equipment: ['Dumbbell', 'Incline bench'],
    aliases: ['incline dumbbell press', 'incline db bench press'],
    step: 2,
    imageId: 'Incline_Dumbbell_Press',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Schrägbankdrücken mit Kurzhanteln',
      'es': 'Press inclinado con mancuernas',
      'fr': 'Développé incliné haltères',
    },
  ),
  ExerciseDef(
    'cable_fly',
    'Cable fly',
    ['chest', 'shoulders'],
    category: 'Chest',
    equipment: ['Cable machine'],
    aliases: ['cable flye', 'cable crossover', 'chest fly'],
    imageId: 'Incline_Cable_Flye',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Fliegende am Kabelzug',
      'es': 'Aperturas en polea',
      'fr': 'Écarté à la poulie',
    },
  ),
  ExerciseDef(
    'push_up',
    'Push-up',
    ['chest', 'triceps', 'shoulders'],
    category: 'Chest',
    equipment: ['none (bodyweight exercise)'],
    aliases: ['push up', 'push-ups', 'press-up', 'pushups'],
    imageId: 'Pushups',
    imageFrames: 2,
    localizedLabels: {'de': 'Liegestütz', 'es': 'Flexión', 'fr': 'Pompe'},
    bodyweight: true,
  ),
  ExerciseDef(
    'overhead_press',
    'Overhead press',
    ['shoulders', 'triceps', 'core'],
    category: 'Shoulders',
    equipment: ['Barbell'],
    aliases: ['OHP', 'military press', 'standing military press', 'barbell shoulder press'],
    imageId: 'Standing_Military_Press',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Schulterdrücken',
      'es': 'Press militar',
      'fr': 'Développé militaire',
    },
  ),
  ExerciseDef(
    'triceps_pushdown',
    'Triceps pushdown',
    ['triceps'],
    category: 'Arms',
    equipment: ['Cable machine'],
    aliases: ['tricep pushdown', 'cable pushdown', 'rope pushdown'],
    imageId: 'Triceps_Pushdown',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Trizepsdrücken am Kabel',
      'es': 'Extensión de tríceps en polea',
      'fr': 'Extension des triceps à la poulie',
    },
  ),
  ExerciseDef(
    'overhead_extension',
    'Overhead extension',
    ['triceps'],
    category: 'Arms',
    aliases: ['overhead triceps extension', 'dumbbell overhead extension'],
    imageId: 'Standing_Dumbbell_Triceps_Extension',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Trizepsstrecken über Kopf',
      'es': 'Extensión de tríceps sobre la cabeza',
      'fr': 'Extension des triceps au-dessus de la tête',
    },
  ),
  ExerciseDef(
    'barbell_row',
    'Barbell row',
    ['back', 'biceps', 'core'],
    category: 'Back',
    equipment: ['Barbell'],
    aliases: ['bent over row', 'bent over barbell row'],
    imageId: 'Bent_Over_Barbell_Row',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Langhantelrudern',
      'es': 'Remo con barra',
      'fr': 'Rowing barre',
    },
  ),
  ExerciseDef(
    'lat_pulldown',
    'Lat pulldown',
    ['back', 'biceps'],
    category: 'Back',
    equipment: ['Cable machine'],
    aliases: ['lat pull down', 'pulldown', 'wide-grip lat pulldown'],
    imageId: 'Wide-Grip_Lat_Pulldown',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Latziehen',
      'es': 'Jalón al pecho',
      'fr': 'Tirage vertical',
    },
  ),
  ExerciseDef(
    'pull_up',
    'Pull-up',
    ['back', 'biceps', 'core'],
    category: 'Back',
    equipment: ['Pull-up bar'],
    aliases: ['pull up', 'pull-ups', 'pullup', 'pullups', 'chin-up', 'chin up'],
    imageId: 'Pullups',
    imageFrames: 2,
    localizedLabels: {'de': 'Klimmzug', 'es': 'Dominada', 'fr': 'Traction'},
    bodyweight: true,
  ),
  ExerciseDef(
    'barbell_curl',
    'Barbell curl',
    ['biceps'],
    category: 'Arms',
    equipment: ['Barbell'],
    aliases: ['bicep curl', 'biceps curl'],
    imageId: 'Barbell_Curl',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Langhantelcurl',
      'es': 'Curl con barra',
      'fr': 'Curl barre',
    },
  ),
  ExerciseDef(
    'back_squat',
    'Back squat',
    ['legs', 'glutes', 'core'],
    category: 'Legs',
    equipment: ['Barbell'],
    aliases: ['squat', 'squats', 'barbell squat', 'barbell back squat', 'barbell full squat'],
    imageId: 'Barbell_Full_Squat',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Kniebeuge',
      'es': 'Sentadilla trasera',
      'fr': 'Squat arrière',
    },
  ),
  ExerciseDef(
    'front_squat',
    'Front squat',
    ['legs', 'glutes', 'core'],
    category: 'Legs',
    equipment: ['Barbell'],
    aliases: ['barbell front squat'],
    imageId: 'Front_Barbell_Squat',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Frontkniebeuge',
      'es': 'Sentadilla frontal',
      'fr': 'Squat avant',
    },
  ),
  ExerciseDef(
    'deadlift',
    'Deadlift',
    ['back', 'legs', 'glutes', 'core'],
    category: 'Back',
    equipment: ['Barbell'],
    aliases: ['barbell deadlift', 'conventional deadlift'],
    imageId: 'Barbell_Deadlift',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Kreuzheben',
      'es': 'Peso muerto',
      'fr': 'Soulevé de terre',
    },
  ),
  ExerciseDef(
    'romanian_deadlift',
    'Romanian deadlift',
    ['glutes', 'legs', 'back'],
    category: 'Legs',
    equipment: ['Barbell'],
    aliases: ['RDL', 'rdl', 'barbell romanian deadlift'],
    imageId: 'Romanian_Deadlift',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Rumänisches Kreuzheben',
      'es': 'Peso muerto rumano',
      'fr': 'Soulevé de terre roumain',
    },
  ),
  ExerciseDef(
    'hip_thrust',
    'Hip thrust',
    ['glutes', 'legs'],
    category: 'Legs',
    aliases: ['barbell hip thrust', 'glute bridge'],
    imageId: 'Barbell_Hip_Thrust',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Hip Thrust',
      'es': 'Empuje de cadera',
      'fr': 'Hip thrust',
    },
  ),
  ExerciseDef(
    'leg_press',
    'Leg press',
    ['legs', 'glutes'],
    category: 'Legs',
    aliases: ['seated leg press'],
    imageId: 'Leg_Press',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Beinpresse',
      'es': 'Prensa de piernas',
      'fr': 'Presse à cuisses',
    },
  ),
  ExerciseDef(
    'plank',
    'Plank',
    ['core'],
    category: 'Abs',
    equipment: ['none (bodyweight exercise)'],
    aliases: ['front plank'],
    step: 0,
    imageId: 'Plank',
    imageFrames: 2,
    localizedLabels: {'de': 'Unterarmstütz', 'es': 'Plancha', 'fr': 'Gainage'},
    bodyweight: true,
  ),
  ExerciseDef(
    'hanging_leg_raise',
    'Hanging leg raise',
    ['core'],
    category: 'Abs',
    equipment: ['Pull-up bar'],
    aliases: ['leg raise', 'hanging knee raise'],
    step: 0,
    imageId: 'Hanging_Leg_Raise',
    imageFrames: 2,
    localizedLabels: {
      'de': 'Hängendes Beinheben',
      'es': 'Elevación de piernas colgado',
      'fr': 'Relevé de jambes suspendu',
    },
    bodyweight: true,
  ),
];

const exerciseLibrary = <ExerciseDef>[
  ..._edgeExerciseLibrary,
  ..._wgerExerciseLibrary,
  ..._freeExerciseLibrary,
];

final coreExerciseCount = _edgeExerciseLibrary.length;
final wgerExerciseCount = _wgerExerciseLibrary.length;
final freeExerciseCount = _freeExerciseLibrary.length;

final Map<String, ExerciseDef> _exercisesByKey = {
  for (final e in exerciseLibrary) e.key: e,
};

ExerciseDef? exerciseByKey(String key) => _exercisesByKey[key];

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// "pull ups" and "Pull-Up" are one name: lower case, no punctuation, and a
/// trailing s on a long word dropped.
Set<String> _words(String s) => {
      for (final w in _norm(s).split(' '))
        if (w.isNotEmpty) w.length > 3 && w.endsWith('s') ? w.substring(0, w.length - 1) : w,
    };

List<(ExerciseDef, Set<String>)>? _wordIndex;
final Map<String, ExerciseDef?> _photoOf = {};

/// The exercise whose photos stand for [d]: itself when it has them, else the
/// photographed lift whose name holds all of its words (and adds the fewest),
/// or matches via synonyms and aliases, so a hand-written "Back squat" or "Bench press"
/// always shows the correct visual.
ExerciseDef? photoOf(ExerciseDef d) {
  if (d.imageId != null) return d;
  return _photoOf.putIfAbsent(d.key, () {
    // 1. Synonym lookup on label, key, or aliases
    final qLabel = _norm(d.label);
    final syn = _kExerciseSynonyms[qLabel] ??
        _kExerciseSynonyms[_norm(d.key.replaceAll('_', ' '))] ??
        (d.aliases.isNotEmpty ? _kExerciseSynonyms[_norm(d.aliases.first)] : null);
    if (syn != null) {
      for (final e in exerciseLibrary) {
        if (e.imageId == null) continue;
        if (_norm(e.label) == syn || e.aliases.any((a) => _norm(a) == syn)) {
          return e;
        }
      }
    }

    // 2. Exact word containment
    final qw = _words(d.label);
    if (qw.isEmpty) return null;
    ExerciseDef? best;
    var extra = 1 << 20;
    for (final e in exerciseLibrary) {
      if (e.imageId == null) continue;
      final w = _words(e.label);
      if (!w.containsAll(qw)) continue;
      final x = w.length - qw.length;
      if (x <= 3 && x < extra) {
        best = e;
        extra = x;
      }
    }
    if (best != null) return best;

    // 3. Aliases word containment
    for (final a in d.aliases) {
      final aw = _words(a);
      if (aw.isEmpty) continue;
      for (final e in exerciseLibrary) {
        if (e.imageId == null) continue;
        final w = _words(e.label);
        if (w.containsAll(aw)) return e;
      }
    }

    // 4. Overlap fallback: match closest exercise sharing root words
    var maxOverlap = 0;
    for (final e in exerciseLibrary) {
      if (e.imageId == null) continue;
      final w = _words(e.label);
      final overlap = qw.intersection(w).length;
      if (overlap > maxOverlap && overlap >= 1) {
        maxOverlap = overlap;
        best = e;
      }
    }
    return best;
  });
}

const Map<String, String> _kExerciseSynonyms = {
  'squat': 'barbell full squat',
  'squats': 'barbell full squat',
  'back squat': 'barbell full squat',
  'front squat': 'front barbell squat',
  'bench': 'barbell bench press - medium grip',
  'bench press': 'barbell bench press - medium grip',
  'flat bench': 'barbell bench press - medium grip',
  'incline bench': 'barbell incline bench press - medium grip',
  'incline bench press': 'barbell incline bench press - medium grip',
  'decline bench': 'decline barbell bench press',
  'decline bench press': 'decline barbell bench press',
  'deadlift': 'barbell deadlift',
  'deadlifts': 'barbell deadlift',
  'conventional deadlift': 'barbell deadlift',
  'rdl': 'romanian deadlift',
  'romanian deadlift': 'romanian deadlift',
  'sumo deadlift': 'sumo deadlift',
  'overhead press': 'standing military press',
  'ohp': 'standing military press',
  'military press': 'standing military press',
  'shoulder press': 'dumbbell shoulder press',
  'seated dumbbell press': 'seated dumbbell press',
  'pull up': 'pullups',
  'pull ups': 'pullups',
  'pullup': 'pullups',
  'pullups': 'pullups',
  'chin up': 'chin-up',
  'chin ups': 'chin-up',
  'chinup': 'chin-up',
  'lat pulldown': 'wide-grip lat pulldown',
  'lat pull down': 'wide-grip lat pulldown',
  'pulldown': 'wide-grip lat pulldown',
  'bicep curl': 'dumbbell bicep curl',
  'bicep curls': 'dumbbell bicep curl',
  'biceps curl': 'dumbbell bicep curl',
  'curl': 'dumbbell bicep curl',
  'curls': 'dumbbell bicep curl',
  'barbell curl': 'barbell curl',
  'hammer curl': 'hammer curls',
  'hammer curls': 'hammer curls',
  'preacher curl': 'preacher curl',
  'cable pushdown': 'cable pushdown',
  'tricep pushdown': 'cable pushdown',
  'tricep pushdowns': 'cable pushdown',
  'pushdown': 'cable pushdown',
  'pushdowns': 'cable pushdown',
  'dip': 'dips - chest version',
  'dips': 'dips - chest version',
  'chest dip': 'dips - chest version',
  'chest dips': 'dips - chest version',
  'tricep extension': 'triceps pushdown',
  'triceps extension': 'triceps pushdown',
  'skull crusher': 'ez-bar skullcrusher',
  'skull crushers': 'ez-bar skullcrusher',
  'skullcrusher': 'ez-bar skullcrusher',
  'skullcrushers': 'ez-bar skullcrusher',
  'lateral raise': 'side lateral raise',
  'lateral raises': 'side lateral raise',
  'lat raise': 'side lateral raise',
  'lat raises': 'side lateral raise',
  'side raise': 'side lateral raise',
  'side raises': 'side lateral raise',
  'face pull': 'face pull',
  'face pulls': 'face pull',
  'cable face pull': 'face pull',
  'leg press': 'leg press',
  'leg extension': 'leg extensions',
  'leg extensions': 'leg extensions',
  'leg curl': 'seated leg curl',
  'leg curls': 'seated leg curl',
  'hamstring curl': 'seated leg curl',
  'hamstring curls': 'seated leg curl',
  'calf raise': 'standing calf raises',
  'calf raises': 'standing calf raises',
  'seated cable row': 'seated cable rows',
  'cable row': 'seated cable rows',
  'cable rows': 'seated cable rows',
  'barbell row': 'bent over two-arm long bar row',
  'bent over row': 'bent over two-arm long bar row',
  'dumbbell row': 'one-arm dumbbell row',
  'db row': 'one-arm dumbbell row',
  'push up': 'pushups',
  'push ups': 'pushups',
  'pushup': 'pushups',
  'pushups': 'pushups',
  'lunge': 'dumbbell lunges',
  'lunges': 'dumbbell lunges',
  'bulgarian split squat': 'split squats',
  'split squat': 'split squats',
  'split squats': 'split squats',
  'hip thrust': 'barbell hip thrust',
  'hip thrusts': 'barbell hip thrust',
  'ab wheel': 'ab roller',
  'ab rollout': 'ab roller',
  'crunch': 'crunches',
  'crunches': 'crunches',
  'plank': 'plank',
};

/// The library exercise a free-text name most likely means: a synonym or alias
/// match first, then full query word containment, then best lexical overlap.
ExerciseDef? findExercise(String name) {
  final q = _norm(name);
  if (q.isEmpty) return null;

  // 1. Synonym lookup
  final syn = _kExerciseSynonyms[q];
  if (syn != null) {
    for (final e in exerciseLibrary) {
      if (_norm(e.label) == syn || e.aliases.any((a) => _norm(a) == syn)) {
        return e;
      }
    }
  }

  // 2. Exact label or alias match
  for (final e in exerciseLibrary) {
    if (_norm(e.label) == q || e.aliases.any((a) => _norm(a) == q)) return e;
  }

  final qw = _words(name);
  if (qw.isEmpty) return null;
  _wordIndex ??= [for (final e in exerciseLibrary) (e, _words(e.label))];

  ExerciseDef? best;
  var bestScore = 0.0;

  for (final (e, w) in _wordIndex!) {
    final shared = qw.intersection(w).length;
    if (shared == 0) continue;

    // Full query word containment bonus: if all words in query appear in the exercise
    if (shared == qw.length) {
      final containmentScore = 0.85 + (0.15 * shared / w.length);
      if (containmentScore > bestScore) {
        best = e;
        bestScore = containmentScore;
        continue;
      }
    }

    // Jaccard similarity
    final score = shared / qw.union(w).length;
    if (score > bestScore) {
      best = e;
      bestScore = score;
    }
  }

  return bestScore >= .35 ? best : null;
}
