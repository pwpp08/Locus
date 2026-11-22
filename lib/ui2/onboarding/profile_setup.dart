// Profile setup: four pages laid out on their reference — the name, the
// birthday on a wheel, height and weight on wheels in either units, and the
// sex the scoring tables key on. Each page has one way on, NEXT, and it stays
// grey until the page has what it needs. Settings' profile editors open the
// same pages one at a time (see [NamePage] and the rest).
//
// Sex is the one answer with no honest default — the analytics coefficient
// tables key on it, and the midpoint of two sexes is a third person — so the
// last page will not go on without it. The birthday, height and weight carry
// a value from the start (a wheel always points at something), and the
// person moves it to theirs.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compute/profile.dart' show birthDateOf, wholeYearsOn;
import '../../data/day_label.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/date_text.dart';
import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../screens/home_screen.dart' show monthShortName, weekdayShortName;
import '../ui2.dart';
import 'setup_parts.dart';

class ProfileSetupScreen extends StatelessWidget {
  /// Called after the profile has been written. The router uses it to let a
  /// deliberately-partial profile through the gate.
  final VoidCallback? onDone;

  const ProfileSetupScreen({super.key, this.onDone});

  @override
  Widget build(BuildContext c) {
    final app = c.read<AppState>();
    return ProfileSetupView(
      initial: app.user ?? const {},
      units: c.watch<UnitsController>(),
      onSave: (fields) async {
        await app.updateProfile(fields);
        onDone?.call();
      },
    );
  }
}

/// The profile's names as written: first and last, and the one the person
/// goes by in the community.
({String first, String last, String user}) namesOf(Map<String, dynamic> u) {
  final first = (u['first_name'] as String?)?.trim() ?? '';
  final last = (u['last_name'] as String?)?.trim() ?? '';
  // A profile from before the split keeps its one name as the first.
  if (first.isEmpty && last.isEmpty) {
    final whole = (u['name'] as String?)?.trim() ?? '';
    final i = whole.indexOf(' ');
    return (
      first: i < 0 ? whole : whole.substring(0, i),
      last: i < 0 ? '' : whole.substring(i + 1).trim(),
      user: (u['username'] as String?)?.trim() ?? '',
    );
  }
  return (
    first: first,
    last: last,
    user: (u['username'] as String?)?.trim() ?? '',
  );
}

/// The fields a name page writes: the parts, and the whole name the rest of
/// the app reads ("Hi Max", the profile header).
Map<String, dynamic> nameFields(String first, String last, String user) {
  final f = first.trim(), l = last.trim(), u = user.trim();
  final whole = [f, l].where((e) => e.isNotEmpty).join(' ');
  return {
    'first_name': f.isEmpty ? null : f,
    'last_name': l.isEmpty ? null : l,
    'username': u.isEmpty ? null : u,
    'name': whole.isEmpty ? null : whole,
  };
}

/// The fields a birthday writes: the day, and the age it makes today.
Map<String, dynamic> birthFields(DateTime b) => {
      'birth_date': dayLabelOf(b),
      'age': wholeYearsOn(b, DateTime.now()),
    };

/// How far through setup each page is, round the NEXT ring.
const _progress = [.11, .2, .33, .57];

class ProfileSetupView extends StatefulWidget {
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> fields) onSave;

  /// Display units for height and weight. Null is metric, which is also what
  /// the storage is.
  final UnitsController? units;

  /// The page to open on, for a picture of one.
  final int page;

  const ProfileSetupView({
    super.key,
    required this.onSave,
    this.initial = const {},
    this.units,
    this.page = 0,
  });

  @override
  State<ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<ProfileSetupView> {
  late int _page = widget.page;
  final _fields = <String, dynamic>{};

  void _next(Map<String, dynamic> f) {
    _fields.addAll(f);
    if (_page < 3) {
      setState(() => _page++);
    } else {
      widget.onSave(Map.of(_fields));
    }
  }

  void _back(BuildContext c) {
    if (_page > 0) {
      setState(() => _page--);
    } else {
      Navigator.of(c).maybePop();
    }
  }

  @override
  Widget build(BuildContext c) {
    final first = _page == 0 && !Navigator.of(c).canPop();
    final back = first ? null : () => _back(c);
    final at = {...widget.initial, ..._fields};
    final page = switch (_page) {
      0 => NamePage(
          initial: at, progress: _progress[0], onBack: back, onDone: _next),
      1 => BirthdayPage(
          initial: at, progress: _progress[1], onBack: back, onDone: _next),
      2 => BodyPage(
          initial: at,
          units: widget.units,
          progress: _progress[2],
          onBack: back,
          onDone: _next),
      _ => SexPage(
          initial: at, progress: _progress[3], onBack: back, onDone: _next),
    };
    return AnimatedSwitcher(
      duration: motion(c, Motion.base),
      child: KeyedSubtree(key: ValueKey(_page), child: page),
    );
  }
}

