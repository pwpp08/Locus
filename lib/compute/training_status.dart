// training_status.dart — the last week's training in one word: detraining,
// recovering, maintaining, productive or overreaching. It is the load ratio
// (the last week's load over the last six weeks') read together with how the body is
// taking it (the week's HRV against its usual range).
//
// Nothing is filled in. Without a load ratio, or with under three weeks of
// strain behind the 28-day norm, there is no status. HRV is optional: without
// it the status is the load's alone and says so.
//
// ponytail: the bands are the usual acute:chronic ones (under .8 falling off,
// .8 to 1.0 holding, 1.0 to 1.3 building, past 1.3 too much at once) and one
// standard deviation of HRV as "taking it badly". None is fitted to this
// user. A metric, so it belongs in the analytics repo; it lives here as
// training_readiness.dart does. Nothing is persisted, so no kAlgoVersion bump
// rides on it.

enum TrainingStatus { detraining, recovering, maintaining, productive, overreaching }

/// Days of strain, out of the last 28, a status needs behind it.
const int kStatusMinDays = 21;

class TrainingStatusResult {
  /// Null when there is not enough behind it to say.
  final TrainingStatus? status;

  /// Acute over chronic load, when both are stored.
  final double? ratio;

  /// The week's HRV in standard deviations from its usual, when known.
  final double? hrvZ;

  /// Days of strain found in the last 28.
  final int days;
  const TrainingStatusResult({
    required this.status,
    required this.ratio,
    required this.hrvZ,
    required this.days,
  });
}

/// [acute] and [chronic] are today's stored loads, [ratioWeekAgo] the same
/// ratio seven days back (null when not stored), [hrv7] the last week's mean
/// HRV against [hrvBase], and [days] how many of the last 28 days have strain.
TrainingStatusResult trainingStatus({
  required double? acute,
  required double? chronic,
  required int days,
  double? ratioWeekAgo,
  double? hrv7,
  ({double mean, double sd})? hrvBase,
}) {
  final ratio =
      acute == null || chronic == null || chronic <= 0 ? null : acute / chronic;
  final z = hrv7 == null || hrvBase == null || hrvBase.sd <= 0
      ? null
      : (hrv7 - hrvBase.mean) / hrvBase.sd;
  TrainingStatus? status;
  if (ratio != null && days >= kStatusMinDays) {
    final strained = z != null && z < -1;
    if (ratio > 1.3 || (ratio > 1.1 && strained)) {
      status = TrainingStatus.overreaching;
    } else if (ratio > 1.0) {
      // Building, but the body is not keeping up: that is holding, not gain.
      status = strained ? TrainingStatus.maintaining : TrainingStatus.productive;
    } else if (ratio >= .8) {
      status = TrainingStatus.maintaining;
    } else {
      // Easing off after a week above the norm is recovery; otherwise the
      // load is simply falling away.
      status = ratioWeekAgo != null && ratioWeekAgo > 1.0
          ? TrainingStatus.recovering
          : TrainingStatus.detraining;
    }
  }
  return TrainingStatusResult(status: status, ratio: ratio, hrvZ: z, days: days);
}
