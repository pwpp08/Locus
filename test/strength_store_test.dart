// The strength trainer's store: workouts and hand-typed records land on a
// fresh database and on an upgraded one, round-trip, and the logged rows the
// maths reads come back dated by their set, else by their session.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/strength_stats.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/strength_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

Future<void> _open(String name) async {
  await LocalDb.close();
  await databaseFactory.deleteDatabase(await _dbPath(name));
  LocalDb.dbName = name;
  await LocalDb.instance;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await LocalDb.close();
    for (final n in ['strength_store.db', 'strength_store_old.db']) {
      await databaseFactory.deleteDatabase(await _dbPath(n));
    }
  });

  test('an older database gains the two tables', () async {
    const name = 'strength_store_old.db';
    await LocalDb.close();
    final path = await _dbPath(name);
    await databaseFactory.deleteDatabase(path);
    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 58,
            onCreate: (db, _) => db.execute('CREATE TABLE marker (id INTEGER)')));
    await old.close();
    LocalDb.dbName = name;
    final db = await LocalDb.instance;
    for (final t in ['strength_workout', 'strength_record']) {
      expect(
          await db.rawQuery(
              "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [t]),
          isNotEmpty,
          reason: t);
    }
  });

  test('a workout keeps its exercises and sets in order', () async {
    await _open('strength_store.db');
    final w = StrengthWorkout.fresh('Push', const [
      PlannedExercise('bench_press', [PlannedSet(8, 60), PlannedSet(8, 62.5)]),
      PlannedExercise('fx:Pushups', [PlannedSet(15)]),
    ]);
    await StrengthStore.saveWorkout(w);
    var got = await StrengthStore.workouts();
    expect(got.single.name, 'Push');
    expect(got.single.exercises.map((e) => e.key), ['bench_press', 'fx:Pushups']);
    expect(got.single.exercises.first.sets[1].kg, 62.5);
    // Bodyweight stays null, not zero.
    expect(got.single.exercises.last.sets.single.kg, isNull);

    await StrengthStore.saveWorkout(w.copyWith(name: 'Push day'));
    got = await StrengthStore.workouts();
    expect(got, hasLength(1));
    expect(got.single.name, 'Push day');

    await StrengthStore.deleteWorkout(w.id);
    expect(await StrengthStore.workouts(), isEmpty);
  });

  test('a typed record is replaced, never duplicated, and can be removed',
      () async {
    await _open('strength_store.db');
    await StrengthStore.putRecord('squat', RecordKind.weight, 100, ts: 1000);
    await StrengthStore.putRecord('squat', RecordKind.weight, 110, ts: 2000);
    await StrengthStore.putRecord('pullup', RecordKind.reps, 8, ts: 1500);
    final r = await StrengthStore.typedRecords();
    expect(r, hasLength(2));
    final squat = r.firstWhere((e) => e.key == 'squat');
    expect(squat.value, 110);
    expect(squat.kind, RecordKind.weight);
    expect(r.firstWhere((e) => e.key == 'pullup').kind, RecordKind.reps);
    await StrengthStore.deleteRecord('squat');
    expect((await StrengthStore.typedRecords()).single.key, 'pullup');
  });

  test('logged rows are dated by the set, else by its session', () async {
    await _open('strength_store.db');
    final db = await LocalDb.instance;
    await db.insert('sessions', {
      'id': 's1',
      'start_ts': 1770000000,
      'end_ts': 1770003600,
      'type': 'weight_training',
      'status': 'done',
      'created_at': 1770000000,
    });
    await LocalDb.saveStrengthSets('s1', [
      {'exercise_key': 'bench_press', 'set_index': 1, 'reps': 8, 'load_kg': 80.0, 'at_ts': 1770000600},
      {'exercise_key': 'bench_press', 'set_index': 2, 'reps': 8, 'load_kg': 80.0},
    ]);
    final rows = await StrengthStore.loggedRows();
    expect(rows, hasLength(2));
    expect(rows.firstWhere((r) => r.ts == 1770000600).kg, 80);
    // The set with no time of its own takes its session's start.
    expect(rows.any((r) => r.ts == 1770000000), isTrue);
  });
}