/// "Welcome to Locus!" — the first name, the last, and the name for the
/// community.
class NamePage extends StatefulWidget {
  final Map<String, dynamic> initial;
  final ValueChanged<Map<String, dynamic>> onDone;
  final VoidCallback? onBack;
  final double progress;
  final String action;
  final bool editing;

  const NamePage({
    super.key,
    required this.onDone,
    this.initial = const {},
    this.onBack,
    this.progress = 0,
    this.action = 'NEXT',
    this.editing = false,
  });

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  late final _n = namesOf(widget.initial);
  late final _first = TextEditingController(text: _n.first);
  late final _last = TextEditingController(text: _n.last);
  late final _user = TextEditingController(text: _n.user);

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _user.dispose();
    super.dispose();
  }

  bool get _ready =>
      _first.text.trim().isNotEmpty && _user.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext c) {
    void changed(String _) => setState(() {});
    return SetupFrame(
      picture: const ClapPicture(),
      pictureTop: S.x16 + S.x10 + S.x3,
      title: widget.editing ? 'Your name' : 'Welcome to Locus!',
      body: 'Tell us what to call you, and how to spell it.',
      progress: widget.progress,
      action: widget.action,
      onBack: widget.onBack,
      onNext: _ready
          ? () => widget.onDone(nameFields(_first.text, _last.text, _user.text))
          : null,
      children: [
        const SizedBox(height: S.x6 + S.x1),
        SetupField(_first, label: 'First name', onChanged: changed),
        const SizedBox(height: S.x6 + S.x1),
        SetupField(_last, label: 'Last name', onChanged: changed),
        const SizedBox(height: S.x6 + S.x1),
        SetupField(_user,
            label: 'Username',
            capital: TextCapitalization.none,
            action: TextInputAction.done,
            onChanged: changed),
      ],
    );
  }
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

/// The birthday on three wheels: day, month, year.
class BirthdayPage extends StatefulWidget {
  final Map<String, dynamic> initial;
  final ValueChanged<Map<String, dynamic>> onDone;
  final VoidCallback? onBack;
  final double progress;
  final String action;

  /// Today, for the years on offer; the clock when null.
  final DateTime? now;

  const BirthdayPage({
    super.key,
    required this.onDone,
    this.initial = const {},
    this.onBack,
    this.progress = 0,
    this.action = 'NEXT',
    this.now,
  });

  @override
  State<BirthdayPage> createState() => _BirthdayPageState();
}

class _BirthdayPageState extends State<BirthdayPage> {
  late final DateTime _now = widget.now ?? DateTime.now();

  /// Oldest first; the youngest is 13.
  late final int _y0 = _now.year - 100;
  late final int _years = 100 - 13 + 1;
  late final DateTime _b0 =
      birthDateOf(widget.initial) ?? DateTime(_now.year - 30, 1, 1);
  late int _day = _b0.day, _month = _b0.month, _year = _b0.year;

  /// The day the wheels point at, a 31st pulled back into a shorter month.
  DateTime get _birth {
    final last = DateTime(_year, _month + 1, 0).day;
    return DateTime(_year, _month, _day > last ? last : _day);
  }

  @override
  Widget build(BuildContext c) {
    final year = (_year - _y0).clamp(0, _years - 1);
    return SetupFrame(
      picture: const ClipboardPicture(),
      pictureTop: S.x16 + S.x8 + S.x3 - S.half - S.hair,
      title: 'When Were You Born?',
      body: 'Your age sets the ranges your numbers are read against, so '
          'the coaching fits you.',
      progress: widget.progress,
      action: widget.action,
      onBack: widget.onBack,
      onNext: () => widget.onDone(birthFields(_birth)),
      children: [
        const SizedBox(height: S.x10 + S.x1 + S.half),
        SetupWheels(
          height: S.x16 * 3 + S.x8 + S.x1,
          bands: const [(S.x6 + S.x1 + S.hair, S.x16 * 4 + S.x12 - S.x1)],
          wheels: [
            const SizedBox(width: S.x6 + S.x1 + S.hair),
            SetupWheel(
              count: 31,
              initial: _day - 1,
              loop: true,
              squeeze: 1.57,
              rowHeight: S.x8,
              width: S.x16 + S.x2 - S.hair,
              label: (i) => '${i + 1}',
              onChanged: (i) => setState(() => _day = i + 1),
            ),
            SetupWheel(
              count: 12,
              initial: _month - 1,
              loop: true,
              squeeze: 1.57,
              rowHeight: S.x8,
              width: S.x16 * 2 - S.x3 - S.hair,
              label: (i) => _monthNames[i],
              onChanged: (i) => setState(() => _month = i + 1),
            ),
            SetupWheel(
              count: _years,
              initial: year,
              squeeze: 1.57,
              rowHeight: S.x8,
              width: S.x16 * 2 - S.x1 - S.hair,
              label: (i) => '${_y0 + i}',
              onChanged: (i) => setState(() => _year = _y0 + i),
            ),
          ],
        ),
      ],
    );
  }
}

