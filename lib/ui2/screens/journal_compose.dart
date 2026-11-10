// Journal — the one place a day's self-report is written.
//
// A warm page that cools to char, a strip of days, and one row per question
// the owner chose on the SELECT BEHAVIORS sheet (the pencil). Sizes and
// colours are measured off the reference screenshots; the tokens are `JC` in
// theme.dart.
//
// Every question is a `journal_metric` field, so nothing here is a new
// concept: a yes/no is the habit shape (1 yes, 0 no, nothing unanswered), and
// mood, water, caffeine, alcohol and weight are the fields they always were.
// Ratings are 1–5 and doses are stepped straight off the field spec — the
// ceiling exists so one mis-tap cannot enter forty coffees and dominate every
// correlation that field appears in for months.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/journal_fields.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/display_text.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../state/units_controller.dart';
import '../ui2.dart';
import 'custom_journal_field_sheet.dart';
import 'journal_reminder_sheet.dart';
import 'home_screen.dart'
    show monthName, monthShortName, unitsOf, weekdayShortName;
import 'metric_detail.dart' show detailScaffold;
import 'select_behaviors_sheet.dart';

/// Where the chosen questions are kept, in the order the journal asks them.
const kJournalSelectionPref = 'journal.behaviors';

/// How far back the day strip reaches.
const kJournalStripDays = 30;

class JournalCompose extends StatefulWidget {
  const JournalCompose({super.key, this.date, this.embedded = false});

  /// Living in a tab: no close button, and Done saves and stays.
  final bool embedded;

  /// The day it opens on. Defaults to today's LOCAL label — never a UTC one.
  final String? date;

  @override
  State<JournalCompose> createState() => _JournalComposeState();
}

class _JournalComposeState extends State<JournalCompose> {
  late String _date = widget.date ?? todayLabel();
  final _note = TextEditingController();
  final _strip = ScrollController();

  /// The strip's days, oldest first, ending today.
  late final List<String> _days = _stripDays(_date);

