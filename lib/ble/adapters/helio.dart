// Amazfit Helio Strap, over its own Bluetooth channel: no Zepp app in the loop
// once the strap's pairing key is in hand.
//
// NOTHING HERE HAS MET HARDWARE (ASSUMPTIONS R6). Nobody on this project owns a
// Helio Strap. The wire format is ported from the unstrap project's protocol
// notes and its tests; the crypto and the framing are checked against an
// independent simulated strap (`test/helio/`), and the session below is checked
// against the same simulation. What no test can say is whether a real strap
// answers the way the notes say it does. Anything that goes wrong on a real
// strap should show up in the log lines below, and the raw chunks are banked
// so a wrong guess can be re-read later.
//
// THE SESSION, in order:
//   1. Channel version, then the strap's service list (endpoint 0).
//   2. Authentication (endpoint 0x82): an ECDH exchange on the B-163 curve,
//      then a proof that both ends hold the same pairing key. The key is the
//      one Zepp made when the strap was first linked (`helio/zepp_cloud.dart`).
//   3. The strap pings endpoint 0x15 now and then and expects a pong; the
//      payload size is negotiated on the same endpoint.
//   4. The history endpoint (0x4B): for each kind of record, a START, a
//      TRANSFER over characteristic 0005 and an ACK (`helio/history.dart`),
//      from where the last session stopped.
//
// WHAT COMES BACK: per-minute heart rate and steps, the strap's own sleep
// result (stages and totals), HRV, resting heart rate, SpO2, all-day stress and
// skin temperature. Heart rate and skin temperature go in as samples; the
// strap's own numbers go in as attributed observations; its hypnogram goes in
// as the night's stages.
//
// NOT HERE: alarms (the bytes are undocumented), live heart rate, and anything
// that writes to the strap beyond the handshake and the history ACKs.

import 'dart:async';
import 'dart:typed_data';

import '../../compute/vendor_sleep.dart' show VendorEpoch;
import '../../data/observation.dart';
import '../helio/channel.dart';
import '../helio/history.dart';
import '_registry.dart';
import 'adapter.dart';
import 'signals.dart';

/// The vendor name the user sees beside the strap's own numbers.
const String kHelioAttribution = 'Amazfit';

/// The signals this strap supplies. Mirrored in `kAdapterSignals`.
const Map<InputSignal, Duration> kHelioSignals = {
  InputSignal.hrSparse: Duration(minutes: 1),
  InputSignal.steps: Duration(days: 1),
  InputSignal.skinTempC: Duration(minutes: 1),
  InputSignal.deviceStages: Duration.zero,
  InputSignal.deviceHrv: Duration(days: 1),
  InputSignal.deviceSpo2: Duration(days: 1),
  InputSignal.deviceStress: Duration(days: 1),
};

/// Record kinds this build reads, in the order a session asks for them: the
/// night first, so a session cut short still has it.
const List<int> kHelioFetchOrder = [72, 73, 58, 37, 1, 19, 46];

// ── Cursors ─────────────────────────────────────────────────────────────────

/// Where each record kind resumes: `type:cursor:headerTime;…`. The header time
/// is what the strap said the last chunk started at, kept for its cyclic check.
class HelioCursors {
  HelioCursors([Map<int, (int, int)>? m]) : _m = m ?? {};
  final Map<int, (int, int)> _m;

  factory HelioCursors.decode(String text) {
    final m = <int, (int, int)>{};
    for (final part in text.split(';')) {
      final f = part.split(':');
      if (f.length != 3) continue;
      final t = int.tryParse(f[0]), c = int.tryParse(f[1]), h = int.tryParse(f[2]);
      if (t != null && c != null && h != null) m[t] = (c, h);
    }
    return HelioCursors(m);
  }

  String encode() =>
      [for (final e in _m.entries) '${e.key}:${e.value.$1}:${e.value.$2}'].join(';');

  int? cursor(int type) => _m[type]?.$1;
  int? header(int type) => _m[type]?.$2;
  void set(int type, int cursor, int header) => _m[type] = (cursor, header);
}

// ── The channel ─────────────────────────────────────────────────────────────

/// A queue with a waiter: items are taken by predicate, with a timeout.
class _Mailbox<T> {
  final _items = <T>[];
  Completer<void>? _wake;

