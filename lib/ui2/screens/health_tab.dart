// The Health tab: Locus Age and the Journal, the same segmented switch as
// every other screen between them.

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
  static const _switchH = S.tap;

  /// The page last shown, kept while the app runs so coming back to the tab
  /// lands where you were. A fresh launch opens on Age.
  static int _last = 0;
  int _page = _last;

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
              child: RangeSegments(
                const ['AGE', 'JOURNAL'],
                _page,
                (i) => setState(() => _page = _last = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