  List<JournalFieldSpec> _specs = const [];
  List<String> _selected = const [];
  Map<String, JournalMetricValue> _values = {};
  Set<String> _tags = {};
  // What [_openDay] read, so a save writes only what the user changed here.
  Map<String, JournalMetricValue> _loadedValues = const {};
  Set<String> _loadedTags = const {};
  String _loadedNote = '';
  final Set<String> _logged = {};
  bool _loading = true;
  bool _saving = false;
  bool _addingField = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    _strip.dispose();
    super.dispose();
  }

  static List<String> _stripDays(String date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final asked = DateTime.tryParse(date) ?? today;
    final back = calendarDaysBetween(asked, today).clamp(0, 3650);
    final n = back + 1 > kJournalStripDays ? back + 1 : kJournalStripDays;
    // Calendar arithmetic, not 24 h steps: a DST day is 23 or 25 hours long.
    return [
      for (var i = n - 1; i >= 0; i--)
        dayLabelOf(DateTime(today.year, today.month, today.day - i)),
    ];
  }

  /// A `getJournal` range that reaches back to [day].
  String _rangeFor(String day) {
    final d = DateTime.tryParse(day);
    if (d == null) return '30d';
    final now = DateTime.now();
    final back = calendarDaysBetween(
      d,
      DateTime(now.year, now.month, now.day),
    ).abs();
    return '${back + 1}d';
  }

  JournalFieldSpec? _spec(String key) => journalFieldSpec(
    key,
    custom: [
      for (final s in _specs)
        if (s.custom) s,
    ],
  );

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    final specs = await repo.getJournalFields();
    final rows = await repo.getJournal(range: _rangeFor(_days.first));
    final logged = <String>{
      for (final r in rows)
        if (((r['tags'] as List?) ?? const []).isNotEmpty ||
            ((r['note'] as String?) ?? '').trim().isNotEmpty)
          '${r['date']}',
    };
    // The dots: only the recent month is asked, so an old day opened from a
    // notification does not cost a query per day in between.
    for (final d in _days.skip(_days.length - kJournalStripDays)) {
      if (logged.contains(d)) continue;
      if ((await repo.getJournalMetrics(d)).isNotEmpty) logged.add(d);
    }
    var selected = _storedSelection();
    if (selected == null) {
      // Never chosen: ask what was logged before, so an update does not hide
      // a question someone answers every day.
      final used = await repo.getJournalMetricFields();
      final tags = {
        for (final r in rows)
          ...((r['tags'] as List?) ?? const []).map((t) => '$t'),
      };
      selected = <String>[
        for (final k in used)
          if (journalFieldSpec(k, custom: specs) != null) k,
        for (final s in specs)
          if (s.custom && !used.contains(s.key)) s.key,
        for (final t in tags)
          if (journalBehaviorForTag(t) case final b? when !used.contains(b.key))
            b.key,
      ];
      if (selected.isEmpty) selected = [...kJournalStarterBehaviors];
    }
    if (!mounted) return;
    setState(() {
      _specs = specs;
      _selected = selected!;
      _logged
        ..clear()
        ..addAll(logged);
    });
    await _openDay(_date);
  }

  List<String>? _storedSelection() {
    final raw = Prefs.getString(kJournalSelectionPref, '');
    if (raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is List) return [for (final k in j) '$k'];
    } catch (_) {
      /* a broken pref reads as never chosen */
    }
    return null;
  }

  Future<void> _openDay(String day) async {
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    final values = await repo.getJournalMetrics(day);
    Map<String, dynamic>? row;
    for (final e in await repo.getJournal(range: _rangeFor(day))) {
      if (e['date'] == day) row = e;
    }
    if (!mounted) return;
    setState(() {
      _date = day;
      _values = {...values};
      _loadedValues = {...values};
      _tags = {...?(row?['tags'] as List?)?.map((t) => t.toString())};
      _loadedTags = {..._tags};
      _note.text = (row?['note'] as String?) ?? '';
      _loadedNote = _note.text;
      _loading = false;
    });
  }

  bool get _dirty {
    if (_note.text.trim() != _loadedNote.trim()) return true;
    if (_tags.length != _loadedTags.length || !_tags.containsAll(_loadedTags)) {
      return true;
    }
    for (final k in {..._values.keys, ..._loadedValues.keys}) {
      if (_values[k] != _loadedValues[k]) return true;
    }
    return false;
  }

  void _set(String key, double? v) {
    setState(() {
      if (v == null) {
        _values.remove(key);
      } else {
        _values[key] = JournalMetricValue(
          v,
          atMinuteOfDay: _values[key]?.atMinuteOfDay,
        );
      }
    });
  }

  /// A yes/no answer. Null takes it back to unanswered. A question that a
  /// preset tag used to answer keeps that tag in step, so the tag's history and
  /// everything that reads tags carry on.
  void _answer(String key, bool? yes) {
    final tag = kJournalBehaviorsByKey[key]?.tag;
    _set(key, yes == null ? null : (yes ? 1 : 0));
    if (tag == null) return;
    setState(() => yes == true ? _tags.add(tag) : _tags.remove(tag));
  }

  bool? _yesNoOf(String key) {
    final v = _values[key];
    if (v != null) return v.value >= 1;
    final tag = kJournalBehaviorsByKey[key]?.tag;
    return tag != null && _tags.contains(tag) ? true : null;
  }

  /// MT-06 — when the LAST one landed. Only offered once a dose exists: a time
  /// with no dose is not a fact about anything.
  Future<void> _setTime(String key) async {
    final cur = _values[key];
    if (cur == null) return;
    final l = AppLocalizations.of(context);
    final at = await pickTime(
      context,
      initial: cur.atMinuteOfDay == null
          ? TimeOfDay.now()
          : TimeOfDay(
              hour: cur.atMinuteOfDay! ~/ 60,
              minute: cur.atMinuteOfDay! % 60,
            ),
      title: l?.journalComposeWhenWasLastOne ?? 'When was the last one?',
    );
    if (at == null || !mounted) return;
    setState(() {
      _values[key] = JournalMetricValue(
        cur.value,
        atMinuteOfDay: at.hour * 60 + at.minute,
      );
    });
  }

  /// #273 — define + persist a user-written question. Returns it, or null when
  /// the sheet was closed or the write failed (which says so).
  Future<JournalFieldSpec?> _writeOwn(BuildContext from) async {
    if (_addingField) return null;
    final spec = await showCustomJournalFieldSheet(
      from,
      existingKeys: {
        for (final f in _specs) f.key,
        for (final b in kJournalBehaviors) b.key,
      },
    );
    if (spec == null || !mounted) return null;
    final repo = context.read<AppState>().repo;
    final l = AppLocalizations.of(context);
    // No repo means the sheet should never have been reachable; say so rather
    // than eating the tap.
    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l?.journalComposeNotReady ?? 'Not ready yet — open the app first.',
          ),
        ),
      );
      return null;
    }
    setState(() => _addingField = true);
    try {
      try {
        await repo.postCustomJournalField(spec);
      } catch (_) {
        if (!mounted) return null;
        // A failed persist must not read as success — the question would
        // vanish while the user believes it saved.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l?.journalComposeSaveFailed ??
                  'Could not save it — check storage and retry.',
            ),
          ),
        );
        return null;
      }
      final specs = await repo.getJournalFields();
      if (mounted) setState(() => _specs = specs);
      return spec;
    } finally {
      // Every exit, or one failed save disables the entry for the session.
      if (mounted) setState(() => _addingField = false);
    }
  }

  Future<void> _edit() async {
    final next = await openSelectBehaviors(
      context,
      selected: _selected,
      custom: [
        for (final s in _specs)
          if (s.custom) s,
      ],
      onWriteOwn: _writeOwn,
    );
    if (next == null || !mounted) return;
    Prefs.setString(kJournalSelectionPref, jsonEncode(next));
    setState(() => _selected = next);
  }

  /// Writes the open day. Both writes REPLACE the day, and the strap's
  /// double-tap (a glass of water, a moment tag) writes the same day while this
  /// screen is open, so the day is re-read and only this screen's own edits are
  /// laid over it — never the snapshot from when it opened.
  Future<void> _persist() async {
    final repo = context.read<AppState>().repo;
    if (repo == null || !_dirty) return;
    final metrics = {...await repo.getJournalMetrics(_date)};
    for (final k in {..._loadedValues.keys, ..._values.keys}) {
      final v = _values[k];
      if (v == _loadedValues[k]) continue;
      if (v == null) {
        metrics.remove(k);
      } else {
        metrics[k] = v;
      }
    }
    await repo.postJournalMetrics(_date, metrics);
    final tags = <String>{};
    for (final e in await repo.getJournal(range: _rangeFor(_date))) {
      if (e['date'] == _date) {
        tags.addAll(
          ((e['tags'] as List?) ?? const []).map((t) => t.toString()),
        );
      }
    }
    tags
      ..removeAll(_loadedTags.difference(_tags))
      ..addAll(_tags);
    await repo.postJournal(_date, tags.toList(), _note.text.trim());
    final logged =
        metrics.isNotEmpty || tags.isNotEmpty || _note.text.trim().isNotEmpty;
    _loadedValues = {..._values};
    _loadedTags = {..._tags};
    _loadedNote = _note.text;
    if (mounted) {
      setState(() => logged ? _logged.add(_date) : _logged.remove(_date));
    }
  }

  /// Another day: the one being left is written first, the way DONE writes it.
  Future<void> _goTo(String day) async {
    if (day == _date || _saving) return;
    setState(() => _saving = true);
    try {
      await _persist();
      if (!mounted) return;
      await _openDay(day);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _done() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _persist();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    // Today's "How was today?" is already armed; a rated day moves it to
    // tomorrow, and only a re-arm does that.
    unawaited(context.read<AppState>().refreshAiReminders());
    if (widget.embedded) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Saved')));
      return;
    }
    Navigator.of(context).pop(true);
  }

  /// The questions on the page: the chosen ones in their order, then anything
  /// the day already holds an answer to, so nothing logged is ever hidden.
  List<String> get _rows {
    final out = <String>[
      for (final k in _selected)
        if (_spec(k) != null) k,
    ];
    for (final k in _values.keys) {
      if (!out.contains(k) && _spec(k) != null) out.add(k);
    }
    for (final t in _tags) {
      final b = journalBehaviorForTag(t);
      if (b != null && !out.contains(b.key)) out.add(b.key);
    }
    return out;
  }

  String _question(BuildContext c, String key, JournalFieldSpec spec) {
    final b = kJournalBehaviorsByKey[key];
    if (b != null) return uiText(c, b.question);
    return JournalBehavior.custom(spec).question;
  }

  Widget _row(BuildContext c, String key) {
    final spec = _spec(key)!;
    final q = _question(c, key, spec);
    if (key == 'weight_kg') {
      return _WeightRow(
        question: q,
        kg: _values[key]?.value,
        onChanged: (v) => _set(key, v),
      );
    }
    if (spec.isYesNo) {
      return JournalYesNoRow(
        question: q,
        value: _yesNoOf(key),
        onChanged: (v) => _answer(key, v),
      );
    }
    if (spec.isRating) {
      return JournalRatingRow(
        question: q,
        max: spec.max.round(),
        value: _values[key]?.value.round(),
        onChanged: (v) => _set(key, v?.toDouble()),
      );
    }
    return JournalAmountRow(
      question: q,
      spec: spec,
      value: _values[key]?.value,
      atMin: _values[key]?.atMinuteOfDay,
      onChanged: (v) => _set(key, v),
      onTime: spec.hasTime ? () => _setTime(key) : null,
    );
  }

  String _dayLabel(AppLocalizations? l, String day) {
    final d = DateTime.parse(day);
    final today = todayLabel();
    if (day == today) return uiText(context, 'TODAY');
    if (_days.length > 1 && day == _days[_days.length - 2]) {
      return uiText(context, 'YESTERDAY');
    }
    return '${weekdayShortName(d.weekday, l)}, '
            '${monthShortName(d.month, l)} ${d.day}'
        .toUpperCase();
  }

  String _heading(AppLocalizations? l) {
    final d = DateTime.parse(_date);
    final when = '${monthName(d.month, l)} ${d.day}';
    if (_date == todayLabel()) {
      return uiText(context, "What's happening today, $when?");
    }
    if (_days.length > 1 && _date == _days[_days.length - 2]) {
      return uiText(context, 'What happened yesterday, $when?');
    }
    return uiText(
      context,
      'What happened on ${_kWeekdays[d.weekday - 1]}, $when?',
    );
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final top = MediaQuery.paddingOf(c).top;
    final at = _days.indexOf(_date);
    return AlwaysChar(
      child: Scaffold(
        backgroundColor: JC.foot,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: JC.pageColors,
              stops: JC.pageStops,
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: top),
              _Header(
                title: uiText(c, 'JOURNAL'),
                onClose: widget.embedded ? null : () => Navigator.of(c).pop(),
                onEdit: _loading ? null : () => unawaited(_edit()),
                onBell: () => unawaited(showJournalReminderSheet(c)),
              ),
              // Only the top bar stays put. The day pager and the strip of
              // day pills scroll away with the questions, so a long list gets
              // the whole screen once it is under way.
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: S.x1 + S.half + S.hair / 2),
                    _Pager(
                      label: _dayLabel(l, _date),
                      onOlder:
                          at > 0 ? () => unawaited(_goTo(_days[at - 1])) : null,
                      onNewer: at >= 0 && at < _days.length - 1
                          ? () => unawaited(_goTo(_days[at + 1]))
                          : null,
                    ),
                    const SizedBox(height: S.x2 + S.half),
                    SizedBox(
                      height: JC.pillH,
                      child: ListView.separated(
                        controller: _strip,
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        padding: const EdgeInsets.only(
                          left: S.x2,
                          right: JC.gutter + S.half / 4,
                        ),
                        itemCount: _days.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: JC.pillGap),
                        itemBuilder: (_, i) {
                          final day = _days[_days.length - 1 - i];
                          final d = DateTime.parse(day);
                          return JournalDayPill(
                            weekday: weekdayShortName(d.weekday, l),
                            date: '${d.day}',
                            chosen: day == _date,
                            logged: _logged.contains(day),
                            onTap: () => unawaited(_goTo(day)),
                          );
                        },
                      ),
                    ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(top: S.x16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          JC.gutter,
                          S.x6 + S.half,
                          JC.gutter,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                          Text(
                            _heading(l),
                            style: JC.heading.copyWith(color: JC.ink),
                          ),
                          const SizedBox(height: S.x8),
                          JournalSectionLabel(uiText(c, 'BEHAVIORS')),
                          const SizedBox(height: S.x3 + S.hair),
                          for (final k in _rows) ...[
                            _row(c, k),
                            const SizedBox(height: JC.rowGap),
                          ],
                          if (_rows.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: S.x4),
                              child: Text(
                                uiText(
                                  c,
                                  'Nothing chosen yet. Tap the pencil to pick what to log.',
                                ),
                                style: JC.sub.copyWith(color: JC.label),
                              ),
                            ),
                          const SizedBox(height: S.x5),
                          JournalSectionLabel(uiText(c, 'NOTES')),
                          const SizedBox(height: S.x3 + S.hair),
                          _NoteCard(
                            controller: _note,
                            label:
                                l?.journalComposeAnythingElseLabel ??
                                'Anything else',
                            hint:
                                l?.journalComposeAnythingElseHint ??
                                'A line about the day.',
                          ),
                          const SizedBox(height: S.x4),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: JC.listFoot),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: JC.gutter + S.x2 + S.hair,
                ),
                child: JournalPillButton(
                  label: _saving
                      ? (l?.journalComposeSavingLabel ?? 'Saving').toUpperCase()
                      : uiText(c, 'DONE'),
                  onTap: _saving || _loading ? null : () => unawaited(_done()),
                ),
              ),
              const SizedBox(height: JC.doneFoot),
            ],
          ),
        ),
      ),
    );
  }
}

