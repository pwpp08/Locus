// What the person asked the AI to remember: "no emojis", "I train for a
// marathon in April", "call me Vince". Short notes, kept on the phone, handed
// to every coach chat and every outlook so the ask holds next time too.
//
// The coach writes here with its `remember` / `forget` tools when the person
// says so; the person sees and deletes them under AI settings → Memory.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoachMemory {
  CoachMemory._();

  static const _key = 'coach_memory_v1';

  /// The most notes kept; the oldest goes first.
  static const int maxNotes = 40;

  /// The longest one note may be.
  static const int maxChars = 240;

  /// Bumps whenever the notes change, for a screen listing them.
  static final changed = ValueNotifier<int>(0);

  static Future<List<String>> all() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getStringList(_key) ?? const [];
    } catch (_) {
      return const []; // no store (a test, a headless start): no notes
    }
  }

  static Future<void> _write(List<String> notes) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, notes);
    changed.value++;
  }

  /// Keep [note]. Returns what was stored, or null for an empty note. The
  /// same note twice is kept once.
  static Future<String?> add(String note) async {
    var n = note.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return null;
    if (n.length > maxChars) n = n.substring(0, maxChars);
    final notes = [...await all()]
      ..removeWhere((x) => x.toLowerCase() == n.toLowerCase());
    notes.add(n);
    while (notes.length > maxNotes) {
      notes.removeAt(0);
    }
    await _write(notes);
    return n;
  }

  /// Drop the notes that [match] names: an exact note, or words a note
  /// contains. Returns the notes removed.
  static Future<List<String>> forget(String match) async {
    final m = match.trim().toLowerCase();
    if (m.isEmpty) return const [];
    final notes = [...await all()];
    final exact = notes.where((x) => x.toLowerCase() == m).toList();
    final gone = exact.isNotEmpty
        ? exact
        : notes.where((x) => x.toLowerCase().contains(m)).toList();
    if (gone.isEmpty) return const [];
    notes.removeWhere(gone.contains);
    await _write(notes);
    return gone;
  }

  static Future<void> removeAt(int i) async {
    final notes = [...await all()];
    if (i < 0 || i >= notes.length) return;
    notes.removeAt(i);
    await _write(notes);
  }

  static Future<void> clear() => _write(const []);

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
