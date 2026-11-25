// The Amazfit Helio Strap's "channel" transport: chunk framing, the encrypted
// message format, the supported-services list and the ECDH authentication.
//
// A Dart port of the open-source `unstrap` project's protocol module (MIT/
// Apache-2.0, github.com/sayed0am/unstrap, whose docs/protocol/01 is the wire
// specification and which checked each step against a real strap). Pure: bytes
// in, bytes out, so every rule has a test and none needs a radio.
//
// All integers on the wire are little-endian.

import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'b163.dart';

int u8(List<int> b, int at) => b[at] & 0xFF;
int u16(List<int> b, int at) => u8(b, at) | (u8(b, at + 1) << 8);
int u32(List<int> b, int at) => u16(b, at) | (u16(b, at + 2) << 16);

/// Little-endian byte builder.
class HelioWriter {
  final _out = BytesBuilder(copy: false);
  HelioWriter u8(int v) {
    _out.addByte(v & 0xFF);
    return this;
  }

  HelioWriter u16(int v) => u8(v).u8(v >> 8);
  HelioWriter u32(int v) => u16(v & 0xFFFF).u16((v >> 16) & 0xFFFF);
  HelioWriter bytes(List<int> b) {
    _out.add(b);
    return this;
  }

  Uint8List toBytes() => _out.toBytes();
}

/// Little-endian sequential reader.
class HelioReader {
  final List<int> data;
  int pos;
  HelioReader(this.data, [this.pos = 0]);
  int get remaining => data.length - pos;
  int readU8() => data[pos++] & 0xFF;
  int readS8() => (data[pos++] << 24) >> 24;
  int readU16() {
    final v = u16(data, pos);
    pos += 2;
    return v;
  }

  int readS16() => (readU16() << 48) >> 48;
  int readU32() {
    final v = u32(data, pos);
    pos += 4;
    return v;
  }

  bool readBool() => readU8() != 0;
  Uint8List readBytes(int n) {
    final v = Uint8List.fromList(data.sublist(pos, pos + n));
    pos += n;
    return v;
  }
}

// ── CRC32 and AES ───────────────────────────────────────────────────────────

final List<int> _crcTable = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

/// Standard IEEE / zlib CRC-32.
int helioCrc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List _aes(bool encrypt, List<int> key, List<int> data) {
  if (key.length != 16 || data.length % 16 != 0) {
    throw ArgumentError('AES-128-ECB needs a 16-byte key and whole blocks');
  }
  final engine = AESEngine()..init(encrypt, KeyParameter(Uint8List.fromList(key)));
  final src = Uint8List.fromList(data);
  final out = Uint8List(src.length);
  for (var o = 0; o < src.length; o += 16) {
    engine.processBlock(src, o, out, o);
  }
  return out;
}

/// AES-128-ECB without padding, the only block primitive the strap uses.
Uint8List helioAesEncrypt(List<int> key, List<int> data) => _aes(true, key, data);
Uint8List helioAesDecrypt(List<int> key, List<int> data) => _aes(false, key, data);

class HelioDecryptException implements Exception {
  final String message;
  const HelioDecryptException(this.message);
  @override
  String toString() => message;
}

int _ceil16(int n) => (n + 15) ~/ 16 * 16;

/// Bytes an encrypted message of [totalLength] plaintext bytes occupies.
int helioEncryptedSize(int totalLength) => _ceil16(totalLength + 8);

/// Per-connection channel encryption, derived from the ECDH shared secret (24
/// bytes) and the 16-byte auth key.
class HelioCipher {
  static const int _mod = 0xFFFFFFFF;
  static const int _replayWindow = 100000;

  final Uint8List sessionKey;
  int txCounter, rxCounter;

  HelioCipher._(this.sessionKey, this.txCounter, this.rxCounter);

