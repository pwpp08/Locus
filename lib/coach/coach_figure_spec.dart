// Between the model's `render` call and the figure on screen.
//
// The numbers in a chart come from the app, not from the model's retelling of
// them: a figure names a query and its columns and the rows are read here. The
// finished spec is what gets saved, so an old chat still draws after the rows
// are gone. Anything that cannot be drawn honestly goes back to the model as a
// reason, which it can act on, instead of reaching the user as a blank card.

const _seriesTypes = {'line', 'area', 'bar', 'multi_series', 'lanes'};
const _annotated = {'line', 'area', 'bar', 'multi_series'};
const _aliases = {
  'bars': 'bar',
  'dual_axis': 'lanes',
  'stacked_zone_bar': 'zone_bar',
};
const figureTypes = [
  'line',
  'area',
  'bar',
  'multi_series',
  'lanes',
  'hypnogram',
  'zone_bar',
  'gauge',
  'kpi_grid',
  'heatmap',
  'table',
];

const _maxQueries = 12;
const _maxMarkers = 3;

/// The JSON-schema properties of the `render` tool. One flat object with the
/// type as an enum: `oneOf` per type is rejected or ignored by several
/// OpenAI-compatible providers, so the per-type rules live in [FigureBook.prepare].
const Map<String, dynamic> figureProperties = {
  'type': {'type': 'string', 'enum': figureTypes},
  'title': {'type': 'string'},
  'note': {'type': 'string'},
  'unit': {'type': 'string'},
  'data': {
    'type': 'object',
    'description': 'Where a line, area, bar, multi_series, lanes or table '
        'gets its values: a run_sql query_id and its column names.',
    'properties': {
      'query': {'type': 'integer'},
      'x': {'type': 'string', 'description': 'Column for the x axis.'},
      'y': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Columns to plot.',
      },
      'names': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Legend names, one per y column.',
      },
      'columns': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Table only: columns to show.',
      },
    },
    'required': ['query'],
  },
  'baseline': {
    'type': 'object',
    'description': 'A dashed reference line.',
    'properties': {
      'value': {'type': 'number'},
      'label': {'type': 'string'},
    },
    'required': ['value', 'label'],
  },
  'normal_range': {
    'type': 'object',
    'description': "A shaded band of the person's own usual range.",
    'properties': {
      'min': {'type': 'number'},
      'max': {'type': 'number'},
      'label': {'type': 'string'},
    },
    'required': ['min', 'max', 'label'],
  },
  'markers': {
    'type': 'array',
    'description': 'Up to three events, each at an existing x value.',
    'items': {
      'type': 'object',
      'properties': {
        'x': {'type': 'string'},
        'label': {'type': 'string'},
      },
      'required': ['x', 'label'],
    },
  },
  'x_labels': {
    'type': 'array',
    'items': {'type': 'string'},
  },
  'series': {
    'type': 'array',
    'items': {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'values': {
          'type': 'array',
          'items': {
            'type': ['number', 'null'],
          },
        },
      },
    },
  },
  'segments': {
    'type': 'array',
    'description': 'hypnogram: start and end in epoch seconds, stage is '
        'wake, light, deep or rem.',
    'items': {
      'type': 'object',
      'properties': {
        'start': {'type': 'number'},
        'end': {'type': 'number'},
        'stage': {'type': 'string'},
      },
    },
  },
  'zones': {
    'type': 'array',
    'description': 'zone_bar: five numbers, minutes in HR zones 1 to 5.',
    'items': {'type': 'number'},
  },
  'value': {'type': 'number', 'description': 'gauge: the number.'},
  'min': {'type': 'number', 'description': 'gauge: bottom of the scale.'},
  'max': {'type': 'number', 'description': 'gauge: top of the scale.'},
  'label': {'type': 'string', 'description': 'gauge: what it measures.'},
  'cards': {
    'type': 'array',
    'description': 'kpi_grid: two to four headline numbers.',
    'items': {
      'type': 'object',
      'properties': {
        'label': {'type': 'string'},
        'value': {'type': 'string'},
        'unit': {'type': 'string'},
        'baseline': {'type': 'string'},
      },
    },
  },
  'weeks': {
    'type': 'array',
    'description': 'heatmap: rows of seven numbers, Monday to Sunday, null '
        'for a day with no data.',
    'items': {
      'type': 'array',
      'items': {
        'type': ['number', 'null'],
      },
    },
  },
  'columns': {
    'type': 'array',
    'items': {'type': 'string'},
  },
  'rows': {
    'type': 'array',
    'items': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
};

