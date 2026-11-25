// What to do, step by step, before searching for a device: the one place the
// per-device setup wording lives, so a pairing screen never invents its own.
//
// DATA FIRST. A guide is a [SetupGuideSpec]: one or more situations
// ([SetupPath]), each a short numbered list, plus a plain statement of what the
// device gives and what it does not. The widget only draws it. Wording follows
// the app's honesty rule: what a device cannot do is said as plainly as what it
// can, and a device nobody has put hardware on says it is experimental.

import 'package:flutter/material.dart';

import '../../l10n/display_text.dart';
import '../ui2.dart';

/// One situation a user may be in, and the steps that fit it.
class SetupPath {
  /// The segment label: two or three words.
  final String label;
  final List<String> steps;

  /// A sentence under the steps (what this costs, how to undo it), or null.
  final String? note;
  const SetupPath(this.label, this.steps, {this.note});
}

/// Everything a pairing screen says before it searches.
class SetupGuideSpec {
  /// The question the segments answer ("Where is the ring set up now?"), or
  /// null for a device with a single way in.
  final String? question;
  final List<SetupPath> paths;

  /// What the device feeds the app, and what it does not.
  final String gives, lacks;
  const SetupGuideSpec({
    this.question,
    required this.paths,
    required this.gives,
    required this.lacks,
  });
}

/// The guide for a registry id, or null for a device that needs none.
SetupGuideSpec? setupGuideFor(String? adapterId) => kSetupGuides[adapterId];

/// A Garmin watch and the Garmin band share one protocol and one pairing
/// state, so one entry holds both ways in. Keyed by registry id.
const Map<String, SetupGuideSpec> kSetupGuides = {
  'oura': SetupGuideSpec(
    question: 'Where is your ring set up right now?',
    paths: [
      SetupPath(
        'In the Oura app',
        [
          'Open the Oura app and remove the ring there (the ring’s page, then Remove or Factory reset).',
          'Close the Oura app completely: swipe it away so it cannot reconnect.',
          'Put the ring on its charger, next to your phone.',
          'Tap Find my device below and pick your ring.',
        ],
        note: 'The ring holds one key. Pairing here gives it Locus’s key, so the '
            'Oura app stops working with it. To go back, remove the ring here '
            'and set it up in the Oura app again.',
      ),
      SetupPath(
        'New or reset',
        [
          'Do not open the Oura app: it would install its own key first.',
          'Charge the ring for a few minutes and keep it next to your phone.',
          'Tap Find my device below and pick your ring.',
        ],
      ),
      SetupPath(
        'Dock reset',
        [
          'Use this when the Oura app cannot reach the ring. Seat the ring on its dock.',
          'Flip the dock upside down and wait for a blue light.',
          'Flip it upright and wait for red.',
          'Upside down again for purple, then upright for yellow: yellow means the reset has started.',
          'Wait for a blinking blue light. That means it is done.',
          'Tap Find my device below and pick your ring.',
        ],
        note: 'Already have the ring’s key? Paste it in the field further down '
            'instead, and no reset is needed.',
      ),
    ],
    gives: 'Heart rate, HRV, skin temperature, blood oxygen, sleep stages and activity, read straight from the ring.',
    lacks: 'Oura’s own 0 to 100 scores. Locus works its numbers out itself. Experimental until tested on a real ring.',
  ),
  'garmin': SetupGuideSpec(
    question: 'Which Garmin do you have?',
    paths: [
      SetupPath(
        'Watch',
        [
          'Close the Garmin Connect app on your phone. A Garmin watch talks to one app at a time.',
          'On the watch open Settings, then Sensors & Accessories, then Phone, then Pair Phone. On some models it is Settings, then Phone, then Pair Phone.',
          'Leave the watch on that screen.',
          'Tap Find my device below and pick your watch.',
        ],
        note: 'To use Garmin Connect again, open it. It takes the watch back '
            'the next time Locus is not connected.',
      ),
      SetupPath(
        'Cirqa band',
        [
          'Close the Garmin Connect app on your phone.',
          'Put the Cirqa on its charger, then hold its button until the light blinks (pairing mode).',
          'Keep it next to your phone.',
          'Tap Find my device below and pick your Cirqa.',
        ],
        note: 'Nobody has tested the Cirqa yet. If it does not show up, it is '
            'not supported here yet, and your data is untouched.',
      ),
    ],
    gives: 'Steps, heart rate, sleep, HRV, stress and Body Battery, read from the files the watch stores.',
    lacks: 'Live heart rate unless the watch broadcasts it. Experimental until tested on a real watch.',
  ),
  'helio': SetupGuideSpec(
    paths: [
      SetupPath(
        'Helio Strap',
        [
          'Link the strap in the Zepp app first, the normal way, if you have not. Locus reads the key Zepp made for it.',
          'Do step 1 below: sign in to Zepp with your email and password. Google and Apple sign-in do not work there.',
          'Close the Zepp app completely (Android: App info, then Force stop). The strap talks to one app at a time.',
          'Put the strap on its charger and keep it next to your phone.',
          'Tap Find my device below and pick your strap.',
        ],
        note: 'Do not unlink the strap in Zepp. That makes a new key and the '
            'old one stops working. To use Zepp again, open it; it takes the '
            'strap back when Locus is not connected.',
      ),
    ],
    gives: 'Heart rate, steps, sleep stages, HRV, SpO2, stress and skin temperature, read straight from the strap.',
    lacks: 'Alarms and live heart rate. Experimental until tested on a real strap.',
  ),
  'ble_hrs': SetupGuideSpec(
    paths: [
      SetupPath(
        'Strap or armband',
        [
          'Put it on, with the strap wet or the electrodes moistened.',
          'Close any other app that is connected to it. Most straps talk to one phone at a time.',
          'Tap Find my device below and pick it.',
        ],
      ),
    ],
    gives: 'Live heart rate during a workout.',
    lacks: 'Sleep, steps and history. A sensor nobody has tested here yet is experimental.',
  ),
  // The Fitbit Air does not pair over Bluetooth: Google Health owns its link
  // and writes what it measures into Health Connect, which Locus reads.
  'fitbit_air': SetupGuideSpec(
    question: 'Where are you in setting it up?',
    paths: [
      SetupPath(
        'Set up',
        [
          'Pair the Air in the Google Health app, the way you normally do. Locus does not connect to it directly.',
          'In Google Health open its settings and turn on sharing with Health Connect. Allow heart rate, sleep and steps.',
          'Wear the Air and let Google Health sync.',
          'Back here, tap Open watch comparison and allow Locus to read from Health Connect.',
          'Pick the Google Health entry in the source list.',
        ],
        note: 'Locus shows the Air’s numbers beside your own, under its '
            'source’s name. Nothing is sent anywhere.',
      ),
      SetupPath(
        'Not showing up',
        [
          'Tap Open Health Connect below, then App permissions. Check Google Health may write and Locus may read.',
          'Open Google Health and sync the Air, so there is new data to read.',
          'Come back and open the watch comparison again.',
        ],
        note: 'Google Health decides what it writes and when, so a night can '
            'arrive late.',
      ),
    ],
    gives: 'Whatever Google Health writes to Health Connect, usually heart rate, sleep and steps, shown next to your own numbers. Its workouts can be imported from Workout, History.',
    lacks: 'Scores. The Air’s numbers are shown, never used in your recovery, sleep or strain. Android only.',
  ),
};

