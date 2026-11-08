// Long-pressing the tab bar opens a sheet to reorder and hide tabs. Home and
// More cannot be hidden; the choice is remembered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  group('tabsFromPref', () {
    test('empty and junk are the default bar', () {
      expect(tabsFromPref(''), kDefaultTabs);
      expect(tabsFromPref('nope,,x'), kDefaultTabs);
    });

    test('order is kept and repeats are dropped', () {
      expect(tabsFromPref('more,macros,today,macros,strength'), [
        ShellDomain.more,
        ShellDomain.health,
        ShellDomain.today,
        ShellDomain.strength,
      ]);
    });

    test('Home and More are put back if a stored bar lost them', () {
      expect(tabsFromPref('macros'), [
        ShellDomain.today,
        ShellDomain.health,
        ShellDomain.more,
      ]);
    });

    test('round trip', () {
      final bar = [ShellDomain.more, ShellDomain.today];
      expect(tabsFromPref(tabsToPref(bar)), bar);
    });
  });

  /// Prefs caches one SharedPreferences for the whole process, so each test
  /// sets the key through it rather than through a fresh mock.
  Future<void> prefs(String tabs) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    Prefs.setString(Prefs.navTabs, tabs);
  }

  Future<void> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: AppShell(
        onAction: (_) {},
        builder: (_, d) => Center(child: Text('body ${d.name}')),
      ),
    ));
    await t.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester t) async {
    await t.longPress(find.text('Home'));
    await t.pumpAndSettle();
    expect(find.text('CUSTOMISE TABS'), findsOneWidget);
  }

  testWidgets('a long press on a tab opens the editor; a plain tap does not',
      (t) async {
    await prefs('');
    await mount(t);
    await t.tap(find.text('Strength'));
    await t.pumpAndSettle();
    expect(find.text('CUSTOMISE TABS'), findsNothing);
    expect(find.text('body strength'), findsOneWidget);
    await openEditor(t);
  });

  testWidgets('hiding a tab removes it from the bar and is remembered',
      (t) async {
    await prefs('');
    await mount(t);
    await openEditor(t);

    // Home and More are pinned: no switch for them.
    expect(find.text('Always on'), findsNWidgets(2));
    await t.tap(find.byType(Switch).last); // Strength, now the last row
    await t.pump();
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();

    expect(find.text('Strength'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Health'), findsOneWidget);
    expect(Prefs.getString(Prefs.navTabs, ''), 'today,health,more');

    // And it comes back with the sheet's reset.
    await openEditor(t);
    await t.tap(find.text('RESET TO DEFAULT'));
    await t.pumpAndSettle();
    expect(find.text('Strength'), findsOneWidget);
    expect(Prefs.getString(Prefs.navTabs, ''), 'today,health,strength,more');
  });

  testWidgets('a saved bar is what the next launch shows', (t) async {
    await prefs('more,today');
    await mount(t);
    expect(find.text('Strength'), findsNothing);
    expect(find.text('Health'), findsNothing);
    final more = t.getCenter(find.text('More')).dx;
    final home = t.getCenter(find.text('Home')).dx;
    expect(more, lessThan(home), reason: 'More was moved ahead of Home');
  });

  testWidgets('hiding the tab you are on drops you back on Home', (t) async {
    await prefs('');
    await mount(t);
    await t.tap(find.text('Health'));
    await t.pumpAndSettle();
    expect(find.text('body health'), findsOneWidget);

    await t.longPress(find.text('Health'));
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch).first); // Health, the first removable row
    await t.pump();
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();
    expect(find.text('Health'), findsNothing);
    expect(find.text('body today'), findsOneWidget);
  });
}
