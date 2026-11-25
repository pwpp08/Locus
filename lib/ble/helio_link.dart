// The HOST for a paired Amazfit Helio Strap: connect, run [HelioAdapter] for one
// bounded session, bank what comes back, disconnect. Also the pairing flow and
// the keychain items.
//
// NOTHING HERE HAS MET HARDWARE (ASSUMPTIONS R6) — see `adapters/helio.dart`.
//
// THE PAIRING KEY comes from the owner's Zepp account (`helio/zepp_cloud.dart`)
// or is typed in. It is held in two places over its life:
//   * a PENDING slot, written by the key screen and consumed by [pairHelio];
//   * a per-device item, written once the strap has proved it accepts the key.
// A key is only ever stored against a strap that accepted it, and forgetting a
// strap drops the key with the row.
//
// The strap does not need to be unlinked from Zepp, but the Zepp app must not
// be holding its connection: the strap talks to one phone app at a time.

import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/db.dart';
import '../data/models.dart' show ArchiveRecord;
import '../sync/paired_device.dart' show cleanDeviceLabel;
import 'adapters/_registry.dart';
import 'adapters/gatt_link.dart';
import 'adapters/helio.dart';
import 'adapters/host.dart' show BandHost;
import 'ble_state.dart' show withSecondaryLinkSlot;
import 'helio/channel.dart' show helioParseAuthKey;

const IOSOptions _kApple = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
const MacOsOptions _kMacos = MacOsOptions(accessibility: KeychainAccessibility.first_unlock);
const FlutterSecureStorage _secure = FlutterSecureStorage();

String _keyItem(String deviceId) => 'helio_pairing_key:$deviceId';
const String _pendingItem = 'helio_pending_key';

/// `sync_cursor` name for one strap's per-kind history cursors.
String _cursorItem(String deviceId) => 'helio_cursors:$deviceId';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

// ── The key, before and after pairing ───────────────────────────────────────

/// A key found for a strap, waiting for [pairHelio]. [mac] is the strap it
/// belongs to when Zepp said so, so a different strap in reach is not paired
/// with it by mistake.
class HelioPendingKey {
  const HelioPendingKey(this.key, this.mac);
  final Uint8List key;
  final String? mac;
}

Future<void> saveHelioPendingKey(Uint8List key, {String? mac}) => _secure.write(
      key: _pendingItem,
      value: jsonEncode({'key': _hex(key), if (mac != null) 'mac': mac.toUpperCase()}),
      iOptions: _kApple,
      mOptions: _kMacos,
    );

Future<HelioPendingKey?> readHelioPendingKey() async {
  try {
    final raw = await _secure.read(key: _pendingItem, iOptions: _kApple, mOptions: _kMacos);
    if (raw == null) return null;
    final j = jsonDecode(raw);
    final key = j is Map ? helioParseAuthKey('${j['key']}') : null;
    return key == null ? null : HelioPendingKey(key, j['mac'] as String?);
  } catch (e) {
    debugPrint('[helio] the pending key could not be read: $e');
    return null;
  }
}

Future<void> clearHelioPendingKey() async {
  try {
    await _secure.delete(key: _pendingItem, iOptions: _kApple, mOptions: _kMacos);
  } catch (e) {
    debugPrint('[helio] could not drop the pending key: $e');
  }
}

Future<Uint8List?> _readKey(String deviceId) async {
  try {
    final hex = await _secure.read(key: _keyItem(deviceId), iOptions: _kApple, mOptions: _kMacos);
    return hex == null ? null : helioParseAuthKey(hex);
  } catch (e) {
    debugPrint('[helio] the keychain was unavailable: $e');
    return null;
  }
}

Future<void> _dropKey(String deviceId) async {
  try {
    await _secure.delete(key: _keyItem(deviceId), iOptions: _kApple, mOptions: _kMacos);
  } catch (e) {
    debugPrint('[helio] could not drop the stored key: $e');
  }
}

const String _kTryAgain = 'Put the strap on its charger, close the Zepp app completely '
    '(Android: App info → Force stop), keep the strap next to the phone, and try again.';

