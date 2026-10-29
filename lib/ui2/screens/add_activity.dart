// ADD ACTIVITY — the sheet behind Home's "+ Add activity" button: name what you
// did, say when it started and ended, save. A workout writes through the same
// seam as the Log-a-workout form (`logManualWorkout`), so the session is scored
// from the band's own heart rate over those times, or saved unscored and says
// so. A sleep or a nap (the Sleep tab) is stored the way the Sleep and Naps
// screens store one entered by hand: a sleep window for the night it ends on,
// or a manual nap, and the day re-analysed from it.
//
// The sheet has two pages, as one sheet: the form, and the list the form's
// "Select activity" row opens ([ActivityChooser]: searchable, with the strain,
// recovery and sleep kinds apart; Start Activity opens the same list). Saving
// stays out of reach until an activity is chosen and the window can be saved.

import 'package:flutter/material.dart';

import '../../compute/manual_session.dart';
import '../../data/day_label.dart';
import '../../data/db.dart' show LocalDb;
import '../../health/health_export.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart';
import '../ui2.dart';
import 'home_screen.dart' show monthShortName, repoOf;
import 'log_workout.dart' show appOf;
import 'window_editor.dart';

/// Opens the sheet. Resolves true when an activity was saved.
Future<bool?> openAddActivity(BuildContext c, {DateTime? now}) =>
    AppSheet.open<bool>(
      c,
      builder: (_) => _AddActivitySheet(now: now),
      scroll: true,
      bare: true,
    );

/// The session an Edit Activity sheet changes: its id, what it is, and when.
typedef EditedSession = ({
  String id,
  Activity activity,
  DateTime start,
  DateTime end,
});

/// Opens the same sheet on a saved session: its activity and its times, and
/// SAVE writes them back over it. Resolves true when it was saved.
Future<bool?> openEditActivity(
  BuildContext c,
  EditedSession session, {
  DateTime? now,
}) => AppSheet.open<bool>(
  c,
  builder: (_) => _AddActivitySheet(now: now, edit: session),
  scroll: true,
  bare: true,
);

/// What the list hands back: an activity, or a sleep or a nap.
typedef ActivityChoice = ({Activity? activity, WindowKind? sleep});

/// The activity list on a sheet of its own, for Start Activity: with the Sleep
/// tab, since a sleep or a nap can be started and ended by hand there. Null
/// when it was closed.
Future<ActivityChoice?> chooseActivity(BuildContext c) =>
    AppSheet.open<ActivityChoice>(
      c,
      builder: (sheet) => _SheetFrame(
        child: ActivityChooser(
          close: true,
          onPick: (r) => Navigator.of(sheet).pop(r),
          onBack: () => Navigator.of(sheet).pop(),
        ),
      ),
      scroll: true,
      bare: true,
    );

/// A sleep is the night it ends on, re-derived from the window; a nap is a
/// manual nap on the day it starts, and the day's naps re-read. The one write
/// behind Add Activity's Sleep tab and the end of a started sleep or nap.
Future<void> saveRestWindow(
  AppState? app,
  WindowKind k,
  DateTime start,
  DateTime end,
) async {
  if (k == WindowKind.sleep) {
    await app?.setSleepOverride(dayLabelOf(end), start, end);
  } else {
    await LocalDb.putNapEdit(
      dayId: dayLabelOf(start),
      startTs: start.millisecondsSinceEpoch ~/ 1000,
      endTs: end.millisecondsSinceEpoch ~/ 1000,
      source: 'manual',
    );
    await app?.reanalyzeForNapEdit();
  }
  app?.insightsRevision.value++;
}

