// The Helio channel: curve maths, session crypto, chunk framing, services list
// and the authentication handshake, against a simulated strap. Vectors follow
// the open-source unstrap project's spec and tests.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/helio/b163.dart';
import 'package:openstrap_edge/ble/helio/channel.dart';

Uint8List _hex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

bool _eq(List<int> a, List<int> b) =>
    a.length == b.length && List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);

void main() {
  group('B-163', () {
    test('the generator is on the curve and has order n', () {
      expect(b163IsOnCurve(kB163G), isTrue);
      expect(b163Multiply(kB163N, kB163G).isInfinity, isTrue);
      // (n - 1) * G is -G: the same x.
      expect(b163Multiply(kB163N - BigInt.one, kB163G).x, kB163Gx);
    });

    test('field inverse', () {
      final a = BigInt.parse('123456789abcdef0123456789abcdef01234567', radix: 16);
      expect(b163Mul(a, b163Inv(a)), BigInt.one);
    });

    test('ECDH is symmetric, 24 bytes, little-endian', () {
      final rnd = Random(7);
      final a = B163KeyPair.generate(rnd), b = B163KeyPair.generate(rnd);
      expect(a.publicKey.length, 48);
      final s1 = b163SharedSecret(a.privateKey, b.publicKey);
      final s2 = b163SharedSecret(b.privateKey, a.publicKey);
      expect(s1, s2);
      expect(s1.length, 24);
      // The generator encoded little-endian: Gx's lowest byte (0x36) first.
      final g = b163EncodePoint(kB163G);
      expect(g[0], 0x36);
      expect(g[23], 0x00);
    });

    test('a key that is not on the curve is refused', () {
      expect(() => b163DecodePoint(Uint8List(48)..[0] = 1), throwsArgumentError);
      expect(() => b163DecodePoint(Uint8List(47)), throwsArgumentError);
    });
  });

  group('crypto', () {
    test('CRC-32 of the standard check string', () {
      expect(helioCrc32('123456789'.codeUnits), 0xCBF43926);
    });

    test('AES-128-ECB known answer (FIPS-197)', () {
      final key = _hex('000102030405060708090a0b0c0d0e0f');
      final plain = _hex('00112233445566778899aabbccddeeff');
      final cipher = helioAesEncrypt(key, plain);
      expect(cipher, _hex('69c4e0d86a7b0430d8cdb78070b4c55a'));
      expect(helioAesDecrypt(key, cipher), plain);
    });

    test('a message survives encryption; damage and a wrong session do not', () {
      final secret = Uint8List.fromList(List.generate(24, (i) => i * 3 + 1));
      final key = _hex('00112233445566778899aabbccddeeff');
      final phone = HelioCipher(secret, key);
      // The strap's view: its counters are ours, swapped.
      final strap = HelioCipher(secret, key)
        ..rxCounter = phone.txCounter
        ..txCounter = phone.rxCounter;
      final payload = Uint8List.fromList(List.generate(37, (i) => i));
      final c = phone.encrypt(9, payload);
      expect(c.length, helioEncryptedSize(37));
      expect(strap.decrypt(9, c, 37), payload);
      expect(() => strap.decrypt(10, c, 37), throwsA(isA<HelioDecryptException>()));
      final bad = Uint8List.fromList(c)..[3] ^= 1;
      expect(() => strap.decrypt(9, bad, 37), throwsA(isA<HelioDecryptException>()));
      expect(() => strap.decrypt(9, c.sublist(0, 16), 37),
          throwsA(isA<HelioDecryptException>()));
    });
  });

  group('chunks', () {
    test('the services request, as in the spec', () {
      final c = helioBuildChunks(
        endpoint: 0,
        sessionId: 0,
        data: [0x03],
        plainLength: 1,
        encrypted: false,
        payloadMtu: 20,
      );
      expect(c.single, _hex('030700000001000000000003'));
    });

    test('a 52-byte message is four chunks at the default size', () {
      final c = helioBuildChunks(
        endpoint: kEpAuth,
        sessionId: 5,
        data: List.filled(52, 7),
        plainLength: 52,
        encrypted: false,
        payloadMtu: 20,
      );
      expect(c.length, 4);
      expect(c.map((x) => x[1]).toList(), [0x01, 0x00, 0x00, 0x06]);
      expect([for (var i = 0; i < c.length; i++) c[i].length - (i == 0 ? 11 : 5)],
          [9, 15, 15, 13]);
      expect(u32(c.first, 5), 52);
      expect(u16(c.first, 9), kEpAuth);
    });

    test('reassembly returns the message and acks only when asked', () {
      final got = <HelioMessage>[];
      final r = HelioReassembler(
        isKnownEndpoint: (e) => e == kEpAuth,
        decrypt: (s, c, n) => throw StateError('plaintext only'),
        onMessage: got.add,
      );
      final data = List<int>.generate(52, (i) => i);
      final chunks = helioBuildChunks(
        endpoint: kEpAuth,
        sessionId: 5,
        data: data,
        plainLength: 52,
        encrypted: false,
        payloadMtu: 20,
      );
      final acks = [for (final c in chunks) r.accept(c)];
      expect(got.single.payload, data);
      expect(got.single.endpoint, kEpAuth);
      expect(acks.take(3), everyElement(isNull));
      expect(acks.last, helioBuildAck(5, kAckSuccess, 3));
    });

    test('a lost chunk, an unknown endpoint and a stray continuation', () {
      final got = <HelioMessage>[];
      final r = HelioReassembler(
        isKnownEndpoint: (e) => e == kEpAuth,
        decrypt: (s, c, n) => c,
        onMessage: got.add,
      );
      final chunks = helioBuildChunks(
        endpoint: kEpAuth,
        sessionId: 1,
        data: List.filled(40, 1),
        plainLength: 40,
        encrypted: false,
        payloadMtu: 20,
      );
      expect(r.accept(chunks[0]), isNull);
      expect(r.accept(chunks[2]), helioBuildAck(1, kAckPacketLost, 2));
      expect(got, isEmpty);
      expect(r.accept(chunks[1]), isNull, reason: 'no message in progress');
      final other = helioBuildChunks(
        endpoint: 0x0999,
        sessionId: 2,
        data: [1],
        plainLength: 1,
        encrypted: false,
        payloadMtu: 20,
      );
      expect(r.accept(other.single), helioBuildAck(2, kAckUnknownEndpoint, 0));
    });

    test('an encrypted message round-trips through chunks', () {
      final secret = Uint8List.fromList(List.generate(24, (i) => i + 9));
      final key = _hex('ffeeddccbbaa99887766554433221100');
      final tx = HelioCipher(secret, key);
      final rx = HelioCipher(secret, key)..rxCounter = tx.txCounter;
      final got = <HelioMessage>[];
      final r = HelioReassembler(
        isKnownEndpoint: (_) => true,
        decrypt: (s, c, n) => rx.decrypt(s, c, n),
        onMessage: got.add,
      );
      final payload = Uint8List.fromList(List.generate(70, (i) => 255 - i));
      final body = tx.encrypt(3, payload);
      for (final c in helioBuildChunks(
        endpoint: kEpHistory,
        sessionId: 3,
        data: body,
        plainLength: 70,
        encrypted: true,
        payloadMtu: 20,
      )) {
        r.accept(c);
      }
      expect(got.single.payload, payload);
      expect(got.single.encrypted, isTrue);
    });
  });

  group('services and ACKs', () {
    test('services list parse, change push, and trailing bytes', () {
      final reply = [0x04, 0x02, 0x00, 0x4B, 0x00, 0x01, 0x82, 0x00, 0x00];
      final s = HelioServiceList.parse(reply);
      expect(s.has(kEpHistory), isTrue);
      expect(s.requiresEncryption(kEpHistory), isTrue);
      expect(s.requiresEncryption(kEpAuth), isFalse);
      expect(() => HelioServiceList.parse([...reply, 0]), throwsFormatException);
      final added = s.applyChange([0x05, 0x01, 0x29, 0x00, 0x01])!;
      expect(added.requiresEncryption(kEpBattery), isTrue);
      expect(added.applyChange([0x05, 0x02, 0x29, 0x00])!.has(kEpBattery), isFalse);
      expect(s.applyChange([0x05, 0x09, 0x29, 0x00]), isNull);
    });

    test('device ACKs: both layouts, nothing else', () {
      final a5 = helioParseDeviceAck([4, 0, 7, 1, 2])!;
      expect((a5.sessionId, a5.status, a5.chunkIndex), (7, 1, 2));
      final a4 = helioParseDeviceAck([4, 7, 1, 2])!;
      expect((a4.sessionId, a4.status, a4.chunkIndex), (7, 1, 2));
      expect(helioParseDeviceAck([4, 1, 7, 1, 2]), isNull);
      expect(helioParseDeviceAck([3, 0, 7, 1, 2]), isNull);
    });

    test('channel version reply', () {
      final v = HelioChannelVersion.parse([2, 2, 1])!;
      expect((v.version, v.encryptEnable), (2, true));
      expect(HelioChannelVersion.parse([2, 2])!.encryptEnable, isNull);
      expect(HelioChannelVersion.parse([1, 2]), isNull);
    });
  });

  group('authentication', () {
    final key = _hex('00112233445566778899aabbccddeeff');

    // The device side of the already-bound handshake.
    (Uint8List Function(Uint8List), Uint8List Function(Uint8List), HelioCipher Function())
        fakeStrap(List<int> authKey) {
      final keys = B163KeyPair.generate(Random(3));
      final challenge = Uint8List.fromList(List.generate(16, (i) => i * 7));
      late HelioCipher cipher;
      return (
        (req) {
          expect(req.length, 52);
          expect(req.sublist(0, 4), [4, 2, 0, 2]);
          cipher = HelioCipher(b163SharedSecret(keys.privateKey, req.sublist(4)), authKey);
          return Uint8List.fromList([1, ...challenge, ...keys.publicKey]);
        },
        (req) {
          final ok = req[0] == 5 &&
              _eq(req.sublist(1, 17), helioAesEncrypt(authKey, challenge)) &&
              _eq(req.sublist(17, 33), helioAesEncrypt(cipher.sessionKey, challenge));
          return Uint8List.fromList([ok ? 1 : 0x26]);
        },
        () => cipher,
      );
    }

    test('both sides agree on the session key', () {
      final (step1, step2, cipherOf) = fakeStrap(key);
      final hs = HelioAuthHandshake(key, keys: B163KeyPair.generate(Random(11)));
      final next = hs.handleStep1Reply(step1(hs.step1Request));
      expect(next.length, 33);
      final cipher = hs.handleStep2Reply(step2(next));
      expect(cipher.sessionKey, cipherOf().sessionKey);
      expect(cipher.txCounter, cipherOf().txCounter);
    });

    test('a wrong key is reported by name', () {
      final (step1, step2, _) = fakeStrap(key);
      final hs = HelioAuthHandshake(_hex('ffeeddccbbaa99887766554433221100'),
          keys: B163KeyPair.generate(Random(12)));
      final next = hs.handleStep1Reply(step1(hs.step1Request));
      expect(
          () => hs.handleStep2Reply(step2(next)),
          throwsA(isA<HelioAuthException>()
              .having((e) => e.status, 'status', 0x26)
              .having((e) => e.message, 'message', contains('wrong auth key'))));
    });

    test('a refused key exchange, and the reply prefix', () {
      final hs = HelioAuthHandshake(key);
      expect(() => hs.handleStep1Reply([7]), throwsA(isA<HelioAuthException>()));
      expect(helioAuthStripReply(4, [0x10, 4, 1, 9]), [1, 9]);
      expect(helioAuthStripReply(4, [5, 1, 9]), isNull);
    });

    test('auth key text', () {
      expect(helioParseAuthKey('0x00112233445566778899AABBCCDDEEFF'), key);
      expect(helioParseAuthKey('00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff'), key);
      expect(helioParseAuthKey('0011'), isNull);
      expect(helioParseAuthKey('zz112233445566778899aabbccddeeff'), isNull);
    });
  });
}
