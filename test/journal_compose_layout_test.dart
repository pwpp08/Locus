// The journal and its SELECT BEHAVIORS sheet, laid out on a 393 x 852 phone
// with the app's real fonts, against the sizes measured off the reference
// screenshots (921 px across = 393 dp). The owner's standing complaint is
// components drawn too big; these pin the measured sizes so a later "tidy-up"
// cannot quietly grow them.
//
// JOURNAL_SHOTS=<dir> also writes each state as a PNG at the reference's own
// 921 px width, for a side-by-side look.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart';
import 'package:openstrap_edge/ui2/screens/select_behaviors_sheet.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

class _Repo extends LocalRepository {
  _Repo(this.metrics);
  Map<String, JournalMetricValue> metrics;
  List<String> tags = [];
  final custom = <JournalFieldSpec>[];

  @override
  Future<List<JournalFieldSpec>> getJournalFields() async =>
      [...kJournalFields, ...custom];
  @override
  Future<Map<String, JournalMetricValue>> getJournalMetrics(String date) async =>
      date == todayLabel() ? {...metrics} : const {};
  @override
  Future<void> postJournalMetrics(
          String date, Map<String, JournalMetricValue> values) async =>
      metrics = {...values};
  @override
  Future<List<Map<String, dynamic>>> getJournal({String range = '30d'}) async =>
      [
        {'date': todayLabel(), 'tags': [...tags], 'note': ''},
      ];
  @override
  Future<void> postJournal(String date, List<String> t, String note) async =>
      tags = [...t];
  @override
  Future<void> postCustomJournalField(JournalFieldSpec spec) async =>
      custom.add(spec);
}

final _shot = GlobalKey();
final _dir = Platform.environment['JOURNAL_SHOTS'];

Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final f in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(f['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> _write(WidgetTester t, String name) async {
  if (_dir == null) return;
  final boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 921 / 393);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  });
  File('$_dir/$name.png').writeAsBytesSync(png!);
}

