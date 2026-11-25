// Sleep, steps and heart-rate history from the health store: grouped per
// source and local day, our own exported data left out, bad windows dropped,
// and a second import replacing rather than stacking.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/health/health_history_import.dart';

HealthDataPoint _pt(
  HealthDataType type,
  DateTime from,
  DateTime to, {
  num value = 0,
  String uuid = '',
  String source = 'Ring app',
  String sourceId = 'src',
}) =>
    HealthDataPoint(
      uuid: uuid,
      value: NumericHealthValue(numericValue: value),
      type: type,
      unit: HealthDataUnit.NO_UNIT,
      dateFrom: from,
      dateTo: to,
      sourceId: sourceId,
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      sourceDeviceId: 'dev',
      sourceName: source,
    );

class _FakeHealth extends Health {
  _FakeHealth(this.points);
  final List<HealthDataPoint> points;

  @override
  Future<void> configure() async {}

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async =>
      [
        for (final p in points)
          if (types.contains(p.type) &&
              p.dateTo.isAfter(startTime) &&
              p.dateFrom.isBefore(endTime))
            p,
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bed = DateTime(2026, 11, 24, 23);
  final wake = DateTime(2026, 11, 25, 7);

  group('nights', () {
    test('a session takes its stages, overlaps counted once', () {
      final n = nightsFrom([
        _pt(HealthDataType.SLEEP_SESSION, bed, wake, uuid: 's1'),
        _pt(HealthDataType.SLEEP_DEEP, bed, bed.add(const Duration(hours: 2))),
        _pt(HealthDataType.SLEEP_LIGHT, bed.add(const Duration(hours: 1)),
            bed.add(const Duration(hours: 5))),
        _pt(HealthDataType.SLEEP_REM, bed.add(const Duration(hours: 5)), wake),
        _pt(HealthDataType.SLEEP_AWAKE, wake, wake),
      ]).single;
      expect(n.source, 'Ring app');
      expect(n.endTs - n.startTs, 8 * 3600);
      // Deep 0-2h and light 1-5h overlap for an hour; rem 5-8h.
      expect(n.asleepS, 8 * 3600);
      expect(n.deepS, 2 * 3600);
      expect(n.remS, 3 * 3600);
    });

    test('no stages: the length is known, "asleep" is not', () {
      final n = nightsFrom(
          [_pt(HealthDataType.SLEEP_SESSION, bed, wake, uuid: 's1')]).single;
      expect(n.asleepS, isNull);
      expect(n.deepS, isNull);
    });

    test('stage segments with no session group into nights at a long gap', () {
      final d2 = DateTime(2026, 11, 25, 23);
      final n = nightsFrom([
        _pt(HealthDataType.SLEEP_LIGHT, bed, bed.add(const Duration(hours: 4))),
        _pt(HealthDataType.SLEEP_DEEP, bed.add(const Duration(hours: 4)), wake),
        _pt(HealthDataType.SLEEP_LIGHT, d2, d2.add(const Duration(hours: 7))),
      ]);
      expect(n, hasLength(2));
      expect(n.map((e) => e.asleepS), [8 * 3600, 7 * 3600]);
    });

    test('a short or absurd window is dropped, and our own is skipped', () {
      final n = nightsFrom([
        _pt(HealthDataType.SLEEP_SESSION, bed,
            bed.add(const Duration(minutes: 10)), uuid: 'short'),
        _pt(HealthDataType.SLEEP_SESSION, bed,
            bed.add(const Duration(hours: 30)), uuid: 'long'),
        _pt(HealthDataType.SLEEP_SESSION, bed, wake,
            uuid: 'ours', source: 'Locus', sourceId: 'wtf.locus'),
      ], ownApp: 'wtf.locus');
      expect(n, isEmpty);
    });
  });

  group('daily', () {
    test('steps add per day and source, never across sources', () {
      final d = dailyFrom([
        _pt(HealthDataType.STEPS, DateTime(2026, 11, 25, 8),
            DateTime(2026, 11, 25, 9), value: 1000),
        _pt(HealthDataType.STEPS, DateTime(2026, 11, 25, 12),
            DateTime(2026, 11, 25, 13), value: 500),
        _pt(HealthDataType.STEPS, DateTime(2026, 11, 25, 8),
            DateTime(2026, 11, 25, 9), value: 900, source: 'Watch'),
      ]);
      double of(String src) => d
          .firstWhere((e) => e.kind == kKindSteps && e.source == src)
          .value;
      expect(of('Ring app'), 1500);
      expect(of('Watch'), 900);
    });

    test('heart rate: mean, lowest and highest, bad samples dropped', () {
      final t = DateTime(2026, 11, 25, 10);
      final d = dailyFrom([
        for (final v in [60, 80, 100, 5, 400])
          _pt(HealthDataType.HEART_RATE, t, t, value: v),
      ]);
      double of(String k) => d.firstWhere((e) => e.kind == k).value;
      expect(of(kKindHrAvg), 80);
      expect(of(kKindHrMin), 60);
      expect(of(kKindHrMax), 100);
    });
  });

  group('sync', () {
    late Directory dir;

    setUp(() async {
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_history_import_test.db';
      dir = Directory(await databaseFactory.getDatabasesPath());
      await LocalDb.close();
      await databaseFactory.deleteDatabase(p.join(dir.path, LocalDb.dbName));
      await LocalDb.instance;
      SharedPreferences.setMockInitialValues(const {});
      PackageInfo.setMockInitialValues(
        appName: 'Locus',
        packageName: 'wtf.locus',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
    });

    tearDown(() async {
      await LocalDb.close();
      await databaseFactory.deleteDatabase(p.join(dir.path, LocalDb.dbName));
    });

    test('stores nights and days, and a second pass replaces them', () async {
      final now = DateTime(2026, 11, 25, 12);
      final importer = HealthHistoryImporter(
        health: _FakeHealth([
          _pt(HealthDataType.SLEEP_SESSION, bed, wake, uuid: 's1'),
          _pt(HealthDataType.SLEEP_DEEP, bed, wake),
          _pt(HealthDataType.STEPS, DateTime(2026, 11, 24, 9),
              DateTime(2026, 11, 24, 10), value: 4000),
          _pt(HealthDataType.HEART_RATE, DateTime(2026, 11, 24, 9),
              DateTime(2026, 11, 24, 9), value: 70),
        ]),
        isApple: false,
      );
      final first = await importer.sync(now: now);
      expect(first.nights, 1);
      expect(first.days, 1);
      await importer.sync(now: now);
      expect(await LocalDb.importedSleep(), hasLength(1));
      // steps + avg + min + max for the one day, once.
      expect(await LocalDb.importedDaily(), hasLength(4));
      final counts = await LocalDb.importedCounts();
      expect(counts['sleep'], 1);
      expect(counts['days'], 1);
    });
  });
}
