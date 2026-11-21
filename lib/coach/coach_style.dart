// How the person wants the coach to write: emojis or none, how long an
// answer runs, and the tone. Chosen under AI settings, sent with every chat
// turn after the base prompt so it overrides the prompt's own STYLE defaults.

import '../state/prefs.dart';

/// How long a chat answer runs.
enum CoachLength {
  brief('Brief', 'Answer in two to four short lines. Skip background unless '
      'asked; one bullet list at most.'),
  balanced('Balanced', 'Keep answers short: the verdict, the why, and what to '
      'do, in a few short paragraphs.'),
  thorough('Thorough', 'Give fuller answers: explain the why with the numbers '
      'behind it and the trade-offs, still in short paragraphs.');

  final String label, rule;
  const CoachLength(this.label, this.rule);
}

/// The coach's tone.
enum CoachTone {
  friendly('Friendly', 'Warm and encouraging, like a supportive friend who '
      'knows the science. Plain words, a little personality.'),
  professional('Professional', 'Calm, precise and neutral, like a sports '
      'physician. No small talk, no exclamation marks.'),
  direct('Direct', 'Blunt and to the point, like a no-nonsense coach. Say what '
      'to do and why in as few words as possible.'),
  motivating('Motivating', 'Energetic and upbeat, like a coach before a '
      'session. Push the person a little, celebrate progress.');

  final String label, rule;
  const CoachTone(this.label, this.rule);
}

class CoachStyle {
  CoachStyle._();

  static const _kEmoji = 'coach.style.emoji';
  static const _kLength = 'coach.style.length';
  static const _kTone = 'coach.style.tone';

  /// Off by default: the person asked the coach to stop using them.
  static bool get emojis => Prefs.getBool(_kEmoji, false);
  static set emojis(bool v) => Prefs.setBool(_kEmoji, v);

  static CoachLength get length =>
      _pick(CoachLength.values, Prefs.getString(_kLength, ''),
          CoachLength.balanced);
  static set length(CoachLength v) => Prefs.setString(_kLength, v.name);

  static CoachTone get tone =>
      _pick(CoachTone.values, Prefs.getString(_kTone, ''), CoachTone.friendly);
  static set tone(CoachTone v) => Prefs.setString(_kTone, v.name);

  static T _pick<T extends Enum>(List<T> values, String name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  /// The system-prompt section for the current choices.
  static String promptSection() => section(
        emojis: emojis,
        length: length,
        tone: tone,
      );

  static String section({
    required bool emojis,
    required CoachLength length,
    required CoachTone tone,
  }) =>
      [
        '# THE PERSON\'S STYLE CHOICES (these override STYLE above)',
        '- Length: ${length.rule}',
        '- Tone: ${tone.rule}',
        emojis
            ? '- Emojis: allowed, at most one or two in an answer where they '
                'fit.'
            : '- Emojis: never use any emoji or emoticon, in any reply.',
      ].join('\n');
}