const _kWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// ✕ on the left, the title in the middle, the pencil on the right.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onClose,
    this.onEdit,
    this.onBell,
  });
  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onBell;

  @override
  Widget build(BuildContext c) => SizedBox(
    height: JC.header,
    width: double.infinity,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Text(title, style: JC.title.copyWith(color: JC.ink)),
        if (onClose != null) Positioned(
          left: S.x2 + S.half,
          width: S.x12,
          height: S.x12,
          child: Pressable(
            semanticLabel: uiText(c, 'Close'),
            onTap: onClose,
            child: const SizedBox(
              width: S.x12,
              height: S.x12,
              child: Icon(LucideIcons.xThin, size: JC.closeIcon, color: JC.ink),
            ),
          ),
        ),
        Positioned(
          right: S.x12,
          width: S.x12,
          height: S.x12,
          child: Pressable(
            semanticLabel: uiText(c, 'Journal reminders'),
            onTap: onBell,
            child: const SizedBox(
              width: S.x12,
              height: S.x12,
              child: Icon(LucideIcons.bell, size: JC.editIcon, color: JC.ink),
            ),
          ),
        ),
        Positioned(
          right: S.x2 + S.hair,
          width: S.x12,
          height: S.x12,
          child: Pressable(
            semanticLabel: uiText(c, 'Choose what to log'),
            onTap: onEdit,
            child: const SizedBox(
              width: S.x12,
              height: S.x12,
              child: Icon(
                LucideIcons.pencilThin,
                size: JC.editIcon,
                color: JC.ink,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// `‹ TODAY ›`. A dead end draws its chevron dim.
class _Pager extends StatelessWidget {
  const _Pager({required this.label, this.onOlder, this.onNewer});
  final String label;
  final VoidCallback? onOlder, onNewer;

  @override
  Widget build(BuildContext c) {
    Widget chevron(IconData icon, VoidCallback? onTap, String what) =>
        Pressable(
          semanticLabel: uiText(c, what),
          onTap: onTap,
          child: Icon(icon, size: I.lg, color: onTap == null ? JC.dim : JC.ink),
        );
    return SizedBox(
      height: S.tap,
      width: S.x16 * 2 + S.x12 + S.x4 + S.x1 + S.hair,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: chevron(LucideIcons.chevronLeft, onOlder, 'Previous day'),
          ),
          Text(label, style: JC.day.copyWith(color: JC.ink)),
          Align(
            alignment: Alignment.centerRight,
            child: chevron(LucideIcons.chevronRight, onNewer, 'Next day'),
          ),
        ],
      ),
    );
  }
}

/// One day in the strip: weekday, date and a dot that fills once the day has
/// anything logged. The chosen day wears a white rim.
class JournalDayPill extends StatelessWidget {
  const JournalDayPill({
    super.key,
    required this.weekday,
    required this.date,
    required this.chosen,
    required this.logged,
    this.onTap,
  });

  final String weekday, date;
  final bool chosen, logged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) => Pressable(
    semanticLabel: '$weekday $date',
    onTap: onTap,
    child: Container(
      width: JC.pillW,
      height: JC.pillH,
      decoration: const BoxDecoration(color: JC.pill, borderRadius: R.rPill),
      // Drawn over, not inset: a rim that took layout would nudge the
      // chosen day's text off its neighbours' line.
      foregroundDecoration: chosen
          ? BoxDecoration(
              borderRadius: R.rPill,
              border: Border.all(color: JC.ink, width: JC.pillRim),
            )
          : null,
      child: Column(
        children: [
          const SizedBox(height: S.x3 + S.half / 4),
          // A fixed capsule: large text shrinks to fit it rather than spill.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(weekday, style: JC.pillDay.copyWith(color: JC.ink)),
                  const SizedBox(height: S.x1 / 2),
                  Text(date, style: JC.pillDate.copyWith(color: JC.ink)),
                ],
              ),
            ),
          ),
          const SizedBox(height: S.x1),
          Container(
            width: JC.pillDot,
            height: JC.pillDot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: logged ? JC.dotLogged : JC.dot,
            ),
          ),
          const SizedBox(height: S.x3 - S.hair / 2),
        ],
      ),
    ),
  );
}

