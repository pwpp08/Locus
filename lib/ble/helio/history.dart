// The Helio Strap's history ("GDSP") fetch: command codec, the fetch client and
// the record parsers for the data Locus can use.
//
// A Dart port of the open-source `unstrap` project's history module (MIT/
// Apache-2.0, github.com/sayed0am/unstrap; docs/protocol/02 is the spec and its
// parsers were checked against a real strap). Only the data types Locus has a
// place for are decoded: per-minute activity (heart rate, steps), the strap's
// own sleep result, HRV, resting heart rate, SpO2, all-day stress and skin
// temperature. The rest are asked for by nobody.
//
// A FETCH IS START -> TRANSFER -> ACK. START names a data type and the time to
// read from and is answered with a size and the first record's time; TRANSFER
// streams indexed packets on HUAMI(0005), ended by `10 02` with a CRC-32 of the
// wire bytes; an ACK `03 <code>` closes the exchange in every case.

import 'dart:async';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'channel.dart';

// ── Time on the wire ────────────────────────────────────────────────────────

/// Wall-clock time as GDSP carries it: local date fields plus the UTC offset in
/// quarter-hours (signed, DST included).
class GdspTime {
  final int year, month, day, hour, minute, second, tzQuarters;
  const GdspTime(this.year, this.month, this.day, this.hour, this.minute,
      this.second, this.tzQuarters);

  static const int wireSize = 8;

  /// `civil(Y,M,D) + h:m:s - tz` as epoch seconds.
  int get epochSecond =>
      DateTime.utc(year, month, day, hour, minute, second).millisecondsSinceEpoch ~/ 1000 -
      tzQuarters * 900;

  /// [epoch] in the phone's own zone.
  factory GdspTime.of(int epoch) {
    final t = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    return GdspTime(t.year, t.month, t.day, t.hour, t.minute, t.second,
        t.timeZoneOffset.inSeconds ~/ 900);
  }

  void writeTo(HelioWriter w) =>
      w.u16(year).u8(month).u8(day).u8(hour).u8(minute).u8(second).u8(tzQuarters);

  static GdspTime read(HelioReader r) => GdspTime(
      r.readU16(), r.readU8(), r.readU8(), r.readU8(), r.readU8(), r.readU8(), r.readS8());
}

// ── Codec ───────────────────────────────────────────────────────────────────

const int kGdspVersion = 0x00, kGdspStart = 0x01, kGdspTransfer = 0x02, kGdspAck = 0x03;

/// Device status codes.
const int kGdspOk = 1,
    kGdspOpFailed = 4,
    kGdspPacketIndexError = 6,
    kGdspCrcMismatch = 8,
    kGdspDecompressFailed = 13,
    kGdspSizeMismatch = 14;

/// Zepp's cyclic-sync result, -6, as the ACK byte 0xFA.
const int kGdspCyclic = 0xFA;

/// What the strap said on the control path.
sealed class GdspMsg {
  const GdspMsg();
}

class GdspResponse extends GdspMsg {
  final int opcode, status;
  final Uint8List data;
  const GdspResponse(this.opcode, this.status, this.data);
  bool get ok => status == kGdspOk;
}

/// START reply: [size] 0 means nothing newer; [first] is the first record's time.
class GdspStartReply extends GdspResponse {
  final int size;
  final GdspTime? first;
  final Uint8List expansion;
  GdspStartReply(int status, this.size, this.first, this.expansion)
      : super(kGdspStart, status, Uint8List(0));
  int? get firstEpoch => first?.epochSecond;

  /// Expansion byte 0 is the compression flag: 1 is a zlib payload.
  bool? get compressed => expansion.isEmpty ? null : expansion[0] == 1;
}

class GdspTransferComplete extends GdspResponse {
  final Uint8List extra;
  GdspTransferComplete(int status, this.extra) : super(kGdspTransfer, status, extra);
  int? get crc32 => extra.length >= 4 ? u32(extra, 0) : null;
}

