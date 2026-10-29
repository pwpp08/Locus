// A PERSONAL RECORD: one lift's figure, its photo, and its progress — the
// best of every session it was done in, as a line chart in the same style as
// the metrics. The figure is the logged one, or the one typed by hand (a pin
// that stands until a logged set beats it). Both can be changed here.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../compute/strength_stats.dart';
import '../../data/strength_store.dart';
import '../../l10n/app_localizations.dart';
import '../activity/catalogue.dart';
import '../activity/exercise_image.dart';
import '../activity/exercise_picker.dart';
import '../ui2.dart';
import 'home_screen.dart' show monthShortName;

/// Pick a lift, then type its record. True when one was saved.
Future<bool?> addRecordByHand(BuildContext c) async {
  final key = await showExercisePicker(c, mode: ExercisePickMode.choose);
  if (key == null || !c.mounted) return null;
  return editRecordSheet(c, key, null);
}

/// The record form: the number, and whether it counts kilograms or reps.
/// [current] fills it for a change. True when saved.
Future<bool?> editRecordSheet(
    BuildContext c, String key, PersonalRecord? current) {
  return AppSheet.show<bool>(c,
      title: exerciseByKey(key)?.label ?? 'Record',
      child: _RecordForm(exerciseKey: key, current: current));
}

class _RecordForm extends StatefulWidget {
  final String exerciseKey;
  final PersonalRecord? current;
  const _RecordForm({required this.exerciseKey, required this.current});

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  late RecordKind _kind = widget.current?.kind ??
      (exerciseByKey(widget.exerciseKey)?.bodyweight == true
          ? RecordKind.reps
          : RecordKind.weight);
  late final TextEditingController _v = TextEditingController(
      text: widget.current == null
          ? ''
          : (widget.current!.value == widget.current!.value.roundToDouble()
              ? '${widget.current!.value.round()}'
              : '${widget.current!.value}'));
  String? _error;

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = double.tryParse(_v.text.trim().replaceAll(',', '.'));
    final max = _kind == RecordKind.reps ? 1000 : 1000.0;
    if (v == null || v <= 0 || v > max) {
      setState(() => _error = _kind == RecordKind.reps
          ? 'Enter the most reps you did in one set.'
          : 'Enter the heaviest load, in kilograms.');
      return;
    }
    final nav = Navigator.of(context);
    await StrengthStore.putRecord(widget.exerciseKey, _kind, v);
    if (mounted) nav.pop(true);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget kind(RecordKind k, String label) => Expanded(
          child: Pressable(
            onTap: () => setState(() => _kind = k),
            semanticLabel: label,
            child: Container(
              height: S.x10,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _kind == k ? p.ink : p.ink.withValues(alpha: .09),
                borderRadius: R.rMd,
              ),
              child: Text(label,
                  style: F.caps.copyWith(
                      color: _kind == k ? p.inkOn(p.ink) : p.ink,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        kind(RecordKind.weight, 'KILOGRAMS'),
        const SizedBox(width: S.x2),
        kind(RecordKind.reps, 'REPS'),
      ]),
      const SizedBox(height: S.x4),
      AppField(
        label: _kind == RecordKind.reps ? 'Most reps in a set' : 'Heaviest load (kg)',
        controller: _v,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        errorText: _error,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _save(),
      ),
      const SizedBox(height: S.x2),
      Text(
          'It stands until a set you log afterwards beats it.',
          style: F.cap.copyWith(color: p.ink3)),
      const SizedBox(height: S.x5),
      BigButton('Save', onTap: _save),
    ]);
  }
}

class StrengthRecordScreen extends StatefulWidget {
  final String exerciseKey;

  /// Handed in by a test; read from the store when null.
  final ({List<LoggedRow> rows, List<TypedRecord> typed})? data;
  const StrengthRecordScreen({super.key, required this.exerciseKey, this.data});

  @override
  State<StrengthRecordScreen> createState() => _StrengthRecordScreenState();
}

class _StrengthRecordScreenState extends State<StrengthRecordScreen> {
  PersonalRecord? _record;
  List<({int ts, double v})> _points = const [];
  List<String> _steps = const [];
  bool _loaded = false;
  int? _at;

