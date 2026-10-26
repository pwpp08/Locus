// workout_ai.dart — turns a person's own notes ("push day: bench 4x8 at 60,
// overhead press 3x10, triceps pushdowns") into a PROPOSED strength workout via
// the BYOK key, the same way journal_ai.dart turns a recap into a journal entry.
// The model never writes to the store: it names exercises, the app matches
// each name against its own library, and the person sees and edits what was
// understood before anything is saved. A name the library does not know stays
// out and is reported, never invented into a lift.

import 'dart:convert';

import '../coach/coach_config.dart';
import '../coach/coach_engine.dart';

/// One line of a proposed workout, as the model wrote it.
class AiExercise {
  final String name;
  final int sets, reps;

  /// Per-set load in kg when the notes gave one; null for bodyweight or unsaid.
  final double? kg;
  const AiExercise(this.name, this.sets, this.reps, this.kg);
}

class AiWorkout {
  final String name;
  final List<AiExercise> exercises;
  const AiWorkout(this.name, this.exercises);
}

String workoutAiSystemPrompt() =>
    'You turn a person\'s workout notes into a structured strength workout.\n'
    'Respond with ONLY a JSON object, no other text:\n'
    '{"name": string, "exercises": [{"name": string, "sets": integer, '
    '"reps": integer, "kg": number or null}]}\n'
    '- name: a short title for the workout (e.g. "Push", "Leg day"), in '
    'their words if they gave one.\n'
    '- exercises: in the order given. Use the common English name of each '
    'lift (e.g. "Barbell Bench Press", "Pull-Up", "Romanian Deadlift"). '
    '"sets" and "reps" are what one set is; if the notes give a range take '
    'the lower end; if they give none use 3 sets of 10. "kg" is the load per '
    'set in kilograms (convert pounds), or null for bodyweight or when no '
    'load is given.\n'
    '- Only exercises they actually wrote. No advice, no extras, no '
    'commentary.';

/// Parses the model's JSON leniently (fences, prose around the object). Null
/// when nothing usable came back: the caller says so rather than guessing.
AiWorkout? parseWorkoutAi(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final nl = text.indexOf('\n');
    if (nl > 0) text = text.substring(nl + 1);
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);
    text = text.trim();
  }
  dynamic j;
  try {
    j = jsonDecode(text);
  } catch (_) {
    final s = text.indexOf('{'), e = text.lastIndexOf('}');
    if (s >= 0 && e > s) {
      try {
        j = jsonDecode(text.substring(s, e + 1));
      } catch (_) {}
    }
  }
  if (j is! Map || j['exercises'] is! List) return null;
  final out = <AiExercise>[];
  for (final e in j['exercises'] as List) {
    if (e is! Map) continue;
    final name = (e['name'] as String?)?.trim();
    if (name == null || name.isEmpty) continue;
    final sets = ((e['sets'] as num?)?.toInt() ?? 3).clamp(1, 12);
    final reps = ((e['reps'] as num?)?.toInt() ?? 10).clamp(1, 100);
    final kg = (e['kg'] as num?)?.toDouble();
    out.add(AiExercise(name, sets, reps, kg != null && kg > 0 ? kg : null));
  }
  if (out.isEmpty) return null;
  final name = (j['name'] as String?)?.trim();
  return AiWorkout(name == null || name.isEmpty ? 'My workout' : name, out);
}

class WorkoutAiEngine {
  final CoachConfig config;

  /// Test seam: given the messages, return the model text.
  final Future<String> Function(List<Map<String, dynamic>> messages)? chat;

  WorkoutAiEngine({required this.config, this.chat});

  bool get configured => chat != null || config.configured;

  /// One request → the parsed proposal. Throws [CoachException] on provider
  /// errors or a missing key; returns null when the reply held no workout.
  Future<AiWorkout?> build(String notes) async {
    if (!configured) {
      throw CoachException('Add your AI key to build a workout from notes.');
    }
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': workoutAiSystemPrompt()},
      {'role': 'user', 'content': notes},
    ];
    final raw = await (chat != null
        ? chat!(messages)
        : CoachEngine.chatOnce(config: config, messages: messages));
    return parseWorkoutAi(raw);
  }
}