/// BEHAVIORS ──────────── : the label, then a hairline to the edge.
class JournalSectionLabel extends StatelessWidget {
  const JournalSectionLabel(this.text, {super.key, this.color = JC.label});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext c) => Semantics(
    header: true,
    child: Row(
      children: [
        Text(text, style: JC.sectionText.copyWith(color: color)),
        const SizedBox(width: S.x2 + S.half),
        const Expanded(
          child: Divider(height: S.hair, thickness: S.hair, color: JC.hairline),
        ),
      ],
    ),
  );
}

/// The row card every question sits on.
class _RowCard extends StatelessWidget {
  const _RowCard({required this.child, this.vertical = 0});
  final Widget child;
  final double vertical;

  @override
  Widget build(BuildContext c) => Container(
    constraints: const BoxConstraints(minHeight: JC.rowH),
    padding: EdgeInsets.fromLTRB(
      JC.rowPad,
      vertical,
      JC.rowPad - (S.tap - JC.answer) / 2,
      vertical,
    ),
    decoration: const BoxDecoration(color: JC.card, borderRadius: JC.rRow),
    alignment: Alignment.centerLeft,
    child: child,
  );
}

/// One square answer button: a tenth of white, or white with a dark glyph
/// when it is the chosen answer.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.label,
    required this.chosen,
    required this.onTap,
    this.icon,
    this.text,
    this.width = JC.answer,
  });

  final String label;
  final bool chosen;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? text;
  final double width;

  @override
  Widget build(BuildContext c) {
    final ink = chosen ? JC.onChosen : (onTap == null ? JC.dim : JC.ink);
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: motion(c, Motion.fast),
        width: width,
        height: JC.answer,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: chosen ? JC.chosen : JC.button,
          borderRadius: JC.rAnswer,
        ),
        child: icon != null
            ? Icon(icon, size: I.sm, color: ink)
            : Text(text ?? '', style: JC.value.copyWith(color: ink)),
      ),
    );
  }
}

