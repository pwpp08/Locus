// What the person asked the AI to remember: "no emojis", "I train for a
// marathon in April", "call me Vince". Short notes, kept on the phone, handed
// to every coach chat and every outlook so the ask holds next time too.
//
// The coach writes here with its `remember` / `forget` tools when the person
// says so, and the person adds their own on the memory page. Each note has a
// kind (a goal, a coaching preference, or something about them) and the day
// it was kept, which the memory page's tabs and timeline sort by.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/prefs.dart';
import 'coach_recent.dart';

/// What a note is about; the memory page has a tab for each.
enum MemoryKind {
  goal('Goal', 'Goals'),
  preference('Preference', 'Coaching preferences'),
  about('About you', 'About you');

  final String label, tab;
  const MemoryKind(this.label, this.tab);

  static MemoryKind parse(Object? v) {
    for (final k in values) {
      if (k.name == v) return k;
    }
    return MemoryKind.about;
  }
}

@immutable
class MemoryNote {
  final String text;
  final MemoryKind kind;

  /// When it was kept, ms since epoch; 0 for a note from before dates.
  final int at;

  const MemoryNote(this.text, this.kind, this.at);

  Map<String, Object> toJson() => {'t': text, 'k': kind.name, 'at': at};

  static MemoryNote? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = '${j['t'] ?? ''}'.trim();
    if (t.isEmpty) return null;
    return MemoryNote(
        t, MemoryKind.parse(j['k']), (j['at'] as num?)?.toInt() ?? 0);
  }
}

class CoachMemory {
  CoachMemory._();

  static const _key = 'coach_memory_v2';

  /// The text-only list the first version kept; read once and carried over.
  static const _legacyKey = 'coach_memory_v1';

  /// The most notes kept; the oldest goes first.
  static const int maxNotes = 40;

  /// The longest one note may be.
  static const int maxChars = 240;

  /// Bumps whenever the notes change, for a screen listing them.
  static final changed = ValueNotifier<int>(0);

  static const _kOn = 'coach.memory.on';

  /// Whether the AI may use and keep notes (AI settings → Memory). Off, the
  /// notes stay on the page but go to no prompt, and nothing new is kept.
  static bool get enabled => Prefs.getBool(_kOn, true);
  static set enabled(bool v) => Prefs.setBool(_kOn, v);

  /// What the prompts get: every note, or none while memory is off.
  static Future<List<String>> forPrompt() async =>
      enabled ? await all() : const [];

  /// Every note, oldest first.
  static Future<List<MemoryNote>> notes() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is! List) return const [];
        return [
          for (final j in list) ?MemoryNote.fromJson(j),
        ];
      }
      final legacy = p.getStringList(_legacyKey) ?? const [];
      return [for (final t in legacy) MemoryNote(t, MemoryKind.about, 0)];
    } catch (_) {
      return const []; // no store (a test, a headless start): no notes
    }
  }

  /// Every note's words, oldest first: what the prompts are given.
  static Future<List<String>> all() async =>
      [for (final n in await notes()) n.text];

  static Future<void> _write(List<MemoryNote> notes) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode([for (final n in notes) n.toJson()]));
    await p.remove(_legacyKey);
    changed.value++;
  }

  /// Keep [note] as [kind]. Returns what was stored, or null for an empty
  /// note. The same words twice are kept once, as the newer one.
  static Future<String?> add(String note,
      {MemoryKind kind = MemoryKind.about, DateTime? now}) async {
    var n = note.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return null;
    if (n.length > maxChars) n = n.substring(0, maxChars);
    final list = [...await notes()]
      ..removeWhere((x) => x.text.toLowerCase() == n.toLowerCase());
    list.add(MemoryNote(n, kind, (now ?? DateTime.now()).millisecondsSinceEpoch));
    while (list.length > maxNotes) {
      list.removeAt(0);
    }
    await _write(list);
    return n;
  }

  /// Drop the notes that [match] names: an exact note, or words a note
  /// contains. Returns the notes removed.
  static Future<List<String>> forget(String match) async {
    final m = match.trim().toLowerCase();
    if (m.isEmpty) return const [];
    final list = [...await notes()];
    final exact = list.where((x) => x.text.toLowerCase() == m).toList();
    final gone = exact.isNotEmpty
        ? exact
        : list.where((x) => x.text.toLowerCase().contains(m)).toList();
    if (gone.isEmpty) return const [];
    list.removeWhere(gone.contains);
    await _write(list);
    return [for (final g in gone) g.text];
  }

  /// Drop [note] itself (the memory page's delete).
  static Future<void> remove(MemoryNote note) async {
    final list = [...await notes()]..remove(note);
    await _write(list);
  }

  static Future<void> removeAt(int i) async {
    final list = [...await notes()];
    if (i < 0 || i >= list.length) return;
    list.removeAt(i);
    await _write(list);
  }

  static Future<void> clear() async {
    await CoachRecent.clear();
    await _write(const []);
  }

  /// The notes as a prompt section, or '' when there are none.
  static String promptSection(List<String> notes) {
    if (notes.isEmpty) return '';
    return [
      '# WHAT THEY ASKED YOU TO REMEMBER',
      'They told you these in earlier chats. Follow them every time, without '
          'mentioning that you remembered.',
      for (final n in notes) '- $n',
    ].join('\n');
  }
}
