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
import '../screens/dial_parts.dart' show dialCard, kDialPad;
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
      onSave: (fields) async {
        await app.updateProfile(fields);
        widget.onDone?.call();
      },
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
    // Short enough for a third of the switcher; Edit profile says the same.
    ('other', 'Other'),
  ];
}

class ProfileSetupView extends StatefulWidget {
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> fields) onSave;

  /// Display units for height and weight. Null is metric, which is also what
  /// the storage is.
  final UnitsController? units;

  const ProfileSetupView(
      {super.key,
      required this.onSave,
      this.initial = const {},
      this.units});

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
        const SizedBox(height: S.x8),
        _Label(l?.profileSetupSexHeader ?? 'SEX'),
        // The switcher every choice in the app uses.
        RangeSegments(
          [for (final (_, label) in sexes) label.toUpperCase()],
          sexes.indexWhere((e) => e.$1 == _sex),
          (i) => setState(() => _sex = sexes[i].$1),
          width: null,
        ),
        // Which constants that choice actually gets. Calories average the
        // two published sets; training load has no third set to average,
        // so it uses the male one — said here rather than nowhere.
        if (_sex == 'other') ...[
          const SizedBox(height: S.x2),
          Text(
            l?.profileSetupOtherSexNote ??
                'Calories use the mean of the two published sets. Training '
                    'load and strain have only two published constants and no '
                    'third, so they use the male pair.',
            style: F.dTiny.copyWith(color: DC.ink3, height: 1.4),
          ),
        ],
        const SizedBox(height: S.x6),
        _Label(l?.profileSetupOptional ?? 'OPTIONAL'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: kDialPad),
          decoration: dialCard(),
          child: Column(children: [
            _Field(_age, l?.profileSetupAgeLabel ?? 'AGE',
                l?.profileSetupAgeUnit ?? 'years'),
            const Divider(height: S.hair, thickness: S.hair, color: DC.line),
            _Field(_height, l?.profileSetupHeightLabel ?? 'HEIGHT',
                uiText(c, _u.isImperial ? 'in' : 'cm')),
            const Divider(height: S.hair, thickness: S.hair, color: DC.line),
            _Field(_weight, l?.profileSetupWeightLabel ?? 'WEIGHT',
                uiText(c, _u.isImperial ? 'lb' : 'kg')),
          ]),
        ),
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

/// A group's name in tracked capitals, over what it names.
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(left: S.x1, bottom: S.x3),
        child: Text(text.toUpperCase(),
            style: F.dLabel.copyWith(color: DC.ink2)),
      );
}

/// A body measure on one line: its name on the left; on the right the
/// figure, typed into a small well and set flush right in the numerals, then
/// its unit in a fixed slot so the three figures line up.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label, unit;
  const _Field(this.controller, this.label, this.unit);

  @override
  Widget build(BuildContext c) => SizedBox(
        height: S.x12 + S.x4,
        child: Row(children: [
          Expanded(
            child: Text(label.toUpperCase(),
                style: F.dNav.copyWith(color: DC.ink)),
          ),
          Container(
            width: S.x16 + S.x2,
            height: S.x10,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: S.x3),
            decoration:
                const BoxDecoration(color: DC.field, borderRadius: R.rMd),
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
