// COMMUNITY — teams, their leaderboards, the team feed and team chat.
//
// Signed out it is one page that says what this is and how to join, and the
// rest of the app works exactly as before. Signed in: your teams (and the
// open community, leaderboard only, which you can leave), what you share
// (nothing until you tick it), and your account.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../community/community_service.dart';
import '../../community/leaderboard.dart';
import '../profile/profile.dart' show SetRow, settingsGroup;
import '../screens/home_screen.dart' show go;
import '../ui2.dart';

CommunityService get _svc => CommunityService.instance;

/// The colour a member picked, as their avatar's ring.
Color hueColor(int hue, {double lightness = .58}) =>
    HSLColor.fromAHSL(1, hue % 360 + 0.0, .62, lightness).toColor();

/// A member: their initials on a disc in a ring of their colour.
class CommunityAvatar extends StatelessWidget {
  final String name;
  final int hue;
  final double size;
  const CommunityAvatar(this.name, this.hue, {super.key, this.size = S.x10});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(S.half),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [
          hueColor(hue),
          hueColor(hue + 40, lightness: .45),
          hueColor(hue),
        ]),
      ),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.card2),
        alignment: Alignment.center,
        child: Text(
          initialsOf(name),
          style: (size >= S.x16 ? F.t2 : F.caps)
              .copyWith(color: p.ink, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Small helpers every screen here uses.
void _say(BuildContext c, String text) => ScaffoldMessenger.maybeOf(c)
    ?.showSnackBar(SnackBar(content: Text(text)));

Future<bool> _confirm(BuildContext c, String title, String body, String yes,
    {bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AppDialog(
      title: title,
      content: Text(body, style: F.body.copyWith(color: P.of(d).ink2)),
      actions: [
        BigButton('Cancel', soft: true, onTap: () => Navigator.of(d).pop(false)),
        BigButton(yes,
            tone: danger ? ButtonTone.danger : ButtonTone.standard,
            onTap: () => Navigator.of(d).pop(true)),
      ],
    ),
  );
  return ok ?? false;
}

/// One line of text asked for in a sheet; null when cancelled.
Future<String?> _ask(BuildContext c, String title, String action,
    {String initial = '', String hint = '', int maxLength = 40, bool caps = false}) {
  final ctrl = TextEditingController(text: initial);
  return AppSheet.show<String>(
    c,
    title: title,
    child: AppField(
      controller: ctrl,
      hint: hint,
      autofocus: true,
      maxLength: maxLength,
      textInputAction: TextInputAction.done,
      onSubmitted: (v) => Navigator.of(c).pop(v),
      textStyle: caps ? F.t2.copyWith(letterSpacing: 4) : null,
    ),
    actions: [
      Builder(
        builder: (s) => BigButton(action,
            onTap: () => Navigator.of(s).pop(ctrl.text)),
      ),
    ],
  ).whenComplete(ctrl.dispose);
}

// ═══════════════════════════ the door ═══════════════════════════

class CommunityScreen extends StatefulWidget {
  /// Shown as a tab of its own: no back arrow.
  final bool tab;
  const CommunityScreen({super.key, this.tab = false});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  @override
  void initState() {
    super.initState();
    _svc.addListener(_changed);
    unawaited(_svc.ensureReady().then((_) {
      if (_svc.signedIn) _svc.refresh();
    }));
  }

  @override
  void dispose() {
    _svc.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: widget.tab
                ? const ScreenTitle('Community')
                : const NavBar('Community'),
          ),
          Expanded(
            child: !_svc.ready
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _svc.signedIn
                    ? _SignedIn(onRefresh: _svc.refresh)
                    : const _Welcome(),
          ),
        ]),
      ),
    );
  }
}

