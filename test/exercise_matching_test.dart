import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';

void main() {
  group('findExercise', () {
    test('matches core gym lifts by common synonyms', () {
      expect(findExercise('squat')?.label.toLowerCase(), contains('squat'));
      expect(findExercise('bench press')?.label.toLowerCase(), contains('bench press'));
      expect(findExercise('bench')?.label.toLowerCase(), contains('bench press'));
      expect(findExercise('deadlift')?.label.toLowerCase(), contains('deadlift'));
      expect(findExercise('pull up')?.label.toLowerCase(), contains('pullup'));
      expect(findExercise('overhead press')?.label.toLowerCase(), contains('press'));
      expect(findExercise('curls')?.label.toLowerCase(), contains('curl'));
      expect(findExercise('lateral raises')?.label.toLowerCase(), contains('lateral raise'));
      expect(findExercise('tricep pushdown')?.label.toLowerCase(), contains('pushdown'));
      expect(findExercise('leg press')?.label.toLowerCase(), contains('leg press'));
    });

    test('matches through word containment', () {
      final res = findExercise('incline dumbbell press');
      expect(res, isNotNull);
      expect(res!.label.toLowerCase(), contains('incline'));
    });

    test('returns null for completely unrelated terms', () {
      expect(findExercise('xyz random nonexistent'), isNull);
    });
  });
}
