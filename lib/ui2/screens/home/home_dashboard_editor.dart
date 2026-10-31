import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../grammar.dart' show AppSwitch, BigButton, Pressable;
import '../../theme.dart' show C, F, I, P, R, S;
import '../../ui2.dart' show LucideIcons;
import '../trend_view.dart'
    show kCompareTile, kStrainRecoveryTile, kTrendCatalogue, trendMetricOf;

/// What the editor hands back: the tiles in order, and which metrics are drawn
/// as their week chart instead of a row.
typedef DashboardChoice = ({List<String> tiles, Set<String> expanded});

class HomeDashboardEditor extends StatefulWidget {
  final List<String> selected;

  /// Metrics currently drawn expanded.
  final Set<String> expanded;
  const HomeDashboardEditor(
      {super.key, required this.selected, this.expanded = const {}});

  @override
  State<HomeDashboardEditor> createState() => _HomeDashboardEditorState();
}

class _HomeDashboardEditorState extends State<HomeDashboardEditor> {
  late final List<String> _order = [
    ...widget.selected,
    for (final k in [
      kStrainRecoveryTile,
      kCompareTile,
      for (final m in kTrendCatalogue) m.id,
    ])
      if (!widget.selected.contains(k)) k,
  ];
  late final Set<String> _on = {...widget.selected};
  late final Set<String> _big = {...widget.expanded};

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x5, S.gutter, S.x4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('MY DASHBOARD', style: F.caps.copyWith(color: p.ink)),
          const SizedBox(height: S.x1),
          Text('Choose what to show, how big, and drag to reorder.',
              style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(height: S.x3),
          SizedBox(
            height: MediaQuery.sizeOf(c).height * .55,
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorder: (from, to) => setState(() {
                if (to > from) to--;
                _order.insert(to, _order.removeAt(from));
              }),
              itemBuilder: (c, i) {
                final k = _order[i];
                final m = trendMetricOf(k);
                final title = m?.title ??
                    (k == kCompareTile ? 'Compare metrics' : 'Strain & Recovery');
                return Padding(
                  key: ValueKey(k),
                  padding: const EdgeInsets.symmetric(vertical: S.x1),
                  child: Row(children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: SizedBox(
                        width: S.tap,
                        height: S.tap,
                        child: Icon(LucideIcons.gripVertical,
                            size: I.md, color: p.ink3),
                      ),
                    ),
                    Icon(
                        m?.icon ??
                            (k == kCompareTile
                                ? LucideIcons.gitCompareArrows
                                : LucideIcons.chartColumn),
                        size: I.md, color: p.ink2),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Text(title, style: F.body.copyWith(color: p.ink)),
                    ),
                    // Row or week chart. The two tiles are always charts.
                    if (m != null)
                      _SizeToggle(
                        big: _big.contains(k),
                        enabled: _on.contains(k),
                        title: title,
                        onTap: () => setState(() =>
                            _big.contains(k) ? _big.remove(k) : _big.add(k)),
                      ),
                    const SizedBox(width: S.x2),
                    AppSwitch(
                      _on.contains(k),
                      (v) => setState(() => v ? _on.add(k) : _on.remove(k)),
                      semanticLabel: title,
                    ),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: S.x3),
          BigButton(
            l?.actionSave ?? 'Save',
            color: C.white,
            onTap: () => Navigator.of(c).pop<DashboardChoice>((
              tiles: [
                for (final k in _order)
                  if (_on.contains(k)) k,
              ],
              expanded: {
                for (final k in _big)
                  if (_on.contains(k)) k,
              },
            )),
          ),
        ]),
      ),
    );
  }
}

/// Slim row or full card: two glyphs in one small tile, the chosen one lit.
class _SizeToggle extends StatelessWidget {
  final bool big, enabled;
  final String title;
  final VoidCallback onTap;
  const _SizeToggle({
    required this.big,
    required this.enabled,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget glyph(IconData i, bool on) => Container(
          width: S.x8,
          height: S.x8,
          alignment: Alignment.center,
          decoration: on
              ? BoxDecoration(color: p.card, borderRadius: R.rMd)
              : null,
          child: Icon(i, size: I.sm, color: on ? p.ink : p.ink3),
        );
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: Pressable(
        onTap: enabled ? onTap : null,
        semanticLabel: big
            ? '$title shown as a chart. Show as a row'
            : '$title shown as a row. Show as a chart',
        child: Container(
          height: S.tap,
          padding: const EdgeInsets.all(S.x1),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.all(S.half),
            decoration: BoxDecoration(
              color: p.ink.withValues(alpha: .06),
              borderRadius: R.rLg,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              glyph(LucideIcons.minus, !big),
              glyph(LucideIcons.chartColumn, big),
            ]),
          ),
        ),
      ),
    );
  }
}
