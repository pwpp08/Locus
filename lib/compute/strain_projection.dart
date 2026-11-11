// Where today's strain usually goes from here: the minutes left in the day,
// priced off the days before it.

import 'whoop_scores.dart' show whoopLoadForStrain, whoopStrainFromLoad;

/// Today's strain from minute [now] to the end of the day, one value per
/// minute (index 0 is [now]), or null when it cannot be said.
///
/// [today] is today's running curve and [before] earlier days' whole curves,
/// one cumulative 0–21 value per minute of the day. Each earlier day gives the
/// load it gained after [now]; the mean of those gains goes on top of today's
/// load so far. The sum is taken in load, not in strain: strain is a log of
/// load, so an easy day's +3 is not a hard day's +3.
///
/// Null when [now] is not inside the day, today has no value at [now], or
/// fewer than [minDays] earlier days cover the whole day.
List<double>? projectStrain(
  List<double?> today,
  int now,
  List<List<double?>> before, {
  int minDays = 3,
}) {
  final n = today.length;
  if (now < 0 || now >= n - 1) return null;
  final base = today[now];
  if (base == null) return null;
  final gain = List<double>.filled(n - now, 0);
  var days = 0;
  for (final d in before) {
    if (d.length != n || d.sublist(now).any((v) => v == null)) continue;
    final from = whoopLoadForStrain(d[now]!);
    for (var m = now; m < n; m++) {
      gain[m - now] += whoopLoadForStrain(d[m]!) - from;
    }
    days++;
  }
  if (days < minDays) return null;
  final load = whoopLoadForStrain(base);
  return [
    for (final g in gain) whoopStrainFromLoad(load + g / days),
  ];
}
