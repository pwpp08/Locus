// Picking a time of day: two columns that scroll up and down, hours and
// minutes, in the app's own numerals. No clock face, no dial to drag round.
//
// A sheet like every other (the grab bar, the title, one primary action). Each
// column loops, so 23 → 00 and 59 → 00 are a flick, and snaps onto a value; a
// soft tick marks each one passing under the band. Under a 12-hour clock the
// hours read "7 AM" … "12 PM" in the same one column, so there are always two.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/clock_format.dart' show use24HourClock;
import 'grammar.dart';
import 'lucide.dart';
import 'theme.dart';

/// Asks for a time of day. Null when the sheet was closed without choosing.
Future<TimeOfDay?> pickTime(
  BuildContext c, {
  required TimeOfDay initial,
  String title = 'Set time',
}) =>
    AppSheet.open<TimeOfDay>(
      c,
      // Its own height: the default caps a sheet at 9/16 of the screen, which
      // would clip the button on a short phone held sideways.
      scroll: true,
      builder: (_) => TimePickerSheet(initial: initial, title: title),
    );

class TimePickerSheet extends StatefulWidget {
  final TimeOfDay initial;
  final String title;

  const TimePickerSheet(
      {super.key, required this.initial, this.title = 'Set time'});

  @override
  State<TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<TimePickerSheet> {
  late int _hour = widget.initial.hour, _minute = widget.initial.minute;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final h24 = use24HourClock;
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
          const SizedBox(height: S.x4),
          SizedBox(
            height: _Wheel.rows * _Wheel.extent,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The band the chosen value sits in.
                IgnorePointer(
                  child: Container(
                    height: _Wheel.extent,
                    decoration:
                        BoxDecoration(color: p.card2, borderRadius: R.rLg),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Wheel(
                        label: 'Hours',
                        count: 24,
                        initial: _hour,
                        text: (i) => h24
                            ? i.toString().padLeft(2, '0')
                            : '${i % 12 == 0 ? 12 : i % 12} ${i < 12 ? 'AM' : 'PM'}',
                        onChanged: (v) => setState(() => _hour = v),
                      ),
                    ),
                    Text(':', style: F.n34.copyWith(color: p.ink3)),
                    Expanded(
                      child: _Wheel(
                        label: 'Minutes',
                        count: 60,
                        initial: _minute,
                        text: (i) => i.toString().padLeft(2, '0'),
                        onChanged: (v) => setState(() => _minute = v),
                      ),
                    ),
                  ],
                ),
                // Rows fade away above and below the band.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          p.card,
                          p.card.withValues(alpha: 0),
                          p.card.withValues(alpha: 0),
                          p.card,
                        ],
                        stops: const [0, .34, .66, 1],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x5),
          BigButton(
            'Set time',
            icon: LucideIcons.check,
            onTap: () => Navigator.of(c)
                .pop(TimeOfDay(hour: _hour, minute: _minute)),
          ),
        ],
      ),
    );
  }
}

/// One looping column of [count] values.
class _Wheel extends StatefulWidget {
  /// Rows in view, and the height of each.
  static const rows = 5;
  static const extent = S.x12;

  final String label;
  final int count, initial;
  final String Function(int) text;
  final ValueChanged<int> onChanged;

  const _Wheel({
    required this.label,
    required this.count,
    required this.initial,
    required this.text,
    required this.onChanged,
  });

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final FixedExtentScrollController _ctl =
      FixedExtentScrollController(initialItem: widget.initial);
  int? _shown;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Semantics(
      label: widget.label,
      child: ListWheelScrollView.useDelegate(
        controller: _ctl,
        itemExtent: _Wheel.extent,
        // Nearly flat: a list that moves, not a drum that curves away.
        diameterRatio: 40,
        perspective: .0005,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) {
          final v = i % widget.count;
          if (v == _shown) return;
          // Not for the value it opened on.
          if (_shown != null) HapticFeedback.selectionClick();
          _shown = v;
          widget.onChanged(v);
        },
        childDelegate: ListWheelChildLoopingListDelegate(children: [
          for (var i = 0; i < widget.count; i++)
            Center(
              child: Text(
                widget.text(i),
                maxLines: 1,
                style: F.n34.copyWith(color: p.ink),
              ),
            ),
        ]),
      ),
    );
  }
}
