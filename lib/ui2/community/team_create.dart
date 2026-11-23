part of 'community.dart';

// Creating a team, four steps over a photo (refs 6.2-6.10): its name, its
// banner, its logo, then its boards (fixed for good) and who can find it.
// Then the invite sheet, and the team's own page.

class _CreateTeamFlow extends StatefulWidget {
  const _CreateTeamFlow();

  @override
  State<_CreateTeamFlow> createState() => _CreateTeamFlowState();
}

class _CreateTeamFlowState extends State<_CreateTeamFlow> {
  final _name = TextEditingController();
  final _bannerPages = PageController();
  final _logoPages = PageController();
  int _step = 0;
  int _banner = 0, _logo = 0;
  Uint8List? _bannerImage, _logoImage;
  bool _strain = true, _recovery = true, _sleep = true;
  bool _public = false, _chat = true, _chatTouched = false;

  @override
  void dispose() {
    _name.dispose();
    _bannerPages.dispose();
    _logoPages.dispose();
    super.dispose();
  }

  String get _title => switch (_step) {
        0 => "What's your team name",
        1 => 'Choose your banner',
        2 => 'Choose your logo',
        _ => 'Data sharing',
      };

  bool get _canNext => switch (_step) {
        0 => _name.text.trim().isNotEmpty,
        3 => _strain || _recovery || _sleep,
        _ => true,
      };

  void _back() {
    if (_step == 0) {
      Navigator.maybePop(context);
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    if (!await _ensureSignedIn(context) || !mounted) return;
    final id = await _busy(
      context,
      'Creating',
      () => _svc.createTeam(NewTeam(
        name: _name.text,
        banner: _banners[_banner],
        logo: _logos.keys.elementAt(_logo),
        bannerImage: _bannerImage,
        logoImage: _logoImage,
        isPublic: _public,
        chat: _chat,
        boards: Boards(strain: _strain, recovery: _recovery, sleep: _sleep),
      )),
    );
    if (id == null || !mounted) return;
    final team = _svc.teams.where((t) => t.id == id).firstOrNull;
    if (team == null) return;
    await _showInvite(context, team);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
        themedRoute((_) => TeamScreen(team: team), name: 'TeamScreen'));
  }

