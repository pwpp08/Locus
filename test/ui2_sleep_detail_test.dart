// The Sleep dial's screen: what it says with data, and what it refuses to say
// without it. This pumps the whole page into a tall viewport, so a RenderFlex
// overflow anywhere below the fold fails the pump.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/sleep_stress.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart' show DeviceFilter;
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

const _day = '2026-05-20';
final _onset = DateTime(2026, 5, 19, 23, 7).millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _night() => {
      'duration_min': 370,
      'awake_min': 55,
      'efficiency': .89,
      'onset_ts': _onset,
      'wake_ts': _onset + 425 * 60,
      'light_min': 155,
      'deep_min': 108,
      'rem_min': 107,
      'hypnogram': [
        {'t': _onset, 'stage': 'light'},
        {'t': _onset + 3600, 'stage': 'awake'},
        {'t': _onset + 3900, 'stage': 'deep'},
        {'t': _onset + 7200, 'stage': 'awake'},
        {'t': _onset + 7500, 'stage': 'rem'},
        {'t': _onset + 425 * 60, 'stage': 'awake'},
      ],
    };

Future<void> _pump(WidgetTester t, SleepData d, {double scale = 1}) async {
  t.view.physicalSize = Size(390 * 3, 5200 * 3 * scale);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<ThemeController>(
    // The routes this screen opens (the window editor) read the theme.
    create: (_) => ThemeController.seed(AppThemeChoice.light, Brightness.light),
    child: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: SleepDetail(data: d),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

SleepData _full() => SleepData(
      day: _day,
      night: _night(),
      tstHistory: const [439, 439, 439],
      performance: 72,
      consistency: 85,
      lastNeedMin: 650,
      stress: {
        _day: SleepStress(
          pct: 1,
          scored: 100,
          high: 1,
          nights: 10,
          low: 80,
          medium: 19,
          curve: [for (var i = 0; i < 545; i++) i % 3 * .5],
          curveLead: 60,
        ),
      },
      vitals: SleepVitals(
        week: [for (var i = 6; i >= 0; i--) shiftDay(_day, -i)],
        perf: {_day: 72, shiftDay(_day, -1): 80},
        tst: {_day: 370},
        need: {_day: 650},
        hvn: {_day: 57},
        deep: {_day: 108},
        rem: {_day: 107},
        consistency: {_day: 85},
        eff: {_day: 89},
        debt: {_day: 148},
        spans: {_day: (bed: 667, wake: 1093)},
        needParts: const NeedParts(491, 32, 127, 0),
        streak: 7,
      ),
    );

void main() {
  testWidgets('today before any sleep says none is recorded, and scores nothing',
      (t) async {
    await _pump(
      t,
      const SleepData(day: _day, night: {'has_sleep': false, 'in_progress': true}),
    );
    expect(find.text('No sleep recorded'), findsOneWidget);
    expect(find.text('SET ONE MANUALLY'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('the ring, its contributors and each section read the night',
      (t) async {
    await _pump(t, _full());
    expect(find.text('72'), findsOneWidget);
    expect(find.text('SLEEP\nPERFORMANCE'), findsOneWidget);
    expect(find.text('HOURS VS. NEEDED'), findsWidgets);
    expect(find.text('SLEEP CONSISTENCY'), findsWidgets);
    expect(find.text('HIGH SLEEP STRESS'), findsOneWidget);
    expect(find.text('6:10'), findsWidgets);
    expect(find.text('SWS (DEEP)'), findsOneWidget);
    expect(find.text('10:50'), findsOneWidget);
    expect(find.text('+2:07'), findsOneWidget);
    expect(find.text('Weekly Trends'), findsOneWidget);
    // Never another wearable's words or name.
    expect(find.textContaining('WHOOP'), findsNothing);
  });

  testWidgets('with nothing stored, a figure is -- and has no triangle',
      (t) async {
    await _pump(t, SleepData(day: _day, night: _night()));
    expect(find.text('--'), findsWidgets);
    expect(find.byType(DeltaTriangle), findsNothing);
  });

  testWidgets('a low bar for a stage, not a made-up one, when the band has no REM',
      (t) async {
    final n = _night()..['rem_min'] = null;
    await _pump(t, SleepData(day: _day, night: n));
    expect(find.text('REM'), findsOneWidget);
    // The row stays and says it has nothing, rather than a REM of 0:00.
    expect(find.text('0:00'), findsNothing);
  });

  test('an unobserved stretch is not a stage', () {
    final runs = stageRunsOf({
      ..._night(),
      'hypnogram': [
        {'t': _onset, 'stage': 'unobserved'},
        {'t': _onset + 212 * 60, 'stage': 'deep'},
        {'t': _onset + 425 * 60, 'stage': 'awake'},
      ],
    });
    expect(runs.length, 1);
    expect(runs.single.stage, SleepStage.deep);
    expect(runs.single.from, closeTo(.5, .01));
    expect(stageRunsOf(const {}), isEmpty);
  });

  group('sleep latency', () {
    testWidgets('an auto window never claims one', (t) async {
      await _pump(t, SleepData(day: _day, night: _night(), solMin: 37));
      expect(find.text('0:37'), findsNothing);
    });

    testWidgets('a window you set yourself shows it', (t) async {
      await _pump(
          t,
          SleepData(
              day: _day,
              night: {..._night(), 'sleep_source': 'manual'},
              solMin: 37));
      expect(find.text('0:37'), findsOneWidget);
    });
  });

  testWidgets('picking a stage marks it and picking it again clears it',
      (t) async {
    await _pump(t, _full());
    Finder stageBars() => find.byWidgetPredicate((w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == '_StageBarPaint');
    expect(stageBars(), findsWidgets);
    await t.tap(find.text('LIGHT'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('LIGHT'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('EDIT opens the window sheet, with no other brand in it',
      (t) async {
    await _pump(t, _full());
    await t.tap(find.text('EDIT'));
    await t.pumpAndSettle();
    expect(find.text('EDIT TIME IN BED'), findsOneWidget);
    expect(find.text('Bed Time'), findsOneWidget);
    expect(find.text('Wake Time'), findsOneWidget);
    expect(find.text('Where did you wear your band?'), findsOneWidget);
    expect(find.text('SAVE'), findsOneWidget);
    expect(find.text('DELETE SLEEP'), findsOneWidget);
  });

  group('a device\'s own staging, beside ours', () {
    Map<String, Object?> deviceNight(
            String id, String label, Map<String, int> minutes) =>
        {
          'device_id': id,
          'label': label,
          'onset_ts': _onset,
          'wake_ts': _onset + 480 * 60,
          'duration_min': 460,
          'stage_min': minutes,
          'hypnogram': [
            {'t': _onset, 'stage': 'light'},
            {'t': _onset + 3600, 'stage': 'deep'},
            {'t': _onset + 480 * 60, 'stage': 'deep'},
          ],
        };

    testWidgets('a switcher offers Locus and each device; picking one says whose '
        'staging it is and what it cannot report', (t) async {
      await _pump(
        t,
        SleepData(day: _day, night: _night(), deviceNights: [
          deviceNight('mb-1', 'Mi Band', {'light': 400, 'deep': 60, 'wake': 20}),
          deviceNight('cm-1', 'Colmi ring',
              {'light': 250, 'deep': 100, 'rem': 110, 'wake': 20}),
        ]),
      );
      expect(_sw('LOCUS'), findsOneWidget);
      expect(_sw('MI BAND'), findsOneWidget);
      expect(_sw('COLMI RING'), findsOneWidget);
      expect(find.textContaining('Staged by'), findsNothing);

      await t.tap(_sw('MI BAND'));
      await t.pumpAndSettle();
      expect(find.textContaining('Staged by Mi Band'), findsOneWidget);
      expect(find.textContaining('does not report REM'), findsOneWidget);

      await t.ensureVisible(_sw('COLMI RING'));
      await t.pumpAndSettle();
      await t.tap(_sw('COLMI RING'));
      await t.pumpAndSettle();
      expect(find.textContaining('Staged by Colmi ring'), findsOneWidget);
      expect(find.textContaining('does not report'), findsNothing);
    });

    testWidgets('no device night means no switcher', (t) async {
      await _pump(t, SleepData(day: _day, night: _night()));
      expect(_sw('LOCUS'), findsNothing);
    });
  });

  for (final scale in const [2.0, 3.1]) {
    testWidgets('every section survives ${scale}x text', (t) async {
      await _pump(t, _full(), scale: scale);
      expect(t.takeException(), isNull);
      expect(find.text('Weekly Trends'), findsOneWidget);
    });
  }

  group('correctedSleepWindow', () {
    test('a bedtime moved past midnight stays on the same night', () {
      final (on, off) = correctedSleepWindow(
        DateTime(2026, 3, 1, 23, 50),
        DateTime(2026, 3, 2, 7, 0),
        const TimeOfDay(hour: 0, minute: 20),
        const TimeOfDay(hour: 7, minute: 10),
      );
      expect(on, DateTime(2026, 3, 2, 0, 20));
      expect(off, DateTime(2026, 3, 2, 7, 10));
    });

    test('a bedtime moved back before midnight stays on the same night', () {
      final (on, off) = correctedSleepWindow(
        DateTime(2026, 3, 2, 0, 30),
        DateTime(2026, 3, 2, 7, 0),
        const TimeOfDay(hour: 23, minute: 40),
        const TimeOfDay(hour: 7, minute: 0),
      );
      expect(on, DateTime(2026, 3, 1, 23, 40));
      expect(off, DateTime(2026, 3, 2, 7, 0));
    });

    test('an ordinary correction only moves the clock', () {
      final (on, off) = correctedSleepWindow(
        DateTime(2026, 3, 1, 23, 7),
        DateTime(2026, 3, 2, 7, 5),
        const TimeOfDay(hour: 22, minute: 45),
        const TimeOfDay(hour: 6, minute: 30),
      );
      expect(on, DateTime(2026, 3, 1, 22, 45));
      expect(off, DateTime(2026, 3, 2, 6, 30));
    });

    test('a wake moved far later on a truncated night lands the same day', () {
      final (on, off) = correctedSleepWindow(
        DateTime(2026, 3, 2, 0, 30),
        DateTime(2026, 3, 2, 1, 0),
        const TimeOfDay(hour: 0, minute: 30),
        const TimeOfDay(hour: 13, minute: 30),
      );
      expect(on, DateTime(2026, 3, 2, 0, 30));
      expect(off, DateTime(2026, 3, 2, 13, 30));
    });
  });

  testWidgets('a night with nothing found is set by hand on the heart rate',
      (t) async {
    await _pump(t, const SleepData(day: _day));
    expect(find.text('No sleep recorded'), findsOneWidget);
    final b = find.text('SET ONE MANUALLY');
    expect(b, findsOneWidget);
    await t.tap(b);
    await t.pumpAndSettle();
    // The window editor: the heart rate chart, two times, and save.
    expect(find.byType(WindowEditor), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('END'), findsOneWidget);
    expect(find.text('SAVE SLEEP'), findsOneWidget);
  });

  testWidgets('a night marked not sleep is set by hand the same way', (t) async {
    await _pump(
        t, const SleepData(day: _day, night: {'sleep_source': 'rejected'}));
    expect(find.text('No sleep recorded'), findsOneWidget);
    expect(find.text('Marked as not sleep'), findsNothing);
    expect(find.text('SET ONE MANUALLY'), findsOneWidget);
  });
}

/// A pill of the device switcher, by the label it draws (uppercased).
Finder _sw(String label) =>
    find.descendant(of: find.byType(DeviceFilter), matching: find.text(label));
