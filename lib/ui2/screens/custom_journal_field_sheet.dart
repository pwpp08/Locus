// "Write your own" — a question of the user's own for the journal.
//
// Ported from the pre-ui2 journal (lib/ui/journal/custom_journal_field_sheet.dart,
// lost in the UI rebuild — issue #273) and cut down to the journal's compact
// sheet. Most questions are a yes or a no, so that is where it starts: type
// it and add it. A number has to declare what it MEANS: without a unit its
// values render as bare numbers, and without a ceiling a mis-tap can enter a
// value that dominates every correlation it appears in.

import 'package:flutter/material.dart';

import '../../data/journal_fields.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/display_text.dart';
import '../ui2.dart';
import 'journal_compose.dart' show JournalPillButton, JournalSectionLabel;

/// Opens the sheet. Returns the new field, or null if dismissed.
///
/// [existingKeys] are rejected on save so a second field cannot quietly
/// overwrite the first one's history by colliding on the generated key.
Future<JournalFieldSpec?> showCustomJournalFieldSheet(
  BuildContext context, {
  required Set<String> existingKeys,
}) {
  return AppSheet.open<JournalFieldSpec>(context,
    builder: (ctx) => AlwaysChar(
      child: Padding(
        // The sheet holds a text field; without this it sits under the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _CustomFieldSheet(existingKeys: existingKeys),
      ),
    ),
    scroll: true,
    bare: true,
    scrim: JC.scrim,
  );
}

/// How the question is answered.
enum _Shape { yesNo, rating, amount, minutes }

class _CustomFieldSheet extends StatefulWidget {
  const _CustomFieldSheet({required this.existingKeys});
  final Set<String> existingKeys;

  @override
  State<_CustomFieldSheet> createState() => _CustomFieldSheetState();
}

class _CustomFieldSheetState extends State<_CustomFieldSheet> {
  final _nameCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  _Shape _shape = _Shape.yesNo;
  double _max = 1;
  double _step = 1;
  bool _hasTime = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  void _select(_Shape s) {
    setState(() {
      _shape = s;
      // Sensible shapes per kind, so the common case needs no further tapping.
      // Every branch sets BOTH unit and time — otherwise a unit typed under
      // one kind silently rides along when the kind changes.
      const durStep = 15.0;
      switch (s) {
        case _Shape.yesNo:
          // The habit shape the wellness tab writes: a ceiling of one.
          _max = 1;
          _step = 1;
          _unitCtrl.text = '';
          _hasTime = false;
        case _Shape.rating:
          _max = 5;
          _step = 1;
          _unitCtrl.text = '';
          _hasTime = false;
        case _Shape.amount:
          _max = 100;
          _step = 1;
          _unitCtrl.text = '';
          _hasTime = false;
        case _Shape.minutes:
          // A value the ceiling chips can actually produce (step x 20).
          _step = durStep;
          _max = durStep * 20;
          _unitCtrl.text = 'min';
          _hasTime = false;
      }
    });
  }

  JournalFieldKind get _kind => switch (_shape) {
        _Shape.yesNo || _Shape.rating => JournalFieldKind.rating,
        _Shape.amount => JournalFieldKind.dose,
        _Shape.minutes => JournalFieldKind.duration,
      };

  bool get _counted => _shape == _Shape.amount || _shape == _Shape.minutes;

