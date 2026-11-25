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

  /// One day's later ring, as a local `YYYY-MM-DD` and the minutes it moves:
  /// that day's occurrence rings [moveMin] minutes later, every other day
  /// rings at the set time. Set from the heads-up notification's delay
  /// buttons; a date in the past is simply never matched again.
  final String? moveDay;
  final int moveMin;

  /// False for a schedule that only says when you wake: the planner plans
  /// bed and wake times round it, and nothing is ever armed on the band
  /// ("Don't use an alarm"). It has no next ring, so every armer skips it.
  final bool ring;

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
    this.moveDay,
    this.moveMin = 0,
    this.ring = true,
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
    if (!enabled || !ring) return null;

    if (days.isEmpty) {
      // Ring once
      final at = onceAt;
      if (at != null) {
        final t = _moved(DateTime.fromMillisecondsSinceEpoch(at));
        return t.isAfter(from) ? t : null;
      }
      final candidate = DateTime(from.year, from.month, from.day, hour, minute);
      if (_moved(candidate).isAfter(from)) {
        return _moved(candidate);
      }
      return candidate.add(const Duration(days: 1));
    }

    // Check upcoming 14 days
    for (int offset = 0; offset <= 14; offset++) {
      final date = from.add(Duration(days: offset));
      if (days.contains(date.weekday)) {
        final candidate = DateTime(date.year, date.month, date.day, hour, minute);
        final rings = _moved(candidate);
        if (rings.isAfter(from) && dayKey(candidate) != skipDay) {
          return rings;
        }
      }
    }
    return null;
  }

  /// [t] with this alarm's one later morning applied, when it is that day.
  DateTime _moved(DateTime t) => moveDay != null &&
          moveMin != 0 &&
          dayKey(DateTime(t.year, t.month, t.day)) == moveDay
      ? t.add(Duration(minutes: moveMin))
      : t;

  /// This alarm with its next ring dropped: a repeating alarm skips that
  /// morning only, a ring-once alarm turns off. Null when nothing is ahead.
  AlarmItem? skippedNext(DateTime now) {
    if (days.isEmpty) {
      return nextOccurrence(now) == null
          ? null
          : copyWith(enabled: false, clearOnce: true, clearMove: true);
    }
    final next = nextUnskipped(now);
    return next == null
        ? null
        : copyWith(skipDay: dayKey(next), clearMove: true);
  }

  /// This alarm with its next ring [minutes] later, that morning only. Null
  /// when nothing is ahead.
  AlarmItem? delayedNext(int minutes, DateTime now) {
    final next = nextOccurrence(now);
    if (next == null) return null;
    // The morning's own set time; [next] already carries any move made earlier
    // that day, so the new move is that plus [minutes].
    final set = DateTime(next.year, next.month, next.day, hour, minute);
    return copyWith(
        moveDay: dayKey(set),
        moveMin: next.difference(set).inMinutes + minutes);
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
    bool? ring,
    String? moveDay,
    int? moveMin,
    bool clearMove = false,
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
        moveDay: clearMove ? null : (moveDay ?? this.moveDay),
        moveMin: clearMove ? 0 : (moveMin ?? this.moveMin),
        ring: ring ?? this.ring,
      );

  /// This alarm as it should be stored at [now]: an enabled ring-once alarm
  /// stamped with the next time its clock time comes round, anything else
  /// with no stamp. A stamp still ahead for the same clock time is kept.
  AlarmItem stampedAt(DateTime now) {
    if (!enabled || !ring || days.isNotEmpty) {
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
        if (moveDay != null && moveMin != 0) ...{
          'moveDay': moveDay,
          'moveMin': moveMin,
        },
        if (!ring) 'ring': false,
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
        moveDay: json['moveDay'] as String?,
        moveMin: (json['moveMin'] as num?)?.toInt() ?? 0,
        ring: json['ring'] != false,
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
