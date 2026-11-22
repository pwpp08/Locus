// A2UI (Agent-to-User Interface, https://a2ui.org) v1.0 for the coach: the
// model describes a small interface as data (components in a flat list, a
// data model, actions), and the app draws it with its own components.
//
// This file is the protocol half, with no Flutter in it: the tool the model
// calls, checking its messages into ONE surface the chat can keep, reading
// bound values and templated children out of the data model, and building
// the action message a tap sends back. `ui2/screens/coach_a2ui_view.dart`
// draws it.
//
// What is and is not here. The basic catalog's components are understood:
// Text, Image, Icon, Row, Column, List, Card, Tabs, Divider, Modal, Button,
// TextField, CheckBox, ChoicePicker, Slider, DateTimeInput (Video and
// AudioPlayer are refused: there is nothing in a health chat to play). The
// messages a single answer can carry are createSurface, updateComponents and
// updateDataModel, folded into one surface; a surface is not updated from a
// later turn, a new one is sent instead, so a saved chat redraws exactly what
// was shown. The v0.9 spellings models still produce ({"path": …},
// {"literalString": …}, {"explicitList": …}) are read too. Anything that
// cannot be drawn goes back to the model as a reason it can act on, the way
// a figure that cannot be drawn does.

import 'dart:convert';

const kA2uiVersion = '1.0';
const kA2uiCatalog =
    'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json';

/// The components drawn, and what each holds its children in.
const a2uiComponents = {
  'Text',
  'Image',
  'Icon',
  'Row',
  'Column',
  'List',
  'Card',
  'Tabs',
  'Divider',
  'Modal',
  'Button',
  'TextField',
  'CheckBox',
  'ChoicePicker',
  'Slider',
  'DateTimeInput',
};

const _maxComponents = 120;

/// The `show_ui` tool's parameters.
const Map<String, dynamic> a2uiToolProperties = {
  'messages': {
    'type': 'array',
    'description': 'A2UI v1.0 messages, in order: one createSurface (with '
        'its components and dataModel), then optionally updateComponents '
        'and updateDataModel for the same surfaceId.',
    'items': {'type': 'object'},
  },
};

/// What the model is told about the catalog, in the tool's description.
const a2uiToolDescription =
    'Show the person a small native interface (A2UI v1.0, basic catalog) '
    'instead of describing one: choices to pick from, a checklist, a short '
    'form, a plan as cards, options with buttons. Not for charts or data '
    'tables: use render for those. Each message is an object with '
    '"version":"1.0" and one of createSurface {surfaceId, catalogId, '
    'components, dataModel}, updateComponents {surfaceId, components}, '
    'updateDataModel {surfaceId, path, value}. Components are a FLAT list; '
    'exactly one has id "root"; children are referenced by id. '
    'Components: Text{text, variant: h1|h2|h3|h4|h5|body|caption}; '
    'Row/Column{children, justify: start|center|end|spaceBetween|'
    'spaceEvenly, align: start|center|end|stretch}; List{children, '
    'direction: vertical|horizontal}; Card{child}; Divider{}; '
    'Icon{name: check|close|info|warning|star|heart|moon|sun|bolt|'
    'calendar|clock|run|bike|walk|water|food|bed|timer|trophy|flame}; '
    'Image{url (https)}; Button{child (a Text id), variant: '
    'primary|default|borderless, action}; Tabs{tabs: [{title, child}]}; '
    'Modal{trigger, content}; TextField{label, value, variant: '
    'shortText|longText|number}; CheckBox{label, value}; '
    'ChoicePicker{label, options: [{label, value}], value, variant: '
    'mutuallyExclusive|multipleSelection}; Slider{label, min, max, value}; '
    'DateTimeInput{label, value, enableDate, enableTime}. '
    'Bind a value to the data model with {"@path": "/plan/minutes"}; join '
    'text with {"@call": "formatString", "args": {"value": "Hi \${/name}"}}. '
    'Repeat a template over a list: "children": {"path": "/items", '
    '"componentId": "itemRow"}, with relative paths like {"@path": "label"} '
    'inside it. A Button\'s action is {"event": {"name": "chooseWorkout", '
    '"userMessage": "I\'ll do the 30-minute run", "context": {"minutes": '
    '{"@path": "/plan/minutes"}}}}; the tap comes back to you as the '
    'person\'s message followed by the action JSON. Keep it small: a '
    'handful of components that answer the question.';

