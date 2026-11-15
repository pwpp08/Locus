// stageNap: the night's stager over a nap's window, or nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/nap_staging.dart';
import 'package:openstrap_edge/compute/substrate.dart';

const _t0 = 1786700000;

/// [sec] seconds from [_t0]: a still wrist lying flat, heart rate [hr] (0 is
/// off the wrist), a beat a second.
Substrate _still(int sec, {int Function(int i)? hr}) {
  final n = sec;
  return Substrate(
    tsSec: [for (var i = 0; i < n; i++) _t0 + i],
    hr: [for (var i = 0; i < n; i++) hr?.call(i) ?? 56],
    rrTsMs: [for (var i = 0; i < n; i++) (_t0 + i) * 1000.0],
    rrMs: [for (var i = 0; i < n; i++) 1000.0 + (i % 7) * 12],
    ax: List.filled(n, 0.0),
    ay: List.filled(n, 0.0),
    az: List.filled(n, 1.0),
    spo2Red: List.filled(n, 0),
    spo2Ir: List.filled(n, 0),
    skinTemp: List.filled(n, 0),
    skinContact: List.filled(n, 1),
    deviceFamily: 'gen4',
  );
}

void main() {
  test('a nap the band saw is staged over its own window', () {
    final st = stageNap(_still(3600), _t0, _t0 + 3600)!;
    expect(st['in_bed_min'], 60);
    expect(st['asleep_min'], inInclusiveRange(1, 60));
    final runs = st['runs'] as List;
    expect((runs.first as List)[0], _t0);
    expect((runs.last as List)[1], _t0 + 3600);
    final parts = (st['wake_min'] as int) +
        (st['light_min'] as int) +
        (st['deep_min'] as int) +
        (st['rem_min'] as int);
    expect(parts, closeTo(60, 2));
  });

  test('too short to stage', () {
    expect(stageNap(_still(3600), _t0, _t0 + 10 * 60), isNull);
  });

  test('too little of it recorded to stage', () {
    final sparse = _still(3600, hr: (i) => i < 1800 ? 56 : 0);
    expect(stageNap(sparse, _t0, _t0 + 3600), isNull);
  });

  test('nothing recorded in the window', () {
    expect(stageNap(_still(600), _t0 + 7200, _t0 + 9000), isNull);
  });
}
