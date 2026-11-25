// Which behavior insights have newly unlocked, and which the person has been
// told about.
//
// A behavior unlocks once it has [kBehaviorMinDays] days on each side
// (behavior_impact.dart). This remembers the ones already announced so a card
// says each only once. The first time it runs it announces nothing: whatever is
// already unlocked then is not news.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'behavior_impact.dart';

/// A behavior's stable id: its kind and its name.
String insightId(BehaviorImpact b) => '${b.kind.name}:${b.title}';

/// The unlocked behaviors in [all] that are not in [told], strongest first.
List<BehaviorImpact> unseenUnlocked(List<BehaviorImpact> all, Set<String> told) {
  final out = [
    for (final b in all)
      if (b.impact != null && !told.contains(insightId(b))) b,
  ]..sort((a, b) => b.impact!.abs().compareTo(a.impact!.abs()));
  return out;
}

const String _kTold = 'insights.told';
const String _kPending = 'insights.pending';
const String _kChecked = 'insights.checked_day';

class InsightsUnlockedStore {
  const InsightsUnlockedStore();

  /// True when today has not been checked yet: the work is a 90-day read, so
  /// it runs once a day.
  Future<bool> dueOn(String day) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kChecked) != day;
  }

  /// Folds today's unlocked behaviors in: new ones become pending (the first
  /// run marks everything told instead), and [day] is recorded as checked.
  Future<void> update(List<BehaviorImpact> all, String day) async {
    final p = await SharedPreferences.getInstance();
    final first = !p.containsKey(_kTold);
    final told = {...?p.getStringList(_kTold)};
    if (first) {
      told.addAll([
        for (final b in all)
          if (b.impact != null) insightId(b),
      ]);
    }
    final fresh = first ? const <BehaviorImpact>[] : unseenUnlocked(all, told);
    final pending = _pending(p);
    for (final b in fresh) {
      if (!pending.any((e) => e['id'] == insightId(b))) {
        pending.add({'id': insightId(b), 'title': b.title});
      }
    }
    await p.setStringList(_kTold, told.toList());
    await p.setString(_kPending, jsonEncode(pending));
    await p.setString(_kChecked, day);
  }

  /// The names waiting to be announced, oldest first.
  Future<List<String>> pendingTitles() async {
    final p = await SharedPreferences.getInstance();
    return [for (final e in _pending(p)) '${e['title']}'];
  }

  /// The card was read or put away: what it showed is told.
  Future<void> dismiss() async {
    final p = await SharedPreferences.getInstance();
    final told = {...?p.getStringList(_kTold)}
      ..addAll([for (final e in _pending(p)) '${e['id']}']);
    await p.setStringList(_kTold, told.toList());
    await p.setString(_kPending, '[]');
  }

  List<Map<String, dynamic>> _pending(SharedPreferences p) {
    try {
      return [
        for (final e in jsonDecode(p.getString(_kPending) ?? '[]') as List)
          Map<String, dynamic>.from(e as Map),
      ];
    } catch (_) {
      return [];
    }
  }
}