  Future<Uint8List?> _pick() async {
    try {
      final f = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1400, imageQuality: 82);
      return f == null ? null : await f.readAsBytes();
    } catch (e) {
      if (mounted) _say(context, 'Could not open your pictures.');
      return null;
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final top = MediaQuery.sizeOf(c).height * .42;
    final name = _name.text.trim().toUpperCase();
    Widget banner() => _bannerImage != null
        ? Image.memory(_bannerImage!, fit: BoxFit.cover)
        : TeamBanner(_banners[_banner]);
    return Scaffold(
      backgroundColor: p.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        // The photo: the create page's own on step one, the banner after.
        SizedBox(
          height: top,
          width: double.infinity,
          child: _step == 0
              ? _Backdrop(
                  _photo('create_bg'),
                  height: top,
                  strength: .6)
              : _step == 1 && _bannerImage == null
                  ? Stack(fit: StackFit.expand, children: [
                      PageView.builder(
                        controller: _bannerPages,
                        itemCount: _banners.length,
                        onPageChanged: (i) => setState(() => _banner = i),
                        itemBuilder: (_, i) => _Backdrop(TeamBanner(_banners[i]),
                            height: top, strength: .75),
                      ),
                    ])
                  : _Backdrop(banner(), height: top, strength: .75),
        ),
        SafeArea(
          child: Column(children: [
            _StepHeader(
              step: _step,
              title: _title,
              onBack: _back,
            ),
            SizedBox(
              height: top - S.x16 - MediaQuery.paddingOf(c).top,
              child: Column(children: [
                const Spacer(),
                if (_step == 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: S.gutter),
                    child: AppField(
                      controller: _name,
                      bare: true,
                      autofocus: true,
                      semanticLabel: 'Team name',
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _canNext ? _next() : null,
                      textStyle: F.t2.copyWith(
                          letterSpacing: 4, fontWeight: FontWeight.w800),
                    ),
                  )
                else if (_step == 2)
                  SizedBox(
                    height: S.x16 * 2.4,
                    child: _logoImage != null
                        ? Center(
                            child: SizedBox.square(
                              dimension: S.x16 * 2.4,
                              child: ClipOval(
                                  child: Image.memory(_logoImage!, fit: BoxFit.cover)),
                            ),
                          )
                        : PageView.builder(
                            controller: _logoPages,
                            itemCount: _logos.length,
                            onPageChanged: (i) => setState(() => _logo = i),
                            itemBuilder: (_, i) => Center(
                              child: TeamLogo(_logos.keys.elementAt(i),
                                  size: S.x16 * 2.4),
                            ),
                          ),
                  )
                else
                  IgnorePointer(
                    child: Text(name,
                        textAlign: TextAlign.center,
                        style: F.t2.copyWith(
                            color: p.ink,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w800)),
                  ),
                const Spacer(),
                if (_step == 1 || _step == 2)
                  _SwipeHint(
                    onLeft: () => _swipe(-1),
                    onRight: () => _swipe(1),
                  ),
                const SizedBox(height: S.x3),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.gutter, S.x6, S.gutter, S.x4),
                children: [
                  if (_step == 1 || _step == 2) ...[
                    Center(
                      child: _label(c, _step == 1
                          ? 'Swipe to select a banner'
                          : 'Swipe to select a logo'),
                    ),
                    const SizedBox(height: S.x4),
                    _OrRule(),
                    const SizedBox(height: S.x4),
                    BigButton(
                      (_step == 1 ? _bannerImage : _logoImage) == null
                          ? 'Upload your own'
                          : 'Use the stock ones',
                      soft: true,
                      icon: LucideIcons.imagePlus,
                      onTap: () async {
                        if ((_step == 1 ? _bannerImage : _logoImage) != null) {
                          setState(() => _step == 1
                              ? _bannerImage = null
                              : _logoImage = null);
                          return;
                        }
                        final b = await _pick();
                        if (b == null || !mounted) return;
                        setState(() =>
                            _step == 1 ? _bannerImage = b : _logoImage = b);
                      },
                    ),
                  ],
                  if (_step == 3) ..._sharing(c),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter,
                  S.x4 + MediaQuery.paddingOf(c).bottom * 0),
              child: BigButton(_step == 3 ? 'Create team' : 'Next',
                  soft: !_canNext, onTap: _canNext ? _next : null),
            ),
          ]),
        ),
      ]),
    );
  }

  void _swipe(int by) {
    final pages = _step == 1 ? _bannerPages : _logoPages;
    if (!pages.hasClients) return;
    final n = _step == 1 ? _banners.length : _logos.length;
    final to = ((pages.page ?? 0).round() + by) % n;
    pages.jumpToPage(to);
  }

  List<Widget> _sharing(BuildContext c) {
    final p = P.of(c);
    Widget board(IconData icon, String name, bool v, ValueChanged<bool> set) =>
        SizedBox(
          height: S.x12 + S.x1,
          child: Row(children: [
            Container(
              width: S.x10,
              height: S.x10,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.card2, shape: BoxShape.circle),
              child: Icon(icon, size: I.md, color: p.ink),
            ),
            const SizedBox(width: S.x4),
            Expanded(child: Text(name, style: F.body.copyWith(color: p.ink))),
            AppSwitch(v, (x) => setState(() => set(x)), semanticLabel: name),
          ]),
        );
    return [
      Row(children: [
        Expanded(child: _label(c, 'Choose leaderboards')),
        Pressable(
          onTap: () => AppDialog.show(c,
              title: 'Leaderboards',
              body: 'Each board you keep is shared with everyone who joins: '
                  'Strain shares day strain, workouts and calories; Recovery '
                  'shares recovery, HRV and resting heart rate; Sleep shares '
                  'sleep performance and hours slept. Joining is agreeing to '
                  'exactly that, so the boards can never change later.',
              primary: 'OK'),
          semanticLabel: 'About leaderboards',
          child: SizedBox.square(
              dimension: S.tap,
              child: Icon(LucideIcons.circleHelp, size: I.md, color: p.ink2)),
        ),
      ]),
      Text('These settings cannot be changed later.',
          style: F.cap.copyWith(color: p.ink3)),
      const SizedBox(height: S.x3),
      board(LucideIcons.dumbbell, 'Strain Leaderboard', _strain, (x) => _strain = x),
      board(LucideIcons.heartPulse, 'Recovery Leaderboard', _recovery,
          (x) => _recovery = x),
      board(LucideIcons.moon, 'Sleep Leaderboard', _sleep, (x) => _sleep = x),
      const SizedBox(height: S.x6),
      _label(c, 'Who can join'),
      const SizedBox(height: S.x1),
      Text('You can change these any time.', style: F.cap.copyWith(color: p.ink3)),
      const SizedBox(height: S.x3),
      board(LucideIcons.search, 'Public team', _public, (x) {
        _public = x;
        // Public teams are usually boards only; private ones talk.
        if (!_chatTouched) _chat = !x;
      }),
      board(LucideIcons.messageSquare, 'Team chat', _chat, (x) {
        _chat = x;
        _chatTouched = true;
      }),
      Text(
        _public
            ? 'Anyone can find it in Explore teams and join. Members can also '
                'invite with its code.'
            : 'Only people with its code can join.',
        style: F.cap.copyWith(color: p.ink3),
      ),
    ];
  }
}

