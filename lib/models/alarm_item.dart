// alarm_item.dart — multi-alarm model with repeat rules, smart wake windows and labels.

import 'dart:convert';

/// How the band buzzes for an alarm.
///
/// [standard] is the strap's own wake buzz, armed with the REV-1 form that
/// fires on every WHOOP 4 firmware we have seen. Every other pattern needs the
/// 20-byte RICH arm form, which some WHOOP 4 firmwares (41.17.4) store and
/// confirm but never execute — so a custom pattern is only ever armed once the
/// user has watched it fire on their own band (see `AlarmManager.richVerified`).
/// Until then it falls back to [standard]: a silent alarm is the one failure
/// this feature must never cause.
///
/// The patterns only reorder and repeat the two waveform effects (47, 152) the
/// strap itself uses for its wake buzz. No other effect id is known to do
/// anything on this hardware, so none is guessed at.
enum AlarmBuzz {
  standard('Standard', "The band's own wake buzz"),
  gentle('Gentle', 'Single soft pulses, 20 s'),
  pulse('Pulse', 'Double pulses, 45 s'),
  insistent('Insistent', 'Back-to-back buzzing, 60 s'),
  marathon('Long', 'Standard rhythm for 2 minutes');

  final String label;
  final String description;
  const AlarmBuzz(this.label, this.description);

  /// The 12-byte rich-form haptic body: 8 waveform-effect slots, u16 loop
  /// control (LE), overall loop count, duration in seconds. Null for
  /// [standard], which is armed with the rev-1 form instead.
  List<int>? get haptics => switch (this) {
        AlarmBuzz.standard => null,
        AlarmBuzz.gentle => const [47, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 20],
        AlarmBuzz.pulse => const [47, 47, 0, 0, 0, 0, 0, 0, 0, 0, 10, 45],
        AlarmBuzz.insistent =>
          const [47, 152, 47, 152, 47, 152, 47, 152, 0, 0, 15, 60],
        AlarmBuzz.marathon => const [47, 152, 0, 0, 0, 0, 0, 0, 0, 0, 30, 120],
      };

  static AlarmBuzz fromName(String? name) => AlarmBuzz.values.firstWhere(
      (b) => b.name == name,
      orElse: () => AlarmBuzz.standard);
}

/// Days of week: 1 = Monday ... 7 = Sunday (matches DateTime.weekday).
class AlarmItem {
  final String id;
  final int hour;
  final int minute;
  final String label;
  final bool enabled;

  /// Empty set means "Ring once" (one-shot).
  /// Non-empty set contains weekdays 1=Mon .. 7=Sun.
  final Set<int> days;

  /// Minutes before wake time to buzz early if light sleep is detected.
  /// 0 = disabled.
  final int smartWindowMinutes;

  /// The buzz this alarm asks for. See [AlarmBuzz] for when it is honoured.
  final AlarmBuzz buzz;

  const AlarmItem({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = 'Alarm',
    this.enabled = true,
    this.days = const {},
    this.smartWindowMinutes = 0,
    this.buzz = AlarmBuzz.standard,
  });

  bool get isRingOnce => days.isEmpty;
  bool get isOneShot => isRingOnce;
  bool get isEveryday => days.length == 7;
  bool get isWeekdays =>
      days.length == 5 &&
      days.contains(DateTime.monday) &&
      days.contains(DateTime.tuesday) &&
      days.contains(DateTime.wednesday) &&
      days.contains(DateTime.thursday) &&
      days.contains(DateTime.friday);
  bool get isWeekends =>
      days.length == 2 &&
      days.contains(DateTime.saturday) &&
      days.contains(DateTime.sunday);

  String repeatSummary() {
    if (isRingOnce) return 'Ring once';
    if (isEveryday) return 'Every day';
    if (isWeekdays) return 'Weekdays';
    if (isWeekends) return 'Weekends';

    const shortNames = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    final sorted = days.toList()..sort();
    return sorted.map((d) => shortNames[d] ?? '').join(' ');
  }

  /// Calculates the next occurrence of this alarm strictly after [from].
  DateTime? nextOccurrence(DateTime from) {
    if (!enabled) return null;

    if (days.isEmpty) {
      // Ring once
      final candidate = DateTime(from.year, from.month, from.day, hour, minute);
      if (candidate.isAfter(from)) {
        return candidate;
      }
      return candidate.add(const Duration(days: 1));
    }

    // Check upcoming 14 days
    for (int offset = 0; offset <= 14; offset++) {
      final date = from.add(Duration(days: offset));
      if (days.contains(date.weekday)) {
        final candidate = DateTime(date.year, date.month, date.day, hour, minute);
        if (candidate.isAfter(from)) {
          return candidate;
        }
      }
    }
    return null;
  }

  AlarmItem copyWith({
    String? id,
    int? hour,
    int? minute,
    String? label,
    bool? enabled,
    Set<int>? days,
    int? smartWindowMinutes,
    AlarmBuzz? buzz,
  }) =>
      AlarmItem(
        id: id ?? this.id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        days: days ?? this.days,
        smartWindowMinutes: smartWindowMinutes ?? this.smartWindowMinutes,
        buzz: buzz ?? this.buzz,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled,
        'days': days.toList()..sort(),
        'smartWindowMinutes': smartWindowMinutes,
        'buzz': buzz.name,
      };

  factory AlarmItem.fromJson(Map<String, dynamic> json) => AlarmItem(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        hour: (json['hour'] as num?)?.toInt() ?? 7,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
        label: (json['label'] as String?) ?? 'Alarm',
        enabled: (json['enabled'] as bool?) ?? true,
        days: ((json['days'] as List?)?.map((e) => (e as num).toInt()).toSet()) ?? const {},
        smartWindowMinutes: (json['smartWindowMinutes'] as num?)?.toInt() ?? 0,
        buzz: AlarmBuzz.fromName(json['buzz'] as String?),
      );

  static List<AlarmItem> decodeList(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) => AlarmItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<AlarmItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
}
