import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';

void main() {
  group('findExercise', () {
    test('matches core gym lifts by common synonyms', () {
      expect(findExercise('squat')?.label.toLowerCase(), contains('squat'));
      expect(findExercise('bench press')?.label.toLowerCase(), contains('bench press'));
      expect(findExercise('bench')?.label.toLowerCase(), contains('bench press'));
      expect(findExercise('deadlift')?.label.toLowerCase(), contains('deadlift'));
      expect(findExercise('pull up')?.label.toLowerCase(), contains('pull'));
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

  group('photoOf', () {
    test('back squat and core exercises all have images', () {
      final backSquat = exerciseByKey('back_squat');
      expect(backSquat, isNotNull);
      final photo = photoOf(backSquat!);
      expect(photo, isNotNull);
      expect(photo!.imageId, isNotNull);
      expect(photo.imageFrames, greaterThanOrEqualTo(1));

      for (var i = 0; i < coreExerciseCount; i++) {
        final ex = exerciseLibrary[i];
        final p = photoOf(ex);
        expect(p, isNotNull, reason: '${ex.label} should have an image');
        expect(p!.imageId, isNotNull, reason: '${ex.label} imageId should not be null');
      }
    });

    test('synonym and word matching finds image for free-text inputs', () {
      final squat = findExercise('back squat');
      expect(squat, isNotNull);
      expect(photoOf(squat!), isNotNull);

      final rdl = findExercise('RDL');
      expect(rdl, isNotNull);
      expect(photoOf(rdl!), isNotNull);
    });
  });
}
