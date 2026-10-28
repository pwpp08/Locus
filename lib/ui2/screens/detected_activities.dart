import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/activity_suggestion.dart';
import '../../theme/theme_switcher.dart' show themedRoute;
import '../activity/catalogue.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'log_workout.dart';
import 'window_editor.dart';

class DetectedActivitiesScreen extends StatefulWidget {
  const DetectedActivitiesScreen({super.key, this.focusId, this.preloaded});
  final String? focusId;
  final List<ActivitySuggestion>? preloaded;
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
      final items =
          widget.preloaded ?? await repoOf(context)!.pendingActivities();
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
        await repo.confirmActivity(
          s,
          startTs: start,
          endTs: end,
          workoutType: activityByName(s.sport)?.typeKey ?? 'other',
        );
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
    final l = AppLocalizations.of(context);
    if (s.kind == ActivityKind.workout) {
      await Navigator.of(context).push<bool>(
        themedActivityRoute(
          LogWorkout(
            suggestion: s,
            start: DateTime.fromMillisecondsSinceEpoch(s.startTs * 1000),
            end: DateTime.fromMillisecondsSinceEpoch(s.endTs * 1000),
            activity: activityByName(s.sport),
            title: l?.activityEditWorkout ?? 'Edit workout',
          ),
        ),
      );
      if (mounted) await _load();
    } else {
      final result = await editNapWindow(context, s);
      if (result != null && mounted) {
        await _act(s, start: result.$1, end: result.$2);
      }
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
                      l?.activityEmptyBody ??
                          'Possible naps and workouts will appear here.',
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
                          onConfirm: _busy ? null : () => _act(s),
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

/// Routes inherit the app's theme and reduced-motion policy.
Route<T> themedActivityRoute<T>(Widget child) =>
    themedRoute<T>((_) => child, name: child.runtimeType.toString());

class ActivityProposalCard extends StatelessWidget {
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
  final VoidCallback? onConfirm, onEdit, onDiscard;

  /// Where the preview's heart rate comes from; the band's store when null.
  final HrReader? hr;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final nap = suggestion.kind == ActivityKind.nap;
    final accent = nap ? C.domHealth : C.domMove;
    final start = DateTime.fromMillisecondsSinceEpoch(
      suggestion.startTs * 1000,
    );
    final end = DateTime.fromMillisecondsSinceEpoch(suggestion.endTs * 1000);
    final material = MaterialLocalizations.of(c);
    String when(DateTime value) =>
        '${material.formatMediumDate(value)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(value), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(c))}';
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                nap ? LucideIcons.moon : LucideIcons.activity,
                color: p.on(accent),
                size: I.md,
              ),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  nap
                      ? (l?.activityPossibleNap ?? 'Possible nap')
                      : (l?.activityPossibleWorkout ?? 'Possible workout'),
                  style: F.head.copyWith(color: p.ink),
                ),
              ),
              if (highlighted)
                Icon(LucideIcons.bell, color: p.on(accent), size: I.md),
            ],
          ),
          const SizedBox(height: S.x2),
          Text(
            '${when(start)} – ${when(end)}',
            style: F.body.copyWith(color: p.ink2),
          ),
          Text(
            l?.activityLengthMinutes(suggestion.durationMin) ??
                '${suggestion.durationMin} min',
            style: F.cap.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x3),
          // The heart rate around it, the window drawn on it the way the
          // editor draws it: what the detector saw, before it is confirmed.
          WindowPreview(
            start: suggestion.startTs,
            end: suggestion.endTs,
            kind: nap ? WindowKind.nap : WindowKind.workout,
            hr: hr,
          ),
          const SizedBox(height: S.x3),
          Wrap(
            spacing: S.x4,
            runSpacing: S.x2,
            children: [
              _action(c, l?.activityConfirm ?? 'Confirm', onConfirm, accent),
              // The workout editor is where the sport is picked, so it says
              // that; a nap only has times to edit.
              _action(
                c,
                nap
                    ? (l?.activityEdit ?? 'Edit')
                    : (l?.activityChangeSport ?? 'Change sport'),
                onEdit,
                accent,
              ),
              // Same words as the correction on a logged nap and a night, so
              // "this was wrong" reads the same wherever the detection shows.
              // A discard is kept by window and wins over every re-detection.
              _action(
                c,
                nap
                    ? (l?.napsNotANapLabel ?? 'Not a nap')
                    : (l?.activityNotAWorkout ?? 'Not a workout'),
                onDiscard,
                C.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext c,
    String label,
    VoidCallback? tap,
    Color accent,
  ) => Pressable(
    onTap: tap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x2),
      child: Text(
        label.toUpperCase(),
        style: F.caps.copyWith(
          color: accent == C.red ? P.of(c).on(C.red) : P.of(c).ink,
        ),
      ),
    ),
  );
}

/// Home's banner for what the detector found: the first proposal itself, with
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
      final items = await repo.pendingActivities();
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
        await repo.confirmActivity(s,
            startTs: start,
            endTs: end,
            workoutType: activityByName(s.sport)?.typeKey ?? 'other');
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
    if (s.kind == ActivityKind.nap) {
      final r = await editNapWindow(context, s);
      if (r != null && mounted) await _act(s, start: r.$1, end: r.$2);
      return;
    }
    // A workout's editor is where its sport is picked too; the list
    // re-reads when it comes back (RevisionReload).
    go(context, const DetectedActivitiesScreen());
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
          onConfirm: _busy ? null : () => _act(first),
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
