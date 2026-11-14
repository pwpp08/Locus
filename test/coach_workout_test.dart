// The coach's workouts, reply chips and Answer again: the model's options are
// checked before they become cards, the strain on a card is the app's own
// (and absent without its anchors), and the replies line never shows as text.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_actions.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/coach/coach_engine.dart';
import 'package:openstrap_edge/coach/workout_plan.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bands = [
  (100.0, 120.0),
  (120.0, 140.0),
  (140.0, 155.0),
  (155.0, 170.0),
  (170.0, 190.0),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a proposed workout', () {
    WorkoutPlan parse(Map<String, Object?> o) =>
        WorkoutPlan.parse(o, date: '2026-11-14');

    test('takes the sport and zone minutes, padding to five zones', () {
      final w = parse({'sport': 'Running', 'zone_minutes': [0, 3, 9, 5]});
      expect(w.zoneMin, [0, 3, 9, 5, 0]);
      expect(w.durationMin, 17);
    });

    test('refuses what it cannot honour, with the reason', () {
      for (final bad in <Map<String, Object?>>[
        {'zone_minutes': [10]},
        {'sport': 'Run', 'zone_minutes': []},
        {'sport': 'Run', 'zone_minutes': [1, 2, 3, 4, 5, 6]},
        {'sport': 'Run', 'zone_minutes': [-5, 20]},
        {'sport': 'Run', 'zone_minutes': [2]},
        {'sport': 'Run', 'zone_minutes': [10, 10], 'duration_min': 45},
      ]) {
        expect(() => parse(bad), throwsA(isA<CoachActionError>()), reason: '$bad');
      }
    });

    test('a saved plan reads back the same', () {
      final w = parse({'sport': 'Cycling', 'zone_minutes': [5, 30, 10]});
      expect(WorkoutPlan.fromJson(w.toJson())!.sameAs(w), isTrue);
    });
  });

  group('the strain estimate', () {
    test('is absent without the anchors', () {
      expect(
          plannedStrain([0, 10, 10, 0, 0],
              zones: _bands, restingHr: null, maxHr: 190),
          isNull);
      expect(
          plannedStrain([0, 10, 10, 0, 0],
              zones: const [], restingHr: 55, maxHr: 190),
          isNull);
    });

    test('rises with time and with intensity, and stays on the dial', () {
      double s(List<double> m) =>
          plannedStrain(m, zones: _bands, restingHr: 55, maxHr: 190)!;
      final easy = s([0, 20, 0, 0, 0]);
      expect(s([0, 40, 0, 0, 0]), greaterThan(easy));
      expect(s([0, 0, 0, 20, 0]), greaterThan(easy));
      expect(s([0, 0, 0, 0, 300]), lessThanOrEqualTo(21));
    });
  });

  group('suggested replies', () {
    test('come off the end of an answer', () {
      final (text, replies) = splitReplies(
          'Recovery is **64%**.\n\n[[replies: Plan a workout | Why? | ]]');
      expect(text, 'Recovery is **64%**.');
      expect(replies, ['Plan a workout', 'Why?']);
    });

    test('an answer without them is left alone', () {
      final (text, replies) = splitReplies('Just this.');
      expect(text, 'Just this.');
      expect(replies, isEmpty);
    });

    test('a half-arrived line is held back while streaming', () {
      expect(withoutRepliesTail('All good.\n[[repl'), 'All good.');
      expect(withoutRepliesTail('All good.'), 'All good.');
    });

    test('survive being saved', () {
      final item = CoachItem.assistant('Hi', replies: const ['One', 'Two']);
      expect(CoachItem.fromJson(item.toJson()).replies, ['One', 'Two']);
    });
  });

  test('Answer again takes the last question and its answer back', () {
    final e = CoachEngine(config: CoachConfig(), api: _FakeRepo(), storageKey: 't');
    addTearDown(e.dispose);
    e.newSession();
    e.seedAnswer('First?', 'One.');
    e.transcript.add(CoachItem.user('Second?'));
    e.debugHistory
      ..add({'role': 'user', 'content': 'Second?'})
      ..add({'role': 'assistant', 'content': 'Two.'});
    e.transcript.add(CoachItem.assistant('Two.'));
    expect(e.takeBackLastTurn(), 'Second?');
    expect(e.transcript.map((i) => i.text), ['One.']);
    expect(e.debugHistory.map((m) => m['content']), ['First?', 'One.']);
  });
}

class _FakeRepo extends LocalRepository {}
