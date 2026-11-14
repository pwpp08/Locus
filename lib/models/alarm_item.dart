// alarm_item.dart — multi-alarm model with repeat rules, smart wake windows and labels.

import 'dart:convert';

import '../state/alarm_mode.dart';

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

  /// What the alarm waits for before it wakes you; [hour]:[minute] is the
  /// time it is set to, and the latest it will ever ring.
  final AlarmMode mode;

  /// A repeating alarm's one skipped morning, as a local `YYYY-MM-DD`: that
  /// day's occurrence does not ring, every later one does. Null when nothing
  /// is skipped. A date in the past is simply never matched again.
  final String? skipDay;

  /// A ring-once alarm's one instant, epoch milliseconds, stamped when it is
  /// saved or switched on. Once that instant has passed the alarm is spent:
  /// it has no next occurrence, so nothing re-arms it for the same time
  /// tomorrow (a ring the phone was not connected to hear, a headless sync
  /// the morning after). Null on a repeating alarm, and on one saved before
  /// this field existed, which keeps the old "next time this clock time
  /// comes round" reading.
  final int? onceAt;

  const AlarmItem({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = 'Alarm',
    this.enabled = true,
    this.days = const {},
    this.smartWindowMinutes = 0,
    this.mode = AlarmMode.exact,
    this.skipDay,
    this.onceAt,
  });

  /// `YYYY-MM-DD` for [d], the form [skipDay] is kept in.
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The minutes before the set time inside which this alarm may buzz early:
  /// its Smart Wake window, or a goal mode's own.
  int get earlyWindowMinutes =>
      mode == AlarmMode.exact ? smartWindowMinutes : kGoalWindowMin;

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
      final at = onceAt;
      if (at != null) {
        final t = DateTime.fromMillisecondsSinceEpoch(at);
        return t.isAfter(from) ? t : null;
      }
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
        if (candidate.isAfter(from) && dayKey(candidate) != skipDay) {
          return candidate;
        }
      }
    }
    return null;
  }

  /// The occurrence the next skip would drop: the next one, ignoring any skip
  /// already set. Null for a one-shot (turning it off is the skip).
  DateTime? nextUnskipped(DateTime from) =>
      days.isEmpty ? null : copyWith(clearSkip: true).nextOccurrence(from);

  AlarmItem copyWith({
    String? id,
    int? hour,
    int? minute,
    String? label,
    bool? enabled,
    Set<int>? days,
    int? smartWindowMinutes,
    AlarmMode? mode,
    String? skipDay,
    bool clearSkip = false,
    int? onceAt,
    bool clearOnce = false,
  }) =>
      AlarmItem(
        id: id ?? this.id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        days: days ?? this.days,
        smartWindowMinutes: smartWindowMinutes ?? this.smartWindowMinutes,
        mode: mode ?? this.mode,
        skipDay: clearSkip ? null : (skipDay ?? this.skipDay),
        onceAt: clearOnce ? null : (onceAt ?? this.onceAt),
      );

  /// This alarm as it should be stored at [now]: an enabled ring-once alarm
  /// stamped with the next time its clock time comes round, anything else
  /// with no stamp. A stamp still ahead for the same clock time is kept.
  AlarmItem stampedAt(DateTime now) {
    if (!enabled || days.isNotEmpty) {
      return onceAt == null ? this : copyWith(clearOnce: true);
    }
    final kept =
        onceAt == null ? null : DateTime.fromMillisecondsSinceEpoch(onceAt!);
    if (kept != null &&
        kept.isAfter(now) &&
        kept.hour == hour &&
        kept.minute == minute) {
      return this;
    }
    final next = copyWith(clearOnce: true).nextOccurrence(now)!;
    return copyWith(onceAt: next.millisecondsSinceEpoch);
  }

  /// A ring-once alarm whose instant has passed by [now].
  bool spentAt(DateTime now) =>
      enabled &&
      days.isEmpty &&
      onceAt != null &&
      !DateTime.fromMillisecondsSinceEpoch(onceAt!).isAfter(now);

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled,
        'days': days.toList()..sort(),
        'smartWindowMinutes': smartWindowMinutes,
        'mode': mode.name,
        if (skipDay != null) 'skipDay': skipDay,
        if (onceAt != null) 'onceAt': onceAt,
      };

  factory AlarmItem.fromJson(Map<String, dynamic> json) => AlarmItem(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        hour: (json['hour'] as num?)?.toInt() ?? 7,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
        label: (json['label'] as String?) ?? 'Alarm',
        enabled: (json['enabled'] as bool?) ?? true,
        days: ((json['days'] as List?)?.map((e) => (e as num).toInt()).toSet()) ?? const {},
        smartWindowMinutes: (json['smartWindowMinutes'] as num?)?.toInt() ?? 0,
        mode: AlarmMode.fromName(json['mode']),
        skipDay: json['skipDay'] as String?,
        onceAt: (json['onceAt'] as num?)?.toInt(),
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
