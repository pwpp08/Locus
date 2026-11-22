// The Android widget faces: every face draws, with or without a figure, and
// the sleep score is read the way Home's dial reads it.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/payloads.dart';
import 'package:openstrap_edge/ui2/theme.dart' show C;
import 'package:openstrap_edge/widget/widget_faces.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const full = FaceData(
    sleep: FaceRing(value: '61', suffix: '%', frac: .61, color: C.dialSleep),
    recovery: FaceRing(value: '47', suffix: '%', frac: .47, color: C.recYellow),
    strain: FaceRing(value: '6.6', frac: 6.6 / 21, color: C.dialStrain),
    hrv: 58,
    calories: 1214,
    batteryPct: 76,
  );
  const bare = FaceData(
    sleep: FaceRing(
        value: 'No score', numeric: false, color: kFaceMuted),
    recovery: FaceRing(
        value: 'Calibrating', numeric: false, frac: .4, color: kFaceMuted),
    strain: FaceRing(value: 'No strain', numeric: false, color: kFaceMuted),
  );

  for (final (name, data) in [('with figures', full), ('without', bare)]) {
    testWidgets('every face draws $name', (t) async {
      await t.runAsync(() async {
        for (final f in WidgetFace.values) {
          final png = await WidgetFaces.png(f, data);
          expect(png, isNotNull, reason: f.name);
          // The PNG signature, and a picture 3x the face's logical size.
          expect(png!.sublist(1, 4), [0x50, 0x4E, 0x47], reason: f.name);
        }
      });
    });
  }

  test('the sleep score is the coach performance envelope, or null', () {
    TodayData of(Map<String, dynamic>? coach) => TodayData.fromJson({
          'daily': const {},
          'sleep': const {},
          'coach': ?coach,
        });
    expect(
        of({
          'performance': {
            'value': {'pct': 61.4}
          }
        }).sleepPerformancePct,
        61.4);
    expect(of(null).sleepPerformancePct, isNull);
    expect(of({'performance': {'value': '—'}}).sleepPerformancePct, isNull);
  });
}