  void add(T v) {
    _items.add(v);
    if (_items.length > 64) _items.removeAt(0);
    final w = _wake;
    _wake = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<T?> next(bool Function(T) test, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (true) {
      final i = _items.indexWhere(test);
      if (i >= 0) return _items.removeAt(i);
      final left = end.difference(DateTime.now());
      if (left <= Duration.zero) return null;
      final w = _wake ??= Completer<void>();
      await Future.any([w.future, Future<void>.delayed(left)]);
    }
  }
}

/// One connection to the strap: the chunked, optionally encrypted message
/// channel, authenticated and then used by the history client.
class HelioSession {
  HelioSession(this.link, {this.timeout = const Duration(seconds: 10), this.ackWait = const Duration(seconds: 3)});

  final BandLink link;
  final Duration timeout, ackWait;

  /// Bytes of payload per write on 0016. 20 until the strap says otherwise.
  int payloadMtu = 20;

  HelioCipher? _cipher;
  HelioServiceList _services = const HelioServiceList({});
  int _sid = 0;

  final _msgs = _Mailbox<HelioMessage>();
  final _acks = _Mailbox<HelioDeviceAck>();
  final _versions = _Mailbox<HelioChannelVersion>();
  final _mtus = _Mailbox<int>();
  final _early = <GdspMsg>[];
  GdspClient? _gdsp;
  final _subs = <StreamSubscription<Object?>>[];
  late final HelioReassembler _reassembler = HelioReassembler(
    isKnownEndpoint: (_) => true,
    decrypt: (sid, cipher, total) {
      final c = _cipher;
      if (c == null) throw const HelioDecryptException('no session key yet');
      return c.decrypt(sid, cipher, total);
    },
    onMessage: _dispatch,
  )..onDecryptFailure = (e) => link.log('helio: dropped a message ($e)');

  /// Subscribes to the three characteristics. Call once, first.
  void open() {
    _subs.add(link.notify(kHelioCmdChar).listen((r) {
      final v = r.$2;
      final a = helioParseDeviceAck(v);
      if (a != null) {
        _acks.add(a);
        return;
      }
      final ver = HelioChannelVersion.parse(v);
      if (ver != null) _versions.add(ver);
    }));
    _subs.add(link.notify(kHelioDataChar).listen((r) {
      final ack = _reassembler.accept(r.$2);
      if (ack != null) unawaited(link.write(kHelioDataChar, ack));
    }));
    _subs.add(link.notify(kHelioGdspChar).listen((r) {
      _gdsp?.onData(Uint8List.fromList(r.$2));
    }));
  }

  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  void _dispatch(HelioMessage m) {
    final p = m.payload;
    switch (m.endpoint) {
      case kEpConnect:
        if (p.isEmpty) return;
        if (p[0] == 3) {
          unawaited(send(kEpConnect, const [4]));
        } else if (p[0] == 2 && p.length >= 3) {
          _mtus.add(u16(p, 1));
        }
      case kEpHistory:
        final g = gdspParse(p);
        final c = _gdsp;
        if (c != null) {
          c.onControl(g);
        } else {
          _early.add(g);
        }
      default:
        _msgs.add(m);
    }
  }

  /// Routes history control messages to [client]; anything that arrived before
  /// it existed is replayed.
  void attach(GdspClient client) {
    _gdsp = client;
    for (final g in _early) {
      client.onControl(g);
    }
    _early.clear();
  }

  /// Sends one message on [endpoint], encrypted when the strap's service list
  /// says that endpoint needs it. False when a write was refused or the strap
  /// answered the message with a refusal.
  Future<bool> send(int endpoint, List<int> payload) async {
    final sid = _sid;
    _sid = (_sid + 1) & 0xFF;
    final enc = _cipher != null && _services.requiresEncryption(endpoint);
    final data = enc ? _cipher!.encrypt(sid, payload) : payload;
    final chunks = helioBuildChunks(
      endpoint: endpoint,
      sessionId: sid,
      data: data,
      plainLength: payload.length,
      encrypted: enc,
      payloadMtu: payloadMtu,
    );
    for (final c in chunks) {
      if (!await link.write(kHelioCmdChar, c)) return false;
    }
    final last = (chunks.length - 1) & 0xFF;
    final a = await _acks.next((a) => a.sessionId == sid && a.chunkIndex == last, ackWait);
    // A strap that never ACKs is not treated as a refusal: the reply, if there
    // is one, is what the caller waits on.
    return a == null || a.status == kAckSuccess;
  }

