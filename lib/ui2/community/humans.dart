part of 'community.dart';

// Humans: who I follow and who follows me, with requests to answer
// (humans_1-3), searching for people (humans_2), and the privacy page with
// its search and data settings (humans_4-5).

class _HumansScreen extends StatefulWidget {
  const _HumansScreen();

  @override
  State<_HumansScreen> createState() => _HumansScreenState();
}

class _HumansScreenState extends State<_HumansScreen> {
  var _tab = 0;
  List<Human> _following = const [], _followers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = _svc.myId;
    if (me == null) return;
    try {
      final a = await _svc.followList(me, 'following');
      final b = await _svc.followList(me, 'followers');
      _svc.requests = [for (final h in b) if (h.requested) h];
      if (!mounted) return;
      setState(() {
        _following = a;
        _followers = [for (final h in b) if (!h.requested) h];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _say(context, communityError(e));
      }
    }
  }

  Future<void> _answer(Human h, bool yes) async {
    try {
      yes ? await _svc.accept(h.id) : await _svc.removeFollower(h.id);
      await _load();
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    }
  }

  Future<void> _rowMenu(Human h, bool follower) async {
    final ok = await _confirm(
      context,
      follower ? 'REMOVE FOLLOWER?' : 'UNFOLLOW?',
      follower
          ? '${h.name} stops seeing your numbers. They are not told.'
          : 'You stop seeing ${h.name}\'s numbers.',
      follower ? 'Remove' : 'Unfollow',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      follower ? await _svc.removeFollower(h.id) : await _svc.unfollow(h.id);
      await _load();
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final requests = _svc.requests;
    final list = _tab == 0 ? _following : _followers;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Humans',
                trailing: Pressable(
                  onTap: () => go(c, const _SearchMembersScreen()),
                  semanticLabel: 'Search members',
                  child: SizedBox.square(
                      dimension: S.x12,
                      child: Icon(LucideIcons.search, size: I.lg, color: p.ink)),
                )),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x4),
            child: RangeSegments(
              [
                'Following (${_following.length})',
                'Followers (${_followers.length})',
              ],
              _tab,
              (i) => setState(() => _tab = i),
              width: null,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : RefreshIndicator.adaptive(
                    onRefresh: _load,
                    child: ListView(
                      padding:
                          const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x8),
                      children: [
                        if (requests.isNotEmpty) ...[
                          _label(c, 'Requests (${requests.length})', color: p.ink2),
                          const SizedBox(height: S.x3),
                          for (final h in requests) ...[
                            _HumanRow(h,
                                rings: false,
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  _RingButton(LucideIcons.check, 'Accept ${h.name}',
                                      () => _answer(h, true)),
                                  const SizedBox(width: S.x2),
                                  _RingButton(LucideIcons.x, 'Decline ${h.name}',
                                      () => _answer(h, false)),
                                ])),
                            const SizedBox(height: S.x2),
                          ],
                          const SizedBox(height: S.x4),
                        ],
                        if (list.isEmpty)
                          _FindHumansCard(
                              onSearch: () => go(c, const _SearchMembersScreen()))
                        else
                          for (final h in list) ...[
                            _HumanRow(h,
                                key: ValueKey('$_tab ${h.id}'),
                                rings: _tab == 0,
                                onLongPress: () => _rowMenu(h, _tab == 1)),
                            const SizedBox(height: S.x2),
                          ],
                      ],
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// A person in a list: picture, name and handle, today's rings for those I
/// follow, or [trailing]. Tapping opens their profile.
class _HumanRow extends StatefulWidget {
  final Human h;
  final bool rings;
  final Widget? trailing;
  final VoidCallback? onLongPress;
  const _HumanRow(this.h,
      {super.key, this.rings = false, this.trailing, this.onLongPress});

  @override
  State<_HumanRow> createState() => _HumanRowState();
}

class _HumanRowState extends State<_HumanRow> {
  DayScore? _today;

  @override
  void initState() {
    super.initState();
    if (widget.rings) _loadToday();
  }

