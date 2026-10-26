// Strength, derived on read: records from logged sets, a pin typed by hand,
// the best of each session, and total volume cut by day, week and month.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/strength_stats.dart';

int _ts(int y, int m, int d, [int h = 10]) =>
    DateTime(y, m, d, h).millisecondsSinceEpoch ~/ 1000;

LoggedRow _set(String session, String key, int reps, double? kg, int ts) =>
    (session: session, key: key, reps: reps, kg: kg, ts: ts);

void main() {
  group('records', () {
    final rows = [
      _set('a', 'squat', 8, 60, _ts(2026, 10, 1)),
      _set('a', 'squat', 5, 80, _ts(2026, 10, 1)),
      _set('b', 'squat', 5, 80, _ts(2026, 10, 8)),
      _set('b', 'squat', 3, 70, _ts(2026, 10, 8)),
      _set('a', 'pullup', 6, null, _ts(2026, 10, 1)),
      _set('b', 'pullup', 9, null, _ts(2026, 10, 8)),
    ];

    test('the heaviest load, or the most reps for a bodyweight lift', () {
      final r = loggedRecords(rows);
      expect(r['squat']!.kind, RecordKind.weight);
      expect(r['squat']!.value, 80);
      expect(r['pullup']!.kind, RecordKind.reps);
      expect(r['pullup']!.value, 9);
    });

    test('a tie belongs to the first time it was lifted', () {
      expect(loggedRecords(rows)['squat']!.ts, _ts(2026, 10, 1));
    });

    test('a set with no reps counts for nothing', () {
      final r = loggedRecords([_set('a', 'x', 0, 100, _ts(2026, 10, 1))]);
      expect(r, isEmpty);
    });

    test('a loaded lift outranks the same lift done bare', () {
      final r = loggedRecords([
        _set('a', 'dip', 15, null, _ts(2026, 10, 1)),
        _set('b', 'dip', 5, 20, _ts(2026, 10, 8)),
      ]);
      expect(r['dip']!.kind, RecordKind.weight);
    });

    test('a number typed by hand stands, until a later set beats it', () {
      final logged = loggedRecords(rows);
      // Typed after the last session: it stands, even though it is lower.
      final pin = (
        key: 'squat',
        kind: RecordKind.weight,
        value: 75.0,
        ts: _ts(2026, 10, 20)
      );
      var m = mergeRecords(logged, [pin]).firstWhere((e) => e.key == 'squat');
      expect(m.value, 75);
      expect(m.typed, isTrue);
      // Typed before a heavier logged set: the lift has overtaken it.
      final old = (
        key: 'squat',
        kind: RecordKind.weight,
        value: 75.0,
        ts: _ts(2026, 9, 1)
      );
      m = mergeRecords(logged, [old]).firstWhere((e) => e.key == 'squat');
      expect(m.value, 80);
      expect(m.typed, isFalse);
    });

    test('a record typed for a lift never logged is listed', () {
      final m = mergeRecords(const {}, [
        (key: 'curl', kind: RecordKind.weight, value: 20.0, ts: _ts(2026, 10, 2)),
      ]);
      expect(m.single.key, 'curl');
    });

    test('progress is the best of each session, oldest first', () {
      final p = recordProgress('squat', RecordKind.weight, rows);
      expect([for (final e in p) e.v], [80, 80]);
      expect(p.first.ts, lessThan(p.last.ts));
      final reps = recordProgress('pullup', RecordKind.reps, rows);
      expect([for (final e in reps) e.v], [6, 9]);
    });

    test('a typed record is a point of its own', () {
      final p = recordProgress('squat', RecordKind.weight, rows,
          typed: (
            key: 'squat',
            kind: RecordKind.weight,
            value: 90.0,
            ts: _ts(2026, 10, 20)
          ));
      expect(p.last.v, 90);
    });
  });

  group('volume', () {
    // Monday 2026-10-26's week and the four before it.
    const today = '2026-10-28'; // a Wednesday
    final rows = [
      _set('a', 'x', 10, 50, _ts(2026, 10, 26)), // Mon this week: 500
      _set('a', 'y', 5, 100, _ts(2026, 10, 26)), //                500
      _set('b', 'x', 10, 40, _ts(2026, 10, 20)), // last week: 400
      _set('c', 'x', 8, 30, _ts(2026, 9, 29)), //   a month back: 240
      _set('d', 'pull', 6, null, _ts(2026, 10, 27)), // bare: no volume
    ];

    test('a week is its seven days, Monday to Sunday', () {
      final w = volumeWindow(rows, VolumeSpan.week, today: today);
      expect(w.bars.length, 7);
      expect(w.from, '2026-10-26');
      expect(w.to, '2026-11-01');
      expect(w.bars[0].kg, 1000);
      // A day with only a bodyweight set has no volume, not zero.
      expect(w.bars[1].kg, isNull);
      expect(w.bars[2].kg, isNull);
      expect(w.average, 1000);
    });

    test('a month is five whole weeks, the last holding today', () {
      final w = volumeWindow(rows, VolumeSpan.month, today: today);
      expect(w.bars.length, 5);
      expect(w.to, '2026-11-01');
      expect(w.from, '2026-09-28');
      expect(w.bars.last.kg, 1000);
      expect(w.bars[3].kg, 400);
      expect(w.bars[0].kg, 240);
      expect(w.average, closeTo((1000 + 400 + 240) / 3, 1e-9));
    });

    test('paging back moves a whole window', () {
      final w = volumeWindow(rows, VolumeSpan.month, today: today, back: 1);
      expect(w.to, '2026-09-27');
      expect(w.bars.every((b) => b.kg == null), isTrue);
      expect(w.average, isNull);
    });

    test('six months are six calendar months, the last holding today', () {
      final w = volumeWindow(rows, VolumeSpan.sixMonths, today: today);
      expect(w.bars.length, 6);
      expect(w.from, '2026-05-01');
      expect(w.to, '2026-10-31');
      expect(w.bars.last.kg, 1000 + 400);
      expect(w.bars[4].kg, 240);
    });

    test('the axis leaves a step of room over the tallest bar', () {
      expect(volumeAxis(3400), (hi: 6000.0, step: 2000.0));
      expect(volumeAxis(950).step, 500);
      expect(volumeAxis(0), (hi: 6000.0, step: 2000.0));
    });
  });
}