  Future<HelioMessage?> _reply(int endpoint, int first) => _msgs.next(
      (m) => m.endpoint == endpoint && m.payload.isNotEmpty && m.payload[0] == first, timeout);

  /// Version, services and the key handshake. Null on success, else a
  /// sentence saying what failed.
  Future<String?> authenticate(List<int> key) async {
    if (!await link.write(kHelioCmdChar, HelioChannelVersion.request)) {
      return 'The strap would not take the first command.';
    }
    final v = await _versions.next((_) => true, timeout);
    if (v == null) return 'The strap did not answer. Is it on and nearby?';
    link.log('helio: channel version ${v.version}');

    await send(kEpServices, HelioServiceList.request);
    final sm = await _reply(kEpServices, 0x04);
    if (sm == null) return 'The strap did not list its services.';
    try {
      _services = HelioServiceList.parse(sm.payload);
    } on FormatException catch (e) {
      return 'The strap\'s service list was unreadable (${e.message}).';
    }

    final hs = HelioAuthHandshake(key);
    try {
      await send(kEpAuth, hs.step1Request);
      final r1 = await _reply(kEpAuth, 0x10);
      final s1 = r1 == null ? null : helioAuthStripReply(kAuthCmdKeyExchange, r1.payload);
      if (s1 == null) return 'The strap did not answer the key exchange.';
      final step2 = hs.handleStep1Reply(s1);

      await send(kEpAuth, step2);
      final r2 = await _reply(kEpAuth, 0x10);
      final s2 = r2 == null ? null : helioAuthStripReply(kAuthCmdProve, r2.payload);
      if (s2 == null) return 'The strap did not answer the key proof.';
      _cipher = hs.handleStep2Reply(s2);
    } on HelioAuthException catch (e) {
      return e.message;
    }
    return null;
  }

  /// Asks the strap how big a payload it takes per write and uses the smaller
  /// of that and [limit]. Keeps 20 on no answer.
  Future<void> negotiateMtu(int? limit) async {
    if (!await send(kEpConnect, const [1])) return;
    final n = await _mtus.next((_) => true, const Duration(seconds: 3));
    if (n == null || n < 23 || n > 247) return;
    var p = n - 3;
    if (limit != null && limit < p) p = limit;
    if (p > 20) payloadMtu = p;
  }
}

// ── The adapter ─────────────────────────────────────────────────────────────

int _wallNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

class HelioAdapter extends BandAdapter {
  const HelioAdapter({
    required this.authKey,
    this.cursors = '',
    this.priorSteps = const {},
    this.maxWrite,
    this.nowSeconds = _wallNow,
    this.window = const Duration(minutes: 5),
    this.firstWindow = const Duration(days: 14),
    this.maxChunks = 40,
    this.gdspTimeout = const Duration(seconds: 20),
    this.step = const Duration(seconds: 10),
  });

  /// The 16-byte pairing key.
  final Uint8List authKey;

  /// [HelioCursors.encode] from the last session.
  final String cursors;

  /// Step totals already stored for this strap, one per local day.
  final Map<DateTime, int> priorSteps;

  /// The largest write the radio takes, or null when unknown.
  final int? maxWrite;

  final int Function() nowSeconds;

  /// How long one session may spend fetching.
  final Duration window;

  /// How far back the first session reaches.
  final Duration firstWindow;

  /// The most chunks one record kind may take in a session.
  final int maxChunks;

  final Duration gdspTimeout, step;

  @override
  BandEntry get entry => kHelio;

  @override
  Map<InputSignal, Duration> get signals => kHelioSignals;

