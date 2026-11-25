// "Woke up to an alarm?" answered from what the band recorded, not asked.
//
// Two facts decide it: when an alarm RANG that morning (the band's fired event,
// kept in a short log, because the single `alarm_fired_at` is overwritten every
// day) and when you were UP (the night's wake time). Pure, so every case is a
// test. Where the facts do not settle it the answer stays open: a question left
// for the person is better than a wrong tick.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'clock_format.dart' show formatClockOf;

/// The log's key, and how many rings it keeps.
const String kAlarmFiredLog = 'alarm_fired_log';
const int kAlarmFiredLogMax = 60;

/// Seconds before the ring that still count as waking to it, and after it.
const int _kBeforeSec = 10 * 60;
const int _kAfterSec = 30 * 60;

/// Hours of the day after midnight in which a ring is that morning's.
const int _kMorningUntilHour = 14;

typedef AlarmWakeAnswer = ({bool woke, String why});

/// The answer for the morning of [dayStart] (epoch seconds, local midnight),
/// from the rings in [firedSec] and the night's [wakeTs]; null when no alarm
/// rang that morning (nothing to say either way).
AlarmWakeAnswer? alarmWakeAnswer({
  required int dayStart,
  required Iterable<int> firedSec,
  int? wakeTs,
}) {
  final from = dayStart;
  final to = dayStart + _kMorningUntilHour * 3600;
  final rang = [
    for (final t in firedSec)
      if (t >= from && t < to) t,
  ]..sort();
  if (rang.isEmpty) return null;
  // The ring that decided the night: the last before you were up, else the first.
  final ring = wakeTs == null
      ? rang.first
      : rang.lastWhere((t) => t <= wakeTs + _kBeforeSec, orElse: () => rang.first);
  String clock(int t) =>
      formatClockOf(DateTime.fromMillisecondsSinceEpoch(t * 1000));
  if (wakeTs == null) {
    return (woke: true, why: 'Your alarm rang at ${clock(ring)}');
  }
  if (wakeTs < ring - _kBeforeSec) {
    return (
      woke: false,
      why: 'You were up at ${clock(wakeTs)}, before the alarm at ${clock(ring)}',
    );
  }
  if (wakeTs > ring + _kAfterSec) {
    return (
      woke: false,
      why: 'The alarm rang at ${clock(ring)} and you slept until ${clock(wakeTs)}',
    );
  }
  return (
    woke: true,
    why: 'Your alarm rang at ${clock(ring)} and you were up by ${clock(wakeTs)}',
  );
}

/// Adds a ring to the stored log (newest last, [kAlarmFiredLogMax] kept).
Future<void> recordAlarmFired(int sec) async {
  final p = await SharedPreferences.getInstance();
  final log = _read(p)..add(sec);
  final kept = (log.toSet().toList()..sort());
  await p.setString(
      kAlarmFiredLog,
      jsonEncode(kept.length > kAlarmFiredLogMax
          ? kept.sublist(kept.length - kAlarmFiredLogMax)
          : kept));
}

Future<List<int>> loadAlarmFired() async {
  final p = await SharedPreferences.getInstance();
  await p.reload();
  return _read(p);
}

List<int> _read(SharedPreferences p) {
  try {
    final j = jsonDecode(p.getString(kAlarmFiredLog) ?? '[]');
    return [for (final v in j as List) (v as num).toInt()];
  } catch (_) {
    return [];
  }
}
