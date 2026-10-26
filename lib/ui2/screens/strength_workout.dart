// A STRENGTH WORKOUT, built or opened: its name, its exercises in order, and
// each exercise's planned sets (reps and load). Drag the handle to reorder,
// tap a card to open its sets, ADD EXERCISE to pick from the library (photos
// and all), START WORKOUT to begin it. Every change is saved as it is made.
//
// "Generate with AI" lives here too: notes in, a proposed workout out, from
// the person's own AI key (ai/workout_ai.dart). Names the library cannot match
// are listed, never turned into lifts.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ai/workout_ai.dart';
import '../../coach/coach_config.dart';
import '../../coach/coach_engine.dart' show CoachException;
import '../../data/strength_store.dart';
import '../activity/catalogue.dart';
import '../activity/exercise_image.dart';
import '../activity/exercise_picker.dart';
import '../activity/live.dart' show SetHistory;
import '../ui2.dart';
import 'coach.dart' show CoachSetup, coachReadyNow;
import 'home_screen.dart' show go;
import 'strength_trainer.dart' show startStrengthSession;
import 'workout_screen.dart' show loadSetHistory;

/// A workout the AI proposed, matched against the library.
typedef BuiltWorkout = ({String name, List<PlannedExercise> exercises});

/// Notes in, a proposed workout out. Null when it was left, or when the AI
/// key is not set up (the sheet says so and offers the setup).
Future<BuiltWorkout?> buildWorkoutFromNotes(BuildContext c) async {
  if (!coachReadyNow(c)) {
    final go_ = await AppSheet.show<bool>(c,
        title: 'Generate with AI',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              'Your notes are turned into a workout by your own AI key. Add '
              'one and it is ready here.',
              style: F.body.copyWith(color: P.of(c).ink2, height: 1.45)),
          const SizedBox(height: S.x5),
          Builder(
              builder: (sheet) => BigButton('Set up AI',
                  onTap: () => Navigator.of(sheet).pop(true))),
        ]));
    if (go_ == true && c.mounted) go(c, const CoachSetup());
    return null;
  }
  return AppSheet.show<BuiltWorkout>(c, child: const _AiNotes());
}

class _AiNotes extends StatefulWidget {
  const _AiNotes();

  @override
  State<_AiNotes> createState() => _AiNotesState();
}

class _AiNotesState extends State<_AiNotes> {
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;
  BuiltWorkout? _built;
  List<String> _missed = const [];

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    final text = _notes.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await WorkoutAiEngine(config: context.read<CoachConfig>())
          .build(text);
      if (!mounted) return;
      if (r == null) {
        setState(() {
          _busy = false;
          _error = 'No workout came back from that. Try listing the lifts, '
              'one to a line.';
        });
        return;
      }
      final matched = <PlannedExercise>[];
      final missed = <String>[];
      for (final e in r.exercises) {
        final def = findExercise(e.name);
        if (def == null) {
          missed.add(e.name);
          continue;
        }
        matched.add(PlannedExercise(def.key, [
          for (var i = 0; i < e.sets; i++)
            PlannedSet(e.reps, def.bodyweight ? null : e.kg),
        ]));
      }
      setState(() {
        _busy = false;
        _built = (name: r.name, exercises: matched);
        _missed = missed;
      });
      if (missed.isEmpty && matched.isNotEmpty) {
        Navigator.of(context).pop(_built);
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is CoachException
            ? e.message
            : 'Could not reach your AI. Check its setup and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final built = _built;
    return Padding(
      padding: EdgeInsets.only(
          left: S.x4,
          right: S.x4,
          top: S.x4,
          bottom: MediaQuery.viewInsetsOf(c).bottom + S.x5),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Generate with AI',
                style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: S.x2),
            if (built == null) ...[
              Text(
                  'Paste or type your workout: the lifts, and sets and reps '
                  'if you have them.',
                  style: F.body.copyWith(color: p.ink2, height: 1.4)),
              const SizedBox(height: S.x4),
              AppField(
                controller: _notes,
                hint: 'Push day: bench 4x8 at 60, overhead press 3x10…',
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                autofocus: true,
                errorText: _error,
              ),
              const SizedBox(height: S.x4),
              BigButton(_busy ? 'Building…' : 'Build workout',
                  onTap: _busy ? null : _build),
            ] else ...[
              Text(
                  built.exercises.isEmpty
                      ? 'None of those lifts matched the library.'
                      : '${built.exercises.length} lift${built.exercises.length == 1 ? '' : 's'} matched.',
                  style: F.body.copyWith(color: p.ink2, height: 1.4)),
              const SizedBox(height: S.x2),
              Text('Left out, not in the library: ${_missed.join(', ')}.',
                  style: F.body.copyWith(color: p.on(C.orange), height: 1.4)),
              const SizedBox(height: S.x4),
              if (built.exercises.isNotEmpty)
                BigButton('Use these',
                    onTap: () => Navigator.of(c).pop(built)),
            ],
          ]),
    );
  }
}

