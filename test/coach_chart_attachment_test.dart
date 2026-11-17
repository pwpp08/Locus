// An attached chart: the model gets the whole series and its reading; the
// chat gets the same series as a figure; an absent day stays absent.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_chart_attachment.dart';

void main() {
  String day(int i) {
    final d = DateTime(2026, 10, 19 + i);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  CoachChartAttachment hrv({bool zeroFill = false}) => CoachChartAttachment(
        metricId: 'hrv',
        title: 'Heart rate variability',
        unit: 'ms',
        higherBetter: true,
        from: day(0),
        to: day(29),
        // Rising by one a day, day 5 missing, and one value out of range.
        daily: {
          for (var i = 0; i < 30; i++)
            if (i != 5) day(i): 50.0 + i,
          day(-3): 10.0,
        },
        format: (v) => v.round().toString(),
        zeroFill: zeroFill,
        firstDay: day(0),
      );

  test('the model reads the series, its spread, its trend and its days', () {
    final t = hrv().toModelText();
    expect(t, contains('ATTACHED CHART: Heart rate variability (ms)'));
    expect(t, contains('Higher is better.'));
    expect(t, contains('Days with a value: 29 of 30.'));
    expect(t, contains('Latest: 79 ms on ${day(29)}'));
    expect(t, contains('Lowest 50 ms on ${day(0)}'));
    expect(t, contains('Trend: +7 a week'));
    expect(t, contains('Average by weekday'));
    expect(t, contains('${day(4)} '));
    // A missing day is not listed, and nothing from outside the range is.
    expect(t, isNot(contains('${day(5)} ')));
    expect(t, isNot(contains(day(-3))));
  });

  test('the figure keeps the gap and marks the usual range', () {
    final f = hrv().toFigure();
    final values = (f['series'] as List).first['values'] as List;
    expect(values, hasLength(30));
    expect(values[5], isNull);
    expect(f['type'], 'bar');
    expect(f['normal_range'], isA<Map>());
  });

  test('a metric whose empty day is a real zero gets its zeros', () {
    expect(hrv(zeroFill: true).daily[day(5)], 0);
  });

  test('nothing in range says so', () {
    final a = CoachChartAttachment(
      metricId: 'steps',
      title: 'Steps',
      from: day(0),
      to: day(6),
      daily: const {},
      format: (v) => '$v',
    );
    expect(a.isEmpty, isTrue);
    expect(a.toModelText(), contains('No values in this range.'));
  });
}