class _Reject implements Exception {
  final String why;
  const _Reject(this.why);
}

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}');
final _numberRe = RegExp(r'\d+(?:\.\d+)?');

double? _number(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v.trim());
  return null;
}

List<dynamic> _list(dynamic v) {
  if (v is List) return v;
  if (v is Map && v['item'] is List) return v['item'] as List;
  if (v is Map && v['items'] is List) return v['items'] as List;
  return const [];
}

/// The query rows and tool numbers of one conversation.
class FigureBook {
  final _queries = <int, List<Map<String, Object?>>>{};
  final _seen = <double>{};
  var _nextId = 1;

  void clear() {
    _queries.clear();
    _seen.clear();
  }

  /// Records a tool's output as something a figure may quote. Returns it as-is.
  String note(String toolResult) {
    for (final m in _numberRe.allMatches(toolResult)) {
      _seen.add(double.parse(m.group(0)!));
    }
    return toolResult;
  }

  /// Keeps [rows] and adds their `query_id` to the JSON object [out].
  String noteQuery(String out, List<Map<String, Object?>>? rows) {
    note(out);
    if (rows == null || !out.startsWith('{')) return out;
    final id = _nextId++;
    _queries[id] = rows;
    if (_queries.length > _maxQueries) _queries.remove(_queries.keys.first);
    return '{"query_id":$id,${out.substring(1)}';
  }

  // ponytail: matches a number anywhere in what was fetched, at the figure's
  // own precision, so a small invented integer can still collide with a real
  // one. It catches arithmetic and invention at scale; a bound `data` block is
  // the actual guarantee.
  bool _wasFetched(double v) {
    final abs = v.abs();
    final text = abs == abs.roundToDouble() ? '' : abs.toString();
    final decimals = text.isEmpty ? 0 : text.length - text.indexOf('.') - 1;
    final want = abs.toStringAsFixed(decimals);
    return _seen.any((n) => n.toStringAsFixed(decimals) == want);
  }

  void _requireFetched(double v, String what) {
    if (!_wasFetched(v)) {
      throw _Reject(
        '$what $v is not in any data you fetched. Compute it with run_sql, '
        'then use that result.',
      );
    }
  }

  /// The drawable spec, or the reason the model should fix it.
  ({Map<String, dynamic>? spec, String? error}) prepare(
    Map<String, dynamic> args,
  ) {
    try {
      return (spec: _prepare(args), error: null);
    } on _Reject catch (e) {
      return (spec: null, error: 'Figure not drawn: ${e.why}');
    }
  }

  Map<String, dynamic> _prepare(Map<String, dynamic> args) {
    final raw = '${args['type'] ?? ''}'.trim().toLowerCase();
    final type = _aliases[raw] ?? raw;
    if (!figureTypes.contains(type)) {
      throw _Reject(
        'unknown type "$raw". Choose one of ${figureTypes.join(', ')}.',
      );
    }
    final spec = Map<String, dynamic>.from(args)..['type'] = type;
    final data = spec.remove('data');
    if (data is Map) {
      if (type == 'table') {
        _bindTable(spec, data);
      } else if (_seriesTypes.contains(type)) {
        _bindSeries(spec, data, type);
      } else {
        throw _Reject('$type does not take a data block.');
      }
    } else if (_seriesTypes.contains(type)) {
      _checkInlineSeries(spec);
    }
    if (_seriesTypes.contains(type)) _checkSeriesShape(spec, type);
    _checkPayload(spec, type);
    _checkAnnotations(spec, type);
    return spec;
  }

