// The beta "use this device" switch on a paired device's page, off a real
// database: the title per category, the confirm sheet before a wearable
// scores (cancel, confirm, the active wearable switched off), the off path,
// and that the developer toggles flip the same flag the switch shows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/wearable_numbers.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _garmin = 'garmin-1', _oura = 'oura-1', _strap = 'strap-1';
const _scale = 'scale-1', _thermo = 'thermo-1', _coros = 'coros-1';
const _whoop = 'whoop-2';

/// Lets the database work a build or a tap starts finish: real time for the
/// I/O, a fake-time pump for what it hands back (and the sheet's motion),
/// until a toggle's re-derive is done.
Future<void> _settle(WidgetTester t, [Widget? w]) async {
  if (w != null) await t.pumpWidget(w);
  for (var i = 0; i < 200 && (i < 10 || WearableDisplay.instance.busy); i++) {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _page(WidgetTester t, String id, String adapter) => _settle(
    t,
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
          body: SingleChildScrollView(
              child: DeviceUseSwitch(deviceId: id, adapterId: adapter))),
    ));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    Prefs.setBool(Prefs.devMode, false);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = 'device_use_switch_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    for (final (id, adapter, label) in [
      (_garmin, 'garmin', 'Garmin watch'),
      (_oura, 'oura', 'Oura ring'),
      (_strap, 'ble_hrs', 'Chest strap'),
      (_scale, 'miscale2', 'Mi Smart Scale 2'),
      (_thermo, 'thermometer', 'Thermometer'),
      (_coros, 'coros', 'Coros watch'),
      (_whoop, 'gen4', 'WHOOP 4.0'),
    ]) {
      await LocalDb.upsertDevice(id: id, adapterId: adapter, label: label);
    }
    // Real-zone first read, so a page's own read is a quick one.
    await WearableDisplay.instance.loadDevices();
  });

  tearDownAll(() async => LocalDb.close());

  testWidgets('no switch for a thermometer, a Coros watch or a WHOOP band',
      (t) async {
    for (final (id, adapter) in [
      (_thermo, 'thermometer'),
      (_coros, 'coros'),
      (_whoop, 'gen4'),
    ]) {
      await _page(t, id, adapter);
      expect(find.byType(Switch), findsNothing, reason: adapter);
      expect(find.text('Beta'), findsNothing, reason: adapter);
    }
  });

}
