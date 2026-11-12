import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/coach.dart' show standardModels;

void main() {
  test('Gemini lists its chat models, not previews, media or pinned builds',
      () {
    const listed = [
      'models/gemini-2.5-flash',
      'models/gemini-2.5-pro',
      'models/gemini-2.5-flash-lite',
      'models/gemini-2.0-flash',
      'models/gemini-2.0-flash-001',
      'models/gemini-2.5-flash-preview-05-20',
      'models/gemini-2.5-flash-preview-tts',
      'models/gemini-2.5-flash-image',
      'models/gemini-2.0-flash-exp',
      'models/gemini-live-2.5-flash',
      'models/embedding-001',
      'models/gemini-embedding-001',
      'models/imagen-4.0-generate-001',
      'models/veo-3.0-generate-001',
      'models/gemma-3-27b-it',
      'models/aqa',
    ];
    expect(standardModels(listed), [
      'models/gemini-2.5-flash',
      'models/gemini-2.5-pro',
      'models/gemini-2.5-flash-lite',
      'models/gemini-2.0-flash',
    ]);
  });

  test('a dated id stays when it is the only name the model has', () {
    expect(standardModels(['claude-opus-4-1-20250805', 'gpt-4o', 'gpt-4o-2024-08-06']),
        ['claude-opus-4-1-20250805', 'gpt-4o']);
  });

  test('never an empty list', () {
    expect(standardModels(['text-embedding-3-small']), ['text-embedding-3-small']);
  });

  test('small chat models are standard: nano is a tier, not a media type', () {
    expect(
        standardModels(
            ['gpt-4.1', 'gpt-4.1-mini', 'gpt-4.1-nano', 'gpt-5-nano', 'whisper-1']),
        ['gpt-4.1', 'gpt-4.1-mini', 'gpt-4.1-nano', 'gpt-5-nano']);
  });

  test('-instruct is the chat build on a local server, a legacy one hosted', () {
    const ids = ['llama3.2:3b', 'qwen2.5:7b-instruct', 'nomic-embed-text'];
    expect(standardModels(ids, local: true),
        ['llama3.2:3b', 'qwen2.5:7b-instruct']);
    expect(standardModels(['gpt-4o', 'gpt-3.5-turbo-instruct']), ['gpt-4o']);
  });
}
