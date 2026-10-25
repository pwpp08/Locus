// The Stress Monitor screen: what it reads out, what it says when it cannot,
// and that a finger on the chart moves the gauge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/ui2/screens/stress_monitor.dart';
import 'package:openstrap_edge/ui2/screens/trend_view.dart' show shiftDay;
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

const today = '2026-05-22';

/// Fifteen believable days: calm mornings, a workout at five, a noisy
/// afternoon today, and a night either side.
class _Repo extends LocalRepository {
  final int days;
  _Repo({this.days = 15});

  int _ts(String day, int h, int m) {
    final d = DateTime.parse(day);
    return DateTime(d.year, d.month, d.day, h, m).millisecondsSinceEpoch ~/ 1000;
  }

  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) async {
    final ago = DateTime.parse(today).difference(DateTime.parse(date)).inDays;
    if (ago < 0 || ago >= days) return const {};
    final hr = <Map<String, num>>[], hrv = <Map<String, num>>[], act = <Map<String, num>>[];
    final end = date == today ? 22 * 60 + 41 : 23 * 60;
    for (var m = 0; m <= end; m++) {
      final asleep = m < 6 * 60 + 30;
      final workout = m >= 17 * 60 && m < 18 * 60;
      final rough = date == today && m >= 13 * 60 && m < 14 * 60 + 30;
      final h = asleep ? 52 : workout ? 128 : rough ? 84 : 64 + (m % 7);
      final v = asleep ? 95 : workout ? 30 : rough ? 38 : 70 - (m % 5);
      final t = _ts(date, m ~/ 60, m % 60);
      hr.add({'t': t, 'v': h});
      hrv.add({'t': t, 'v': v});
      if (m % 5 == 0) act.add({'t': t, 'v': workout ? .6 : asleep ? 0 : .02});
    }
    return {
      'date': date,
      'hr': hr,
      'hrv': hrv,
      'activity': act,
      'sleep': [
        {'onset_ts': _ts(shiftDay(date, -1), 23, 0), 'wake_ts': _ts(date, 6, 30)},
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getSessions(
          {int? from, int? to, bool includeDetected = true}) async =>
      [
        {
          'start_ts': from! + 17 * 3600,
          'end_ts': from + 18 * 3600,
          'type': 'Cycling',
        },
      ];
}

Future<void> _show(WidgetTester t, LocalRepository repo) async {
  t.view.physicalSize = const Size(390 * 3, 2200 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: StressMonitorScreen(source: StressSource(repo), today: today),
  ));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppFonts();
  });

  testWidgets('the day is read out, scored, and compared with a typical one',
      (t) async {
    await _show(t, _Repo());
    expect(find.text('STRESS MONITOR'), findsOneWidget);
    expect(find.text('FRI, MAY 22'), findsOneWidget);
    // The last reading of the day is the evening, at rest: low.
    expect(find.text('22:41'), findsWidgets);
    expect(find.text('LOW'), findsWidgets);
    expect(find.text('TOTAL DAY'), findsOneWidget);
    expect(find.textContaining('VS. TYPICAL DAY'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a finger on the afternoon moves the gauge to that minute',
      (t) async {
    await _show(t, _Repo());
    final box = t.getRect(find.byType(ScrubLine));
    // The plot runs 00:00 to 22:41; 13:45 is 60.6 % of the way along it.
    const gutter = S.x10, right = S.x2;
    final x = box.left + gutter + (box.width - gutter - right) * (13 * 60 + 45) / (22 * 60 + 41);
    final g = await t.startGesture(Offset(x, box.center.dy));
    await t.pump();
    expect(find.text('13:45'), findsWidgets);
    await g.up();
    await t.pump();
    expect(find.text('22:41'), findsWidgets);
  });

  testWidgets('sleep and the workout are each marked by their own icon',
      (t) async {
    await _show(t, _Repo());
    // The night is the shaded stretch at the start of the day; the cycling
    // session is the one at five. Each has its icon over the middle of it.
    expect(find.byIcon(LucideIcons.moon), findsOneWidget);
    expect(find.byIcon(LucideIcons.bike), findsOneWidget);
  });

  testWidgets('with too little history it says it is building a baseline',
      (t) async {
    await _show(t, _Repo(days: 2));
    expect(find.text('Building your baseline'), findsOneWidget);
    expect(find.text('TOTAL DAY'), findsNothing);
    expect(find.text('--'), findsWidgets);
  });

  testWidgets('paging back a day loads that day', (t) async {
    await _show(t, _Repo());
    // The nav bar has its own back chevron; the pager's is the second.
    await t.tap(find.byIcon(LucideIcons.chevronLeft).last);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('THU, MAY 21'), findsOneWidget);
    expect(find.text('TOTAL DAY'), findsOneWidget);
    expect(dayLabelOf(DateTime(2026, 5, 21)), '2026-05-21');
  });
}
