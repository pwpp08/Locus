// The Daily Outlook opens as the coach's first turn of a NEW conversation, and
// the question it answers rides in the history so a reply has context.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ai/food_ai.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/coach/coach_engine.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('seedAnswer shows only the answer and keeps the pair in history', () {
    final e = CoachEngine(
        config: CoachConfig(), api: _FakeRepo(), storageKey: 't');
    addTearDown(e.dispose);
    e.newSession();
    e.seedAnswer('What is my outlook for today?', 'Recovery is 64%.');
    expect(e.transcript.map((i) => i.kind), [CoachItemKind.assistant]);
    expect(e.transcript.single.text, 'Recovery is 64%.');
    expect(e.debugHistory.map((m) => m['role']), ['user', 'assistant']);
  });

  test('content sent as a list of parts is still text', () {
    expect(CoachEngine.contentText('hi'), 'hi');
    expect(
        CoachEngine.contentText([
          {'type': 'text', 'text': '{"items":'},
          {'type': 'text', 'text': '[]}'},
        ]),
        '{"items":[]}');
    expect(CoachEngine.contentText(null), '');
  });

  test('food figures quoted as strings are read', () {
    final g = parseFoodAi(
        '{"items":[{"name":"Rice","grams":"150 g","kcal":"195","protein_g":4}]}');
    expect(g.single.grams, 150);
    expect(g.single.kcal, closeTo(195, .01));
  });
}

class _FakeRepo extends LocalRepository {}
