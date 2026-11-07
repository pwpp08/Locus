// Edit Time in Bed: the sheet behind Sleep's EDIT. The night's bed and wake, each
// a date chip and a time chip, where the band was worn, Save and Delete Sleep.
// Sizes measured off the reference recording (see DC).

import 'package:flutter/material.dart';

import '../../data/day_label.dart';
import '../../l10n/app_localizations.dart';
import '../../state/prefs.dart';
import '../ui2.dart';
import 'dial_parts.dart';
import 'home/home_data.dart' show clockOfTs;
import 'home_screen.dart' show monthShortName;

/// What the sheet closed with. Null: closed without a change.
sealed class EditTimeResult {
  const EditTimeResult();
}

class EditTimeSaved extends EditTimeResult {
  final DateTime start, end;
  const EditTimeSaved(this.start, this.end);
}

class EditTimeDeleted extends EditTimeResult {
  const EditTimeDeleted();
}

/// Where the band can be worn. Stored per night, read by nothing yet but this
/// sheet: the place it was worn is the user's note on the night.
const kWearLocations = ['Wrist', 'Bicep', 'Chest', 'Calf', 'Other'];

/// The Prefs key for a night's wear location.
String wearLocationKey(String day) => 'wear_location_$day';

Future<EditTimeResult?> openEditTimeInBed(
  BuildContext c, {
  required String day,
  required DateTime start,
  required DateTime end,
}) =>
    AppSheet.open<EditTimeResult>(
      c,
      scroll: true,
      bare: true,
      scrim: DC.scrim,
      builder: (_) => AlwaysChar(
        child: EditTimeInBedSheet(day: day, start: start, end: end),
      ),
    );

class EditTimeInBedSheet extends StatefulWidget {
  final String day;
  final DateTime start, end;
  const EditTimeInBedSheet(
      {super.key, required this.day, required this.start, required this.end});

  @override
  State<EditTimeInBedSheet> createState() => _EditTimeInBedSheetState();
}

class _EditTimeInBedSheetState extends State<EditTimeInBedSheet> {
  late DateTime _start = widget.start, _end = widget.end;
  late String _where = Prefs.getString(wearLocationKey(widget.day), '');

  bool get _valid => _end.isAfter(_start);
  bool get _changed => _start != widget.start || _end != widget.end;

  Future<void> _pickDate(bool bed) async {
    final at = bed ? _start : _end;
    final d = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(at.year - 1),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final next = DateTime(d.year, d.month, d.day, at.hour, at.minute);
    setState(() => bed ? _start = next : _end = next);
  }

  Future<void> _pickClock(bool bed) async {
    final at = bed ? _start : _end;
    final t = await pickTime(context,
        initial: TimeOfDay.fromDateTime(at),
        title: bed ? 'Bed Time' : 'Wake Time');
    if (t == null || !mounted) return;
    final next = DateTime(at.year, at.month, at.day, t.hour, t.minute);
    setState(() => bed ? _start = next : _end = next);
  }