  List<Map<String, Object?>> _rowsOf(Map data) {
    final id = _number(data['query'])?.toInt();
    final rows = id == null ? null : _queries[id];
    if (rows == null) {
      throw const _Reject(
        'that query_id is no longer available. Run the query again.',
      );
    }
    if (rows.isEmpty) {
      throw const _Reject(
        'the query returned no rows. Tell the user there is no data for this.',
      );
    }
    return rows;
  }

  void _requireColumn(List<Map<String, Object?>> rows, String column) {
    if (!rows.first.containsKey(column)) {
      throw _Reject(
        'no column "$column". The columns are '
        '${rows.first.keys.join(', ')}.',
      );
    }
  }

  void _bindSeries(Map<String, dynamic> spec, Map data, String type) {
    var rows = _rowsOf(data);
    final x = '${data['x'] ?? ''}';
    final ys = data['y'] is String
        ? ['${data['y']}']
        : [for (final e in _list(data['y'])) '$e'];
    if (x.isEmpty || ys.isEmpty) {
      throw const _Reject('data needs an x column and at least one y column.');
    }
    _requireColumn(rows, x);
    for (final y in ys) {
      _requireColumn(rows, y);
    }
    if (type == 'bar' && ys.length > 1) {
      throw const _Reject('bar takes one y column. Use multi_series for more.');
    }
    if (type == 'lanes' && ys.length > 3) {
      throw const _Reject('lanes takes at most three y columns.');
    }
    // A query's ORDER BY date DESC must not draw time running backwards.
    if (rows.every((r) => _dateRe.hasMatch('${r[x]}'))) {
      rows = [...rows]
        ..sort((a, b) => '${a[x]}'.compareTo('${b[x]}'));
    }
    final names = [for (final e in _list(data['names'])) '$e'];
    spec['x_labels'] = [for (final r in rows) '${r[x] ?? ''}'];
    spec['series'] = [
      for (var i = 0; i < ys.length; i++)
        {
          'name': i < names.length && names[i].isNotEmpty ? names[i] : ys[i],
          'values': [for (final r in rows) _cell(r[ys[i]], ys[i])],
        },
    ];
  }

  double? _cell(Object? v, String column) {
    if (v == null) return null;
    final n = _number(v);
    if (n == null) throw _Reject('column "$column" is not numeric.');
    return n;
  }

  void _bindTable(Map<String, dynamic> spec, Map data) {
    final rows = _rowsOf(data);
    final asked = [for (final e in _list(data['columns'])) '$e'];
    final columns = asked.isEmpty ? rows.first.keys.toList() : asked;
    for (final c in columns) {
      _requireColumn(rows, c);
    }
    String text(Object? v) {
      if (v == null) return '—';
      if (v is double && v != v.roundToDouble()) {
        return v.toStringAsFixed(1);
      }
      if (v is double) return v.round().toString();
      return '$v';
    }

    spec['columns'] = columns;
    spec['rows'] = [
      for (final r in rows) [for (final c in columns) text(r[c])],
    ];
  }

  void _checkInlineSeries(Map<String, dynamic> spec) {
    for (final s in _list(spec['series']).whereType<Map>()) {
      for (final e in _list(s['values'])) {
        final v = _number(e);
        if (v == null) continue;
        if (!_wasFetched(v)) {
          throw _Reject(
            'the value $v is not in any data you fetched. Plot a run_sql '
            'result through the data block.',
          );
        }
      }
    }
  }