/// Signed out: what this is, and the way in.
class _Welcome extends StatefulWidget {
  const _Welcome();

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  bool _google = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _svc.googleAvailable().then((g) {
      if (mounted) setState(() => _google = g);
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: S.x4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: S.x10,
              height: S.x10,
              decoration: BoxDecoration(color: p.card2, shape: BoxShape.circle),
              child: Icon(icon, size: I.md, color: p.ink),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: F.head.copyWith(color: p.ink)),
                const SizedBox(height: S.half),
                Text(body, style: F.cap.copyWith(color: p.ink2, height: 1.4)),
              ]),
            ),
          ]),
        );
    return ListView(
      padding: EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.navClear(c)),
      children: [
        Text('Train with your people',
            style: F.t1.copyWith(color: p.ink)),
        const SizedBox(height: S.x2),
        Text(
          'Make a team, send its code to friends, and see who recovered best, '
          'pushed hardest and slept longest.',
          style: F.body.copyWith(color: p.ink2, height: 1.45),
        ),
        const SizedBox(height: S.x6),
        point(LucideIcons.trophy, 'Leaderboards',
            'Recovery, strain, sleep, or all three, over a day, a week or a month.'),
        point(LucideIcons.messageSquare, 'Team chat and feed',
            'Talk, and post a workout, a chart or a good night as a picture.'),
        point(LucideIcons.shieldCheck, 'You choose what is shared',
            'Nothing leaves this phone until you tick it. Untick it and it is '
                'taken back down.'),
        const SizedBox(height: S.x4),
        BigButton('Join',
            icon: LucideIcons.logIn,
            busy: _busy,
            onTap: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await _svc.join();
                    } catch (e) {
                      if (c.mounted) _say(c, communityError(e));
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  }),
        if (_google) ...[
          const SizedBox(height: S.x3),
          BigButton('Continue with Google', soft: true, onTap: () async {
            try {
              await _svc.signInWithGoogle();
            } catch (e) {
              if (c.mounted) _say(c, communityError(e));
            }
          }),
        ],
        const SizedBox(height: S.x4),
        Text(
          'Optional. Everything else in the app works the same without an account.',
          textAlign: TextAlign.center,
          style: F.cap.copyWith(color: p.ink3),
        ),
      ],
    );
  }
}

/// Signed in: a name prompt if there is none yet, the teams, sharing, account.
class _SignedIn extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _SignedIn({required this.onRefresh});

  static bool _defaultName(String n) => RegExp(r'^Member [0-9A-F]{4}$').hasMatch(n);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final me = _svc.profile;
    final mine = _svc.teams.where((t) => !t.isOpen).toList();
    final open = _svc.teams.where((t) => t.isOpen).firstOrNull;
    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.navClear(c)),
        children: [
          if (me != null && _defaultName(me.name)) ...[
            StatusCard(
              'Pick the name your team sees',
              'Right now you show up as ${me.name}.',
              fix: 'Choose a name',
              icon: LucideIcons.userPen,
              onFix: () => _rename(c),
            ),
            const SizedBox(height: S.x3),
          ],
          if (me != null && !me.sharesAnything) ...[
            StatusCard(
              'You are not on any leaderboard yet',
              'Nothing is shared until you tick it under What I share.',
              icon: LucideIcons.shieldCheck,
            ),
            const SizedBox(height: S.x3),
          ],
          settingsGroup(c, 'My teams', [
            for (final t in mine) _TeamRow(t),
            if (open != null) _TeamRow(open),
            SetRow(LucideIcons.plus, C.dialStrain, 'Create a team',
                onTap: () => _create(c)),
            SetRow(LucideIcons.logIn, C.dialStrain, 'Join with a code',
                onTap: () => _join(c)),
          ]),
          if (me != null)
            settingsGroup(c, 'What I share', [
              SetRow(LucideIcons.heartPulse, C.dialStrain, 'Recovery',
                  sub: 'A day’s recovery %',
                  switchValue: me.shareRecovery,
                  onTap: () => _toggle(c, () =>
                      _svc.updateProfile(shareRecovery: !me.shareRecovery))),
              SetRow(LucideIcons.flame, C.dialStrain, 'Strain',
                  sub: 'A day’s strain, out of 21',
                  switchValue: me.shareStrain,
                  onTap: () => _toggle(
                      c, () => _svc.updateProfile(shareStrain: !me.shareStrain))),
              SetRow(LucideIcons.moon, C.dialStrain, 'Sleep',
                  sub: 'Hours slept in the night',
                  switchValue: me.shareSleep,
                  onTap: () => _toggle(
                      c, () => _svc.updateProfile(shareSleep: !me.shareSleep))),
              SetRow(LucideIcons.users, C.dialStrain, 'Open community',
                  sub: 'The leaderboard everyone with Locus can see',
                  switchValue: _svc.inOpenCommunity,
                  onTap: () => _toggle(c,
                      () => _svc.setOpenCommunity(!_svc.inOpenCommunity))),
            ]),
          if (me != null)
            settingsGroup(c, 'Account', [
              SetRow(LucideIcons.userRound, C.dialStrain, 'Name',
                  value: me.name, onTap: () => _rename(c)),
              SetRow(LucideIcons.circle, C.dialStrain, 'Colour',
                  trailing: CommunityAvatar(me.name, me.hue, size: S.x8),
                  onTap: () => _toggle(c,
                      () => _svc.updateProfile(hue: (me.hue + 47) % 360))),
              if (!_svc.anonymous)
                SetRow(LucideIcons.logOut, C.dialStrain, 'Sign out',
                    value: _svc.user?.email ?? '',
                    onTap: () => _toggle(c, _svc.signOut)),
              SetRow(LucideIcons.trash2, C.dialStrain, 'Delete my account',
                  danger: true, onTap: () => _delete(c)),
            ]),
          const SizedBox(height: S.x4),
          Text(
            'Your teams see your name, your colour and the numbers you share. '
            'Nothing else leaves this phone.',
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }

  static Future<void> _toggle(BuildContext c, Future<void> Function() job) async {
    try {
      await job();
    } catch (e) {
      if (c.mounted) _say(c, communityError(e));
    }
  }

  static Future<void> _rename(BuildContext c) async {
    final name = await _ask(c, 'YOUR NAME', 'Save',
        initial: _svc.profile?.name ?? '', hint: 'How your team knows you');
    if (name == null || name.trim().isEmpty || !c.mounted) return;
    await _toggle(c, () => _svc.updateProfile(name: name));
  }

  static Future<void> _create(BuildContext c) async {
    final name = await _ask(c, 'NEW TEAM', 'Create', hint: 'Team name');
    if (name == null || name.trim().isEmpty || !c.mounted) return;
    try {
      final id = await _svc.createTeam(name);
      final t = _svc.teams.where((t) => t.id == id).firstOrNull;
      if (t != null && c.mounted) go(c, TeamScreen(team: t, startOn: 3));
    } catch (e) {
      if (c.mounted) _say(c, communityError(e));
    }
  }

  static Future<void> _join(BuildContext c) async {
    final code = await _ask(c, 'JOIN A TEAM', 'Join',
        hint: 'The six-letter code', maxLength: 6, caps: true);
    if (code == null || code.trim().isEmpty || !c.mounted) return;
    try {
      final id = await _svc.joinTeam(code);
      final t = _svc.teams.where((t) => t.id == id).firstOrNull;
      if (t != null && c.mounted) go(c, TeamScreen(team: t));
    } catch (e) {
      if (c.mounted) _say(c, communityError(e));
    }
  }

  static Future<void> _delete(BuildContext c) async {
    final ok = await _confirm(
        c,
        'Delete your account?',
        'Your profile, everything you shared, your messages and posts are '
            'removed from the server for good. What is on this phone stays.',
        'Delete',
        danger: true);
    if (ok && c.mounted) await _toggle(c, _svc.deleteAccount);
  }
}

