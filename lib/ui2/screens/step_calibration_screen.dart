// The band's step correction: what the app has learned about how the band's
// own step counter compares with the phone's, and nothing it has not.
//
// The correction is learned, not set: on each day the phone also counted steps,
// the derivation compares the two and refits the factor
// (`estimateStepCalibration`). This screen reads that stored profile for the
// paired band's family and how it is worn.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/step_calibration.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'metric_detail.dart' show detailScaffold;

class StepCalibrationScreen extends StatefulWidget {
  const StepCalibrationScreen({super.key});

  @override
  State<StepCalibrationScreen> createState() => _StepCalibrationScreenState();
}

class _StepCalibrationScreenState extends State<StepCalibrationScreen> {
  StepCalibrationProfile? _profile;
  int? _wearing;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final family = context.read<AppState>().paired?.generation;
    StepCalibrationProfile? profile;
    int? wearing;
    try {
      final row = await LocalDb.deviceRow();
      wearing = Wearing.parse(row?['wearing']) ?? Wearing.wrist;
      if (family != null) {
        profile = await LocalDb.stepCalibrationProfile(family, wearing);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _wearing = wearing;
      _loading = false;
    });
  }

  String get _where => switch (_wearing) {
        Wearing.bicep => 'on the upper arm',
        Wearing.other => 'somewhere other than the wrist',
        _ => 'on the wrist',
      };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final paired = c.watch<AppState>().paired;
    final f = _profile;
    final learned = f != null && f.isCalibrated;
    return detailScaffold(c, 'Step counter', [
      const SizedBox(height: S.x2),
      if (paired == null)
        const StatusCard(
          'No band paired',
          'Pair a band to see how its step count is corrected.',
          icon: LucideIcons.bluetoothOff,
        )
      else if (_loading)
        const Padding(
          padding: EdgeInsets.only(top: S.x8),
          child: Center(child: CircularProgressIndicator()),
        )
      else ...[
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ScrubReadout(
              caption: 'Correction',
              value: learned ? '×${f.factor.toStringAsFixed(2)}' : '--',
            ),
            const SizedBox(height: S.x3),
            Text(
              learned
                  ? 'Learned from ${f.nDays} ${f.nDays == 1 ? 'day' : 'days'} '
                      'your phone counted steps too, with the band worn '
                      '$_where. The band\'s own count is multiplied by this.'
                  : 'Nothing learned yet for the band worn $_where. It is '
                      'learned on days your phone counts steps as well.',
              style: F.body.copyWith(color: p.ink2, height: 1.4),
            ),
          ]),
        ),
        Section(
          'How it is learned',
          Surface(
            child: Column(children: [
              for (final (i, (icon, text)) in const [
                (
                  LucideIcons.smartphone,
                  'Each day your phone also counts steps, the two counts are '
                      'compared.',
                ),
                (
                  LucideIcons.calendarDays,
                  'It is fitted over the last 30 such days and pulled toward '
                      'no correction, so a few odd days cannot swing it. It '
                      'needs three days to start.',
                ),
                (
                  LucideIcons.footprints,
                  'A day with under 1,000 phone steps does not count, and the '
                      'correction stays between ×0.50 and ×2.00.',
                ),
              ].indexed) ...[
                if (i > 0) const SizedBox(height: S.x4),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: I.md, color: p.ink2),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(text,
                        style: F.body.copyWith(color: p.ink, height: 1.4)),
                  ),
                ]),
              ],
            ]),
          ),
        ),
      ],
    ]);
  }
}