// ══════════════════ THE WORKOUT ══════════════════

/// The mutable twin of a [PlannedExercise] while it is being edited.
class _Ex {
  final int id;
  final String key;
  final List<_Set> sets;
  _Ex(this.id, this.key, this.sets);
}

class _Set {
  final int id;
  int reps;
  double? kg;
  _Set(this.id, this.reps, this.kg);
}

class StrengthWorkoutScreen extends StatefulWidget {
  final StrengthWorkout workout;

  /// Not saved yet: it is, once it has an exercise.
  final bool isNew;
  const StrengthWorkoutScreen({super.key, required this.workout, this.isNew = false});

  @override
  State<StrengthWorkoutScreen> createState() => _StrengthWorkoutScreenState();
}

class _StrengthWorkoutScreenState extends State<StrengthWorkoutScreen> {
  late String _name = widget.workout.name;
  late final List<_Ex> _ex;
  int _ids = 0;
  int? _open;
  Map<String, SetHistory> _history = const {};

  @override
  void initState() {
    super.initState();
    _ex = [
      for (final e in widget.workout.exercises)
        _Ex(_ids++, e.key,
            [for (final s in e.sets) _Set(_ids++, s.reps, s.kg)]),
    ];
    loadSetHistory().then((h) {
      if (mounted) _history = h;
    });
  }

  List<PlannedExercise> get _plan => [
        for (final e in _ex)
          PlannedExercise(
              e.key, [for (final s in e.sets) PlannedSet(s.reps, s.kg)]),
      ];

