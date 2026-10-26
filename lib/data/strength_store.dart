// STRENGTH TRAINER STORE — the workouts a person builds (a name and its
// exercises, each with its planned sets) and the personal records they typed
// by hand. What was LIFTED stays in `strength_set`, written by the live
// screen; volume and logged records are derived from it on read (see
// compute/strength_stats.dart), so nothing here duplicates a measurement.
//
// A workout's exercises are one JSON column: they are always read and written
// whole, in order, and never queried into.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../compute/strength_stats.dart';
import 'db.dart' show LocalDb;

/// One planned set: how many reps, at what load (null: bodyweight).
class PlannedSet {
  final int reps;
  final double? kg;
  const PlannedSet(this.reps, [this.kg]);

  Map<String, Object?> toJson() => {'reps': reps, 'kg': kg};

  static PlannedSet? from(Object? j) {
    if (j is! Map) return null;
    final reps = (j['reps'] as num?)?.toInt();
    if (reps == null || reps < 0) return null;
    return PlannedSet(reps, (j['kg'] as num?)?.toDouble());
  }
}

/// One exercise in a workout, with its sets in order.
class PlannedExercise {
  final String key;
  final List<PlannedSet> sets;
  const PlannedExercise(this.key, this.sets);

  PlannedExercise copyWith({List<PlannedSet>? sets}) =>
      PlannedExercise(key, sets ?? this.sets);

  Map<String, Object?> toJson() =>
      {'key': key, 'sets': [for (final s in sets) s.toJson()]};

  static PlannedExercise? from(Object? j) {
    if (j is! Map || j['key'] is! String) return null;
    final sets = <PlannedSet>[
      if (j['sets'] is List)
        for (final s in j['sets'] as List) ?PlannedSet.from(s),
    ];
    return PlannedExercise(j['key'] as String, sets);
  }
}

class StrengthWorkout {
  final String id;
  final String name;
  final List<PlannedExercise> exercises;
  final int updatedAt;

  const StrengthWorkout(this.id, this.name, this.exercises, this.updatedAt);

  StrengthWorkout copyWith({String? name, List<PlannedExercise>? exercises}) =>
      StrengthWorkout(id, name ?? this.name, exercises ?? this.exercises,
          DateTime.now().millisecondsSinceEpoch ~/ 1000);

  /// A new workout under a fresh id.
  static StrengthWorkout fresh(String name, List<PlannedExercise> exercises) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return StrengthWorkout('sw$now', name, exercises, now ~/ 1000);
  }
}

class StrengthStore {
  StrengthStore._();

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS strength_workout (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        exercises_json TEXT NOT NULL DEFAULT '[]',
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS strength_record (
        exercise_key TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        value REAL NOT NULL,
        at_ts INTEGER NOT NULL
      )
    ''');
  }

  // ── workouts ────────────────────────────────────────────────────────────

  static Future<List<StrengthWorkout>> workouts() async {
    final db = await LocalDb.instance;
    final rows = await db.query('strength_workout', orderBy: 'updated_at DESC');
    return [
      for (final r in rows)
        StrengthWorkout(
          r['id'] as String,
          r['name'] as String,
          _decode(r['exercises_json'] as String?),
          (r['updated_at'] as num).toInt(),
        ),
    ];
  }

  static List<PlannedExercise> _decode(String? json) {
    try {
      final j = jsonDecode(json ?? '[]');
      return [
        if (j is List)
          for (final e in j) ?PlannedExercise.from(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveWorkout(StrengthWorkout w) async {
    final db = await LocalDb.instance;
    await db.insert(
        'strength_workout',
        {
          'id': w.id,
          'name': w.name,
          'exercises_json':
              jsonEncode([for (final e in w.exercises) e.toJson()]),
          'updated_at': w.updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteWorkout(String id) async {
    final db = await LocalDb.instance;
    await db.delete('strength_workout', where: 'id = ?', whereArgs: [id]);
  }

  // ── records typed by hand ───────────────────────────────────────────────

  static Future<List<TypedRecord>> typedRecords() async {
    final db = await LocalDb.instance;
    final rows = await db.query('strength_record');
    return [
      for (final r in rows)
        (
          key: r['exercise_key'] as String,
          kind: r['kind'] == 'reps' ? RecordKind.reps : RecordKind.weight,
          value: (r['value'] as num).toDouble(),
          ts: (r['at_ts'] as num).toInt(),
        ),
    ];
  }

  /// Pins [value] as the record for [key], dated [ts] (now by default).
  static Future<void> putRecord(String key, RecordKind kind, double value,
      {int? ts}) async {
    final db = await LocalDb.instance;
    await db.insert(
        'strength_record',
        {
          'exercise_key': key,
          'kind': kind == RecordKind.reps ? 'reps' : 'weight',
          'value': value,
          'at_ts': ts ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteRecord(String key) async {
    final db = await LocalDb.instance;
    await db.delete('strength_record',
        where: 'exercise_key = ?', whereArgs: [key]);
  }

  // ── what was lifted ─────────────────────────────────────────────────────

  /// Every logged set, dated by its own time or else its session's start.
  static Future<List<LoggedRow>> loggedRows() async {
    final db = await LocalDb.instance;
    final rows = await db.rawQuery('''
      SELECT s.session_id AS session, s.exercise_key AS key, s.reps AS reps,
             s.load_kg AS kg, COALESCE(s.at_ts, ss.start_ts) AS ts
      FROM strength_set s
      LEFT JOIN sessions ss ON ss.id = s.session_id
    ''');
    return [
      for (final r in rows)
        (
          session: r['session'] as String,
          key: r['key'] as String,
          reps: (r['reps'] as num?)?.toInt(),
          kg: (r['kg'] as num?)?.toDouble(),
          ts: (r['ts'] as num?)?.toInt(),
        ),
    ];
  }
}
