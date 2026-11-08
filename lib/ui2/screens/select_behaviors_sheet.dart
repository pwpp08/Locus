// SELECT BEHAVIORS: the sheet behind the journal's pencil. A search across the
// whole catalogue, a tab per category, what is chosen above what is not, and
// a way to write a question of your own. Sizes measured off the reference
// screenshots (see JC in theme.dart).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/journal_fields.dart';
import '../../l10n/display_text.dart';
import '../ui2.dart';
import 'journal_compose.dart' show JournalPillButton, JournalSectionLabel;

/// Opens the sheet over [selected]. Returns the new choice in the order the
/// journal should ask it, or null when the sheet was closed without saving.
///
/// [custom] are the user's own fields. [onWriteOwn] defines and stores a new
/// one (it opens its own sheet over this one) and returns it, or null.
Future<List<String>?> openSelectBehaviors(
  BuildContext c, {
  required List<String> selected,
  required List<JournalFieldSpec> custom,
  required Future<JournalFieldSpec?> Function(BuildContext) onWriteOwn,
}) => AppSheet.open<List<String>>(
  c,
  scroll: true,
  bare: true,
  scrim: JC.scrim,
  builder: (_) => AlwaysChar(
    child: SelectBehaviorsSheet(
      // A sheet's own MediaQuery has the status bar taken off; its top is
      // measured from the screen's.
      top: MediaQuery.paddingOf(c).top + JC.sheetTop,
      selected: selected,
      custom: custom,
      onWriteOwn: onWriteOwn,
    ),
  ),
);

class SelectBehaviorsSheet extends StatefulWidget {
  const SelectBehaviorsSheet({
    super.key,
    required this.selected,
    required this.custom,
    required this.onWriteOwn,
    this.top = JC.sheetTop,
  });

  /// How far below the top of the screen the sheet starts.
  final double top;
  final List<String> selected;
  final List<JournalFieldSpec> custom;
  final Future<JournalFieldSpec?> Function(BuildContext) onWriteOwn;

  @override
  State<SelectBehaviorsSheet> createState() => _SelectBehaviorsSheetState();
}

class _SelectBehaviorsSheetState extends State<SelectBehaviorsSheet> {
  late final List<String> _selected = [...widget.selected];
  late final List<JournalFieldSpec> _custom = [...widget.custom];
  final _search = TextEditingController();

  /// Null is All; otherwise the category's tab.
  JournalBehaviorCategory? _tab;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<JournalBehavior> get _all => [
    for (final s in _custom) JournalBehavior.custom(s),
    ...kJournalBehaviors,
  ];

  /// What the list shows: a search reaches every category; otherwise the tab.
  List<JournalBehavior> get _shown {
    final q = _search.text.trim().toLowerCase();
    final out = [
      for (final b in _all)
        if (q.isNotEmpty
            ? b.name.toLowerCase().contains(q) ||
                  b.question.toLowerCase().contains(q) ||
                  b.category.label.toLowerCase().contains(q)
            : _tab == null || b.category == _tab)
          b,
    ];
    return out
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _toggle(String key) => setState(
    () => _selected.contains(key) ? _selected.remove(key) : _selected.add(key),
  );

  Future<void> _writeOwn() async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      final spec = await widget.onWriteOwn(context);
      if (spec == null || !mounted) return;
      setState(() {
        _custom.add(spec);
        if (!_selected.contains(spec.key)) _selected.add(spec.key);
      });
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final mq = MediaQuery.of(c);
    final shown = _shown;
    final on = [
      for (final b in shown)
        if (_selected.contains(b.key)) b,
    ];
    final off = [
      for (final b in shown)
        if (!_selected.contains(b.key)) b,
    ];
    final searching = _search.text.trim().isNotEmpty;
    final offerOwn = searching
        ? shown.isEmpty
        : _tab == null || _tab == JournalBehaviorCategory.custom;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        height: mq.size.height - widget.top,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: JC.sheetColors,
            stops: JC.sheetStops,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: S.x4 + S.x1 / 2 + S.hair),
            Container(
              width: JC.grabW,
              height: JC.grabH,
              decoration: const BoxDecoration(
                color: JC.grab,
                borderRadius: R.rPill,
              ),
            ),
            const SizedBox(height: S.x6 + S.hair / 4),
            Semantics(
              header: true,
              child: Text(
                uiText(c, 'SELECT BEHAVIORS'),
                style: JC.title.copyWith(color: JC.ink),
              ),
            ),
            const SizedBox(height: S.x6 - S.hair),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: JC.gutter + S.hair,
              ),
              child: _SearchField(controller: _search),
            ),
            const SizedBox(height: S.x4 + S.half + S.hair / 4),
            _Tabs(
              tab: _tab,
              dim: searching,
              onTab: (t) => setState(() {
                _tab = t;
                _search.clear();
              }),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  JC.gutter + S.half / 4,
                  0,
                  JC.gutter + S.half / 4,
                  0,
                ),
                children: [
                  const SizedBox(height: S.x8),
                  if (offerOwn) ...[
                    BehaviorPickRow(
                      name: uiText(c, 'Write your own'),
                      question: searching
                          ? uiText(c, 'Nothing matches. Add it as a question.')
                          : uiText(c, 'Add a question of your own'),
                      selected: false,
                      adds: true,
                      onTap: _writing ? null : () => unawaited(_writeOwn()),
                    ),
                    const SizedBox(height: S.x3),
                  ],
                  if (on.isNotEmpty) ...[
                    JournalSectionLabel(
                      uiText(c, 'CURRENTLY SELECTED'),
                      color: JC.sectionInk,
                    ),
                    const SizedBox(height: S.x5 - S.hair / 2),
                    for (final b in on) _pick(c, b, true),
                    const SizedBox(height: S.x4 + S.x1 / 2),
                  ],
                  if (off.isNotEmpty) ...[
                    JournalSectionLabel(
                      uiText(c, 'NOT SELECTED'),
                      color: JC.sectionInk,
                    ),
                    const SizedBox(height: S.x5 - S.hair / 2),
                    for (final b in off) _pick(c, b, false),
                  ],
                  const SizedBox(height: S.x4),
                ],
              ),
            ),
            const SizedBox(height: JC.listFoot),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: JC.gutter + S.half / 4,
              ),
              child: JournalPillButton(
                label: uiText(c, 'SAVE BEHAVIORS'),
                onTap: () => Navigator.of(c).pop([..._selected]),
              ),
            ),
            const SizedBox(height: JC.doneFoot),
          ],
        ),
      ),
    );
  }

  Widget _pick(BuildContext c, JournalBehavior b, bool on) {
    final own = b.category == JournalBehaviorCategory.custom;
    return BehaviorPickRow(
      name: own ? b.name : uiText(c, b.name),
      question: own ? b.question : uiText(c, b.question),
      selected: on,
      onTap: () => _toggle(b.key),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext c) => Container(
    height: JC.searchH,
    decoration: BoxDecoration(
      color: JC.search,
      borderRadius: JC.rSearch,
      border: Border.all(color: JC.searchEdge, width: S.hair),
    ),
    child: Row(
      children: [
        const SizedBox(width: S.x3 + S.x1 / 2 + S.hair / 4),
        const Icon(LucideIcons.search, size: I.lg, color: JC.ink),
        const SizedBox(width: S.x5 + S.hair / 2),
        Expanded(
          child: AppField(
            controller: controller,
            bare: true,
            hint: uiText(c, 'Search for Behaviors'),
            semanticLabel: uiText(c, 'Search for Behaviors'),
            textStyle: JC.searchText,
            textInputAction: TextInputAction.search,
          ),
        ),
        const SizedBox(width: S.x4),
      ],
    ),
  );
}