  factory HelioCipher(List<int> sharedSecret, List<int> authKey) {
    if (sharedSecret.length < 24 || authKey.length != 16) {
      throw ArgumentError('Shared secret >= 24 bytes and a 16-byte auth key');
    }
    return HelioCipher._(
      Uint8List.fromList([for (var i = 0; i < 16; i++) sharedSecret[8 + i] ^ authKey[i]]),
      u32(sharedSecret, 0),
      u32(sharedSecret, 4),
    );
  }

  Uint8List _messageKey(int sessionId) =>
      Uint8List.fromList([for (final b in sessionKey) b ^ sessionId]);

  /// The ciphertext; the first chunk's total length stays the plaintext size.
  Uint8List encrypt(int sessionId, List<int> payload) {
    final withCounter = HelioWriter().bytes(payload).u32(txCounter).toBytes();
    final plain = HelioWriter().bytes(withCounter).u32(helioCrc32(withCounter)).toBytes();
    final padded = Uint8List(_ceil16(plain.length))..setAll(0, plain);
    txCounter = (txCounter + 1) % _mod;
    return helioAesEncrypt(_messageKey(sessionId), padded);
  }

  Uint8List decrypt(int sessionId, List<int> cipher, int totalLength) {
    if (cipher.length != helioEncryptedSize(totalLength)) {
      throw HelioDecryptException('Bad encrypted length ${cipher.length}');
    }
    final plain = helioAesDecrypt(_messageKey(sessionId), cipher);
    final payload = Uint8List.fromList(plain.sublist(0, totalLength));
    final counter = u32(plain, totalLength);
    final crc = u32(plain, totalLength + 4);
    if (helioCrc32(plain.sublist(0, totalLength + 4)) != crc) {
      throw const HelioDecryptException('CRC mismatch');
    }
    if (((counter - rxCounter) + _mod) % _mod > _replayWindow) {
      throw const HelioDecryptException('Counter outside replay window');
    }
    rxCounter = counter;
    return payload;
  }
}

// ── Chunk framing (v2) ──────────────────────────────────────────────────────

const int kChunkFirst = 0x01;
const int kChunkLast = 0x02;
const int kChunkNeedsAck = 0x04;
const int kChunkEncrypted = 0x08;

const int kPacketData = 0x03;
const int kPacketAck = 0x04;

const int kAckSuccess = 1;
const int kAckSessionMismatch = 2;
const int kAckPacketLost = 3;
const int kAckBadFormat = 4;
const int kAckUnknownEndpoint = 5;

const int _firstHeader = 11;
const int _nextHeader = 5;
const int _replyFreq = 16;

/// Splits one logical message into chunks for the phone-to-device characteristic
/// (0016). [data] is the already-encrypted body when [encrypted]; [plainLength]
/// is always the plaintext size.
List<Uint8List> helioBuildChunks({
  required int endpoint,
  required int sessionId,
  required List<int> data,
  required int plainLength,
  required bool encrypted,
  required int payloadMtu,
  bool wantReply = true,
}) {
  if (payloadMtu <= _firstHeader) {
    throw ArgumentError('Payload MTU too small: $payloadMtu');
  }
  final chunks = <Uint8List>[];
  var offset = 0, index = 0;
  do {
    final first = index == 0;
    final room = payloadMtu - (first ? _firstHeader : _nextHeader);
    final left = data.length - offset;
    final n = room < left ? room : left;
    final last = offset + n >= data.length;
    var flags = 0;
    if (first) flags |= kChunkFirst;
    if (last) flags |= kChunkLast;
    if (encrypted) flags |= kChunkEncrypted;
    if ((last && wantReply) || (index + 1) % _replyFreq == 0) flags |= kChunkNeedsAck;
    final w = HelioWriter().u8(kPacketData).u8(flags).u8(0).u8(sessionId).u8(index);
    if (first) w.u32(plainLength).u16(endpoint);
    w.bytes(data.sublist(offset, offset + n));
    chunks.add(w.toBytes());
    offset += n;
    index = (index + 1) & 0xFF;
  } while (offset < data.length);
  return chunks;
}

