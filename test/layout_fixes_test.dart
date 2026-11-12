// Regressions found reviewing the gallery's rendered components: a flex peer
// that squeezed a headline for no reason, and a separator that was a question
// mark.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/gallery.dart';
import 'package:openstrap_edge/ui2/screens/home/home_header.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(390 * 3, 800 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(S.x4), child: w),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  bool cut(WidgetTester t, String text) =>
      t.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

  testWidgets('the sync bar never cuts its state word, whichever state',
      (t) async {
    for (final (state, word, at) in [
      (SyncBarState.catchingUp, 'DATA CATCHING UP', '10:18 AM'),
      (SyncBarState.caughtUp, 'DATA CAUGHT UP', '5:09 PM'),
      (SyncBarState.behind, 'DATA NOT UP TO DATE', 'Mon 9:40 PM'),
    ]) {
      await pump(t, HomeSyncBar(state: state, syncedTo: at));
      expect(cut(t, word), isFalse, reason: word);
    }
  });

  testWidgets('a trend card prints its whole reading with room to spare',
      (t) async {
    await pump(t, galleryCases()['trend']!);
    expect(find.text('7h 42m'), findsOneWidget);
    expect(cut(t, '7h 42m'), isFalse);
  });

  testWidgets('a medication line separates its parts with a dot, not a "?"',
      (t) async {
    await pump(t, galleryCases()['med_row']!);
    final lines = [
      for (final w in t.widgetList<Text>(find.byType(Text)))
        if (w.data != null) w.data!,
    ];
    expect(lines.where((s) => s.contains(' ? ')), isEmpty);
    expect(lines.where((s) => s.contains('·')), isNotEmpty);
  });

  testWidgets('every clock in the day timeline fits its column on one line',
      (t) async {
    for (final key in ['moment_row', 'timeline_day']) {
      await pump(t, galleryCases()[key]!);
      final clock = RegExp(r'^\d{1,2}:\d{2}( [AP]M)?$');
      var seen = 0;
      for (final e in t.elementList(find.byType(Text))) {
        final w = e.widget as Text;
        if (w.data == null || !clock.hasMatch(w.data!)) continue;
        final box = e.renderObject;
        final para = t.renderObject<RenderParagraph>(find.text(w.data!).first);
        seen++;
        expect(para.size.width,
            greaterThanOrEqualTo(para.getMaxIntrinsicWidth(double.infinity)),
            reason: '${w.data} is wider than its column in $key');
        expect(box, isNotNull);
      }
      expect(seen, greaterThan(1), reason: key);
    }
  });
}
