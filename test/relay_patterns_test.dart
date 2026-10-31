// Two moments buzz the strap in a pattern of their own, with no app picked: an
// incoming call (three long buzzes) and a Google Tasks reminder (two short).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/notify/notification_relay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<(int, bool)> beats;
  late int plain;
  late bool connected;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    beats = [];
    plain = 0;
    connected = true;
  });

  NotificationRelay relay() => NotificationRelay(
        buzz: () async => plain++,
        isConnected: () => connected,
        buzzBeats: (n, long) async => beats.add((n, long)),
      );

  const dialer = 'com.google.android.dialer';
  const tasks = 'com.google.android.apps.tasks';

  test('an incoming call is three long buzzes, once', () {
    final r = relay();
    r.handle(dialer);
    expect(beats, [(3, true)]);
    // The ongoing-call notification that replaces it a moment later.
    r.handle(dialer, onGoing: true);
    expect(beats, hasLength(1), reason: 'one buzz sequence per call');
    expect(plain, 0);
  });

  test('a call posted as an ongoing notification still buzzes', () {
    final r = relay();
    r.handle(dialer, onGoing: true);
    expect(beats, [(3, true)]);
  });

  test('a Google Tasks reminder is two short buzzes', () {
    final r = relay();
    r.handle(tasks);
    expect(beats, [(2, false)]);
  });

  test('an ongoing Google Tasks notification does not buzz', () {
    final r = relay();
    r.handle(tasks, onGoing: true);
    expect(beats, isEmpty);
  });

  test('nothing buzzes while the band is not connected', () {
    connected = false;
    final r = relay();
    r.handle(dialer);
    r.handle(tasks);
    expect(beats, isEmpty);
  });

  test('each pattern can be switched off on its own', () async {
    final r = relay();
    await r.setCallsEnabled(false);
    r.handle(dialer);
    r.handle(tasks);
    expect(beats, [(2, false)]);
    await r.setTasksEnabled(false);
    r.handle(tasks, onGoing: false);
    expect(beats, hasLength(1));
  });

  test('a removal never buzzes', () {
    final r = relay();
    r.handle(dialer, hasRemoved: true);
    expect(beats, isEmpty);
  });

  test('an app that is not picked still does not buzz', () {
    final r = relay();
    r.handle('com.example.chat');
    expect(beats, isEmpty);
    expect(plain, 0);
  });

  test('a picked app is the same single buzz it always was', () async {
    final r = relay();
    await r.setAppEnabled('com.example.chat', true);
    // `supported` is false off Android, so setAppEnabled is a no-op here:
    // arm it through the test seam the relay already has.
    r.packages.add('com.example.chat');
    r.handle('com.example.chat');
    expect(plain, 1);
    expect(beats, isEmpty);
  });
}
