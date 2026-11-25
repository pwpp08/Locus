// The Helio history fetch against a simulated strap, and the record parsers on
// hand-built payloads laid out as the unstrap spec describes them.

import 'dart:async';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/helio/channel.dart';
import 'package:openstrap_edge/ble/helio/history.dart';

/// A strap serving [payload] for one START: control replies and data packets are
/// handed straight to [client], as the radio would.
class _Strap {
  _Strap(this.payload, {this.compress = false, this.tamper, this.dropPacket = -1});
  final Uint8List payload;
  final bool compress;
  final int Function(int crc)? tamper;
  final int dropPacket;
  late final GdspClient client;
  final seen = <int>[];

  Future<void> handle(Uint8List cmd) async {
    seen.add(cmd[0]);
    // Replies arrive after the command returns, as on a radio.
    Future<void> reply(void Function() f) async => scheduleMicrotask(f);
    switch (cmd[0]) {
      case kGdspStart:
        final wire = compress ? Uint8List.fromList(ZLibCodec().encode(payload)) : payload;
        final t = GdspTime.of(1700000000);
        final w = HelioWriter()
            .u8(0x10)
            .u8(kGdspStart)
            .u8(kGdspOk)
            .u32(payload.isEmpty ? 0 : payload.length);
        t.writeTo(w);
        w.u8(compress ? 1 : 0);
        await reply(() => client.onControl(gdspParse(w.toBytes())));
        _wire = wire;
      case kGdspTransfer:
        final wire = _wire;
        await reply(() {
          var idx = 0;
          for (var o = 0; o < wire.length; o += 18, idx++) {
            if (idx == dropPacket) continue;
            final end = o + 18 < wire.length ? o + 18 : wire.length;
            client.onData(Uint8List.fromList([idx, ...wire.sublist(o, end)]));
          }
          var crc = helioCrc32(wire);
          if (tamper != null) crc = tamper!(crc);
          client.onControl(gdspParse(
              HelioWriter().u8(0x10).u8(kGdspTransfer).u8(kGdspOk).u32(crc).toBytes()));
        });
      case kGdspAck:
        await reply(() => client.onControl(gdspParse([0x10, kGdspAck, kGdspOk])));
    }
  }

  Uint8List _wire = Uint8List(0);
}

GdspClient _client(_Strap s) {
  final c = GdspClient(
    send: s.handle,
    timeout: const Duration(milliseconds: 400),
    trailing: const Duration(milliseconds: 20),
  );
  s.client = c;
  return c;
}