  Future<void> _pickWhere() async {
    final picked = await AppSheet.show<String>(
      context,
      title: 'Where did you wear your band?',
      child: Builder(builder: (sheet) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          for (final w in kWearLocations)
            Pressable(
              onTap: () => Navigator.of(sheet).pop(w),
              child: SizedBox(
                height: S.tap,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(w, style: F.dBody.copyWith(color: P.of(sheet).ink)),
                ),
              ),
            ),
        ]);
      }),
    );
    if (picked == null || !mounted) return;
    setState(() => _where = picked);
    Prefs.setString(wearLocationKey(widget.day), picked);
  }

  String _dateText(DateTime d, AppLocalizations? l) {
    if (dayLabelOf(d) == todayLabel()) return l?.healthToday ?? 'Today';
    return '${monthShortName(d.month, l)} ${d.day}';
  }

  Widget _row(String label, DateTime at, bool bed, AppLocalizations? l) {
    return SizedBox(
      height: S.x12 + S.x1,
      child: Row(children: [
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.dBody.copyWith(color: DC.ink)),
        ),
        Flexible(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _Chip(_dateText(at, l), () => _pickDate(bed)),
                const SizedBox(width: S.x2 + S.hair),
                _Chip(clockOfTs(at.millisecondsSinceEpoch ~/ 1000),
                    () => _pickClock(bed)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final bottom = MediaQuery.paddingOf(c).bottom;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .92),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [DC.sheetTop, DC.sheetFoot],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          kDialMargin, S.x4 + S.half + S.hair, kDialMargin, 0),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: S.x16 + S.x2,
          height: S.x1 + S.hair,
          decoration: const BoxDecoration(color: DC.grab, borderRadius: R.rPill),
        ),
        const SizedBox(height: S.x4 + S.hair),
        SizedBox(
          height: S.x8,
          child: Stack(alignment: Alignment.center, children: [
            Align(
              alignment: Alignment.centerLeft,
              // The ✕ sits nearer the edge than its tap target's centre.
              child: Transform.translate(
                offset: const Offset(-S.x2 - S.half, 0),
                child: Pressable(
                  onTap: () => Navigator.of(c).pop(),
                  semanticLabel: 'Close',
                  child: const Icon(LucideIcons.x, size: I.md, color: DC.ink),
                ),
              ),
            ),
            Text('EDIT TIME IN BED', style: F.dNav.copyWith(color: DC.ink)),
          ]),
        ),
        const SizedBox(height: S.x4),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: S.x12 + S.hair + bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const _SectionRule('TIME'),
              const SizedBox(height: S.x6 + S.half),
              Padding(
                padding: const EdgeInsets.only(left: S.x2 + S.hair),
                child: Column(children: [
                  _row('Bed Time', _start, true, l),
                  _row('Wake Time', _end, false, l),
                ]),
              ),
              const SizedBox(height: S.x6 + S.x1),
              const _SectionRule('LOCATION'),
              const SizedBox(height: S.x8 + S.half),
              Padding(
                padding: const EdgeInsets.only(left: S.x2 + S.hair),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Where did you wear your band?',
                      style: F.dBody.copyWith(color: DC.ink)),
                ),
              ),
              const SizedBox(height: S.x4 + S.half + S.hair),
              Pressable(
                onTap: _pickWhere,
                semanticLabel: 'Where did you wear your band?',
                child: Container(
                  width: double.infinity,
                  height: S.x12 + S.x1,
                  padding: const EdgeInsets.symmetric(horizontal: S.x4 + S.hair),
                  alignment: Alignment.centerLeft,
                  decoration:
                      const BoxDecoration(color: DC.field, borderRadius: R.rLg),
                  child: Text(_where.isEmpty ? '---' : _where,
                      style: F.dBody.copyWith(color: DC.ink)),
                ),
              ),
              const SizedBox(height: S.x16 * 2 + S.x2 + S.hair),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x6 + S.x1),
                child: Column(children: [
                  _Pill(
                    'SAVE',
                    filled: true,
                    onTap: !_valid
                        ? null
                        : () => Navigator.of(c).pop(
                            _changed ? EditTimeSaved(_start, _end) : null),
                  ),
                  const SizedBox(height: S.x4),
                  _Pill('DELETE SLEEP',
                      onTap: () =>
                          Navigator.of(c).pop(const EditTimeDeleted())),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SectionRule extends StatelessWidget {
  final String label;
  const _SectionRule(this.label);

  @override
  Widget build(BuildContext c) {
    return Row(children: [
      Text(label, style: F.dLabel.copyWith(color: DC.ink2)),
      const SizedBox(width: S.x2 + S.hair),
      const Expanded(
          child: Divider(height: S.hair, thickness: S.hair, color: DC.edge)),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Chip(this.label, this.onTap);

  @override
  Widget build(BuildContext c) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: S.x8 + S.half,
        padding: const EdgeInsets.symmetric(horizontal: S.x3 + S.hair),
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: DC.chip, borderRadius: R.rSm),
        child: Text(label, style: F.dText.copyWith(color: DC.ink)),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  const _Pill(this.label, {this.filled = false, this.onTap});

  @override
  Widget build(BuildContext c) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: S.x12 + S.x1,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? DC.pure : const Color(0x00000000),
          borderRadius: R.rXxl,
          border: filled ? null : Border.all(color: DC.ink3, width: S.hair + .2),
        ),
        child: Text(label,
            style: F.dNav.copyWith(color: filled ? DC.well : DC.ink)),
      ),
    );
  }
}