Uint8List helioBuildAck(int sessionId, int status, int chunkIndex) =>
    HelioWriter().u8(kPacketAck).u8(0).u8(sessionId).u8(status).u8(chunkIndex).toBytes();

class HelioDeviceAck {
  final int sessionId, status, chunkIndex;
  const HelioDeviceAck(this.sessionId, this.status, this.chunkIndex);
}

/// A device ACK received on 0016: `04 00 sess status idx` (the strap's form), or
/// the 4-byte `04 sess status idx`. Anything else is not one.
HelioDeviceAck? helioParseDeviceAck(List<int> p) {
  if (p.length < 4 || u8(p, 0) != kPacketAck) return null;
  if (p.length == 4) return HelioDeviceAck(u8(p, 1), u8(p, 2), u8(p, 3));
  if (u8(p, 1) != 0) return null;
  return HelioDeviceAck(u8(p, 2), u8(p, 3), u8(p, 4));
}

class HelioMessage {
  final int endpoint, sessionId;
  final Uint8List payload;
  final bool encrypted;
  const HelioMessage(this.endpoint, this.sessionId, this.payload, this.encrypted);
}

/// Reassembles device-to-phone chunks from 0017. [accept] takes one
/// notification and returns the ACK bytes to write back to 0017, if any;
/// finished messages go to [onMessage].
class HelioReassembler {
  final bool Function(int endpoint) isKnownEndpoint;
  final Uint8List Function(int sessionId, Uint8List cipher, int totalLength) decrypt;
  final void Function(HelioMessage) onMessage;
  void Function(Object) onDecryptFailure = (_) {};

  HelioReassembler({
    required this.isKnownEndpoint,
    required this.decrypt,
    required this.onMessage,
  });

  int _session = -1, _endpoint = 0, _total = 0, _lastIndex = 0;
  bool _encrypted = false;
  final _buf = BytesBuilder(copy: false);

  void _reset() {
    _session = -1;
    _buf.clear();
  }

  Uint8List? accept(List<int> packet) {
    if (packet.length < _nextHeader ||
        u8(packet, 0) != kPacketData ||
        u8(packet, 2) != 0) {
      return null;
    }
    final flags = u8(packet, 1), session = u8(packet, 3), index = u8(packet, 4);
    final needsAck = flags & kChunkNeedsAck != 0;
    Uint8List? ack(int status) => needsAck || status != kAckSuccess
        ? helioBuildAck(session, status, index)
        : null;

    final List<int> body;
    if (flags & kChunkFirst != 0) {
      if (packet.length < _firstHeader) return ack(kAckBadFormat);
      _session = session;
      _total = u32(packet, 5);
      _endpoint = u16(packet, 9);
      _encrypted = flags & kChunkEncrypted != 0;
      _lastIndex = index;
      _buf.clear();
      if (!isKnownEndpoint(_endpoint)) {
        _reset();
        return helioBuildAck(session, kAckUnknownEndpoint, index);
      }
      body = packet.sublist(_firstHeader);
    } else {
      // A continuation with no message in progress: nothing to ACK.
      if (_session == -1) return null;
      if (session != _session) {
        _reset();
        return ack(kAckSessionMismatch);
      }
      if (index != ((_lastIndex + 1) & 0xFF)) {
        _reset();
        return ack(kAckPacketLost);
      }
      _lastIndex = index;
      if (flags & kChunkEncrypted != 0) _encrypted = true;
      body = packet.sublist(_nextHeader);
    }
    _buf.add(body);

    final expected = _encrypted ? helioEncryptedSize(_total) : _total;
    if (_buf.length > expected) {
      _reset();
      return ack(kAckBadFormat);
    }
    if (flags & kChunkLast != 0) {
      if (_buf.length != expected) {
        _reset();
        return ack(kAckBadFormat);
      }
      final raw = _buf.toBytes();
      Uint8List? payload;
      if (!_encrypted) {
        payload = raw;
      } else {
        try {
          payload = decrypt(_session, raw, _total);
        } catch (e) {
          onDecryptFailure(e);
        }
      }
      if (payload == null) {
        // Acknowledged as received and dropped, as the official app does.
        _reset();
        return ack(kAckSuccess);
      }
      final msg = HelioMessage(_endpoint, _session, payload, _encrypted);
      _reset();
      final reply = ack(kAckSuccess);
      onMessage(msg);
      return reply;
    }
    return ack(kAckSuccess);
  }
}

