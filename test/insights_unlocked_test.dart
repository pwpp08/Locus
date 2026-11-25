// Which behavior insights count as newly unlocked, and that each is announced
// once: the first run announces nothing, a later one announces what unlocked since.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/behavior_impact.dart';
import 'package:openstrap_edge/compute/insights_unlocked.dart';
import 'package:shared_preferences/shared_preferences.dart';

BehaviorImpact _b(String t, {double? impact}) => BehaviorImpact(
      kind: BehaviorKind.journalTag,
      title: t,
      yes: impact == null ? 2 : 6,
      no: impact == null ? 2 : 6,
      meanYes: impact == null ? null : 50 + impact,
      meanNo: impact == null ? null : 50,
      se: impact == null ? null : 1,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only unlocked, unannounced behaviors count, strongest first', () {
    final all = [_b('A', impact: -3), _b('B'), _b('C', impact: 8), _b('D', impact: 1)];
    final out = unseenUnlocked(all, {insightId(all[3])});
    expect([for (final b in out) b.title], ['C', 'A']);
  });

  test('the first run announces nothing, a later run announces what is new', () async {
    const store = InsightsUnlockedStore();
    expect(await store.dueOn('2026-11-25'), isTrue);
    await store.update([_b('A', impact: 4)], '2026-11-25');
    expect(await store.pendingTitles(), isEmpty);
    expect(await store.dueOn('2026-11-25'), isFalse);

    await store.update([_b('A', impact: 4), _b('B', impact: -5)], '2026-11-26');
    expect(await store.pendingTitles(), ['B']);
    // Running again the same day does not repeat it.
    await store.update([_b('A', impact: 4), _b('B', impact: -5)], '2026-11-26');
    expect(await store.pendingTitles(), ['B']);

    await store.dismiss();
    expect(await store.pendingTitles(), isEmpty);
    await store.update([_b('A', impact: 4), _b('B', impact: -5)], '2026-11-27');
    expect(await store.pendingTitles(), isEmpty);
  });
}
