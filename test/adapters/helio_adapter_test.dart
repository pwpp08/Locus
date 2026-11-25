// The Helio session end to end against a simulated strap: channel version,
// service list, key handshake, the pong, the payload size, and history fetches
// over the encrypted history endpoint with the bulk packets on 0005.
//
// The simulated strap is written from the protocol notes, not from the adapter,
// so a misreading shared by both would still pass: what this proves is that
// the pieces fit together, not that a real strap agrees.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart';
import 'package:openstrap_edge/ble/adapters/adapter.dart';
import 'package:openstrap_edge/ble/adapters/helio.dart';
import 'package:openstrap_edge/ble/helio/b163.dart';
import 'package:openstrap_edge/ble/helio/channel.dart';
import 'package:openstrap_edge/ble/helio/history.dart';

Uint8List _key(int seed) => Uint8List.fromList(List.generate(16, (i) => (i * seed + 3) & 0xFF));

/// The strap side of one connection.
class _Strap {
  _Strap(this.link, this.key, this.data) {
    link.onWrite = _onWrite;
    _reassembler = HelioReassembler(
      isKnownEndpoint: (_) => true,
      decrypt: (s, c, n) => _cipher!.decrypt(s, c, n),
      onMessage: _onMessage,
    );
  }

  final ReplayBandLink link;
  final Uint8List key;

  /// Type -> its raw payload and the first record's time.
  final Map<int, (Uint8List, int)> data;

  final started = <int>[];
  final since = <int>[];
  final pongs = <int>[];
  bool silent = false;
  HelioCipher? _cipher;
  late final HelioReassembler _reassembler;
  final _keys = B163KeyPair.generate(Random(3));
  final _challenge = Uint8List.fromList(List.generate(16, (i) => i * 7));
  final _served = <int>{};
  Uint8List _wire = Uint8List(0);
  int _sid = 100;

  void _feed(String char, List<int> v) => link.feed(char, v, atSec: 0);

  void _onWrite(String char, List<int> v) {
    if (silent) return;
    if (char == kHelioCmdChar) {
      if (v.length == 1 && v[0] == 1) {
        _feed(kHelioCmdChar, [2, 2, 1]);
      } else {
        final ack = _reassembler.accept(v);
        if (ack != null) _feed(kHelioCmdChar, ack);
      }
    }
  }

  void _say(int endpoint, List<int> payload) {
    final enc = endpoint == kEpHistory;
    final sid = _sid++ & 0xFF;
    final body = enc ? _cipher!.encrypt(sid, payload) : payload;
    for (final c in helioBuildChunks(
      endpoint: endpoint,
      sessionId: sid,
      data: body,
      plainLength: payload.length,
      encrypted: enc,
      payloadMtu: 244,
      wantReply: false,
    )) {
      _feed(kHelioDataChar, c);
    }
  }

  void _onMessage(HelioMessage m) {
    final p = m.payload;
    switch (m.endpoint) {
      case kEpServices:
        // v2 list: 04 count, then {endpoint u16, requires-encryption}.
        _say(kEpServices, [4, 3, 0, 0x15, 0, 0, 0x4B, 0, 1, 0x82, 0, 0]);
        _say(kEpConnect, [3]); // a ping, answered by the phone
      case kEpConnect:
        if (p[0] == 1) _say(kEpConnect, [2, 0xF7, 0]);
        if (p[0] == 4) pongs.add(1);
      case kEpAuth:
        if (p[0] == 4) {
          final c = HelioCipher(b163SharedSecret(_keys.privateKey, p.sublist(4)), key);
          final t = c.txCounter;
          c.txCounter = c.rxCounter;
          c.rxCounter = t;
          _cipher = c;
          _say(kEpAuth, [0x10, 4, 1, ..._challenge, ..._keys.publicKey]);
        } else if (p[0] == 5) {
          final ok = Iterable.generate(16, (i) => i).every(
                  (i) => p[1 + i] == helioAesEncrypt(key, _challenge)[i]) &&
              Iterable.generate(16, (i) => i).every(
                  (i) => p[17 + i] == helioAesEncrypt(_cipher!.sessionKey, _challenge)[i]);
          _say(kEpAuth, [0x10, 5, ok ? 1 : 0x26]);
        }
      case kEpHistory:
        switch (p[0]) {
          case kGdspVersion:
            _say(kEpHistory, [0x10, 0, 1, 2, 1, 2, 0, 73, 1, 58, 1]);
          case kGdspStart:
            final type = p[1];
            started.add(type);
            since.add(GdspTime.read(HelioReader(p, 2)).epochSecond);
            final d = data[type];
            final w = HelioWriter().u8(0x10).u8(kGdspStart).u8(kGdspOk);
            if (d == null || !_served.add(type)) {
              w.u32(0);
              GdspTime.of(1700000000).writeTo(w);
              w.u8(0);
              _wire = Uint8List(0);
            } else {
              w.u32(d.$1.length);
              GdspTime.of(d.$2).writeTo(w);
              w.u8(0);
              _wire = d.$1;
            }
            _say(kEpHistory, w.toBytes());
          case kGdspTransfer:
            var idx = 0;
            for (var o = 0; o < _wire.length; o += 18, idx++) {
              final end = o + 18 < _wire.length ? o + 18 : _wire.length;
              _feed(kHelioGdspChar, [idx, ..._wire.sublist(o, end)]);
            }
            _say(kEpHistory,
                HelioWriter().u8(0x10).u8(kGdspTransfer).u8(kGdspOk).u32(helioCrc32(_wire)).toBytes());
          case kGdspAck:
            _say(kEpHistory, [0x10, kGdspAck, kGdspOk]);
        }
    }
  }
}

