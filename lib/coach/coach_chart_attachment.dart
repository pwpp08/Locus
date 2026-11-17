// A chart the person attaches to a coach message: one metric's daily values
// over a range, as the app itself computes them for Trend View.
//
// The model gets the whole series plus the reading of it a person would make
// at a glance (where it sits, which way it goes, the best and worst days, how
// the last week compares, a weekday pattern), so it can answer "why is this
// dropping?" from the numbers instead of guessing. The chat shows the same
// series as a figure. Absent days stay absent: no value is filled in, except
// for a metric where a day without any is a real zero.

import 'dart:math' as math;

import '../data/day_label.dart';

/// The ranges a chart can be attached over, in days.
const kCoachChartRanges = <(int, String)>[
  (7, '7 days'),
  (30, '30 days'),
  (91, '3 months'),
  (182, '6 months'),
];

/// Charts one message can carry.
const int kCoachMaxCharts = 3;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _shift(String day, int by) {
  final d = DateTime.parse(day);
  return dayLabelOf(DateTime(d.year, d.month, d.day + by, 12));
}

String _weekday(String day) => _weekdays[DateTime.parse(day).weekday - 1];

String _short(String day) {
  final d = DateTime.parse(day);
  return '${d.day} ${_months[d.month - 1]}';
}

