import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';

void main() {
  final now = DateTime(2026, 10, 31, 23, 0, 30);
  test('hours and minutes, rounded up to the minute', () {
    expect(alarmCountdownText(DateTime(2026, 11, 1, 6, 30), now),
        'Rings in 7 h 30 min');
    expect(alarmCountdownText(DateTime(2026, 11, 1, 7, 0, 30), now),
        'Rings in 8 h');
    expect(alarmCountdownText(now.add(const Duration(seconds: 20)), now),
        'Rings in 1 min');
    expect(alarmCountdownText(now, now), 'Ringing now');
  });
}