class _TeamRow extends StatelessWidget {
  final CommunityTeam team;
  const _TeamRow(this.team);

  @override
  Widget build(BuildContext c) => SetRow(
        team.isOpen ? LucideIcons.users : LucideIcons.trophy,
        C.dialStrain,
        team.name,
        sub: team.isOpen ? 'Everyone · leaderboard only' : 'Code ${team.code}',
        trailing: team.unread == 0
            ? null
            : Pill('${team.unread > 99 ? '99+' : team.unread} new', C.dialStrain),
        onTap: () => go(c, TeamScreen(team: team)),
      );
}

// ═══════════════════════════ a team ═══════════════════════════

class TeamScreen extends StatefulWidget {
  final CommunityTeam team;

  /// The tab to open on (an index into this team's tabs).
  final int startOn;
  const TeamScreen({super.key, required this.team, this.startOn = 0});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  late int _tab = widget.startOn;
  Map<String, CommunityProfile> _people = const {};
  List<DayScore> _scores = const [];
  bool _loading = true;
  String? _error;

  CommunityTeam get t => widget.team;

  /// The open community is a leaderboard and its info, nothing more.
  List<String> get _tabs =>
      t.isOpen ? const ['BOARD', 'INFO'] : const ['BOARD', 'FEED', 'CHAT', 'INFO'];

  @override
  void initState() {
    super.initState();
    _tab = _tab.clamp(0, _tabs.length - 1);
    _load();
  }

