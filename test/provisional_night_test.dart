// This morning's night, slept and woken, before the data has run far enough
// past the wake to settle it: Home, Sleep and My Day used to hide it behind
// yesterday's night ("still being worked out"), and the Sleep screen said
// "No sleep yet". It is today's night, shown and marked provisional.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_provisional_night_test.db';
  });

  setUp(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  Map<String, dynamic> night(DateTime onset, DateTime wake, {int? edgeSec}) => {
        'scalars': {'readiness': 60},
        'sleep': {
          'window': {
            'value': {
              'onset_ms': onset.millisecondsSinceEpoch,
              'offset_ms': wake.millisecondsSinceEpoch,
            },
          },
          'accounting': {
            'value': {
              'tst_sec': wake.difference(onset).inSeconds - 1800,
            },
          },
        },
        'data_edge_sec': ?edgeSec,
      };

  test('a woken but unsettled night is today\'s, provisional', () async {
    final n = DateTime.now();
    // An hour ago (never before 03:00, which is a night still going), with
    // the data only five minutes past it: not settled.
    final wake = n.hour >= 5
        ? DateTime(n.year, n.month, n.day, n.hour - 1, n.minute)
        : DateTime(n.year, n.month, n.day, 3, 30);
    final onset =
        DateTime(wake.year, wake.month, wake.day, wake.hour - 7, wake.minute);
    final today = todayLabel();
    final yesterday = todayLabel(DateTime(n.year, n.month, n.day - 1, 12));
    final y = DateTime(n.year, n.month, n.day - 1);
    await LocalDb.putDayResult(
      dayId: yesterday,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(night(DateTime(y.year, y.month, y.day - 1, 23),
          DateTime(y.year, y.month, y.day, 7))),
      windowJson: '{}',
    );
    await LocalDb.putDayResult(
      dayId: today,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(night(onset, wake,
          edgeSec: wake.millisecondsSinceEpoch ~/ 1000 + 300)),
      windowJson: '{}',
    );
    await LocalDb.refreshComputeFreshness();

    final repo = LocalRepositoryImpl(getProfileMap: () => {});
    final t = await repo.getToday();
    expect((t['status'] as Map)['overnight_state'], isNot('ready'));
    // Home: this morning's night in place of the held-over one.
    final sp = t['sleep_provisional'] as Map;
    expect((sp['duration_min'] as Map)['value'], 7 * 60 - 30);

    // Sleep and My Day: the night itself, marked as still settling.
    final s = await repo.getDaySleepV2(today);
    expect(s['has_sleep'], true);
    expect(s['provisional'], true);
    expect(s['duration_min'], 7 * 60 - 30);
  });
}
