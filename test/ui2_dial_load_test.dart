// What the dial screens read off the repository: the stored series, keyed by the
// day they belong to, and the parts of the need rebuilt from them.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/behavior_impact.dart';
import 'package:openstrap_edge/compute/whoop_scores.dart' show whoopStrainSleepMin;
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';

const _day = '2026-05-20';
int _noon(String d) =>
    DateTime.parse('$d 12:00:00').millisecondsSinceEpoch ~/ 1000;
final _onset = DateTime(2026, 5, 19, 23, 7).millisecondsSinceEpoch ~/ 1000;
final _wake = _onset + 425 * 60;

class _Repo extends LocalRepository {
  final Map<String, Map<String, double>> charts;
  final List<Map<String, dynamic>> journal;
  _Repo(this.charts, {this.journal = const []});

  @override
  Future<Map<String, dynamic>> getChart(String metric,
          {int? from, int? to, Set<String> signals = const {}}) async =>
      {
        'points': [
          for (final e in (charts[metric] ?? const <String, double>{}).entries)
            {'t': _noon(e.key), 'v': e.value},
        ],
      };

  @override
  Future<List<String>> availableDays() async => const [_day];

  @override
  Future<Map<String, dynamic>> getToday() async => {
        'status': {'today_day': _day},
        'daily': {'readiness': {'value': 70, 'confidence': .8, 'tier': 'HIGH'}},
      };

  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) async => {
        'has_sleep': true,
        'duration_min': 370,
        'onset_ts': _onset,
        'wake_ts': _wake,
      };

  @override
  Future<List<Map<String, Object?>>> getDeviceNights(String date) async =>
      const [];

  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) async => {
        'date': date,
        'hr': [
          {'t': _onset + 60, 'v': 55},
          {'t': _onset + 120, 'v': 54},
          {'t': _onset - 86400, 'v': 99},
        ],
      };

  @override
  Future<List<Map<String, dynamic>>> sleepWindows(
          {int days = 60, String? before}) async =>
      [
        {
          'date': _day,
          'onset_ts': _onset,
          'wake_ts': _wake,
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> getSessions(
          {int? from, int? to, bool includeDetected = true}) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> getJournal({String range = '30d'}) async =>
      journal;
}

Map<String, double> _on(double v, double before) => {
      _day: v,
      for (var i = 1; i <= 40; i++) shiftDay(_day, -i): before,
    };

void main() {
  test('Sleep reads its night and rebuilds the need from the series', () async {
    final strain = 14.0;
    final d = await SleepData.load(
      _Repo({
        'sleep': _on(370, 400),
        'sleep_last_need_min': _on(650, 500),
        'sleep_performance': _on(72, 80),
        'sleep_consistency': _on(85, 70),
        'efficiency': _on(89, 91),
        'strain': _on(10, strain),
        'nap_min': {shiftDay(_day, -1): 20},
        'deep': _on(108, 100),
        'rem': _on(107, 100),
      }),
      want: _day,
    );
    expect(d.day, _day);
    expect(d.performance, 72);
    expect(d.lastNeedMin, 650);
    expect(d.consistency, 85);
    // Prior 30 days, not counting the night itself.
    expect(d.vitals.prior(d.vitals.perf, _day), 80);
    expect(d.vitals.prior(d.vitals.eff, _day), 91);
    expect(d.vitals.priorRestorative(_day), 200);
    expect(d.vitals.week.last, _day);
    expect(d.vitals.spans[_day]?.bed, (23 * 60 + 7 - 720).toDouble());

    final parts = d.vitals.needParts!;
    final strainMin = whoopStrainSleepMin(strain);
    expect(parts.strain, strainMin);
    expect(parts.nap, 20);
    // Half of the night before's shortfall: need 500 against 400 asleep.
    expect(parts.debt, 50);
    expect(parts.baseline, 650 - strainMin - 50 + 20);

    // The bundle's curve stands in where the raw store is gone, clipped to the
    // night and its margins.
    expect(d.vitals.heart.map((p) => p.v), [55, 54]);
  });

  test('a series with nothing stored stays absent', () async {
    final d = await SleepData.load(_Repo(const {}), want: _day);
    expect(d.performance, isNull);
    expect(d.lastNeedMin, isNull);
    expect(d.vitals.needParts, isNull);
    expect(d.vitals.prior(d.vitals.perf, _day), isNull);
  });

  test('Recovery reads its day and each contributor', () async {
    final d = await ReadinessData.load(_Repo({
      'recovery': _on(70, 60),
      'hrv': _on(114, 107),
      'resting_hr': _on(60, 58),
      'resp_rate': _on(15.5, 15.2),
      'sleep_performance': _on(72, 78),
    }));
    expect(d.day, _day);
    expect(d.readiness.value, 70);
    expect(d.vitals.hrv[_day], 114);
    expect(d.vitals.prior(d.vitals.restingHr, _day), 58);
    expect(d.vitals.resp[_day], 15.5);
  });

  test('Behavior Insights compares its own days and journal tags', () async {
    final recovery = {
      for (var i = 0; i < 40; i++) shiftDay(_day, -i): i.isEven ? 80.0 : 50.0,
    };
    final got = await BehaviorInsightsData.load(
      _Repo(
        {
          'recovery': recovery,
          // Hard on the odd-back days, so the mornings after are the even ones.
          'strain': {
            for (var i = 0; i < 41; i++) shiftDay(_day, -i): i.isOdd ? 16.0 : 8.0,
          },
          'sleep_performance': {
            for (var i = 0; i < 40; i++)
              shiftDay(_day, -i): i.isEven ? 90.0 : 60.0,
          },
        },
        journal: [
          for (var i = 0; i < 12; i++)
            {
              'date': shiftDay(_day, -i),
              'tags': i.isEven ? const <String>[] : const ['alcohol'],
            },
        ],
      ),
      _day,
    );
    final by = {for (final b in got.data.behaviors) b.kind: b};
    expect(by[BehaviorKind.highStrain]!.impact, 30);
    expect(by[BehaviorKind.sleepPerformance]!.title, '75%+ Sleep Performance');
    expect(by[BehaviorKind.sleepPerformance]!.impact, 30);
    // A lag-1 tag lands on the morning after: odd-back days point at even ones.
    final tag = got.data.behaviors
        .firstWhere((b) => b.kind == BehaviorKind.journalTag);
    expect(tag.title, 'Alcohol');
    expect(tag.impact, 30);
    // One night of bed times is not a comparison.
    expect(by[BehaviorKind.consistentBed]!.impact, isNull);
    // Nothing for the app to see, nothing fabricated.
    expect(by.containsKey(BehaviorKind.highStress), isFalse);
  });
}