  Future<void> _load() async {
    try {
      final people = await _svc.members(t.id);
      final scores = await _svc.scores(t.id);
      if (!mounted) return;
      setState(() {
        _people = people;
        _scores = scores;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = communityError(e);
        });
      }
    }
  }

  Future<void> _menu() async {
    final c = context;
    final pick = await AppSheet.show<String>(
      c,
      title: t.name.toUpperCase(),
      child: Column(children: [
        if (!t.isOpen) ...[
          SetRow(LucideIcons.share2, C.dialStrain, 'Invite with the code',
              value: t.code, onTap: () => Navigator.of(c).pop('invite')),
          SetRow(LucideIcons.copy, C.dialStrain, 'Copy the code',
              onTap: () => Navigator.of(c).pop('copy')),
        ],
        SetRow(LucideIcons.logOut, C.dialStrain,
            t.isOpen ? 'Leave the open community' : 'Leave the team',
            danger: true, onTap: () => Navigator.of(c).pop('leave')),
      ]),
    );
    if (!mounted) return;
    switch (pick) {
      case 'invite':
        await Share.share(
            'Join my team "${t.name}" in Locus: open Community, Join with a '
            'code, and enter ${t.code}.');
      case 'copy':
        await Clipboard.setData(ClipboardData(text: t.code));
        if (mounted) _say(context, 'Code copied');
      case 'leave':
        final ok = await _confirm(
            context,
            t.isOpen ? 'Leave the open community?' : 'Leave ${t.name}?',
            t.isOpen
                ? 'You come off its leaderboard. You can join again from '
                    'Community, under What I share.'
                : 'You can join again with its code, ${t.code}.',
            'Leave',
            danger: true);
        if (!ok || !mounted) return;
        try {
          await _svc.leaveTeam(t.id);
          if (mounted) Navigator.of(context).maybePop();
        } catch (e) {
          if (mounted) _say(context, communityError(e));
        }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final name = _tabs[_tab];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(t.name.toUpperCase(),
                trailing: RoundIconButton(
                    LucideIcons.ellipsis, _menu, 'Team options')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: SubTabs(_tabs, _tab, (i) => setState(() => _tab = i),
                color: C.dialStrain),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _error != null
                    ? ListView(padding: const EdgeInsets.all(S.x4), children: [
                        StatusCard('The team did not load', _error!,
                            fix: 'Try again',
                            icon: LucideIcons.cloudOff, onFix: () {
                          setState(() => _loading = true);
                          _load();
                        }),
                      ])
                    : switch (name) {
                        'BOARD' => _Board(
                            people: _people, scores: _scores, onRefresh: _load),
                        'FEED' => _Feed(team: t, people: _people),
                        'CHAT' => _Chat(team: t, people: _people),
                        _ => _Info(team: t, people: _people, scores: _scores),
                      },
          ),
        ]),
      ),
    );
  }
}

// ── the board ──

