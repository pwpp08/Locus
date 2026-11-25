// A watch worn through the day and a ring worn to bed: the day's wearable and
// the night's are two choices, and with the second unset nothing differs from
// one wearable at a time.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/inputs/canonical.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = 'sleep_wearable_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    await LocalDb.upsertDevice(id: 'g1', adapterId: 'garmin', label: 'watch');
    await LocalDb.upsertDevice(id: 'o1', adapterId: 'oura', label: 'ring');
    onWearableDaysChanged = null;
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('unset, the night follows the day\'s wearable', () async {
    await setWearableEnabled('garmin', true);
    await setActiveWearable('g1');
    expect((await sleepWearable())?.$1, 'g1');
    expect([for (final w in await wearablesInUse()) w.$1], ['g1']);
  });

  test('a chosen night wearable is used, the day keeps its own', () async {
    await setWearableEnabled('oura', true);
    await setSleepWearable('o1');
    expect((await activeWearable())?.$1, 'g1');
    expect((await sleepWearable())?.$1, 'o1');
    expect([for (final w in await wearablesInUse()) w.$1], ['g1', 'o1']);
  });

  test('a night wearable whose flag is off falls back to the day\'s', () async {
    await setWearableEnabled('oura', false);
    expect((await sleepWearable())?.$1, 'g1');
    expect([for (final w in await wearablesInUse()) w.$1], ['g1']);
  });

  test('clearing the choice returns to one wearable', () async {
    await setWearableEnabled('oura', true);
    await setSleepWearable(null);
    expect((await sleepWearable())?.$1, 'g1');
  });
}
