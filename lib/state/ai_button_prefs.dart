// The floating AI button, as the user set it up: whether it is there at all,
// how big it is, which edge it sits on, and how strongly it shows.

import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// Where the button floats. Bottom spots sit just above the tab bar (and the
/// minimised-workout pill, when there is one); middle spots halfway down.
enum AiButtonSpot { bottomRight, bottomLeft, middleRight, middleLeft }

class AiButtonPrefs {
  static const String kOn = 'ai_button.on';
  static const String kSize = 'ai_button.size';
  static const String kSpot = 'ai_button.spot';
  static const String kVisibility = 'ai_button.visibility';

  /// Bumped on every change, so the shell redraws the button at once.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static const sizeLabels = ['Small', 'Medium', 'Large'];
  static const spotLabels = [
    'Bottom right',
    'Bottom left',
    'Middle right',
    'Middle left',
  ];
  static const visibilityLabels = ['Solid', 'Soft', 'Faint'];

  /// The button's side for each of [sizeLabels].
  static const sides = [40.0, 48.0, 60.0];

  /// Its opacity for each of [visibilityLabels].
  static const opacities = [1.0, .7, .4];

  static bool get on => Prefs.getBool(kOn, true);
  static int get sizeIndex => Prefs.getInt(kSize, 1).clamp(0, 2);
  static int get spotIndex =>
      Prefs.getInt(kSpot, 0).clamp(0, AiButtonSpot.values.length - 1);
  static int get visibilityIndex => Prefs.getInt(kVisibility, 0).clamp(0, 2);

  static double get side => sides[sizeIndex];
  static AiButtonSpot get spot => AiButtonSpot.values[spotIndex];
  static double get opacity => opacities[visibilityIndex];

  static void setOn(bool v) {
    Prefs.setBool(kOn, v);
    changed.value++;
  }

  static void setIndex(String key, int v) {
    Prefs.setInt(key, v);
    changed.value++;
  }
}