  @override
  Stream<BandEvent> run(BandLink link) async* {
    final clock = Stopwatch()..start();
    final session = HelioSession(link, timeout: step);
    session.open();
    try {
      final err = await session.authenticate(authKey);
      if (err != null) {
        yield BandNote('helio_auth_failed', err);
        return;
      }
      yield const BandNote('helio_auth', 'ok');
      await session.negotiateMtu(maxWrite);

      final client = GdspClient(
        send: (b) async {
          await session.send(kEpHistory, b);
        },
        log: (m) => link.log('helio: $m'),
        timeout: gdspTimeout,
      );
      session.attach(client);

      final types = await _plan(client);
      link.log('helio: reading kinds ${types.join(", ")}');
      final cur = HelioCursors.decode(cursors);
      final steps = Map<DateTime, int>.of(priorSteps);

      for (final type in types) {
        GdspPrevious? previous;
        for (var n = 0; n < maxChunks; n++) {
          if (clock.elapsed > window) {
            link.log('helio: session window spent; the rest waits for next time');
            return;
          }
          final since = cur.cursor(type) ?? nowSeconds() - firstWindow.inSeconds;
          previous ??= cur.header(type) == null || cur.cursor(type) == null
              ? null
              : GdspPrevious(cur.cursor(type)!, cur.header(type)!);
          final r = await client.fetch(type, since, previous: previous);
          if (r.isFailed) {
            link.log('helio: kind $type stopped: ${r.reason}');
            break;
          }
          if (!r.isChunk) break;
          final d = _decode(type, r, steps);
          if (d.failure != null) {
            link.log('helio: kind $type unreadable: ${d.failure}');
            break;
          }
          yield* Stream.fromIterable(d.events);
          final next = d.next;
          if (next == null || next <= since) break;
          cur.set(type, next, r.headerTime);
          previous = GdspPrevious(next, r.headerTime);
          yield BandNote('helio_cursor', cur.encode());
          yield OffloadCheckpoint(() async => true);
        }
      }
      // The strap says what it has new: remember it for the next session.
      if (client.pushed.isNotEmpty) {
        link.log('helio: strap reports new data of kinds ${client.pushed.join(", ")}');
      }
    } finally {
      await session.close();
    }
  }

