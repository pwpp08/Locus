// watch_compare.dart — read another watch's data back out of Health Connect /
// HealthKit so it can be laid next to the band's for the same period.
//
// WHY NOT THE WATCH'S BLUETOOTH. A Galaxy Watch is bonded to Samsung Health over
// an encrypted, proprietary link; there is no documented GATT service to read
// heart rate or sleep from, and pairing it to a second app would break its own
// sync. Samsung Health already copies what the watch measures into Health
// Connect, so that is the honest, supported route — and it works the same for
// any other watch whose app writes there (Pixel Watch, Garmin, Fitbit…).
//
// WHAT IS NEVER COMPARED. This app writes the band's own heart rate, sleep and
// steps INTO Health Connect when health sync is on, so a naive read would
// compare the band with itself and report perfect agreement. Every sample this
// app wrote is dropped ([isOwnHealthSample]), and the reader keeps one source
// at a time so two watches are never blended into one line.
//
// Nothing read here is stored or fed into any derived metric. It is a
// side-by-side view and nothing else.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'health_rhr_seed.dart' show isOwnHealthSample;

/// Samsung Health's Android package — what Health Connect reports as the
/// source of everything a Galaxy Watch measured.
const String kSamsungHealthPackage = 'com.sec.android.app.shealth';

/// One night as the other watch scored it.
@immutable
class WatchNight {
  const WatchNight({
    required this.start,
    required this.end,
    required this.stageMin,
  });

  final DateTime start, end;

  /// Minutes per stage: `deep`, `light`, `rem`, `awake`. A stage the watch did
  /// not report is absent, not zero.
  final Map<String, int> stageMin;

  int get inBedMin => end.difference(start).inMinutes;

  /// Asleep minutes, when the watch staged the night; null when it only
  /// recorded a session with no stages.
  int? get asleepMin {
    final parts = [stageMin['deep'], stageMin['light'], stageMin['rem']];
    if (parts.every((v) => v == null)) return null;
    return parts.fold<int>(0, (a, v) => a + (v ?? 0));
  }
}

/// Everything read for one window from one source.
@immutable
class WatchWindow {
  const WatchWindow({
    required this.source,
    required this.hr,
    required this.nights,
    this.steps,
    this.restingHr,
    this.hrvRmssd,
    this.spo2,
    this.resp,
  });

  final String source;

  /// Heart-rate samples, (epoch seconds, bpm), time-ordered.
  final List<(int, double)> hr;

  /// Sleep sessions overlapping the window, earliest first.
  final List<WatchNight> nights;

  final int? steps;
  final double? restingHr, hrvRmssd, spo2, resp;

  /// The session that overlaps [from]..[to] the most, or null.
  WatchNight? nightOverlapping(DateTime from, DateTime to) {
    WatchNight? best;
    var bestMin = 0;
    for (final n in nights) {
      final s = n.start.isAfter(from) ? n.start : from;
      final e = n.end.isBefore(to) ? n.end : to;
      final m = e.difference(s).inMinutes;
      if (m > bestMin) {
        bestMin = m;
        best = n;
      }
    }
    return best;
  }

  /// The longest session that ENDS inside [from]..[to] — "last night" for a
  /// day when the band has no night of its own to line up against.
  WatchNight? longestEndingIn(DateTime from, DateTime to) {
    WatchNight? best;
    for (final n in nights) {
      if (n.end.isBefore(from) || n.end.isAfter(to)) continue;
      if (best == null || n.inBedMin > best.inBedMin) best = n;
    }
    return best;
  }
}

/// How two heart-rate lines agree, over the minutes both of them measured.
@immutable
class HrAgreement {
  const HrAgreement({
    required this.pairedMinutes,
    required this.meanDiff,
    required this.meanAbsDiff,
    required this.r,
  });

  /// Minutes where both devices had a reading.
  final int pairedMinutes;

  /// Mean of (watch − band), bpm. Positive: the watch reads higher.
  final double meanDiff;

  /// Mean absolute difference, bpm.
  final double meanAbsDiff;

  /// Pearson correlation over the paired minutes; null under 10 pairs or with
  /// no spread on one side.
  final double? r;

  /// Pair two (epoch-seconds, bpm) lines by minute. Each side is averaged
  /// within a minute first. Null when fewer than 5 minutes pair up — too
  /// few for a mean difference to mean anything.
  static HrAgreement? of(List<(int, double)> band, List<(int, double)> watch) {
    Map<int, double> perMin(List<(int, double)> l) {
      final sum = <int, double>{}, n = <int, int>{};
      for (final (t, v) in l) {
        if (v <= 0) continue;
        final m = t ~/ 60;
        sum[m] = (sum[m] ?? 0) + v;
        n[m] = (n[m] ?? 0) + 1;
      }
      return {for (final k in sum.keys) k: sum[k]! / n[k]!};
    }

    final a = perMin(band), b = perMin(watch);
    final xs = <double>[], ys = <double>[];
    for (final k in a.keys) {
      final w = b[k];
      if (w == null) continue;
      xs.add(a[k]!);
      ys.add(w);
    }
    if (xs.length < 5) return null;
    var d = 0.0, ad = 0.0;
    for (var i = 0; i < xs.length; i++) {
      d += ys[i] - xs[i];
      ad += (ys[i] - xs[i]).abs();
    }
    double? r;
    if (xs.length >= 10) {
      final mx = xs.reduce((p, q) => p + q) / xs.length;
      final my = ys.reduce((p, q) => p + q) / ys.length;
      var sxy = 0.0, sxx = 0.0, syy = 0.0;
      for (var i = 0; i < xs.length; i++) {
        sxy += (xs[i] - mx) * (ys[i] - my);
        sxx += (xs[i] - mx) * (xs[i] - mx);
        syy += (ys[i] - my) * (ys[i] - my);
      }
      if (sxx > 0 && syy > 0) r = sxy / math.sqrt(sxx * syy);
    }
    return HrAgreement(
      pairedMinutes: xs.length,
      meanDiff: d / xs.length,
      meanAbsDiff: ad / xs.length,
      r: r,
    );
  }
}

