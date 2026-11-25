// The debounced HR-zone-crossing alert behind the opt-in live-workout
// haptic. Pure logic only — [ZoneCrossingAlert] never touches the band; the
// wiring that turns a `true` return into `engine.buzz()` lives in
// AppState._tickWorkout and is not re-tested here.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/zone_alert.dart';

void main() {
  zoneLimitTests();
  final t0 = DateTime(2026, 9, 18, 7, 0);
  DateTime at(int sec) => t0.add(Duration(seconds: sec));

  group('baseline', () {
    test('the first tick never fires — nothing has been crossed yet', () {
      final a = ZoneCrossingAlert(targetZone: 3);
      expect(a.onTick(at(0), 3), isFalse);
      expect(a.onTick(at(0), 0), isFalse);
    });
  });

  group('crossing into the target zone', () {
    test('fires once the other side has held for the full debounce', () {
      final a = ZoneCrossingAlert(targetZone: 3);
      expect(a.onTick(at(0), 2), isFalse); // baseline: outside
      expect(a.onTick(at(1), 3), isFalse); // stepped in, clock starts
      expect(a.onTick(at(5), 3), isFalse); // 4s held < 5s debounce
      expect(a.onTick(at(6), 3), isTrue); // held 5s — crossing confirmed
    });

    test('does not fire again while it stays inside', () {
      final a = ZoneCrossingAlert(targetZone: 3);
      a.onTick(at(0), 2);
      a.onTick(at(1), 3);
      expect(a.onTick(at(6), 3), isTrue);
      expect(a.onTick(at(7), 3), isFalse);
      expect(a.onTick(at(30), 3), isFalse);
    });
  });

  group('crossing out of the target zone', () {
    test('fires the same way in the other direction', () {
      final a = ZoneCrossingAlert(targetZone: 3);
      expect(a.onTick(at(0), 3), isFalse); // baseline: inside
      expect(a.onTick(at(1), 4), isFalse); // stepped out
      expect(a.onTick(at(5), 4), isFalse);
      expect(a.onTick(at(6), 4), isTrue);
    });
  });

  group('boundary jitter never fires', () {
    test('a blip back to the confirmed side cancels the pending crossing',
        () {
      final a = ZoneCrossingAlert(targetZone: 3);
      a.onTick(at(0), 3); // baseline: inside
      a.onTick(at(1), 2); // steps out, clock starts
      expect(a.onTick(at(3), 3), isFalse, // one noisy sample back inside
          reason: 'back on the confirmed side — nothing has crossed yet');
      // The debounce clock restarts from scratch on the NEXT step out.
      expect(a.onTick(at(4), 2), isFalse);
      expect(a.onTick(at(8), 2), isFalse, reason: 'only 4s since re-stepping out');
      expect(a.onTick(at(9), 2), isTrue);
    });

    test('a single tick that flickers zone by zone but stays outside the '
        'target never fires', () {
      final a = ZoneCrossingAlert(targetZone: 3);
      a.onTick(at(0), 3); // baseline: inside
      // Zone 2 then zone 1 — both "outside", counts as the SAME pending side.
      a.onTick(at(1), 2);
      expect(a.onTick(at(5), 1), isFalse);
      expect(a.onTick(at(6), 1), isTrue);
    });
  });

  group('repeated crossings', () {
    test('fires again on a later, independent crossing', () {
      final a = ZoneCrossingAlert(targetZone: 3);
      a.onTick(at(0), 2);
      a.onTick(at(1), 3);
      expect(a.onTick(at(6), 3), isTrue); // crossed in
      a.onTick(at(7), 2);
      expect(a.onTick(at(11), 2), isFalse); // 4s, not yet
      expect(a.onTick(at(12), 2), isTrue); // crossed out
      a.onTick(at(13), 3);
      expect(a.onTick(at(17), 3), isFalse);
      expect(a.onTick(at(18), 3), isTrue); // crossed in again
    });
  });

  group('zone 0 (no reading billed as rest)', () {
    test('is just another non-target zone, no special case', () {
      final a = ZoneCrossingAlert(targetZone: 3);
      a.onTick(at(0), 3);
      a.onTick(at(1), 0);
      expect(a.onTick(at(6), 0), isTrue);
    });
  });
}

/// The per-workout ceiling: buzz above it, repeat while above, silent below.
void zoneLimitTests() {
  final t0 = DateTime(2026, 9, 18, 7, 0);
  DateTime at(int sec) => t0.add(Duration(seconds: sec));

  group('ZoneLimitAlert', () {
    test('inside the limit never buzzes, however long', () {
      final a = ZoneLimitAlert(limitZone: 3);
      for (var s = 0; s < 120; s++) {
        expect(a.onTick(at(s), 3), isFalse);
      }
    });

    test('above it buzzes once the debounce has held, then every 30 seconds', () {
      final a = ZoneLimitAlert(limitZone: 3);
      expect(a.onTick(at(0), 4), isFalse);
      expect(a.onTick(at(4), 4), isFalse);
      expect(a.onTick(at(5), 4), isTrue);
      expect(a.onTick(at(20), 4), isFalse);
      expect(a.onTick(at(35), 4), isTrue);
      expect(a.onTick(at(60), 4), isFalse);
      expect(a.onTick(at(65), 4), isTrue);
    });

    test('a blip above for under the debounce says nothing', () {
      final a = ZoneLimitAlert(limitZone: 3);
      expect(a.onTick(at(0), 4), isFalse);
      expect(a.onTick(at(3), 3), isFalse);
      expect(a.onTick(at(4), 4), isFalse);
      expect(a.onTick(at(8), 4), isFalse);
    });

    test('coming back down is silent, and going above again buzzes anew', () {
      final a = ZoneLimitAlert(limitZone: 2);
      a.onTick(at(0), 3);
      expect(a.onTick(at(5), 3), isTrue);
      expect(a.onTick(at(10), 2), isFalse);
      a.onTick(at(11), 3);
      expect(a.onTick(at(16), 3), isTrue);
    });

    test('zone 0 (no zones set) is never above anything', () {
      final a = ZoneLimitAlert(limitZone: 1);
      for (var s = 0; s < 60; s++) {
        expect(a.onTick(at(s), 0), isFalse);
      }
    });

    test('a stored limit reads back, and nonsense is none', () {
      expect(ZoneLimitAlert.parse('3'), 3);
      expect(ZoneLimitAlert.parse(''), isNull);
      expect(ZoneLimitAlert.parse('5'), isNull);
      expect(ZoneLimitAlert.parse('x'), isNull);
    });
  });
}
