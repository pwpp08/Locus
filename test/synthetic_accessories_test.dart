// Workout sensors and health measurements on a wearable's day, end to end.
// A Pebble 2 is the ACTIVE WEARABLE (four synthetic days through the real
// Pebble link, no primary band). A Bluetooth heart-rate strap, flagged on,
// is worn for a 20-minute session and again overnight at rest: inside the
// session its 1 Hz HR wins (strain, heart-rate recovery), and its night
// beats give the watch's day an HRV of ours the watch alone cannot. A Mi
// composition scale's weighing then becomes the app's profile weight once
// its flag is on (never before), and the day's calories move with it.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/hrs_link.dart';
import 'package:openstrap_edge/ble/pebble_link.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/inputs/canonical.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/strap_day.dart';
import 'support/synthetic_day.dart';

final List<SyntheticDay> _days = [
  for (var d = 1; d <= 4; d++) SyntheticDay(DateTime(2026, 10, d)),
];
final SyntheticDay _truth = _days.last;
const String _watch = 'pebble-accessories';
const String _strap = 'hrs-accessories';
const String _dayId = '2026-10-04';
const Map<String, dynamic> _profileMap = {
  'age': 32,
  'weight_kg': 72.0,
  'height_cm': 176.0,
  'sex': 'm',
};

Future<Map<String, dynamic>> _scalars() async =>
    ((jsonDecode((await LocalDb.dayResult(_dayId))!['payload_json'] as String)
            as Map)['scalars'] as Map)
        .cast<String, dynamic>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = 'synthetic_accessories_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    await LocalDb.upsertDevice(
        id: _watch, adapterId: 'pebble', remoteId: 'AA:BB:CC:00:00:13');
    final now = DateTime(2026, 10, 4, 22, 30);
    await PebbleLink.instance.ingestForTest(
        _watch, SyntheticDay.pebbleDays(_days),
        nowSeconds: () => SyntheticDay.sec(now));
    await LocalDb.setCursor(kActiveWearableCursor, _watch);
    await LocalDb.setCursor(wearableEnabledCursor('pebble'), '1');
    final profile = Profile.fromMap(_profileMap);
    for (var i = 0; i < 2; i++) {
      await DerivationEngine()
          .runDays(profile, {for (final d in _days) dayLabelOf(d.day)},
              force: true);
    }
  });

  tearDownAll(() async => LocalDb.close());

  test("a strap's workout and its night at rest on the watch's day",
      () async {
    final profile = Profile.fromMap(_profileMap);
    final before = (await dayCells(_dayId))!;
    expect(before['workouts_with_strap']!['class'], 'unavailable');
    expect(before['hrv'],
        allOf(containsPair('class', 'unavailable'),
            containsPair('reason', Why.neverBeats.name)));
    final strainBefore = (await _scalars())['strain'] as num;

    await LocalDb.upsertDevice(id: _strap, adapterId: 'ble_hrs');
    final start = SyntheticDay.sec(DateTime(2026, 10, 4, 12));
    final end = start + 20 * 60;
    int bpm(int t) =>
        t <= end ? 150 : (150 - 30 * (t - end) / 60).round().clamp(100, 150);
    final (night, rmssd) = strapRestingBeats(
        SyntheticDay.sec(_truth.sleepOnset), SyntheticDay.sec(_truth.sleepOffset));
    await HrsLink.instance.ingestForTest(_strap, [
      ...night,
      for (var t = start; t <= end + kStrapTailSec; t++) (t, [0x00, bpm(t)]),
    ]);
    await LocalDb.putSession({
      'id': 'strap-session',
      'start_ts': start,
      'end_ts': end,
      'type': 'run',
      'status': 'done',
      'created_at': end,
    });

    // Flag off: the strap's rows are there and move nothing.
    await DerivationEngine().runDays(profile, {_dayId}, force: true);
    expect((await dayCells(_dayId))!['hrv']!['class'], 'unavailable');

    await useDevice(_strap, 'ble_hrs', true);
    await DerivationEngine().runDays(profile, {_dayId}, force: true);
    final c = (await dayCells(_dayId))!;
    expect(c['workouts_with_strap'],
        allOf(containsPair('class', 'ours'), containsPair('value', 1),
            containsPair('method', 'hr_1hz')));
    expect(c['hrr'], containsPair('method', 'hr_1hz'));
    expect(c['hrr']!['value'] as num, closeTo(30, 3));
    expect(c['hrv'],
        allOf(containsPair('class', 'ours'), containsPair('method', 'rr_strap')));
    expect(c['hrv']!['value'] as num, closeTo(rmssd, rmssd * 0.15),
        reason: 'the RMSSD of the beats the strap sent');
    expect(c['strain']!['value'] as num, greaterThan(strainBefore),
        reason: "the session's 150 bpm is the strap's, at 1 Hz");
    // The watch's own rows still decide the rest of the day.
    expect(c['resting_hr']!['method'], 'hr_1min');
    // Stored as made: the beat-only numbers are the strap's, the recovery
    // time constant its 1 Hz tail's.
    final stored = {
      for (final r in await (await LocalDb.instance).query('metric_method',
          where: 'date = ?', whereArgs: [_dayId]))
        r['key'] as String: r['method'],
    };
    for (final k in ['rmssd', 'sdnn', ...kStrapBeatSeriesKeys]) {
      expect(stored[k], 'rr_strap', reason: k);
    }
    expect(stored['hrr_tau_s'], 'hr_1hz');

    // Flag off again: the night's HRV goes with it.
    await useDevice(_strap, 'ble_hrs', false);
    await DerivationEngine().runDays(profile, {_dayId}, force: true);
    final off = (await dayCells(_dayId))!;
    expect(off['hrv']!['class'], 'unavailable');
    expect(off['workouts_with_strap']!['class'], 'unavailable');
  }, timeout: const Timeout(Duration(minutes: 3)));

}