class _Board extends StatefulWidget {
  final Map<String, CommunityProfile> people;
  final List<DayScore> scores;
  final Future<void> Function() onRefresh;
  const _Board(
      {required this.people, required this.scores, required this.onRefresh});

  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board> {
  BoardMetric _metric = BoardMetric.recovery;
  BoardRange _range = BoardRange.today;

  static const _metricNames = ['Recovery', 'Strain', 'Sleep', 'Overall'];
  static const _rangeNames = ['TODAY', '7 DAYS', '30 DAYS'];

  Color _ink(BoardMetric m) => switch (m) {
        BoardMetric.recovery => C.recGreen,
        BoardMetric.strain => C.dialStrain,
        BoardMetric.sleep => C.dialSleep,
        BoardMetric.combined => C.white,
      };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final rows = rankBoard(
            widget.scores, _metric, _range, DateTime.now())
        .where((r) => widget.people.containsKey(r.userId))
        .toList();
    final avg = rows.isEmpty
        ? null
        : rows.map((r) => r.value).reduce((a, b) => a + b) / rows.length;
    final ink = p.on(_ink(_metric));
    return RefreshIndicator.adaptive(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.navClear(c)),
        children: [
          RangeSegments(_metricNames, _metric.index,
              (i) => setState(() => _metric = BoardMetric.values[i]),
              width: null),
          const SizedBox(height: S.x3),
          RangeSegments(_rangeNames, _range.index,
              (i) => setState(() => _range = BoardRange.values[i]),
              width: null),
          const SizedBox(height: S.x4),
          Row(children: [
            Expanded(
              child: Text(
                avg == null
                    ? _metricNames[_metric.index]
                    : '${_metricNames[_metric.index]} · '
                        '${boardValue(_metric, avg)} avg',
                style: F.head.copyWith(color: p.ink),
              ),
            ),
            Text('${rows.length} on the board',
                style: F.cap.copyWith(color: p.ink3)),
          ]),
          if (_metric == BoardMetric.combined) ...[
            const SizedBox(height: S.x1),
            Text(
              'The mean of recovery, strain out of 21 and sleep against eight '
              'hours, over whichever of them each person shares.',
              style: F.cap.copyWith(color: p.ink3, height: 1.4),
            ),
          ],
          const SizedBox(height: S.x3),
          if (rows.isEmpty)
            NoData(
              message: 'Nobody has shared ${_metricNames[_metric.index].toLowerCase()} '
              '${_range == BoardRange.today ? 'today' : 'in this window'} yet.',
            )
          else
            for (var i = 0; i < rows.length; i++)
              _BoardRow(
                place: i + 1,
                who: widget.people[rows[i].userId]!,
                value: boardValue(_metric, rows[i].value),
                days: _range == BoardRange.today ? null : rows[i].days,
                // Recovery in its own three colours, like everywhere else.
                ink: _metric != BoardMetric.recovery
                    ? ink
                    : p.on(rows[i].value >= 67
                        ? C.recGreen
                        : rows[i].value >= 34
                            ? C.recYellow
                            : C.recRed),
                me: rows[i].userId == _svc.myId,
                onTap: () => go(
                    c,
                    MemberProfile(
                      who: widget.people[rows[i].userId]!,
                      scores: [
                        for (final s in widget.scores)
                          if (s.userId == rows[i].userId) s,
                      ],
                    )),
              ),
        ],
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  final int place;
  final CommunityProfile who;
  final String value;
  final int? days;
  final Color ink;
  final bool me;
  final VoidCallback onTap;
  const _BoardRow(
      {required this.place,
      required this.who,
      required this.value,
      required this.days,
      required this.ink,
      required this.me,
      required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$place. ${who.name}, $value',
      child: Container(
        margin: const EdgeInsets.only(bottom: S.x2),
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
        decoration: BoxDecoration(
          color: me ? p.card2 : p.card,
          borderRadius: R.rLg,
        ),
        child: Row(children: [
          CommunityAvatar(who.name, who.hue),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$place. ${who.name.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.caps.copyWith(
                      color: p.ink, fontWeight: FontWeight.w700)),
              if (days != null)
                Text(days == 1 ? '1 day shared' : '$days days shared',
                    style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Text(value,
              style: F.t2.copyWith(color: ink, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

// ── a member ──

class MemberProfile extends StatelessWidget {
  final CommunityProfile who;
  final List<DayScore> scores;
  const MemberProfile({super.key, required this.who, required this.scores});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final sorted = [...scores]..sort((a, b) => b.day.compareTo(a.day));
    // Days in a row, back from the newest, with anything shared.
    var streak = 0;
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i - 1].day.difference(sorted[i].day).inDays != 1) break;
      streak++;
    }
    final today = DateTime.now();
    Widget stat(String label, BoardMetric m, bool shared) {
      if (!shared) return const SizedBox.shrink();
      final month = rankBoard(scores, m, BoardRange.month, today);
      final values = [for (final s in scores) ?s.value(m)];
      final best = values.isEmpty
          ? null
          : (m == BoardMetric.strain || m == BoardMetric.sleep || m == BoardMetric.recovery
              ? values.reduce((a, b) => a > b ? a : b)
              : null);
      return SetRow(
        switch (m) {
          BoardMetric.recovery => LucideIcons.heartPulse,
          BoardMetric.strain => LucideIcons.flame,
          _ => LucideIcons.moon,
        },
        C.dialStrain,
        label,
        sub: best == null ? '' : 'Best ${boardValue(m, best)}',
        value: month.isEmpty ? '—' : '${boardValue(m, month.first.value)} avg',
        chevron: false,
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          children: [
            const NavBar(''),
            Center(child: CommunityAvatar(who.name, who.hue, size: S.x16 + S.x8)),
            const SizedBox(height: S.x3),
            Text(who.name,
                textAlign: TextAlign.center,
                style: F.t1.copyWith(color: p.ink)),
            const SizedBox(height: S.x1),
            Text(
              who.sharesAnything
                  ? 'Shares ${[
                      if (who.shareRecovery) 'recovery',
                      if (who.shareStrain) 'strain',
                      if (who.shareSleep) 'sleep',
                    ].join(', ')}'
                  : 'Shares nothing yet',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink3),
            ),
            const SizedBox(height: S.x4),
            Row(children: [
              Expanded(child: _Tile('$streak', streak == 1 ? 'DAY STREAK' : 'DAYS STREAK')),
              const SizedBox(width: S.x3),
              Expanded(child: _Tile('${scores.length}', 'DAYS SHARED, 30 D')),
            ]),
            settingsGroup(c, 'Last 30 days', [
              stat('Recovery', BoardMetric.recovery, who.shareRecovery),
              stat('Strain', BoardMetric.strain, who.shareStrain),
              stat('Sleep', BoardMetric.sleep, who.shareSleep),
            ]),
            if (who.id != _svc.myId) ...[
              const SizedBox(height: S.x6),
              Center(
                child: TextAction('Block ${who.name}', () async {
                  final ok = await _confirm(
                      c,
                      'Block ${who.name}?',
                      'You will not see their messages, posts or place on '
                          'any board. They are not told.',
                      'Block',
                      danger: true);
                  if (!ok) return;
                  await _svc.block(who.id);
                  if (c.mounted) Navigator.of(c).maybePop();
                }, icon: LucideIcons.circleSlash, tone: ButtonTone.danger),
              ),
            ],
            const SizedBox(height: S.x10),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String value, label;
  const _Tile(this.value, this.label);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
      child: Column(children: [
        Text(value, style: F.t1.copyWith(color: p.ink)),
        const SizedBox(height: S.x1),
        Text(label,
            textAlign: TextAlign.center,
            style: F.over.copyWith(color: p.ink3, letterSpacing: 1.2)),
      ]),
    );
  }
}

// ── the feed ──

class _Feed extends StatefulWidget {
  final CommunityTeam team;
  final Map<String, CommunityProfile> people;
  const _Feed({required this.team, required this.people});

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  List<FeedPost>? _posts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _svc.markRead(widget.team.id);
  }

  Future<void> _load() async {
    try {
      final posts = await _svc.posts(widget.team.id);
      if (mounted) setState(() => _posts = posts);
    } catch (e) {
      if (mounted) setState(() => _error = communityError(e));
    }
  }

  Future<void> _newPost() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    final done = await shareToTeam(context, bytes,
        mime: 'image/jpeg', only: widget.team.id);
    if (done) await _load();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final posts = _posts;
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.navClear(c)),
        children: [
          BigButton('Post a picture',
              icon: LucideIcons.imagePlus, soft: true, onTap: _newPost),
          const SizedBox(height: S.x2),
          Text(
            'Or tap Share to team on a workout to post its card.',
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x4),
          if (_error != null)
            ErrorLine(_error!)
          else if (posts == null)
            const Center(child: CircularProgressIndicator.adaptive())
          else if (posts.isEmpty)
            const NoData(message: 'Nothing posted yet. Be the first.')
          else
            for (final post in posts)
              _PostCard(
                post: post,
                who: widget.people[post.userId],
                onGone: () => setState(() => _posts = [
                      for (final q in _posts ?? const <FeedPost>[])
                        if (q.id != post.id) q,
                    ]),
              ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final FeedPost post;
  final CommunityProfile? who;
  final VoidCallback onGone;
  const _PostCard({required this.post, required this.who, required this.onGone});

  Future<void> _menu(BuildContext c) async {
    final mine = post.userId == _svc.myId;
    final pick = await AppSheet.show<String>(c,
        child: Column(children: [
          if (mine)
            SetRow(LucideIcons.trash2, C.dialStrain, 'Delete the post',
                danger: true, onTap: () => Navigator.of(c).pop('delete'))
          else ...[
            SetRow(LucideIcons.flag, C.dialStrain, 'Report the post',
                onTap: () => Navigator.of(c).pop('report')),
            SetRow(LucideIcons.circleSlash, C.dialStrain,
                'Block ${who?.name ?? 'them'}',
                danger: true, onTap: () => Navigator.of(c).pop('block')),
          ],
        ]));
    if (!c.mounted) return;
    try {
      switch (pick) {
        case 'delete':
          await _svc.deletePost(post);
          onGone();
        case 'report':
          await _svc.report(teamId: post.teamId, postId: post.id);
          if (c.mounted) _say(c, 'Reported. Thank you.');
        case 'block':
          await _svc.block(post.userId);
          onGone();
      }
    } catch (e) {
      if (c.mounted) _say(c, communityError(e));
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final name = who?.name ?? 'A member';
    return Container(
      margin: const EdgeInsets.only(bottom: S.x4),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x3, S.x3, S.x1, S.x2),
          child: Row(children: [
            CommunityAvatar(name, who?.hue ?? 0, size: S.x8),
            const SizedBox(width: S.x2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                Text(_ago(post.at), style: F.cap.copyWith(color: p.ink3)),
              ]),
            ),
            RoundIconButton(LucideIcons.ellipsis, () => _menu(c), 'Post options'),
          ]),
        ),
        FutureBuilder<String>(
          future: _svc.pictureUrl(post.imagePath),
          builder: (_, snap) => AspectRatio(
            aspectRatio: 1,
            child: snap.data == null
                ? ColoredBox(color: p.card2)
                : Image.network(snap.data!,
                    fit: BoxFit.cover,
                    semanticLabel: 'Picture from $name',
                    errorBuilder: (_, _, _) => ColoredBox(
                        color: p.card2,
                        child: Icon(LucideIcons.imagePlus,
                            size: I.lg, color: p.ink3))),
          ),
        ),
        if (post.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(S.x3),
            child: Text(post.caption,
                style: F.body.copyWith(color: p.ink, height: 1.4)),
          ),
      ]),
    );
  }
}

