// THE CALENDAR a tap on Home's date opens: a month at a time, every day written
// in the colour its recovery scored. A day with no score is grey, and cannot
// be opened, because there is nothing on record to open it to.

import 'package:flutter/material.dart';

import '../../data/day_label.dart';
import '../ui2.dart';
import 'home_screen.dart' show recoveryColor;

/// Opens the calendar from the top of the screen and returns the day the user
/// picked, or null when it is dismissed.
Future<String?> openRecoveryCalendar(
  BuildContext c, {
  required String today,
  required String selected,
  required Map<String, double> recovery,
  required Set<String> days,
}) {
  final p = P.of(c);
  return showGeneralDialog<String>(
    context: c,
    barrierDismissible: true,
    barrierLabel: 'Close calendar',
    barrierColor: p.bg.withValues(alpha: .78),
    transitionDuration: motion(c, Motion.base),
    pageBuilder: (c, _, _) => Align(
      alignment: Alignment.topCenter,
      child: _Calendar(
          today: today, selected: selected, recovery: recovery, days: days),
    ),
    transitionBuilder: (c, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, -1), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Ease.standard)),
      child: child,
    ),
  );
}

class _Calendar extends StatefulWidget {
  final String today, selected;
  final Map<String, double> recovery;
  final Set<String> days;
  const _Calendar({
    required this.today,
    required this.selected,
    required this.recovery,
    required this.days,
  });

  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  late DateTime _month = () {
    final d = DateTime.tryParse(widget.selected) ?? DateTime.now();
    return DateTime(d.year, d.month);
  }();

  static const _names = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST',
    'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  DateTime get _thisMonth {
    final t = DateTime.tryParse(widget.today) ?? DateTime.now();
    return DateTime(t.year, t.month);
  }

  /// The oldest month with a day on record (this month at the least).
  DateTime get _firstMonth {
    var first = _thisMonth;
    for (final d in widget.days) {
      final t = DateTime.tryParse(d);
      if (t != null && DateTime(t.year, t.month).isBefore(first)) {
        first = DateTime(t.year, t.month);
      }
    }
    return first;
  }

  void _step(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final canBack = _month.isAfter(_firstMonth);
    final canForward = _month.isBefore(_thisMonth);
    final lead = DateTime(_month.year, _month.month).weekday - 1;
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = ((lead + count) / 7).ceil();

    Widget arrow(bool left, bool on) => Semantics(
          label: left ? 'Previous month' : 'Next month',
          button: true,
          enabled: on,
          excludeSemantics: true,
          child: Pressable(
            onTap: on ? () => _step(left ? -1 : 1) : null,
            child: SizedBox(
              width: S.x12,
              height: S.x12,
              child: Center(
                child: BoldChevron(
                    left: left,
                    height: S.x5,
                    color: on ? p.ink : p.ink.withValues(alpha: .22)),
              ),
            ),
          ),
        );

    Widget cell(int day) {
      final id = dayLabelOf(DateTime(_month.year, _month.month, day));
      final v = widget.recovery[id];
      final open = widget.days.contains(id) || id == widget.today;
      final colour = v == null ? p.ink3 : recoveryColor(v);
      return Semantics(
        label: v == null ? '$id, no recovery' : '$id, recovery ${v.round()}%',
        button: true,
        enabled: open,
        excludeSemantics: true,
        child: Pressable(
          onTap: open ? () => Navigator.of(c).pop(id) : null,
          child: Container(
            height: S.x12 + S.x2,
            alignment: Alignment.center,
            child: Container(
              width: S.x10,
              height: S.x10,
              alignment: Alignment.center,
              decoration: id == widget.selected
                  ? BoxDecoration(
                      color: p.ink.withValues(alpha: .12),
                      borderRadius: R.rLg)
                  : null,
              child: Text('$day',
                  style: F.n17.copyWith(color: colour, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
    }

    Widget key(Color colour, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: S.x2,
              height: S.x2,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle)),
          const SizedBox(width: S.x2),
          Text(text, style: F.num(F.cap).copyWith(color: colour, fontWeight: FontWeight.w600)),
        ]);

    return Material(
      color: p.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.gutter, S.x4, S.gutter, S.x6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              arrow(true, canBack),
              Expanded(
                child: Center(
                  child: Semantics(
                    header: true,
                    child: Text('${_names[_month.month - 1]} ${_month.year}',
                        style: F.num(F.head).copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                  ),
                ),
              ),
              arrow(false, canForward),
            ]),
            const SizedBox(height: S.x8),
            Row(children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(w,
                        style: F.caps.copyWith(
                            color: p.ink3, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
            const SizedBox(height: S.x3),
            for (var r = 0; r < rows; r++)
              Row(children: [
                for (var k = 0; k < 7; k++)
                  Expanded(
                    child: () {
                      final day = r * 7 + k - lead + 1;
                      return day < 1 || day > count
                          ? const SizedBox(height: S.x12 + S.x2)
                          : cell(day);
                    }(),
                  ),
              ]),
            const SizedBox(height: S.x5),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: S.x4, children: [
                key(C.recRed, '<34%'),
                key(C.recYellow, '34% - 66%'),
                key(C.recGreen, '>66%'),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
