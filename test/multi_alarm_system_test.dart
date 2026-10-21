import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/alarm_item.dart';
import 'package:openstrap_edge/state/alarm_manager.dart';

void main() {
  group('AlarmItem model', () {
    test('serializes and deserializes correctly', () {
      final alarm = AlarmItem(
        id: 'alarm_1',
        hour: 7,
        minute: 30,
        label: 'Work',
        enabled: true,
        days: {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday},
        smartWindowMinutes: 20,
      );

      final jsonMap = alarm.toJson();
      final revived = AlarmItem.fromJson(jsonMap);

      expect(revived.id, 'alarm_1');
      expect(revived.hour, 7);
      expect(revived.minute, 30);
      expect(revived.label, 'Work');
      expect(revived.enabled, true);
      expect(revived.days, {1, 2, 3, 4, 5});
      expect(revived.isWeekdays, true);
      expect(revived.smartWindowMinutes, 20);
    });

    test('repeat summaries work as expected', () {
      expect(const AlarmItem(id: '1', hour: 6, minute: 0, days: {}).repeatSummary(), 'Ring once');
      expect(const AlarmItem(id: '2', hour: 6, minute: 0, days: {1, 2, 3, 4, 5}).repeatSummary(), 'Weekdays');
      expect(const AlarmItem(id: '3', hour: 6, minute: 0, days: {6, 7}).repeatSummary(), 'Weekends');
      expect(const AlarmItem(id: '4', hour: 6, minute: 0, days: {1, 2, 3, 4, 5, 6, 7}).repeatSummary(), 'Every day');
      expect(const AlarmItem(id: '5', hour: 6, minute: 0, days: {1, 3, 5}).repeatSummary(), 'Mon Wed Fri');
    });

    test('ring once calculates next occurrence correctly', () {
      // Reference: Wednesday 2026-10-21 14:00
      final now = DateTime(2026, 10, 21, 14, 0);

      // Later today: 18:30
      final alarmLater = const AlarmItem(id: '1', hour: 18, minute: 30, days: {});
      expect(alarmLater.nextOccurrence(now), DateTime(2026, 10, 21, 18, 30));

      // Earlier today: 08:00 -> rolls to tomorrow
      final alarmEarlier = const AlarmItem(id: '2', hour: 8, minute: 0, days: {});
      expect(alarmEarlier.nextOccurrence(now), DateTime(2026, 10, 22, 8, 0));
    });

    test('repeating alarms pick the soonest enabled weekday', () {
      // Wednesday 2026-10-21 14:00 (weekday = 3)
      final now = DateTime(2026, 10, 21, 14, 0);

      // Repeats Tuesdays (2) and Fridays (5) at 09:00
      // Upcoming from Wednesday 14:00 is Friday 2026-10-23 09:00
      final alarm = const AlarmItem(id: '1', hour: 9, minute: 0, days: {2, 5});
      expect(alarm.nextOccurrence(now), DateTime(2026, 10, 23, 9, 0));
    });
  });

  group('AlarmManager plan computation', () {
    test('computes earliest plan among multiple active alarms', () {
      final manager = AlarmManager();
      final now = DateTime(2026, 10, 21, 10, 0);

      // Alarm A: tomorrow at 06:00
      final alarmA = const AlarmItem(id: 'a', hour: 6, minute: 0, days: {});
      // Alarm B: today at 15:00
      final alarmB = const AlarmItem(id: 'b', hour: 15, minute: 0, days: {});
      // Alarm C (disabled): today at 12:00
      final alarmC = const AlarmItem(id: 'c', hour: 12, minute: 0, enabled: false, days: {});

      manager.debugSetAlarms([alarmA, alarmB, alarmC]);

      final plan = manager.computeNextArmedPlan(now);
      expect(plan, isNotNull);
      expect(plan!.sourceAlarm?.id, 'b');
      expect(plan.time, DateTime(2026, 10, 21, 15, 0));
      expect(plan.isFromSystemClock, false);
    });

    test('system alarm is chosen when earlier and sync is enabled', () {
      final manager = AlarmManager();
      final now = DateTime(2026, 10, 21, 10, 0);

      // User alarm: today at 17:00
      final userAlarm = const AlarmItem(id: 'u', hour: 17, minute: 0, days: {});
      manager.debugSetAlarms([userAlarm]);

      // System alarm: today at 14:00
      manager.debugSetSystemAlarm(
        syncEnabled: true,
        systemTime: DateTime(2026, 10, 21, 14, 0),
      );

      final plan = manager.computeNextArmedPlan(now);
      expect(plan, isNotNull);
      expect(plan!.isFromSystemClock, true);
      expect(plan.time, DateTime(2026, 10, 21, 14, 0));
    });
  });
}