double _median(List<double> s) {
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double _quantile(List<double> sorted, double q) {
  final pos = (sorted.length - 1) * q;
  final lo = pos.floor(), hi = pos.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

class CoachChartAttachment {
  final String metricId;
  final String title;

  /// Written after a value; null when it has none.
  final String? unit;

  /// True up is good, false down is good, null neither.
  final bool? higherBetter;

  /// What the metric is, in the app's own words.
  final String? about;

  /// The first and last day of the range, local labels.
  final String from, to;

  /// The values per day, only the days that have one.
  final Map<String, double> daily;

  /// How a value is written, as the app writes it.
  final String Function(double) format;

  /// Drawn as a line rather than a column per day.
  final bool line;

  CoachChartAttachment({
    required this.metricId,
    required this.title,
    required this.from,
    required this.to,
    required Map<String, double> daily,
    required this.format,
    this.unit,
    this.higherBetter,
    this.about,
    this.line = false,
    bool zeroFill = false,
    String? firstDay,
  }) : daily = _inRange(daily, from, to, zeroFill, firstDay);

  static Map<String, double> _inRange(Map<String, double> all, String from,
      String to, bool zeroFill, String? firstDay) {
    final out = <String, double>{};
    for (var d = from; d.compareTo(to) <= 0; d = _shift(d, 1)) {
      final v = all[d] ??
          (zeroFill && firstDay != null && d.compareTo(firstDay) >= 0
              ? 0.0
              : null);
      if (v != null && v.isFinite) out[d] = v;
    }
    return out;
  }

  /// The days of the range, in order.
  List<String> get days => [
        for (var d = from; d.compareTo(to) <= 0; d = _shift(d, 1)) d,
      ];

  bool get isEmpty => daily.isEmpty;

  String get rangeLabel {
    final n = days.length;
    for (final (d, label) in kCoachChartRanges) {
      if (d == n) return label;
    }
    return '$n days';
  }

  String _v(double v) => unit == null ? format(v) : '${format(v)} $unit';

  /// The block the model reads.
  String toModelText() {
    final all = days;
    final b = StringBuffer()
      ..writeln('--- ATTACHED CHART: $title${unit == null ? '' : ' ($unit)'}, '
          '$from to $to (${all.length} days) ---');
    if (higherBetter != null) {
      b.writeln(higherBetter! ? 'Higher is better.' : 'Lower is better.');
    }
    if (about != null) b.writeln('About: $about');
    b.writeln('Days with a value: ${daily.length} of ${all.length}.');
    if (daily.isEmpty) {
      b.writeln('No values in this range.');
      return b.toString();
    }
    final entries = daily.entries.toList(); // in day order
    final xs = [for (final e in entries) e.value];
    final sorted = [...xs]..sort();
    final mean = xs.reduce((a, c) => a + c) / xs.length;
    final sd = xs.length < 2
        ? 0.0
        : math.sqrt(xs.fold(0.0, (a, c) => a + (c - mean) * (c - mean)) /
            (xs.length - 1));
    final last = entries.last;
    b.writeln('Latest: ${_v(last.value)} on ${last.key} (${_weekday(last.key)}).');
    b.writeln('Average ${format(mean)}, median ${format(_median(sorted))}, '
        'spread (SD) ${format(sd)}.');
    if (xs.length >= 7) {
      b.writeln('Usual range (middle half of these days): '
          '${format(_quantile(sorted, .25))} to ${format(_quantile(sorted, .75))}.');
    }
    final lo = entries.reduce((a, c) => c.value < a.value ? c : a);
    final hi = entries.reduce((a, c) => c.value > a.value ? c : a);
    b.writeln('Lowest ${_v(lo.value)} on ${lo.key} (${_weekday(lo.key)}). '
        'Highest ${_v(hi.value)} on ${hi.key} (${_weekday(hi.key)}).');

    // The slope per week, least squares over the day index.
    if (xs.length >= 5) {
      final index = {for (var i = 0; i < all.length; i++) all[i]: i};
      final ts = [for (final e in entries) index[e.key]!.toDouble()];
      final tm = ts.reduce((a, c) => a + c) / ts.length;
      var num = 0.0, den = 0.0;
      for (var i = 0; i < ts.length; i++) {
        num += (ts[i] - tm) * (xs[i] - mean);
        den += (ts[i] - tm) * (ts[i] - tm);
      }
      if (den > 0) {
        final perWeek = num / den * 7;
        final sign = perWeek > 0 ? '+' : '';
        b.writeln('Trend: $sign${format(perWeek)} a week '
            '(a straight line through the period).');
      }
    }

    // The last week against what came before it.
    if (all.length > 7) {
      final cut = all[all.length - 7];
      final recent = [for (final e in entries) if (e.key.compareTo(cut) >= 0) e.value];
      final before = [for (final e in entries) if (e.key.compareTo(cut) < 0) e.value];
      if (recent.isNotEmpty && before.isNotEmpty) {
        final r = recent.reduce((a, c) => a + c) / recent.length;
        final p = before.reduce((a, c) => a + c) / before.length;
        final d = r - p;
        b.writeln('Last 7 days average ${format(r)} against ${format(p)} '
            'over the ${all.length - 7} days before (${d > 0 ? '+' : ''}${format(d)}).');
      }
    }

    // A weekday pattern needs three weeks of days to mean anything.
    if (xs.length >= 21) {
      final by = <int, List<double>>{};
      for (final e in entries) {
        (by[DateTime.parse(e.key).weekday] ??= []).add(e.value);
      }
      b.writeln('Average by weekday: ${[
        for (var w = 1; w <= 7; w++)
          if (by[w] case final v?)
            '${_weekdays[w - 1]} ${format(v.reduce((a, c) => a + c) / v.length)}',
      ].join(', ')}.');
    }

    b.writeln('Daily values (a day not listed has no reading):');
    for (final e in entries) {
      b.writeln('${e.key} ${_weekday(e.key)}: ${format(e.value)}');
    }
    return b.toString();
  }

  /// The figure the chat draws for it (see `ui2/screens/coach_figures.dart`).
  Map<String, dynamic> toFigure() {
    final all = days;
    final sorted = [...daily.values]..sort();
    return {
      'type': line || all.length > 31 ? 'line' : 'bar',
      'title': '$title · $rangeLabel',
      if (unit != null) 'unit': unit,
      'x_labels': [for (final d in all) _short(d)],
      'series': [
        {
          'name': title,
          'values': [for (final d in all) daily[d]],
        },
      ],
      if (sorted.length >= 7)
        'normal_range': {
          'min': _quantile(sorted, .25),
          'max': _quantile(sorted, .75),
          'label': 'Usual range',
        },
      'attached': true,
    };
  }
}
