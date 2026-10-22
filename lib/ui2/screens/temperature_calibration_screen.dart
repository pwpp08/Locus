// temperature_calibration_screen.dart — UI to manually calibrate body temperature.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/temperature_calibration.dart';
import '../ui2.dart';

class TemperatureCalibrationScreen extends StatefulWidget {
  const TemperatureCalibrationScreen({super.key});

  @override
  State<TemperatureCalibrationScreen> createState() =>
      _TemperatureCalibrationScreenState();
}

class _TemperatureCalibrationScreenState
    extends State<TemperatureCalibrationScreen> {
  TemperatureCalibration _config = const TemperatureCalibration();
  late TextEditingController _tempInput;
  bool _loading = true;
  String? _statusMsg;

  @override
  void initState() {
    super.initState();
    _tempInput = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final c = await TemperatureCalibration.load();
    if (!mounted) return;
    setState(() {
      _config = c;
      final displayVal = c.useFahrenheit
          ? TemperatureCalibration.toFahrenheit(c.referenceTempC)
          : c.referenceTempC;
      _tempInput.text = displayVal.toStringAsFixed(1);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final parsed = double.tryParse(_tempInput.text.trim());
    if (parsed == null) {
      setState(() => _statusMsg = 'Please enter a valid temperature.');
      return;
    }

    final inCelsius =
        _config.useFahrenheit ? TemperatureCalibration.toCelsius(parsed) : parsed;

    if (inCelsius < 34.0 || inCelsius > 41.5) {
      setState(() => _statusMsg = 'Temperature must be between 34°C and 41.5°C.');
      return;
    }

    final updated = TemperatureCalibration(
      referenceTempC: inCelsius,
      referenceAdc: _config.referenceAdc,
      manualOffsetC: 0.0,
      useFahrenheit: _config.useFahrenheit,
    );

    await updated.save();
    if (!mounted) return;
    setState(() {
      _config = updated;
      _statusMsg = 'Calibrated successfully!';
    });
  }

  void _adjustOffset(double deltaC) async {
    final newOffset = _config.manualOffsetC + deltaC;
    final updated = TemperatureCalibration(
      referenceTempC: _config.referenceTempC,
      referenceAdc: _config.referenceAdc,
      manualOffsetC: newOffset,
      useFahrenheit: _config.useFahrenheit,
    );
    await updated.save();
    if (!mounted) return;
    setState(() {
      _config = updated;
      _statusMsg = 'Offset updated: ${newOffset >= 0 ? '+' : ''}${newOffset.toStringAsFixed(1)}°C';
    });
  }

  void _toggleUnit(bool fahrenheit) async {
    final updated = TemperatureCalibration(
      referenceTempC: _config.referenceTempC,
      referenceAdc: _config.referenceAdc,
      manualOffsetC: _config.manualOffsetC,
      useFahrenheit: fahrenheit,
    );
    await updated.save();
    if (!mounted) return;
    setState(() {
      _config = updated;
      final displayVal = fahrenheit
          ? TemperatureCalibration.toFahrenheit(updated.referenceTempC)
          : updated.referenceTempC;
      _tempInput.text = displayVal.toStringAsFixed(1);
    });
  }

  @override
  void dispose() {
    _tempInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final unitLabel = _config.useFahrenheit ? '°F' : '°C';
    final effectiveTemp = _config.referenceTempC + _config.manualOffsetC;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        title: Text('Temperature Calibration', style: F.t2.copyWith(color: p.ink)),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: p.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(S.x4),
                children: [
                  // Current calibrated display
                  Container(
                    padding: const EdgeInsets.all(S.x5),
                    decoration: BoxDecoration(
                      color: p.wash(C.orange),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.line.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        const Icon(LucideIcons.thermometer, size: 36, color: C.orange),
                        const SizedBox(height: S.x2),
                        Text(
                          _config.format(effectiveTemp),
                          style: F.n48.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Calibrated Baseline Body Temperature',
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x5),

                  // Unit switch (°C / °F)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Temperature Unit', style: F.body.copyWith(color: p.ink)),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('°C')),
                          ButtonSegment(value: true, label: Text('°F')),
                        ],
                        selected: {_config.useFahrenheit},
                        onSelectionChanged: (set) => _toggleUnit(set.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x4),

                  // Manual Calibration Input
                  Text(
                    'Reference Calibration',
                    style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: S.x1),
                  Text(
                    'Measure your temperature with a standard medical thermometer, then enter it below to calibrate your WHOOP strap.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                  const SizedBox(height: S.x3),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tempInput,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: F.body.copyWith(color: p.ink),
                          decoration: InputDecoration(
                            labelText: 'Reference Reading ($unitLabel)',
                            labelStyle: TextStyle(color: p.ink3),
                            suffixText: unitLabel,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: S.x2),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: C.blue,
                          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _save,
                        child: const Text('Calibrate'),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x5),

                  // Fine tuning offset buttons (+/- 0.1°C)
                  Text(
                    'Fine-tune Offset',
                    style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: S.x1),
                  Text(
                    'Nudge the body temperature reading up or down by 0.1°C.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                  const SizedBox(height: S.x3),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(LucideIcons.minus, size: 16),
                        label: const Text('-0.1°C'),
                        onPressed: () => _adjustOffset(-0.1),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(LucideIcons.rotateCcw, size: 16),
                        label: const Text('Reset'),
                        onPressed: () async {
                          const def = TemperatureCalibration();
                          await def.save();
                          await _load();
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text('+0.1°C'),
                        onPressed: () => _adjustOffset(0.1),
                      ),
                    ],
                  ),

                  if (_statusMsg != null) ...[
                    const SizedBox(height: S.x4),
                    Center(
                      child: Text(
                        _statusMsg!,
                        style: F.body.copyWith(
                          color: _statusMsg!.contains('successfully') ? C.green : C.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