/// "‹ 02  Create Team / CHOOSE YOUR BANNER".
class _StepHeader extends StatelessWidget {
  final int step;
  final String title;
  final VoidCallback onBack;
  const _StepHeader({required this.step, required this.title, required this.onBack});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SizedBox(
      height: S.x16,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.x3),
        child: Row(children: [
          _RingButton(step == 0 ? LucideIcons.x : LucideIcons.chevronLeft,
              step == 0 ? 'Close' : 'Back', onBack),
          const SizedBox(width: S.x2),
          Text((step + 1).toString().padLeft(2, '0'),
              style: F.t2.copyWith(color: C.dialStrain, fontWeight: FontWeight.w700)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create Team', style: F.over.copyWith(color: p.ink2)),
                Text(title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.caps.copyWith(
                        color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// ‹‹‹  ☚☛  ›››: the photo above swipes; the arrows step it too.
class _SwipeHint extends StatelessWidget {
  final VoidCallback onLeft, onRight;
  const _SwipeHint({required this.onLeft, required this.onRight});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget arrows(bool left) => Pressable(
          onTap: left ? onLeft : onRight,
          semanticLabel: left ? 'Previous' : 'Next',
          child: SizedBox(
            width: S.x16,
            height: S.tap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Icon(left ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
                      size: I.md, color: p.ink3),
              ],
            ),
          ),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      arrows(true),
      const SizedBox(width: S.x8),
      Icon(LucideIcons.hand, size: I.xl, color: p.ink),
      const SizedBox(width: S.x8),
      arrows(false),
    ]);
  }
}

class _OrRule extends StatelessWidget {
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Row(children: [
      Expanded(child: Divider(color: p.line, height: S.hair)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.x3),
        child: Text('OR', style: F.caps.copyWith(color: p.ink3)),
      ),
      Expanded(child: Divider(color: p.line, height: S.hair)),
    ]);
  }
}

/// The invite sheet: the team's code to copy, and a way to send it (6.10).
Future<void> _showInvite(BuildContext c, CommunityTeam team) => AppSheet.open<void>(
      c,
      dragHandle: true,
      builder: (s) => _InviteSheet(team),
    );

class _InviteSheet extends StatefulWidget {
  final CommunityTeam team;
  const _InviteSheet(this.team);

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  bool _copied = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String get _message =>
      'Join my team "${widget.team.name}" on Locus: open Community, tap Enter '
      'code, and type ${widget.team.code}.';

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('INVITE A MEMBER',
              style: F.head.copyWith(
                  color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 2)),
          const SizedBox(height: S.x2),
          Text('Share your team’s code. Anyone who enters it can join.',
              textAlign: TextAlign.center,
              style: F.body.copyWith(color: p.ink2)),
          const SizedBox(height: S.x5),
          Row(children: [
            Expanded(
              child: Container(
                height: S.x12,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.card2, borderRadius: R.rPill),
                child: SelectableText(widget.team.code,
                    style: F.head.copyWith(
                        color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 3)),
              ),
            ),
            const SizedBox(width: S.x3),
            BigButton(_copied ? 'Copied' : 'Copy',
                icon: _copied ? LucideIcons.check : LucideIcons.copy,
                compact: true,
                soft: true, onTap: () async {
              await Clipboard.setData(ClipboardData(text: widget.team.code));
              if (!mounted) return;
              setState(() => _copied = true);
              _t?.cancel();
              _t = Timer(Motion.copied, () {
                if (mounted) setState(() => _copied = false);
              });
            }),
          ]),
          const SizedBox(height: S.x6),
          Divider(color: p.line, height: S.hair),
          const SizedBox(height: S.x6),
          BigButton('Share invite',
              icon: LucideIcons.share2,
              onTap: () => Share.share(_message)),
        ]),
      ),
    );
  }
}