/// A yes/no question: the question, then ✕ and ✓. Tapping the chosen answer
/// again takes it back to unanswered — a mis-tap is never permanent.
class JournalYesNoRow extends StatelessWidget {
  const JournalYesNoRow({
    super.key,
    required this.question,
    required this.value,
    required this.onChanged,
  });

  final String question;

  /// Null is unanswered, which is not the same as no.
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext c) => _RowCard(
    child: Row(
      children: [
        Expanded(
          child: Text(question, style: JC.row.copyWith(color: JC.ink)),
        ),
        const SizedBox(width: S.x2),
        _Answer(
          label: uiText(c, 'No'),
          icon: LucideIcons.xHeavy,
          chosen: value == false,
          onTap: () => onChanged(value == false ? null : false),
        ),
        const SizedBox(width: S.hair),
        _Answer(
          label: uiText(c, 'Yes'),
          icon: LucideIcons.checkBold,
          chosen: value == true,
          onTap: () => onChanged(value == true ? null : true),
        ),
      ],
    ),
  );
}

/// A 1–5 self-report: the question, then one square per step. Five, not ten:
/// a ten-point self-report is not ten distinguishable states. Tapping the
/// chosen step again clears it.
class JournalRatingRow extends StatelessWidget {
  const JournalRatingRow({
    super.key,
    required this.question,
    required this.value,
    required this.onChanged,
    this.max = 5,
  });

