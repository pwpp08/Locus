// "Generate with AI": the reply is read leniently, nothing is invented from
// it, and a lift the library does not know is left out rather than guessed.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ai/workout_ai.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/coach/coach_engine.dart' show CoachException;
import 'package:openstrap_edge/ui2/activity/catalogue.dart';

void main() {
  group('parse', () {
    test('reads the contract', () {
      final w = parseWorkoutAi('''
{"name":"Push","exercises":[
 {"name":"Barbell Bench Press","sets":4,"reps":8,"kg":60},
 {"name":"Push-Up","sets":3,"reps":15,"kg":null}]}''')!;
      expect(w.name, 'Push');
      expect(w.exercises, hasLength(2));
      expect(w.exercises.first.sets, 4);
      expect(w.exercises.first.kg, 60);
      expect(w.exercises.last.kg, isNull);
    });

    test('survives fences and prose around the object', () {
      final w = parseWorkoutAi(
          'Sure!\n```json\n{"name":"Legs","exercises":[{"name":"Squat"}]}\n```')!;
      expect(w.exercises.single.sets, 3, reason: 'no sets given: 3 of 10');
      expect(w.exercises.single.reps, 10);
    });

    test('keeps the numbers sane and drops the nameless', () {
      final w = parseWorkoutAi('''
{"exercises":[{"name":"","sets":3},{"name":"Row","sets":99,"reps":-5,"kg":0}]}''')!;
      expect(w.name, 'My workout');
      expect(w.exercises.single.sets, 12);
      expect(w.exercises.single.reps, 1);
      expect(w.exercises.single.kg, isNull, reason: '0 kg is no load');
    });

    test('nothing usable is null, not an empty workout', () {
      expect(parseWorkoutAi('I could not do that.'), isNull);
      expect(parseWorkoutAi('{"exercises":[]}'), isNull);
      expect(parseWorkoutAi('{"name":"x"}'), isNull);
    });
  });

  group('engine', () {
    test('needs a key unless a chat is wired', () async {
      final e = WorkoutAiEngine(config: CoachConfig());
      expect(e.configured, isFalse);
      expect(() => e.build('bench'), throwsA(isA<CoachException>()));
    });

    test('sends the notes with the system prompt, returns the proposal', () async {
      List<Map<String, dynamic>>? seen;
      final e = WorkoutAiEngine(
        config: CoachConfig(),
        chat: (m) async {
          seen = m;
          return '{"name":"A","exercises":[{"name":"Deadlift","sets":5,"reps":5,"kg":100}]}';
        },
      );
      final w = await e.build('deadlift 5x5 at 100');
      expect(w!.exercises.single.name, 'Deadlift');
      expect(seen!.first['role'], 'system');
      expect(seen!.last['content'], 'deadlift 5x5 at 100');
    });
  });

  group('matching a name to the library', () {
    test('an exact label wins, whatever the case', () {
      expect(findExercise('bench press')?.key, 'bench_press');
      expect(findExercise('  BENCH  PRESS ')?.key, 'bench_press');
    });

    test('hyphens and plurals do not matter', () {
      final a = findExercise('Pull-Up');
      final b = findExercise('pull ups');
      expect(a, isNotNull);
      expect(a!.label.toLowerCase(), contains('pull'));
      expect(b?.key, a.key);
    });

    test('an unknown name is not forced onto the nearest lift', () {
      expect(findExercise('quantum flux curl'), isNull);
      expect(findExercise(''), isNull);
    });
  });

  group('the imported library', () {
    test('has the photos it advertises', () {
      final withPhotos = exerciseLibrary.where((e) => e.imageId != null);
      expect(withPhotos.length, greaterThan(500));
      final e = withPhotos.first;
      expect(e.imagePath(0), startsWith('assets/exercises/'));
      expect(e.imagePath(0), endsWith('_0.jpg'));
      // A single-photo exercise never points past it.
      final single = withPhotos.where((x) => x.imageFrames == 1);
      for (final s in single) {
        expect(s.imagePath(1), s.imagePath(0));
      }
    });

    test('keys stay unique across all three sources', () {
      final keys = exerciseLibrary.map((e) => e.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });
}