/// Unsolicited `11 <type>`: new data of that type is waiting.
class GdspDataAvailable extends GdspMsg {
  final int type;
  const GdspDataAvailable(this.type);
}

class GdspMalformed extends GdspMsg {
  final String reason;
  const GdspMalformed(this.reason);
}

Uint8List gdspStart(int type, GdspTime since) {
  final w = HelioWriter().u8(kGdspStart).u8(type);
  since.writeTo(w);
  return w.u8(0x01).toBytes();
}

Uint8List gdspAck(int code) => Uint8List.fromList([kGdspAck, code & 0xFF]);
final Uint8List gdspQueryVersion = Uint8List.fromList([kGdspVersion]);
final Uint8List gdspTransfer = Uint8List.fromList([kGdspTransfer]);

/// Decodes one control-path message.
GdspMsg gdspParse(List<int> b) {
  if (b.isEmpty) return const GdspMalformed('empty');
  switch (u8(b, 0)) {
    case 0x11:
      return b.length >= 2 ? GdspDataAvailable(u8(b, 1)) : const GdspMalformed('no type');
    case 0x10:
      if (b.length < 3) return const GdspMalformed('response shorter than 3 bytes');
      final op = u8(b, 1), status = u8(b, 2);
      final data = Uint8List.fromList(b.sublist(3));
      if (op == kGdspStart) {
        if (status != kGdspOk) return GdspStartReply(status, 0, null, Uint8List(0));
        if (data.length < 4 + GdspTime.wireSize) {
          return const GdspMalformed('START reply too short');
        }
        final r = HelioReader(data);
        final size = r.readU32();
        final time = GdspTime.read(r);
        return GdspStartReply(status, size, time, r.readBytes(r.remaining));
      }
      if (op == kGdspTransfer) return GdspTransferComplete(status, data);
      return GdspResponse(op, status, data);
  }
  return const GdspMalformed('unknown leading byte');
}

/// The data types the strap says it can serve, from the version reply
/// (`version u8, supportDataUpload u8, count u16, count x {type u8, hasData u8}`).
Set<int>? gdspSupportedTypes(GdspResponse version) {
  final d = version.data;
  if (d.length < 4) return null;
  final r = HelioReader(d, 2);
  final count = r.readU16();
  if (r.remaining < count * 2) return null;
  final out = <int>{};
  for (var i = 0; i < count; i++) {
    out.add(r.readU8());
    r.readU8();
  }
  return out;
}

// ── Fetch client ────────────────────────────────────────────────────────────

class GdspFetch {
  /// 'empty' | 'failed' | 'chunk'.
  final String kind;
  final int ack;
  final String reason;
  final Uint8List payload;
  final int headerTime, sizeField;
  const GdspFetch._(this.kind, this.ack, this.reason, this.payload, this.headerTime,
      this.sizeField);

  static final GdspFetch empty = GdspFetch._('empty', kGdspOk, '', Uint8List(0), 0, 0);
  factory GdspFetch.failed(int ack, String reason) =>
      GdspFetch._('failed', ack, reason, Uint8List(0), 0, 0);
  factory GdspFetch.chunk(Uint8List payload, int headerTime, int size) =>
      GdspFetch._('chunk', kGdspOk, '', payload, headerTime, size);

  bool get isChunk => kind == 'chunk';
  bool get isFailed => kind == 'failed';
  bool get cyclic => ack == kGdspCyclic;
}

class GdspTimeout implements Exception {
  final int op;
  const GdspTimeout(this.op);
  @override
  String toString() => 'no reply to GDSP command ${op.toRadixString(16)}';
}

/// A tiny async mailbox: items in, a timed wait out.
class _Inbox {
  final _items = <Object>[];
  Completer<void>? _wake;

  void add(Object o) {
    _items.add(o);
    final w = _wake;
    if (w != null && !w.isCompleted) w.complete();
  }

