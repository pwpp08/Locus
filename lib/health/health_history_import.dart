// Read sleep, steps and heart-rate HISTORY out of the platform health store
// into tables this app does not derive from.
//
// The same rule as `health_workout_import.dart`, and for the same reason: these
// are other apps' and devices' numbers. They are shown with the name of whatever
// recorded them and are never an input to a score, a baseline or a calibration,
// and never added to ours. Two sources' step counts for one day stay two rows —
// the table is keyed by source — because a total of two devices' models is a
// number neither would agree with.
//
// Our own exported data is skipped (it is already ours, and the export rewrites
// it on every pass), by the same own-app test the workout import uses.
//
// Everything that decides what a row says is pure and takes points in, so the
// grouping is tested without a store.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/day_label.dart';
import '../data/db.dart';
import 'health_import_state.dart';
import 'health_read_access.dart';
import 'health_workout_import.dart'
    show isOwnHealthPoint, kImportWindowDaysAndroid, kImportWindowDaysApple;

/// A night another app recorded.
@immutable
class ImportedNight {
  const ImportedNight({
    required this.uuid,
    required this.startTs,
    required this.endTs,
    required this.source,
    this.asleepS,
    this.deepS,
    this.remS,
    this.lightS,
  });

  final String uuid, source;
  final int startTs, endTs;

  /// Null where the source recorded no stages at all: the length of the night
  /// is then all we know, and "asleep" would be a guess.
  final int? asleepS, deepS, remS, lightS;

  Map<String, Object?> toRow() => {
        'uuid': uuid,
        'start_ts': startTs,
        'end_ts': endTs,
        'asleep_s': asleepS,
        'deep_s': deepS,
        'rem_s': remS,
        'light_s': lightS,
        'source': source,
      };
}

/// One day's steps or heart-rate figure from one source.
@immutable
class ImportedDay {
  const ImportedDay(this.day, this.kind, this.source, this.value);
  final String day, kind, source;
  final double value;

  Map<String, Object?> toRow() =>
      {'day': day, 'kind': kind, 'source': source, 'value': value};
}

const String kKindSteps = 'steps';
const String kKindHrAvg = 'hr_avg';
const String kKindHrMin = 'hr_min';
const String kKindHrMax = 'hr_max';

String _src(HealthDataPoint p) =>
    p.sourceName.trim().isEmpty ? 'Unknown app' : p.sourceName;

int _sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

const _stageAsleep = {
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_REM,
};

/// The sleep types a read needs.
const List<HealthDataType> kSleepTypes = [
  HealthDataType.SLEEP_SESSION,
  HealthDataType.SLEEP_IN_BED,
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_REM,
  HealthDataType.SLEEP_AWAKE,
];

