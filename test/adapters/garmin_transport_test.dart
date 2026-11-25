// A Garmin watch with no Multi-Link service speaks GFDI straight on one write
// and one notify characteristic. That transport must carry the same
// conversation without the Multi-Link handshake or its handle byte, and a
// Multi-Link watch must be driven exactly as before.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart'
    show kGarminNotifyChar, kGarminWriteChar;
import 'package:openstrap_edge/ble/adapters/adapter.dart';
import 'package:openstrap_edge/ble/adapters/garmin.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

class _FakeLink implements BandLink {
  final writes = <(String, List<int>)>[];
  final logs = <String>[];
  final _quiet = StreamController<(int, List<int>)>.broadcast();

  @override
  Stream<(int, List<int>)> notify(String characteristicUuid) =>
      _quiet.stream; // open, like a live connection that says nothing yet

  @override
  Future<List<int>?> read(String characteristicUuid) async => null;

  @override
  Future<bool> write(String characteristicUuid, List<int> value) async {
    writes.add((characteristicUuid, value));
    return true;
  }

  @override
  void log(String message) => logs.add(message);

  @override
  Future<void> close() async {}
}

void main() {
  group('which characteristics', () {
    test('the newer single pair, then the older one, else none', () {
      final v1 = garminLegacyPair([kGarminGfdiV1Send, kGarminGfdiV1Receive]);
      expect(v1?.notify, kGarminGfdiV1Receive);
      expect(v1?.write, kGarminGfdiV1Send);
      final v0 = garminLegacyPair(
          [kGarminGfdiV0Send.toUpperCase(), kGarminGfdiV0Receive]);
      expect(v0?.write, kGarminGfdiV0Send);
      expect(garminLegacyPair([kGarminGfdiV1Send]), isNull,
          reason: 'half a pair is not a transport');
      expect(garminHasTransport([kGarminNotifyChar, kGarminWriteChar]), isTrue);
      expect(garminHasTransport([kGarminGfdiV1Send, kGarminGfdiV1Receive]), isTrue);
      expect(garminHasTransport(const ['2a37']), isFalse);
    });
  });

  group('session', () {
    GarminAdapter adapter({bool legacy = true}) => GarminAdapter(
          mlChars: legacy ? const [] : const [kGarminNotifyChar, kGarminWriteChar],
          legacyChars: legacy
              ? (notify: kGarminGfdiV1Receive, write: kGarminGfdiV1Send)
              : null,
          handshakeTimeout: const Duration(milliseconds: 30),
          registerTimeout: const Duration(milliseconds: 30),
          configWait: const Duration(milliseconds: 30),
          sessionWindow: const Duration(milliseconds: 250),
          maxWrite: 20,
        );

    test('single characteristic: no handshake, no handle byte, then the sync asks', () async {
      final link = _FakeLink();
      await adapter().run(link).toList().timeout(const Duration(seconds: 5));
      // Everything went to the single write characteristic.
      expect(link.writes.map((w) => w.$1).toSet(), {kGarminGfdiV1Send});
      final stream = [for (final w in link.writes) ...w.$2];
      final expected = [
        ...garminCobsEncode(garminBuildProtobufRequest(
          requestId: 1,
          protoBytes: garminBatteryRequestProto(),
        )),
        ...garminCobsEncode(garminBuildDownloadRequest(0)),
      ];
      expect(stream, expected,
          reason: 'the battery ask and the directory request, COBS-framed, '
              'with no Multi-Link control frame and no routing byte');
      // Cut to the write size less one, as the Multi-Link path does.
      expect(link.writes.every((w) => w.$2.length <= 19), isTrue);
    });

    test('multi-link: still opens with close-all on handle 0', () async {
      final link = _FakeLink();
      await adapter(legacy: false)
          .run(link)
          .toList()
          .timeout(const Duration(seconds: 5));
      expect(link.writes, isNotEmpty);
      expect(link.writes.first.$1, kGarminWriteChar);
      expect(Uint8List.fromList(link.writes.first.$2),
          Uint8List.fromList(garminEncodeTx(0, garminCloseAllRequest())));
    });

    test('no characteristic at all ends the session quietly', () async {
      final link = _FakeLink();
      final out = await const GarminAdapter(mlChars: [])
          .run(link)
          .toList()
          .timeout(const Duration(seconds: 5));
      expect(out, isEmpty);
      expect(link.writes, isEmpty);
    });
  });
}