  void _save() {
    final l = AppLocalizations.of(context);
    final label = _nameCtrl.text.trim();
    if (label.isEmpty) {
      setState(() => _error = l?.journalFieldErrorNoName ?? 'Give it a name');
      return;
    }
    final key = customJournalFieldKey(label);
    // A name that slugs to nothing ("???") would produce a bare `custom_`
    // key that every other such name also produces.
    if (key == customJournalFieldKey('')) {
      setState(() => _error =
          l?.journalFieldErrorInvalidName ?? 'Use at least one letter or number');
      return;
    }
    // An amount with no unit renders as a bare number everywhere after —
    // correlations, findings, CSV. Demand it up front.
    if (_counted && _unitCtrl.text.trim().isEmpty) {
      setState(() => _error =
          l?.journalFieldErrorNoUnit ?? 'Say what it is counted in (mg, ml, cups…)');
      return;
    }
    if (widget.existingKeys.contains(key)) {
      setState(() => _error =
          l?.journalFieldErrorDuplicate ?? 'You already track something by that name');
      return;
    }
    Navigator.pop(
      context,
      JournalFieldSpec(
        key: key,
        label: label,
        kind: _kind,
        unit: _counted ? _unitCtrl.text.trim() : '',
        max: _max,
        step: _step,
        hasTime: _hasTime,
        custom: true,
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final bottom = MediaQuery.paddingOf(c).bottom;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .85),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: JC.sheetColors,
          stops: JC.sheetStops,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: JC.gutter + S.hair),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: S.x4 + S.x1 / 2 + S.hair),
          Center(
            child: Container(
              width: JC.grabW,
              height: JC.grabH,
              decoration:
                  const BoxDecoration(color: JC.grab, borderRadius: R.rPill),
            ),
          ),
          const SizedBox(height: S.x6),
          Semantics(
            header: true,
            child: Text(uiText(c, 'WRITE YOUR OWN'),
                textAlign: TextAlign.center,
                style: JC.title.copyWith(color: JC.ink)),
          ),
          const SizedBox(height: S.x5),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Box(
                    child: AppField(
                      controller: _nameCtrl,
                      bare: true,
                      autofocus: true,
                      textStyle: JC.searchText,
                      semanticLabel: uiText(c, 'Your question'),
                      hint: uiText(c, 'Walked after lunch?'),
                    ),
                  ),
                  const SizedBox(height: S.x5),
                  JournalSectionLabel(uiText(c, 'ANSWERED WITH'),
                      color: JC.sectionInk),
                  const SizedBox(height: S.x3),
                  Wrap(
                    spacing: S.x2,
                    // Each chip's 44 pt target already leaves air between runs.
                    runSpacing: 0,
                    children: [
                      for (final (s, text) in [
                        (_Shape.yesNo, uiText(c, 'Yes or no')),
                        (_Shape.rating,
                            l?.journalFieldKindRating ?? 'A 1–5 rating'),
                        (_Shape.amount, l?.journalFieldKindAmount ?? 'An amount'),
                        (_Shape.minutes, l?.journalFieldKindMinutes ?? 'Minutes'),
                      ])
                        _Chip(text, _shape == s, () => _select(s)),
                    ],
                  ),
                  if (_counted) ...[
                    const SizedBox(height: S.x5),
                    _Box(
                      child: AppField(
                        controller: _unitCtrl,
                        bare: true,
                        textStyle: JC.searchText,
                        semanticLabel: l?.journalFieldUnitLabel ?? 'Unit',
                        hint: l?.journalFieldUnitHint ?? 'mg, ml, cups…',
                      ),
                    ),
                    const SizedBox(height: S.x5),
                    JournalSectionLabel(
                        (l?.journalFieldStepSize ?? 'Step size').toUpperCase(),
                        color: JC.sectionInk),
                    const SizedBox(height: S.x3),
                    Wrap(
                      spacing: S.x2,
                      // Each chip's 44 pt target already leaves air between runs.
                    runSpacing: 0,
                      children: [
                        for (final st in const [1.0, 5.0, 15.0, 50.0, 100.0])
                          _Chip(st.round().toString(), _step == st, () {
                            setState(() {
                              _step = st;
                              // The ceiling must stay above the step or the
                              // field can only ever hold 0 — and it must be
                              // one of the chips below, or the selected state
                              // lies.
                              if (_max < st || _max % st != 0) _max = st * 20;
                            });
                          }),
                      ],
                    ),
                    const SizedBox(height: S.x5),
                    JournalSectionLabel(
                        (l?.journalFieldMaxPerDay ?? 'Most you would log in a day')
                            .toUpperCase(),
                        color: JC.sectionInk),
                    const SizedBox(height: S.x3),
                    Wrap(
                      spacing: S.x2,
                      // Each chip's 44 pt target already leaves air between runs.
                    runSpacing: 0,
                      children: [
                        for (final m in [
                          _step * 10,
                          _step * 20,
                          _step * 50,
                          _step * 100,
                        ])
                          _Chip(m.round().toString(), _max == m,
                              () => setState(() => _max = m)),
                      ],
                    ),
                    const SizedBox(height: S.x3),
                    _Chip(
                        l?.journalFieldAskLastTime ?? 'Ask when the last one was',
                        _hasTime,
                        () => setState(() => _hasTime = !_hasTime)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: S.x3),
                    ErrorLine(_error!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: JC.listFoot),
          JournalPillButton(label: uiText(c, 'ADD QUESTION'), onTap: _save),
          SizedBox(height: JC.doneFoot + bottom / 2),
        ],
      ),
    );
  }
}

/// The dark well a text field sits in, the search field's shape.
class _Box extends StatelessWidget {
  const _Box({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext c) => Container(
        height: JC.searchH,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: S.x4),
        decoration: BoxDecoration(
          color: JC.search,
          borderRadius: JC.rSearch,
          border: Border.all(color: JC.searchEdge, width: S.hair),
        ),
        child: child,
      );
}

/// A choice: a tenth of white, or white with dark type when chosen.
class _Chip extends StatelessWidget {
  const _Chip(this.label, this.chosen, this.onTap);
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        child: Container(
          height: S.x8,
          padding: const EdgeInsets.symmetric(horizontal: S.x3),
          decoration: BoxDecoration(
            color: chosen ? JC.chosen : JC.button,
            borderRadius: JC.rAnswer,
          ),
          // widthFactor 1: a chip is as wide as its words, not the row.
          child: Center(
            widthFactor: 1,
            child: Text(label,
                style: JC.value.copyWith(color: chosen ? JC.onChosen : JC.ink)),
          ),
        ),
      );
}
