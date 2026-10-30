import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/journal_fields.dart';
import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../grammar.dart';
import '../lucide.dart';
import '../marks.dart';
import '../theme.dart';

/// Modal bottom sheet for quick weight logging from the navbar (+) action.
class LogWeightSheet extends StatefulWidget {
  const LogWeightSheet({super.key});

  static Future<bool?> show(BuildContext context) => AppSheet.show<bool>(
    context,
    title: 'LOG WEIGHT',
    child: const LogWeightSheet(),
  );

  @override
  State<LogWeightSheet> createState() => _LogWeightSheetState();
}

class _LogWeightSheetState extends State<LogWeightSheet> {
  late final UnitsController _units = context.read<UnitsController>();
  late final TextEditingController _controller;
  double _currentVal = 70.0;
  bool _saving = false;

  /// Once saved: the weight logged before this one and this one, in the
  /// user's unit. The sheet rolls from the first to the second, says the
  /// change, and closes.
  ({double? before, double now})? _saved;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final currentKg = (app.user?['weight_kg'] as num?)?.toDouble() ?? 70.0;
    final initialStr = _units.weightField(currentKg);
    _currentVal =
        double.tryParse(initialStr) ?? (_units.isImperial ? 154.0 : 70.0);
    _controller = TextEditingController(
      text: _currentVal == _currentVal.roundToDouble()
          ? _currentVal.round().toString()
          : _currentVal.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(double delta) {
    setState(() {
      final parsed = double.tryParse(_controller.text.trim()) ?? _currentVal;
      const stepSize = 0.1;
      final next = (parsed + (delta > 0 ? stepSize : -stepSize)).clamp(
        20.0,
        300.0,
      );
      final rounded = (next * 10).round() / 10.0;
      _currentVal = rounded;
      _controller.text = rounded.toStringAsFixed(1);
    });
  }

  /// The most recent weight already in the journal, in kg.
  static Future<double?> _lastLogged() async {
    final now = DateTime.now();
    final rows = await LocalDb.journalMetricsByDay(
      sinceDaysEpoch: dayLabelOf(DateTime(now.year, now.month, now.day - 365)),
    );
    final days = rows.keys.toList()..sort();
    for (final d in days.reversed) {
      final v = rows[d]?['weight_kg']?.value;
      if (v != null && v.isFinite && v > 0) return v;
    }
    return null;
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    final kg = _units.weightToKg(text);
    if (kg == null || kg <= 0) return;
    setState(() => _saving = true);
    try {
      final app = context.read<AppState>();
      final before = await _lastLogged();
      await app.updateProfile({'weight_kg': kg});
      final today = todayLabel();
      final existing = await LocalDb.journalMetricsForDay(today);
      await LocalDb.putJournalMetrics(today, {
        ...existing,
        'weight_kg': JournalMetricValue(kg),
      });
      app.insightsRevision.value++;
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _saved = (
            before: before == null ? null : _units.weightValue(before),
            now: _units.weightValue(kg),
          ));
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The roll has settled: a firmer tap, a moment to read it, then close.
  void _settled() {
    HapticFeedback.mediumImpact();
    Future.delayed(motion(context, Motion.linger), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Widget _result(P p, String unit) {
    final s = _saved!;
    final before = s.before;
    // Compared in the unit shown, to the tenth shown.
    final diff =
        before == null ? null : ((s.now - before) * 10).round() / 10;
    return Padding(
      key: const ValueKey('saved'),
      padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              RollingNumber(
                from: before ?? 0,
                value: s.now,
                style: F.n48.copyWith(color: p.ink, fontWeight: FontWeight.w700),
                onTick: HapticFeedback.selectionClick,
                onDone: _settled,
              ),
              const SizedBox(width: S.x1),
              Text(unit,
                  style: F.head.copyWith(
                      color: p.ink3, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: S.x3),
          if (diff == null)
            Text('Your first weigh-in',
                style: F.cap.copyWith(color: p.ink3))
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (diff != 0) ...[
                  DeltaTriangle(up: diff > 0, color: p.ink2, size: S.x2 + S.half),
                  const SizedBox(width: S.x1 + S.half),
                ],
                Text(
                  '${diff > 0 ? '+' : diff < 0 ? '−' : ''}'
                  '${diff.abs().toStringAsFixed(1)} $unit',
                  style: F.num(F.body)
                      .copyWith(color: p.ink, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: S.x2),
                Text('since last time', style: F.cap.copyWith(color: p.ink3)),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final unit = _units.isImperial ? 'lb' : 'kg';

    return AnimatedSwitcher(
      duration: motion(context, Motion.base),
      child: _saved != null ? _result(p, unit) : _form(p, unit),
    );
  }

  Widget _form(P p, String unit) {
    return Padding(
      key: const ValueKey('form'),
      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Keep your profile weight current for accurate caloric burn and load calculation.',
            style: F.cap.copyWith(color: p.ink3, height: 1.45),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: S.x6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Pressable(
                onTap: () => _step(-1),
                semanticLabel: 'Decrease weight',
                child: Container(
                  width: S.x12,
                  height: S.x12,
                  decoration: BoxDecoration(
                    color: p.card2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.minus, size: I.md, color: p.ink),
                ),
              ),
              const SizedBox(width: S.x4),
              Container(
                width: 140,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: S.x3,
                  vertical: S.x2,
                ),
                decoration: BoxDecoration(
                  color: p.card2,
                  borderRadius: R.rLg,
                  border: Border.all(color: p.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    IntrinsicWidth(
                      child: AppField(
                        bare: true,
                        semanticLabel: 'Weight',
                        controller: _controller,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textStyle: F.n34.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: S.x1),
                    Text(
                      unit,
                      style: F.cap.copyWith(
                        color: p.ink3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: S.x4),
              Pressable(
                onTap: () => _step(1),
                semanticLabel: 'Increase weight',
                child: Container(
                  width: S.x12,
                  height: S.x12,
                  decoration: BoxDecoration(
                    color: p.card2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.plus, size: I.md, color: p.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x6),
          BigButton(
            _saving ? 'Saving…' : 'Save weight',
            icon: LucideIcons.check,
            color: C.domHome,
            onTap: _saving ? null : _save,
          ),
          const SizedBox(height: S.x3),
        ],
      ),
    );
  }
}
