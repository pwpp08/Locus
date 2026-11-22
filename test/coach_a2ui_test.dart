// A2UI in the coach: what prepareA2ui accepts and refuses, and that a drawn
// surface binds its inputs and sends its Button's action back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/coach/coach_a2ui.dart';
import 'package:openstrap_edge/ui2/screens/coach_a2ui_view.dart';
import 'package:openstrap_edge/ui2/screens/coach_figures.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Map<String, dynamic> _form() => {
      'messages': [
        {
          'version': 'v1.0',
          'createSurface': {
            'surfaceId': 'rate',
            'catalogId': kA2uiCatalog,
            'dataModel': {
              'feel': 'Good',
              'items': [
                {'name': 'Squats'},
                {'name': 'Rows'},
              ],
            },
          },
        },
        {
          'version': 'v1.0',
          'updateComponents': {
            'surfaceId': 'rate',
            'components': [
              {
                'id': 'root',
                'component': 'Column',
                'children': ['title', 'list', 'feel', 'done', 'send'],
              },
              {'id': 'title', 'component': 'Text', 'text': 'How was it?', 'variant': 'h3'},
              {
                'id': 'list',
                'component': 'List',
                'children': {'path': '/items', 'componentId': 'item'},
              },
              {'id': 'item', 'component': 'Text', 'text': {'@path': 'name'}},
              {
                'id': 'feel',
                'component': 'ChoicePicker',
                'value': {'@path': '/feel'},
                'options': [
                  {'label': 'Good', 'value': 'Good'},
                  {'label': 'Hard', 'value': 'Hard'},
                ],
              },
              {
                'id': 'done',
                'component': 'CheckBox',
                'label': 'Finished every set',
                'value': {'@path': '/done'},
              },
              {
                'id': 'send',
                'component': 'Button',
                'variant': 'primary',
                'child': 'send_t',
                'action': {
                  'event': {
                    'name': 'rate',
                    'userMessage': {
                      '@call': 'formatString',
                      'args': {'value': r'It felt ${/feel}'},
                    },
                    'context': {
                      'feel': {'@path': '/feel'},
                      'done': {'@path': '/done'},
                    },
                  },
                },
              },
              {'id': 'send_t', 'component': 'Text', 'text': 'Send'},
            ],
          },
        },
      ],
    };

void main() {
  test('folds the messages into one surface', () {
    final r = prepareA2ui(_form());
    expect(r.error, isNull);
    expect(r.spec!['type'], 'a2ui');
    expect(r.spec!['surfaceId'], 'rate');
    expect((r.spec!['components'] as List).length, 8);
  });

  test('refuses what it cannot draw, saying why', () {
    expect(prepareA2ui({'messages': []}).error, contains('createSurface'));
    final noRoot = prepareA2ui({
      'messages': [
        {
          'updateComponents': {
            'surfaceId': 's',
            'components': [
              {'id': 'a', 'component': 'Video', 'url': 'x'},
              {'id': 'b', 'component': 'Column', 'children': ['zz']},
            ],
          },
        },
      ],
    }).error!;
    expect(noRoot, contains('"root"'));
    expect(noRoot, contains('Video'));
    expect(noRoot, contains('"zz"'));
    expect(
        prepareA2ui({
          'messages': [
            {'deleteSurface': {'surfaceId': 's'}},
          ],
        }).error,
        contains('Not shown'));
  });

  testWidgets('draws, binds and sends the action', (t) async {
    final spec = prepareA2ui(_form()).spec!;
    String? said;
    Map<String, dynamic>? sent;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: A2uiSurfaceView(
            spec: spec,
            onAction: (s, m) {
              said = s;
              sent = m;
            },
          ),
        ),
      ),
    ));
    expect(find.text('How was it?'), findsOneWidget);
    // The template repeats once per item.
    expect(find.text('Squats'), findsOneWidget);
    expect(find.text('Rows'), findsOneWidget);

    await t.tap(find.text('Hard'));
    await t.tap(find.text('Finished every set'));
    await t.pumpAndSettle();
    await t.tap(find.text('Send'));
    await t.pump();

    expect(said, 'It felt Hard');
    final a = sent!['action'] as Map;
    expect(a['name'], 'rate');
    expect(a['surfaceId'], 'rate');
    expect(a['sourceComponentId'], 'send');
    expect(a['context'], {'feel': 'Hard', 'done': true});
    // The coach's own copy is untouched: the surface writes to its own.
    expect((spec['dataModel'] as Map)['feel'], 'Good');
  });

  test('chat tables say dates and units the short way', () {
    final now = DateTime(2026, 11, 22);
    expect(chatDate(tableDate('2026-11-17')!, now: now), 'Tue 17 Nov');
    expect(chatDate(tableDate('2025-11-17')!, now: now), 'Mon 17 Nov 2025');
    expect(tableDate('17 Nov'), isNull);
    expect(tableUnit(['148 bpm', '', '102 bpm']), 'bpm');
    expect(tableUnit(['148 bpm', '64 ms']), '');
    expect(tableNumber('7:12'), 432);
    expect(tableNumber('2026-11-17'), isNull);
  });
}