/// Height and weight on wheels, in imperial or metric.
class BodyPage extends StatefulWidget {
  final Map<String, dynamic> initial;
  final UnitsController? units;
  final ValueChanged<Map<String, dynamic>> onDone;
  final VoidCallback? onBack;
  final double progress;
  final String action;

  const BodyPage({
    super.key,
    required this.onDone,
    this.initial = const {},
    this.units,
    this.onBack,
    this.progress = 0,
    this.action = 'NEXT',
  });

  @override
  State<BodyPage> createState() => _BodyPageState();
}

/// The wheels' ranges.
const _ft0 = 3, _ftN = 5; // 3–7 ft
const _cm0 = 120, _cmN = 101; // 120–220 cm
const _lb0 = 66, _lbN = 375; // 66–440 lb
const _kg0 = 30, _kgN = 171; // 30–200 kg
const _cmPerIn = 2.54, _kgPerLb = 0.45359237;

class _BodyPageState extends State<BodyPage> {
  late bool _imperial = widget.units?.isImperial ?? false;
  late double _cm =
      ((widget.initial['height_cm'] as num?)?.toDouble() ?? 170)
          .clamp(_cm0.toDouble(), (_cm0 + _cmN - 1).toDouble());
  late double _kg =
      ((widget.initial['weight_kg'] as num?)?.toDouble() ?? 70)
          .clamp(_kg0.toDouble(), (_kg0 + _kgN - 1).toDouble());

  int get _inches => (_cm / _cmPerIn).round();
  int get _ft => (_inches ~/ 12).clamp(_ft0, _ft0 + _ftN - 1);
  int get _in => _inches % 12;

  void _setFeet(int ft, int inch) =>
      setState(() => _cm = (ft * 12 + inch) * _cmPerIn);

