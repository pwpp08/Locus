// alarm_manager.dart — handles multiple alarms, occurrence scheduling, and system clock sync.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_item.dart';
import '../platform/system_alarm.dart';
import 'alarm_schedule.dart' show AlarmScheduleEntry;

class NextArmedPlan {
  final DateTime time;
  final AlarmItem? sourceAlarm;
  final bool isFromSystemClock;

  const NextArmedPlan({
    required this.time,
    this.sourceAlarm,
    this.isFromSystemClock = false,
  });
}

class AlarmManager extends ChangeNotifier {
  static const String _kAlarmsList = 'alarms_list_v2';
  static const String _kSyncSystem = 'alarm_sync_system';

  List<AlarmItem> _alarms = [];
  bool _syncSystem = false;
  DateTime? _cachedSystemAlarmTime;
  bool _loaded = false;

  List<AlarmItem> get alarms => List.unmodifiable(_alarms);
  bool get syncSystem => _syncSystem;
  DateTime? get systemAlarmTime => _cachedSystemAlarmTime;
  bool get isLoaded => _loaded;

  AlarmManager();

  Future<void> init({List<AlarmScheduleEntry>? legacySchedule}) async {
    final prefs = await SharedPreferences.getInstance();
    _syncSystem = prefs.getBool(_kSyncSystem) ?? false;
    final jsonStr = prefs.getString(_kAlarmsList);

    if (jsonStr != null && jsonStr.isNotEmpty) {
      _alarms = AlarmItem.decodeList(jsonStr);
    } else if (legacySchedule != null && legacySchedule.isNotEmpty) {
      // Migrate from 7-day schedule
      _alarms = _migrateFromLegacy(legacySchedule);
      await _persist();
    } else {
      // Default: sample wake-up alarm
      _alarms = [
        const AlarmItem(
          id: 'default_1',
          hour: 7,
          minute: 0,
          label: 'Wake up',
          enabled: true,
          days: {1, 2, 3, 4, 5}, // Weekdays
        ),
      ];
      await _persist();
    }

    if (_syncSystem) {
      await refreshSystemAlarm();
    }

    _loaded = true;
    notifyListeners();
  }

  static List<AlarmItem> _migrateFromLegacy(List<AlarmScheduleEntry> legacy) {
    // Group days with identical wake times
    final Map<String, List<int>> groups = {};
    for (final entry in legacy) {
      if (!entry.enabled) continue;
      final key = '${entry.hour}:${entry.minute}:${entry.smartWindowMinutes}';
      // entry.weekday in AlarmScheduleEntry is 0=Mon..6=Sun
      final wd = entry.weekday + 1; // map to 1=Mon..7=Sun
      groups.putIfAbsent(key, () => []).add(wd);
    }

    if (groups.isEmpty) {
      return [
        const AlarmItem(
          id: 'migrated_1',
          hour: 7,
          minute: 0,
          label: 'Wake up',
          enabled: false,
          days: {1, 2, 3, 4, 5},
        )
      ];
    }

    final items = <AlarmItem>[];
    int idCounter = 1;
    for (final entry in groups.entries) {
      final parts = entry.key.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final smartMin = int.parse(parts[2]);
      items.add(AlarmItem(
        id: 'migrated_${idCounter++}',
        hour: hour,
        minute: minute,
        label: 'Alarm',
        enabled: true,
        days: entry.value.toSet(),
        smartWindowMinutes: smartMin,
      ));
    }
    return items;
  }

  Future<void> setSyncSystem(bool enabled) async {
    _syncSystem = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSyncSystem, enabled);
    if (enabled) {
      await refreshSystemAlarm();
    } else {
      _cachedSystemAlarmTime = null;
    }
    notifyListeners();
  }

  Future<DateTime?> refreshSystemAlarm() async {
    final info = await SystemAlarmBridge.getNextSystemAlarm();
    _cachedSystemAlarmTime = info?.triggerTime;
    return _cachedSystemAlarmTime;
  }

  Future<void> addAlarm(AlarmItem item) async {
    _alarms.add(item);
    await _persist();
    notifyListeners();
  }

  Future<void> updateAlarm(AlarmItem updated) async {
    final idx = _alarms.indexWhere((a) => a.id == updated.id);
    if (idx != -1) {
      _alarms[idx] = updated;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> toggleAlarm(String id, bool enabled) async {
    final idx = _alarms.indexWhere((a) => a.id == id);
    if (idx != -1) {
      _alarms[idx] = _alarms[idx].copyWith(enabled: enabled);
      await _persist();
      notifyListeners();
    }
  }

  Future<void> deleteAlarm(String id) async {
    _alarms.removeWhere((a) => a.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _alarms.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> onAlarmFired(int firedEpoch) async {
    final firedDt = DateTime.fromMillisecondsSinceEpoch(firedEpoch * 1000);
    var changed = false;
    for (var i = 0; i < _alarms.length; i++) {
      final a = _alarms[i];
      if (a.enabled && a.isOneShot) {
        if (a.hour == firedDt.hour && (a.minute - firedDt.minute).abs() <= 2) {
          _alarms[i] = a.copyWith(enabled: false);
          changed = true;
        }
      }
    }
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAlarmsList, AlarmItem.encodeList(_alarms));
  }

  /// Finds the earliest upcoming alarm occurrence after [now].
  /// Incorporates system alarm if [syncSystem] is true and system alarm is upcoming.
  NextArmedPlan? computeNextArmedPlan(DateTime now) {
    NextArmedPlan? best;

    // Check all user alarms
    for (final alarm in _alarms) {
      if (!alarm.enabled) continue;
      final occ = alarm.nextOccurrence(now);
      if (occ != null) {
        if (best == null || occ.isBefore(best.time)) {
          best = NextArmedPlan(time: occ, sourceAlarm: alarm);
        }
      }
    }

    // Check system alarm
    if (_syncSystem && _cachedSystemAlarmTime != null) {
      final sysTime = _cachedSystemAlarmTime!;
      if (sysTime.isAfter(now)) {
        if (best == null || sysTime.isBefore(best.time)) {
          best = NextArmedPlan(
            time: sysTime,
            isFromSystemClock: true,
          );
        }
      }
    }

    return best;
  }

  @visibleForTesting
  void debugSetAlarms(List<AlarmItem> list) {
    _alarms = List.of(list);
    _loaded = true;
  }

  @visibleForTesting
  void debugSetSystemAlarm({required bool syncEnabled, DateTime? systemTime}) {
    _syncSystem = syncEnabled;
    _cachedSystemAlarmTime = systemTime;
  }
}
