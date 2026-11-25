// One place to bring history in from other apps: the phone's health store
// (Apple Health or Health Connect, whichever this phone has) and Strava. Each
// source says what it brings, when it last did, what is stored from it, and has
// the button that does it.
//
// The pure half ([ImportHubView]) takes the state to draw, so the gallery shows
// every state; [ImportHubScreen] reads the real state and runs the importers.
// Everything imported keeps its source's name and never changes a score.

import 'package:flutter/material.dart';

import '../../data/db.dart' show LocalDb;
import '../../health/health_history_import.dart';
import '../../health/health_import_state.dart';
import '../../health/health_workout_import.dart';
import '../../import/strava_import.dart';
import '../../l10n/display_text.dart';
import '../ui2.dart';

/// One button on a source's card.
typedef ImportAction = ({String label, VoidCallback? onTap, bool soft});

/// What to draw for one source.
class ImportSourceState {
  final IconData icon;
  final String name, brings;

  /// What is stored from it, or '' for nothing yet.
  final String stored;
  final DateTime? last;

  /// What the last run did, in a sentence; null when none ran this visit.
  final String? result;
  final bool busy;
  final List<ImportAction> actions;
  const ImportSourceState({
    required this.icon,
    required this.name,
    required this.brings,
    this.stored = '',
    this.last,
    this.result,
    this.busy = false,
    this.actions = const [],
  });
}

/// "5 min ago", "3 h ago", "Yesterday", "12 Nov": how long since [t].
String importedAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
  if (days == 1) return 'yesterday';
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${t.day} ${m[t.month - 1]}';
}

class ImportHubView extends StatelessWidget {
  final List<ImportSourceState> sources;
  final DateTime now;
  const ImportHubView({super.key, required this.sources, required this.now});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(uiText(c, 'Import'),
                sub: uiText(c, 'Bring your history in from other apps')),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                Text(
                  uiText(c,
                      'Everything imported keeps the name of the app it came from. It shows beside your own data and never changes your scores.'),
                  style: F.cap.copyWith(color: p.ink3, height: 1.5),
                ),
                const SizedBox(height: S.x4),
                for (final s in sources) ...[
                  _SourceCard(s, now),
                  const SizedBox(height: S.x3),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final ImportSourceState s;
  final DateTime now;
  const _SourceCard(this.s, this.now);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      pad: const EdgeInsets.all(S.x4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(s.icon, size: I.md, color: p.ink),
          const SizedBox(width: S.x3),
          Expanded(child: Text(uiText(c, s.name), style: F.head.copyWith(color: p.ink))),
        ]),
        const SizedBox(height: S.x2),
        Text(uiText(c, s.brings),
            style: F.cap.copyWith(color: p.ink3, height: 1.5)),
        const SizedBox(height: S.x3),
        Text(
          s.last == null
              ? uiText(c, 'Not imported yet')
              : '${uiText(c, 'Last imported')} ${importedAgo(s.last!, now)}',
          style: F.cap.copyWith(color: p.ink),
        ),
        if (s.stored.isNotEmpty) ...[
          const SizedBox(height: S.x1),
          Text(uiText(c, s.stored), style: F.cap.copyWith(color: p.ink3)),
        ],
        if (s.result != null) ...[
          const SizedBox(height: S.x2),
          Text(uiText(c, s.result!),
              style: F.cap.copyWith(color: p.ink, height: 1.5)),
        ],
        if (s.actions.isNotEmpty) ...[
          const SizedBox(height: S.x4),
          Row(children: [
            for (var i = 0; i < s.actions.length; i++) ...[
              if (i > 0) const SizedBox(width: S.x2),
              Expanded(
                child: BigButton(
                  uiText(c, s.actions[i].label).toUpperCase(),
                  compact: true,
                  fill: true,
                  soft: s.actions[i].soft,
                  busy: s.busy && i == 0,
                  onTap: s.busy ? null : s.actions[i].onTap,
                ),
              ),
            ],
          ]),
        ],
      ]),
    );
  }
}

class ImportHubScreen extends StatefulWidget {
  const ImportHubScreen({super.key});

  @override
  State<ImportHubScreen> createState() => _ImportHubScreenState();
}

