// Coach figures draw the app's rows, and refuse what they cannot draw honestly.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_figure_spec.dart';

void main() {
  late FigureBook book;
  const rows = <Map<String, Object?>>[
    {'date': '2026-11-03', 'hrv': 70.5, 'note': 'x'},
    {'date': '2026-11-02', 'hrv': null, 'note': 'y'},
    {'date': '2026-11-01', 'hrv': 60.25, 'note': 'z'},
  ];

  setUp(() => book = FigureBook());

  int query([List<Map<String, Object?>> r = rows]) {
    final out = book.noteQuery('{"columns":[],"rows":[]}', r);
    return int.parse(RegExp(r'"query_id":(\d+)').firstMatch(out)!.group(1)!);
  }

  Map<String, dynamic> line(int id, {String y = 'hrv'}) => {
    'type': 'line',
    'title': 'HRV',
    'data': {
      'query': id,
      'x': 'date',
      'y': [y],
    },
  };

  test('the app fills in the values, oldest first, holes kept', () {
    final spec = book.prepare(line(query())).spec!;
    expect(spec.containsKey('data'), isFalse);
    expect(spec['x_labels'], ['2026-11-01', '2026-11-02', '2026-11-03']);
    expect((spec['series'] as List).single['values'], [60.25, null, 70.5]);
  });

  test('a bad reference comes back as a reason', () {
    final id = query();
    expect(book.prepare(line(id, y: 'nope')).error, contains('date, hrv, note'));
    expect(book.prepare(line(id, y: 'note')).error, contains('not numeric'));
    expect(book.prepare(line(99)).error, contains('Run the query again'));
    expect(book.prepare(line(query(const []))).error, contains('no rows'));
    expect(book.prepare({'type': 'scatter'}).error, contains('unknown type'));
  });

  test('typed-out numbers must have been fetched', () {
    book.note('{"hrv":[61,64]}');
    Map<String, dynamic> inline(List<num> v) => {
      'type': 'line',
      'title': 't',
      'x_labels': ['a', 'b'],
      'series': [
        {'name': 'hrv', 'values': v},
      ],
    };
    expect(book.prepare(inline([61, 64])).spec, isNotNull);
    expect(book.prepare(inline([61, 977])).error, contains('977'));
  });

  test('annotations are checked against the data and the axis', () {
    final id = query();
    book.note('{"avg":65.4}');
    final good = {
      ...line(id),
      'baseline': {'value': 65.4, 'label': 'Average'},
      'markers': [
        {'x': '2026-11-02', 'label': 'Long run'},
      ],
    };
    expect(book.prepare(good).spec, isNotNull);
    expect(
      book.prepare({
        ...line(id),
        'baseline': {'value': 1234, 'label': 'Average'},
      }).error,
      contains('1234'),
    );
    expect(
      book.prepare({
        ...line(id),
        'markers': [
          {'x': '2020-01-01', 'label': 'Old'},
        ],
      }).error,
      contains('x values'),
    );
    expect(
      book.prepare({
        'type': 'gauge',
        'value': 5,
        'baseline': {'value': 65.4, 'label': 'a'},
      }).error,
      contains('does not take'),
    );
  });

  test('a table reads its cells from the query', () {
    final spec = book.prepare({
      'type': 'table',
      'title': 't',
      'data': {
        'query': query(),
        'columns': ['date', 'hrv'],
      },
    }).spec!;
    expect(spec['rows'], [
      ['2026-11-03', '70.5'],
      ['2026-11-02', '—'],
      ['2026-11-01', '60.3'],
    ]);
  });
}
