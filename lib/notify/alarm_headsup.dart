// The heads-up before an alarm: "Alarm in 30 minutes", with a button to turn
// today's ring off (exactly Skip once) and two to push it later (today only).
//
// ARMED, not stored: one OS-scheduled one-shot for the next ring of the alarms
// list, re-armed whenever that list changes, after each headless sync and on
// every foreground pass. The buttons act on the list in SharedPreferences, the
// one store the foreground manager, the headless sync and this file all read,
// so they work with the app closed.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_item.dart';
import '../state/alarm_manager.dart';
import '../state/clock_format.dart' show formatClockOf;
import '../sync/background_sync.dart' show runHeadlessSync;
import 'notification_service.dart';

/// How long before the ring the heads-up lands.
const int kAlarmHeadsUpMin = 30;

const String kAlarmHeadsUpCategory = 'alarm_headsup';
const String kAlarmActionSkip = 'alarm_skip';
const String kAlarmActionPlus15 = 'alarm_plus15';
const String kAlarmActionPlus30 = 'alarm_plus30';

/// The payload of a heads-up: which alarm it is for.
String alarmHeadsUpPayload(String alarmId) => 'alarm_headsup:$alarmId';

String? alarmIdFromPayload(String? payload) {
  const p = 'alarm_headsup:';
  return payload != null && payload.startsWith(p) && payload.length > p.length
      ? payload.substring(p.length)
      : null;
}

/// The minutes an action moves the ring, or null for the skip (and for an
/// action that is not ours).
int? alarmActionMinutes(String actionId) => switch (actionId) {
      kAlarmActionPlus15 => 15,
      kAlarmActionPlus30 => 30,
      _ => null,
    };

/// [storedJson] (the alarms list) after [actionId] on alarm [alarmId] at
/// [now]; null when the action is not ours, the alarm is gone, or nothing is
/// ahead to change.
String? applyAlarmAction(
    String storedJson, String actionId, String alarmId, DateTime now) {
  if (actionId != kAlarmActionSkip && alarmActionMinutes(actionId) == null) {
    return null;
  }
  final alarms = AlarmItem.decodeList(storedJson);
  final i = alarms.indexWhere((a) => a.id == alarmId);
  if (i == -1) return null;
  final minutes = alarmActionMinutes(actionId);
  final changed = minutes == null
      ? alarms[i].skippedNext(now)
      : alarms[i].delayedNext(minutes, now);
  if (changed == null) return null;
  alarms[i] = changed;
  return AlarmItem.encodeList(alarms);
}

/// The alarm that rings next and when: our own alarms only (the phone's own
/// next alarm is not ours to skip).
({AlarmItem alarm, DateTime at})? nextOwnRing(
    List<AlarmItem> alarms, DateTime now) {
  ({AlarmItem alarm, DateTime at})? best;
  for (final a in alarms) {
    final at = a.nextOccurrence(now);
    if (at != null && (best == null || at.isBefore(best.at))) {
      best = (alarm: a, at: at);
    }
  }
  return best;
}

/// Arms the heads-up for the next ring in [storedJson], or cancels it when
/// there is none, or it is already inside [kAlarmHeadsUpMin] minutes.
Future<void> armAlarmHeadsUp(NotificationService svc, String? storedJson,
    {DateTime? now}) async {
  final t = now ?? DateTime.now();
  await svc.cancel(NotificationService.idAlarmHeadsUp);
  if (storedJson == null || storedJson.isEmpty) return;
  final next = nextOwnRing(AlarmItem.decodeList(storedJson), t);
  if (next == null) return;
  final at = next.at.subtract(const Duration(minutes: kAlarmHeadsUpMin));
  if (!at.isAfter(t)) return;
  final label = next.alarm.label.trim();
  await svc.scheduleAlarmHeadsUp(
    at: at,
    title: 'Alarm in $kAlarmHeadsUpMin minutes',
    body: label.isEmpty || label == 'Alarm'
        ? formatClockOf(next.at)
        : '${formatClockOf(next.at)} · $label',
    payload: alarmHeadsUpPayload(next.alarm.id),
  );
}

/// Set by the app's main isolate: after a button changed the stored list,
/// reload the live manager (which re-arms the band). Null in a background
/// isolate, which has no manager and re-arms the band headlessly instead.
Future<void> Function()? onAlarmListChangedByAction;

/// Set by the background entry: re-arm the band from the stored list with no
/// foreground app (the headless sync's own pass).
Future<void> Function()? headlessRearm;

/// Runs one button. Foreground and background alike.
Future<void> handleAlarmHeadsUpAction(NotificationResponse r) async {
  try {
    final id = alarmIdFromPayload(r.payload);
    final action = r.actionId;
    if (id == null || action == null || action.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final stored = prefs.getString(AlarmManager.kAlarmsList);
    if (stored == null) return;
    final updated = applyAlarmAction(stored, action, id, DateTime.now());
    if (updated == null) return;
    await prefs.setString(AlarmManager.kAlarmsList, updated);
    final live = onAlarmListChangedByAction;
    if (live != null) {
      await live();
    } else {
      await headlessRearm?.call();
    }
    final svc = NotificationService.instance;
    await svc.init();
    await armAlarmHeadsUp(svc, updated);
  } catch (e) {
    debugPrint('[alarm] heads-up action failed: $e');
  }
}

/// The entry the plugin starts in its own isolate when a button is pressed
/// with the app closed.
@pragma('vm:entry-point')
Future<void> alarmHeadsUpBackground(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  // No live manager here: the band is re-armed by a headless sync pass, which
  // reads the stored list. It skips itself when the foreground owns the band.
  headlessRearm = () async {
    await runHeadlessSync().timeout(const Duration(seconds: 60));
  };
  await handleAlarmHeadsUpAction(r);
}