/// The sheet's ground: lit at the top, a handle, then [child].
class _SheetFrame extends StatelessWidget {
  final Widget child;
  const _SheetFrame({required this.child});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final top = Color.alphaBlend(C.dialSleep.withValues(alpha: .10), p.card);
    return FractionallySizedBox(
      heightFactor: .825,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(R.xxl + S.x3),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, p.bg],
            stops: const [0, .55],
          ),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: Column(
          children: [
            const SizedBox(height: S.x5),
            Container(
              width: S.x16 + S.x4,
              height: S.x1,
              decoration: BoxDecoration(
                color: p.ink.withValues(alpha: .22),
                borderRadius: R.rPill,
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _AddActivitySheet extends StatefulWidget {
  final DateTime? now;

  /// Set when this edits a saved session instead of adding one.
  final EditedSession? edit;
  const _AddActivitySheet({this.now, this.edit});

  @override
  State<_AddActivitySheet> createState() => _AddActivitySheetState();
}

class _AddActivitySheetState extends State<_AddActivitySheet> {
  late DateTime _start, _end;
  Activity? _activity;

  /// A sleep or a nap, picked from the Sleep tab, in place of an activity.
  WindowKind? _sleep;
  bool _picking = false, _saving = false;
  String? _message;
  List<SessionSpan> _spans = const [];

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e == null) {
      _hourToNow();
    } else {
      _activity = e.activity;
      _start = e.start;
      _end = e.end;
    }
    _loadSpans();
  }

  /// An hour, ending now to the minute.
  void _hourToNow() {
    final n = _now;
    _end = DateTime(n.year, n.month, n.day, n.hour, n.minute);
    _start = DateTime(n.year, n.month, n.day, n.hour - 1, n.minute);
  }

  /// Last night: eight hours to 07:00, or to now on a morning before it.
  void _lastNight() {
    final n = _now;
    var end = DateTime(n.year, n.month, n.day, 7);
    if (end.isAfter(n)) {
      end = DateTime(n.year, n.month, n.day, n.hour, n.minute);
    }
    _end = end;
    _start = DateTime(end.year, end.month, end.day, end.hour - 8, end.minute);
  }

  Future<void> _loadSpans() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final s = await repo.savedSessionSpans();
      if (mounted) setState(() => _spans = s);
    } catch (_) {
      /* the write seam checks again */
    }
  }

  int get _startSec => _start.millisecondsSinceEpoch ~/ 1000;
  int get _endSec => _end.millisecondsSinceEpoch ~/ 1000;

  /// Why the window cannot be saved for what is picked, or null.
  String? get _problem {
    final k = _sleep;
    if (k != null) return windowProblem(k, _start, _end, _now);
    return validateManualWindow(
      startSec: _startSec,
      endSec: _endSec,
      nowSec: _now.millisecondsSinceEpoch ~/ 1000,
      existing: _spans,
      editingId: widget.edit?.id ?? manualSessionId(_startSec),
    )?.message;
  }

  bool get _chosen => _activity != null || _sleep != null;
  bool get _canSave => _chosen && _problem == null && !_saving;

  Future<void> _pickDate({required bool start}) async {
    final at = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(2000),
      lastDate: _now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final moved = DateTime(
        picked.year,
        picked.month,
        picked.day,
        at.hour,
        at.minute,
      );
      if (start) {
        final span = _end.difference(_start);
        _start = moved;
        _end = _start.add(span);
      } else {
        _end = moved;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final at = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: at.hour, minute: at.minute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final moved = DateTime(
        at.year,
        at.month,
        at.day,
        picked.hour,
        picked.minute,
      );
      if (start) {
        final span = _end.difference(_start);
        _start = moved;
        _end = _start.add(span);
      } else {
        // Past midnight: a late run that finishes at 00:20 is the next day.
        _end = moved.isAfter(_start)
            ? moved
            : DateTime(
                at.year,
                at.month,
                at.day + 1,
                picked.hour,
                picked.minute,
              );
      }
    });
  }

  /// The times on the heart rate chart, for an activity, sleep or nap.
  Future<void> _onChart(WindowKind k) async {
    final title = k == WindowKind.sleep
        ? 'Set sleep'
        : (k == WindowKind.nap ? 'Set nap' : 'Set activity');
    final r = await openWindowEditor(
      context,
      kind: k,
      title: title,
      start: _start,
      end: _end,
      save: 'Use these times',
    );
    if (r == null || !mounted) return;
    setState(() {
      _start = r.$1;
      _end = r.$2;
    });
  }

  void _choose(ActivityChoice r) {
    setState(() {
      _picking = false;
      _message = null;
      final was = _sleep;
      _activity = r.activity;
      _sleep = r.sleep;
      // A sleep starts from last night; leaving one goes back to the hour.
      if (_sleep == WindowKind.sleep && was != WindowKind.sleep) _lastNight();
      if (_sleep != WindowKind.sleep && was == WindowKind.sleep) _hourToNow();
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    if (_sleep != null) return _saveSleep(_sleep!);
    final repo = repoOf(context);
    final a = _activity;
    if (repo == null || a == null) return;
    final nav = Navigator.of(context);
    final app = appOf(context);
    final l = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final edit = widget.edit;
      final r = edit == null
          ? await repo.logManualWorkout(
              startTs: _startSec,
              endTs: _endSec,
              type: a.typeKey,
            )
          : await repo.setWorkoutWindow(
              edit.id,
              startTs: _startSec,
              endTs: _endSec,
              type: a.typeKey,
            );
      await HealthExporter.exportWorkoutId(
        (r['workout_id'] ?? widget.edit?.id) as String?,
      );
      app?.insightsRevision.value++;
      if (r['unscored'] == true) {
        // Saved, with only its times: say so rather than pop silently.
        if (!mounted) return;
        setState(() {
          _saving = false;
          _message =
              l?.logWorkoutUnscoredSaved ??
              'Saved. No heart rate was recorded over that window, so it has '
                  'no strain and no calorie figure — the times are all this '
                  'one carries.';
        });
        return;
      }
      nav.pop(true);
    } on ManualWindowException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = e.error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message =
            l?.logWorkoutCouldNotSave ?? 'Could not save that — try again.';
      });
    }
  }

  /// A sleep is the night it ends on, re-derived from the window; a nap is a
  /// manual nap on the day it starts, and the day's naps re-read.
  Future<void> _saveSleep(WindowKind k) async {
    final app = appOf(context);
    final nav = Navigator.of(context);
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await saveRestWindow(app, k, _start, _end);
      nav.pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Could not save that — try again.';
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    return _SheetFrame(
      child: _picking
          ? ActivityChooser(
              sleep: widget.edit == null,
              onPick: _choose,
              onBack: () => setState(() => _picking = false),
            )
          : _form(c, P.of(c)),
    );
  }

  // ── page one: the form ───────────────────────────────────────────────────
  Widget _form(BuildContext c, P p) {
    final l = AppLocalizations.of(c);
    final bad = _problem;
    final a = _activity;
    final k = _sleep ?? (_activity != null ? WindowKind.workout : null);
    final name = _sleep == WindowKind.sleep
        ? 'Sleep'
        : (_sleep == WindowKind.nap ? 'Nap' : a?.displayName(c));
    final icon = _sleep == WindowKind.sleep
        ? LucideIcons.moon
        : (_sleep == WindowKind.nap ? LucideIcons.sun : a?.icon);
    return Column(
      children: [
        _sheetHeader(
          c,
          p,
          widget.edit == null ? 'Add activity' : 'Edit activity',
          leading: LucideIcons.x,
          onLeading: () => Navigator.of(c).pop(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(S.x4, S.x5, S.x4, S.x6),
            children: [
              Pressable(
                onTap: () => setState(() => _picking = true),
                semanticLabel: 'Select activity',
                child: Container(
                  height: S.x16 + S.half,
                  padding: const EdgeInsets.symmetric(horizontal: S.x5),
                  decoration: BoxDecoration(
                    color: p.ink.withValues(alpha: .09),
                    borderRadius: R.rXl,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon ?? LucideIcons.personStanding,
                        size: I.lg,
                        color: p.ink2,
                      ),
                      const SizedBox(width: S.x5),
                      Expanded(
                        child: Text(
                          (name ?? 'Select activity').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: F.body.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                      Icon(LucideIcons.chevronRight, size: I.lg, color: p.ink2),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: S.x12 + S.x2),
              _rule(p, 'Time'),
              const SizedBox(height: S.x8 + S.x1),
              _timeRow(c, p, 'Start Time', _start, true),
              const SizedBox(height: S.x5),
              _timeRow(c, p, 'End Time', _end, false),
              if (k != null) ...[
                const SizedBox(height: S.x5),
                WindowPreview(
                  key: ValueKey('preview-$k'),
                  start: _startSec,
                  end: _endSec,
                  kind: k,
                  onChanged: (newStart, newEnd) {
                    setState(() {
                      _start = DateTime.fromMillisecondsSinceEpoch(
                        newStart * 1000,
                      );
                      _end = DateTime.fromMillisecondsSinceEpoch(newEnd * 1000);
                    });
                  },
                  onExpand: () => _onChart(k),
                ),
              ],
              if (bad != null && _chosen) ...[
                const SizedBox(height: S.x5),
                Text(
                  bad,
                  style: F.cap.copyWith(color: p.on(C.orange), height: 1.4),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: S.x5),
                Text(
                  _message!,
                  style: F.cap.copyWith(color: p.ink2, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x12, S.x2, S.x12, S.x16 + S.x4),
          child: _SaveButton(
            label: _saving ? (l?.logWorkoutSaving ?? 'Saving…') : 'Save',
            enabled: _canSave,
            onTap: _save,
          ),
        ),
      ],
    );
  }

  Widget _timeRow(BuildContext c, P p, String label, DateTime at, bool start) {
    final l = AppLocalizations.of(c);
    Widget chip(String text, VoidCallback onTap, String hint, double width) =>
        Pressable(
          onTap: onTap,
          semanticLabel: '$label, $hint: $text',
          child: Container(
            width: width,
            height: S.x8 + S.x1,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.ink.withValues(alpha: .09),
              borderRadius: R.rMd,
            ),
            child: Text(text, style: F.body.copyWith(color: p.ink)),
          ),
        );
    String two(int v) => v.toString().padLeft(2, '0');
    return Row(
      children: [
        Expanded(
          child: Text(label, style: F.body.copyWith(color: p.ink)),
        ),
        chip(
          '${monthShortName(at.month, l)} ${at.day}',
          () => _pickDate(start: start),
          'date',
          S.x16 + S.x1 + S.half,
        ),
        const SizedBox(width: S.x2 + S.half),
        chip(
          '${at.hour}:${two(at.minute)}',
          () => _pickTime(start: start),
          'time',
          S.x12 + S.x2 + S.half + S.half,
        ),
      ],
    );
  }
}

Widget _sheetHeader(
  BuildContext c,
  P p,
  String title, {
  required IconData leading,
  required VoidCallback onLeading,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(S.x3, S.x3, S.x3, 0),
    child: SizedBox(
      height: S.tap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              onTap: onLeading,
              semanticLabel: leading == LucideIcons.x ? 'Close' : 'Back',
              child: SizedBox(
                width: S.tap,
                height: S.tap,
                child: Icon(leading, size: I.lg, color: p.ink),
              ),
            ),
          ),
          Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: F.body.copyWith(
                color: p.ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _rule(P p, String text) => Row(
  children: [
    Text(text.toUpperCase(), style: F.over.copyWith(color: p.ink2)),
    const SizedBox(width: S.x3),
    Expanded(child: Container(height: 1, color: p.ink.withValues(alpha: .12))),
  ],
);

/// SELECT YOUR ACTIVITY: every activity, searchable, under ALL, STRAIN and
/// RECOVERY tabs, and a SLEEP tab with a sleep and a nap when [sleep] is set.
/// Add Activity shows it as its second page; Start Activity on a sheet.
class ActivityChooser extends StatefulWidget {
  final ValueChanged<ActivityChoice> onPick;
  final VoidCallback onBack;

  /// Offer the Sleep tab.
  final bool sleep;

  /// A close cross in the corner rather than a back chevron.
  final bool close;

  const ActivityChooser({
    super.key,
    required this.onPick,
    required this.onBack,
    this.sleep = true,
    this.close = false,
  });

  @override
  State<ActivityChooser> createState() => _ActivityChooserState();
}

class _ActivityChooserState extends State<ActivityChooser> {
  String _q = '';
  int _tab = 0;

  /// Recovery work is the still kind (stretching, yoga, breathwork); the rest
  /// is strain. Sleep is a sleep or a nap, entered by its times.
  List<String> get _tabs => [
    'All',
    'Strain',
    'Recovery',
    if (widget.sleep) 'Sleep',
  ];

  Widget _row(
    BuildContext c,
    P p,
    IconData icon,
    String name,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: S.x3),
    child: Pressable(
      onTap: onTap,
      semanticLabel: name,
      child: Container(
        height: S.x16 + S.x3,
        padding: const EdgeInsets.symmetric(horizontal: S.x5),
        decoration: BoxDecoration(
          color: p.ink.withValues(alpha: .09),
          borderRadius: R.rXl,
        ),
        child: Row(
          children: [
            SizedBox(
              width: S.x8,
              child: Icon(icon, size: I.lg, color: p.ink3),
            ),
            const SizedBox(width: S.x5),
            Expanded(
              child: Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.caps.copyWith(color: p.ink),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final q = _q.trim().toLowerCase();
    final sleepTab = widget.sleep && _tab == 3;
    final items = sleepTab
        ? const <Activity>[]
        : ([
            for (final a in allActivities)
              if (_tab == 0 || (_tab == 1) == (a.track != Track.stillness))
                if (q.isEmpty ||
                    a.displayName(c).toLowerCase().contains(q) ||
                    a.name.toLowerCase().contains(q))
                  a,
          ]..sort((x, y) => x.displayName(c).compareTo(y.displayName(c))));
    final sleeps = [
      for (final (k, icon, name) in const [
        (WindowKind.sleep, LucideIcons.moon, 'Sleep'),
        (WindowKind.nap, LucideIcons.sun, 'Nap'),
      ])
        if (sleepTab && (q.isEmpty || name.toLowerCase().contains(q)))
          (k, icon, name),
    ];
    final empty = sleepTab ? sleeps.isEmpty : items.isEmpty;
    return Column(
      children: [
        _sheetHeader(
          c,
          p,
          'Select your activity',
          leading: widget.close ? LucideIcons.x : LucideIcons.chevronLeft,
          onLeading: widget.onBack,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x5, S.x4, S.x3),
          child: Container(
            decoration: BoxDecoration(
              color: C.char.withValues(alpha: .55),
              borderRadius: R.rXl,
            ),
            child: AppField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              hint: 'Search for Activities',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: Pressable(
                    onTap: () => setState(() => _tab = i),
                    semanticLabel: _tabs[i],
                    child: SizedBox(
                      height: S.tap,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _tabs[i].toUpperCase(),
                              style: F.caps.copyWith(
                                color: i == _tab ? p.ink : p.ink2,
                              ),
                            ),
                            const SizedBox(height: S.x1),
                            Container(
                              height: 2,
                              width: S.x6,
                              color: i == _tab
                                  ? p.ink
                                  : const Color(0x00000000),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x2),
          child: _rule(p, sleepTab ? 'Sleep' : 'All A-Z'),
        ),
        Expanded(
          child: empty
              ? Padding(
                  padding: const EdgeInsets.all(S.x6),
                  child: Text(
                    'No activity by that name',
                    style: F.body.copyWith(color: p.ink3),
                  ),
                )
              : sleepTab
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x6),
                  children: [
                    for (final (k, icon, name) in sleeps)
                      _row(
                        c,
                        p,
                        icon,
                        name,
                        () => widget.onPick((activity: null, sleep: k)),
                      ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x6),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final a = items[i];
                    return _row(
                      c,
                      p,
                      a.icon,
                      a.displayName(c),
                      () => widget.onPick((activity: a, sleep: null)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The sheet's one action: an outline until it can be pressed, then a white
/// pill.
class _SaveButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _SaveButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: enabled ? onTap : null,
      semanticLabel: label,
      child: Container(
        height: S.x12 + S.x1 + S.half,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? p.ink : const Color(0x00000000),
          borderRadius: R.rPill,
          border: Border.all(
            color: enabled ? p.ink : p.ink.withValues(alpha: .3),
            width: 2,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: F.body.copyWith(
            color: enabled ? p.inkOn(p.ink) : p.ink.withValues(alpha: .4),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
      ),
    );
  }
}
