// QUALITY-ADJUSTED SLEEP PERFORMANCE
//
// Pure hours-vs-needed scores a night 100% whenever enough time is spent in bed,
// ignoring fragmented sleep, low efficiency, or depleted restorative stages.
// This calculates a balanced score:
//   Duration (65%) + Sleep Efficiency (20%) + Restorative Sleep (REM + Deep) (15%)
//
// When stages are unavailable, it smoothly degrades to 75% Duration + 25% Efficiency.
// When efficiency is also unavailable, it falls back to 100% Duration.

/// Computes the quality-adjusted sleep performance score (0..100).
double computeAdjustedSleepPerformance({
  required double tstMin,
  required double needMin,
  double? efficiencyPct,
  double? remMin,
  double? deepMin,
}) {
  if (needMin <= 0 || tstMin <= 0) return 0.0;

  final durationScore = (tstMin / needMin * 100.0).clamp(0.0, 100.0);

  // Normalize efficiency to 0..100 if passed as 0..1
  double? eff = efficiencyPct;
  if (eff != null && eff <= 1.0 && eff > 0) {
    eff = eff * 100.0;
  }

  final rem = remMin;
  final deep = deepMin;

  if (eff != null && rem != null && deep != null && tstMin > 0) {
    // 90% efficiency is clinical optimal (score 100). Below 90% scales down to 50 minimum.
    final effScore = (eff / 90.0 * 100.0).clamp(50.0, 100.0);

    // Restorative sleep (REM + Deep) benchmark is 40% of TST (score 100).
    final restorativeRatio = (rem + deep) / tstMin;
    final restorativeScore = (restorativeRatio / 0.40 * 100.0).clamp(50.0, 100.0);

    return (durationScore * 0.65 + effScore * 0.20 + restorativeScore * 0.15)
        .clamp(0.0, 100.0);
  } else if (eff != null) {
    final effScore = (eff / 90.0 * 100.0).clamp(50.0, 100.0);
    return (durationScore * 0.75 + effScore * 0.25).clamp(0.0, 100.0);
  }

  return durationScore;
}
