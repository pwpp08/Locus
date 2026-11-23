part of 'community.dart';

// A team: its banner behind a header with its name, and the tabs INFO, CHAT
// (when the admin has it on), then one per board (refs 1.7-1.10, 6.11-6.14,
// humans_4-6). The ⋯ opens add members, manage (admins) and leave.

class TeamScreen extends StatefulWidget {
  final CommunityTeam team;

  /// Open on the first board rather than INFO: straight after joining.
  final bool openOnBoard;
  const TeamScreen({super.key, required this.team, this.openOnBoard = false});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

enum _Tab { info, chat, strain, recovery, sleep }

class _TeamScreenState extends State<TeamScreen> {
  late CommunityTeam _team = widget.team;
  late _Tab _tab = widget.openOnBoard && _tabs.length > 1 ? _firstBoard : _Tab.info;
  List<TeamPerson> _people = const [];

  List<_Tab> get _tabs => [
        _Tab.info,
        if (_team.hasChat) _Tab.chat,
        if (_team.boards.strain) _Tab.strain,
        if (_team.boards.recovery) _Tab.recovery,
        if (_team.boards.sleep) _Tab.sleep,
      ];

  _Tab get _firstBoard =>
      _tabs.firstWhere((t) => t.index >= _Tab.strain.index, orElse: () => _Tab.info);

  @override
  void initState() {
    super.initState();
    _svc.addListener(_changed);
    _loadPeople();
  }

  @override
  void dispose() {
    _svc.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final t = _svc.teams.where((t) => t.id == _team.id).firstOrNull;
    if (t != null && mounted) {
      setState(() {
        _team = t;
        if (!_tabs.contains(_tab)) _tab = _Tab.info;
      });
    }
  }

  Future<void> _loadPeople() async {
    try {
      final p = await _svc.people(_team.id);
      if (mounted) setState(() => _people = p);
    } catch (e) {
      debugPrint('team people: $e');
    }
  }

  Color _tabInk(_Tab t, P p) => switch (t) {
        _Tab.strain => C.dialStrain,
        _Tab.recovery => C.recGreen,
        _Tab.sleep => C.dialSleep,
        _ => p.ink,
      };