  Future<void> _save() async {
    if (_ex.isEmpty && widget.isNew) return;
    try {
      await StrengthStore.saveWorkout(
          widget.workout.copyWith(name: _name, exercises: _plan));
    } catch (_) {/* the next change writes it again */}
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _name);
    final v = await AppSheet.show<String>(context,
        title: 'Name',
        child: Builder(
            builder: (sheet) => Column(children: [
                  AppField(
                      controller: c,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (t) => Navigator.of(sheet).pop(t)),
                  const SizedBox(height: S.x4),
                  BigButton('Save', onTap: () => Navigator.of(sheet).pop(c.text)),
                ])));
    c.dispose();
    final t = v?.trim();
    if (t == null || t.isEmpty || !mounted) return;
    setState(() => _name = t);
    await _save();
  }

  Future<void> _add() async {
    final key = await showExercisePicker(context,
        mode: ExercisePickMode.add, selectedKeys: {for (final e in _ex) e.key});
    if (key == null || !mounted) return;
    final prev = _history[key]?.previous;
    final def = exerciseByKey(key);
    setState(() {
      _ex.add(_Ex(_ids++, key, [
        for (var i = 0; i < 3; i++)
          _Set(_ids++, prev?.reps ?? 10, def?.bodyweight == true ? null : prev?.loadKg),
      ]));
      _open = _ex.length - 1;
    });
    await _save();
  }

  void _info(_Ex e) {
    final def = exerciseByKey(e.key);
    AppSheet.show<void>(context,
        title: def?.label ?? e.key,
        child: _ExerciseInfo(def: def));
  }

  Future<void> _start() async {
    await _save();
    if (!mounted) return;
    final ok = await startStrengthSession(context, plan: _plan);
    if (!ok && mounted) {
      AppSheet.show<void>(context,
          title: 'Could not start',
          child: Text(
              'A session is already running, or this one would not start.',
              style: F.body.copyWith(color: P.of(context).ink2, height: 1.45)));
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final bottom = MediaQuery.paddingOf(c).bottom;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x4, 0),
            child: SizedBox(
              height: S.x12,
              child: Row(children: [
                Pressable(
                  onTap: () => Navigator.of(c).maybePop(),
                  semanticLabel: 'Back',
                  child: SizedBox(
                    width: S.x12 + S.x2,
                    height: S.x12,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: S.x2),
                        child: Icon(LucideIcons.arrowLeft,
                            size: I.lg + S.x2, color: p.ink),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Pressable(
                    onTap: _rename,
                    semanticLabel: 'Workout name, $_name. Rename',
                    child: Center(
                      child: Text(_name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: F.body.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6)),
                    ),
                  ),
                ),
                const SizedBox(width: S.x12 + S.x2),
              ]),
            ),
          ),
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.fromLTRB(S.x6, S.x6, S.x6, S.x6),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, _, _) => Material(
                  type: MaterialType.transparency, child: child),
              onReorder: (a, b) {
                setState(() {
                  if (b > a) b--;
                  final openKey = _open == null ? null : _ex[_open!].id;
                  _ex.insert(b, _ex.removeAt(a));
                  _open = openKey == null
                      ? null
                      : _ex.indexWhere((e) => e.id == openKey);
                });
                _save();
              },
              footer: Padding(
                padding: const EdgeInsets.only(top: S.x1),
                child: _AddExerciseCard(onTap: _add),
              ),
              children: [
                for (var i = 0; i < _ex.length; i++)
                  Padding(
                    key: ValueKey(_ex[i].id),
                    padding: const EdgeInsets.only(bottom: S.x2 + S.half),
                    child: _ExerciseCard(
                      index: i,
                      ex: _ex[i],
                      open: _open == i,
                      onToggle: () => setState(() => _open = _open == i ? null : i),
                      onInfo: () => _info(_ex[i]),
                      onChanged: () {
                        setState(() {});
                        _save();
                      },
                      onAddSet: () {
                        final last = _ex[i].sets.isEmpty ? null : _ex[i].sets.last;
                        setState(() => _ex[i].sets.add(
                            _Set(_ids++, last?.reps ?? 10, last?.kg)));
                        _save();
                      },
                      onRemoveSet: (s) {
                        setState(() => _ex[i].sets.remove(s));
                        _save();
                      },
                      onRemove: () {
                        setState(() {
                          _ex.removeAt(i);
                          _open = null;
                        });
                        _save();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Container(
            color: Color.alphaBlend(C.char.withValues(alpha: .5), p.bg),
            padding: EdgeInsets.fromLTRB(S.x8 + S.x1, S.x4, S.x8 + S.x1, S.x4 + bottom),
            child: Pressable(
              onTap: _ex.isEmpty ? null : _start,
              semanticLabel: 'Start workout',
              child: Container(
                height: S.x12 + S.x1 + S.half,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: R.rPill,
                  border: Border.all(
                      color: _ex.isEmpty
                          ? C.optimal.withValues(alpha: .35)
                          : C.optimal,
                      width: S.x1 - S.half / 2),
                ),
                child: Text('START WORKOUT',
                    style: F.body.copyWith(
                        color: _ex.isEmpty
                            ? C.optimal.withValues(alpha: .4)
                            : C.optimal,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One exercise's card: photo, name, set count, handle — and when open, the
/// table of its sets.
class _ExerciseCard extends StatelessWidget {
  final int index;
  final _Ex ex;
  final bool open;
  final VoidCallback onToggle, onInfo, onChanged, onAddSet, onRemove;
  final void Function(_Set) onRemoveSet;

  const _ExerciseCard({
    required this.index,
    required this.ex,
    required this.open,
    required this.onToggle,
    required this.onInfo,
    required this.onChanged,
    required this.onAddSet,
    required this.onRemove,
    required this.onRemoveSet,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final def = exerciseByKey(ex.key);
    final n = ex.sets.length;
    return ClipRRect(
      borderRadius: R.rXxl,
      child: Column(children: [
        Container(
          color: open ? p.card2 : p.card,
          padding: const EdgeInsets.all(S.x1 + S.half / 2),
          child: Row(children: [
            Pressable(
              onTap: onInfo,
              semanticLabel: 'About ${def?.label ?? ex.key}',
              child: ExerciseImage(
                  def: def,
                  width: S.x16 + S.x4,
                  height: S.x16 + S.half,
                  radius: R.rLg),
            ),
            Expanded(
              child: Pressable(
                onTap: onToggle,
                semanticLabel: '${def?.label ?? ex.key}, $n sets',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(def?.label ?? ex.key,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: F.body.copyWith(
                                color: p.ink, fontWeight: FontWeight.w500)),
                        Text('$n ${n == 1 ? 'Set' : 'Sets'}',
                            style: F.body.copyWith(color: p.ink3)),
                      ]),
                  ),
                ),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: S.x12,
                height: S.x16,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < 2; i++) ...[
                      if (i > 0) const SizedBox(height: S.x1 + S.half),
                      Container(
                        width: S.x5,
                        height: S.x1 - S.half / 2,
                        decoration: BoxDecoration(
                            color: p.ink, borderRadius: R.rPill),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ]),
        ),
        if (open)
          Container(
            color: Color.alphaBlend(C.char.withValues(alpha: .35), p.card),
            padding: const EdgeInsets.fromLTRB(S.x4, S.x6, S.x2, S.x4),
            child: Column(children: [
              Row(children: [
                const SizedBox(width: S.x8 + S.x5),
                SizedBox(
                  width: S.x16 + S.x2 + S.x6,
                  child: Text('REPS',
                      style: F.cap.copyWith(
                          color: p.ink2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4)),
                ),
                Text('WEIGHT (kg)',
                    style: F.cap.copyWith(
                        color: p.ink2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4)),
              ]),
              const SizedBox(height: S.x3),
              for (var i = 0; i < ex.sets.length; i++)
                Padding(
                  key: ValueKey(ex.sets[i].id),
                  padding: const EdgeInsets.only(bottom: S.x4),
                  child: Row(children: [
                    SizedBox(
                      width: S.x8 + S.x1,
                      child: Text('${i + 1}',
                          style: F.n24.copyWith(
                              color: p.ink3, fontWeight: FontWeight.w700)),
                    ),
                    _Box(
                      width: S.x16 + S.x6,
                      text: '${ex.sets[i].reps}',
                      hint: '0',
                      semantic: 'Set ${i + 1} reps',
                      keyboard: TextInputType.number,
                      onChanged: (t) {
                        final v = int.tryParse(t.trim());
                        if (v != null && v >= 0 && v <= 1000) {
                          ex.sets[i].reps = v;
                          onChanged();
                        }
                      },
                    ),
                    const SizedBox(width: S.x4),
                    _Box(
                      width: S.x16 * 2 + S.x4 + S.x1,
                      text: ex.sets[i].kg == null
                          ? ''
                          : (ex.sets[i].kg! == ex.sets[i].kg!.roundToDouble()
                              ? '${ex.sets[i].kg!.round()}'
                              : '${ex.sets[i].kg}'),
                      hint: '--',
                      semantic: 'Set ${i + 1} weight in kilograms',
                      keyboard:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (t) {
                        final s = t.trim().replaceAll(',', '.');
                        if (s.isEmpty) {
                          ex.sets[i].kg = null;
                          onChanged();
                          return;
                        }
                        final v = double.tryParse(s);
                        if (v != null && v >= 0 && v <= 1000) {
                          ex.sets[i].kg = v;
                          onChanged();
                        }
                      },
                    ),
                    const Spacer(),
                    Pressable(
                      onTap: () => onRemoveSet(ex.sets[i]),
                      semanticLabel: 'Remove set ${i + 1}',
                      child: SizedBox(
                        width: S.tap,
                        height: S.tap,
                        child: Icon(LucideIcons.x, size: I.lg, color: p.ink),
                      ),
                    ),
                  ]),
                ),
              Row(children: [
                Pressable(
                  onTap: onAddSet,
                  semanticLabel: 'Add set',
                  child: SizedBox(
                    height: S.tap,
                    child: Row(children: [
                      const SizedBox(width: S.x3),
                      Text('ADD SET',
                          style: F.cap.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4)),
                      const SizedBox(width: S.x3),
                      Icon(LucideIcons.plus, size: I.lg, color: p.ink),
                    ]),
                  ),
                ),
                const Spacer(),
                Pressable(
                  onTap: onRemove,
                  semanticLabel: 'Remove exercise',
                  child: SizedBox(
                    width: S.tap,
                    height: S.tap,
                    child: Icon(LucideIcons.trash2, size: I.lg - S.half, color: p.ink),
                  ),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}

/// A near-black input cell: the number, left-aligned, bold.
class _Box extends StatelessWidget {
  final double width;
  final String text, hint, semantic;
  final TextInputType keyboard;
  final ValueChanged<String> onChanged;
  const _Box({
    required this.width,
    required this.text,
    required this.hint,
    required this.semantic,
    required this.keyboard,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      width: width,
      height: S.x10 + S.x1,
      padding: const EdgeInsets.symmetric(horizontal: S.x4 + S.half),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Color.alphaBlend(C.char.withValues(alpha: .75), p.bg),
        borderRadius: R.rSm,
      ),
      child: AppField(
        bare: true,
        initialValue: text,
        hint: hint,
        semanticLabel: semantic,
        keyboardType: keyboard,
        textStyle: F.num(F.head).copyWith(fontWeight: FontWeight.w700),
        onChanged: onChanged,
      ),
    );
  }
}

/// The dashed green card that adds an exercise.
class _AddExerciseCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddExerciseCard({required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Add exercise',
      child: CustomPaint(
        painter: _Dashed(C.optimal),
        child: Container(
          margin: const EdgeInsets.all(S.half),
          padding: const EdgeInsets.all(S.x1 + S.half / 2),
          decoration: BoxDecoration(
            color: C.optimal.withValues(alpha: .07),
            borderRadius: R.rMd,
          ),
          child: Row(children: [
            Container(
              width: S.x16 + S.x4,
              height: S.x16 + S.half,
              decoration: BoxDecoration(
                color: p.ink.withValues(alpha: .1),
                borderRadius: R.rSm,
              ),
              child: Icon(LucideIcons.plus, size: I.xl, color: p.ink),
            ),
            const SizedBox(width: S.x4),
            Text('ADD EXERCISE',
                style: F.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6)),
          ]),
        ),
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  final Color color;
  _Dashed(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(R.md + S.half)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}

/// The photo swapping between its two frames, and the steps.
class _ExerciseInfo extends StatefulWidget {
  final ExerciseDef? def;
  const _ExerciseInfo({required this.def});

  @override
  State<_ExerciseInfo> createState() => _ExerciseInfoState();
}

class _ExerciseInfoState extends State<_ExerciseInfo> {
  List<String> _steps = const [];

  @override
  void initState() {
    super.initState();
    exerciseSteps(widget.def).then((s) {
      if (mounted) setState(() => _steps = s);
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final def = widget.def;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(
        builder: (_, box) => ExerciseImage(
            def: def,
            width: box.maxWidth,
            height: box.maxWidth * 2 / 3,
            radius: R.rXl,
            animate: true),
      ),
      const SizedBox(height: S.x3),
      if (def != null)
        Text(
            [
              ...def.primaryMuscles,
              if (def.equipment.isNotEmpty) ...def.equipment,
            ].join(' · '),
            style: F.cap.copyWith(color: p.ink3)),
      const SizedBox(height: S.x3),
      for (var i = 0; i < _steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: Text('${i + 1}. ${_steps[i]}',
              style: F.body.copyWith(color: p.ink2, height: 1.4)),
        ),
    ]);
  }
}