String _ago(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${at.day}/${at.month}/${at.year}';
}

/// Posts [image] with a caption to the teams the person picks (or to [only]).
/// True when it went up.
Future<bool> shareToTeam(BuildContext c, List<int> image,
    {String mime = 'image/png', String? only}) async {
  await _svc.ensureReady();
  if (!c.mounted) return false;
  if (!_svc.signedIn) {
    go(c, const CommunityScreen());
    return false;
  }
  final teams = [for (final t in _svc.teams) if (!t.isOpen) t];
  if (teams.isEmpty) {
    _say(c, 'Create or join a team first, in Community.');
    return false;
  }
  final bytes = image is Uint8List ? image : Uint8List.fromList(image);
  final caption = TextEditingController();
  final chosen = <String>{only ?? teams.first.id};
  var busy = false;
  final posted = await AppSheet.open<bool>(
    c,
    scroll: true,
    dragHandle: true,
    builder: (s) => StatefulBuilder(
      builder: (s, setS) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              S.x4, 0, S.x4, S.x4 + MediaQuery.viewInsetsOf(s).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('SHARE TO TEAM',
                    style: F.caps.copyWith(
                        color: P.of(s).ink2, fontWeight: FontWeight.w700)),
                const SizedBox(height: S.x3),
                ClipRRect(
                  borderRadius: R.rLg,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: S.x16 * 4),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: S.x3),
                AppField(
                    controller: caption,
                    hint: 'Say something about it',
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 4),
                if (only == null && teams.length > 1)
                  for (final t in teams)
                    SetRow(LucideIcons.trophy, C.dialStrain, t.name,
                        switchValue: chosen.contains(t.id),
                        onTap: () => setS(() => chosen.contains(t.id)
                            ? chosen.remove(t.id)
                            : chosen.add(t.id))),
                const SizedBox(height: S.x3),
                BigButton('Post', busy: busy, onTap: chosen.isEmpty
                    ? null
                    : () async {
                        setS(() => busy = true);
                        try {
                          await _svc.post(chosen.toList(), bytes, caption.text,
                              mime: mime);
                          if (s.mounted) Navigator.of(s).pop(true);
                        } catch (e) {
                          setS(() => busy = false);
                          if (s.mounted) _say(s, communityError(e));
                        }
                      }),
              ],
            ),
          ),
        );
      },
    ),
  );
  caption.dispose();
  if (posted == true && c.mounted) _say(c, 'Posted');
  return posted == true;
}

