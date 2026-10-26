// THE STRENGTH TRAINER — two tabs.
//
//   PROGRESS    total volume load (Σ reps × load) by day, week or month, and
//               the personal records: pulled from the sets the person logged,
//               added or changed by hand. A record opens its progress chart.
//   MY WORKOUTS start a workout now or build one (by hand or from notes with
//               the person's own AI key) and start it from the list.
//
// Everything on Progress is derived on read from `strength_set` and the
// records typed by hand (compute/strength_stats.dart); nothing is estimated.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compute/strength_stats.dart';
import '../../data/day_label.dart';
import '../../data/strength_store.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart';
import '../activity/exercise_image.dart';
import '../activity/live.dart';
import '../ui2.dart';
import 'home_screen.dart' show monthShortName, repoOf, weekdayShortName;
import 'strength_record.dart';
import 'strength_workout.dart';
import 'workout_screen.dart' show activityHost, loadSetHistory;

/// Starts a strength session now: the same live session as any other start,
/// with the exercises (and the sets planned for them) already on its list.
/// False when one is already running or it would not start.
Future<bool> startStrengthSession(BuildContext c,
    {List<PlannedExercise> plan = const []}) async {
  final AppState app;
  try {
    app = c.read<AppState>();
  } catch (_) {
    return false;
  }
  final a = activityByName('Weight training');
  if (a == null || app.activeWorkout != null) return false;
  final nav = Navigator.of(c);
  final repo = repoOf(c);
  double? weight;
  try {
    weight = ((await repo?.getProfile())?['weight_kg'] as num?)?.toDouble();
  } catch (_) {}
  final history = await loadSetHistory();
  app.startWorkout(type: a.typeKey, trackRoute: false);
  if (app.activeWorkout == null) return false;
  LiveDraft.begin(a, weightKg: weight);
  if (plan.isNotEmpty) {
    LiveDraft.current?.put('exercise_plan', [for (final e in plan) e.key]);
    LiveDraft.current?.put('planned', {
      for (final e in plan)
        e.key: [for (final s in e.sets) {'reps': s.reps, 'kg': s.kg}],
    });
  }
  await nav.push(MaterialPageRoute<void>(
    builder: (_) => liveFor(a,
        weightKg: weight, host: activityHost(app, history: history)),
  ));
  return true;
}

/// "1,846": a whole number of kilograms with its thousands marked.
String groupedKg(double v) {
  final s = v.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

class StrengthTrainerScreen extends StatefulWidget {
  /// 0 Progress, 1 My workouts.
  final int tab;

  /// Handed in by a test; read from the store when null.
  final ({List<LoggedRow> rows, List<TypedRecord> typed, List<StrengthWorkout> workouts})?
      data;
  const StrengthTrainerScreen({super.key, this.tab = 0, this.data});

  @override
  State<StrengthTrainerScreen> createState() => _StrengthTrainerScreenState();
}

class _StrengthTrainerScreenState extends State<StrengthTrainerScreen> {
  late int _tab = widget.tab;
  List<LoggedRow> _rows = const [];
  List<TypedRecord> _typed = const [];
  List<StrengthWorkout> _workouts = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    if (d != null) {
      _rows = d.rows;
      _typed = d.typed;
      _workouts = d.workouts;
      _loaded = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.data != null) return;
    try {
      final rows = await StrengthStore.loggedRows();
      final typed = await StrengthStore.typedRecords();
      final workouts = await StrengthStore.workouts();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _typed = typed;
        _workouts = workouts;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _info() => AppSheet.show<void>(context,
      title: 'Strength trainer',
      child: Text(
          'Volume load is every set\'s reps times its load, added up. A '
          'personal record is your heaviest load for a lift, or your most '
          'reps for one done with your body alone. They come from the sets '
          'you log; you can add one by hand or change one, and it stands '
          'until a logged set beats it.',
          style: F.body.copyWith(color: P.of(context).ink2, height: 1.45)));

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          // ── the header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x4, 0),
            child: SizedBox(
              height: S.x12,
              child: Row(children: [
                Pressable(
                  onTap: () => Navigator.of(c).maybePop(),
                  semanticLabel: 'Close',
                  child: SizedBox(
                    width: S.x12,
                    height: S.x12,
                    child: Icon(LucideIcons.x, size: I.lg + S.x1, color: p.ink),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Semantics(
                      header: true,
                      child: Text('STRENGTH TRAINER',
                          style: F.body.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6)),
                    ),
                  ),
                ),
                Pressable(
                  onTap: _info,
                  semanticLabel: 'About the strength trainer',
                  child: SizedBox(
                    width: S.x12,
                    height: S.x12,
                    child: Center(
                      child: Container(
                        width: S.x8 + S.half,
                        height: S.x8 + S.half,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: p.ink, width: 2),
                        ),
                        child: Text('i',
                            style: F.head.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w800,
                                height: 1)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: S.x6),
          // ── the tabs ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x6),
            child: Row(children: [
              _tabLabel(p, 'PROGRESS', 0),
              const SizedBox(width: S.x8 + S.half),
              _tabLabel(p, 'MY WORKOUTS', 1),
            ]),
          ),
          const SizedBox(height: S.x2),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _tab == 0
                    ? _ProgressTab(
                        rows: _rows, typed: _typed, onChanged: _load)
                    : _WorkoutsTab(workouts: _workouts, onChanged: _load),
          ),
        ]),
      ),
    );
  }

  Widget _tabLabel(P p, String label, int i) => Pressable(
        onTap: () => setState(() => _tab = i),
        semanticLabel: label[0] + label.substring(1).toLowerCase(),
        child: SizedBox(
          height: S.tap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            IntrinsicWidth(
              child: Column(children: [
                Text(label,
                    style: F.cap.copyWith(
                        color: i == _tab ? p.ink : p.ink3,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6)),
                const SizedBox(height: S.x1 + S.half),
                Container(
                    height: S.x1 - S.half,
                    color: i == _tab ? p.ink : const Color(0x00000000)),
              ]),
            ),
          ]),
        ),
      );
}

