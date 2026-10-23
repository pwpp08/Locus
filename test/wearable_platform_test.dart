// The multi-device platform under the device columns
// (lib/compute/inputs/canonical.dart): device categories, the active
// wearable and its migration, the per-wearable flag and the re-derive it
// triggers, sparse-HR coverage and ownership, a strap's per-beat timing, the
// workout-sensor session override, and the per-(date, key) method that keeps
// baselines per method family. A Garmin watch is the wearable throughout; no
// primary band rows exist except the history seeded for the baseline check.


import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart';
import 'package:openstrap_edge/ble/adapters/host.dart' show beatEndTimesMs;
import 'package:openstrap_edge/ble/garmin_link.dart';
import 'package:openstrap_edge/ble/hrs_link.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/inputs/canonical.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/garmin_watch.dart';
import 'support/synthetic_day.dart';

final List<SyntheticDay> _days = [
  for (var d = 1; d <= 4; d++) SyntheticDay(DateTime(2026, 10, d)),
];
const String _watch = 'garmin-synthetic';
const String _strap = 'hrs-0a1b2c3d';

/// 120 bpm with two beats (488 ms, 500 ms): a standard 0x2A37 notification.
const List<int> _hrWithTwoRr = <int>[0x16, 120, 0xF4, 0x01, 0x00, 0x02];

