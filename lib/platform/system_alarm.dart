// system_alarm.dart — reads the next scheduled alarm clock from the host OS
// (Android AlarmManager.getNextAlarmClock()), so Whoop can wake with the phone.

import 'dart:io' show Platform;
import 'package:flutter/services.dart';

class SystemAlarmInfo {
  final DateTime triggerTime;
  final String? package;

  const SystemAlarmInfo({
    required this.triggerTime,
    this.package,
  });
}

abstract class SystemAlarmBridge {
  static const MethodChannel _channel = MethodChannel('openstrap/system_alarm');

  /// Reads the next scheduled system alarm clock trigger time, if any.
  /// Returns null if no alarm is scheduled, on non-Android platforms, or on error.
  static Future<SystemAlarmInfo?> getNextSystemAlarm() async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _channel.invokeMethod<Map>('getNextAlarmClock');
      if (res == null) return null;
      final triggerMs = res['triggerTime'] as num?;
      if (triggerMs == null || triggerMs <= 0) return null;
      final dt = DateTime.fromMillisecondsSinceEpoch(triggerMs.toInt());
      return SystemAlarmInfo(
        triggerTime: dt,
        package: res['package'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