  void clearData() => _items.removeWhere((e) => e is Uint8List);

  /// The next item, or null after [timeout].
  Future<Object?> next(Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (_items.isEmpty) {
      final left = end.difference(DateTime.now());
      if (left <= Duration.zero) return null;
      _wake = Completer<void>();
      await _wake!.future.timeout(left, onTimeout: () {});
    }
    return _items.removeAt(0);
  }

  Object? tryTake() => _items.isEmpty ? null : _items.removeAt(0);
}

/// The previous chunk of one type in a loop, for the cyclic check: when the
/// cursor moved and the new header time is not later, the strap is going round
/// in circles.
class GdspPrevious {
  final int cursor, headerTime;
  const GdspPrevious(this.cursor, this.headerTime);
}

/// The phone side of GDSP fetches. [send] writes a control command; feed the
/// strap's control messages to [onControl] and indexed data packets to [onData].
class GdspClient {
  final Future<void> Function(Uint8List) send;
  final void Function(String) log;
  final Duration timeout, trailing;
  final _inbox = _Inbox();

  /// Types the strap pushed as available while a fetch was in progress.
  final pushed = <int>{};

  GdspClient({
    required this.send,
    this.log = _noLog,
    this.timeout = const Duration(seconds: 20),
    this.trailing = const Duration(milliseconds: 300),
  });
  static void _noLog(String _) {}

  void onControl(GdspMsg m) => _inbox.add(m);
  void onData(Uint8List p) => _inbox.add(p);

  void _note(GdspMsg m) {
    if (m is GdspDataAvailable) pushed.add(m.type);
  }

  /// Sends [bytes] and waits for its `10 <op>` response.
  Future<GdspResponse> command(Uint8List bytes) async {
    final op = bytes[0];
    await send(bytes);
    final end = DateTime.now().add(timeout);
    while (true) {
      final left = end.difference(DateTime.now());
      final m = left <= Duration.zero ? null : await _inbox.next(left);
      if (m == null) throw GdspTimeout(op);
      if (m is GdspResponse && m.opcode == op) return m;
      if (m is GdspMsg) _note(m);
    }
  }

  Future<GdspResponse?> queryVersion() async {
    try {
      return await command(gdspQueryVersion);
    } catch (e) {
      log('history: version query failed: $e');
      return null;
    }
  }

  /// One START to ACK exchange for [type] from [since] (epoch seconds).
  Future<GdspFetch> fetch(int type, int since, {GdspPrevious? previous}) async {
    GdspResponse? start;
    try {
      start = await command(gdspStart(type, GdspTime.of(since)));
    } on GdspTimeout catch (e) {
      log('history: start $type: $e');
    }
    if (start == null) return _closed(GdspFetch.failed(kGdspOpFailed, 'no reply to START'));
    if (!start.ok) {
      return _closed(GdspFetch.failed(start.status, 'start refused (${start.status})'));
    }
    if (start is! GdspStartReply) {
      return _closed(GdspFetch.failed(kGdspOpFailed, 'no header'));
    }
    if (start.size == 0) return _closed(GdspFetch.empty);
    final header = start.firstEpoch;
    if (header == null) return _closed(GdspFetch.failed(kGdspOpFailed, 'no header'));
    if (previous != null && since != previous.cursor && header <= previous.headerTime) {
      return _closed(GdspFetch.failed(kGdspCyclic, 'cyclic: header $header'));
    }
    return _closed(await _transfer(type, start, header));
  }