// ── Services list and channel version ───────────────────────────────────────

const int kEpServices = 0x0000;
const int kEpConnect = 0x0015;
const int kEpBattery = 0x0029;
const int kEpTime = 0x0047;
const int kEpHistory = 0x004B;
const int kEpAuth = 0x0082;

/// The strap's supported endpoints and whether each requires encryption.
class HelioServiceList {
  final Map<int, bool> endpoints;
  const HelioServiceList(this.endpoints);
  static final Uint8List request = Uint8List.fromList([0x03]);

  bool has(int endpoint) => endpoints.containsKey(endpoint);
  bool requiresEncryption(int endpoint) => endpoints[endpoint] == true;

  /// The v2 reply `04 count(u16) {endpoint u16, requireEncryption bool}*`.
  static HelioServiceList parse(List<int> reply) {
    if (reply.isEmpty || u8(reply, 0) != 0x04) {
      throw const FormatException('Not a v2 services reply');
    }
    final r = HelioReader(reply, 1);
    final count = r.readU16();
    final map = <int, bool>{};
    for (var i = 0; i < count; i++) {
      map[r.readU16()] = r.readBool();
    }
    if (r.remaining != 0) throw const FormatException('Trailing bytes in services list');
    return HelioServiceList(map);
  }

  /// Applies the strap's unsolicited `05 op endpoint u16 requireEncryption`
  /// push (op 1 adds, 2 removes); null for anything else.
  HelioServiceList? applyChange(List<int> push) {
    if (push.length < 4 || u8(push, 0) != 0x05) return null;
    final ep = u8(push, 2) | (u8(push, 3) << 8);
    switch (u8(push, 1)) {
      case 1:
        return HelioServiceList({...endpoints, ep: push.length > 4 && u8(push, 4) != 0});
      case 2:
        return HelioServiceList({...endpoints}..remove(ep));
    }
    return null;
  }
}

/// The reply to `01` on 0016: `02 version [encryptEnable] ...`.
class HelioChannelVersion {
  final int version;
  final bool? encryptEnable;
  const HelioChannelVersion(this.version, this.encryptEnable);
  static final Uint8List request = Uint8List.fromList([0x01]);

  static HelioChannelVersion? parse(List<int> reply) {
    if (reply.length < 2 || u8(reply, 0) != 0x02) return null;
    return HelioChannelVersion(u8(reply, 1), reply.length >= 3 ? u8(reply, 2) != 0 : null);
  }
}

// ── Authentication ──────────────────────────────────────────────────────────

const int kAuthCmdInfo = 0x00;
const int kAuthCmdKeyExchange = 0x04;
const int kAuthCmdProve = 0x05;
const int kAuthSuccess = 1;

const Map<int, String> _authNames = {
  0: 'other error',
  1: 'success',
  2: 'invalid state',
  3: 'unknown command',
  4: 'operation failed',
  5: 'a workout is in progress',
  6: 'invalid parameter',
  7: 'no key on the strap (it was unbound)',
  8: 'signature verification failed',
  9: 'API level insufficient',
  0x20: 'cannot save key',
  0x21: 'rejected on the strap',
  0x22: 'public key hash failed',
  0x23: 'AES failed',
  0x24: 'out of memory',
  0x25: 'binding ciphertext mismatch',
  0x26: 'wrong auth key',
  0x27: 'ECDH private key failed',
  0x28: 'ECDH shared secret failed',
  0x41: 'binding protection is on',
  0x81: 'local binding forbidden (cloud bind required)',
};

