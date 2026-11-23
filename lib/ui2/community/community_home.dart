part of 'community.dart';

// The Community tab: privacy and search up top, Find your humans, My Teams
// with each team's rank (or its size), Humans, then recommended teams. The
// user's screenshots merged with the reference's rank display (refs 0.6-0.8,
// 10.2-10.4, humans_1, humans_7).

class CommunityScreen extends StatefulWidget {
  /// Shown as a tab of its own: no back arrow.
  final bool tab;
  const CommunityScreen({super.key, this.tab = false});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<TeamPreview> _recommended = const [];
  Map<String, ({int? rank, int of})> _ranks = const {};
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_changed);
    unawaited(_svc.ensureReady().then((_) => _reload()));
  }

  @override
  void dispose() {
    _svc.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  BoardMetric get _rankMetric => BoardMetric.values.firstWhere(
      (m) => m.name == Prefs.getString(CommunityService.kRankMetric, 'strain'),
      orElse: () => BoardMetric.strain);
  BoardPeriod get _rankPeriod => BoardPeriod.values.firstWhere(
      (m) => m.name == Prefs.getString(CommunityService.kRankRange, 'day'),
      orElse: () => BoardPeriod.day);

  Future<void> _reload() async {
    if (!mounted) return;
    _attachRepo(context);
    if (!_svc.signedIn) {
      setState(() => _loadedOnce = true);
      return;
    }
    await _svc.refresh();
    try {
      final rec = await _svc.publicTeams(limit: 10);
      final (from, to) = _rankPeriod.window(DateTime.now());
      final ranks = await _svc.myRanks(_rankMetric, from, to);
      if (!mounted) return;
      setState(() {
        _recommended = [for (final t in rec) if (!t.joined) t];
        _ranks = ranks;
      });
    } catch (e) {
      debugPrint('community home: $e');
    }
    if (mounted) setState(() => _loadedOnce = true);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    if (_svc.ready && _loadedOnce && !_svc.signedIn) {
      return Scaffold(
        backgroundColor: p.bg,
        body: _CommunityIntro(onDone: _reload),
      );
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _topBar(c),
          Expanded(
            child: !_loadedOnce
                ? const Center(child: CircularProgressIndicator.adaptive())
                : RefreshIndicator.adaptive(
                    onRefresh: _reload,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                          S.gutter, S.x4, S.gutter, S.navClear(c)),
                      children: [
                        _FindHumansCard(
                            onSearch: () => go(c, const _SearchMembersScreen())),
                        const SizedBox(height: S.x8),
                        Divider(color: p.line, height: S.hair),
                        const SizedBox(height: S.x6),
                        ..._myTeams(c),
                        const SizedBox(height: S.x6),
                        Divider(color: p.line, height: S.hair),
                        const SizedBox(height: S.x6),
                        _HumansRow(onTap: () => go(c, const _HumansScreen())),
                        if (_recommended.isNotEmpty) ...[
                          const SizedBox(height: S.x6),
                          Divider(color: p.line, height: S.hair),
                          const SizedBox(height: S.x6),
                          ..._recommendedRow(c),
                        ],
                      ],
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _topBar(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x3),
      child: SizedBox(
        height: S.x16,
        child: Row(children: [
          if (!widget.tab)
            Pressable(
              onTap: () => Navigator.maybePop(c),
              semanticLabel: 'Back',
              child: SizedBox.square(
                  dimension: S.x12,
                  child: Icon(LucideIcons.chevronLeft, size: I.xl, color: p.ink)),
            ),
          Pressable(
            onTap: () => go(c, const _PrivacyScreen()),
            semanticLabel: 'Privacy',
            child: SizedBox.square(
              dimension: S.x12,
              child: Stack(alignment: Alignment.center, children: [
                Icon(LucideIcons.eye, size: I.xl, color: p.ink),
                Positioned(
                  right: S.x1,
                  bottom: S.x2,
                  child: Container(
                    decoration: BoxDecoration(color: p.bg, shape: BoxShape.circle),
                    child: Icon(LucideIcons.settings, size: I.sm, color: p.ink),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: Text('COMMUNITY',
                textAlign: TextAlign.center,
                style: F.caps.copyWith(
                    color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 2)),
          ),
          if (!widget.tab) const SizedBox(width: S.x12),
          Pressable(
            onTap: () => go(c, const _SearchMembersScreen()),
            semanticLabel: 'Search members',
            child: SizedBox.square(
                dimension: S.x12,
                child: Icon(LucideIcons.search, size: I.xl, color: p.ink)),
          ),
        ]),
      ),
    );
  }

  List<Widget> _myTeams(BuildContext c) {
    final p = P.of(c);
    final teams = _svc.teams;
    return [
      Row(children: [
        Expanded(child: Text('My Teams', style: F.t1.copyWith(color: p.ink))),
        Pressable(
          onTap: () => go(c, const _ExploreTeamsScreen()),
          semanticLabel: 'Search for teams',
          child: SizedBox(
            height: S.tap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _label(c, 'Search for teams'),
              const SizedBox(width: S.x2),
              Icon(LucideIcons.arrowRight, size: I.md, color: p.ink),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: S.x3),
      if (teams.isEmpty) ...[
        _label(c, 'Getting started', color: p.ink3),
        const SizedBox(height: S.x3),
        _actionRow(c, LucideIcons.users, 'Enter invite code',
            () => go(c, const _JoinByCodeScreen())),
        const SizedBox(height: S.x2),
        _actionRow(c, LucideIcons.circlePlus, 'Create team',
            () => go(c, const _CreateTeamFlow())),
      ] else ...[
        Pressable(
          onTap: () => _rankSheet(c),
          semanticLabel: 'Choose how ranks show',
          child: SizedBox(
            height: S.tap,
            child: Row(children: [
              Expanded(child: _label(c, 'My teams', color: p.ink3)),
              _label(c, _rankTitle),
              const SizedBox(width: S.x1),
              Icon(LucideIcons.chevronDown, size: I.md, color: p.ink),
            ]),
          ),
        ),
        const SizedBox(height: S.x2),
        for (final t in teams) ...[
          _TeamRow(t, rank: _ranks[t.id], onTap: () => _open(c, t)),
          const SizedBox(height: S.x3),
        ],
        Row(children: [
          Expanded(
            child: BigButton('Enter code',
                icon: LucideIcons.users,
                soft: true,
                compact: true,
                fill: true,
                onTap: () => go(c, const _JoinByCodeScreen())),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: BigButton('Create team',
                icon: LucideIcons.circlePlus,
                soft: true,
                compact: true,
                fill: true,
                onTap: () => go(c, const _CreateTeamFlow())),
          ),
        ]),
      ],
    ];
  }

  String get _rankTitle {
    final m = switch (_rankMetric) {
      BoardMetric.strain => 'strain',
      BoardMetric.recovery => 'recovery',
      BoardMetric.sleep => 'sleep',
    };
    final r = switch (_rankPeriod) {
      BoardPeriod.day => 'Daily',
      BoardPeriod.week => 'Weekly',
      BoardPeriod.month => 'Monthly',
    };
    return '$r $m rank';
  }

  Future<void> _open(BuildContext c, CommunityTeam t) async {
    await Navigator.of(c).push(themedRoute((_) => TeamScreen(team: t),
        name: 'TeamScreen'));
    if (mounted) unawaited(_reload());
  }

  Future<void> _rankSheet(BuildContext c) async {
    final picked = await AppSheet.open<(BoardMetric, BoardPeriod)>(
      c,
      dragHandle: true,
      builder: (s) => _RankDisplaySheet(metric: _rankMetric, period: _rankPeriod),
    );
    if (picked == null) return;
    Prefs.setString(CommunityService.kRankMetric, picked.$1.name);
    Prefs.setString(CommunityService.kRankRange, picked.$2.name);
    await _reload();
  }

  List<Widget> _recommendedRow(BuildContext c) {
    final p = P.of(c);
    return [
      Row(children: [
        Expanded(child: _label(c, 'Recommended teams', color: p.ink3)),
        Pressable(
          onTap: () => go(c, const _ExploreTeamsScreen()),
          semanticLabel: 'View all teams',
          child: SizedBox(
            height: S.tap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _label(c, 'View all'),
              const SizedBox(width: S.x2),
              Icon(LucideIcons.arrowRight, size: I.md, color: p.ink),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: S.x3),
      SizedBox(
        height: S.x16 * 3.4,
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          children: [
            for (final t in _recommended) ...[
              _TeamCard(t, onTap: () => go(c, _TeamDetailsScreen(teamId: t.id))),
              const SizedBox(width: S.x3),
            ],
            _DiscoverCard(onTap: () => go(c, const _ExploreTeamsScreen())),
          ],
        ),
      ),
    ];
  }
}

Widget _actionRow(BuildContext c, IconData icon, String text, VoidCallback onTap) {
  final p = P.of(c);
  return _cardRow(
    c,
    onTap: onTap,
    label: text,
    padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x5),
    child: Row(children: [
      Icon(icon, size: I.lg, color: p.ink3),
      const SizedBox(width: S.x4),
      _label(c, text),
    ]),
  );
}

/// "Find your humans": the way into following people (humans_1).
class _FindHumansCard extends StatelessWidget {
  final VoidCallback onSearch;
  const _FindHumansCard({required this.onSearch});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      padding: const EdgeInsets.fromLTRB(S.x6, S.x8, S.x6, S.x8),
      decoration: BoxDecoration(
        borderRadius: R.rXxl,
        border: Border.all(color: p.line, width: S.half),
      ),
      child: Column(children: [
        const _HighFive(),
        const SizedBox(height: S.x5),
        Text('Find your humans', style: F.t2.copyWith(color: p.ink)),
        const SizedBox(height: S.x3),
        Text(
          'See the daily numbers of the people you care about and support '
          'healthier habits together.',
          textAlign: TextAlign.center,
          style: F.body.copyWith(color: p.ink2, height: 1.45),
        ),
        const SizedBox(height: S.x5),
        BigButton('Search members',
            icon: LucideIcons.search, compact: true, fill: true, onTap: onSearch),
      ]),
    );
  }
}

/// Two hands meeting, with a few ticks of joy around them.
class _HighFive extends StatelessWidget {
  const _HighFive();

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const d = S.x16 + S.x8;
    return SizedBox.square(
      dimension: d,
      child: CustomPaint(
        painter: _Sparks(C.rose),
        child: Center(
          child: Icon(LucideIcons.heartHandshake, size: I.hero, color: p.ink3),
        ),
      ),
    );
  }
}

class _Sparks extends CustomPainter {
  final Color color;
  const _Sparks(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = color
      ..strokeWidth = S.half
      ..strokeCap = StrokeCap.round;
    for (final a in [-150.0, -120, -90, -60, -30, -170, -10]) {
      final r = a * math.pi / 180;
      final dir = Offset(math.cos(r), math.sin(r));
      canvas.drawLine(c + dir * size.width * .36, c + dir * size.width * .44, p);
    }
  }

  @override
  bool shouldRepaint(_Sparks o) => o.color != color;
}

/// One of my teams: logo, name, and my rank in it (or its size).
class _TeamRow extends StatelessWidget {
  final CommunityTeam team;
  final ({int? rank, int of})? rank;
  final VoidCallback onTap;
  const _TeamRow(this.team, {this.rank, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = rank;
    final (String big, String small) = r?.rank != null
        ? (ordinal(r!.rank!), 'of ${groupThousands(r.of, compact: true)}')
        : (
            groupThousands(team.members ?? 0, compact: true),
            team.members == 1 ? 'Member' : 'Members',
          );
    return _cardRow(
      c,
      onTap: onTap,
      label: team.name,
      child: Row(children: [
        TeamLogo(team.logo, size: S.x12),
        const SizedBox(width: S.x4),
        Expanded(
          child: Text(team.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.body.copyWith(
                  color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ),
        if (team.unread > 0) ...[
          Pill('${team.unread > 99 ? '99+' : team.unread} new', C.dialStrain),
          const SizedBox(width: S.x2),
        ],
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(big, style: F.head.copyWith(color: p.ink)),
          Text(small, style: F.cap.copyWith(color: p.ink3)),
        ]),
      ]),
    );
  }
}

/// A public team as a tall card: its banner, logo, name and size.
class _TeamCard extends StatelessWidget {
  final TeamPreview team;
  final VoidCallback onTap;
  final double width;
  const _TeamCard(this.team, {required this.onTap, this.width = S.x16 * 2.9});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: team.name,
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: p.card, borderRadius: R.rMd),
        child: Stack(fit: StackFit.expand, children: [
          Opacity(opacity: .55, child: TeamBanner(team.banner)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.bg.withValues(alpha: 0), p.bg.withValues(alpha: .7)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(S.x3),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              TeamLogo(team.logo, size: S.x16),
              const SizedBox(height: S.x3),
              Text(team.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: F.head.copyWith(
                      color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
              const SizedBox(height: S.x1),
              Text('${groupThousands(team.members)} members'.toUpperCase(),
                  style: F.over.copyWith(color: p.ink2, letterSpacing: 1)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  final VoidCallback onTap;
  const _DiscoverCard({required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Discover more teams',
      child: Container(
        width: S.x16 * 2.9,
        decoration: BoxDecoration(color: p.card, borderRadius: R.rMd),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(LucideIcons.search, size: I.hero, color: p.ink3),
          const SizedBox(height: S.x4),
          Text('DISCOVER\nMORE',
              textAlign: TextAlign.center,
              style: F.head.copyWith(
                  color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
        ]),
      ),
    );
  }
}

/// The Humans door: people I follow and who follow me.
class _HumansRow extends StatelessWidget {
  final VoidCallback onTap;
  const _HumansRow({required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final n = _svc.requests.length;
    return _cardRow(
      c,
      onTap: onTap,
      label: 'Humans',
      padding: const EdgeInsets.symmetric(horizontal: S.x5, vertical: S.x5),
      child: Row(children: [
        Icon(LucideIcons.users, size: I.xl, color: p.ink3),
        const SizedBox(width: S.x5),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(c, 'Humans'),
            const SizedBox(height: S.half),
            Text('Manage your followers and who you are following',
                style: F.body.copyWith(color: p.ink2)),
          ]),
        ),
        if (n > 0) Pill('$n', C.dialStrain),
      ]),
    );
  }
}

/// DISPLAY RANK AS… and OVER THE COURSE OF…, then Apply (refs 10.2-10.3).
class _RankDisplaySheet extends StatefulWidget {
  final BoardMetric metric;
  final BoardPeriod period;
  const _RankDisplaySheet({required this.metric, required this.period});

  @override
  State<_RankDisplaySheet> createState() => _RankDisplaySheetState();
}

class _RankDisplaySheetState extends State<_RankDisplaySheet> {
  late var _metric = widget.metric;
  late var _period = widget.period;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final now = DateTime.now();
    final (wf, wt) = BoardPeriod.week.window(now);
    String dm(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    final options = [
      (BoardPeriod.day, 'Today'),
      (BoardPeriod.week, 'This week (${dm(wf)} – ${dm(wt)})'),
      (BoardPeriod.month, 'This month (${months[now.month - 1]})'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label(c, 'Display rank as…', color: p.ink3),
            const SizedBox(height: S.x3),
            RangeSegments(
              const ['DAY STRAIN', 'RECOVERY', 'SLEEP'],
              _metric.index,
              (i) => setState(() => _metric = BoardMetric.values[i]),
              width: null,
            ),
            const SizedBox(height: S.x6),
            _label(c, 'Over the course of…', color: p.ink3),
            const SizedBox(height: S.x2),
            for (final (v, text) in options)
              _Radio(text, v == _period, () => setState(() => _period = v)),
            const SizedBox(height: S.x4),
            BigButton('Apply',
                onTap: () => Navigator.of(c).pop((_metric, _period))),
          ],
        ),
      ),
    );
  }
}

/// One choice of a set: a ring that fills when chosen, and its words.
class _Radio extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback onTap;
  const _Radio(this.text, this.on, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: text,
      child: SizedBox(
        height: S.x12,
        child: Row(children: [
          Container(
            width: S.x8,
            height: S.x8,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? p.ink : null,
              border: Border.all(color: p.ink, width: S.half),
            ),
            child: on
                ? Container(
                    width: S.x2,
                    height: S.x2,
                    decoration: BoxDecoration(color: p.bg, shape: BoxShape.circle))
                : null,
          ),
          const SizedBox(width: S.x4),
          Expanded(child: _label(c, text, color: on ? p.ink : p.ink2)),
        ]),
      ),
    );
  }
}

/// Every public team, searchable by name (Explore teams).
class _ExploreTeamsScreen extends StatefulWidget {
  const _ExploreTeamsScreen();

  @override
  State<_ExploreTeamsScreen> createState() => _ExploreTeamsScreenState();
}

class _ExploreTeamsScreenState extends State<_ExploreTeamsScreen> {
  final _q = TextEditingController();
  List<TeamPreview>? _teams;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await _svc.publicTeams(query: _q.text, limit: 60);
      if (mounted) setState(() => _teams = t);
    } catch (e) {
      if (mounted) {
        setState(() => _teams = const []);
        _say(context, communityError(e));
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final teams = _teams;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Explore teams'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x3),
            child: AppField(
              controller: _q,
              hint: 'Search teams',
              semanticLabel: 'Search teams',
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(Motion.slow, _load);
              },
            ),
          ),
          Expanded(
            child: teams == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : teams.isEmpty
                    ? Center(
                        child: Text('No public teams match.',
                            style: F.body.copyWith(color: p.ink3)))
                    : GridView.count(
                        padding: const EdgeInsets.fromLTRB(
                            S.gutter, 0, S.gutter, S.x8),
                        crossAxisCount: 2,
                        mainAxisSpacing: S.x3,
                        crossAxisSpacing: S.x3,
                        childAspectRatio: .86,
                        children: [
                          for (final t in teams)
                            _TeamCard(t,
                                width: double.infinity,
                                onTap: () => go(c, _TeamDetailsScreen(teamId: t.id))),
                        ],
                      ),
          ),
        ]),
      ),
    );
  }
}
