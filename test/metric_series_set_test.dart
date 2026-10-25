// setMetricSeriesValue: a value is stored, a later null clears it, and a null
// for a day that never had one adds no row (the freeze golden counts rows).

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_metric_series_set_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('a null clears the day instead of storing a null row', () async {
    Future<int> rows() async => (await LocalDb.metricSeries('sleep_debt_min')).length;
    await LocalDb.setMetricSeriesValue('2026-10-25', 'sleep_debt_min', null);
    expect(await rows(), 0);
    await LocalDb.setMetricSeriesValue('2026-10-25', 'sleep_debt_min', 90);
    expect(await rows(), 1);
    await LocalDb.setMetricSeriesValue('2026-10-25', 'sleep_debt_min', null);
    expect(await rows(), 0);
  });
}