  Future<void> _loadToday() async {
    try {
      final m = await _svc.member(widget.h.id, from: DateTime.now());
      final key = todayLabel();
      final t = m.days.where((d) => dayLabelOf(d.day) == key).firstOrNull;
      if (mounted) setState(() => _today = t);
    } catch (_) {
      // No rings: they share nothing today, or the network failed.
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final h = widget.h;
    final t = _today;
    final line = h.handleLine(DateTime.now());
    Widget mini(double? v, double top, Color ink) => Padding(
          padding: const EdgeInsets.only(left: S.x1),
          child: SizedBox.square(
            dimension: S.x6,
            child: CustomPaint(
              painter: _RingPainter(
                  color: v == null ? p.ink3 : ink,
                  track: p.track,
                  fill: v == null ? 0 : (v / top).clamp(0, 1),
                  stroke: S.half + S.hair),
            ),
          ),
        );
    return _cardRow(
        c,
        onTap: () => go(c, MemberProfile(userId: h.id, name: h.name, hue: h.hue)),
        onLongPress: widget.onLongPress,
        label: h.name,
        child: Row(children: [
          CommunityAvatar(h.name, h.hue, size: S.x10, photo: h.avatarPath),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.body.copyWith(
                      color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1)),
              if (line.isNotEmpty)
                Text(line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          ?widget.trailing,
          if (widget.trailing == null && t != null) ...[
            mini(t.sleepPerf, 100, C.dialSleep),
            mini(t.recovery, 100, _recoveryInk(t.recovery ?? 0)),
            mini(t.strain, 21, C.dialStrain),
          ],
        ]),
    );
  }
}

/// SEARCH MEMBERS: by name or @username, with a follow button on each.
class _SearchMembersScreen extends StatefulWidget {
  const _SearchMembersScreen();

  @override
  State<_SearchMembersScreen> createState() => _SearchMembersScreenState();
}

class _SearchMembersScreenState extends State<_SearchMembersScreen> {
  final _q = TextEditingController();
  Timer? _wait;
  List<Human> _found = const [];
  bool _searching = false;
  final _busy = <String>{};

  @override
  void dispose() {
    _wait?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _wait?.cancel();
    _wait = Timer(Motion.slow, () => _search(q));
  }

  Future<void> _search(String q) async {
    if (!await _ensureSignedIn(context) || !mounted) return;
    setState(() => _searching = true);
    try {
      final r = await _svc.search(q.replaceFirst('@', ''));
      if (mounted && _q.text == q) setState(() => _found = r);
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _follow(Human h) async {
    setState(() => _busy.add(h.id));
    try {
      if (h.following_ || h.requested) {
        await _svc.unfollow(h.id);
      } else {
        await _svc.follow(h.id);
      }
      final again = await _svc.human(h.id);
      if (mounted && again != null) {
        setState(() =>
            _found = [for (final x in _found) x.id == h.id ? again : x]);
      }
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(h.id));
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final me = _svc.myId;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Search members')),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x4),
            child: AppField(
              controller: _q,
              hint: 'Name or @username',
              semanticLabel: 'Search members',
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _changed,
              onSubmitted: _search,
            ),
          ),
          Expanded(
            child: _searching && _found.isEmpty
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _found.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(S.gutter),
                        child: Text(
                            _q.text.trim().length < 2
                                ? 'Type at least two letters of a name or username.'
                                : 'Nobody found. People can hide from search in '
                                    'their privacy settings.',
                            textAlign: TextAlign.center,
                            style: F.body.copyWith(color: p.ink3)),
                      )
                    : ListView(
                        padding:
                            const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x8),
                        children: [
                          for (final h in _found) ...[
                            _HumanRow(h,
                                trailing: h.id == me
                                    ? Text('You', style: F.cap.copyWith(color: p.ink3))
                                    : BigButton(
                                        h.following_
                                            ? 'Following'
                                            : h.requested
                                                ? 'Requested'
                                                : h.followsMe
                                                    ? 'Follow back'
                                                    : 'Follow',
                                        compact: true,
                                        soft: h.following_ || h.requested,
                                        busy: _busy.contains(h.id),
                                        onTap: () => _follow(h))),
                            const SizedBox(height: S.x2),
                          ],
                        ],
                      ),
          ),
        ]),
      ),
    );
  }
}

// ── privacy ─────────────────────────────────────────────────────────────────

const _metricNames = {
  'sleep': 'Sleep',
  'recovery': 'Recovery',
  'strain': 'Strain',
  'activities': 'Activities',
  'age': 'Locus Age',
  'achievements': 'Achievements',
};