  @override
  Widget build(BuildContext c) {
    // The bands sit where the reference puts them: height from 38, weight
    // from 188, both 135 wide.
    const hLeft = S.x8 + S.x1 + S.hair, bandW = S.x16 * 2 + S.x3 - S.hair;
    const wLeft = S.x16 * 3 - S.x1;
    const half = bandW / 2;
    return SetupFrame(
      picture: const ClipboardPicture(),
      pictureTop: S.x16 + S.x5 + S.half,
      title: 'Your Height and Weight',
      body: 'Both go into your calories and strain. You can change them any '
          'time in your profile.',
      progress: widget.progress,
      action: widget.action,
      onBack: widget.onBack,
      onNext: () => widget.onDone({
        'height_cm': double.parse(_cm.toStringAsFixed(1)),
        'weight_kg': double.parse(_kg.toStringAsFixed(1)),
      }),
      children: [
        const SizedBox(height: S.x6 + S.x1),
        SetupSegments(
          const ['Imperial', 'Metric'],
          chosen: _imperial ? 0 : 1,
          onChoose: (i) {
            setState(() => _imperial = i == 0);
            widget.units
                ?.setSystem(i == 0 ? UnitSystem.imperial : UnitSystem.metric);
          },
        ),
        const SizedBox(height: S.x8 + S.half),
        Row(children: [
          const SizedBox(width: hLeft),
          SizedBox(
              width: bandW,
              child: Text('HEIGHT',
                  textAlign: TextAlign.center,
                  style: OB.caps.copyWith(color: OB.label))),
          const SizedBox(width: wLeft - hLeft - bandW),
          SizedBox(
              width: bandW,
              child: Text('WEIGHT',
                  textAlign: TextAlign.center,
                  style: OB.caps.copyWith(color: OB.label))),
        ]),
        SetupWheels(
          height: S.x16 * 2 + S.x10 + S.x1 + S.half,
          bandHeight: S.x8 + S.x1 - S.hair,
          bandRadius: const BorderRadius.all(Radius.circular(S.half)),
          bands: const [(hLeft, bandW), (wLeft, bandW)],
          wheels: [
            const SizedBox(width: hLeft),
            if (_imperial) ...[
              SetupWheel(
                key: const ValueKey('ft'),
                count: _ftN,
                initial: _ft - _ft0,
                width: half,
                rowHeight: S.x8 + S.x1 - S.hair,
                squeeze: 1.56,
                on: OB.measure,
                off: OB.measure,
                label: (i) => '${_ft0 + i} ft',
                onChanged: (i) => _setFeet(_ft0 + i, _in),
              ),
              SetupWheel(
                key: const ValueKey('in'),
                count: 12,
                initial: _in,
                width: half,
                rowHeight: S.x8 + S.x1 - S.hair,
                squeeze: 1.56,
                on: OB.measure,
                off: OB.measure,
                label: (i) => '$i in',
                onChanged: (i) => _setFeet(_ft, i),
              ),
            ] else
              SetupWheel(
                key: const ValueKey('cm'),
                count: _cmN,
                initial: _cm.round() - _cm0,
                width: bandW,
                rowHeight: S.x8 + S.x1 - S.hair,
                squeeze: 1.56,
                on: OB.measure,
                off: OB.measure,
                label: (i) => '${_cm0 + i} cm',
                onChanged: (i) => setState(() => _cm = (_cm0 + i).toDouble()),
              ),
            const SizedBox(width: wLeft - hLeft - bandW),
            if (_imperial)
              SetupWheel(
                key: const ValueKey('lb'),
                count: _lbN,
                initial: (_kg / _kgPerLb).round().clamp(_lb0, _lb0 + _lbN - 1) -
                    _lb0,
                width: bandW,
                rowHeight: S.x8 + S.x1 - S.hair,
                squeeze: 1.56,
                on: OB.measure,
                off: OB.measure,
                label: (i) => '${_lb0 + i} lbs',
                onChanged: (i) => setState(() => _kg = (_lb0 + i) * _kgPerLb),
              )
            else
              SetupWheel(
                key: const ValueKey('kg'),
                count: _kgN,
                initial: _kg.round() - _kg0,
                width: bandW,
                rowHeight: S.x8 + S.x1 - S.hair,
                squeeze: 1.56,
                on: OB.measure,
                off: OB.measure,
                label: (i) => '${_kg0 + i} kg',
                onChanged: (i) => setState(() => _kg = (_kg0 + i).toDouble()),
              ),
          ],
        ),
      ],
    );
  }
}

/// Male or female: the two sets of published constants the scores use.
class SexPage extends StatefulWidget {
  final Map<String, dynamic> initial;
  final ValueChanged<Map<String, dynamic>> onDone;
  final VoidCallback? onBack;
  final double progress;
  final String action;

  const SexPage({
    super.key,
    required this.onDone,
    this.initial = const {},
    this.onBack,
    this.progress = 0,
    this.action = 'NEXT',
  });

  @override
  State<SexPage> createState() => _SexPageState();
}

class _SexPageState extends State<SexPage> {
  static const _keys = ['f', 'm'];
  late String? _sex = switch ((widget.initial['sex'] as String?)?.toLowerCase()) {
    'f' || 'female' => 'f',
    'm' || 'male' => 'm',
    _ => null,
  };

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final chosen = _keys.indexOf(_sex ?? '');
    return SetupFrame(
      picture: const ClipboardPicture(),
      pictureTop: S.x16 + S.x8 - S.x1 + S.hair,
      title: 'Choose Your Sex',
      body: 'Calories and strain are scored against the published values '
          'for each.',
      progress: widget.progress,
      action: widget.action,
      onBack: widget.onBack,
      onNext: _sex == null ? null : () => widget.onDone({'sex': _sex}),
      children: [
        const SizedBox(height: S.x8 + S.x1),
        SetupChoices(
          [
            l?.profileSetupSexFemale ?? 'Female',
            l?.profileSetupSexMale ?? 'Male',
          ],
          chosen: chosen < 0 ? null : chosen,
          onChoose: (i) => setState(() => _sex = _keys[i]),
        ),
      ],
    );
  }
}

/// "Thu 4 Sep" — a date a person can hold, not an ISO string. Local by
/// construction; the app's day labels are local everywhere.
String formatDay(DateTime d, [AppLocalizations? l]) =>
    l?.localeName.startsWith('ru') == true
    ? localizedDate(d, l!.localeName, pattern: 'EEE d MMM')
    : '${weekdayShortName(d.weekday, l)} ${d.day} ${monthShortName(d.month, l)}';