  ExerciseDef? get _def => exerciseByKey(widget.exerciseKey);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<LoggedRow> rows = widget.data?.rows ?? const [];
    List<TypedRecord> typed = widget.data?.typed ?? const [];
    if (widget.data == null) {
      try {
        rows = await StrengthStore.loggedRows();
        typed = await StrengthStore.typedRecords();
      } catch (_) {}
    }
    final all = mergeRecords(loggedRecords(rows), typed);
    final r = all.where((e) => e.key == widget.exerciseKey).firstOrNull;
    TypedRecord? pin;
    for (final t in typed) {
      if (t.key == widget.exerciseKey) pin = t;
    }
    if (!mounted) return;
    setState(() {
      _record = r;
      _points = r == null
          ? const []
          : recordProgress(widget.exerciseKey, r.kind, rows, typed: pin);
      _loaded = true;
      _at = null;
    });
    exerciseSteps(_def).then((steps) {
      if (mounted && steps.isNotEmpty) {
        setState(() => _steps = steps);
      }
    });
  }

  Future<void> _edit() async {
    if (await editRecordSheet(context, widget.exerciseKey, _record) == true) {
      await _load();
    }
  }

  Future<void> _removePin() async {
    final ok = await confirmRemove(context,
        title: 'Remove the number you typed?',
        body: 'The record goes back to what your logged sets show.',
        remove: 'Remove');
    if (!ok) return;
    await StrengthStore.deleteRecord(widget.exerciseKey);
    await _load();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final def = _def;
    final r = _record;
    final unit = r?.kind == RecordKind.reps ? 'reps' : 'kg';
    final pts = _points.length > 16
        ? _points.sublist(_points.length - 16)
        : _points;
    final values = [for (final e in pts) e.v];
    final lo0 = values.isEmpty ? 0.0 : values.reduce(math.min);
    final hi0 = values.isEmpty ? 1.0 : values.reduce(math.max);
    final pad = math.max(r?.kind == RecordKind.reps ? 1.0 : 2.5, (hi0 - lo0) * .25);
    final step = _niceStep((hi0 - lo0 + 2 * pad) / 3);
    final lo = math.max(0.0, ((lo0 - pad) / step).floorToDouble() * step);
    final hi = ((hi0 + pad) / step).ceilToDouble() * step;
    final ticks = [for (var v = lo; v <= hi + 1e-6; v += step) v];
    String date(int ts) {
      final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      return '${monthShortName(d.month, l)} ${d.day}';
    }

    final at = _at != null && _at! < pts.length ? pts[_at!] : null;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16),
          children: [
            NavBar(def?.label ?? widget.exerciseKey),
            const SizedBox(height: S.x2),
            LayoutBuilder(
              builder: (_, box) => ExerciseImage(
                def: def,
                width: box.maxWidth,
                height: box.maxWidth * 2 / 3 * .62,
                radius: R.rXl,
                animate: true,
              ),
            ),
            const SizedBox(height: S.x5),
            if (!_loaded)
              const Center(child: CircularProgressIndicator())
            else if (r == null) ...[
              Text('No record yet',
                  style: F.t2.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              const SizedBox(height: S.x2),
              Text(
                  'Log a set of this lift and its record appears, or type one in.',
                  style: F.body.copyWith(color: p.ink2, height: 1.4)),
              const SizedBox(height: S.x4),
              BigButton('Add a record', onTap: _edit),
            ] else ...[
              ScrubReadout(
                caption: at == null
                    ? 'PERSONAL RECORD'
                    : date(at.ts),
                value: _fmt(at?.v ?? r.value),
                unit: unit,
                under: Text(
                    at != null
                        ? 'Best of that session'
                        : r.ts == null
                            ? ''
                            : '${r.typed ? 'Added' : 'Lifted'} ${date(r.ts!)}'
                                '${r.typed ? ' by hand' : ''}',
                    style: F.cap.copyWith(color: p.ink3)),
              ),
              const SizedBox(height: S.x4),
              if (pts.length >= 2)
                ScrubLine(
                  values: values,
                  xLabels: [for (final e in pts) '${date(e.ts).split(' ').first}\n${date(e.ts).split(' ').last}'],
                  lo: lo,
                  hi: hi,
                  ticks: ticks,
                  tickText: _fmt,
                  color: C.dialStrain,
                  height: S.x16 * 3 + S.x4,
                  highlight: _at,
                  label: '${def?.label ?? 'Lift'} progress',
                  describe: (i) =>
                      '${date(pts[i].ts)}, ${_fmt(pts[i].v)} $unit',
                  onScrub: (i) => setState(() => _at = i),
                )
              else
                Text(
                    'Progress draws itself once this lift has been logged in '
                    'two sessions.',
                    style: F.body.copyWith(color: p.ink3, height: 1.4)),
              const SizedBox(height: S.x5),
              BigButton('Change the record', onTap: _edit),
              if (r.typed) ...[
                const SizedBox(height: S.x2),
                Center(child: TextAction('Remove the number I typed', _removePin)),
              ],
            ],
            if (_steps.isNotEmpty) ...[
              const SizedBox(height: S.x8),
              Text('How it is done',
                  style: F.head.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              const SizedBox(height: S.x3),
              for (var i = 0; i < _steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.x3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: S.x6,
                      child: Text('${i + 1}',
                          style: F.num(F.body).copyWith(
                              color: p.ink3, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text(_steps[i],
                          style: F.body.copyWith(color: p.ink2, height: 1.4)),
                    ),
                  ]),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// A step of 1, 2 or 5 times a power of ten that is at least [raw].
  double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / mag;
    return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * mag;
  }
}
