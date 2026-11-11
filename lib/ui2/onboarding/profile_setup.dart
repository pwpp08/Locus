import '../../l10n/display_text.dart';
// Profile setup.
//
// The audit found this screen promising one thing and enforcing another: the
// copy said "leave a field blank and only that metric stays unknown — never
// guessed", and the validator then refused to continue until all four were
// filled. A promise the form contradicts is worse than no promise, because it
// teaches the user that the honesty copy elsewhere is decoration too.
//
// So: every field is optional except sex, which is the one input with no
// honest default — the analytics coefficient tables key on it and the
// midpoint of two sexes is a third person. Everything else that is blank
// simply withholds the metrics that need it.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/date_text.dart';
import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../screens/home_screen.dart' show monthShortName, weekdayShortName;
import '../screens/dial_parts.dart'
    show dialCard, dialCardTitle, kDialPad;
import '../ui2.dart';
import 'welcome.dart' show OnboardingPage;

class ProfileSetupScreen extends StatefulWidget {
  /// Called after the profile has been written. The router uses it to let a
  /// deliberately-partial profile through the gate.
  final VoidCallback? onDone;

  const ProfileSetupScreen({super.key, this.onDone});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  @override
  Widget build(BuildContext c) {
    final app = context.read<AppState>();
    return ProfileSetupView(
      initial: app.user ?? const {},
      units: context.watch<UnitsController>(),
      cycleTracking: app.cycleTrackingEnabled,
      onSave: (fields) async {
        await app.updateProfile(fields);
        widget.onDone?.call();
      },
      onCycleTracking: app.setCycleTrackingEnabled,
    );
  }
}

/// The three answers the analytics coefficient tables can take.
///
/// 'other' maps to the non-binary block FOR CALORIES, which is the published
/// mean of the two sex constants. It does NOT for training load: Banister
/// publishes two constants and no third, so `nonbinary` collapses onto the
/// male pair everywhere TRIMP and the 0–21 strain score are computed
/// (`derivation_engine.dart` says so at its collapse). The screen says which,
/// because a woman who picks it is otherwise scored as a man with nothing on
/// screen admitting it.
List<(String, String)> _sexes(BuildContext c) {
  final l = AppLocalizations.of(c);
  return [
    ('m', l?.profileSetupSexMale ?? 'Male'),
    ('f', l?.profileSetupSexFemale ?? 'Female'),
    ('other', l?.profileSetupSexPreferNotToSay ?? 'Prefer not to say'),
  ];
}

class ProfileSetupView extends StatefulWidget {
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> fields) onSave;

  /// Display units for height and weight. Null is metric, which is also what
  /// the storage is.
  final UnitsController? units;

  /// Cycle tracking, offered here rather than left off in Settings where
  /// nobody found it. [cycleTracking] is the current setting; null leaves the
  /// switch to follow the sex picked (on for female).
  final bool? cycleTracking;
  final Future<void> Function(bool on)? onCycleTracking;

  const ProfileSetupView(
      {super.key,
      required this.onSave,
      this.initial = const {},
      this.units,
      this.cycleTracking,
      this.onCycleTracking});

  @override
  State<ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<ProfileSetupView> {
  late final UnitsController _u =
      widget.units ?? UnitsController.seed(UnitSystem.metric);
  late String? _sex = (widget.initial['sex'] as String?)?.toLowerCase();
  late final _age = TextEditingController(text: _str(widget.initial['age']));
  late final _height = TextEditingController(
      text: _u.heightField(widget.initial['height_cm'] as num?));
  late final _weight = TextEditingController(
      text: _u.weightField(widget.initial['weight_kg'] as num?));

  static String _str(Object? v) => v == null ? '' : '$v';

  /// Null until touched: then it follows the sex picked, on for female.
  bool? _cycle;
  bool get _cycleOn => _cycle ?? (widget.cycleTracking == true || _sex == 'f');

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// Only what was actually entered. A blank field writes nothing, so the
  /// dependent metric abstains rather than scoring somebody else's body. The
  /// fields are typed in the units on their labels and stored in metric.
  Map<String, dynamic> _fields() => {
        if (_sex != null) 'sex': _sex,
        if (Typed.of(_age.text).value case final v?) 'age': v.round(),
        'height_cm': ?_u.heightToCm(_height.text),
        'weight_kg': ?_u.weightToKg(_weight.text),
      };

  /// Continue, unless something typed cannot be read — a typo is not a blank,
  /// and dropping it silently is how a body ends up half-described.
  Future<void> _continue() async {
    final bad = [
      if (Typed.of(_age.text).bad) 'Age',
      if (Typed.of(_height.text).bad) uiText(context, _u.heightLabel),
      if (Typed.of(_weight.text).bad) uiText(context, _u.weightLabel),
    ];
    if (bad.isNotEmpty) {
      sayUnreadable(context, bad);
      return;
    }
    await widget.onCycleTracking?.call(_cycleOn);
    await widget.onSave(_fields());
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final sexes = _sexes(c);
    return OnboardingPage(
      step: 3,
      title: l?.profileSetupTitle ?? 'About you',
      body: l?.profileSetupBody ??
          'Four numbers change how your data is scored. Leave any of them '
              'blank and only the metrics that need it stay unavailable.',
      below: [
        const SizedBox(height: S.x6),
        _Card(
          title: l?.profileSetupSexHeader ?? 'SEX',
          children: [
            for (final (key, label) in sexes)
              _Choice(
                label: label,
                on: _sex == key,
                onTap: () => setState(() => _sex = key),
              ),
          ],
        ),
        // Which constants that choice actually gets. Calories average the
        // two published sets; training load has no third set to average,
        // so it uses the male one — said here rather than nowhere.
        if (_sex == 'other') ...[
          const SizedBox(height: S.x2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x1),
            child: Text(
              l?.profileSetupOtherSexNote ??
                  'Calories use the mean of the two published sets. Training '
                      'load and strain have only two published constants and no '
                      'third, so they use the male pair.',
              style: F.dTiny.copyWith(color: DC.ink3, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: S.x3),
        _Card(
          title: l?.profileSetupOptional ?? 'OPTIONAL',
          children: [
            _Field(_age, l?.profileSetupAgeLabel ?? 'AGE',
                l?.profileSetupAgeUnit ?? 'years',
                l?.profileSetupAgeConsequence ??
                    'Without it: heart-rate zones, calories, fitness age.'),
            _Field(
              _height,
              l?.profileSetupHeightLabel ?? 'HEIGHT',
              uiText(c, _u.isImperial ? 'in' : 'cm'),
              l?.profileSetupHeightConsequence ??
                  'Without it: stride length, and distance from steps.',
            ),
            _Field(
              _weight,
              l?.profileSetupWeightLabel ?? 'WEIGHT',
              uiText(c, _u.isImperial ? 'lb' : 'kg'),
              l?.profileSetupWeightConsequence ??
                  'Without it: calories and training load.',
            ),
          ],
        ),
        const SizedBox(height: S.x3),
        // Offered to everyone, on by default for a female profile.
        // Changeable any time in Settings; switching it off keeps what
        // was logged. Merged, so the row is read as one switch with its
        // title.
        _Card(children: [
          MergeSemantics(
            child: _Row(
              title: l?.settingsCycleTrackingRowTitle ?? 'Cycle tracking',
              sub: l?.profileSetupCycleSub ??
                  'Log your period in Health. You can change this later.',
              trailing: AppSwitch(_cycleOn, (v) => setState(() => _cycle = v)),
            ),
          ),
        ]),
      ],
      actions: [
        BigButton(l?.actionContinue ?? 'Continue',
            onTap: _sex == null ? null : _continue),
        if (_sex == null) ...[
          const SizedBox(height: S.x3),
          Text(
              l?.profileSetupPickOneToContinue ??
                  'Pick one option above to continue.',
              textAlign: TextAlign.center,
              style: F.dTiny.copyWith(color: DC.ink3)),
        ],
      ],
    );
  }
}

/// A dial card holding rows on hairlines: the title in tracked capitals over
/// them.
class _Card extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const _Card({this.title, required this.children});

  @override
  Widget build(BuildContext c) => Container(
        padding: EdgeInsets.fromLTRB(
            kDialPad, title == null ? 0 : kDialPad, kDialPad, 0),
        decoration: dialCard(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title case final t?)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x2),
              child: dialCardTitle(t),
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 || title != null)
              const Divider(height: S.hair, thickness: S.hair, color: DC.line),
            children[i],
          ],
        ]),
      );
}

