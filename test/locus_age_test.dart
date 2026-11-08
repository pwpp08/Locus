// Locus Age: the blob's physics, the week arithmetic, what a locked reading
// still shows, and the words written from the figures.

import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/compute/whoop_age.dart';
import 'package:openstrap_edge/ui2/profile/storage_screen.dart';
import 'package:openstrap_edge/ui2/screens/locus_age.dart';
import 'package:openstrap_edge/ui2/screens/locus_blob.dart';

double _maxOffset(BlobSim s) {
  var most = 0.0;
  for (var i = 0; i < BlobSim.nodeCount; i++) {
    final o = (s.radiusAt(i) - 1).abs();
    if (o > most) most = o;
  }
  return most;
}

void main() {
  group('blob', () {
    test('stays bounded at the worst frame rate, poked or not', () {
      final s = BlobSim();
      for (var i = 0; i < 2000; i++) {
        if (i % 40 == 0) s.tap(.8, -.3);
        s.step(1 / 30);
        expect(_maxOffset(s), lessThanOrEqualTo(.24 + 1e-9));
        expect(s.dotX(i % BlobSim.dotCount).isFinite, isTrue);
      }
    });

    test('the rim reaches for a finger and lets go after', () {
      final s = BlobSim();
      for (var i = 0; i < 60; i++) {
        s.step(1 / 60);
      }
      final before = s.radiusAt(0);
      s.press(.9, 0); // Node 0 is the point at angle zero.
      for (var i = 0; i < 40; i++) {
        s.step(1 / 60);
      }
      expect(s.radiusAt(0), greaterThan(before + .03));
      s.release();
      for (var i = 0; i < 600; i++) {
        s.step(1 / 60);
      }
      expect(_maxOffset(s), lessThan(.11));
    });

    test('specks scatter from under a finger and come home', () {
      final s = BlobSim();
      double nearest() {
        var best = 9.0;
        for (var i = 0; i < BlobSim.dotCount; i++) {
          final dx = s.dotX(i) - .75, dy = s.dotY(i);
          final d = dx * dx + dy * dy;
          if (d < best) best = d;
        }
        return best;
      }

      final idle = nearest();
      s.press(.75, 0);
      for (var i = 0; i < 90; i++) {
        s.step(1 / 60);
      }
      expect(nearest(), greaterThan(idle));
    });
  });

  group('weeks', () {
    test('only finished Sunday to Saturday weeks count', () {
      // 2026-11-08 is a Sunday: yesterday's Saturday has just finished.
      expect(finishedSaturdays('2026-11-08', 2), ['2026-11-07', '2026-10-31']);
      // On a Saturday, the week in progress is not over yet.
      expect(finishedSaturdays('2026-11-07', 1), ['2026-10-31']);
      expect(finishedSaturdays('2026-11-09', 1), ['2026-11-07']);
    });

    test('the next update is the coming Sunday', () {
      expect(daysToNextUpdate('2026-11-08'), 7); // Sunday
      expect(daysToNextUpdate('2026-11-09'), 6); // Monday
      expect(daysToNextUpdate('2026-11-14'), 1); // Saturday
    });
  });

  group('reading', () {
    final days = [
      for (var i = 0; i < 20; i++)
        '2026-10-${(i + 10).toString().padLeft(2, '0')}',
    ];

    test('locked: contributors are there, an age is not', () {
      final r = whoopAge(
        today: '2026-10-29',
        age: 30,
        sex: 'm',
        recovery: {for (final d in days.take(14)) d: 60},
        sleepMin: {for (final d in days) d: 420},
      );
      expect(r.whoopAge, isNull);
      expect(r.pace, isNull);
      expect(r.why, contains('have=14'));
      expect(r.parts.keys, contains('sleep_hours'));
      expect(r.recent.keys, contains('sleep_hours'));
      expect(r.age, 30);
    });

    test('a row with no data is simply absent', () {
      final r = whoopAge(
        today: '2026-10-29',
        age: 30,
        sex: 'm',
        recovery: {for (final d in days) d: 60},
        sleepMin: {for (final d in days) d: 420},
      );
      expect(r.parts.containsKey('lean_mass'), isFalse);
      expect(r.parts.containsKey('vo2max'), isFalse);
    });
  });

  group('words', () {
    const part = (value: 7.0, target: 7.0, years: 0.0);
    const worse = (value: 5.5, target: 7.0, years: .8);

    test('the note names what actually moved', () {
      const now = WhoopAgeResult(
        whoopAge: 30.5,
        pace: 1.8,
        age: 30,
        parts: {'sleep_hours': part},
        recent: {'sleep_hours': worse},
      );
      const before = WhoopAgeResult(whoopAge: 30.2, pace: 1, age: 30);
      final n = paceInsight(now, before);
      expect(n.title, 'Picking up speed');
      expect(n.body, contains('went up by 0.3'));
      expect(n.body, contains('Hours of sleep'));
    });

    test('a first week does not claim a change', () {
      const now = WhoopAgeResult(whoopAge: 30, pace: 1, age: 30);
      final n = paceInsight(now, null);
      expect(n.body, contains('first full week'));
      expect(n.title, 'Holding steady');
    });

    test('a bar is amber short of the target and green past it', () {
      final row = kLocusGroups.first.$2.last; // hours of sleep
      expect(locusSegment(5.2, row, 7).g, lessThan(locusSegment(7.9, row, 7).g));
      expect(
        locusSegment(7, row, 7).toARGB32(),
        locusSegment(7.05, row, 7).toARGB32(),
      );
    });
  });

  test('storage lines add up to the file and put the biggest first', () {
    final lines = storageLines(
      tables: const [
        {'table': 'decoded_onehz', 'bytes': 200},
        {'table': 'day_result', 'bytes': 30},
        {'table': 'metric_series', 'bytes': 20},
      ],
      fileBytes: 300,
      freeBytes: 10,
    );
    expect(lines.first.label, 'Second-by-second readings');
    expect(lines.fold<int>(0, (a, l) => a + l.bytes), 300);
    expect(lines.map((l) => l.label), isNot(contains('Heartbeat intervals')));
  });
}
