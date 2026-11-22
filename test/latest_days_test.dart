// Total day stress scores the latest days, counted back from today: counted
// forward from the first day, a long history stopped months before this week
// and the chart said "not enough of a day scored".

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/trend_view.dart';

void main() {
  test('a long history still ends today', () {
    final days = latestDays('2024-01-01', '2026-11-22', 400);
    expect(days, hasLength(400));
    expect(days.last, '2026-11-22');
    expect(days.first, '2025-10-19');
    expect(days, orderedEquals([...days]..sort()));
  });

  test('a short history starts at its first day', () {
    expect(latestDays('2026-11-20', '2026-11-22', 400),
        ['2026-11-20', '2026-11-21', '2026-11-22']);
  });
}