/// One row of a card: the name in capitals with its line under it, and
/// whatever answers it flush against the right edge.
class _Row extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget trailing;
  const _Row({required this.title, this.sub, required this.trailing});

  @override
  Widget build(BuildContext c) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: S.x12 + S.x1 + S.half),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title.toUpperCase(),
                      style: F.dNav.copyWith(color: DC.ink)),
                  if (sub case final s?) ...[
                    const SizedBox(height: S.x1),
                    Text(s,
                        style: F.dTiny.copyWith(color: DC.ink3, height: 1.35)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: S.x3),
            trailing,
          ]),
        ),
      );
}

/// One answer to "sex": the word in capitals and a round mark on the right,
/// filled white with a check when chosen.
class _Choice extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Choice({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: _Row(
          title: label,
          trailing: AnimatedContainer(
            duration: motion(c, Motion.fast),
            width: S.x5 + S.half,
            height: S.x5 + S.half,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? DC.pure : null,
              border: on ? null : Border.all(color: DC.ink3, width: S.half - S.hair / 2),
            ),
            child: on
                ? const Icon(LucideIcons.check, size: I.sm, color: DC.bgFoot)
                : null,
          ),
        ),
      );
}

/// A body measure: its name and what goes missing without it on the left;
/// on the right the figure, typed into a small well and set flush right in
/// the numerals, then its unit in a fixed slot so the three figures line up.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label, unit, consequence;
  const _Field(this.controller, this.label, this.unit, this.consequence);

  @override
  Widget build(BuildContext c) => _Row(
        title: label,
        sub: consequence,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: S.x16 + S.x2,
            height: S.x10,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: S.x3),
            decoration: const BoxDecoration(color: DC.field, borderRadius: R.rMd),
            child: AppField(
              controller: controller,
              bare: true,
              semanticLabel: label,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              textStyle: F.n24.copyWith(color: DC.ink),
            ),
          ),
          const SizedBox(width: S.x2),
          SizedBox(
            width: S.x8 + S.x1,
            child: Text(unit, style: F.dText.copyWith(color: DC.ink2)),
          ),
        ]),
      );
}

// No day-0 "unlock contract" card. There was one — locked headline, unlock
// date, nights banked, live HR beside it — and nothing ever built it. Day zero
// is carried by `StatusCard.forMetric`, which already says how many more
// nights the metric needs.

/// "Thu 4 Sep" — a date a person can hold, not an ISO string. Local by
/// construction; the app's day labels are local everywhere.
String formatDay(DateTime d, [AppLocalizations? l]) =>
    l?.localeName.startsWith('ru') == true
    ? localizedDate(d, l!.localeName, pattern: 'EEE d MMM')
    : '${weekdayShortName(d.weekday, l)} ${d.day} ${monthShortName(d.month, l)}';
