import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/activity_suggestion.dart';
import '../../compute/manual_session.dart'
    show ManualWindowErrorMessage, ManualWindowException;
import '../../data/local_repository.dart';
import '../activity/catalogue.dart';
import '../ui2.dart';
import 'add_activity.dart';
import 'home_screen.dart';
import 'log_workout.dart' show bumpInsights;
import 'window_editor.dart';

/// The last activity logged that the catalogue can name, or null.
Future<Activity?> recentActivityOf(LocalRepository repo) async {
  for (final s in await repo.getSessions(includeDetected: false)) {
    if (activityByName(s['type']?.toString()) case final a?) return a;
  }
  return null;
}

/// Puts a detected workout's answer on record: saved as that activity, or
/// thrown away. False when it could not be, and the reason has been said.
Future<bool> settleDetected(
  BuildContext c,
  ActivitySuggestion s,
  DetectedAnswer answer,
) async {
  final repo = repoOf(c);
  if (repo == null) return false;
  final messenger = ScaffoldMessenger.maybeOf(c);
  try {
    // The window can have moved as more data arrived since the row was drawn;
    // the store only takes the revision it holds now.
    final latest =
        (await repo.pendingActivities()).where((p) => p.id == s.id).firstOrNull ??
        s;
    final a = answer.activity;
    if (answer.discard || a == null) {
      await repo.discardActivity(latest);
    } else {
      await repo.confirmActivity(latest, workoutType: a.typeKey);
    }
  } on ManualWindowException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.error.message)));
    return false;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    return false;
  }
  if (c.mounted) bumpInsights(c);
  return true;
}

/// A detected workout's row, tapped: what was it? True when it was answered
/// and My Day should read again.
Future<bool> identifyDetected(BuildContext c, ActivitySuggestion s) async {
  final repo = repoOf(c);
  if (repo == null) return false;
  Activity? recent;
  try {
    recent = await recentActivityOf(repo);
  } catch (_) {
    // The list works without its shortcut.
  }
  if (!c.mounted) return false;
  final answer = await chooseDetectedActivity(c, recent: recent);
  if (answer == null || !c.mounted) return false;
  return settleDetected(c, s, answer);
}

/// Where the "Did you work out?" notification lands: the same question as the
/// row in My Day, as a page.
class IdentifyActivityScreen extends StatefulWidget {
  const IdentifyActivityScreen({super.key, this.focusId});

  /// The bout the notification was about; the oldest waiting when it has gone.
  final String? focusId;

  @override
  State<IdentifyActivityScreen> createState() => _IdentifyActivityScreenState();
}