/// All, then a tab per category, scrolling sideways; the active one is white
/// and underlined. While a search runs every tab is dimmed: it covers them all.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.dim, required this.onTab});
  final JournalBehaviorCategory? tab;
  final bool dim;
  final ValueChanged<JournalBehaviorCategory?> onTab;

  @override
  Widget build(BuildContext c) {
    final tabs = <JournalBehaviorCategory?>[
      null,
      ...JournalBehaviorCategory.values,
    ];
    return SizedBox(
      height: S.tap,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: JC.gutter + S.hair),
        child: Row(
          children: [
            for (final t in tabs)
              Builder(
                builder: (tc) => Pressable(
                  semanticLabel: uiText(c, t?.label ?? 'All'),
                  onTap: () {
                    onTab(t);
                    // The chosen tab slides to the middle, as in the reference.
                    unawaited(
                      Scrollable.ensureVisible(
                        tc,
                        alignment: .5,
                        duration: motion(c, Motion.base),
                      ),
                    );
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: JC.tabMin),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: JC.tabPad,
                      ),
                      child: _Tab(
                        label: uiText(c, t?.label ?? 'All'),
                        active: !dim && t == tab,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext c) => Center(
    widthFactor: 1,
    child: IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: JC.tab.copyWith(color: active ? JC.ink : JC.tabOff),
          ),
          const SizedBox(height: S.x2 - S.hair),
          Container(
            height: JC.tabLine,
            decoration: BoxDecoration(
              color: active ? JC.ink : const Color(0x00000000),
              borderRadius: R.rPill,
            ),
          ),
        ],
      ),
    ),
  );
}

/// One behavior on the sheet: its name, the question it asks, and a square
/// checkbox, filled blue with a dark tick when chosen. [adds] draws a plus in
/// an empty box instead — the "write your own" row.
class BehaviorPickRow extends StatelessWidget {
  const BehaviorPickRow({
    super.key,
    required this.name,
    required this.question,
    required this.selected,
    this.onTap,
    this.adds = false,
  });

  final String name, question;
  final bool selected, adds;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) => Pressable(
    semanticLabel: '$name. $question',
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: JC.pickRowH),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x2 + S.half),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: JC.row.copyWith(color: JC.ink)),
                  Text(question, style: JC.sub.copyWith(color: JC.question)),
                ],
              ),
            ),
            const SizedBox(width: S.x4),
            AnimatedContainer(
              duration: motion(c, Motion.fast),
              width: JC.boxSide,
              height: JC.boxSide,
              decoration: BoxDecoration(
                color: selected ? JC.box : const Color(0x00000000),
                borderRadius: JC.rBox,
                border: selected
                    ? null
                    : Border.all(color: JC.ink, width: JC.boxRim),
              ),
              child: selected
                  ? const OverflowBox(
                      maxWidth: JC.tick,
                      maxHeight: JC.tick,
                      child: Icon(
                        LucideIcons.checkHeavy,
                        size: JC.tick,
                        color: JC.tickOn,
                      ),
                    )
                  : adds
                  ? const Icon(LucideIcons.plusBold, size: I.sm, color: JC.ink)
                  : null,
            ),
            const SizedBox(width: S.x4 - S.hair - S.half / 10),
          ],
        ),
      ),
    ),
  );
}