/// PRIVACY: who finds me and sees my profile, what followers see of each
/// metric, and the account itself.
class _PrivacyScreen extends StatefulWidget {
  const _PrivacyScreen();

  @override
  State<_PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<_PrivacyScreen> {
  Future<void> _save(Map<String, Object?> f) async {
    try {
      await _svc.updateProfile(f);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    }
  }

  Future<void> _audience(String title, String column, Audience now,
      {bool withAll = true}) async {
    final pick = await AppSheet.open<Audience>(
      context,
      dragHandle: true,
      builder: (s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(s, title, color: P.of(s).ink2),
              const SizedBox(height: S.x2),
              for (final a in Audience.values)
                if (withAll || a != Audience.all)
                  _Radio(a.label, a == now, () => Navigator.of(s).pop(a)),
            ],
          ),
        ),
      ),
    );
    if (pick != null && pick != now) await _save({column: pick.name});
  }

  Future<String?> _askText(String title, String? now, {int max = 40}) async {
    final t = TextEditingController(text: now ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AppDialog(
        title: title,
        content: AppField(
            controller: t, maxLength: max, autofocus: true, semanticLabel: title),
        actions: [
          BigButton('Cancel', soft: true, compact: true, fill: true,
              onTap: () => Navigator.of(d).pop()),
          BigButton('Save', compact: true, fill: true,
              onTap: () => Navigator.of(d).pop(t.text.trim())),
        ],
      ),
    );
    t.dispose();
    return r;
  }

  Future<void> _photo() async {
    try {
      final f = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
      if (f == null || !mounted) return;
      final b = await f.readAsBytes();
      if (!mounted) return;
      await _busy(context, 'Saving', () => _svc.setAvatar(b));
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) _say(context, 'Could not open your pictures.');
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await _confirm(
      context,
      'DELETE ACCOUNT?',
      'Your community profile, teams you own, messages and shared numbers '
          'are deleted for good. Your data on this phone stays.',
      'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    final done = await _busy(context, 'Deleting', () async {
      await _svc.deleteAccount();
      return true;
    });
    if (done == true && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final me = _svc.profile;
    if (me == null) {
      return Scaffold(
        backgroundColor: p.bg,
        body: const SafeArea(
          child: Padding(
              padding: EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Privacy')),
        ),
      );
    }
    SetRow row(IconData icon, String title, String value, VoidCallback onTap) =>
        SetRow(icon, p.ink, title, value: value, onTap: onTap);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Privacy')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x10),
              children: [
                Text(
                  'Choose who can find you, what your profile shows and what '
                  'your followers see. Teams see what their boards share, '
                  'whatever you set here.',
                  style: F.body.copyWith(color: p.ink2, height: 1.45),
                ),
                settingsGroup(c, 'Search settings', [
                  row(LucideIcons.search, 'Searchable by', me.searchable.label,
                      () => _audience('Who can find you', 'searchable', me.searchable)),
                  row(LucideIcons.cake, 'Age', me.showAge.label,
                      () => _audience('Who sees your age', 'show_age', me.showAge)),
                  row(LucideIcons.mapPin, 'Region',
                      me.region?.isNotEmpty == true
                          ? '${me.region} · ${me.showRegion.label}'
                          : 'Not set', () async {
                    final r = await _askText('Region', me.region);
                    if (r == null || !mounted) return;
                    await _save({'region': r.isEmpty ? null : r});
                    if (r.isNotEmpty && mounted) {
                      await _audience(
                          'Who sees your region', 'show_region', me.showRegion);
                    }
                  }),
                  row(LucideIcons.users, 'Follower lists', me.showLists.label,
                      () => _audience('Who sees who you follow', 'show_lists',
                          me.showLists)),
                  row(LucideIcons.camera, 'Profile photo', me.showPhoto.label,
                      () => _audience('Who sees your photo', 'show_photo',
                          me.showPhoto)),
                  SetRow(LucideIcons.userCheck, p.ink, 'Mutual following',
                      sub: 'Accepting a request follows them back',
                      switchValue: me.mutualFollow,
                      onTap: () => _save({'mutual_follow': !me.mutualFollow})),
                ]),
                settingsGroup(c, 'Data settings', [
                  for (final k in kPrivacyMetrics)
                    row(
                      _metricIcon(k),
                      _metricNames[k]!,
                      me.privacyOf(k).followers ? 'Followers' : 'No One',
                      () => AppSheet.open<void>(
                        c,
                        dragHandle: true,
                        scroll: true,
                        builder: (_) => _MetricPrivacySheet(k),
                      ).then((_) {
                        if (mounted) setState(() {});
                      }),
                    ),
                ]),
                const SizedBox(height: S.x4),
                _label(c, 'Never shared', color: p.ink3),
                const SizedBox(height: S.x2),
                Text(
                  'Your raw heart data, health notes, journal, location and '
                  'routes, and anything you mark private stay on this phone.',
                  style: F.cap.copyWith(color: p.ink3, height: 1.45),
                ),
                settingsGroup(c, 'Account', [
                  row(LucideIcons.userRound, 'Name', me.name, () async {
                    final r = await _askText('Name', me.name);
                    if (r != null && r.isNotEmpty) await _save({'display_name': r});
                  }),
                  row(LucideIcons.atSign, 'Username', me.username ?? 'Not set',
                      () async {
                    final r = await _askText('Username', me.username, max: 24);
                    if (r == null) return;
                    final u = r.replaceFirst('@', '').toLowerCase();
                    if (u.isNotEmpty && !RegExp(r'^[a-z0-9_.]{3,24}$').hasMatch(u)) {
                      if (mounted) {
                        _say(context,
                            'Use 3 to 24 letters, numbers, dots or underscores.');
                      }
                      return;
                    }
                    await _save({'username': u.isEmpty ? null : u});
                  }),
                  row(LucideIcons.image, 'Photo',
                      me.avatarPath == null ? 'None' : 'Set', _photo),
                  if (!_svc.anonymous)
                    SetRow(LucideIcons.logOut, p.ink, 'Sign out', onTap: () async {
                      await _svc.signOut();
                      if (mounted) Navigator.of(context).maybePop();
                    }),
                  SetRow(LucideIcons.trash2, p.ink, 'Delete account',
                      danger: true, onTap: _deleteAccount),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

IconData _metricIcon(String k) => switch (k) {
      'sleep' => LucideIcons.moon,
      'recovery' => LucideIcons.heartPulse,
      'strain' => LucideIcons.activity,
      'activities' => LucideIcons.dumbbell,
      'age' => LucideIcons.hourglass,
      _ => LucideIcons.medal,
    };

/// One metric's setting: No One or Followers, and with followers whether the
/// daily values and the weekly trends go too (humans_5).
class _MetricPrivacySheet extends StatefulWidget {
  final String metric;
  const _MetricPrivacySheet(this.metric);

  @override
  State<_MetricPrivacySheet> createState() => _MetricPrivacySheetState();
}

class _MetricPrivacySheetState extends State<_MetricPrivacySheet> {
  late var _v = _svc.profile?.privacyOf(widget.metric) ?? const MetricPrivacy();
  bool _saving = false;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final name = _metricNames[widget.metric]!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${name.toUpperCase()} PRIVACY',
                textAlign: TextAlign.center,
                style: F.caps.copyWith(
                    color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 2)),
            const SizedBox(height: S.x2),
            Text('Who can see your ${name.toLowerCase()}?',
                textAlign: TextAlign.center,
                style: F.body.copyWith(color: p.ink2)),
            const SizedBox(height: S.x3),
            _Radio('No One', !_v.followers,
                () => setState(() => _v = _v.copyWith(followers: false))),
            _Radio('Followers', _v.followers,
                () => setState(() => _v = _v.copyWith(followers: true))),
            if (_v.followers) ...[
              const SizedBox(height: S.x2),
              Divider(color: p.line, height: S.hair),
              _switchRow(c, 'Include daily values', _v.daily,
                  (x) => setState(() => _v = _v.copyWith(daily: x))),
              _switchRow(c, 'Include weekly trends', _v.trends,
                  (x) => setState(() => _v = _v.copyWith(trends: x))),
            ],
            const SizedBox(height: S.x4),
            BigButton('Save', busy: _saving, onTap: () async {
              setState(() => _saving = true);
              try {
                await _svc.setPrivacy(widget.metric, _v);
                unawaited(_svc.uploadScores());
                if (c.mounted) Navigator.of(c).pop();
              } catch (e) {
                if (c.mounted) {
                  setState(() => _saving = false);
                  _say(c, communityError(e));
                }
              }
            }),
          ],
        ),
      ),
    );
  }
}