class _IdentifyActivityScreenState extends State<IdentifyActivityScreen> {
  ActivitySuggestion? _s;
  Activity? _recent;
  var _loading = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    ActivitySuggestion? s;
    Activity? recent;
    try {
      final all = [
        for (final p in await repo!.pendingActivities())
          if (p.kind == ActivityKind.workout) p,
      ];
      s = all.where((p) => p.id == widget.focusId).firstOrNull ?? all.firstOrNull;
      recent = await recentActivityOf(repo);
    } catch (_) {
      // Nothing to ask about: the empty state says so.
    }
    if (mounted) {
      setState(() {
        _s = s;
        _recent = recent;
        _loading = false;
      });
    }
  }

  Future<void> _answer(DetectedAnswer answer) async {
    final s = _s;
    if (s == null || _busy) return;
    setState(() => _busy = true);
    final done = await settleDetected(context, s, answer);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    return Scaffold(
      backgroundColor: P.of(c).bg,
      body: SafeArea(
        child: _s != null
            ? ActivityChooser(
                sleep: false,
                note: kDetectedNote,
                recent: _recent,
                onPick: (r) => _answer((activity: r.activity, discard: false)),
                onDiscard: () => _answer((activity: null, discard: true)),
                onBack: () => Navigator.of(c).maybePop(),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: NavBar(l?.activityReviewTitle ?? 'Detected activities'),
                  ),
                  if (_loading)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Padding(
                      padding: pad,
                      child: StatusCard(
                        l?.activityNothing ?? 'Nothing to review',
                        'Activities the band finds will appear in My Day.',
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// The naps the band thinks it saw, for a yes or a no. A detected workout is
/// not reviewed here: it waits in My Day to be named.
class DetectedActivitiesScreen extends StatefulWidget {
  const DetectedActivitiesScreen({super.key, this.focusId});
  final String? focusId;
  @override
  State<DetectedActivitiesScreen> createState() =>
      _DetectedActivitiesScreenState();
}

class _DetectedActivitiesScreenState extends State<DetectedActivitiesScreen>
    with RevisionReload {
  List<ActivitySuggestion>? _items;
  String? _error;
  bool _busy = false;
  final _focusKey = GlobalKey();
  bool _focused = false;
  int _loadRevision = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void reload() {
    if (!_busy) _load();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    try {
      final items = [
        for (final s in await repoOf(context)!.pendingActivities())
          if (s.kind == ActivityKind.nap) s,
      ];
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _items = items;
        _error = null;
      });
      if (!_focused && items.any((s) => s.id == widget.focusId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _focusKey.currentContext;
          if (target != null) {
            _focused = true;
            Scrollable.ensureVisible(target);
          }
        });
      }
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(
          () => _error =
              AppLocalizations.of(context)?.activityLoadFailed ??
              'Could not load activities. Try again.',
        );
      }
    }
  }

  /// Confirms [s] at the window its card shows; the detected one stays null,
  /// so an untouched card confirms exactly as it did before it could be edited.
  Future<void> _confirm(ActivitySuggestion s, int a, int b) => _act(s,
      start: a == s.startTs ? null : a, end: b == s.endTs ? null : b);

  Future<void> _act(
    ActivitySuggestion s, {
    bool discard = false,
    int? start,
    int? end,
  }) async {
    if (_busy) return;
    final repo = repoOf(context);
    if (repo == null) return;
    setState(() => _busy = true);
    String? error;
    try {
      if (discard) {
        await repo.discardActivity(s);
      } else {
        await repo.confirmActivity(s, startTs: start, endTs: end);
      }
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    bumpInsights(context);
    await _load();
    if (mounted && error != null) setState(() => _error = error);
  }

  Future<void> _edit(ActivitySuggestion s) async {
    final result = await editNapWindow(context, s);
    if (result != null && mounted) {
      await _act(s, start: result.$1, end: result.$2);
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final items = _items;
    return Scaffold(
      backgroundColor: P.of(c).bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(l?.activityReviewTitle ?? 'Detected activities'),
            ),
            Expanded(
              child: ListView(
                padding: pad,
                children: [
                  if (_error != null)
                    StatusCard(
                      l?.activityReviewProblem ?? 'Could not finish',
                      _error!,
                      fix: l?.homeTryAgain ?? 'Try again',
                      onFix: _load,
                    ),
                  if (items == null && _error == null)
                    const Center(child: CircularProgressIndicator()),
                  if (_error == null && items != null && items.isEmpty)
                    StatusCard(
                      l?.activityNothing ?? 'Nothing to review',
                      'Possible naps will appear here.',
                    ),
                  if (items != null)
                    for (final s in items)
                      Padding(
                        key: widget.focusId == s.id
                            ? _focusKey
                            : ValueKey(s.id),
                        padding: const EdgeInsets.only(bottom: S.x3),
                        child: ActivityProposalCard(
                          suggestion: s,
                          highlighted: widget.focusId == s.id,
                          onConfirm: _busy ? null : (a, b) => _confirm(s, a, b),
                          onEdit: _busy ? null : () => _edit(s),
                          onDiscard: _busy
                              ? null
                              : () => _act(s, discard: true),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActivityProposalCard extends StatefulWidget {
  const ActivityProposalCard({
    super.key,
    required this.suggestion,
    this.highlighted = false,
    this.onConfirm,
    this.onEdit,
    this.onDiscard,
    this.hr,
  });
  final ActivitySuggestion suggestion;
  final bool highlighted;

  /// Confirms the window as it stands on the card: what the detector found, or
  /// where the person moved its lines to.
  final void Function(int startTs, int endTs)? onConfirm;
  final VoidCallback? onEdit, onDiscard;

  /// Where the preview's heart rate comes from; the band's store when null.
  final HrReader? hr;

  @override
  State<ActivityProposalCard> createState() => _ActivityProposalCardState();
}

class _ActivityProposalCardState extends State<ActivityProposalCard> {
  late int _start = widget.suggestion.startTs, _end = widget.suggestion.endTs;

  @override
  void didUpdateWidget(ActivityProposalCard old) {
    super.didUpdateWidget(old);
    // A different proposal in the same slot starts from its own window.
    if (old.suggestion.id != widget.suggestion.id) {
      _start = widget.suggestion.startTs;
      _end = widget.suggestion.endTs;
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final suggestion = widget.suggestion;
    final start = DateTime.fromMillisecondsSinceEpoch(_start * 1000);
    final end = DateTime.fromMillisecondsSinceEpoch(_end * 1000);
    final material = MaterialLocalizations.of(c);
    String clock(DateTime value) => material.formatTimeOfDay(
        TimeOfDay.fromDateTime(value),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(c));
    // The date once; the end repeats it only when the window crosses midnight.
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    final minutes = math.max(0, (_end - _start) ~/ 60);
    final when = '${material.formatMediumDate(start)} · ${clock(start)} – '
        '${sameDay ? '' : '${material.formatMediumDate(end)} '}${clock(end)}';
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.moon, color: p.ink3, size: I.md),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  (l?.activityPossibleNap ?? 'Possible nap').toUpperCase(),
                  style: F.caps.copyWith(color: p.ink),
                ),
              ),
              if (widget.highlighted)
                Icon(LucideIcons.bell, color: p.on(C.domHealth), size: I.md),
            ],
          ),
          const SizedBox(height: S.x1),
          Text(
            '$when · '
            '${l?.activityLengthMinutes(minutes) ?? '$minutes min'}',
            style: F.cap.copyWith(color: p.ink2),
          ),
          const SizedBox(height: S.x3),
          // The heart rate and the wrist's movement around it, the window drawn
          // on them the way the editor draws it. Its two lines can be dragged
          // to where the nap or the session really began and ended; two
          // fingers zoom.
          WindowPreview(
            start: suggestion.startTs,
            end: suggestion.endTs,
            kind: WindowKind.nap,
            hr: widget.hr,
            zoomable: true,
            height: S.x16 * 2 + S.x6,
            onChanged: (a, b) => setState(() {
              _start = a;
              _end = b;
            }),
          ),
          const SizedBox(height: S.x4),
          // A discard is kept by window and wins over every re-detection; same
          // words as the correction on a logged nap and a night. The answer
          // first, on its own line: three pills abreast left no word room to
          // fit its label.
          BigButton(
            l?.activityConfirm ?? 'Confirm',
            onTap: widget.onConfirm == null
                ? null
                : () => widget.onConfirm!(_start, _end),
          ),
          const SizedBox(height: S.x2),
          Row(
            children: [
              Expanded(
                child: BigButton(
                  l?.activityEdit ?? 'Edit',
                  compact: true,
                  soft: true,
                  onTap: widget.onEdit,
                ),
              ),
              const SizedBox(width: S.x2),
              Expanded(
                child: BigButton(
                  l?.napsNotANapLabel ?? 'Not a nap',
                  compact: true,
                  tone: ButtonTone.danger,
                  onTap: widget.onDiscard,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Home's banner for a nap the detector found: the first proposal itself, with
/// its heart rate and its three answers, so most of them are settled without
/// leaving Home; the rest are one tap away. [pendingCount] (the gallery, tests)
/// draws the plain summary card instead of reading the database.
class DetectedActivitiesCard extends StatefulWidget {
  const DetectedActivitiesCard({super.key, this.pendingCount});
  final int? pendingCount;
  @override
  State<DetectedActivitiesCard> createState() => _DetectedActivitiesCardState();
}

class _DetectedActivitiesCardState extends State<DetectedActivitiesCard>
    with RevisionReload {
  List<ActivitySuggestion>? _items;
  bool _failed = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void reload() {
    if (!_busy) _load();
  }

  Future<void> _load() async {
    try {
      if (widget.pendingCount != null) return;
      final repo = repoOf(context);
      if (repo == null) return;
      final items = [
        for (final s in await repo.pendingActivities())
          if (s.kind == ActivityKind.nap) s,
      ];
      if (mounted) {
        setState(() {
          _items = items;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Confirms [s] at the window its card shows; the detected one stays null,
  /// so an untouched card confirms exactly as it did before it could be edited.
  Future<void> _confirm(ActivitySuggestion s, int a, int b) => _act(s,
      start: a == s.startTs ? null : a, end: b == s.endTs ? null : b);

  Future<void> _act(ActivitySuggestion s,
      {bool discard = false, int? start, int? end}) async {
    final repo = repoOf(context);
    if (_busy || repo == null) return;
    setState(() => (_busy = true, _error = null));
    String? error;
    try {
      if (discard) {
        await repo.discardActivity(s);
      } else {
        await repo.confirmActivity(s, startTs: start, endTs: end);
      }
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    bumpInsights(context);
    await _load();
    if (mounted && error != null) setState(() => _error = error);
  }

  Future<void> _edit(ActivitySuggestion s) async {
    final r = await editNapWindow(context, s);
    if (r != null && mounted) await _act(s, start: r.$1, end: r.$2);
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final given = widget.pendingCount;
    // A failed load is not "nothing", so that still shows, with the retry.
    if (given != null || _failed) {
      final n = given ?? 0;
      if (!_failed && n <= 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: S.x3),
        child: ActionCard(
          l?.activityReviewTitle ?? 'Detected activities',
          _failed
              ? (l?.activityLoadFailed ?? 'Could not load activities. Try again.')
              : (l?.activityPending(n) ?? '$n to review'),
          l?.activityReview ?? 'Review',
          LucideIcons.radar,
          C.domHome,
          onTap: () => go(c, const DetectedActivitiesScreen()),
        ),
      );
    }
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final first = items.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ActivityProposalCard(
          suggestion: first,
          onConfirm: _busy ? null : (a, b) => _confirm(first, a, b),
          onEdit: _busy ? null : () => _edit(first),
          onDiscard: _busy ? null : () => _act(first, discard: true),
        ),
        if (_error != null) ...[
          const SizedBox(height: S.x2),
          Text(_error!, style: F.cap.copyWith(color: C.orange)),
        ],
        if (items.length > 1)
          Align(
            alignment: Alignment.centerRight,
            child: TextAction(
                '${items.length - 1} more to review',
                () => go(c, const DetectedActivitiesScreen())),
          ),
      ]),
    );
  }
}

/// A detected nap's times, on the heart rate: the window editor seeded with
/// the proposal. Epoch seconds, or null when it was left.
Future<(int, int)?> editNapWindow(BuildContext c, ActivitySuggestion s) async {
  final l = AppLocalizations.of(c);
  final r = await openWindowEditor(
    c,
    kind: WindowKind.nap,
    title: l?.activityEditNap ?? 'Edit nap',
    start: DateTime.fromMillisecondsSinceEpoch(s.startTs * 1000),
    end: DateTime.fromMillisecondsSinceEpoch(s.endTs * 1000),
    save: l?.activitySaveConfirm ?? 'Save and confirm',
  );
  if (r == null) return null;
  return (
    r.$1.millisecondsSinceEpoch ~/ 1000,
    r.$2.millisecondsSinceEpoch ~/ 1000,
  );
}
