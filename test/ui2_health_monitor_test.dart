// Health Monitor: the heart rate and the five vitals.
//
// Pins the honesty rules the redesign must keep: a verdict pill only ever
// states the user's own range numbers, a reading far out on the harmful side
// takes the warning colour, an absent vital says "No data", and the hero shows
// the live beat, else the day's last recorded heart rate with its time, else a
// dash. It also pins that the beat only runs while there is one to follow and
// motion is allowed.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:openstrap_edge/compute/whoop_scores.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/health_monitor.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// Twenty nights of history, then tonight's reading last.
List<double> _nights(double mid, double spread, double tonight) => [
      for (var i = 0; i < 20; i++) mid + spread * ((i * 7 % 11) / 5 - 1),
      tonight,
    ];

Map<String, dynamic> _chart(List<double> vs) {
  final now = DateTime.now();
  return {
    'points': [
      for (var i = 0; i < vs.length; i++)
        {
          't': DateTime(now.year, now.month, now.day - (vs.length - 1 - i))
                  .millisecondsSinceEpoch ~/
              1000,
          'v': vs[i],
        },
    ],
  };
}

final _resp = _nights(16.5, .5, 16.6);
final _rhr = _nights(52, 3, 70);
final _hrv = _nights(72, 9, 95);

class _Repo extends LocalRepository {
  final bool empty;
  _Repo({this.empty = false});

  @override
  Future<Map<String, dynamic>> getToday() async => empty
      ? {'status': {'today_day': todayLabel()}}
      : {
          'daily': {
            'resting_hr': {'value': 70, 'confidence': .8, 'tier': 'HIGH'},
          },
          'hrv': {'rmssd': 95, 'confidence': .8, 'tier': 'HIGH'},
          'resp': {'value': 16.6, 'confidence': .8, 'tier': 'HIGH'},
          'status': {'today_day': todayLabel()},
        };

  @override
  Future<Map<String, dynamic>> getDayHeart(String date) async => empty
      ? const {}
      : {
          'hr': [
            {'t': DateTime(2020, 1, 1, 7, 42).millisecondsSinceEpoch ~/ 1000, 'v': 64},
          ],
        };

  @override
  Future<Map<String, dynamic>> getChart(String metric,
          {int? from, int? to, Set<String> signals = const {}}) async =>
      switch (metric) {
        'resp_rate' => _chart(_resp),
        'resting_hr' => _chart(_rhr),
        'hrv' => _chart(_hrv),
        _ => const {},
      };
}

/// A gen5 night: skin temperature shown in °C, its range held in SD.
class _SkinRepo extends _Repo {
  @override
  Future<Map<String, dynamic>> getToday() async => {
        ...await super.getToday(),
        'skin_temp': {
          'value': .2, 'dev_c': .5, 'confidence': .8, 'tier': 'RELATIVE',
        },
      };

  @override
  Future<Map<String, dynamic>> getChart(String metric,
          {int? from, int? to, Set<String> signals = const {}}) async =>
      metric == 'skin_temp'
          ? _chart(_nights(0, .8, .2))
          : super.getChart(metric, from: from, to: to, signals: signals);
}

String _range(List<double> s, {required bool up, int places = 0}) {
  final r = whoopMonitorReading(s.last, s.sublist(0, s.length - 1), harmfulUp: up)!;
  String n(double x) => x.toStringAsFixed(places);
  return s.last > r.hi
      ? 'elevated > ${n(r.hi)}'
      : s.last < r.lo
          ? 'low < ${n(r.lo)}'
          : 'within ${n(r.lo)} - ${n(r.hi)}';
}

Future<void> _pump(WidgetTester t, AppState app, {bool still = false}) async {
  t.view.physicalSize = const Size(393, 852);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(size: const Size(393, 852), disableAnimations: still),
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: ChangeNotifierProvider<AppState>.value(
          value: app, child: const HealthMonitorScreen()),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump(const Duration(milliseconds: 16));
  }
}

Color? _inkOf(WidgetTester t, String text) =>
    t.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('each pill states the user\'s own range; far out is a warning',
      (t) async {
    final app = AppState.forTesting()..repo = _Repo();
    addTearDown(app.dispose);
    await _pump(t, app);

    final resp = _range(_resp, up: true, places: 1);
    final rhr = _range(_rhr, up: true);
    final hrv = _range(_hrv, up: false);
    expect(find.text(resp), findsOneWidget);
    expect(find.text(rhr), findsOneWidget);
    expect(find.text(hrv), findsOneWidget);
    // RHR 70 against ~52: far out on the harmful side → the warning colour.
    expect(_inkOf(t, rhr), C.poor);
    // HRV up is not the harmful side: green, however high.
    expect(_inkOf(t, hrv), HM.within);
    // No skin reading and no ring's blood oxygen: no number, no range.
    expect(find.text('No data'), findsNWidgets(2));
  });

  testWidgets('a °C skin reading never shows its SD range', (t) async {
    final app = AppState.forTesting()..repo = _SkinRepo();
    addTearDown(app.dispose);
    await _pump(t, app);

    expect(find.text('+0.5'), findsOneWidget);
    expect(find.text('°C'), findsOneWidget);
    expect(find.text('within usual range'), findsOneWidget);
    expect(find.textContaining('SD'), findsNothing);
  });

  testWidgets('no live beat: the last recorded rate, labelled, and a still heart',
      (t) async {
    final app = AppState.forTesting()..repo = _Repo();
    addTearDown(app.dispose);
    await _pump(t, app);

    expect(find.text('64'), findsOneWidget);
    expect(find.textContaining('Last recorded'), findsOneWidget);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('nothing recorded: a dash and five tiles of No data', (t) async {
    final app = AppState.forTesting()..repo = _Repo(empty: true);
    addTearDown(app.dispose);
    await _pump(t, app);

    expect(find.text('--'), findsNWidgets(6));
    expect(find.text('No data'), findsNWidgets(5));
    expect(find.textContaining('Last recorded'), findsNothing);
  });

  testWidgets('a live beat is shown and beats; reduced motion holds it still',
      (t) async {
    AppState live() => AppState.forTesting()
      ..repo = _Repo()
      ..device.connection = 'connected'
      ..device.liveHr = 75
      ..device.liveHrAt = DateTime.now().millisecondsSinceEpoch;

    final app = live();
    addTearDown(app.dispose);
    await _pump(t, app);
    expect(find.text('75'), findsOneWidget);
    expect(find.textContaining('Last recorded'), findsNothing);
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
    await t.pumpWidget(const SizedBox());

    final still = live();
    addTearDown(still.dispose);
    await _pump(t, still, still: true);
    expect(find.text('75'), findsOneWidget);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    await t.pumpWidget(const SizedBox());
  });
}