  Future<void> _menu() async {
    final c = context;
    final pick = await AppSheet.open<String>(
      c,
      dragHandle: true,
      builder: (s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!_team.isOpen) ...[
              _actionRow(s, LucideIcons.users, 'Add team members',
                  () => Navigator.of(s).pop('invite')),
              const SizedBox(height: S.x3),
            ],
            if (_team.isAdmin) ...[
              _actionRow(s, LucideIcons.pencil, 'Manage team',
                  () => Navigator.of(s).pop('manage')),
              const SizedBox(height: S.x3),
            ],
            if (!_team.isOwner)
              _actionRow(s, LucideIcons.logOut, 'Leave team',
                  () => Navigator.of(s).pop('leave')),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    switch (pick) {
      case 'invite':
        await _showInvite(context, _team);
      case 'manage':
        await Navigator.of(context).push(themedRoute(
            (_) => _ManageTeamScreen(team: _team, people: _people),
            name: 'ManageTeam'));
        if (!mounted) return;
        if (!_svc.teams.any((t) => t.id == _team.id)) {
          Navigator.of(context).maybePop();
        } else {
          unawaited(_loadPeople());
        }
      case 'leave':
        await _leave();
    }
  }

  Future<void> _leave() async {
    final ok = await _confirm(context, 'LEAVE TEAM?',
        'Your data will be removed from the team unless you rejoin.', 'Yes');
    if (!ok || !mounted) return;
    final done = await _busy(context, 'Leaving', () async {
      await _svc.leaveTeam(_team.id);
      return true;
    });
    if (done == true && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final tabs = _tabs;
    final bannerH = MediaQuery.sizeOf(c).height * (_tab == _Tab.info ? .36 : .34);
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        _Backdrop(TeamBanner(_team.banner),
            height: bannerH,
            strength: _tab == _Tab.info ? .95 : (_tab == _Tab.chat ? .3 : .6)),
        SafeArea(
          bottom: false,
          child: Column(children: [
            SizedBox(
              height: S.x16,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x3),
                child: Row(children: [
                  _RingButton(LucideIcons.chevronLeft, 'Back',
                      () => Navigator.maybePop(c)),
                  Expanded(
                    child: Text(_team.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.caps.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                  ),
                  _RingButton(LucideIcons.ellipsis, 'Team options', _menu),
                ]),
              ),
            ),
            SizedBox(
              height: S.x12,
              child: Row(children: [
                for (final t in tabs)
                  Expanded(
                    child: Pressable(
                      onTap: () => setState(() => _tab = t),
                      semanticLabel: t.name,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(t.name.toUpperCase(),
                                style: F.over.copyWith(
                                    color: t == _tab ? p.ink : p.ink2,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4)),
                          ),
                          const Spacer(),
                          AnimatedContainer(
                            duration: Motion.fast,
                            height: S.x1,
                            color: t == _tab ? _tabInk(t, p) : null,
                          ),
                        ],
                      ),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: switch (_tab) {
                _Tab.info => _InfoTab(
                    team: _team, people: _people, onChanged: _loadPeople),
                _Tab.chat => _ChatTab(team: _team, people: _people),
                _Tab.strain => _BoardTab(
                    key: const ValueKey('strain'),
                    team: _team,
                    people: _people,
                    metric: BoardMetric.strain),
                _Tab.recovery => _BoardTab(
                    key: const ValueKey('recovery'),
                    team: _team,
                    people: _people,
                    metric: BoardMetric.recovery),
                _Tab.sleep => _BoardTab(
                    key: const ValueKey('sleep'),
                    team: _team,
                    people: _people,
                    metric: BoardMetric.sleep),
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

/// INFO: logo and name, about, what it shares, and its people (7.4, 1.10).
class _InfoTab extends StatelessWidget {
  final CommunityTeam team;
  final List<TeamPerson> people;
  final Future<void> Function() onChanged;
  const _InfoTab({required this.team, required this.people, required this.onChanged});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final n = team.members ?? people.length;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          S.gutter, MediaQuery.sizeOf(c).height * .17, S.gutter, S.x10),
      children: [
        Row(children: [
          TeamLogo(team.logo, size: S.x16 + S.x2),
          const SizedBox(width: S.x5),
          Expanded(
            child: Text(team.name.toUpperCase(),
                style: F.t2.copyWith(
                    color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 2)),
          ),
        ]),
        const SizedBox(height: S.x8),
        _label(c, 'About'),
        const SizedBox(height: S.x2),
        if (team.description.isNotEmpty)
          Text(team.description, style: F.body.copyWith(color: p.ink2))
        else if (team.isAdmin)
          Align(
            alignment: Alignment.centerLeft,
            child: BigButton('Add description',
                compact: true,
                soft: true,
                onTap: () async {
                  await Navigator.of(c).push(themedRoute(
                      (_) => _ManageTeamScreen(team: team, people: people),
                      name: 'ManageTeam'));
                  await onChanged();
                }),
          )
        else
          _grey(c, 'No description yet.'),
        const SizedBox(height: S.x6),
        _label(c, 'Data sharing'),
        const SizedBox(height: S.x2),
        _grey(c, team.boards.words),
        const SizedBox(height: S.x6),
        _label(c, n == 1 ? '1 member' : '${groupThousands(n)} members'),
        const SizedBox(height: S.x3),
        if (!team.isOpen)
          Pressable(
            onTap: () => _showInvite(c, team),
            semanticLabel: 'Add members',
            child: SizedBox(
              height: S.x12,
              child: Row(children: [
                Container(
                  width: S.x10,
                  height: S.x10,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: C.dialStrain, width: S.half),
                  ),
                  child: Icon(LucideIcons.users, size: I.md, color: C.dialStrain),
                ),
                const SizedBox(width: S.x3),
                _label(c, 'Add members'),
              ]),
            ),
          ),
        for (final m in people) _PersonRow(m),
      ],
    );
  }
}

/// A team member: their avatar (ADMIN under it), name and handle.
class _PersonRow extends StatelessWidget {
  final TeamPerson m;
  final Widget? trailing;
  const _PersonRow(this.m, {this.trailing});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: () => go(c, MemberProfile(userId: m.id, name: m.name, hue: m.hue)),
      semanticLabel: m.name,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x2),
        child: Row(children: [
          SizedBox(
            width: S.x10,
            child: Column(children: [
              CommunityAvatar(m.name, m.hue, size: S.x10, photo: m.avatarPath),
              if (m.isAdmin)
                Container(
                  margin: const EdgeInsets.only(top: S.half),
                  padding: const EdgeInsets.symmetric(horizontal: S.x1),
                  color: p.ink,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('ADMIN',
                        maxLines: 1,
                        style: F.over.copyWith(color: p.bg, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name.toUpperCase(),
                  style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
              if (m.username != null)
                Text('@${m.username}', style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}

/// MANAGE TEAM: banner, logo, name, description, chat, who can join, removing
/// members, and the owner's leave-and-delete (7.2-7.3).
class _ManageTeamScreen extends StatefulWidget {
  final CommunityTeam team;
  final List<TeamPerson> people;
  const _ManageTeamScreen({required this.team, required this.people});

  @override
  State<_ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends State<_ManageTeamScreen> {
  late final _name = TextEditingController(text: widget.team.name);
  late final _about = TextEditingController(text: widget.team.description);
  late bool _chat = widget.team.chatEnabled;
  late bool _public = widget.team.isPublic;
  late String _banner = widget.team.banner, _logo = widget.team.logo;
  Uint8List? _bannerImage, _logoImage;

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _say(context, 'The team needs a name.');
      return;
    }
    final ok = await _busy(context, 'Saving', () async {
      await _svc.updateTeam(widget.team.id,
          name: _name.text,
          description: _about.text,
          chat: _chat,
          isPublic: _public,
          banner: _banner,
          logo: _logo,
          bannerImage: _bannerImage,
          logoImage: _logoImage);
      return true;
    });
    if (ok == true && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _pickPicture({required bool banner}) async {
    final picked = await AppSheet.open<Object>(
      context,
      scroll: true,
      dragHandle: true,
      builder: (s) => _PictureChooser(banner: banner),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (picked is Uint8List) {
        banner ? _bannerImage = picked : _logoImage = picked;
      } else if (picked is String) {
        if (banner) {
          _banner = picked;
          _bannerImage = null;
        } else {
          _logo = picked;
          _logoImage = null;
        }
      }
    });
  }

  Future<void> _removeMembers() async {
    final others = [
      for (final m in widget.people)
        if (m.id != _svc.myId && m.role != 'owner') m,
    ];
    if (others.isEmpty) {
      _say(context, 'There is nobody else in the team yet.');
      return;
    }
    await AppSheet.open<void>(
      context,
      scroll: true,
      dragHandle: true,
      builder: (s) => SafeArea(
        child: StatefulBuilder(
          builder: (s, setS) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
            children: [
              _label(s, 'Remove members', color: P.of(s).ink3),
              const SizedBox(height: S.x2),
              for (final m in others)
                _PersonRow(m,
                    trailing: TextAction('Remove', () async {
                      final ok = await _confirm(s, 'Remove ${m.name}?',
                          'They can join again only with the code.', 'Remove',
                          no: 'Cancel', danger: true);
                      if (!ok || !s.mounted) return;
                      try {
                        await _svc.removeMember(widget.team.id, m.id);
                        setS(() => others.remove(m));
                      } catch (e) {
                        if (s.mounted) _say(s, communityError(e));
                      }
                    }, tone: ButtonTone.danger)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await _confirm(
        context,
        'Leave and delete the team?',
        'The team, its boards and its chat go for everyone. This cannot be undone.',
        'Delete',
        no: 'Cancel',
        danger: true);
    if (!ok || !mounted) return;
    final done = await _busy(context, 'Deleting', () async {
      await _svc.deleteTeam(widget.team.id);
      return true;
    });
    if (done == true && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final top = MediaQuery.sizeOf(c).height * .4;
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        _Backdrop(
            _bannerImage != null
                ? Image.memory(_bannerImage!, fit: BoxFit.cover)
                : TeamBanner(_banner),
            height: top,
            strength: .9),
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x8),
            children: [
              SizedBox(
                height: S.x16,
                child: Row(children: [
                  _RingButton(LucideIcons.chevronLeft, 'Back',
                      () => Navigator.maybePop(c)),
                  Expanded(
                    child: Text('MANAGE TEAM',
                        textAlign: TextAlign.center,
                        style: F.caps.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                  ),
                  const SizedBox(width: S.tap),
                ]),
              ),
              Pressable(
                onTap: () => _pickPicture(banner: true),
                semanticLabel: 'Edit your banner',
                child: SizedBox(
                  height: S.x16 * 1.6,
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.pencil, size: I.lg, color: p.ink),
                      const SizedBox(width: S.x3),
                      _label(c, 'Edit your\nbanner'),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: S.x6),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Pressable(
                  onTap: () => _pickPicture(banner: false),
                  semanticLabel: 'Edit the logo',
                  child: Stack(alignment: Alignment.center, children: [
                    _logoImage != null
                        ? SizedBox.square(
                            dimension: S.x16 + S.x2,
                            child: ClipOval(
                                child: Image.memory(_logoImage!, fit: BoxFit.cover)))
                        : TeamLogo(_logo, size: S.x16 + S.x2),
                    Container(
                      width: S.x16 + S.x2,
                      height: S.x16 + S.x2,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: C.char.withValues(alpha: .45)),
                      child: Icon(LucideIcons.pencil, size: I.lg, color: p.ink),
                    ),
                  ]),
                ),
                const SizedBox(width: S.x4),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _label(c, 'Team name'),
                    const SizedBox(height: S.x2),
                    AppField(
                        controller: _name,
                        maxLength: 40,
                        semanticLabel: 'Team name',
                        textStyle: F.body.copyWith(
                            color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 2)),
                  ]),
                ),
              ]),
              const SizedBox(height: S.x4),
              _label(c, 'Team description'),
              const SizedBox(height: S.x2),
              AppField(
                  controller: _about,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 500,
                  semanticLabel: 'Team description'),
              const SizedBox(height: S.x6),
              _switchRow(c, 'Team chat', _chat, (v) => setState(() => _chat = v)),
              _switchRow(c, 'Public team', _public, (v) => setState(() => _public = v)),
              Text(
                  _public
                      ? 'Anyone can find it in Explore teams and join.'
                      : 'Only people with its code (${widget.team.code}) can join.',
                  style: F.cap.copyWith(color: p.ink3)),
              const SizedBox(height: S.x6),
              BigButton('Save changes', onTap: _save),
              const SizedBox(height: S.x3),
              BigButton('Remove members', soft: true, onTap: _removeMembers),
              if (widget.team.isOwner) ...[
                const SizedBox(height: S.x3),
                BigButton('Leave & delete team',
                    tone: ButtonTone.danger, onTap: _delete),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

Widget _switchRow(BuildContext c, String text, bool v, ValueChanged<bool> set) =>
    SizedBox(
      height: S.x12 + S.x1,
      child: Row(children: [
        Expanded(child: _label(c, text)),
        AppSwitch(v, set, semanticLabel: text),
      ]),
    );

/// A grid of the bundled banners (or logos) and an upload button. Pops a key
/// for a bundled one, the bytes of an uploaded one.
class _PictureChooser extends StatelessWidget {
  final bool banner;
  const _PictureChooser({required this.banner});

  @override
  Widget build(BuildContext c) {
    final keys = banner ? _banners : _logos.keys.toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: banner ? 2 : 4,
              mainAxisSpacing: S.x3,
              crossAxisSpacing: S.x3,
              childAspectRatio: banner ? 1.6 : 1,
              children: [
                for (final k in keys)
                  Pressable(
                    onTap: () => Navigator.of(c).pop(k),
                    semanticLabel: k,
                    child: banner
                        ? ClipRRect(borderRadius: R.rMd, child: TeamBanner(k))
                        : Center(child: TeamLogo(k, size: S.x16)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: S.x4),
          BigButton('Upload your own',
              icon: LucideIcons.imagePlus, soft: true, onTap: () async {
            try {
              final f = await ImagePicker().pickImage(
                  source: ImageSource.gallery, maxWidth: 1400, imageQuality: 82);
              final b = f == null ? null : await f.readAsBytes();
              if (b != null && c.mounted) Navigator.of(c).pop(b);
            } catch (_) {
              if (c.mounted) _say(c, 'Could not open your pictures.');
            }
          }),
        ]),
      ),
    );
  }
}