String helioAuthDescribe(int status) =>
    _authNames[status] ?? 'status 0x${status.toRadixString(16).padLeft(2, '0')}';

/// `10 <cmd>` reply prefix removed, leaving `[status][data...]`; null when the
/// reply is not an answer to [command].
Uint8List? helioAuthStripReply(int command, List<int> reply) =>
    reply.length >= 3 && u8(reply, 0) == 0x10 && u8(reply, 1) == command
        ? Uint8List.fromList(reply.sublist(2))
        : null;

class HelioAuthException implements Exception {
  final int status;
  final String message;
  const HelioAuthException(this.status, this.message);
  @override
  String toString() => message;
}

/// The already-bound handshake as a pure state machine: send [step1Request],
/// feed the stripped reply to [handleStep1Reply] (which returns the step-2
/// request), then check the step-2 status with [handleStep2Reply], which yields
/// the session [HelioCipher].
class HelioAuthHandshake {
  final Uint8List authKey;
  final B163KeyPair _keys;
  HelioCipher? _cipher;

  HelioAuthHandshake(List<int> authKey, {B163KeyPair? keys})
      : authKey = Uint8List.fromList(authKey),
        _keys = keys ?? B163KeyPair.generate() {
    if (authKey.length != 16) throw ArgumentError('Auth key must be 16 bytes');
  }

  /// `04 02 00 02` + the phone's public key (52 bytes).
  Uint8List get step1Request =>
      Uint8List.fromList([kAuthCmdKeyExchange, 0x02, 0x00, 0x02, ..._keys.publicKey]);

  /// [reply] is `status, random[16], devicePub[48]`; returns the step-2 payload.
  Uint8List handleStep1Reply(List<int> reply) {
    final status = reply.isEmpty ? 0 : u8(reply, 0);
    if (status != kAuthSuccess) {
      throw HelioAuthException(status, 'Key exchange failed: ${helioAuthDescribe(status)}');
    }
    if (reply.length < 1 + 16 + kB163PublicKeyBytes) {
      throw HelioAuthException(0, 'Key exchange reply too short (${reply.length})');
    }
    final challenge = reply.sublist(1, 17);
    final devicePublic = reply.sublist(17, 17 + kB163PublicKeyBytes);
    final shared = b163SharedSecret(_keys.privateKey, devicePublic);
    final c = HelioCipher(shared, authKey);
    _cipher = c;
    return HelioWriter()
        .u8(kAuthCmdProve)
        .bytes(helioAesEncrypt(authKey, challenge))
        .bytes(helioAesEncrypt(c.sessionKey, challenge))
        .toBytes();
  }

  /// [reply] is the stripped step-2 reply; on success returns the session cipher.
  HelioCipher handleStep2Reply(List<int> reply) {
    final status = reply.isEmpty ? 0 : u8(reply, 0);
    if (status != kAuthSuccess) {
      throw HelioAuthException(status, 'Authentication failed: ${helioAuthDescribe(status)}');
    }
    return _cipher ?? (throw const HelioAuthException(0, 'Step 2 before step 1'));
  }
}

/// A 16-byte auth key from 32 hex characters, with an optional `0x` prefix and
/// any whitespace or colons; null when it is not one.
Uint8List? helioParseAuthKey(String raw) {
  var s = raw.replaceAll(RegExp(r'[\s:]'), '').toLowerCase();
  if (s.startsWith('0x')) s = s.substring(2);
  if (s.length != 32 || !RegExp(r'^[0-9a-f]+$').hasMatch(s)) return null;
  return Uint8List.fromList(
      [for (var i = 0; i < 32; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
}
