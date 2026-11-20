// watch_step_reference.dart — learn how the phone's step count compares with
// another watch's, and correct the phone's count by it.
//
// The phone pedometer is the app's step sensor on a band with no counter of
// its own (WHOOP 4). Someone who also wears a watch that is better at steps
// (a Galaxy Watch, say) sees the two disagree by a steady share every day. The
// watch's daily totals reach Health Connect through its own app, so they can
// be read back and set beside the phone's count for the same days.
//
// The model is the step counter's: one multiplicative factor, a ratio of sums
// over the days both counted properly, shrunk toward 1.0 and clamped. It is
// stored in `step_calibration` under its own family, and
// `LocalDb.resolvedStepsForDay` scales the phone's spans by it. Nothing is
// invented: a day the phone did not count stays uncounted.

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/day_label.dart';
import '../data/db.dart';
import '../data/step_calibration.dart';
import 'health_read_access.dart';
import 'health_rhr_seed.dart' show isOwnHealthSample;

/// The tightest band a phone-vs-watch factor may take: past it the two were
/// not counting the same day (the watch on the charger, the phone in a
/// drawer), not miscounting it.
const double kPhoneRefFactorMin = 0.7;
const double kPhoneRefFactorMax = 1.3;

/// How many finished days are compared.
const int kPhoneRefLookbackDays = 21;

/// One day both counted: the watch's total and the phone's raw total.
typedef StepRefDay = ({int watch, int phone});

/// A day is used only when both counted a real day and roughly agree on its
/// size; a day one of them half-missed says nothing about the other's error.
@visibleForTesting
bool stepRefDayAdmissible(StepRefDay d) =>
    d.watch >= kStepCalMinReferenceSteps &&
    d.phone >= kStepCalMinReferenceSteps &&
    d.watch / d.phone >= kPhoneRefFactorMin * .8 &&
    d.watch / d.phone <= kPhoneRefFactorMax / .8;

/// The factor that turns the phone's count into the watch's: a ratio of sums
/// over the admitted days, shrunk toward 1.0 by
/// [kStepFactorPriorWeight] pseudo-days and clamped. Uncalibrated (factor 1,
/// no days) under three days.
StepCalibrationProfile estimatePhoneStepReference(List<StepRefDay> days) {
  final ok = days.where(stepRefDayAdmissible).toList(growable: false);
  if (ok.length < 3) {
    return StepCalibrationProfile.uncalibrated(
        kPhoneStepRefFamily, Wearing.wrist);
  }
  final watch = ok.fold<int>(0, (a, d) => a + d.watch);
  final phone = ok.fold<int>(0, (a, d) => a + d.phone);
  final ratio = watch / phone;
  final shrunk = (ok.length * ratio + kStepFactorPriorWeight) /
      (ok.length + kStepFactorPriorWeight);
  return StepCalibrationProfile(
    deviceFamily: kPhoneStepRefFamily,
    wearing: Wearing.wrist,
    factor: shrunk.clamp(kPhoneRefFactorMin, kPhoneRefFactorMax),
    nDays: ok.length,
    version: kStepCalibrationVersion,
  );
}

/// Daily step totals per source app from [points], own samples dropped.
@visibleForTesting
Map<String, Map<String, int>> stepsByDayAndSource(
  List<HealthDataPoint> points,
  String ownId,
) {
  final out = <String, Map<String, int>>{};
  for (final p in points) {
    if (p.type != HealthDataType.STEPS) continue;
    if (isOwnHealthSample(p.sourceId, p.sourceName, ownId)) continue;
    final v = p.value;
    if (v is! NumericHealthValue) continue;
    final src = p.sourceId.isNotEmpty ? p.sourceId : p.sourceName;
    if (src.isEmpty) continue;
    final day = dayLabelOf(p.dateFrom.toLocal());
    final byDay = out.putIfAbsent(src, () => {});
    byDay[day] = (byDay[day] ?? 0) + v.numericValue.round();
  }
  return out;
}

/// Read the last [kPhoneRefLookbackDays] finished days of the other watch's
/// steps out of Health Connect, pair them with the phone's own raw count, and
/// store the factor. Only reads when step access was already granted (never
/// asks); does nothing without a watch. Never throws.
Future<StepCalibrationProfile?> refreshPhoneStepReference({
  Health? health,
  DateTime? now,
}) async {
  try {
    final h = health ?? Health();
    await h.configure();
    final granted = await h.hasPermissions(
      const [HealthDataType.STEPS],
      permissions: const [HealthDataAccess.READ],
    );
    if (granted != true) return null;
    final own = (await PackageInfo.fromPlatform()).packageName;
    if (own.isEmpty) return null;
    final today = now ?? DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final start = DateTime(end.year, end.month, end.day - kPhoneRefLookbackDays);
    final pts = await readEachHealthType(h,
        types: const [HealthDataType.STEPS], start: start, end: end);
    final bySource = stepsByDayAndSource(pts, own);
    if (bySource.isEmpty) return null;
    // The watch: the source that counted the most, which is the one worn.
    final watch = bySource.entries.reduce((a, b) =>
        a.value.values.fold<int>(0, (s, v) => s + v) >=
                b.value.values.fold<int>(0, (s, v) => s + v)
            ? a
            : b);
    final days = <StepRefDay>[];
    for (final e in watch.value.entries) {
      final phone = await LocalDb.phoneStepsForDay(e.key);
      days.add((watch: e.value, phone: phone));
    }
    final profile = estimatePhoneStepReference(days);
    await LocalDb.putStepCalibrationProfile(profile);
    return profile;
  } catch (e) {
    debugPrint('[steps] watch reference: $e');
    return null;
  }
}