// ── The link ────────────────────────────────────────────────────────────────

/// The live link to a paired Helio Strap. One instance.
class HelioLink {
  HelioLink._();
  static final HelioLink instance = HelioLink._();

  static Future<Map<String, Object?>?> pairedRow() async {
    for (final r in await LocalDb.deviceRows()) {
      if (r['adapter_id'] == kHelio.id) return r;
    }
    return null;
  }

  /// Forget a paired strap: drop its key, then its `device` row. The key goes
  /// first so a crash between the two leaves a row that fails visibly rather
  /// than a secret that outlives its reason to exist.
  static Future<bool> forget(String id) async {
    if (id == LocalDb.kPrimaryDeviceId) {
      debugPrint('[helio] refusing to forget the primary band from here.');
      return false;
    }
    if (instance._deviceId == id) await instance.stop();
    await _dropKey(id);
    await LocalDb.deleteDevice(id);
    return true;
  }

  /// What the last session said about itself, in words, or null when it went
  /// well (or has not run). Shown beside the strap.
  String? get problem => _problem;
  String? _problem;

  BluetoothDevice? _device;
  GattBandLink? _link;
  BandHost? _host;
  String? _deviceId;
  bool _busy = false;

  /// The newest cursors the adapter reported, not yet committed.
  String? _pendingCursors;

  Future<bool> sync() {
    if (_busy) return Future.value(false);
    _busy = true;
    return _sync().whenComplete(() => _busy = false);
  }

  Future<bool> _sync() async {
    final row = await pairedRow();
    if (row == null) return false;
    final deviceId = row['id'] as String?;
    final remoteId = row['remote_id'] as String?;
    if (deviceId == null || remoteId == null || remoteId.isEmpty) return false;
    if (deviceId == LocalDb.kPrimaryDeviceId) {
      debugPrint('[helio] refusing to sync: the row claims the primary device id.');
      return false;
    }
    final key = await _readKey(deviceId);
    if (key == null) {
      _problem = 'The strap\'s key could not be read from this phone. '
          'Remove the strap here and pair it again.';
      return false;
    }
    _deviceId = deviceId;
    _problem = null;
    try {
      return await withSecondaryLinkSlot(() async {
        try {
          final device = BluetoothDevice.fromId(remoteId);
          _device = device;
          await device.connect(timeout: const Duration(seconds: 20));
          final services = await device.discoverServices();
          final link = GattBandLink(
            entry: kHelio,
            services: services,
            onLog: (m) => debugPrint('[helio] $m'),
          );
          _link = link;
          final missing = link.missingCharacteristics(kHelio.requiredCharacteristics);
          if (missing.isNotEmpty) {
            _problem = 'That device does not expose the strap\'s data service.';
            return false;
          }
          _pendingCursors = null;
          final host = BandHost(
            adapter: HelioAdapter(
              authKey: key,
              cursors: await LocalDb.getCursor(_cursorItem(deviceId)) ?? '',
              priorSteps: await _priorSteps(deviceId),
              maxWrite: device.mtuNow - 3,
            ),
            deviceId: deviceId,
            onLog: (m) => debugPrint('[helio] $m'),
            notesAfterVendorWrites: true,
            buildArchive: _buildArchiveRow,
            onNote: _handleNote,
            // The cursor lands in the same commit as the rows it covers.
            extraCursors: () {
              final c = _pendingCursors;
              return c == null ? const {} : {_cursorItem(deviceId): c};
            },
          );
          _host = host;
          await host.run(link).timeout(const Duration(minutes: 8), onTimeout: () {});
          return _problem == null;
        } finally {
          await stop();
        }
      });
    } catch (e) {
      debugPrint('[helio] sync failed: $e');
      _problem ??= 'Could not reach the strap. It has to be nearby, and not connected to the Zepp app.';
      return false;
    }
  }

  void _handleNote(String key, Object? value) {
    switch (key) {
      case 'helio_cursor':
        if (value is String) _pendingCursors = value;
      case 'helio_auth_failed':
        _problem = '${value ?? 'The strap did not accept the key.'}';
      case 'helio_auth':
        _problem = null;
    }
  }

