// Food photos have a model of their own, and a refused request says enough to
// act on: a bare 404 used to read "Provider error (404):" and nothing else.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/coach/coach_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions');

  group('a refused request', () {
    test('a bare 404 names the host, the model and the usual cause', () {
      final t = CoachEngine.providerErrorText(
          status: 404, body: '', reason: 'Not Found', uri: uri, model: 'gemini-x');
      expect(t, startsWith('Provider error (404): Not Found'));
      expect(t, contains('generativelanguage.googleapis.com'));
      expect(t, contains('model "gemini-x"'));
      expect(t, contains('model name'));
    });

    test('a message in a list, as Google sends it, is read', () {
      final t = CoachEngine.providerErrorText(
          status: 404,
          body: '[{"error":{"code":404,"message":"models/gemini-x is not found"}}]',
          uri: uri,
          model: 'gemini-x');
      expect(t, contains('models/gemini-x is not found'));
    });

    test('a message in an object, as OpenAI sends it, is read', () {
      final t = CoachEngine.providerErrorText(
          status: 401,
          body: '{"error":{"message":"Incorrect API key"}}',
          uri: uri,
          model: 'm');
      expect(t, contains('Incorrect API key'));
      expect(t, contains('API key'));
    });

    test('it stays on one line, so the translated card can still parse it', () {
      final t = CoachEngine.providerErrorText(
          status: 500, body: 'oops', uri: uri, model: 'm');
      expect(t.contains('\n'), isFalse);
    });
  });

  group('the food model', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('empty means the coach model', () async {
      final c = CoachConfig();
      await c.save(model: 'big-model');
      expect(c.foodModelOrCoach, 'big-model');
    });

    test('its own value is kept apart and survives a reload', () async {
      final c = CoachConfig();
      await c.save(model: 'big-model', foodModel: ' vision-model ');
      expect(c.model, 'big-model');
      expect(c.foodModel, 'vision-model');
      expect(c.foodModelOrCoach, 'vision-model');
      final again = CoachConfig();
      await again.load();
      expect(again.foodModelOrCoach, 'vision-model');
      expect(again.model, 'big-model');
    });

    test('clearing it goes back to the coach model', () async {
      final c = CoachConfig();
      await c.save(model: 'big-model', foodModel: 'vision-model');
      await c.save(foodModel: '');
      expect(c.foodModelOrCoach, 'big-model');
    });
  });
}
