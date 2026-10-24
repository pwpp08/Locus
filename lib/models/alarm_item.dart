// alarm_item.dart — multi-alarm model with repeat rules, smart wake windows and labels.

import 'dart:convert';

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

  const AlarmItem({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = 'Alarm',
    this.enabled = true,
    this.days = const {},
    this.smartWindowMinutes = 0,
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
  }) =>
      AlarmItem(
        id: id ?? this.id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        days: days ?? this.days,
        smartWindowMinutes: smartWindowMinutes ?? this.smartWindowMinutes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled,
        'days': days.toList()..sort(),
        'smartWindowMinutes': smartWindowMinutes,
      };

  factory AlarmItem.fromJson(Map<String, dynamic> json) => AlarmItem(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        hour: (json['hour'] as num?)?.toInt() ?? 7,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
        label: (json['label'] as String?) ?? 'Alarm',
        enabled: (json['enabled'] as bool?) ?? true,
        days: ((json['days'] as List?)?.map((e) => (e as num).toInt()).toSet()) ?? const {},
        smartWindowMinutes: (json['smartWindowMinutes'] as num?)?.toInt() ?? 0,
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
