// Pushed routes. There is one theme (dark), so nothing here switches
// anything any more; [themedRoute] stays because every push names its screen
// through it.

import 'package:flutter/material.dart';

/// The route every screen is pushed with.
///
/// NAVIGATION CONTRACT — this MUST stay a [MaterialPageRoute] (or another
/// route mixing in Material/Cupertino route-transition machinery). A raw
/// PageRouteBuilder has no interactive back-gesture support, which silently
/// kills the iOS edge-swipe-back on every pushed screen. Transitions therefore
/// live in the theme's pageTransitionsTheme (`buildTheme`, lib/ui2/theme.dart):
/// each platform's own, gated by reduced motion, so iOS/macOS keep the
/// Cupertino slide WITH swipe-back.
/// [name] shows up as `current_screen` on the next Crashlytics crash/ANR
/// report (see TelemetryNavigatorObserver) — without it, every push here
/// falls back to a generic `MaterialPageRoute<...>` label, which isn't useful
/// for figuring out which screen a report actually happened on. Pass the
/// destination screen's name at each call site.
PageRoute<T> themedRoute<T>(
  WidgetBuilder builder, {
  bool fullscreenDialog = false,
  String? name,
}) => MaterialPageRoute<T>(
  fullscreenDialog: fullscreenDialog,
  settings: RouteSettings(name: name),
  builder: builder,
);