class _ImportHubScreenState extends State<ImportHubScreen> {
  final _strava = StravaAccount();
  Map<String, int> _counts = const {};
  DateTime? _storeLast, _stravaLast;
  bool _hasClient = false, _connected = false;
  bool _storeBusy = false, _stravaBusy = false;
  String? _storeResult, _stravaResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await LocalDb.importedCounts();
    final w = await lastImportAt(HealthImport.workouts);
    final h = await lastImportAt(HealthImport.history);
    final s = await lastImportAt(HealthImport.strava);
    final client = await _strava.credentials() != null;
    final on = await _strava.connected();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _storeLast = [w, h].whereType<DateTime>().fold<DateTime?>(
          null, (a, b) => a == null || b.isAfter(a) ? b : a);
      _stravaLast = s;
      _hasClient = client;
      _connected = on;
    });
  }

  String _plural(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';

  Future<void> _importStore() async {
    setState(() {
      _storeBusy = true;
      _storeResult = null;
    });
    String result;
    try {
      final workouts = HealthWorkoutImporter();
      final history = HealthHistoryImporter();
      final okW = await workouts.requestPermission();
      final okH = await history.requestPermission();
      if (!okW && !okH) {
        result =
            'Access was not allowed. Allow Locus to read from $storeName, then try again.';
      } else {
        final w = okW ? await workouts.sync(prompt: true) : null;
        if (w != null && w.workouts > 0) {
          await markImported(HealthImport.workouts);
        }
        final h = okH ? await history.run() : const HistoryImportResult();
        final parts = [
          if ((w?.workouts ?? 0) > 0) _plural(w!.workouts, 'workout'),
          if (h.nights > 0) _plural(h.nights, 'night'),
          if (h.days > 0) '${_plural(h.days, 'day')} of steps and heart rate',
        ];
        result = parts.isEmpty
            ? 'Nothing new was found in $storeName.'
            : 'Brought in ${parts.join(', ')}.';
      }
    } catch (_) {
      result = 'The import did not finish. Try again.';
    }
    if (!mounted) return;
    setState(() {
      _storeBusy = false;
      _storeResult = result;
    });
    await _load();
  }

  Future<void> _stravaSignIn() async {
    setState(() {
      _stravaBusy = true;
      _stravaResult = null;
    });
    final err = await _strava.signIn();
    String? result = err;
    if (err == null) {
      final r = await _strava.sync();
      result = r.error ??
          (r.workouts == 0
              ? 'Signed in. No activities in the last 90 days.'
              : 'Brought in ${_plural(r.workouts, 'activity', 'activities')}.');
    }
    if (!mounted) return;
    setState(() {
      _stravaBusy = false;
      _stravaResult = result;
    });
    await _load();
  }

  Future<void> _stravaRefresh() async {
    setState(() {
      _stravaBusy = true;
      _stravaResult = null;
    });
    final r = await _strava.sync();
    if (!mounted) return;
    setState(() {
      _stravaBusy = false;
      _stravaResult = r.error ??
          (r.workouts == 0
              ? 'Nothing new on Strava.'
              : 'Brought in ${_plural(r.workouts, 'activity', 'activities')}.');
    });
    await _load();
  }

  Future<void> _stravaSignOut() async {
    await _strava.signOut();
    if (!mounted) return;
    setState(() => _stravaResult = 'Signed out of Strava.');
    await _load();
  }

  void _setUpStrava() {
    final id = TextEditingController(), secret = TextEditingController();
    AppSheet.show<void>(context,
        title: 'Set up Strava',
        child: Builder(builder: (sc) {
          final p = P.of(sc);
          Widget step(String n, String t) => Padding(
                padding: const EdgeInsets.only(bottom: S.x2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      width: S.x6,
                      child: Text(n, style: F.cap.copyWith(color: p.ink3))),
                  Expanded(
                      child: Text(uiText(sc, t),
                          style: F.cap.copyWith(color: p.ink, height: 1.5))),
                ]),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            step('1', 'On a computer or in a browser, open strava.com/settings/api and create an app. Any name works.'),
            step('2', 'Set its Authorization Callback Domain to strava-callback'),
            step('3', 'Copy its Client ID and Client Secret into the two boxes below.'),
            const SizedBox(height: S.x3),
            AppField(
                label: 'Client ID',
                controller: id,
                keyboardType: TextInputType.number,
                autocorrect: false),
            const SizedBox(height: S.x3),
            AppField(
                label: 'Client Secret',
                controller: secret,
                obscure: true,
                autocorrect: false,
                enableSuggestions: false),
            const SizedBox(height: S.x4),
            BigButton('SAVE', compact: true, fill: true, onTap: () async {
              if (id.text.trim().isEmpty || secret.text.trim().isEmpty) return;
              await _strava.saveCredentials(id.text, secret.text);
              if (sc.mounted) Navigator.of(sc).pop();
              await _load();
            }),
          ]);
        }));
  }

  @override
  Widget build(BuildContext c) {
    final n = _counts;
    final store = [
      if ((n['workouts'] ?? 0) - (n['strava'] ?? 0) > 0)
        _plural((n['workouts'] ?? 0) - (n['strava'] ?? 0), 'workout'),
      if ((n['sleep'] ?? 0) > 0) _plural(n['sleep']!, 'night'),
      if ((n['days'] ?? 0) > 0) '${_plural(n['days']!, 'day')} of steps and heart rate',
    ];
    return ImportHubView(
      now: DateTime.now(),
      sources: [
        ImportSourceState(
          icon: LucideIcons.heartPulse,
          name: storeName,
          brings: isAppleHealth
              ? 'Workouts with their routes, sleep, steps and heart rate from the last 90 days.'
              : 'Workouts, sleep, steps and heart rate from the last 30 days, the most Health Connect shares.',
          stored: store.isEmpty ? '' : 'Stored: ${store.join(' · ')}',
          last: _storeLast,
          result: _storeResult,
          busy: _storeBusy,
          actions: [
            (
              label: _storeLast == null ? 'Import' : 'Refresh',
              onTap: _importStore,
              soft: false
            ),
          ],
        ),
        ImportSourceState(
          icon: LucideIcons.activity,
          name: 'Strava',
          brings: _hasClient
              ? 'Your activities from the last 90 days. You sign in on Strava; Locus keeps only a token.'
              : 'Your activities from the last 90 days. Strava needs a free API app of your own first.',
          stored: (n['strava'] ?? 0) > 0
              ? 'Stored: ${_plural(n['strava']!, 'activity', 'activities')}'
              : '',
          last: _stravaLast,
          result: _stravaResult,
          busy: _stravaBusy,
          actions: !_hasClient
              ? [(label: 'Set up Strava', onTap: _setUpStrava, soft: false)]
              : !_connected
                  ? [(label: 'Sign in to Strava', onTap: _stravaSignIn, soft: false)]
                  : [
                      (label: 'Refresh', onTap: _stravaRefresh, soft: false),
                      (label: 'Sign out', onTap: _stravaSignOut, soft: true),
                    ],
        ),
      ],
    );
  }
}