class WatchCompareReader {
  WatchCompareReader({Health? health}) : _health = health ?? Health();

  final Health _health;

  static const List<HealthDataType> types = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
  ];

  /// READ only — this view never writes anything.
  Future<bool> requestPermission() async {
    try {
      await _health.configure();
      final perms = [for (final _ in types) HealthDataAccess.READ];
      final already =
          await _health.hasPermissions(types, permissions: perms);
      if (already == true) return true;
      return await _health.requestAuthorization(types, permissions: perms);
    } catch (e) {
      debugPrint('[watch_compare] permission: $e');
      return false;
    }
  }

  Future<String> _ownId() async {
    try {
      return (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {
      return '';
    }
  }

  static String _sourceOf(HealthDataPoint p) =>
      p.sourceName.isNotEmpty ? p.sourceName : p.sourceId;

  Future<List<HealthDataPoint>> _read(DateTime start, DateTime end) async {
    await _health.configure();
    final own = await _ownId();
    // Without our own id we cannot drop what this app wrote, and a band
    // compared with itself is the one result this screen must never show.
    if (own.isEmpty) return const [];
    final pts = <HealthDataPoint>[];
    // Read type by type: one type the provider refuses (an undeclared or
    // denied permission) must not blank every other row.
    for (final t in types) {
      try {
        pts.addAll(await _health.getHealthDataFromTypes(
            types: [t], startTime: start, endTime: end));
      } catch (e) {
        debugPrint('[watch_compare] read $t: $e');
      }
    }
    return [
      for (final p in pts)
        if (!isOwnHealthSample(p.sourceId, p.sourceName, own)) p,
    ];
  }

  /// Every app that wrote heart rate or sleep in the window, most samples
  /// first — the candidates for "the other watch".
  Future<List<String>> sources(DateTime start, DateTime end) async {
    final counts = <String, int>{};
    for (final p in await _read(start, end)) {
      if (p.type != HealthDataType.HEART_RATE &&
          p.type != HealthDataType.SLEEP_SESSION) {
        continue;
      }
      final s = _sourceOf(p);
      if (s.isEmpty) continue;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final out = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return out;
  }

  /// One source's data for [start]..[end]. Steps are summed only over records
  /// that lie wholly inside the window; scalars are means over the window.
  Future<WatchWindow> read(DateTime start, DateTime end,
      {required String source}) async {
    final pts = [
      for (final p in await _read(start, end))
        if (_sourceOf(p) == source) p,
    ];
    double? num0(HealthDataPoint p) {
      final v = p.value;
      return v is NumericHealthValue ? v.numericValue.toDouble() : null;
    }

    double? mean(HealthDataType t) {
      final v = [
        for (final p in pts)
          if (p.type == t) ?num0(p),
      ];
      return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    }

    final hr = <(int, double)>[
      for (final p in pts)
        if (p.type == HealthDataType.HEART_RATE)
          if (num0(p) case final v?)
            (p.dateFrom.millisecondsSinceEpoch ~/ 1000, v),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    int? steps;
    for (final p in pts) {
      if (p.type != HealthDataType.STEPS) continue;
      if (p.dateFrom.isBefore(start) || p.dateTo.isAfter(end)) continue;
      steps = (steps ?? 0) + (num0(p)?.round() ?? 0);
    }

    final sessions = [
      for (final p in pts)
        if (p.type == HealthDataType.SLEEP_SESSION) p,
    ]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    const stageKeys = {
      HealthDataType.SLEEP_DEEP: 'deep',
      HealthDataType.SLEEP_LIGHT: 'light',
      HealthDataType.SLEEP_REM: 'rem',
      HealthDataType.SLEEP_AWAKE: 'awake',
    };
    final nights = <WatchNight>[];
    for (final s in sessions) {
      final mins = <String, int>{};
      for (final p in pts) {
        final key = stageKeys[p.type];
        if (key == null) continue;
        if (p.dateTo.isBefore(s.dateFrom) || p.dateFrom.isAfter(s.dateTo)) {
          continue;
        }
        mins[key] =
            (mins[key] ?? 0) + p.dateTo.difference(p.dateFrom).inMinutes;
      }
      nights.add(WatchNight(start: s.dateFrom, end: s.dateTo, stageMin: mins));
    }

    return WatchWindow(
      source: source,
      hr: hr,
      nights: nights,
      steps: steps,
      restingHr: mean(HealthDataType.RESTING_HEART_RATE),
      hrvRmssd: mean(HealthDataType.HEART_RATE_VARIABILITY_RMSSD),
      // Health Connect hands oxygen saturation over as a fraction on some
      // providers and a percent on others.
      spo2: switch (mean(HealthDataType.BLOOD_OXYGEN)) {
        final v? when v <= 1.0 => v * 100,
        final v => v,
      },
      resp: mean(HealthDataType.RESPIRATORY_RATE),
    );
  }
}
