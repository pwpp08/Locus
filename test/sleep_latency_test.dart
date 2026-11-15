// bedTimeBefore: the lie-down, read off the wrist's minutes before a night.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/sleep_latency.dart';

const _onset = 1786700000 ~/ 60 * 60;

/// The minutes before the onset, oldest first, at [shares].
List<({int t, double v})> _lead(List<double> shares) => [
      for (var i = 0; i < shares.length; i++)
        (t: _onset - (shares.length - i) * 60, v: shares[i]),
    ];

void main() {
  test('bed is the end of the last active minute before a quiet run', () {
    final b = bedTimeBefore(
        _onset, _lead([.8, .7, .6, .1, .2, .0, .15, .05, .0, .0]));
    expect(b, _onset - 7 * 60);
  });

  test('tossing and turning is still in bed', () {
    final b = bedTimeBefore(_onset, _lead([.9, .3, .35, .2, .38, .1]));
    expect(b, _onset - 5 * 60);
  });

  test('an unmeasured minute in the run: no answer', () {
    final lead = _lead([.8, .1, .1, .1])..removeAt(2);
    expect(bedTimeBefore(_onset, lead), isNull);
  });

  test('no active minute in the look-back: no answer', () {
    expect(bedTimeBefore(_onset, _lead(List.filled(90, .1))), isNull);
  });

  test('a run over an hour is rest, not falling asleep', () {
    expect(
        bedTimeBefore(_onset, _lead([.9, ...List.filled(70, .1)])), isNull);
    expect(bedTimeBefore(_onset, _lead([.9, ...List.filled(50, .1)])),
        _onset - 50 * 60);
  });

  test('no onset, no bed', () {
    expect(bedTimeBefore(0, _lead([.9, .1])), isNull);
  });
}