/// [args] of a `show_ui` call, checked into one surface: the render spec the
/// chat keeps (`type: a2ui`), or the reason it cannot be drawn.
({Map<String, dynamic>? spec, String? error}) prepareA2ui(
    Map<String, dynamic> args) {
  var messages = args['messages'];
  if (messages is String) {
    try {
      messages = jsonDecode(messages);
    } catch (_) {
      return (spec: null, error: 'Not shown: messages is not JSON.');
    }
  }
  // A single message, or the model's {"item": [...]} wrapping.
  if (messages is Map) {
    messages = messages['item'] ?? messages['items'] ?? [messages];
  }
  if (messages is! List || messages.isEmpty) {
    return (spec: null, error: 'Not shown: send a list of A2UI messages, '
        'starting with createSurface.');
  }
  String? surfaceId;
  final components = <String, Map<String, dynamic>>{};
  final order = <String>[];
  Object? data = <String, dynamic>{};
  var sendData = false;
  void addAll(Object? list) {
    if (list is! List) return;
    for (final c in list) {
      if (c is! Map || c['id'] is! String) continue;
      final id = c['id'] as String;
      final m = c.cast<String, dynamic>();
      // v0.9 wrapped a component's props under its type: {"component":
      // {"Text": {...}}}. Flatten it.
      if (m['component'] is Map) {
        final w = (m['component'] as Map).cast<String, dynamic>();
        if (w.length == 1) {
          final e = w.entries.first;
          m
            ..remove('component')
            ..addAll({'component': e.key, ...(e.value as Map).cast<String, dynamic>()});
        }
      }
      if (!components.containsKey(id)) order.add(id);
      components[id] = m;
    }
  }

  for (final raw in messages) {
    if (raw is! Map) continue;
    final m = raw.cast<String, dynamic>();
    final create = m['createSurface'] ?? m['beginRendering'];
    final update = m['updateComponents'] ?? m['surfaceUpdate'];
    final dm = m['updateDataModel'] ?? m['dataModelUpdate'];
    if (create is Map) {
      surfaceId ??= '${create['surfaceId'] ?? 'surface'}';
      addAll(create['components']);
      if (create['dataModel'] is Map) data = create['dataModel'];
      sendData = create['sendDataModel'] == true;
    } else if (update is Map) {
      surfaceId ??= '${update['surfaceId'] ?? 'surface'}';
      addAll(update['components']);
    } else if (dm is Map) {
      final path = '${dm['path'] ?? '/'}';
      data = a2uiSet(data, path, dm['value'] ?? dm['contents']);
    } else if (m['deleteSurface'] != null) {
      return (spec: null, error: 'Not shown: a surface is drawn once in the '
          'chat. Send a new one instead of deleting.');
    }
  }

  final errors = <String>[];
  if (components.isEmpty) errors.add('there are no components');
  if (components.length > _maxComponents) {
    errors.add('${components.length} components is too many; keep it under '
        '$_maxComponents');
  }
  if (!components.containsKey('root')) {
    errors.add('no component has id "root"');
  }
  for (final c in components.values) {
    final type = '${c['component']}';
    if (!a2uiComponents.contains(type)) {
      errors.add('"${c['id']}" is a $type, which this app does not draw '
          '(use one of ${a2uiComponents.join(', ')})');
    }
    for (final ref in a2uiRefs(c)) {
      if (!components.containsKey(ref)) {
        errors.add('"${c['id']}" refers to "$ref", which is not in the list');
      }
    }
  }
  if (errors.isNotEmpty) {
    return (spec: null, error: 'Not shown: ${errors.take(6).join('; ')}.');
  }
  return (
    spec: {
      'type': 'a2ui',
      'surfaceId': surfaceId ?? 'surface',
      'sendDataModel': sendData,
      'components': [for (final id in order) components[id]],
      'dataModel': data,
    },
    error: null,
  );
}

/// The ids a component points at: its children, child, tabs and modal parts.
/// A template's component counts once.
List<String> a2uiRefs(Map<String, dynamic> c) {
  final out = <String>[];
  void one(Object? v) {
    if (v is String) out.add(v);
  }

  final ch = c['children'];
  if (ch is List) {
    ch.forEach(one);
  } else if (ch is Map) {
    one(ch['componentId']);
    if (ch['explicitList'] is List) (ch['explicitList'] as List).forEach(one);
    if (ch['template'] is Map) one((ch['template'] as Map)['componentId']);
  }
  one(c['child']);
  one(c['trigger']);
  one(c['content']);
  if (c['tabs'] is List) {
    for (final t in c['tabs'] as List) {
      if (t is Map) one(t['child']);
    }
  }
  return out;
}

// ── the data model ───────────────────────────────────────────────────────────

List<String> _parts(String pointer) => [
      for (final p in pointer.split('/'))
        if (p.isNotEmpty) p.replaceAll('~1', '/').replaceAll('~0', '~'),
    ];

/// [pointer] made absolute against [scope] (a template item's own path).
String a2uiAbsolute(String pointer, String scope) => pointer.startsWith('/')
    ? pointer
    : '${scope.endsWith('/') ? scope : '$scope/'}$pointer';

/// The value at [pointer] (a JSON Pointer) in [data], or null.
Object? a2uiGet(Object? data, String pointer) {
  var at = data;
  for (final k in _parts(pointer)) {
    if (at is Map) {
      at = at[k];
    } else if (at is List) {
      final i = int.tryParse(k);
      at = i == null || i < 0 || i >= at.length ? null : at[i];
    } else {
      return null;
    }
  }
  return at;
}

