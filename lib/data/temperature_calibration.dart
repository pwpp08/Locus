// temperature_calibration.dart — policy and storage for body temperature calibration
// from Whoop thermistor ADC counts to calibrated body / skin temperature (°C / °F).

import 'package:shared_preferences/shared_preferences.dart';

const double kDefaultReferenceTempC = 36.6; // standard healthy basal body temp
const double kDefaultReferenceAdc = 28500.0; // typical Whoop 4.0 resting ADC
const double kAdcCountsPerDegreeC = 350.0; // Whoop thermistor sensitivity

class TemperatureCalibration {
  static const String _kReferenceTemp = 'temp_calibrated_reference_c';
  static const String _kReferenceAdc = 'temp_calibrated_reference_adc';
  static const String _kManualOffset = 'temp_calibrated_manual_offset_c';
  static const String _kUseFahrenheit = 'temp_use_fahrenheit';

  final double referenceTempC;
  final double referenceAdc;
  final double manualOffsetC;
  final bool useFahrenheit;

  const TemperatureCalibration({
    this.referenceTempC = kDefaultReferenceTempC,
    this.referenceAdc = kDefaultReferenceAdc,
    this.manualOffsetC = 0.0,
    this.useFahrenheit = false,
  });

  /// Convert raw thermistor ADC to calibrated body temperature in Celsius.
  double adcToCelsius(double rawAdc, {double? baselineAdc}) {
    final refAdc = baselineAdc ?? referenceAdc;
    // NTC thermistor: higher temp => lower ADC count (negative temperature coefficient)
    final deltaT = -(rawAdc - refAdc) / kAdcCountsPerDegreeC;
    final temp = referenceTempC + deltaT + manualOffsetC;
    // Clamp to valid physiological body temp (34.0°C to 41.5°C)
    return temp.clamp(34.0, 41.5);
  }

  /// Convert Celsius to Fahrenheit
  static double toFahrenheit(double celsius) => (celsius * 9.0 / 5.0) + 32.0;

  /// Convert Fahrenheit to Celsius
  static double toCelsius(double fahrenheit) => (fahrenheit - 32.0) * 5.0 / 9.0;

  /// Calibrate using a manual reference reading (e.g. thermometer reads 36.8°C while ADC is 28300)
  TemperatureCalibration calibrateWithReading({
    required double thermometerC,
    required double currentAdc,
  }) {
    return TemperatureCalibration(
      referenceTempC: thermometerC,
      referenceAdc: currentAdc,
      manualOffsetC: 0.0,
      useFahrenheit: useFahrenheit,
    );
  }

  /// Format temperature string according to unit preference
  String format(double celsius) {
    if (useFahrenheit) {
      final f = toFahrenheit(celsius);
      return '${f.toStringAsFixed(1)}°F';
    }
    return '${celsius.toStringAsFixed(1)}°C';
  }

  static Future<TemperatureCalibration> load() async {
    final prefs = await SharedPreferences.getInstance();
    return TemperatureCalibration(
      referenceTempC: prefs.getDouble(_kReferenceTemp) ?? kDefaultReferenceTempC,
      referenceAdc: prefs.getDouble(_kReferenceAdc) ?? kDefaultReferenceAdc,
      manualOffsetC: prefs.getDouble(_kManualOffset) ?? 0.0,
      useFahrenheit: prefs.getBool(_kUseFahrenheit) ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kReferenceTemp, referenceTempC);
    await prefs.setDouble(_kReferenceAdc, referenceAdc);
    await prefs.setDouble(_kManualOffset, manualOffsetC);
    await prefs.setBool(_kUseFahrenheit, useFahrenheit);
  }
}
