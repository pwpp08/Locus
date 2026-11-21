// Past coach chats, as the reference's history sheet lays them out: a caps
// title and a close cross, then each day as a caps label with a rule running
// to the edge, and under it one rounded row per chat (a glyph, its title, a
// chevron). A long press offers to delete a chat.

import 'package:flutter/material.dart';

import '../../coach/coach_engine.dart' show CoachEngine, CoachSessionMeta;
import '../ui2.dart';

/// Opens the history for [storageKey]'s chats. [onOpen] gets the chosen
/// chat's id (the sheet has closed by then); [onDeleted] hears of each one
/// deleted, so a screen showing it can let it go.
Future<void> openCoachHistory(
  BuildContext context, {
  required String storageKey,
  ValueChanged<String>? onOpen,
  ValueChanged<String>? onDeleted,
}) =>
    AppSheet.open<void>(
      context,
      bare: true,
      scroll: true,
      builder: (_) => CoachHistorySheet(
        load: () => CoachEngine.sessionsFor(storageKey),
        delete: (id) async {
          await CoachEngine.deleteSessionFor(storageKey, id);
          onDeleted?.call(id);
        },
        onOpen: onOpen,
      ),
    );

const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _months = [
  'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY',
  'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
];

/// A day's heading in the history: TODAY, YESTERDAY, or the weekday and date
/// ("SUN, AUGUST 2"), with the year when it is not this one. Counted in
/// calendar days, so a DST change does not move a chat to the wrong day.
String coachHistoryDay(DateTime d, DateTime now) {
  final back = DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(d.year, d.month, d.day))
      .inDays;
  if (back == 0) return 'TODAY';
  if (back == 1) return 'YESTERDAY';
  final year = d.year == now.year ? '' : ', ${d.year}';
  return '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}$year';
}

class CoachHistorySheet extends StatefulWidget {
  final Future<List<CoachSessionMeta>> Function() load;
  final Future<void> Function(String id) delete;
  final ValueChanged<String>? onOpen;

  /// Today, for the day labels; the clock when null.
  final DateTime? now;

  const CoachHistorySheet({
    super.key,
    required this.load,
    required this.delete,
    this.onOpen,
    this.now,
  });

  @override
  State<CoachHistorySheet> createState() => _CoachHistorySheetState();
}

class _CoachHistorySheetState extends State<CoachHistorySheet> {
  late Future<List<CoachSessionMeta>> _list = widget.load();

  Future<void> _remove(CoachSessionMeta s) async {
    final ok = await AppDialog.show(
      context,
      title: 'Delete this chat?',
      body: 'It goes from this phone for good. What the AI was asked to '
          'remember stays.',
      destructive: 'Delete',
      secondary: 'Cancel',
    );
    if (ok != DialogChoice.destructive) return;
    await widget.delete(s.id);
    if (mounted) setState(() => _list = widget.load());
  }

  @override
  Widget build(BuildContext c) {
    final now = widget.now ?? DateTime.now();
    final height = MediaQuery.sizeOf(c).height * .92;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [HIST.top, HIST.foot],
        ),
      ),
      child: Column(children: [
        const SizedBox(height: S.x2),
        Container(
          width: S.x16,
          height: S.x1,
          decoration: const BoxDecoration(
              color: HIST.grab, borderRadius: R.rPill),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x2, 0),
          child: Row(children: [
            Expanded(
              child: Text('CONVERSATION HISTORY',
                  style: HIST.title.copyWith(color: C.white)),
            ),
            Pressable(
              semanticLabel: 'Close',
              onTap: () => Navigator.of(c).maybePop(),
              child: const SizedBox.square(
                dimension: S.tap,
                child: Icon(LucideIcons.x, size: I.lg, color: C.white),
              ),
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<CoachSessionMeta>>(
            future: _list,
            builder: (_, snap) {
              final list = snap.data;
              if (list == null) return const SizedBox.shrink();
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(S.x6),
                  child: Text(
                    'No chats yet. Every conversation you have with the AI '
                    'is kept here, by day.',
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(color: HIST.label, height: 1.5),
                  ),
                );
              }
              final rows = <Widget>[];
              String? last;
              for (final s in list) {
                final label = coachHistoryDay(
                    DateTime.fromMillisecondsSinceEpoch(s.updatedAt), now);
                if (label != last) {
                  last = label;
                  rows.add(_DayRule(label, first: rows.isEmpty));
                }
                rows.add(_ChatRow(
                  s.title.isEmpty ? 'Untitled chat' : s.title,
                  onTap: () {
                    Navigator.of(c).pop();
                    widget.onOpen?.call(s.id);
                  },
                  onLongPress: () => _remove(s),
                ));
              }
              return ListView(
                padding: EdgeInsets.fromLTRB(S.x4, 0, S.x4,
                    MediaQuery.viewPaddingOf(c).bottom + S.x6),
                children: rows,
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// A day's caps label and the rule that runs from it to the edge.
class _DayRule extends StatelessWidget {
  final String label;
  final bool first;
  const _DayRule(this.label, {required this.first});

  @override
  Widget build(BuildContext c) => Padding(
        padding: EdgeInsets.only(top: first ? S.x2 : S.x1, bottom: S.x4),
        child: Row(children: [
          Text(label,
              style: F.over.copyWith(
                  color: HIST.label,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6)),
          const SizedBox(width: S.x3),
          Expanded(child: Container(height: S.hair, color: HIST.rule)),
        ]),
      );
}

/// One past chat: a glyph, its title on one line, a chevron.
class _ChatRow extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ChatRow(this.title,
      {required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(bottom: S.x4),
        child: Pressable(
          onTap: onTap,
          onLongPress: onLongPress,
          semanticLabel: title,
          child: Container(
            height: S.tap,
            padding: const EdgeInsets.symmetric(horizontal: S.x3),
            decoration: const BoxDecoration(
                color: HIST.row, borderRadius: R.rLg),
            child: Row(children: [
              const Icon(LucideIcons.clipboardList, size: I.md, color: C.white),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.body.copyWith(
                        color: C.white, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: S.x3),
              const Icon(LucideIcons.chevronRight, size: I.md, color: C.white),
            ]),
          ),
        ),
      );
}