HelioAdapter _adapter(Uint8List key, {String cursors = ''}) => HelioAdapter(
      authKey: key,
      cursors: cursors,
      nowSeconds: () => 1700100000,
      step: const Duration(milliseconds: 400),
      gdspTimeout: const Duration(seconds: 2),
      window: const Duration(seconds: 30),
    );

Uint8List _daily(List<(int, int)> rows) {
  final w = HelioWriter();
  for (final (ts, v) in rows) {
    w.u32(ts).u8(4).u8(v);
  }
  return w.toBytes();
}

void main() {
  final hrv = _daily([(1700000000, 48), (1700086400, 52)]);
  final rhr = _daily([(1700000000, 55)]);

  test('a full session: handshake, pong, MTU, and two kinds of history', () async {
    final link = ReplayBandLink();
    final strap = _Strap(link, _key(5), {73: (hrv, 1700000000), 58: (rhr, 1700000000)});
    final events = await _adapter(_key(5)).run(link).toList();

    expect(events.whereType<BandNote>().map((n) => n.key), contains('helio_auth'));
    expect(strap.pongs, isNotEmpty, reason: 'the ping was answered');
    // The plan is the strap's list narrowed to what is read, night kinds first:
    // 73 then 58, each asked a second time and answered empty.
    expect(strap.started, [73, 73, 58, 58]);

    final rows = [for (final e in events.whereType<VendorScalars>()) ...e.rows];
    expect([for (final r in rows.where((r) => r.vendorKey == 'hrv_last_night_avg')) r.value], [48, 52]);
    final rhrRow = rows.singleWhere((r) => r.key == 'resting_hr');
    expect((rhrRow.value, rhrRow.attribution), (55, kHelioAttribution));

    // Every chunk was banked verbatim with its kind in front.
    final raws = [for (final b in events.whereType<SampleBatch>()) ...?b.raw];
    expect(raws.map((r) => r[0]).toSet(), {73, 58});

    // The last cursor note moves each kind past its last record.
    final cur = HelioCursors.decode(
        events.whereType<BandNote>().where((n) => n.key == 'helio_cursor').last.value! as String);
    expect(cur.cursor(73), 1700086401);
    expect(cur.cursor(58), 1700000001);
    expect(events.whereType<OffloadCheckpoint>().length, 2);
  });

  test('the next session starts where the cursor says', () async {
    final link = ReplayBandLink();
    final strap = _Strap(link, _key(5), {73: (hrv, 1700000000)});
    await _adapter(_key(5), cursors: '73:1700086401:1700000000').run(link).toList();
    expect(strap.started.first, 73);
    expect(strap.since.first, 1700086401);
  });

  test('a first session reaches back the first window', () async {
    final link = ReplayBandLink();
    final strap = _Strap(link, _key(5), {});
    await _adapter(_key(5)).run(link).toList();
    expect(strap.since.first, 1700100000 - 14 * 86400);
  });

  test('a wrong key is reported in words and nothing is fetched', () async {
    final link = ReplayBandLink();
    final strap = _Strap(link, _key(5), {73: (hrv, 1700000000)});
    final events = await _adapter(_key(9)).run(link).toList();
    final fail = events.whereType<BandNote>().singleWhere((n) => n.key == 'helio_auth_failed');
    expect(fail.value, isA<String>());
    expect((fail.value! as String).toLowerCase(), contains('authentication failed'));
    expect(strap.started, isEmpty);
    expect(events.whereType<SampleBatch>(), isEmpty);
  });

  test('a strap that does not answer ends the session quietly', () async {
    final link = ReplayBandLink();
    final strap = _Strap(link, _key(5), {})..silent = true;
    final events = await HelioAdapter(
      authKey: _key(5),
      step: const Duration(milliseconds: 150),
    ).run(link).toList();
    expect(events.whereType<BandNote>().single.key, 'helio_auth_failed');
    expect(strap.started, isEmpty);
  });

  test('cursors survive a round trip and ignore rubbish', () {
    final c = HelioCursors()..set(73, 5, 3)..set(1, 9, 7);
    final d = HelioCursors.decode(c.encode());
    expect((d.cursor(73), d.header(73), d.cursor(1), d.header(1)), (5, 3, 9, 7));
    expect(HelioCursors.decode('x;1:2;a:b:c').encode(), '');
  });

  test('the registry knows the strap by name and by service', () {
    expect(kHelio.id, 'helio');
    expect(kHelio.service, kHelioService);
    expect(kHelio.scanByName, isTrue);
    expect(kHelio.nameMatcher!('amazfit helio strap'), isTrue);
    expect(kHelio.nameMatcher!('stuttgart'), isTrue);
    expect(kHelio.nameMatcher!('mi band 3'), isFalse);
    expect(HelioAdapter(authKey: _key(1)).signals, kAdapterSignals['helio']);
  });
}