  Future<GdspFetch> _transfer(int type, GdspStartReply start, int header) async {
    _inbox.clearData();
    final wire = BytesBuilder(copy: false);
    var lastIndex = -1;
    Uint8List? lastPacket;
    await send(gdspTransfer);
    GdspTransferComplete? complete;
    while (complete == null) {
      final got = await _inbox.next(timeout);
      if (got == null) {
        log('history: no data for ${timeout.inSeconds} s');
        return GdspFetch.failed(kGdspOpFailed, 'no data');
      }
      if (got is Uint8List) {
        if (got.isEmpty) continue;
        final index = got[0];
        if (index == lastIndex && lastPacket != null && _same(lastPacket, got)) continue;
        if (index == ((lastIndex + 1) & 0xFF) && (lastIndex >= 0 || index == 0)) {
          lastIndex = index;
          lastPacket = got;
          wire.add(got.sublist(1));
        } else {
          log('history: missing packet, $lastIndex then $index');
          return GdspFetch.failed(kGdspPacketIndexError, 'packet gap');
        }
      } else if (got is GdspTransferComplete) {
        complete = got;
      } else if (got is GdspMsg) {
        _note(got);
      }
    }
    // Data can reach the phone just after the `10 02` on the control path.
    while (true) {
      final p = await _inbox.next(trailing);
      if (p == null) break;
      if (p is Uint8List && p.isNotEmpty && p[0] == ((lastIndex + 1) & 0xFF)) {
        lastIndex = p[0];
        wire.add(p.sublist(1));
      }
    }
    final raw = wire.toBytes();
    Uint8List payload = raw;
    if (start.compressed == true) {
      try {
        payload = Uint8List.fromList(ZLibCodec().decode(raw));
      } catch (e) {
        return GdspFetch.failed(kGdspDecompressFailed, 'inflate failed');
      }
    }
    const unchecked = {60, 80, 84};
    if (payload.length < start.size && !unchecked.contains(type)) {
      return GdspFetch.failed(kGdspSizeMismatch, '${payload.length} bytes for ${start.size}');
    }
    if (!complete.ok || complete.extra.length != 4) {
      return GdspFetch.failed(kGdspOpFailed, 'transfer ended with ${complete.status}');
    }
    if (complete.crc32 != helioCrc32(raw)) {
      return GdspFetch.failed(kGdspCrcMismatch, 'CRC mismatch');
    }
    return GdspFetch.chunk(payload, header, start.size);
  }

