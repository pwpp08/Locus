// CREATE SCHEDULE — one sheet, three steps, laid out on its reference:
//
//   1. SELECT DAYS WITH REPEAT WAKE TIMES: seven day keys, white once picked;
//      NEXT stays an outline until a day is.
//   2. CHOOSE ALARM MODE: Exact time, Sleep goal, In the green, or no alarm at
//      all (the schedule then only says when you wake, for the planner).
//   3. SET YOUR WAKE TIME: a drum of hours, minutes (and AM/PM on a 12-hour
//      clock) under one band, SAVE.
//
// Saving runs under the status overlay ("Saving your schedule…", then
// SUCCESS) and lands back where the flow was opened.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/alarm_item.dart';
import '../../state/alarm_manager.dart';
import '../../state/alarm_mode.dart';
import '../../state/clock_format.dart' show use24HourClock;
import '../screens/status_overlay.dart' show runWithStatus;
import '../ui2.dart';

/// Opens the flow and saves what it makes. True once a schedule is saved.
Future<bool> openScheduleFlow(BuildContext c, AlarmManager mgr) async {
  final item = await AppSheet.open<AlarmItem>(
    c,
    bare: true,
    scroll: true,
    builder: (_) => const ScheduleFlowSheet(),
  );
  if (item == null || !c.mounted) return false;
  return runWithStatus(
    c,
    working: 'Saving your schedule…',
    workingLine:
        item.ring ? 'Keep your band close and connected.' : null,
    done: 'Success!',
    doneLine: 'Your schedule has been saved.',
    task: () => mgr.addAlarm(item),
  );
}

enum _Step { days, mode, time }

/// The three steps on one sheet. Pops the schedule it made.
class ScheduleFlowSheet extends StatefulWidget {
  /// Where it opens; [_Step.days] unless a gallery case shows another.
  final int step;
  final Set<int> days;
  const ScheduleFlowSheet({super.key, this.step = 0, this.days = const {}});

  @override
  State<ScheduleFlowSheet> createState() => _ScheduleFlowSheetState();
}