void main() {
  test('every registry entry carries its category', () {
    // This build scans for the two WHOOP generations only (`kBandRegistry` was
    // trimmed to them); the other adapters keep their category on the entry
    // but are not in the registry, so `categoryOf` answers null for them.
    expect({for (final e in kBandRegistry) e.id: e.category}, {
      'gen4': DeviceCategory.wearable,
      'gen5': DeviceCategory.wearable,
    });
    expect(categoryOf('garmin'), isNull);
    expect(categoryOf('nothing-we-speak'), isNull);
  });

  test("a strap's beats chain off one another, re-anchored on a gap", () {
    // First notification: no chain yet, so the last beat lands mid-second.
    final a = beatEndTimesMs([488, 500], 100, null);
    expect(a, [99988 + 12, 100500]);
    // The next one continues the chain exactly.
    expect(beatEndTimesMs([510], 101, a.last), [101010]);
    // A gap (a dropped notification) no longer fits: re-anchored.
    expect(beatEndTimesMs([510], 109, a.last), [109500]);
  });

  test('method family and class per stored key', () {
    expect(seriesMethodFor('gen4')!('rhr'),
        (method: 'hr_1hz', family: 'hr_1hz', cls: 'ours'));
    final g = seriesMethodFor('garmin')!;
    expect(g('rhr'), (method: 'hr_1min', family: 'hr_1min', cls: 'ours'));
    expect(g('deep_min'), (method: 'device', family: 'device', cls: 'device'));
    expect(g('dyn_p90'), (method: 'hr_1min', family: 'hr_1min', cls: 'ours'));
    expect(seriesMethodFor('ultrahuman')!('strain').cls, 'estimated');
    expect(seriesMethodFor('miband234')!('rhr').method, 'hr_1min');
    // Efficiency and wake-ups are off the device's stages only on a night it
    // staged; on our HR-led night they are ours off its HR.
    for (final k in ['efficiency', 'awakenings']) {
      expect(seriesMethodFor('miband234', vendorNight: true)!(k).method,
          'device_stages', reason: k);
      expect(seriesMethodFor('miband234')!(k).method, 'hr_1min', reason: k);
    }
    expect(seriesMethodFor('ble_hrs'), isNull,
        reason: 'no validated method yet: abstain');
  });

  group('with a synced Garmin and a strap', () {
    final moved = <Set<String>>[];

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await LocalDb.close();
      LocalDb.dbName = 'wearable_platform_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      await LocalDb.upsertDevice(
          id: _watch,
          adapterId: 'garmin',
          remoteId: 'AA:BB:CC:00:00:02',
          label: 'garmin');
      final now = DateTime(2026, 10, 4, 22, 30);
      await GarminLink.instance.ingestForTest(
          _watch, GarminWatchScript(SyntheticDay.garminDays(_days)).reply,
          nowSeconds: () => SyntheticDay.sec(now));
      // Fourteen prior days a WHOOP band measured, resting HR far above the
      // watch's: a baseline that mixed the two would sit near 75.
      final db = await LocalDb.instance;
      for (var d = 17; d <= 30; d++) {
        final date = '2026-09-$d';
        await db.insert('metric_series', {'date': date, 'key': 'rhr', 'value': 75.0});
        await db.insert('metric_series_version',
            {'date': date, 'algo_version': 109, 'device_family': 'gen4'});
      }
      onWearableDaysChanged = (days) async => moved.add(days);
    });

    tearDownAll(() async {
      onWearableDaysChanged = null;
      LocalDb.sessionSensorSources = const {};
      await LocalDb.close();
    });

    test('a sparse watch covers hrSparse, merged, never hr1Hz', () async {
      final db = await LocalDb.instance;
      final rows = await db.query('device_coverage',
          where: 'device_id = ?', whereArgs: [_watch]);
      expect({for (final r in rows) r['signal']}, {'hrSparse'});
      expect(rows.length, lessThan(40),
          reason: 'spans tolerate two of its own gaps, not one row a minute');
    });

    test("a band day of no single family baselines against the band's days "
        "only, never the watch's", () async {
      Future<Set<double>> base(String? family) async =>
          (await debugSweepBaselineWindows('rhr', ['2026-10-05'],
                  deviceFamily: family))
              .single
              .toSet();
      expect(await base(null), {75.0},
          reason: 'a strap-swap or unstamped band day is a band day');
      expect(await base('gen5'), {75.0});
      expect(await base('garmin'), isNot(contains(75.0)));
    });

    test('a flagged-on strap takes its session window, and only then',
        () async {
      const t0 = 1_800_000_000;
      await HrsLink.instance.ingestForTest(_strap, const [
        (t0, _hrWithTwoRr),
        (t0 + 1, _hrWithTwoRr),
      ]);
      expect(await LocalDb.hrSamplesInRange(t0, t0 + 1), isEmpty,
          reason: 'flag off: the strap is not admitted');
      await useDevice(_strap, 'ble_hrs', true);
      expect(LocalDb.sessionSensorSources, {'ble_hrs'});
      expect([for (final r in await LocalDb.hrSamplesInRange(t0, t0 + 1)) r['hr']],
          [120, 120]);
      await useDevice(_strap, 'ble_hrs', false);
      expect(LocalDb.sessionSensorSources, isEmpty);
      expect(await LocalDb.hrSamplesInRange(t0, t0 + 1), isEmpty,
          reason: 'no sensor on: the band-only read');
    });

  });

  group('a WHOOP band and a Garmin watch on the same days', () {
    // The band records 10-03 18:00 to 10-04 22:00; the watch every day.
    final band = SyntheticDay(DateTime(2026, 10, 4));

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await LocalDb.close();
      LocalDb.dbName = 'wearable_platform_mixed_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      for (final (raws, samples) in band.primaryBatches()) {
        await LocalDb.commitSyncBatch(raws, samples);
      }
      await LocalDb.upsertDevice(
          id: _watch,
          adapterId: 'garmin',
          remoteId: 'AA:BB:CC:00:00:02',
          label: 'garmin');
      await GarminLink.instance.ingestForTest(
          _watch, GarminWatchScript(SyntheticDay.garminDays(_days)).reply,
          nowSeconds: () => SyntheticDay.sec(DateTime(2026, 10, 4, 22, 30)));
    });

    tearDownAll(() async {
      onWearableDaysChanged = null;
      await LocalDb.close();
    });

    test("a flagged-on strap never takes a session window off the band's "
        'rows, so the workout and the day read the same seconds', () async {
      final t0 = SyntheticDay.sec(DateTime(2026, 10, 4, 12));
      final band = [
        for (final r in await LocalDb.hrSamplesInRange(t0, t0 + 1)) r['hr'],
      ];
      expect(band, hasLength(2), reason: 'the band was worn then');
      await LocalDb.upsertDevice(id: _strap, adapterId: 'ble_hrs');
      await HrsLink.instance.ingestForTest(_strap, [
        (t0, _hrWithTwoRr),
        (t0 + 1, _hrWithTwoRr),
      ]);
      await useDevice(_strap, 'ble_hrs', true);
      try {
        expect([
          for (final r in await LocalDb.hrSamplesInRange(t0, t0 + 1)) r['hr'],
        ], band);
      } finally {
        await useDevice(_strap, 'ble_hrs', false);
      }
    });

  });
}