// ── the chat ──

class _Chat extends StatefulWidget {
  final CommunityTeam team;
  final Map<String, CommunityProfile> people;
  const _Chat({required this.team, required this.people});

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage>? _msgs;
  String? _error;
  StreamSubscription<ChatMessage>? _sub;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _svc.viewingChat = widget.team.id;
    _sub = _svc.newMessages.listen((m) {
      if (m.teamId != widget.team.id || !mounted) return;
      final list = _msgs ?? <ChatMessage>[];
      if (list.any((x) => x.id == m.id)) return;
      setState(() => _msgs = [...list, m]);
      _down();
      _svc.markRead(widget.team.id);
    });
    _load();
    _svc.markRead(widget.team.id);
  }

  @override
  void dispose() {
    if (_svc.viewingChat == widget.team.id) _svc.viewingChat = null;
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await _svc.messages(widget.team.id);
      if (!mounted) return;
      setState(() => _msgs = m);
      _down();
    } catch (e) {
      if (mounted) setState(() => _error = communityError(e));
    }
  }

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _svc.send(widget.team.id, text);
      _input.clear();
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _hold(ChatMessage m) async {
    final c = context;
    final mine = m.userId == _svc.myId;
    final who = widget.people[m.userId]?.name ?? 'them';
    final pick = await AppSheet.show<String>(c,
        child: Column(children: [
          SetRow(LucideIcons.copy, C.dialStrain, 'Copy',
              onTap: () => Navigator.of(c).pop('copy')),
          if (mine)
            SetRow(LucideIcons.trash2, C.dialStrain, 'Delete',
                danger: true, onTap: () => Navigator.of(c).pop('delete'))
          else ...[
            SetRow(LucideIcons.flag, C.dialStrain, 'Report the message',
                onTap: () => Navigator.of(c).pop('report')),
            SetRow(LucideIcons.circleSlash, C.dialStrain, 'Block $who',
                danger: true, onTap: () => Navigator.of(c).pop('block')),
          ],
        ]));
    if (!mounted) return;
    try {
      switch (pick) {
        case 'copy':
          await Clipboard.setData(ClipboardData(text: m.body));
        case 'delete':
          await _svc.deleteMessage(m.id);
          setState(() => _msgs = [for (final x in _msgs!) if (x.id != m.id) x]);
        case 'report':
          await _svc.report(teamId: m.teamId, messageId: m.id);
          if (mounted) _say(context, 'Reported. Thank you.');
        case 'block':
          await _svc.block(m.userId);
          setState(() =>
              _msgs = [for (final x in _msgs!) if (x.userId != m.userId) x]);
      }
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    }
  }

  @override
  Widget build(BuildContext c) {
    final msgs = _msgs;
    final me = _svc.myId;
    return Column(children: [
      Expanded(
        child: _error != null
            ? Padding(padding: const EdgeInsets.all(S.x4), child: ErrorLine(_error!))
            : msgs == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : msgs.isEmpty
                    ? const Center(child: NoData(message: 'No messages yet. Say hello.'))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x3),
                        itemCount: msgs.length,
                        itemBuilder: (_, i) {
                          final m = msgs[i];
                          final prev = i == 0 ? null : msgs[i - 1];
                          final first = prev == null ||
                              prev.userId != m.userId ||
                              m.at.difference(prev.at).inMinutes > 10;
                          final who = widget.people[m.userId];
                          return _Bubble(
                            m: m,
                            mine: m.userId == me,
                            name: first ? (who?.name ?? 'A member') : null,
                            hue: who?.hue ?? 0,
                            onHold: () => _hold(m),
                          );
                        },
                      ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(S.x4, S.x2, S.x4,
            S.x2 + MediaQuery.viewInsetsOf(c).bottom + MediaQuery.paddingOf(c).bottom),
        child: Row(children: [
          Expanded(
            child: AppField(
              controller: _input,
              hint: 'Message ${widget.team.name}',
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: S.x2),
          RoundIconButton(LucideIcons.send, _sending ? null : _send, 'Send'),
        ]),
      ),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage m;
  final bool mine;
  final String? name;
  final int hue;
  final VoidCallback onHold;
  const _Bubble(
      {required this.m,
      required this.mine,
      required this.name,
      required this.hue,
      required this.onHold});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final t = '${m.at.hour.toString().padLeft(2, '0')}:'
        '${m.at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.only(top: name != null ? S.x3 : S.half),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (name != null && !mine)
            Padding(
              padding: const EdgeInsets.only(left: S.x1, bottom: S.half),
              child: Text(name!,
                  style: F.cap.copyWith(
                      color: p.on(hueColor(hue)), fontWeight: FontWeight.w700)),
            ),
          Pressable(
            onTap: () {},
            onLongPress: onHold,
            semanticLabel: '${mine ? 'You' : name ?? 'A member'}: ${m.body}',
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(c).width * .78),
              padding:
                  const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
              decoration: BoxDecoration(
                color: mine ? C.dialStrain.withValues(alpha: .28) : p.card2,
                borderRadius: R.rLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(m.body, style: F.body.copyWith(color: p.ink, height: 1.35)),
                  Text(t, style: F.over.copyWith(color: p.ink3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── info ──

class _Info extends StatelessWidget {
  final CommunityTeam team;
  final Map<String, CommunityProfile> people;
  final List<DayScore> scores;
  const _Info({required this.team, required this.people, required this.scores});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final list = people.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ListView(
      padding: EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.navClear(c)),
      children: [
        if (!team.isOpen) ...[
          Surface(
            child: Column(children: [
              Text('TEAM CODE',
                  style: F.over.copyWith(color: p.ink3, letterSpacing: 1.6)),
              const SizedBox(height: S.x2),
              SelectableText(team.code,
                  style: F.t1.copyWith(color: p.ink, letterSpacing: 8)),
              const SizedBox(height: S.x2),
              Text('Anyone with this code can join.',
                  style: F.cap.copyWith(color: p.ink3)),
              const SizedBox(height: S.x3),
              BigButton('Invite', icon: LucideIcons.share2, compact: true,
                  onTap: () => Share.share(
                      'Join my team "${team.name}" in Locus: open Community, '
                      'Join with a code, and enter ${team.code}.')),
            ]),
          ),
        ] else
          Text(
            'Everyone who uses the community is here, and only the leaderboard '
            'is: no chat and no feed. Leave it from the menu above.',
            style: F.body.copyWith(color: p.ink2, height: 1.45),
          ),
        settingsGroup(c, '${list.length} ${list.length == 1 ? 'member' : 'members'}', [
          for (final who in list.take(team.isOpen ? 50 : 500))
            SetRow(LucideIcons.userRound, C.dialStrain, who.name,
                sub: who.id == _svc.myId
                    ? 'You'
                    : who.sharesAnything
                        ? 'Shares ${[
                            if (who.shareRecovery) 'recovery',
                            if (who.shareStrain) 'strain',
                            if (who.shareSleep) 'sleep',
                          ].join(', ')}'
                        : 'Shares nothing yet',
                trailing: CommunityAvatar(who.name, who.hue, size: S.x8),
                onTap: () => go(
                    c,
                    MemberProfile(who: who, scores: [
                      for (final s in scores)
                        if (s.userId == who.id) s,
                    ]))),
        ]),
      ],
    );
  }
}
