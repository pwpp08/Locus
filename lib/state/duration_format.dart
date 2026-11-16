/// The one way the app writes a length of time under a day: "56m", "7h 05m".
/// Stopwatch readings (a workout's 1:02:15) are a different thing and stay
/// clock-style.
String durationText(num minutes) {
  final m = minutes.round().abs();
  final s = m < 60
      ? '${m}m'
      : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  return minutes < 0 ? '−$s' : s;
}
