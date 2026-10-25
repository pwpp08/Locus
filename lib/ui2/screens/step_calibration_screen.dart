// step_calibration_screen.dart — Guided step count calibration and diagnostic test.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/step_calibration.dart';
import '../../state/app_state.dart';
import '../ui2.dart';

class StepCalibrationScreen extends StatefulWidget {
  const StepCalibrationScreen({super.key});

  @override
  State<StepCalibrationScreen> createState() => _StepCalibrationScreenState();
}

class _StepCalibrationScreenState extends State<StepCalibrationScreen> {
  int _targetSteps = 1000;
  bool _testing = false;
  int _startStrapSteps = 0;
  int _currentStrapSteps = 0;
  DateTime? _startTime;
  DateTime? _endTime;
  double? _measuredHz;
  final List<double> _hzSamples = [];

  // Results
  bool _completed = false;
  double? _computedFactor;
  String? _diagnosticReport;
  bool _applied = false;

  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startTest(AppState app) {
    setState(() {
      _testing = true;
      _completed = false;
      _applied = false;
      _diagnosticReport = null;
      _computedFactor = null;
      _startStrapSteps = app.workoutStepsMeasured ?? 0;
      _currentStrapSteps = app.workoutStepsMeasured ?? 0;
      _startTime = DateTime.now();
      _endTime = null;
      _hzSamples.clear();
    });

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Motion.tick, (t) {
      if (!mounted || !_testing) return;
      final currentApp = context.read<AppState>();
      setState(() {
        _currentStrapSteps = currentApp.workoutStepsMeasured ?? 0;
        final hz = currentApp.liveHz;
        if (hz != null && hz > 0) {
          _measuredHz = hz;
          _hzSamples.add(hz);
        }
      });
    });
  }

  Future<void> _finishTest(AppState app) async {
    _pollTimer?.cancel();
    _endTime = DateTime.now();
    final elapsedSec = (_startTime != null && _endTime != null)
        ? _endTime!.difference(_startTime!).inSeconds
        : 60;

    final countedByStrap = (_currentStrapSteps - _startStrapSteps).abs();
    final avgHz = _hzSamples.isNotEmpty
        ? _hzSamples.reduce((a, b) => a + b) / _hzSamples.length
        : (_measuredHz ?? 25.0);

    // Compute factor
    double factor;
    if (countedByStrap > 0) {
      factor = _targetSteps / countedByStrap;
    } else {
      // If strap counted 0 or was gated out
      factor = (_targetSteps / 100.0).clamp(kStepFactorMin, kStepFactorMax);
    }
    factor = factor.clamp(kStepFactorMin, kStepFactorMax);

    // Generate diagnostic report
    final sb = StringBuffer();
    sb.writeln('• Target steps walked: $_targetSteps');
    sb.writeln('• Strap counted: $countedByStrap steps in ${elapsedSec}s');
    sb.writeln('• Discrepancy ratio: ${factor.toStringAsFixed(2)}x');
    sb.writeln('• Average BLE motion rate: ${avgHz.toStringAsFixed(1)} Hz');

    if (avgHz < 45.0) {
      sb.writeln(
        '\n[Diagnosis]: The BLE stream is running at ${avgHz.toStringAsFixed(1)} Hz (typical for Bluetooth low-power mode). '
        'Strap step counting needs at least 50 Hz to be accurate, so while the stream is this slow '
        'the strap\'s steps are left out and your phone\'s count is used instead. '
        'A calibration factor cannot correct for this.',
      );
    } else if (countedByStrap < _targetSteps * 0.4) {
      sb.writeln(
        '\n[Diagnosis]: Wrist swing motion amplitude during walking was lower than standard stride thresholds. '
        'Applying a ${(factor).toStringAsFixed(2)}x calibration factor will align Whoop\'s pedometer with your Samsung Watch and true count.',
      );
    } else {
      sb.writeln(
        '\n[Diagnosis]: Gait cadence measured normally. Applying a fine calibration multiplier of ${(factor).toStringAsFixed(2)}x.',
      );
    }

    setState(() {
      _testing = false;
      _completed = true;
      _computedFactor = factor;
      _diagnosticReport = sb.toString();
    });
  }

  Future<void> _applyFactor(AppState app) async {
    if (_computedFactor == null) return;
    try {
      final family = app.paired?.generation != null ? 'whoop_' : 'whoop';
      const wearing = Wearing.wrist;

      final profile = StepCalibrationProfile(
        deviceFamily: family,
        wearing: wearing,
        factor: _computedFactor!,
        nDays: 1,
        version: kStepCalibrationVersion,
      );

      await LocalDb.putStepCalibrationProfile(profile);
      if (!mounted) return;

      setState(() {
        _applied = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Calibrated! Factor ${_computedFactor!.toStringAsFixed(2)}x applied to your step counter.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving calibration: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final app = c.watch<AppState>();
    final connected = app.isConnected;
    final strapCountedSoFar = (_currentStrapSteps - _startStrapSteps).abs();

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(
                'Step Calibration & Diagnostics',
                sub: 'Calibrate Whoop against your Samsung watch',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  if (!connected)
                    StatusCard(
                      'Strap Not Connected',
                      'Connect your Whoop band first to calibrate the live step counter.',
                      icon: LucideIcons.bluetoothOff,
                    )
                  else ...[
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.footprints, color: C.orange, size: 28),
                              const SizedBox(width: S.x3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Target: $_targetSteps Steps',
                                      style: F.n24.copyWith(color: p.ink),
                                    ),
                                    Text(
                                      'Walk exactly $_targetSteps steps (tracked by watch or counting)',
                                      style: F.cap.copyWith(color: p.ink3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: S.x4),
                          if (!_testing && !_completed) ...[
                            Text('Choose Target Steps:', style: F.cap.copyWith(color: p.ink3)),
                            const SizedBox(height: S.x2),
                            Row(
                              children: [200, 500, 1000].map((steps) {
                                final selected = _targetSteps == steps;
                                return Padding(
                                  padding: const EdgeInsets.only(right: S.x2),
                                  child: FilterChip(
                                    label: Text('$steps steps'),
                                    selected: selected,
                                    onSelected: (val) {
                                      if (val) setState(() => _targetSteps = steps);
                                    },
                                    selectedColor: p.wash(C.orange),
                                    checkmarkColor: C.orange,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                          if (_testing) ...[
                            Divider(color: p.line),
                            const SizedBox(height: S.x3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Strap Counted:', style: F.body.copyWith(color: p.ink3)),
                                Text(
                                  '$strapCountedSoFar / $_targetSteps',
                                  style: F.n24.copyWith(color: C.orange),
                                ),
                              ],
                            ),
                            const SizedBox(height: S.x2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Live BLE Rate:', style: F.cap.copyWith(color: p.ink3)),
                                Text(
                                  _measuredHz != null ? '${_measuredHz!.toStringAsFixed(1)} Hz' : 'Streaming...',
                                  style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: S.x4),
                            LinearProgressIndicator(
                              value: (strapCountedSoFar / _targetSteps).clamp(0.0, 1.0),
                              color: C.orange,
                              backgroundColor: p.wash(C.orange),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: S.x4),
                    if (!_testing && !_completed)
                      BigButton(
                        'Start $_targetSteps-Step Test',
                        icon: LucideIcons.play,
                        color: C.orange,
                        onTap: () => _startTest(app),
                      )
                    else if (_testing)
                      BigButton(
                        'I Finished Walking $_targetSteps Steps',
                        icon: LucideIcons.check,
                        color: C.green,
                        onTap: () => _finishTest(app),
                      ),
                    if (_completed && _diagnosticReport != null) ...[
                      const SizedBox(height: S.x4),
                      Surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(LucideIcons.stethoscope, color: C.blue, size: 24),
                                const SizedBox(width: S.x2),
                                Text(
                                  'Diagnostic Results',
                                  style: F.body.copyWith(fontWeight: FontWeight.w600, color: p.ink),
                                ),
                              ],
                            ),
                            const SizedBox(height: S.x3),
                            Text(
                              _diagnosticReport!,
                              style: F.cap.copyWith(color: p.ink2, height: 1.5),
                            ),
                            const SizedBox(height: S.x4),
                            if (_applied)
                              Pill('Calibration Active & Saved', C.green, icon: LucideIcons.badgeCheck)
                            else
                              BigButton(
                                'Apply Calibration (${_computedFactor!.toStringAsFixed(2)}x)',
                                icon: LucideIcons.check,
                                color: C.green,
                                onTap: () => _applyFactor(app),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: S.x3),
                      BigButton(
                        'Start New Test',
                        icon: LucideIcons.refreshCw,
                        color: p.ink3,
                        soft: true,
                        onTap: () => setState(() {
                          _completed = false;
                          _applied = false;
                          _diagnosticReport = null;
                        }),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
