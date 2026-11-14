// The coach reads the person's own logs (journal, strength, labs, naps,
// breathing, cycle, detected activities) through views, never through their
// tables, and a private workout's sets stay out as its session does.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_actions.dart';
import 'package:openstrap_edge/coach/coach_db.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const views = [
    'v_journal',
    'v_journal_values',
    'v_cycle',
    'v_strength_sets',
    'v_strength_records',
    'v_labs',
    'v_breathing',
    'v_naps',
    'v_detected_activities',
  ];

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_coach_log_views_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    final db = await LocalDb.instance;
    for (final (id, private) in [('open', 0), ('hidden', 1)]) {
      await db.insert('sessions', {
        'id': id,
        'start_ts': 1787823754,
        'type': 'strength',
        'status': 'done',
        'private': private,
        'created_at': 0,
      });
      await db.insert('strength_set', {
        'session_id': id,
        'seq': 0,
        'exercise_key': 'squat_$id',
        'set_index': 0,
        'reps': 5,
        'load_kg': 100,
      });
    }
    await db.insert('journal_metric', {
      'date': '2026-11-14',
      'field': 'weight_kg',
      'value': 72.5,
      'updated_at': 0,
    });
  });

  tearDownAll(() async {
    await CoachDb.close();
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  for (final v in views) {
    test('$v is readable through run_sql', () async {
      final out = await CoachDb.runCoachSql('SELECT * FROM $v LIMIT 5');
      expect(out, isNot(contains('rejected')));
      expect(out, isNot(contains('error')));
    });
  }

  test('weight is in the journal values', () async {
    final out = await CoachDb.runCoachSql(
        "SELECT value FROM v_journal_values WHERE field = 'weight_kg'");
    expect(out, contains('72.5'));
  });

  test("a private session's sets stay out", () async {
    final out = await CoachDb.runCoachSql('SELECT exercise FROM v_strength_sets');
    expect(out, contains('squat_open'));
    expect(out, isNot(contains('squat_hidden')));
  });

  for (final t in [
    'strength_set',
    'journal_metric',
    'lab_result',
    'sleep_nap',
    'activity_suggestions',
    'alarm_schedule',
    'device',
  ]) {
    test('the base table $t is rejected', () {
      expect(() => CoachDb.guardAndPrepare('SELECT * FROM $t'),
          throwsA(isA<SqlGuardError>()));
    });
  }

  test('settings leave out who the person is', () async {
    final out = await CoachActions.appState(await LocalDb.instance, {
      'name': 'Ana Lopez',
      'email': 'ana@example.com',
      'weight_kg': 70,
      'step_goal': 9000,
    });
    expect(out, contains('"weight_kg":70'));
    expect(out, contains('"step_goal":9000'));
    expect(out, isNot(contains('Ana')));
    expect(out, isNot(contains('example.com')));
  });
}