  /// The ACK every exchange ends with, then up to [timeout] for its `10 03`.
  Future<GdspFetch> _closed(GdspFetch result) async {
    await send(gdspAck(result.ack));
    final end = DateTime.now().add(timeout);
    while (true) {
      final left = end.difference(DateTime.now());
      final m = left <= Duration.zero ? null : await _inbox.next(left);
      if (m == null) break;
      if (m is GdspResponse && m.opcode == kGdspAck) break;
      if (m is GdspMsg) _note(m);
    }
    return result;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ── Records ─────────────────────────────────────────────────────────────────

/// Heart-rate bytes: 30..220 is a reading, 254 "no HR", 255 not worn.
int? helioHeartRate(int raw) => raw >= 30 && raw <= 220 ? raw : null;

class HelioActivity {
  final int ts, rawMode, intensity, steps, rawHr;
  const HelioActivity(this.ts, this.rawMode, this.intensity, this.steps, this.rawHr);

  /// Low nibble of the first byte (the high nibble is firmware state).
  int get mode => rawMode == 126 ? rawMode : rawMode & 0x0F;
  bool get isWorn => mode != 3 && mode != 6; // not worn, charging
  bool get isBlank => rawMode == 0xFF && intensity == 0xFF && steps == 0xFF && rawHr == 0xFF;
  int? get hr => helioHeartRate(rawHr);
}

class HelioSleepStage {
  final int start, stop, rawType;
  const HelioSleepStage(this.start, this.stop, this.rawType);

  /// 'light' | 'deep' | 'wake' | 'rem', or null for an unused slot.
  String? get stage => switch (rawType) {
        4 => 'light',
        5 => 'deep',
        7 => 'wake',
        8 => 'rem',
        _ => null,
      };
}

class HelioSleepResult {
  final int ts, belongTime, version, score, avgHr;
  final bool hasMain;
  final List<HelioSleepStage> mainStages, napStages;
  final int remMin, lightMin, deepMin, wakeMin;
  const HelioSleepResult({
    required this.ts,
    required this.belongTime,
    required this.version,
    required this.hasMain,
    required this.score,
    required this.avgHr,
    required this.mainStages,
    required this.napStages,
    required this.remMin,
    required this.lightMin,
    required this.deepMin,
    required this.wakeMin,
  });

  /// Local midnight of the day this result belongs to: the date of
  /// [belongTime] + 2 h.
  int get dayStart {
    final t = DateTime.fromMillisecondsSinceEpoch((belongTime + 2 * 3600) * 1000);
    return DateTime(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 1000;
  }

  /// A stage time (minutes from local midnight of the day before [dayStart]) as
  /// epoch seconds.
  int resolve(int raw) => dayStart + (raw - 1440) * 60;
}

class HelioPoint {
  final int ts;
  final num value;
  const HelioPoint(this.ts, this.value);
}

class HelioSpo2 {
  final int ts, spo2;
  final bool isAuto;
  const HelioSpo2(this.ts, this.spo2, this.isAuto);
  bool get plausible => spo2 >= 80 && spo2 <= 100;
}

class HelioSkinTemp {
  final int ts;
  final double? skinC;
  const HelioSkinTemp(this.ts, this.skinC);
}

/// One parsed chunk: the records, and the time to ask from next (null when the
/// chunk held none), or [failure] when the whole chunk was rejected.
class HelioParsed<T> {
  final List<T> records;
  final int? next;
  final String? failure;
  const HelioParsed(this.records, this.next, [this.failure]);
  const HelioParsed.failed(String why)
      : records = const [],
        next = null,
        failure = why;
}

typedef _Reader<T> = T Function(HelioReader r, int i);

HelioParsed<T> _fixed<T>(
  List<int> payload,
  int size,
  _Reader<T> read, {
  int offset = 0,
  required int? Function(List<T>) next,
}) {
  if (payload.length < offset) return const HelioParsed.failed('payload shorter than header');
  final r = HelioReader(payload, offset);
  final out = <T>[];
  try {
    var i = 0;
    while (r.remaining >= size) {
      final start = r.pos;
      out.add(read(r, i++));
      r.pos = start + size;
    }
  } on RangeError catch (e) {
    return HelioParsed.failed('truncated payload: $e');
  }
  return HelioParsed(out, next(out));
}

int? _lastPlusOne(List<int> ts) =>
    ts.isEmpty ? null : ts.reduce((a, b) => a > b ? a : b) + 1;

/// The activity record size: the START size field when it divides the payload
/// into 4- or 8-byte records, else 8 when the payload is a multiple of 8.
int helioActivityRecordSize(List<int> payload, int sizeField) {
  if (sizeField > 0 && payload.length % sizeField == 0) {
    final unit = payload.length ~/ sizeField;
    if (unit == 4 || unit == 8) return unit;
  }
  // ponytail: the strap sends 8-byte records; a payload that is not a multiple
  // of 8 is read as 4. A feature-bitmap read would settle it.
  return payload.length % 8 == 0 ? 8 : 4;
}

/// Type 1: one record per minute from the header time.
HelioParsed<HelioActivity> helioParseActivity(
    List<int> raw, int headerTime, int recordSize) {
  final size = recordSize <= 4 ? 4 : recordSize;
  return _fixed(raw, size,
      (r, i) => HelioActivity(headerTime + i * 60, r.readU8(), r.readU8(), r.readU8(), r.readU8()),
      next: (recs) => recs.isEmpty ? null : headerTime + recs.length * 60);
}

const int kHelioSleepResultSize = 594;

/// Type 72: the on-device sleep result.
HelioParsed<HelioSleepResult> helioParseSleepResult(List<int> payload) =>
    _fixed(payload, kHelioSleepResultSize, (r, _) {
      final ts = r.readU32(), belong = r.readU32(), version = r.readU8();
      final hasMain = r.readU8() == 1;
      r.pos += 8; // main start/end, on-bed/off-bed
      r.pos += 3; // rem supported, short supported, has short
      final avg = r.readU8(), score = r.readU8();
      r.pos += 1 + 60; // short-sleep count and its ten slots
      final mainCount = r.readS8().clamp(0, 50);
      r.pos += 1; // nap stage count (the strap's own app ignores it)
      List<HelioSleepStage> stages(int keep) => [
            for (var i = 0; i < 50; i++)
              HelioSleepStage(r.readS16(), r.readS16(), r.readU8()),
          ].take(keep).toList();
      final main = stages(mainCount);
      final naps = stages(50).where((s) => s.stage != null).toList();
      return HelioSleepResult(
        ts: ts,
        belongTime: belong,
        version: version,
        hasMain: hasMain,
        score: score,
        avgHr: avg,
        mainStages: main,
        napStages: naps,
        remMin: r.readS16(),
        lightMin: r.readS16(),
        deepMin: r.readS16(),
        wakeMin: r.readS16(),
      );
    }, next: (recs) => _lastPlusOne([for (final x in recs) x.ts]));

/// Types 73 (HRV RMSSD) and 58 (resting heart rate): `ts u32, tz i8, value u8`.
HelioParsed<HelioPoint> helioParseDailyValue(List<int> payload) => _fixed(
    payload,
    6,
    (r, _) {
      final ts = r.readU32();
      r.readS8();
      return HelioPoint(ts, r.readU8());
    },
    next: (recs) => _lastPlusOne([for (final x in recs) x.ts]));

/// Type 19: all-day stress, one byte per minute from the header time. Zero and
/// 254+ are gaps.
HelioParsed<HelioPoint> helioParseStressAllDay(List<int> payload, int headerTime) =>
    _fixed(payload, 1, (r, i) => HelioPoint(headerTime + i * 60, r.readU8()),
        next: (recs) => recs.isEmpty ? null : headerTime + recs.length * 60 + 1);

/// Type 37: spot / auto SpO2. Versioned payloads (a leading 1 or 2) are read as
/// 5-byte (v1) or 65-byte (v2) records; only the reading itself is kept.
HelioParsed<HelioSpo2> helioParseSpo2(List<int> payload, int headerTime) {
  if (payload.isEmpty) return const HelioParsed([], null);
  bool near(int at) {
    if (payload.length < at + 4) return false;
    return (u32(payload, at) - headerTime).abs() <= 2 * 86400;
  }

  final versioned =
      payload.length >= 5 && (payload[0] == 1 || payload[0] == 2) && near(1) && !near(0);
  final version = versioned ? payload[0] : 1;
  if (version != 1 && version != 2) return HelioParsed.failed('SpO2 version $version');
  return _fixed(payload, version == 2 ? 65 : 5, (r, _) {
    final ts = r.readU32(), b = r.readU8();
    return HelioSpo2(ts, b & 0x7F, b & 0x80 != 0);
  },
      offset: versioned ? 1 : 0,
      next: (recs) => _lastPlusOne([for (final x in recs) x.ts]));
}

/// Type 46: 8-byte per-minute records `env s16, touch s16, reserved[4]` in
/// 0.01 C; 0x7FFF is no reading. Skin readings outside 20-42 C are off-wrist.
HelioParsed<HelioSkinTemp> helioParseSkinTemp(List<int> payload, int headerTime) =>
    _fixed(payload, 8, (r, i) {
      r.readS16(); // ambient
      final touch = r.readS16();
      final c = touch == 0x7FFF ? null : touch / 100.0;
      return HelioSkinTemp(
          headerTime + i * 60, c != null && c >= 20 && c <= 42 ? c : null);
    }, next: (recs) => recs.isEmpty ? null : headerTime + recs.length * 60 + 1);