  Future<Map<DateTime, int>> _priorSteps(String deviceId) async => {
        for (final MapEntry(:key, :value)
            in (await LocalDb.deviceObservationValues(deviceId, 'steps')).entries)
          DateTime.fromMillisecondsSinceEpoch(key): value.toInt(),
      };

  Future<void> stop() async {
    _link?.close();
    _link = null;
    await _host?.stop();
    _host = null;
    _pendingCursors = null;
    _deviceId = null;
    final d = _device;
    _device = null;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {/* already gone */}
    }
  }

  /// A raw chunk, banked verbatim. The first byte is the record kind (the
  /// adapter's own tag, never sent on the radio) and is stripped back off.
  ArchiveRecord? _buildArchiveRow(List<int> bytes, int capturedAtMs) {
    if (bytes.length < 2) return null;
    return ArchiveRecord(
      hex: _hex(bytes.sublist(1)),
      // NULL: no flash-record counter; a constant would exempt every chunk
      // from thinning by accident.
      counter: null,
      packetType: bytes[0],
      recTs: null,
      capturedAt: capturedAtMs,
      reason: 'helio_kind_${bytes[0]}',
    );
  }
}

// ── Pairing ─────────────────────────────────────────────────────────────────

/// Pair [device] using the key waiting from the key screen, proving it against
/// the strap before anything is saved. Returns a sentence on failure, null on
/// success. Used as the picker's `pick`.
Future<String?> pairHelio(BluetoothDevice device) async {
  final pending = await readHelioPendingKey();
  if (pending == null) {
    return 'This strap needs its key first. Use “Get the key” in the setup '
        'steps, then come back and pick the strap.';
  }
  final mac = device.remoteId.str.toUpperCase();
  final wanted = pending.mac;
  // Android shows the MAC as the remote id; where it does not, there is
  // nothing to compare and the proof below is the check.
  if (wanted != null && RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac) && wanted != mac) {
    return 'That is not the strap on your Zepp account. Pick the one whose '
        'address ends in ${wanted.substring(wanted.length - 5)}.';
  }
  final rnd = Random.secure();
  final deviceId = 'helio-${_hex(List<int>.generate(4, (_) => rnd.nextInt(256)))}';
  GattBandLink? link;
  var paired = false;
  try {
    return await withSecondaryLinkSlot<String?>(
      timeout: const Duration(seconds: 30),
      onTimeout: () => 'Another sensor is using this phone’s Bluetooth right now. '
          'Try pairing again in a moment.',
      () async {
        try {
          await device.connect(timeout: const Duration(seconds: 20));
          final services = await device.discoverServices();
          final local = GattBandLink(
            entry: kHelio,
            services: services,
            onLog: (m) => debugPrint('[helio pair] $m'),
          );
          link = local;
          if (local.missingCharacteristics(kHelio.requiredCharacteristics).isNotEmpty) {
            return 'That device does not expose the data service this app speaks '
                'for the Helio Strap.';
          }
          final session = HelioSession(local, timeout: const Duration(seconds: 12));
          session.open();
          final String? err;
          try {
            err = await session.authenticate(pending.key);
          } finally {
            await session.close();
          }
          if (err != null) return '$err $_kTryAgain';

          // Proven: the key is stored first, the row last (the row is what makes
          // the strap reachable).
          await _secure.write(
              key: _keyItem(deviceId), value: _hex(pending.key), iOptions: _kApple, mOptions: _kMacos);
          await LocalDb.upsertDevice(
            id: deviceId,
            adapterId: kHelio.id,
            remoteId: device.remoteId.str,
            label: cleanDeviceLabel(device.platformName) ?? kHelio.label,
          );
          paired = true;
          await clearHelioPendingKey();
          return null;
        } finally {
          link?.close();
          try {
            await device.disconnect();
          } catch (_) {/* already gone */}
        }
      },
    );
  } catch (e) {
    debugPrint('[helio pair] failed: $e');
    return 'Could not connect to that device. $_kTryAgain';
  } finally {
    if (!paired) await _dropKey(deviceId);
  }
}
