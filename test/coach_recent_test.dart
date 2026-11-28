// What was said to one AI surface reaches the others, and only while current.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_memory.dart';
import 'package:openstrap_edge/coach/coach_recent.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends LocalRepository {
  @override
  Future<List<Map<String, dynamic>>> getJournal({String range = '30d'}) async =>
      [
        {'date': '2026-05-22', 'tags': ['sick'], 'note': 'sore throat'},
        {'date': '2026-05-10', 'tags': ['travel'], 'note': ''},
      ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the last day and a half of chat and journal are handed on', () async {
    final now = DateTime(2026, 5, 22, 21);
    await CoachRecent.said('old news', now: DateTime(2026, 5, 20, 9));
    await CoachRecent.said('I am under the weather',
        now: DateTime(2026, 5, 22, 12, 5));
    final lines = await CoachRecent.lines(repo: _Repo(), now: now);
    expect(lines, [
      '2026-05-22 journal: sick. "sore throat"',
      '2026-05-22 12:05 to the coach: "I am under the weather"',
    ]);
  });

  test('clearing memory clears it too', () async {
    await CoachRecent.said('I slept at a friend\'s');
    await CoachMemory.clear();
    expect(await CoachRecent.lines(), isEmpty);
  });
}