/// The guide on a pairing screen: the situation picker, the numbered steps,
/// and a plain line on what the device does and does not give.
class SetupGuideCard extends StatefulWidget {
  final SetupGuideSpec spec;

  /// Which situation shows first.
  final int initial;
  const SetupGuideCard(this.spec, {super.key, this.initial = 0});

  @override
  State<SetupGuideCard> createState() => _SetupGuideCardState();
}

class _SetupGuideCardState extends State<SetupGuideCard> {
  late int _i = widget.initial.clamp(0, widget.spec.paths.length - 1);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final s = widget.spec;
    final path = s.paths[_i];
    return Section(
      uiText(c, 'Before you search'),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (s.question != null) ...[
            Text(uiText(c, s.question!),
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: S.x3),
          ],
          if (s.paths.length > 1) ...[
            RangeSegments(
              [for (final x in s.paths) uiText(c, x.label)],
              _i,
              (i) => setState(() => _i = i),
              width: null,
            ),
            const SizedBox(height: S.x4),
          ],
          for (var n = 0; n < path.steps.length; n++)
            Padding(
              padding: EdgeInsets.only(top: n == 0 ? 0 : S.x3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: S.x6,
                  child: Text('${n + 1}',
                      style: F.body.copyWith(
                          color: p.ink3, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: Text(uiText(c, path.steps[n]),
                      style: F.body.copyWith(color: p.ink, height: 1.35)),
                ),
              ]),
            ),
          if (path.note != null) ...[
            const SizedBox(height: S.x4),
            Text(uiText(c, path.note!),
                style: F.cap.copyWith(color: p.ink3, height: 1.5)),
          ],
          const SizedBox(height: S.x4),
          Divider(color: p.line, height: S.hair),
          const SizedBox(height: S.x3),
          Text(uiText(c, s.gives),
              style: F.cap.copyWith(color: p.ink2, height: 1.5)),
          const SizedBox(height: S.x2),
          Text(uiText(c, s.lacks),
              style: F.cap.copyWith(color: p.ink3, height: 1.5)),
        ]),
      ),
    );
  }
}
