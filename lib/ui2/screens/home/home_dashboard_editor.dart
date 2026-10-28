import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../grammar.dart' show AppSwitch, BigButton;
import '../../theme.dart' show C, F, I, P, S;
import '../../ui2.dart' show LucideIcons;
import '../trend_view.dart'
    show kStrainRecoveryTile, kTrendCatalogue, trendMetricOf;

class HomeDashboardEditor extends StatefulWidget {
  final List<String> selected;
  const HomeDashboardEditor({super.key, required this.selected});

  @override
  State<HomeDashboardEditor> createState() => _HomeDashboardEditorState();
}

class _HomeDashboardEditorState extends State<HomeDashboardEditor> {
  late final List<String> _order = [
    ...widget.selected,
    for (final k in [kStrainRecoveryTile, for (final m in kTrendCatalogue) m.id])
      if (!widget.selected.contains(k)) k,
  ];
  late final Set<String> _on = {...widget.selected};

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
          Text('Choose what to show and drag to reorder.',
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
                final title = m?.title ?? 'Strain & Recovery';
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
                    Icon(m?.icon ?? LucideIcons.chartColumn,
                        size: I.md, color: p.ink2),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Text(title, style: F.body.copyWith(color: p.ink)),
                    ),
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
            onTap: () => Navigator.of(c).pop([
              for (final k in _order)
                if (_on.contains(k)) k,
            ]),
          ),
        ]),
      ),
    );
  }
}
