import 'package:openstrap_edge/compute/derive_scheduler.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart' show deriveStatusText;
import 'package:flutter_test/flutter_test.dart';

DeriveStatus _s({
  DeriveJobKind? running,
  bool light = false,
  bool heavy = false,
  DeriveHold hold = DeriveHold.none,
  (String, int, int)? progress,
}) =>
    (
      running: running,
      pendingLight: light,
      pendingHeavy: heavy,
      hold: hold,
      progress: progress,
    );

void main() {
  String day(String d) => 'day $d';

  test('nothing queued says nothing', () {
    expect(deriveStatusText(_s(), day), isNull);
  });

  test('a running pass names what and how far', () {
    expect(
        deriveStatusText(
            _s(running: DeriveJobKind.heavy, progress: ('2026-11-04', 2, 5)),
            day),
        ('Calculating sleep, recovery and strain',
            'day 2026-11-04 done, 2 of 5 days'));
    expect(deriveStatusText(_s(running: DeriveJobKind.light), day)!.$1,
        'Updating the latest day');
  });

  test('queued work says what holds it', () {
    expect(
        deriveStatusText(_s(heavy: true, hold: DeriveHold.capture), day),
        ('Calculation queued',
            'Sleep, recovery and strain, once the band has finished sending'));
    expect(deriveStatusText(_s(light: true, hold: DeriveHold.workout), day)!.$2,
        endsWith('when your workout ends'));
  });
}
