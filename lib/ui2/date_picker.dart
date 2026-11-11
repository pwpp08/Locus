// Choosing a day: a month at a time in a sheet, laid out as the recovery
// calendar is (bold chevrons either side of the month, the weekdays in caps,
// D-DIN days, the chosen one on a soft square). Replaces Material's date
// picker, whose volt header and its own type were the one calendar in the app
// that did not look like the others.

import 'package:flutter/material.dart';

import 'grammar.dart';
import 'marks.dart' show BoldChevron;
import 'theme.dart';

/// Opens the calendar and returns the day tapped, or null when dismissed. Days
/// outside [first]..[last], or that [selectable] refuses, are drawn dim and
/// cannot be chosen.
Future<DateTime?> pickDate(
  BuildContext c, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
  bool Function(DateTime day)? selectable,
  String title = 'Choose a day',
}) =>
    AppSheet.open<DateTime>(
      c,
      scroll: true,
      builder: (_) => DatePickerSheet(
        initial: initial,
        first: first,
        last: last,
        selectable: selectable,
        title: title,
      ),
    );

class DatePickerSheet extends StatefulWidget {
  final DateTime initial, first, last;
  final bool Function(DateTime day)? selectable;
  final String title;

  const DatePickerSheet({
    super.key,
    required this.initial,
    required this.first,
    required this.last,
    this.selectable,
    this.title = 'Choose a day',
  });

  @override
  State<DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<DatePickerSheet> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);

  static const _names = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST',
    'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _open(DateTime d) =>
      !d.isBefore(_day(widget.first)) &&
      !d.isAfter(_day(widget.last)) &&
      (widget.selectable?.call(d) ?? true);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final firstMonth = DateTime(widget.first.year, widget.first.month);
    final lastMonth = DateTime(widget.last.year, widget.last.month);
    final canBack = _month.isAfter(firstMonth);
    final canForward = _month.isBefore(lastMonth);
    final lead = _month.weekday - 1;
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = ((lead + count) / 7).ceil();
    final chosen = _day(widget.initial);
    final today = _day(DateTime.now());

    Widget arrow(bool left, bool on) => Pressable(
          onTap: on
              ? () => setState(() =>
                  _month = DateTime(_month.year, _month.month + (left ? -1 : 1)))
              : null,
          semanticLabel: left ? 'Previous month' : 'Next month',
          child: SizedBox(
            width: S.x12,
            height: S.x12,
            child: Center(
              child: BoldChevron(
                  left: left,
                  height: S.x4,
                  color: on ? p.ink : p.ink.withValues(alpha: .22)),
            ),
          ),
        );

    Widget cell(int n) {
      final d = DateTime(_month.year, _month.month, n);
      final open = _open(d);
      final on = d == chosen;
      return Pressable(
        onTap: open ? () => Navigator.of(c).pop(d) : null,
        semanticLabel: '${_names[d.month - 1]} $n${open ? '' : ', unavailable'}',
        child: SizedBox(
          height: S.x12,
          child: Center(
            child: Container(
              width: S.x10,
              height: S.x10,
              alignment: Alignment.center,
              decoration: on
                  ? BoxDecoration(
                      color: p.ink.withValues(alpha: .12), borderRadius: R.rLg)
                  : null,
              child: Text('$n',
                  style: F.n17.copyWith(
                      color: !open
                          ? p.ink.withValues(alpha: .22)
                          : d == today || on
                              ? p.ink
                              : p.ink2,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
          S.gutter, S.x3, S.gutter, S.x5 + MediaQuery.paddingOf(c).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: S.x10,
              height: S.x1,
              decoration: BoxDecoration(color: p.line, borderRadius: R.rPill),
            ),
          ),
          const SizedBox(height: S.x5),
          Semantics(
            header: true,
            child: Text(widget.title, style: F.t2.copyWith(color: p.ink)),
          ),
          const SizedBox(height: S.x3),
          Row(children: [
            arrow(true, canBack),
            Expanded(
              child: Center(
                child: Text('${_names[_month.month - 1]} ${_month.year}',
                    style: F.num(F.head).copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
              ),
            ),
            arrow(false, canForward),
          ]),
          const SizedBox(height: S.x4),
          Row(children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: F.caps
                          .copyWith(color: p.ink3, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
          const SizedBox(height: S.x2),
          for (var r = 0; r < rows; r++)
            Row(children: [
              for (var k = 0; k < 7; k++)
                Expanded(
                  child: () {
                    final n = r * 7 + k - lead + 1;
                    return n < 1 || n > count
                        ? const SizedBox(height: S.x12)
                        : cell(n);
                  }(),
                ),
            ]),
        ],
      ),
    );
  }
}