void main() {
  group('codec', () {
    test('GDSP time survives a round trip through the phone zone', () {
      for (final e in [1700000000, 1720000000, 1735000000]) {
        expect(GdspTime.of(e).epochSecond, e);
      }
      expect(const GdspTime(2024, 1, 2, 3, 4, 5, 4).epochSecond,
          DateTime.utc(2024, 1, 2, 3, 4, 5).millisecondsSinceEpoch ~/ 1000 - 3600);
    });

    test('START bytes and the START reply', () {
      final t = GdspTime.of(1700000000);
      final b = gdspStart(73, t);
      expect(b.length, 2 + 8 + 1);
      expect(b.sublist(0, 2), [kGdspStart, 73]);
      expect(b.last, 1);
      final w = HelioWriter().u8(0x10).u8(kGdspStart).u8(kGdspOk).u32(96);
      t.writeTo(w);
      final m = gdspParse(w.u8(1).toBytes()) as GdspStartReply;
      expect((m.size, m.firstEpoch, m.compressed), (96, 1700000000, true));
      final refused = gdspParse([0x10, kGdspStart, 4]) as GdspStartReply;
      expect((refused.ok, refused.size), (false, 0));
    });

    test('data-available, transfer end, and rubbish', () {
      expect((gdspParse([0x11, 5]) as GdspDataAvailable).type, 5);
      final c = gdspParse([0x10, kGdspTransfer, 1, 1, 2, 3, 4]) as GdspTransferComplete;
      expect(c.crc32, 0x04030201);
      expect(gdspParse([]), isA<GdspMalformed>());
      expect(gdspParse([0x10, 1]), isA<GdspMalformed>());
      expect(gdspParse([0x42, 1, 1]), isA<GdspMalformed>());
    });

    test('the version reply lists the types the strap serves', () {
      final v = gdspParse([0x10, kGdspVersion, 1, 2, 1, 2, 0, 1, 1, 73, 0]) as GdspResponse;
      expect(gdspSupportedTypes(v), {1, 73});
      expect(gdspSupportedTypes(gdspParse([0x10, 0, 1, 2]) as GdspResponse), isNull);
    });
  });

  group('fetch', () {
    final payload = Uint8List.fromList(List.generate(100, (i) => (i * 5) & 0xFF));

    test('a transfer comes back whole, and the exchange is START, TRANSFER, ACK', () async {
      final s = _Strap(payload);
      final r = await _client(s).fetch(1, 1699990000);
      expect(r.isChunk, isTrue);
      expect(r.payload, payload);
      expect(r.headerTime, 1700000000);
      expect(s.seen, [kGdspStart, kGdspTransfer, kGdspAck]);
    });

    test('a zlib payload is inflated', () async {
      final r = await _client(_Strap(payload, compress: true)).fetch(1, 1699990000);
      expect(r.payload, payload);
    });

    test('nothing newer is an empty fetch', () async {
      final r = await _client(_Strap(Uint8List(0))).fetch(1, 1699990000);
      expect(r.kind, 'empty');
    });

    test('a wrong CRC and a missing packet fail the chunk', () async {
      final crc = await _client(_Strap(payload, tamper: (c) => c ^ 1)).fetch(1, 1);
      expect((crc.isFailed, crc.ack), (true, kGdspCrcMismatch));
      final gap = await _client(_Strap(payload, dropPacket: 2)).fetch(1, 1);
      expect((gap.isFailed, gap.ack), (true, kGdspPacketIndexError));
    });

    test('a cursor that moved to the same header is the cyclic check', () async {
      final r = await _client(_Strap(payload))
          .fetch(1, 1699990000, previous: const GdspPrevious(1699980000, 1700000000));
      expect((r.isFailed, r.cyclic), (true, true));
    });

    test('no answer is a failed fetch, not a hang', () async {
      final c = GdspClient(
          send: (_) async {}, timeout: const Duration(milliseconds: 60));
      final r = await c.fetch(1, 1);
      expect(r.isFailed, isTrue);
    });

    test('a data-available push during a fetch is remembered', () async {
      final s = _Strap(payload);
      final c = _client(s);
      c.onControl(const GdspDataAvailable(70));
      await c.fetch(1, 1699990000);
      expect(c.pushed, {70});
    });
  });

  group('parsers', () {
    test('activity: per-minute records, blanks flagged, next from the header', () {
      final raw = [
        0x71, 10, 20, 80, 0, 0, 0, 0, // worn, 20 steps, 80 bpm
        0x73, 0, 0, 254, 0, 0, 0, 0, // not worn
        ...List.filled(8, 0xFF), // never written
      ];
      final p = helioParseActivity(raw, 1700000000, helioActivityRecordSize(raw, 3));
      expect(p.records.length, 3);
      expect(p.next, 1700000000 + 3 * 60);
      final a = p.records;
      expect((a[0].hr, a[0].steps, a[0].isWorn, a[0].ts), (80, 20, true, 1700000000));
      expect((a[1].hr, a[1].isWorn), (null, false));
      expect(a[2].isBlank, isTrue);
      expect(helioActivityRecordSize(List.filled(12, 0), 3), 4);
      expect(helioActivityRecordSize(List.filled(16, 0), 0), 8);
    });

    test('sleep result: stages, lengths and the day they belong to', () {
      final w = HelioWriter()
          .u32(1700030000)
          .u32(1700020000)
          .u8(1) // version
          .u8(1); // has main sleep
      w.u16(1500).u16(1900).u16(1480).u16(1910); // main start/end, on/off bed
      w.u8(1).u8(1).u8(0).u8(58).u8(84); // rem, short supported, no short; avg HR, score
      w.u8(0).bytes(List.filled(60, 0)); // no naps
      w.u8(3).u8(0); // three main stages
      for (final (a, b, t) in [(1500, 1600, 4), (1600, 1700, 5), (1700, 1900, 8)]) {
        w.u16(a).u16(b).u8(t);
      }
      w.bytes(List.filled(47 * 5, 0)); // unused main slots
      w.bytes(List.filled(50 * 5, 0)); // unused nap slots
      w.u16(200).u16(100).u16(60).u16(10); // rem, light, deep, wake
      final bytes = w.toBytes();
      expect(bytes.length, kHelioSleepResultSize);
      final r = helioParseSleepResult(bytes).records.single;
      expect((r.score, r.avgHr, r.hasMain), (84, 58, true));
      expect([for (final s in r.mainStages) s.stage], ['light', 'deep', 'rem']);
      expect((r.remMin, r.lightMin, r.deepMin, r.wakeMin), (200, 100, 60, 10));
      expect(r.napStages, isEmpty);
      // 1440 raw minutes is local midnight of the belonging day.
      expect(r.resolve(1440), r.dayStart);
      expect(r.resolve(1500) - r.dayStart, 60 * 60);
      expect(helioParseSleepResult(bytes.sublist(0, 500)).records, isEmpty);
    });

    test('daily values: HRV and resting heart rate', () {
      final raw = HelioWriter().u32(1700000000).u8(4).u8(48).u32(1700086400).u8(4).u8(52).toBytes();
      final p = helioParseDailyValue(raw);
      expect([for (final x in p.records) x.value], [48, 52]);
      expect(p.next, 1700086401);
    });

    test('SpO2: plain 5-byte records, and the v2 form with history', () {
      final plain = HelioWriter().u32(1700000000).u8(0x80 | 97).toBytes();
      final p = helioParseSpo2(plain, 1700000000).records.single;
      expect((p.spo2, p.isAuto, p.plausible), (97, true, true));
      final v2 = HelioWriter().u8(2).u32(1700000100).u8(95).bytes(List.filled(60, 0)).toBytes();
      final q = helioParseSpo2(v2, 1700000000).records.single;
      expect((q.ts, q.spo2, q.isAuto), (1700000100, 95, false));
      expect(helioParseSpo2([], 1).records, isEmpty);
    });

    test('stress and skin temperature are per minute from the header', () {
      final s = helioParseStressAllDay([30, 0, 254, 41], 1700000000);
      expect(s.records.length, 4);
      expect(s.records[3].ts, 1700000180);
      expect(s.next, 1700000000 + 4 * 60 + 1);
      final t = helioParseSkinTemp(
          HelioWriter().u16(2200).u16(3301).u32(0).u16(2200).u16(0x7FFF).u32(0).u16(2200).u16(1500).u32(0).toBytes(),
          1700000000);
      expect(t.records[0].skinC, 33.01);
      expect(t.records[1].skinC, isNull, reason: 'no reading');
      expect(t.records[2].skinC, isNull, reason: 'below 20 C is off-wrist');
    });
  });
}