/// Seconds of [spans] inside [from, to], overlaps counted once.
int _union(List<(int, int)> spans, int from, int to) {
  final clipped = [
    for (final s in spans)
      if (s.$2 > from && s.$1 < to) (s.$1 < from ? from : s.$1, s.$2 > to ? to : s.$2),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  var total = 0, cur = -1;
  for (final s in clipped) {
    final a = s.$1 > cur ? s.$1 : cur;
    if (s.$2 > a) total += s.$2 - a;
    if (s.$2 > cur) cur = s.$2;
  }
  return total;
}

/// Nights from raw points, per source. A night is a sleep session or in-bed
/// span; where a source gives only stage segments, they are grouped into nights
/// at gaps of [gap] or more. Bad windows (under half an hour, over 20 hours)
/// are dropped, never repaired.
@visibleForTesting
List<ImportedNight> nightsFrom(
  List<HealthDataPoint> points, {
  String? ownApp,
  Duration gap = const Duration(minutes: 90),
}) {
  final bySource = <String, List<HealthDataPoint>>{};
  for (final p in points) {
    if (!kSleepTypes.contains(p.type) || isOwnHealthPoint(p, ownApp)) continue;
    bySource.putIfAbsent(_src(p), () => []).add(p);
  }
  final out = <ImportedNight>[];
  final seen = <String>{};
  for (final e in bySource.entries) {
    final source = e.key;
    final pts = e.value;
    List<HealthDataPoint> of(Set<HealthDataType> t) =>
        [for (final p in pts) if (t.contains(p.type)) p];
    (int, int) span(HealthDataPoint p) => (_sec(p.dateFrom), _sec(p.dateTo));
    List<(int, int)> spans(Set<HealthDataType> t) =>
        [for (final p in of(t)) span(p)];

    // The windows: sessions, else in-bed spans, else stage segments clustered.
    var windows = <({String uuid, int from, int to})>[];
    final base = of({HealthDataType.SLEEP_SESSION}).isNotEmpty
        ? of({HealthDataType.SLEEP_SESSION})
        : of({HealthDataType.SLEEP_IN_BED});
    if (base.isNotEmpty) {
      windows = [
        for (final p in base)
          if (p.uuid.isNotEmpty) (uuid: p.uuid, from: _sec(p.dateFrom), to: _sec(p.dateTo)),
      ];
    } else {
      final segs = spans({..._stageAsleep, HealthDataType.SLEEP_AWAKE})
        ..sort((a, b) => a.$1.compareTo(b.$1));
      int from = 0, to = 0;
      var open = false;
      for (final s in segs) {
        if (open && s.$1 - to < gap.inSeconds) {
          if (s.$2 > to) to = s.$2;
          continue;
        }
        if (open) windows.add((uuid: 'sleep:$source:$from', from: from, to: to));
        from = s.$1;
        to = s.$2;
        open = true;
      }
      if (open) windows.add((uuid: 'sleep:$source:$from', from: from, to: to));
    }

    for (final w in windows) {
      final len = w.to - w.from;
      if (len < 30 * 60 || len > 20 * 3600) continue;
      if (!seen.add(w.uuid)) continue;
      final asleep = _union(spans(_stageAsleep), w.from, w.to);
      int? stage(HealthDataType t) {
        final n = _union(spans({t}), w.from, w.to);
        return n == 0 ? null : n;
      }

      out.add(ImportedNight(
        uuid: w.uuid,
        startTs: w.from,
        endTs: w.to,
        source: source,
        asleepS: asleep == 0 ? null : asleep,
        deepS: stage(HealthDataType.SLEEP_DEEP),
        remS: stage(HealthDataType.SLEEP_REM),
        lightS: stage(HealthDataType.SLEEP_LIGHT),
      ));
    }
  }
  return out;
}

double? _num(HealthDataPoint p) {
  final v = p.value;
  return v is NumericHealthValue ? v.numericValue.toDouble() : null;
}

/// Daily steps and heart-rate figures from raw points, per source and local
/// day. Heart rate outside 25–250 bpm is a bad sample and is dropped.
@visibleForTesting
List<ImportedDay> dailyFrom(List<HealthDataPoint> points, {String? ownApp}) {
  final steps = <(String, String), double>{};
  final hr = <(String, String), List<double>>{};
  for (final p in points) {
    if (isOwnHealthPoint(p, ownApp)) continue;
    final v = _num(p);
    if (v == null) continue;
    final key = (dayLabelOf(p.dateFrom), _src(p));
    if (p.type == HealthDataType.STEPS) {
      if (v > 0) steps[key] = (steps[key] ?? 0) + v;
    } else if (p.type == HealthDataType.HEART_RATE) {
      if (v >= 25 && v <= 250) hr.putIfAbsent(key, () => []).add(v);
    }
  }
  return [
    for (final e in steps.entries)
      ImportedDay(e.key.$1, kKindSteps, e.key.$2, e.value.roundToDouble()),
    for (final e in hr.entries) ...[
      ImportedDay(e.key.$1, kKindHrAvg, e.key.$2,
          e.value.reduce((a, b) => a + b) / e.value.length),
      ImportedDay(e.key.$1, kKindHrMin, e.key.$2,
          e.value.reduce((a, b) => a < b ? a : b)),
      ImportedDay(e.key.$1, kKindHrMax, e.key.$2,
          e.value.reduce((a, b) => a > b ? a : b)),
    ],
  ];
}

/// What one history import brought in.
@immutable
class HistoryImportResult {
  const HistoryImportResult({this.nights = 0, this.days = 0});
  final int nights, days;
  bool get any => nights > 0 || days > 0;
}

class HealthHistoryImporter {
  HealthHistoryImporter({Health? health, bool? isApple})
      : _health = health ?? Health(),
        _isApple = isApple ?? (Platform.isIOS || Platform.isMacOS);

  final Health _health;
  final bool _isApple;

  static const List<HealthDataType> types = [
    ...kSleepTypes,
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
  ];

  Future<bool> requestPermission() => requestAnyHealthRead(_health, types);

  /// Read the window, store what came back. Never throws: an empty store, a
  /// denied permission and a locked device all come back as zero.
  Future<HistoryImportResult> sync({DateTime? now}) async {
    final end = now ?? DateTime.now();
    final start = end.subtract(Duration(
      days: _isApple ? kImportWindowDaysApple : kImportWindowDaysAndroid,
    ));
    String? ownApp;
    try {
      ownApp = (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {}
    try {
      await _health.configure();
      // Nights first: a session can start before the window and end inside it.
      final sleep = await readEachHealthType(_health,
          types: kSleepTypes,
          start: start.subtract(const Duration(hours: 12)),
          end: end);
      final nights = nightsFrom(sleep, ownApp: ownApp);
      await LocalDb.putImportedSleep([for (final n in nights) n.toRow()]);
      // A week at a time, from local midnight to local midnight, so a day is
      // never split across two reads (a quarter of heart rate in one read is a
      // lot of rows).
      final days = <ImportedDay>[];
      var a = DateTime(start.year, start.month, start.day);
      while (a.isBefore(end)) {
        final b = DateTime(a.year, a.month, a.day + 7);
        final pts = await readEachHealthType(_health,
            types: const [HealthDataType.STEPS, HealthDataType.HEART_RATE],
            start: a,
            end: b.isAfter(end) ? end : b);
        days.addAll(dailyFrom(pts, ownApp: ownApp));
        a = b;
      }
      await LocalDb.putImportedDaily([for (final d in days) d.toRow()]);
      return HistoryImportResult(
          nights: nights.length,
          days: {for (final d in days) d.day}.length);
    } catch (e) {
      debugPrint('[imported_history] read: $e');
      return const HistoryImportResult();
    }
  }

  /// Marks the history import done only when rows arrived.
  Future<HistoryImportResult> run() async {
    final r = await sync();
    if (r.any) await markImported(HealthImport.history);
    return r;
  }
}