/// [data] with [value] written at [pointer]; a null value removes the key.
/// Maps along the way are made as needed. Returns the (possibly new) root.
Object? a2uiSet(Object? data, String pointer, Object? value) {
  final parts = _parts(pointer);
  if (parts.isEmpty) return value ?? <String, dynamic>{};
  final root = data is Map || data is List ? data : <String, dynamic>{};
  Object? at = root;
  for (var i = 0; i < parts.length; i++) {
    final k = parts[i];
    final last = i == parts.length - 1;
    if (at is Map) {
      if (last) {
        if (value == null) {
          at.remove(k);
        } else {
          at[k] = value;
        }
      } else {
        at = at[k] is Map || at[k] is List
            ? at[k]
            : (at[k] = <String, dynamic>{});
      }
    } else if (at is List) {
      final n = int.tryParse(k);
      if (n == null || n < 0) return root;
      while (at.length <= n) {
        at.add(null);
      }
      if (last) {
        at[n] = value;
      } else {
        at = at[n] is Map || at[n] is List ? at[n] : (at[n] = <String, dynamic>{});
      }
    }
  }
  return root;
}

/// The path a bound property writes back to, or null for a literal.
String? a2uiPathOf(Object? v, String scope) {
  if (v is Map) {
    final p = v['@path'] ?? v['path'];
    if (p is String) return a2uiAbsolute(p, scope);
  }
  return null;
}

/// A dynamic value read against [data]: a literal, a {"@path"} binding, a
/// formatString call, or one of v0.9's literal wrappers.
Object? a2uiValue(Object? v, Object? data, {String scope = '/', int index = 0}) {
  if (v is! Map) return v;
  if (v['@path'] is String || (v['path'] is String && v.length == 1)) {
    return a2uiGet(data, a2uiAbsolute('${v['@path'] ?? v['path']}', scope));
  }
  if (v['@call'] == '@index') return index;
  if (v['@call'] == 'formatString') {
    final args = v['args'];
    final tpl = args is Map ? '${args['value'] ?? ''}' : '';
    return tpl.replaceAllMapped(RegExp(r'\$\{([^}]*)\}'), (m) {
      final got = a2uiGet(data, a2uiAbsolute(m.group(1)!.trim(), scope));
      return got == null ? '' : _plain(got);
    });
  }
  for (final k in const [
    'literalString',
    'literalNumber',
    'literalBoolean',
    'literalArray',
  ]) {
    if (v.containsKey(k)) return v[k];
  }
  return v;
}

String _plain(Object v) => v is num && v == v.roundToDouble() && v is! int
    ? v.round().toString()
    : '$v';

/// [v] read as words.
String a2uiText(Object? v, Object? data, {String scope = '/', int index = 0}) {
  final got = a2uiValue(v, data, scope: scope, index: index);
  return got == null || got is Map ? '' : _plain(got);
}

/// The children of [c] to draw: (component id, scope) pairs. A template
/// repeats its component once per item of the list at its path.
List<(String, String)> a2uiChildren(
    Map<String, dynamic> c, Object? data, String scope) {
  final ch = c['children'];
  if (ch is List) return [for (final id in ch) if (id is String) (id, scope)];
  if (ch is Map) {
    if (ch['explicitList'] is List) {
      return [
        for (final id in ch['explicitList'] as List)
          if (id is String) (id, scope),
      ];
    }
    final t = ch['template'] is Map ? ch['template'] as Map : ch;
    final id = t['componentId'];
    final path = t['path'] ?? t['dataBinding'];
    if (id is String && path is String) {
      final at = a2uiAbsolute(path, scope);
      final list = a2uiGet(data, at);
      if (list is List) {
        return [for (var i = 0; i < list.length; i++) (id, '$at/$i')];
      }
      if (list is Map) {
        return [for (final k in list.keys) (id, '$at/$k')];
      }
    }
  }
  return const [];
}

/// The message a tapped Button sends back: the A2UI `action` envelope, with
/// its context read out of the data model, and the whole model when the
/// surface asked for it.
Map<String, dynamic> a2uiActionMessage({
  required Map<String, dynamic> spec,
  required Map<String, dynamic> button,
  required Object? data,
  required String scope,
  required DateTime at,
}) {
  final event = (button['action'] is Map
          ? (button['action'] as Map)['event']
          : null) as Map? ??
      const {};
  final context = <String, dynamic>{};
  final raw = event['context'];
  if (raw is Map) {
    raw.forEach((k, v) => context['$k'] = a2uiValue(v, data, scope: scope));
  }
  final said = event['userMessage'];
  return {
    'version': kA2uiVersion,
    'action': {
      'name': '${event['name'] ?? 'action'}',
      'surfaceId': spec['surfaceId'],
      'sourceComponentId': button['id'],
      'timestamp': at.toUtc().toIso8601String(),
      if (said != null) 'userMessage': a2uiText(said, data, scope: scope),
      'context': context,
      if (spec['sendDataModel'] == true) 'dataModel': data,
    },
  };
}