class _ScheduleFlowSheetState extends State<ScheduleFlowSheet> {
  late _Step _step = _Step.values[widget.step];
  late final Set<int> _days = {...widget.days};
  AlarmMode _mode = AlarmMode.exact;
  bool _ring = true;
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);

  void _back() => switch (_step) {
        _Step.days => Navigator.of(context).pop(),
        _Step.mode => setState(() => _step = _Step.days),
        _Step.time => setState(() => _step = _Step.mode),
      };

  void _save() => Navigator.of(context).pop(AlarmItem(
        id: 'alarm_${DateTime.now().millisecondsSinceEpoch}',
        hour: _time.hour,
        minute: _time.minute,
        label: 'Wake up',
        days: {..._days},
        mode: _ring ? _mode : AlarmMode.exact,
        ring: _ring,
      ));

  void _info() {
    final (title, body) = switch (_step) {
      _Step.days => (
          'Repeat wake times',
          'Pick the days that wake at the same time. Days that wake at '
              'another time get a schedule of their own.'
        ),
      _Step.mode => (
          'Alarm modes',
          'Exact time buzzes at the time you set. Sleep goal buzzes once you '
              'have slept what you need, up to an hour early. In the green '
              'waits half an hour longer for the deep sleep recovery is built '
              'from. Both goal modes never buzz later than the time you set.'
        ),
      _Step.time => (
          'Wake time',
          _ring
              ? 'The latest the band buzzes on these days.'
              : 'When you plan to be up on these days. Bedtimes are '
                  'suggested from it; nothing buzzes.'
        ),
    };
    final p = P.of(context);
    AppSheet.show<void>(context,
        title: title,
        child: Text(body, style: F.body.copyWith(color: p.ink2, height: 1.45)));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final h = MediaQuery.sizeOf(c).height;
    final safe = MediaQuery.paddingOf(c).bottom;
    final title = switch (_step) {
      _Step.days => 'Select days with repeat wake times',
      _Step.mode => 'Choose alarm mode',
      _Step.time => 'Set your wake time',
    };
    return Container(
      height: (h * .62).clamp(S.x16 * 7, S.x16 * 9) + safe,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xxl)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.bgTop, p.bg],
        ),
      ),
      padding: EdgeInsets.fromLTRB(S.x3, S.x6, S.x3, safe + S.x8),
      child: Column(children: [
        // Back, the step's caps title, the info ring.
        SizedBox(
          height: S.tap,
          child: Row(children: [
            Pressable(
              onTap: _back,
              semanticLabel: _step == _Step.days ? 'Close' : 'Back',
              child: SizedBox.square(
                dimension: S.tap,
                child: Center(
                    child: BoldChevron(left: true, height: S.x4, color: p.ink)),
              ),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: F.caps.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3)),
              ),
            ),
            Pressable(
              onTap: _info,
              semanticLabel: 'About this step',
              child: SizedBox.square(
                dimension: S.tap,
                child: Icon(LucideIcons.info, size: I.md, color: p.ink),
              ),
            ),
          ]),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: motion(c, Motion.base),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: switch (_step) {
                _Step.days => _daysPage(c, p),
                _Step.mode => _modePage(c, p),
                _Step.time => _timePage(c, p),
              },
            ),
          ),
        ),
      ]),
    );
  }

  // ── 1. days ───────────────────────────────────────────────────────────────
  Widget _daysPage(BuildContext c, P p) {
    const keys = [(1, 'M'), (2, 'T'), (3, 'W'), (4, 'T'), (5, 'F'), (6, 'S'), (7, 'S')];
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
      'Saturday', 'Sunday'];
    return Column(children: [
      const Spacer(flex: 2),
      // The mark in its ring.
      Container(
        width: S.x8 - S.half,
        height: S.x8 - S.half,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.ink, width: S.hair * 2),
        ),
        alignment: Alignment.center,
        child: const LocusMark(size: S.x5 + S.half),
      ),
      const SizedBox(height: S.x4),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.x5),
        child: Text(
            'A steady sleep schedule can help you sleep better.',
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: p.ink2, height: 1.45)),
      ),
      const SizedBox(height: S.x5),
      LayoutBuilder(builder: (c, box) {
        // 39 a key, 8 between, smaller only where the sheet is too narrow.
        final side =
            ((box.maxWidth - S.x2 * 6) / 7).clamp(S.x6, S.x10 - S.hair);
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final (i, (d, k)) in keys.indexed) ...[
          if (i > 0) const SizedBox(width: S.x2),
          SizedBox.square(
            dimension: side,
            child: Pressable(
              onTap: () => setState(
                  () => _days.contains(d) ? _days.remove(d) : _days.add(d)),
              semanticLabel:
                  '${names[i]}, ${_days.contains(d) ? 'chosen' : 'not chosen'}',
              child: AnimatedContainer(
                duration: motion(c, Motion.fast),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _days.contains(d)
                      ? p.ink
                      : p.ink.withValues(alpha: .13),
                  borderRadius: const BorderRadius.all(Radius.circular(S.x1)),
                ),
                child: Text(k,
                    style: F.cap.copyWith(
                        color: _days.contains(d) ? p.bg : p.ink,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ]);
      }),
      const Spacer(flex: 4),
      _FlowButton('Next',
          filled: _days.isNotEmpty,
          onTap: _days.isEmpty
              ? null
              : () => setState(() => _step = _Step.mode)),
    ]);
  }

  // ── 2. mode ───────────────────────────────────────────────────────────────
  Widget _modePage(BuildContext c, P p) {
    const blurbs = {
      AlarmMode.exact: 'Wake up at the time you set.',
      AlarmMode.sleepGoal: "Wake up once you've slept what you need.",
      AlarmMode.inTheGreen: 'Wake up with time on top for recovery.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x10),
      child: Column(children: [
        const SizedBox(height: S.x6),
        for (final m in AlarmMode.values) ...[
          Pressable(
            onTap: () => setState(() {
              _mode = m;
              _ring = true;
              _step = _Step.time;
            }),
            semanticLabel: '${m.title}. ${blurbs[m]}',
            child: Container(
              width: double.infinity,
              height: S.x16 + S.x4 + S.half,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: S.x3),
              decoration: BoxDecoration(
                color: p.ink.withValues(alpha: .11),
                borderRadius: R.rLg,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(m.title,
                    style: F.cap.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4)),
                const SizedBox(height: S.half),
                Text(blurbs[m]!,
                    textAlign: TextAlign.center,
                    style: F.over.copyWith(
                        color: p.ink2,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0)),
              ]),
            ),
          ),
          const SizedBox(height: S.x2 + S.half),
        ],
        const SizedBox(height: S.x2),
        Pressable(
          onTap: () => setState(() {
            _ring = false;
            _step = _Step.time;
          }),
          semanticLabel: "Don't use an alarm",
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x2),
            child: Column(children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text("DON'T USE AN ALARM",
                    style: F.over.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3)),
                const SizedBox(width: S.x2),
                Icon(LucideIcons.arrowRight, size: I.md, color: p.ink),
              ]),
              const SizedBox(height: S.x2),
              Text(
                  'Get bed and wake time suggestions without being woken '
                  'by a buzz.',
                  textAlign: TextAlign.center,
                  style: F.cap.copyWith(color: p.ink2, height: 1.45)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── 3. time ───────────────────────────────────────────────────────────────
  Widget _timePage(BuildContext c, P p) => Column(children: [
        const Spacer(flex: 2),
        WakeTimeDrum(
          initial: _time,
          onChanged: (t) => _time = t,
        ),
        const Spacer(flex: 3),
        _FlowButton('Save', filled: false, onTap: _save),
      ]);
}