// ══════════════════ PROGRESS ══════════════════

class _ProgressTab extends StatefulWidget {
  final List<LoggedRow> rows;
  final List<TypedRecord> typed;
  final Future<void> Function() onChanged;
  const _ProgressTab(
      {required this.rows, required this.typed, required this.onChanged});

  @override
  State<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<_ProgressTab> {
  VolumeSpan _span = VolumeSpan.month;
  int _back = 0;
  int? _at;

  Future<void> _open(PersonalRecord r) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StrengthRecordScreen(exerciseKey: r.key)));
    await widget.onChanged();
  }

  Future<void> _add() async {
    if (await addRecordByHand(context) == true) await widget.onChanged();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final w = volumeWindow(widget.rows, _span, today: todayLabel(), back: _back);
    final records =
        mergeRecords(loggedRecords(widget.rows), widget.typed);
    final tallest = w.bars.fold<double>(0, (a, b) => a > (b.kg ?? 0) ? a : (b.kg ?? 0));
    final axis = volumeAxis(tallest);
    final ticks = [for (var v = 0.0; v <= axis.hi + 1; v += axis.step) v];
    final at = _at;
    final bar = at == null || at >= w.bars.length ? null : w.bars[at];

    String two(String label) {
      final d = DateTime.parse(label);
      return switch (_span) {
        VolumeSpan.week => '${weekdayShortName(d.weekday, l)}\n${d.day}',
        VolumeSpan.month => '${monthShortName(d.month, l)}\n${d.day}',
        VolumeSpan.sixMonths => '${monthShortName(d.month, l)}\n',
      };
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.x6, S.x4, S.x6, S.x16),
      children: [
        Text('Total Volume Load',
            style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
        const SizedBox(height: S.x3),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: S.x1),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    bar == null
                        ? 'AVG VOLUME LOAD'
                        : _barCaption(bar, l),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.cap.copyWith(
                        color: p.ink2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4)),
                const SizedBox(height: S.x1),
                Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                          (bar == null ? w.average : bar.kg) == null
                              ? '--'
                              : groupedKg((bar == null ? w.average : bar.kg)!),
                          style: F.n34
                              .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
                      const SizedBox(width: S.x1 + S.half),
                      Text('kg',
                          style: F.head.copyWith(
                              color: p.ink, fontWeight: FontWeight.w500)),
                    ]),
              ]),
            ),
          ),
          const SizedBox(width: S.x3),
          SizedBox(
            width: S.x16 * 3 - S.x6,
            child: Column(children: [
              _Seg(
                items: const ['W', 'M', '6M'],
                index: _span.index,
                onTap: (i) => setState(() {
                  _span = VolumeSpan.values[i];
                  _back = 0;
                  _at = null;
                }),
              ),
              const SizedBox(height: S.x4),
              Row(children: [
                _pageButton(p, true, () => setState(() {
                      _back++;
                      _at = null;
                    })),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_range(w, l),
                        maxLines: 1,
                        style: F.cap.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                  ),
                ),
                _pageButton(
                    p,
                    false,
                    _back == 0
                        ? null
                        : () => setState(() {
                              _back--;
                              _at = null;
                            })),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: S.x4),
        ScrubColumns(
          values: [for (final b in w.bars) b.kg],
          xLabels: [for (final b in w.bars) two(b.from)],
          lo: 0,
          hi: axis.hi,
          ticks: ticks,
          tickText: (v) => groupedKg(v),
          color: C.dialStrain,
          barWidth: S.x2 - S.half / 2,
          height: S.x16 * 4 + S.x3,
          gutter: S.x10 + S.x2,
          highlight: _at,
          label: 'Total volume load',
          describe: (i) => '${_barCaption(w.bars[i], l)}, '
              '${w.bars[i].kg == null ? 'nothing logged' : '${groupedKg(w.bars[i].kg!)} kilograms'}',
          onScrub: (i) => setState(() => _at = i),
        ),
        const SizedBox(height: S.x6),
        Row(children: [
          Expanded(
            child: Text('Personal Records',
                style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
          ),
          Pressable(
            onTap: _add,
            semanticLabel: 'Add a record',
            child: Container(
              height: S.x8 + S.x1,
              padding: const EdgeInsets.symmetric(horizontal: S.x3),
              decoration: BoxDecoration(
                  color: p.ink.withValues(alpha: .1), borderRadius: R.rPill),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.plus, size: I.sm, color: p.ink),
                const SizedBox(width: S.x1),
                Text('ADD',
                    style: F.over.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: S.x4),
        if (records.isEmpty)
          Text(
              'Log a lift and its record appears here, or add one by hand.',
              style: F.body.copyWith(color: p.ink3, height: 1.4))
        else
          for (final r in records) ...[
            _PrRow(record: r, onTap: () => _open(r)),
            const SizedBox(height: S.x3 + S.half),
          ],
      ],
    );
  }

  String _barCaption(VolumeBar b, AppLocalizations? l) {
    final d = DateTime.parse(b.from);
    final e = DateTime.parse(b.to);
    if (_span == VolumeSpan.week) {
      return '${weekdayShortName(d.weekday, l)} ${monthShortName(d.month, l)} ${d.day}'
          .toUpperCase();
    }
    if (_span == VolumeSpan.sixMonths) {
      return '${monthShortName(d.month, l)} ${d.year}'.toUpperCase();
    }
    return '${monthShortName(d.month, l)} ${d.day} - ${monthShortName(e.month, l)} ${e.day}'
        .toUpperCase();
  }

  String _range(VolumeWindow w, AppLocalizations? l) {
    final a = DateTime.parse(w.from), b = DateTime.parse(w.to);
    return '${monthShortName(a.month, l)} ${a.day} - ${monthShortName(b.month, l)} ${b.day}, '
            '${(b.year % 100).toString().padLeft(2, '0')}'
        .toUpperCase();
  }

  Widget _pageButton(P p, bool left, VoidCallback? onTap) => Pressable(
        onTap: onTap,
        semanticLabel: left ? 'Earlier' : 'Later',
        child: SizedBox(
          width: S.x6 + S.x1,
          height: S.tap,
          child: Center(
            child: BoldChevron(
                left: left,
                color: onTap == null ? p.ink.withValues(alpha: .25) : p.ink,
                height: S.x4),
          ),
        ),
      );
}

/// The segmented switch: a dark track, the chosen segment lifted.
class _Seg extends StatelessWidget {
  final List<String> items;
  final int index;
  final ValueChanged<int> onTap;
  const _Seg({required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      height: S.x10 + S.x2 - S.half,
      padding: const EdgeInsets.all(S.x1 + S.half / 2),
      decoration: BoxDecoration(
        color: Color.alphaBlend(C.char.withValues(alpha: .55), p.bg),
        borderRadius: R.rLg,
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: Pressable(
              onTap: () => onTap(i),
              semanticLabel: items[i],
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == index ? p.card2 : const Color(0x00000000),
                  borderRadius: R.rMd,
                ),
                child: Text(items[i],
                    style: F.cap.copyWith(
                        color: i == index ? p.ink : p.ink2,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// One personal record: the lift's photo, its name, its figure.
class _PrRow extends StatelessWidget {
  final PersonalRecord record;
  final VoidCallback onTap;
  const _PrRow({required this.record, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final def = exerciseByKey(record.key);
    final name = def?.label ?? record.key;
    final v = record.value;
    final text = v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    final unit = record.kind == RecordKind.reps ? 'reps' : 'kg';
    return Pressable(
      onTap: onTap,
      semanticLabel: '$name, record $text $unit',
      child: Container(
        height: S.x16 + S.half,
        padding: const EdgeInsets.fromLTRB(S.x2 + S.half, 0, S.x3, 0),
        decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
        child: Row(children: [
          ExerciseImage(
              def: def,
              width: S.x16 + S.x4,
              height: S.x12 + S.x8 + S.x1 - S.half,
              radius: R.rMd),
          const SizedBox(width: S.x4 + S.half),
          Expanded(
            child: Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: S.x2),
          Text(text,
              style: F.n24.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          const SizedBox(width: S.x1 + S.half),
          Text(unit,
              style: F.head.copyWith(color: p.ink2, fontWeight: FontWeight.w500)),
          const SizedBox(width: S.x2 + S.half),
          Icon(LucideIcons.chevronRight, size: I.md, color: p.ink3),
        ]),
      ),
    );
  }
}

// ══════════════════ MY WORKOUTS ══════════════════

class _WorkoutsTab extends StatelessWidget {
  final List<StrengthWorkout> workouts;
  final Future<void> Function() onChanged;
  const _WorkoutsTab({required this.workouts, required this.onChanged});

  Future<void> _quick(BuildContext c) async {
    final ok = await startStrengthSession(c);
    if (!ok && c.mounted) {
      AppSheet.show<void>(c,
          title: 'Could not start',
          child: Text(
              'A session is already running, or this one would not start. '
              'Only one can be live at a time.',
              style: F.body.copyWith(color: P.of(c).ink2, height: 1.45)));
    }
  }

  Future<void> _edit(BuildContext c, StrengthWorkout? w,
      {List<PlannedExercise>? seed, String? name}) async {
    await Navigator.of(c).push(MaterialPageRoute<void>(
        builder: (_) => StrengthWorkoutScreen(
            workout: w ?? StrengthWorkout.fresh(name ?? 'New workout', seed ?? const []),
            isNew: w == null)));
    await onChanged();
  }

  Future<void> _ai(BuildContext c) async {
    final r = await buildWorkoutFromNotes(c);
    if (r == null || !c.mounted) return;
    await _edit(c, null, seed: r.exercises, name: r.name);
  }

  Future<void> _menu(BuildContext c, StrengthWorkout w) async {
    final p = P.of(c);
    final pick = await AppSheet.show<String>(c,
        title: w.name,
        child: Column(children: [
          for (final (id, icon, label) in const [
            ('start', LucideIcons.play, 'Start'),
            ('edit', LucideIcons.pencil, 'Edit'),
            ('copy', LucideIcons.copy, 'Duplicate'),
            ('delete', LucideIcons.trash2, 'Delete'),
          ])
            Pressable(
              onTap: () => Navigator.of(c).pop(id),
              semanticLabel: label,
              child: SizedBox(
                height: S.x12,
                child: Row(children: [
                  Icon(icon, size: I.md, color: p.ink2),
                  const SizedBox(width: S.x4),
                  Text(label.toUpperCase(),
                      style: F.caps.copyWith(
                          color: p.ink, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
        ]));
    if (pick == null || !c.mounted) return;
    switch (pick) {
      case 'start':
        await startStrengthSession(c, plan: w.exercises);
      case 'edit':
        await _edit(c, w);
      case 'copy':
        await StrengthStore.saveWorkout(
            StrengthWorkout.fresh('${w.name} copy', w.exercises));
        await onChanged();
      case 'delete':
        final ok = await confirmRemove(c,
            title: 'Delete ${w.name}?',
            body: 'The workout goes. The sets you have logged stay.',
            remove: 'Delete');
        if (ok) {
          await StrengthStore.deleteWorkout(w.id);
          await onChanged();
        }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final rule = Container(height: 1, color: p.ink.withValues(alpha: .1));
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.x6, S.x4, S.x6, S.x16),
      children: [
        Text('Start a Workout',
            style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
        const SizedBox(height: S.x2),
        Text('Jump right into a workout and log exercises as you go.',
            style: F.body.copyWith(color: p.ink2, height: 1.4)),
        const SizedBox(height: S.x4),
        _Pill(
            label: 'QUICK START',
            filled: true,
            onTap: () => _quick(c)),
        const SizedBox(height: S.x8),
        rule,
        const SizedBox(height: S.x6),
        Text('My Workouts',
            style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
        const SizedBox(height: S.x6 + S.x1),
        _AiCard(onTap: () => _ai(c)),
        const SizedBox(height: S.x3 + S.half),
        _Pill(label: 'BUILD A WORKOUT', onTap: () => _edit(c, null)),
        const SizedBox(height: S.x8),
        rule,
        const SizedBox(height: S.x3),
        for (final w in workouts) ...[
          const SizedBox(height: S.x3 + S.half),
          _WorkoutRow(
              workout: w,
              onTap: () => _edit(c, w),
              onMenu: () => _menu(c, w)),
        ],
      ],
    );
  }
}

/// A full-width pill: white (the primary) or a dark slate.
class _Pill extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: label[0] + label.substring(1).toLowerCase(),
      child: Container(
        height: S.x12 + S.x1 + S.half,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? p.ink : p.card,
          borderRadius: R.rPill,
        ),
        child: Text(label,
            style: F.body.copyWith(
                color: filled ? p.inkOn(p.ink) : p.ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6)),
      ),
    );
  }
}

/// "Generate with AI": a card with a purple-to-blue edge.
class _AiCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AiCard({required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const edge = [C.lavender, C.dialStrain];
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Build a workout from your notes',
      child: Container(
        padding: const EdgeInsets.all(S.half + S.half),
        decoration: const BoxDecoration(
          borderRadius: R.rXl,
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: edge),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(S.x4 + S.half, S.x4, S.x4, S.x4),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(R.xl - S.half)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(C.lavender.withValues(alpha: .16), p.bg),
                Color.alphaBlend(C.dialStrain.withValues(alpha: .10), p.bg),
              ],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Generate with AI',
                style: F.head.copyWith(color: p.ink, fontWeight: FontWeight.w500)),
            const SizedBox(height: S.x2),
            Text(
                'Describe your workout and it will be built for you — type '
                'it out or paste your notes.',
                style: F.body.copyWith(color: p.ink2, height: 1.4)),
            const SizedBox(height: S.x3),
            Row(children: [
              ShaderMask(
                shaderCallback: (r) =>
                    const LinearGradient(colors: edge).createShader(r),
                blendMode: BlendMode.srcIn,
                child: Text('GET STARTED',
                    style: F.cap.copyWith(
                        color: C.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6)),
              ),
              const SizedBox(width: S.x3),
              const Icon(LucideIcons.arrowRight, size: I.md, color: C.dialStrain),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  final StrengthWorkout workout;
  final VoidCallback onTap, onMenu;
  const _WorkoutRow(
      {required this.workout, required this.onTap, required this.onMenu});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      height: S.x16 + S.half,
      decoration: BoxDecoration(color: p.card, borderRadius: R.rMd),
      child: Row(children: [
        Expanded(
          child: Pressable(
            onTap: onTap,
            semanticLabel: workout.name,
            child: Padding(
              padding: const EdgeInsets.only(left: S.x5 - S.half),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(workout.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.body.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6)),
              ),
            ),
          ),
        ),
        Pressable(
          onTap: onMenu,
          semanticLabel: 'More, ${workout.name}',
          child: SizedBox(
            width: S.x16,
            height: S.x16,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: S.x1),
                Container(
                  width: S.x2 + S.half,
                  height: S.x2 + S.half,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: p.ink, width: S.half),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