  /// The record kinds to ask for: what the strap says it serves, narrowed to
  /// the ones this build reads; the full expected set when it will not say.
  Future<List<int>> _plan(GdspClient client) async {
    final v = await client.queryVersion();
    final served = v == null ? null : gdspSupportedTypes(v);
    final planned = [
      for (final t in kHelioFetchOrder)
        if (served == null || served.contains(t)) t,
    ];
    return planned.isEmpty ? kHelioFetchOrder : planned;
  }
}

// ── Decoding ────────────────────────────────────────────────────────────────

class _Decoded {
  const _Decoded(this.events, this.next, [this.failure]);
  final List<BandEvent> events;
  final int? next;
  final String? failure;
}

DateTime _at(int sec) => DateTime.fromMillisecondsSinceEpoch(sec * 1000);
DateTime _dayOf(int sec) {
  final t = _at(sec);
  return DateTime(t.year, t.month, t.day);
}

Observation _obs(DateTime t, String name, num value, String? unit, {bool ours = false}) =>
    Observation(
      at: t,
      sourceKind: ObservationSource.vendor,
      key: ours ? name : null,
      vendorKey: ours ? null : name,
      value: value,
      unit: unit,
      attribution: kHelioAttribution,
    );

/// One mean per local day for [xs], stamped at that day's first reading in the
/// chunk (the same shape as the Garmin adapter's daily means).
List<Observation> _dailyMeans(List<(int, num)> xs, String name, String unit) {
  final byDay = <DateTime, List<(int, num)>>{};
  for (final x in xs) {
    (byDay[_dayOf(x.$1)] ??= []).add(x);
  }
  return [
    for (final day in byDay.values)
      _obs(
          _at(day.map((x) => x.$1).reduce((a, b) => a < b ? a : b)),
          name,
          day.fold<double>(0, (a, x) => a + x.$2) / day.length,
          unit),
  ];
}

/// One fetched chunk into events. [steps] is the running per-day total and is
/// updated in place.
_Decoded _decode(int type, GdspFetch r, Map<DateTime, int> steps) {
  final raw = Uint8List.fromList([type, ...r.payload]);
  // The chunk is banked verbatim with the kind in front, so a wrong reading of
  // it can be redone later.
  SampleBatch bank(List<NeutralSample> s) => SampleBatch(s, raw: [raw]);

  switch (type) {
    case 1:
      final p = helioParseActivity(
          r.payload, r.headerTime, helioActivityRecordSize(r.payload, r.sizeField));
      if (p.failure != null) return _Decoded(const [], null, p.failure);
      final samples = <NeutralSample>[];
      final added = <DateTime, int>{};
      for (final a in p.records) {
        if (a.isBlank || !a.isWorn) continue;
        final hr = a.hr;
        if (hr != null) {
          samples.add(NeutralSample(anchor: TimeAnchor.measured, tsEpoch: a.ts, hr: hr));
        }
        if (a.steps > 0 && a.steps < 250) {
          final d = _dayOf(a.ts);
          added[d] = (added[d] ?? 0) + a.steps;
        }
      }
      // ponytail: a running sum; a chunk read twice (a commit that failed after
      // the strap had already been ACKed) counts its steps twice.
      final rows = [
        for (final e in added.entries)
          _obs(e.key, 'steps', steps[e.key] = (steps[e.key] ?? 0) + e.value, 'steps',
              ours: true),
      ];
      return _Decoded([bank(samples), if (rows.isNotEmpty) VendorScalars(rows)], p.next);

    case 72:
      final p = helioParseSleepResult(r.payload);
      if (p.failure != null) return _Decoded(const [], null, p.failure);
      final epochs = <VendorEpoch>[];
      final rows = <Observation>[];
      for (final s in p.records) {
        if (!s.hasMain) continue;
        for (final st in s.mainStages) {
          final stage = st.stage;
          if (stage == null) continue;
          final a = s.resolve(st.start), b = s.resolve(st.stop);
          if (b > a) epochs.add(VendorEpoch(a, b, stage));
        }
        final day = _at(s.dayStart);
        for (final (name, v) in [
          ('rem', s.remMin),
          ('light', s.lightMin),
          ('deep', s.deepMin),
          ('wake', s.wakeMin),
        ]) {
          if (v > 0 && v <= 1440) rows.add(_obs(day, 'sleep_${name}_min', v, 'min', ours: true));
        }
        if (s.score > 0 && s.score <= 100) rows.add(_obs(day, 'sleep_score', s.score, null));
      }
      // ponytail: naps are not read; the strap's nap slots are not understood
      // well enough to tell a nap from a second stretch of the night.
      return _Decoded([
        bank(const []),
        if (epochs.isNotEmpty) VendorHypnogram('helio', epochs),
        if (rows.isNotEmpty) VendorScalars(rows),
      ], p.next);

    case 73:
      final p = helioParseDailyValue(r.payload);
      if (p.failure != null) return _Decoded(const [], null, p.failure);
      final rows = [
        for (final x in p.records)
          if (x.value > 0 && x.value < 250) _obs(_at(x.ts), 'hrv_last_night_avg', x.value, 'ms'),
      ];
      return _Decoded([bank(const []), if (rows.isNotEmpty) VendorScalars(rows)], p.next);

    case 58:
      final p = helioParseDailyValue(r.payload);
      if (p.failure != null) return _Decoded(const [], null, p.failure);
      final rows = [
        for (final x in p.records)
          if (x.value >= 30 && x.value <= 130)
            _obs(_dayOf(x.ts), 'resting_hr', x.value, 'bpm', ours: true),
      ];
      return _Decoded([bank(const []), if (rows.isNotEmpty) VendorScalars(rows)], p.next);

    case 37:
      final p = helioParseSpo2(r.payload, r.headerTime);
      if (p.failure != null) return _Decoded(const [], null, p.failure);
      final rows = _dailyMeans([
        for (final x in p.records)
          if (x.plausible) (x.ts, x.spo2),
      ], 'spo2_avg', '%');
      return _Decoded([bank(const []), if (rows.isNotEmpty) VendorScalars(rows)], p.next);

    case 19:
      final p = helioParseStressAllDay(r.payload, r.headerTime);
      if (p.failure != null) return _Decoded(const [], null, p.failure);
      final rows = _dailyMeans([
        for (final x in p.records)
          if (x.value >= 1 && x.value <= 100) (x.ts, x.value),
      ], 'stress_avg', '');
      return _Decoded([bank(const []), if (rows.isNotEmpty) VendorScalars(rows)], p.next);

    case 46:
      final p = helioParseSkinTemp(r.payload, r.headerTime);
      if (p.failure != null) return _Decoded(const [], null, p.failure);
      return _Decoded([
        bank([
          for (final x in p.records)
            if (x.skinC != null)
              NeutralSample(anchor: TimeAnchor.measured, tsEpoch: x.ts, skinTempC: x.skinC),
        ]),
      ], p.next);
  }
  return _Decoded(const [], null, 'kind $type is not read');
}