/// The flow's one button: a white pill when it can go, a dim outline while
/// it cannot, and a white outline for SAVE.
class _FlowButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  const _FlowButton(this.label, {required this.filled, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final on = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x5),
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: motion(c, Motion.fast),
          height: S.x12,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? p.ink : const Color(0x00000000),
            borderRadius: R.rPill,
            border: Border.all(
                color: on ? p.ink : p.ink.withValues(alpha: .22),
                width: S.half),
          ),
          child: Text(label.toUpperCase(),
              style: F.caps.copyWith(
                  color: filled ? p.bg : (on ? p.ink : p.ink.withValues(alpha: .3)),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6)),
        ),
      ),
    );
  }
}

/// The wake time on a drum: hours, minutes and, on a 12-hour clock, AM/PM,
/// under one rounded band. The row in the band is white and larger; the rest
/// grey, curving away.
class WakeTimeDrum extends StatefulWidget {
  final TimeOfDay initial;
  final ValueChanged<TimeOfDay> onChanged;
  const WakeTimeDrum(
      {super.key, required this.initial, required this.onChanged});

  @override
  State<WakeTimeDrum> createState() => _WakeTimeDrumState();
}

class _WakeTimeDrumState extends State<WakeTimeDrum> {
  late int _h = widget.initial.hour, _m = widget.initial.minute;

  void _set({int? h, int? m}) {
    _h = h ?? _h;
    _m = m ?? _m;
    widget.onChanged(TimeOfDay(hour: _h, minute: _m));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final h24 = use24HourClock;
    return SizedBox(
      height: _DrumColumn.extent * 7,
      child: Stack(alignment: Alignment.center, children: [
        IgnorePointer(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: S.x8),
            height: _DrumColumn.extent + S.x2,
            decoration: BoxDecoration(
                color: p.ink.withValues(alpha: .1), borderRadius: R.rXl),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _DrumColumn(
            label: 'Hours',
            count: h24 ? 24 : 12,
            initial: h24 ? _h : (_h % 12 == 0 ? 11 : _h % 12 - 1),
            text: (i) => h24 ? i.toString().padLeft(2, '0') : '${i + 1}',
            onChanged: (i) => _set(
                h: h24 ? i : ((i + 1) % 12) + (_h >= 12 ? 12 : 0)),
          ),
          _DrumColumn(
            label: 'Minutes',
            count: 60,
            initial: _m,
            text: (i) => i.toString().padLeft(2, '0'),
            onChanged: (i) => _set(m: i),
          ),
          if (!h24)
            _DrumColumn(
              label: 'AM or PM',
              count: 2,
              loop: false,
              initial: _h >= 12 ? 1 : 0,
              text: (i) => i == 0 ? 'AM' : 'PM',
              onChanged: (i) => _set(h: _h % 12 + (i == 1 ? 12 : 0)),
            ),
        ]),
      ]),
    );
  }
}

class _DrumColumn extends StatefulWidget {
  static const extent = S.x8 - S.x1 + S.half;

  final String label;
  final int count, initial;
  final bool loop;
  final String Function(int) text;
  final ValueChanged<int> onChanged;
  const _DrumColumn({
    required this.label,
    required this.count,
    required this.initial,
    required this.text,
    required this.onChanged,
    this.loop = true,
  });

  @override
  State<_DrumColumn> createState() => _DrumColumnState();
}

class _DrumColumnState extends State<_DrumColumn> {
  late final FixedExtentScrollController _ctl =
      FixedExtentScrollController(initialItem: widget.initial);
  late int _at = widget.initial;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final rows = [
      for (var i = 0; i < widget.count; i++)
        Center(
          child: Text(widget.text(i),
              style: F.num(F.t2).copyWith(
                  color: i == _at ? p.ink : p.ink2,
                  fontWeight: FontWeight.w400)),
        ),
    ];
    return SizedBox(
      width: S.x16,
      child: Semantics(
        label: widget.label,
        value: widget.text(_at),
        child: ListWheelScrollView.useDelegate(
          controller: _ctl,
          itemExtent: _DrumColumn.extent,
          diameterRatio: 1.25,
          perspective: .004,
          useMagnifier: true,
          magnification: 1.22,
          overAndUnderCenterOpacity: .62,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (i) {
            final v = i % widget.count;
            if (v == _at) return;
            HapticFeedback.selectionClick();
            setState(() => _at = v);
            widget.onChanged(v);
          },
          childDelegate: widget.loop
              ? ListWheelChildLoopingListDelegate(children: rows)
              : ListWheelChildListDelegate(children: rows),
        ),
      ),
    );
  }
}
