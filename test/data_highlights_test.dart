// The Profile page's arithmetic, and the double tap every pinchable chart gets.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/data_highlights.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  group('longestStreak', () {
    bool over(double v) => v >= 70;

    test('no days at all is no streak, not a streak of nothing', () {
      expect(longestStreak(const {}, over), isNull);
    });

    test('days that exist but never pass are zero', () {
      expect(longestStreak(const {'2026-11-01': 10}, over), 0);
    });

    test('a missing day breaks the run', () {
      expect(
        longestStreak(const {
          '2026-11-01': 80,
          '2026-11-02': 80,
          '2026-11-04': 80,
        }, over),
        2,
      );
    });

    test('a failing day breaks the run, across a month end', () {
      expect(
        longestStreak(const {
          '2026-10-30': 80,
          '2026-10-31': 80,
          '2026-11-01': 80,
          '2026-11-02': 10,
          '2026-11-03': 80,
        }, over),
        3,
      );
    });
  });

  group('highlightsOf', () {
    const series = <String, Map<String, double>>{
      'sleep_performance': {'2026-09-01': 100, '2026-11-01': 88},
      'recovery': {'2026-09-01': 98, '2026-11-01': 40},
      'strain': {'2026-09-01': 20.6, '2026-11-01': 12},
      'resting_hr': {'2026-09-01': 48, '2026-11-01': 60},
      'tst_min': {'2026-11-01': 561},
      'hr_avg': {'2026-11-01': 70, '2026-11-02': 75},
      'worn_min': {'2026-11-01': 1000},
    };

    test('the period decides which days count', () {
      final all = highlightsOf(series, null);
      expect(all.bestSleep, 100);
      expect(all.peakRecovery, 98);
      expect(all.maxStrain, 20.6);
      final month = highlightsOf(series, '2026-10-08');
      expect(month.bestSleep, 88);
      expect(month.peakRecovery, 40);
      expect(month.maxStrain, 12);
    });

    test('a figure with no days behind it has no row, and nothing is filled in',
        () {
      final none = highlightsOf(const {}, null);
      expect(none.bestSleep, isNull);
      expect(none.sleepStreak, isNull);
      expect(none.notable, isEmpty);
    });

    test('heartbeats need both a mean and a worn time on the day', () {
      final h = highlightsOf(series, null).notable;
      expect(h.singleWhere((s) => s.title == 'Heartbeats').value, '70k');
    });

    test('the longest sleep reads as hours and minutes', () {
      final h = highlightsOf(series, null).notable;
      expect(h.singleWhere((s) => s.title == 'Longest Sleep').value, '9:21');
    });

    test('milestones sit in the same list, in the same shape', () {
      final h = highlightsOf(const {
        'calories': {'2026-11-01': 2000, '2026-11-02': 3000},
        'steps': {'2026-11-01': 10000, '2026-11-02': 2000},
        'tst_min': {'2026-11-01': 600, '2026-11-02': 600},
      }, null).notable;
      final byTitle = {for (final s in h) s.title: s};
      expect(byTitle['Energy Burned']!.value, '5,000');
      expect(byTitle['Energy Burned']!.unit, 'kcal');
      expect(byTitle['Steps Taken']!.value, '12,000');
      expect(byTitle['Time Slept']!.value, '20');
    });
  });

  group('tallyOf', () {
    Map<String, dynamic> s(String type, {num? strain, int day = 1, bool live = false}) => {
      'type': type,
      'strain': strain,
      'start_ts': DateTime(2026, 11, day, 9).millisecondsSinceEpoch ~/ 1000,
      if (!live) 'end_ts': DateTime(2026, 11, day, 10).millisecondsSinceEpoch ~/ 1000,
    };

    test('counts, averages only what was scored, most frequent first', () {
      final rows = tallyOf([
        s('Running', strain: 10),
        s('Running', strain: 14),
        s('Running'),
        s('Cycling', strain: 7),
      ], null);
      expect(rows.map((r) => r.name), ['Running', 'Cycling']);
      expect(rows.first.count, 3);
      expect(rows.first.avgStrain, 12);
    });

    test('no average when nothing was scored', () {
      expect(tallyOf([s('Cycling')], null).single.avgStrain, isNull);
    });

    test('a session still running is not a recorded one', () {
      expect(tallyOf([s('Cycling', live: true)], null), isEmpty);
    });

    test('the period cuts by local day', () {
      final rows = tallyOf([s('Cycling', day: 1), s('Cycling', day: 5)], '2026-11-03');
      expect(rows.single.count, 1);
    });
  });

  group('double tap on a chart', () {
    Future<List<(PinchPhase, double, double)>> pumpStrip(
      WidgetTester t, {
      required bool pinchable,
    }) async {
      final calls = <(PinchPhase, double, double)>[];
      await t.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 100,
            child: Scrubber(
              value: null,
              onChanged: (_) {},
              label: 'chart',
              describe: (v) => '$v',
              onPinch: pinchable
                  ? (ph, sc, fo, pa) => calls.add((ph, sc, fo))
                  : null,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ));
      return calls;
    }

    /// A tap whose events carry a real clock, which a double tap is timed by.
    Future<void> tapAt(WidgetTester t, Offset at, int ms) async {
      final g = await t.startGesture(at);
      await g.up(timeStamp: Duration(milliseconds: ms));
      await t.pump();
    }

    testWidgets('zooms in around the place tapped', (t) async {
      final calls = await pumpStrip(t, pinchable: true);
      final at = t.getTopLeft(find.byType(Scrubber)) + const Offset(100, 50);
      await tapAt(t, at, 1000);
      await tapAt(t, at, 1120);
      await t.pumpAndSettle();
      expect(calls.first.$1, PinchPhase.start);
      expect(calls.first.$3, closeTo(.25, .001));
      expect(calls.last.$1, PinchPhase.end);
      final updates = calls.where((c) => c.$1 == PinchPhase.update);
      expect(updates.last.$2, closeTo(2, .001));
      expect(updates.last.$3, closeTo(.25, .001));
    });

    testWidgets('two slow taps are two taps', (t) async {
      final calls = await pumpStrip(t, pinchable: true);
      final at = t.getCenter(find.byType(Scrubber));
      await tapAt(t, at, 1000);
      await tapAt(t, at, 1500);
      await t.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('a chart that cannot be pinched is left alone', (t) async {
      await pumpStrip(t, pinchable: false);
      final at = t.getCenter(find.byType(Scrubber));
      await tapAt(t, at, 1000);
      await tapAt(t, at, 1120);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
