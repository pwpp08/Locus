// The four-tab layout: what moved where, and the pieces that came with it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart'
    show quietHrrMinDays, readinessCompositeMinBaseline;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'package:openstrap_edge/ui2/screens/calibration.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Widget _app(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the milestones name the gates the pipeline uses', () {
    final m = {
      for (final x in Calibration.of(days: 2).milestones) x.title: x,
    };
    // Strain needs this many earlier days with a resting level, so it is
    // one past them; recovery this many nights of baseline.
    expect(m['Strain']!.need, quietHrrMinDays + 1);
    expect(m['Strain']!.toUnlock,
        'Wear the band ${quietHrrMinDays + 1} days to unlock');
    expect(m['Recovery']!.need, readinessCompositeMinBaseline);
    expect(m['Recovery']!.toUnlock,
        'Log $readinessCompositeMinBaseline sleeps to unlock');
    expect(m['Sleep']!.done, isTrue);
    expect(m['Recovery']!.done, isFalse);
  });

  test('cycle tracking defaults on for a female profile, and a choice wins',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    expect(app.cycleTrackingEnabled, isFalse);
    app.user = {'sex': 'f'};
    expect(app.cycleTrackingEnabled, isTrue);
    await app.setCycleTrackingEnabled(false);
    expect(app.cycleTrackingEnabled, isFalse);
  });

  testWidgets('a provider-free avatar still clears the tap floor', (t) async {
    await t.pumpWidget(_app(const Center(child: ProfileAvatar())));
    final size = t.getSize(find.byType(Pressable));
    expect(size.width, greaterThanOrEqualTo(S.tap));
    expect(size.height, greaterThanOrEqualTo(S.tap));
    expect(find.bySemanticsLabel('Profile and settings'), findsOneWidget);
  });

  testWidgets('the avatar shows an initial when a name is known', (t) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.user = {'name': 'sam'};
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app, child: _app(const Center(child: ProfileAvatar()))));
    expect(find.text('S'), findsOneWidget);
  });
}
