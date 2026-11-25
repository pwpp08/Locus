// The Fitbit Air, through Health Connect: no Bluetooth step, only what to set
// up in the app that owns the watch and where the numbers then appear.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/display_text.dart';
import '../../state/app_state.dart';
import '../screens/watch_compare_screen.dart' show WatchCompareScreen;
import '../ui2.dart';
import 'profile.dart';
import 'setup_guide.dart';

class HealthConnectGuideScreen extends StatelessWidget {
  const HealthConnectGuideScreen({super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(uiText(c, 'Fitbit Air'),
                sub: uiText(c, 'Through Health Connect')),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                SetupGuideCard(kSetupGuides['fitbit_air']!),
                const SizedBox(height: S.x4),
                BigButton(uiText(c, 'Open watch comparison'),
                    icon: LucideIcons.chartLine,
                    color: C.dialStrain,
                    onTap: () => goto(c, const WatchCompareScreen())),
                const SizedBox(height: S.x3),
                BigButton(uiText(c, 'Open Health Connect'),
                    soft: true,
                    icon: LucideIcons.heartPulse,
                    onTap: () => c.read<AppState>().openHealthConnect()),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
