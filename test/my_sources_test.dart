// My sources shows the connected band's numbers on the list itself, with no
// quality ladder, and the band's own page no longer carries a live heart rate,
// a charge-history line or the calibration essay.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/battery_forecast.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

final _band = HealthSource(
  name: 'WHOOP 4.0',
  kind: 'WHOOP 4 · wrist optical',
  tier: SourceTier.wristOptical,
  icon: LucideIcons.watch,
  connected: true,
  batteryPct: 67,
  lastData: DateTime(2026, 8, 22, 7, 12),
  family: 'gen4',
  isBand: true,
);

BatteryForecast get _threeDays => BatteryForecast(
      samplesUsed: 12,
      spanUsed: const Duration(hours: 20),
      predictedEmptyAt: DateTime.now().add(const Duration(hours: 71, minutes: 30)),
    );

void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: w));
    await t.pumpAndSettle();
  }

  testWidgets('the list shows the band battery, days left and last data '
      'without opening the band', (t) async {
    await pump(t, MyDevicesView(sources: [_band], bandForecast: _threeDays));
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('about 3 days left'), findsOneWidget);
    expect(find.text('Last data'), findsOneWidget);
    expect(find.text('Calibration'), findsOneWidget);
    expect(find.text('WHOOP 4'), findsOneWidget);
  });

  testWidgets('the quality ladder is gone from the list', (t) async {
    await pump(t, MyDevicesView(sources: [_band], bandForecast: _threeDays));
    expect(find.textContaining('QUALITY LADDER'), findsNothing);
    expect(find.textContaining('Nothing here yet'), findsNothing);
  });

  testWidgets('no band, no stats card', (t) async {
    await pump(t, const MyDevicesView());
    expect(find.text('Battery'), findsNothing);
  });

  testWidgets('the band page: battery says only the days left, no heart '
      'rate row, no calibration explanation', (t) async {
    await pump(t, DeviceDetailView(_band, forecast: _threeDays));
    expect(find.text('about 3 days left'), findsOneWidget);
    expect(find.textContaining('charges logged'), findsNothing);
    expect(find.text('Heart rate'), findsNothing);
    expect(find.text('Right now'), findsNothing);
    expect(find.text('Calibration'), findsOneWidget);
    expect(find.textContaining('own constants'), findsNothing);
  });
}
