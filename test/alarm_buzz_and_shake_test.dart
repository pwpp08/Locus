import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_edge/models/alarm_item.dart';
import 'package:openstrap_edge/state/alarm_shake.dart';

void main() {
  group('AlarmBuzz', () {
    test('every custom pattern is a 12-byte rich-form body', () {
      for (final b in AlarmBuzz.values) {
        if (b == AlarmBuzz.standard) {
          expect(b.haptics, isNull);
        } else {
          expect(b.haptics, hasLength(12), reason: b.name);
          // Only the two effects the strap's own wake buzz uses.
          for (final e in b.haptics!.take(8)) {
            expect(e, isIn(const [0, 47, 152]), reason: b.name);
          }
        }
      }
    });

    test('round-trips through json; unknown/missing names are standard', () {
      const a = AlarmItem(id: 'x', hour: 6, minute: 30, buzz: AlarmBuzz.pulse);
      expect(AlarmItem.fromJson(a.toJson()).buzz, AlarmBuzz.pulse);
      expect(
          AlarmItem.fromJson({'id': 'y', 'hour': 7, 'minute': 0}).buzz,
          AlarmBuzz.standard);
      expect(AlarmBuzz.fromName('nope'), AlarmBuzz.standard);
    });
  });

  group('AlarmPayloads.setPayloadForBand on gen4', () {
    final when = DateTime.utc(2026, 10, 23, 6, 30);

    test('no haptics → the 9-byte rev-1 form, unchanged', () {
      expect(AlarmPayloads.setPayloadForBand(when, isGen5: false),
          AlarmPayloads.rev1(when));
    });

    test('custom haptics → the 20-byte rich form carrying them', () {
      final h = AlarmBuzz.insistent.haptics!;
      final p =
          AlarmPayloads.setPayloadForBand(when, isGen5: false, haptics: h);
      expect(p, hasLength(20));
      expect(p.first, 0x04);
      expect(p.sublist(8), h);
    });
  });

  group('AlarmShakeDetector', () {
    List<double> still(int n) => List.filled(n, 1.0);

    test('four sharp jolts inside two seconds is a shake', () {
      final d = AlarmShakeDetector();
      // One 100 Hz frame per 250 ms, each carrying one jolt.
      var fired = false;
      for (var i = 0; i < 4 && !fired; i++) {
        final f = still(25)..[10] = 3.0;
        fired = d.add(f, 1000 + i * 250);
      }
      expect(fired, isTrue);
    });

    test('a single long roll-over excursion is not a shake', () {
      final d = AlarmShakeDetector();
      // 600 ms continuously above threshold: one jolt, not many.
      expect(d.add(List.filled(60, 2.6), 1000), isFalse);
      expect(d.add(still(100), 2000), isFalse);
    });

    test('jolts spread over more than the window do not add up', () {
      final d = AlarmShakeDetector();
      var fired = false;
      for (var i = 0; i < 6; i++) {
        final f = still(10)..[5] = 3.0;
        fired = fired || d.add(f, 1000 + i * 1500);
      }
      expect(fired, isFalse);
    });

    test('the buzz itself (small vibration) is not a shake', () {
      final d = AlarmShakeDetector();
      final f = [for (var i = 0; i < 200; i++) i.isEven ? 1.3 : 0.7];
      expect(d.add(f, 5000), isFalse);
    });
  });

  test('alarm shake window owns the IMU stream', () {
    final i = desiredLiveStreams(
      const LiveStreamOwners(alarmShakeWatch: true),
      gen5: true,
      standardHrFallback: false,
    );
    expect(i.imu, isTrue);
    expect(i.hr, isFalse);
  });
}