  final String question;
  final int? value;
  final int max;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext c) => _RowCard(
    vertical: S.x3 + S.hair,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(question, style: JC.row.copyWith(color: JC.ink)),
        const SizedBox(height: S.x2),
        LayoutBuilder(
          builder: (c, box) {
            final n = max.clamp(1, 10);
            // The card's right padding leaves room for a 44 pt target's
            // slop; a square this wide is its own target, so the row stops
            // at the visual edge, with 8 pt of air between squares.
            final w =
                (box.maxWidth - (S.tap - JC.answer) / 2 - S.x2 * (n - 1)) / n;
            return Row(
              children: [
                for (var i = 1; i <= n; i++) ...[
                  if (i > 1) const SizedBox(width: S.x2),
                  _Answer(
                    label: value == i
                        ? '$i of $n, selected. Activate to clear.'
                        : '$i of $n',
                    text: '$i',
                    width: w,
                    chosen: value == i,
                    onTap: () => onChanged(value == i ? null : i),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

/// A dose or a duration: the question and what is logged, then − and +. Null
/// is NOT zero: "no caffeine today" is a logged zero, "did not say" is an
/// absence, and the step down from zero is back to absence.
class JournalAmountRow extends StatelessWidget {
  const JournalAmountRow({
    super.key,
    required this.question,
    required this.spec,
    required this.value,
    required this.onChanged,
    this.atMin,
    this.onTime,
  });

  final String question;
  final JournalFieldSpec spec;
  final double? value;
  final ValueChanged<double?> onChanged;

  /// The LAST occurrence, in local minutes past midnight. Null = not said.
  final int? atMin;

  /// Non-null on a field whose spec says timing matters; offered once a dose
  /// exists — an hour on its own is not a measurement.
  final VoidCallback? onTime;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final v = value;
    final unit = spec.custom ? spec.unit : uiText(c, spec.unit);
    final amount = v == null
        ? (l?.journalComposeNotLogged ?? 'Not logged')
        : (unit.isEmpty ? spec.format(v) : '${spec.format(v)} $unit');
    return _RowCard(
      vertical: S.x2 + S.half,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(question, style: JC.row.copyWith(color: JC.ink)),
                const SizedBox(height: S.half),
                Text(amount, style: JC.sub.copyWith(color: JC.label)),
                if (v != null && v > 0 && onTime != null)
                  Pressable(
                    semanticLabel:
                        l?.journalComposeWhenWasLastField(question) ??
                        'When was the last one',
                    onTap: onTime,
                    child: Text(
                      atMin == null
                          ? (l?.journalComposeAddTimeOfLastOne ??
                                'Add the time of the last one')
                          : (l?.journalComposeLastAt(
                                  formatMinuteOfDay(atMin!),
                                ) ??
                                'Last at ${formatMinuteOfDay(atMin!)}'),
                      style: JC.sub.copyWith(color: JC.box),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: S.x2),
          _Answer(
            label: l?.journalComposeDecrease ?? 'Decrease',
            icon: LucideIcons.minusBold,
            chosen: false,
            // Enabled AT zero on purpose: zero is a logged "none today" and the
            // step down from it is back to absence.
            onTap: v == null
                ? null
                : () {
                    final next = v - spec.step;
                    onChanged(next <= 0 ? (v == 0 ? null : 0) : next);
                  },
          ),
          const SizedBox(width: S.hair),
          _Answer(
            label: l?.journalComposeIncrease ?? 'Increase',
            icon: LucideIcons.plusBold,
            chosen: false,
            onTap: v != null && v >= spec.max
                ? null
                : () => onChanged(
                    ((v ?? 0) + spec.step).clamp(0, spec.max).toDouble(),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The note, on a row card.
class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.controller,
    required this.label,
    required this.hint,
  });
  final TextEditingController controller;
  final String label, hint;

  @override
  Widget build(BuildContext c) => Container(
    constraints: const BoxConstraints(minHeight: JC.rowH),
    padding: const EdgeInsets.symmetric(
      horizontal: JC.rowPad,
      vertical: S.x4 + S.half,
    ),
    decoration: const BoxDecoration(color: JC.card, borderRadius: JC.rRow),
    child: AppField(
      controller: controller,
      semanticLabel: label,
      hint: hint,
      maxLines: 4,
      minLines: 1,
      bare: true,
      textStyle: JC.row,
    ),
  );
}

/// The white pill at the foot: DONE here, SAVE BEHAVIORS on the sheet.
class JournalPillButton extends StatelessWidget {
  const JournalPillButton({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) => Pressable(
    onTap: onTap,
    child: Container(
      height: JC.doneH,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onTap == null ? JC.dotLogged : JC.chosen,
        borderRadius: R.rPill,
      ),
      child: Text(label, style: JC.title.copyWith(color: JC.onChosen)),
    ),
  );
}

/// The app's one text input. Lives here rather than in `grammar.dart` because
/// exactly two screens type into anything — a journal note and a medication
/// name.
class OsTextField extends StatelessWidget {
  const OsTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '',
    this.lines = 1,
    this.keyboard,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int lines;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
          // The label is drawn as a sibling `Text`, which a screen reader reads
          // on the way past and then forgets. Focused, the field itself
          // announced only its HINT — and the hint disappears the moment the
          // user types, leaving "text field" with no way to ask what it is for.
          child: Semantics(
            label: label,
            textField: true,
            child: AppField(
              controller: controller,
              maxLines: lines,
              minLines: 1,
              keyboardType: keyboard,
              bare: true,
              hint: hint,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════ MT-03 · WEIGHT ══════════════════════════
//
// The most eating-disorder-adjacent surface in the app, and it is built to
// EMIT NOTHING. Read the ceiling before adding anything here:
//
//   · ENTERED, never measured, and labelled that way everywhere it appears.
//   · The seven-day EWMA trend is what gets drawn — never the raw readings.
//     Day-to-day scale noise is water and glycogen at ±1-2 kg, and a raw line
//     makes that read as change that happened to a body.
//   · Gaps stay gaps. Nothing is interpolated across a fortnight nobody
//     weighed.
//   · NO goal weight. NO daily prompt. NO red/green. NO arrow, no delta, no
//     "you gained" anything, no notification, ever. No body fat, no lean mass,
//     no metabolic age.
//   · It lives here, where it is entered, and nowhere else. It is on no
//     dashboard and in no summary, because a number that greets you is a
//     number that asks you for something.
//
// BMR still reads the onboarding scalar. Changing the BMR input recomputes
// every historical calorie number in the app, so it lands on its own commit
// where a regression is attributable.

/// How much history the trend screen reads. Long enough for a real four-week
/// change to be visible with a season either side of it.
const int kWeightTrendDays = 180;

/// One journal row, typed rather than stepped, plus the way into the trend.
/// One journal row, typed rather than stepped, plus the way into the trend.
class _WeightRow extends StatelessWidget {
  const _WeightRow({
    required this.question,
    required this.kg,
    required this.onChanged,
  });

  final String question;

  /// Today's entry in kilograms, or null when nothing was entered. Null is not
  /// zero and it is not a missed target — it is a day she did not weigh.
  final double? kg;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final u = unitsOf(c);
    final v = kg;
    return _RowCard(
      vertical: S.x2 + S.half,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(question, style: JC.row.copyWith(color: JC.ink)),
                const SizedBox(height: S.half),
                Text(
                  v == null
                      ? (l?.journalComposeNotEntered ?? 'Not entered')
                      : (l?.journalComposeEnteredNotMeasured(
                              u == null
                                  ? '${v.toStringAsFixed(1)} kg'
                                  : u.weight(v),
                            ) ??
                            '${u == null ? '${v.toStringAsFixed(1)} kg' : u.weight(v)} · entered, not measured'),
                  style: JC.sub.copyWith(color: JC.label),
                ),
                Pressable(
                  semanticLabel:
                      l?.journalComposeSeeWeightTrend ?? 'See the weight trend',
                  onTap: () => Navigator.of(c).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _WeightTrend(),
                    ),
                  ),
                  child: Text(
                    l?.journalComposeSeeTheTrend ?? 'See the trend',
                    style: JC.sub.copyWith(color: JC.box),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: S.x2),
          _Answer(
            label: l?.journalComposeEnterWeight ?? 'Enter weight',
            text: v == null
                ? (l?.journalComposeEnter ?? 'Enter')
                : (l?.journalComposeChange ?? 'Change'),
            width: S.x16 + S.x4 + S.x1,
            chosen: false,
            onTap: () async {
              final next = await _askWeight(c, u, v);
              if (next != null) onChanged(next.value);
            },
          ),
        ],
      ),
    );
  }

  /// The typed entry. Returns a box holding the new value (null inside it means
  /// "clear today's entry"), or null when she backed out — the two are
  /// different answers and collapsing them would make clearing impossible.
  static Future<({double? value})?> _askWeight(
    BuildContext c,
    UnitsController? u,
    double? kg,
  ) {
    final imperial = u?.isImperial ?? false;
    final ctrl = TextEditingController(text: u?.weightField(kg) ?? '');
    final l = AppLocalizations.of(c);
    return showDialog<({double? value})>(
      context: c,
      builder: (dc) => AppDialog(
        title: l?.journalComposeWeightToday ?? 'Weight today',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OsTextField(
              controller: ctrl,
              label: u == null
                  ? (l?.journalComposeWeightKgLabel ?? 'Weight (kg)')
                  : uiText(dc, u.weightLabel),
              hint: imperial ? '154' : '70.0',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: S.x3),
            Text(
              l?.journalComposeWeightScaleNote ??
                  'What you or your scale read. The band does not measure this.',
              style: F.over.copyWith(color: P.of(dc).ink3, height: 1.4),
            ),
          ],
        ),
        actions: [
          if (kg != null)
            BigButton(
              l?.journalComposeClear ?? 'Clear',
              soft: true,
              onTap: () => Navigator.of(dc).pop((value: null)),
            ),
          BigButton(
            l?.actionCancel ?? 'Cancel',
            soft: true,
            onTap: () => Navigator.of(dc).pop(),
          ),
          BigButton(
            l?.actionSave ?? 'Save',
            onTap: () {
              // A typo is not a blank. Nothing is saved from an unreadable
              // field, and the form says which one rather than storing a hole.
              if (Typed.of(ctrl.text).bad) {
                sayUnreadable(dc, [
                  u == null
                      ? (l?.journalComposeWeightLabel ?? 'Weight')
                      : uiText(dc, u.weightLabel),
                ]);
                return;
              }
              final kgIn = u == null
                  ? Typed.of(ctrl.text).value
                  : u.weightToKg(ctrl.text);
              Navigator.of(dc).pop((value: kgIn));
            },
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }
}

/// The trend, and only the trend.
///
/// One line, no headline number, no delta, no arrow, no target and no colour
/// that means good or bad. If a future change wants to add any of those, the
/// answer is in the ceiling at the top of this section.
class _WeightTrend extends StatefulWidget {
  const _WeightTrend();

  @override
  State<_WeightTrend> createState() => _WeightTrendState();
}

class _WeightTrendState extends State<_WeightTrend> {
  Map<String, double> _byDay = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      // Day arithmetic, not a subtracted duration: a DST day is 23 or 25 hours
      // long and `now - 180 days` lands on the wrong calendar date across one.
      final now = DateTime.now();
      final since = dayLabelOf(
        DateTime(now.year, now.month, now.day - (kWeightTrendDays - 1)),
      );
      final rows = await LocalDb.journalMetricsByDay(sinceDaysEpoch: since);
      if (!mounted) return;
      setState(() {
        _byDay = {
          for (final e in rows.entries)
            // The `when` does real work — a non-finite or non-positive weight
            // is not a weight — and the null-aware element form has nowhere to
            // put a guard.
            // ignore: use_null_aware_elements
            if (e.value['weight_kg']?.value case final v?
                when v.isFinite && v > 0)
              e.key: v,
        };
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final title = l?.journalComposeWeightLabel ?? 'Weight';
    if (_loading) {
      return detailScaffold(c, title, const [
        SizedBox(height: S.x8),
        Center(child: CircularProgressIndicator()),
      ]);
    }
    final p = P.of(c);
    final u = unitsOf(c);
    final trend = weightTrendEwma(_byDay);
    if (trend.length < 2) {
      return detailScaffold(c, title, [
        const SizedBox(height: S.x2),
        StatusCard(
          l?.journalComposeNotEnoughEntriesTitle ??
              'Not enough entries for a trend',
          l?.journalComposeNotEnoughEntriesBody ??
              'The line is a seven-day average through what you entered, so it '
                  'needs at least two days. Nothing is filled in between them.',
          icon: LucideIcons.scale,
        ),
      ]);
    }

    // Indexed by CALENDAR DAY, never compacted: a fortnight nobody weighed is a
    // hole in the line, and compacting would draw a straight, confident segment
    // across it.
    final days = trend.keys.toList()..sort();
    final first = DateTime.parse(days.first);
    final span = calendarDaysBetween(first, DateTime.parse(days.last));
    // The controller owns every conversion; this only asks it for the number
    // rather than the sentence, because an axis cannot print "72.4 kg".
    double show(double kg) =>
        u == null ? kg : (double.tryParse(u.weightField(kg)) ?? kg);
    // NOT null-aware: a null here is a day she did not weigh, and dropping it
    // would compact the series and draw a confident straight segment across
    // the gap. The holes are the point.
    final vals = <double?>[
      for (var i = 0; i <= span; i++) _at(trend, first, i, show),
    ];
    final present = <double>[for (final v in vals) ?v];
    final axis = AxisSpec.of(present, format: axisFixed);

    return detailScaffold(c, title, [
      const SizedBox(height: S.x2),
      Surface(
        child: ChartFrame(
          title: l?.journalComposeSevenDayTrend ?? 'Seven-day trend',
          unit: u?.isImperial == true ? 'lb' : 'kg',
          height: 140,
          yAxis: axis,
          xLabels: [days.first, days.last],
          footnote:
              l?.journalComposeTrendFootnote ??
              'Entered by you. Days with no entry are left empty.',
          series: vals,
          empty: axis == null ? const NoData() : null,
          child: axis == null
              ? const SizedBox.shrink()
              // No fill: a filled area under an axis that starts at 68 kg is a
              // truncated axis with the truncation hidden.
              : CustomPaint(
                  size: Size.infinite,
                  painter: LineChart(
                    vals,
                    p.on(C.blue),
                    fill: false,
                    t: animate(c, 1),
                    axis: axis,
                  ),
                ),
        ),
      ),
      const SizedBox(height: S.x4),
      Text(
        l?.journalComposeWeightTrendExplainer(trend.length) ??
            'From you or your scale; the band doesn’t measure weight. The line '
                'is a 7-day average, because water and food alone move a scale '
                '1–2 kg. ${trend.length} '
                '${trend.length == 1 ? 'day' : 'days'} entered.',
        style: F.over.copyWith(color: p.ink3, height: 1.5),
      ),
    ]);
  }

  /// The trend value on one calendar day, or null. Nulls are what draw the gaps
  /// — there is no nearest-neighbour lookup here on purpose.
  double? _at(
    Map<String, double> trend,
    DateTime first,
    int offset,
    double Function(double) show,
  ) {
    // Calendar arithmetic, not a 24 h duration: a DST day is 23 or 25 hours
    // long and adding days as hours slides the whole series by one across one.
    final day = DateTime(first.year, first.month, first.day + offset);
    final v = trend[dayLabelOf(day)];
    return v == null ? null : show(v);
  }
}