  void _checkSeriesShape(Map<String, dynamic> spec, String type) {
    final series = _list(spec['series']).whereType<Map>().toList();
    bool drawable(Map s) => _list(s['values']).any((v) => _number(v) != null);
    if (series.isEmpty || !series.any(drawable)) {
      throw const _Reject(
        'there are no values to plot. Use the data block, or tell the user '
        'there is no data.',
      );
    }
    final labels = _list(spec['x_labels']);
    for (final s in series) {
      final n = _list(s['values']).length;
      if (labels.isNotEmpty && labels.length != n) {
        throw _Reject(
          'x_labels has ${labels.length} entries but "${s['name']}" has $n.',
        );
      }
      if (n < 2 && type != 'bar') {
        throw const _Reject(
          'one point is not a line. Use bar, gauge or kpi_grid.',
        );
      }
    }
  }

  void _checkPayload(Map<String, dynamic> spec, String type) {
    switch (type) {
      case 'hypnogram':
        final segs = _list(spec['segments']).whereType<Map>();
        if (segs.isEmpty ||
            segs.any(
              (s) =>
                  _number(s['start']) == null ||
                  _number(s['end']) == null ||
                  s['stage'] == null,
            )) {
          throw const _Reject(
            'hypnogram needs segments, each with start, end and stage.',
          );
        }
      case 'zone_bar':
        if (_list(spec['zones'] ?? spec['values']).length < 2 &&
            _list(spec['series']).isEmpty) {
          throw const _Reject('zone_bar needs zones: five numbers.');
        }
      case 'gauge':
        final v = _number(spec['value']);
        final lo = _number(spec['min']) ?? 0, hi = _number(spec['max']) ?? 100;
        if (v == null) throw const _Reject('gauge needs a numeric value.');
        if (hi <= lo) throw const _Reject('gauge max must be above min.');
      case 'kpi_grid':
        final cards = _list(spec['cards']).whereType<Map>();
        if (cards.isEmpty ||
            cards.any((c) => c['label'] == null || c['value'] == null)) {
          throw const _Reject(
            'kpi_grid needs cards, each with a label and a value.',
          );
        }
      case 'heatmap':
        if (_list(spec['weeks'] ?? spec['values']).isEmpty) {
          throw const _Reject('heatmap needs weeks: rows of seven numbers.');
        }
      case 'table':
        if (_list(spec['rows']).isEmpty) {
          throw const _Reject(
            'table needs rows. Use the data block, or tell the user there is '
            'no data.',
          );
        }
    }
  }

  void _checkAnnotations(Map<String, dynamic> spec, String type) {
    final present = [
      for (final k in const ['baseline', 'normal_range', 'markers'])
        if (spec[k] != null) k,
    ];
    if (present.isEmpty) return;
    if (!_annotated.contains(type)) {
      throw _Reject('$type does not take ${present.join(', ')}.');
    }
    if (spec['baseline'] case final b?) {
      final v = b is Map ? _number(b['value']) : null;
      if (v == null || b['label'] == null) {
        throw const _Reject('baseline needs a numeric value and a label.');
      }
      _requireFetched(v, 'baseline');
    }
    if (spec['normal_range'] case final r?) {
      final lo = r is Map ? _number(r['min']) : null;
      final hi = r is Map ? _number(r['max']) : null;
      if (lo == null || hi == null || hi <= lo || r['label'] == null) {
        throw const _Reject(
          'normal_range needs a min below its max, and a label.',
        );
      }
      _requireFetched(lo, 'normal_range min');
      _requireFetched(hi, 'normal_range max');
    }
    if (spec['markers'] != null) {
      final labels = [for (final e in _list(spec['x_labels'])) '$e'];
      final markers = _list(spec['markers']).whereType<Map>().toList();
      if (markers.length > _maxMarkers) {
        throw const _Reject('at most three markers fit on a figure.');
      }
      for (final m in markers) {
        if (m['label'] == null || !labels.contains('${m['x']}')) {
          throw _Reject('marker x "${m['x']}" is not one of the x values.');
        }
      }
    }
  }
}