Future<_Repo> _pump(WidgetTester t, List<String> selection,
    {Map<String, JournalMetricValue> metrics = const {}}) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3;
  t.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  await Prefs.ensureLoaded();
  // Prefs keeps one instance for the run, so the choice is written through it.
  Prefs.setString(kJournalSelectionPref, jsonEncode(selection));
  final app = AppState.forTesting();
  final repo = _Repo({...metrics});
  app.repo = repo;
  await t.pumpWidget(RepaintBoundary(
    key: _shot,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const JournalCompose(),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return repo;
}

Rect _box(WidgetTester t, Finder f) => t.getRect(f);

void main() {
  setUpAll(_loadFonts);

  testWidgets('the journal page at the reference sizes', (t) async {
    await _pump(t, ['bhv_morning_snack', 'bhv_recovered', 'bhv_outdoors']);
    await _write(t, 'journal');

    // Rows: 63 tall, 18 in from each edge, 10 apart.
    final cards = find.ancestor(
        of: find.text('Snacked before lunch?'),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints?.minHeight == JC.rowH));
    final row = _box(t, cards.first);
    expect(row.height, closeTo(63, 0.5));
    expect(row.left, closeTo(18, 0.5));
    expect(row.right, closeTo(375, 0.5));

    // The ✕ and ✓: 36 square, 9 apart, 14 in from the card's right edge.
    final answers = find.byWidgetPredicate(
        (w) => w is AnimatedContainer && w.constraints?.maxWidth == JC.answer);
    final no = _box(t, answers.at(0)), yes = _box(t, answers.at(1));
    expect(no.size, const Size(36, 36));
    expect(yes.left - no.right, closeTo(9, 0.5));
    expect(row.right - yes.right, closeTo(13.6, 0.6));

    // DONE: 338 x 52, 18 off the bottom of the screen.
    final done = _box(t,
        find.ancestor(of: find.text('DONE'), matching: find.byType(Container)).first);
    expect(done.height, closeTo(52, 0.5));
    expect(done.width, closeTo(338.4, 1));
    expect(852 - done.bottom, closeTo(18, 0.5));

    // Day pills: 49 x 79, the chosen (today) one at the right gutter.
    final pill = _box(
        t,
        find.ancestor(
            of: find.text('${DateTime.now().day}'),
            matching: find.byWidgetPredicate((w) =>
                w is Container && w.constraints?.maxHeight == JC.pillH)).first);
    expect(pill.size.width, closeTo(49.4, 0.2));
    expect(pill.size.height, closeTo(79, 0.2));
    expect(pill.right, closeTo(374.6, 0.6));
    expect(pill.top, closeTo(179.7, 1.5));

    expect(find.textContaining("What's happening today"), findsOneWidget);
    expect(find.text('JOURNAL'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('BEHAVIORS'), findsOneWidget);
  });

  testWidgets('every kind of question, answered', (t) async {
    final repo = await _pump(t, [
      'bhv_late_meal',
      'mood',
      'caffeine_mg',
      'bhv_outdoors',
      'weight_kg',
    ], metrics: {
      'mood': const JournalMetricValue(4),
      'caffeine_mg': const JournalMetricValue(150, atMinuteOfDay: 14 * 60),
    });
    await t.tap(find.bySemanticsLabel('Yes').first);
    await t.tap(find.bySemanticsLabel('No').at(1));
    await t.pumpAndSettle();
    await _write(t, 'journal_answered');

    await t.tap(find.text('DONE'));
    await t.pumpAndSettle();
    expect(repo.metrics['bhv_late_meal']?.value, 1);
    expect(repo.metrics['bhv_outdoors']?.value, 0);
    expect(repo.metrics['mood']?.value, 4);
    // The preset tag that meant the same thing stays in step.
    expect(repo.tags, contains('late meal'));
  });

  testWidgets('the SELECT BEHAVIORS sheet at the reference sizes', (t) async {
    await _pump(t, ['bhv_morning_snack', 'bhv_recovered', 'bhv_outdoors']);
    await t.tap(find.bySemanticsLabel('Choose what to log'));
    await t.pumpAndSettle();
    expect(find.byType(SelectBehaviorsSheet), findsOneWidget);
    await _write(t, 'select_all');

    final sheet = _box(t, find.byType(SelectBehaviorsSheet));
    expect(sheet.top, closeTo(75, 0.5));
    final search = _box(
        t,
        find.ancestor(
            of: find.byType(AppField),
            matching: find.byWidgetPredicate((w) =>
                w is Container && w.constraints?.maxHeight == JC.searchH)).first);
    expect(search.height, closeTo(51, 0.5));
    expect(search.top, closeTo(163.4, 1.5));
    final save = _box(t,
        find.ancestor(of: find.text('SAVE BEHAVIORS'), matching: find.byType(Container)).first);
    expect(save.size.height, closeTo(52, 0.5));
    expect(save.size.width, closeTo(356.3, 0.6));
    expect(852 - save.bottom, closeTo(18, 0.5));
    final box = _box(
        t,
        find.byWidgetPredicate((w) =>
            w is AnimatedContainer && w.constraints?.maxWidth == JC.boxSide).first);
    expect(box.width, closeTo(24.2, 0.01));
    expect(box.height, closeTo(24.2, 0.01));
    expect(box.right, closeTo(359.8, 0.8));

    // Search reaches every category.
    await t.enterText(find.byType(TextField).last, 'sauna');
    await t.pumpAndSettle();
    expect(find.text('Sauna'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, '');
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Lifestyle'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lifestyle'));
    await t.pumpAndSettle();
    await _write(t, 'select_lifestyle');
    expect(find.text('Air Travel'), findsOneWidget);
    expect(find.text('Sauna'), findsNothing);
  });

  testWidgets('a question written by hand becomes a behavior', (t) async {
    final repo = await _pump(t, ['bhv_outdoors']);
    await t.tap(find.bySemanticsLabel('Choose what to log'));
    await t.pumpAndSettle();
    await t.tap(find.text('Write your own'));
    await t.pumpAndSettle();
    await _write(t, 'write_own');
    await t.enterText(find.byType(TextField).last, 'Walked after lunch?');
    await t.tap(find.text('ADD QUESTION'));
    await t.pumpAndSettle();
    expect(repo.custom.single.key, 'custom_walked_after_lunch');
    expect(repo.custom.single.isYesNo, isTrue);
    await t.tap(find.text('SAVE BEHAVIORS'));
    await t.pumpAndSettle();
    expect(find.text('Walked after lunch?'), findsOneWidget);
    expect(jsonDecode(Prefs.getString(kJournalSelectionPref, '[]')),
        ['bhv_outdoors', 'custom_walked_after_lunch']);
  });

  test('the catalogue is large, unique and brand-free', () {
    expect(kJournalBehaviors.length, greaterThanOrEqualTo(80));
    final keys = kJournalBehaviors.map((b) => b.key).toList();
    expect(keys.toSet().length, keys.length);
    for (final b in kJournalBehaviors) {
      // A non-bhv_ key points at an existing field, never a new number.
      expect(
          b.key.startsWith('bhv_') || kJournalFieldsByKey.containsKey(b.key),
          isTrue,
          reason: b.key);
      expect(journalFieldSpec(b.key), isNotNull, reason: b.key);
      expect('${b.name} ${b.question}'.toLowerCase(), isNot(contains('whoop')));
    }
    for (final c in JournalBehaviorCategory.values) {
      if (c == JournalBehaviorCategory.custom) continue;
      expect(kJournalBehaviors.where((b) => b.category == c), isNotEmpty);
    }
    // Every preset tag that has a question maps to exactly one.
    final tags = [for (final b in kJournalBehaviors) ?b.tag];
    expect(tags.toSet().length, tags.length);
    expect(journalFieldSpec('bhv_sauna')!.isYesNo, isTrue);
    expect(journalFieldSpec('bhv_sauna')!.format(1), 'Yes');
  });
}
