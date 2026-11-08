// The Health tab: Locus Age and the Journal, one small switch between them.

import 'package:flutter/material.dart';

import '../ui2.dart';
import 'journal_compose.dart';
import 'locus_age.dart';

class HealthTab extends StatefulWidget {
  const HealthTab({super.key});

  @override
  State<HealthTab> createState() => _HealthTabState();
}

class _HealthTabState extends State<HealthTab> {
  static const _switchH = S.x10 + S.x1;
  int _page = 0;

  @override
  Widget build(BuildContext c) {
    final mq = MediaQuery.of(c);
    return AlwaysChar(
      child: Stack(
        children: [
          // Each page starts under the switch, and paints up behind it.
          MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(top: mq.padding.top + _switchH),
            ),
            child: IndexedStack(
              index: _page,
              children: [
                TickerMode(enabled: _page == 0, child: const LocusAgeScreen()),
                TickerMode(
                  enabled: _page == 1,
                  child: const JournalCompose(embedded: true),
                ),
              ],
            ),
          ),
          Positioned(
            top: mq.padding.top,
            left: 0,
            right: 0,
            height: _switchH,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(S.half),
                decoration: const BoxDecoration(
                  color: AC.card,
                  borderRadius: R.rPill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _option(c, 'AGE', 0),
                    _option(c, 'JOURNAL', 1),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(BuildContext c, String label, int page) {
    final on = _page == page;
    return Pressable(
      semanticLabel: label,
      onTap: () => setState(() => _page = page),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: S.x4,
          vertical: S.x1 + S.half,
        ),
        decoration: BoxDecoration(
          color: on ? DC.edge : null,
          borderRadius: R.rPill,
        ),
        child: Text(
          label,
          style: F.dLabel.copyWith(color: on ? DC.ink : DC.ink3),
        ),
      ),
    );
  }
}
