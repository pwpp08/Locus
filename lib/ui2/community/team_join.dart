part of 'community.dart';

// Joining: the code page (refs 1.2-1.4), then the team as it is before you
// join it, saying what joining shares (1.5-1.6).

class _JoinByCodeScreen extends StatefulWidget {
  const _JoinByCodeScreen();

  @override
  State<_JoinByCodeScreen> createState() => _JoinByCodeScreenState();
}

class _JoinByCodeScreenState extends State<_JoinByCodeScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    if (!await _ensureSignedIn(context) || !mounted) return;
    final found = await _busy(context, 'Verifying', () => _svc.previewByCode(code));
    if (!mounted) return;
    if (found == null) {
      _say(context, 'No team has that code. Check it with whoever sent it.');
      return;
    }
    await Navigator.of(context).pushReplacement(themedRoute(
        (_) => _TeamDetailsScreen(preview: found, code: code),
        name: 'TeamDetails'));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ready = _code.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        _Backdrop(
          _photo('join_bg'),
          height: MediaQuery.sizeOf(c).height * .5,
          strength: .55,
        ),
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: S.gutter),
            children: [
              SizedBox(
                height: S.x16,
                child: Row(children: [
                  _RingButton(LucideIcons.chevronLeft, 'Back',
                      () => Navigator.maybePop(c)),
                  Expanded(
                    child: Text('JOIN TEAM',
                        textAlign: TextAlign.center,
                        style: F.head.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.4)),
                  ),
                  const SizedBox(width: S.tap),
                ]),
              ),
              const SizedBox(height: S.x16 + S.x6),
              Text('ENTER AN INVITATION CODE',
                  textAlign: TextAlign.center,
                  style: F.head.copyWith(
                      color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 2)),
              const SizedBox(height: S.x2),
              Text('Have a team code? Enter it below to find your team.',
                  textAlign: TextAlign.center,
                  style: F.body.copyWith(color: p.ink2)),
              const SizedBox(height: S.x5),
              _CodeField(
                controller: _code,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: S.x8),
              BigButton('Submit code',
                  soft: !ready, onTap: ready ? _submit : null),
            ],
          ),
        ),
      ]),
    );
  }
}

/// The code box: a filled well with a rule under it, the code centred in it.
class _CodeField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged, onSubmitted;
  const _CodeField(
      {required this.controller,
      required this.onChanged,
      required this.onSubmitted});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: S.x4),
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: .85),
        border: Border(bottom: BorderSide(color: p.ink, width: S.half)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: AppField(
          controller: controller,
          bare: true,
          semanticLabel: 'Invitation code',
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.go,
          autocorrect: false,
          hint: 'INVITATION CODE',
          textStyle: F.head.copyWith(letterSpacing: 2),
        ),
      ),
    );
  }
}

/// A team as someone deciding whether to join sees it: its banner, logo and
/// name, what it is about, what joining shares, how many are in it.
class _TeamDetailsScreen extends StatefulWidget {
  /// From a code (private or public), or a public team's id.
  final TeamPreview? preview;
  final String? code, teamId;
  const _TeamDetailsScreen({this.preview, this.code, this.teamId});

  @override
  State<_TeamDetailsScreen> createState() => _TeamDetailsScreenState();
}

class _TeamDetailsScreenState extends State<_TeamDetailsScreen> {
  late TeamPreview? _t = widget.preview;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_t == null && widget.teamId != null) _load();
  }

  Future<void> _load() async {
    try {
      await _svc.ensureReady();
      final t = await _svc.preview(widget.teamId!);
      if (mounted) setState(() => t == null ? _error = 'That team is private.' : _t = t);
    } catch (e) {
      if (mounted) setState(() => _error = communityError(e));
    }
  }

  Future<void> _join() async {
    final t = _t;
    if (t == null) return;
    if (!t.joined) {
      if (!await _ensureSignedIn(context) || !mounted) return;
      final id = await _busy(
          context,
          'Saving',
          () => widget.code != null
              ? _svc.joinByCode(widget.code!)
              : _svc.joinPublic(t.id));
      if (id == null || !mounted) return;
    }
    final team = _svc.teams.where((x) => x.id == t.id).firstOrNull;
    if (team == null || !mounted) return;
    await Navigator.of(context).pushReplacement(themedRoute(
        (_) => TeamScreen(team: team, openOnBoard: true),
        name: 'TeamScreen'));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final t = _t;
    return Scaffold(
      backgroundColor: p.bg,
      body: t == null
          ? SafeArea(
              child: Column(children: [
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: S.x4),
                    child: NavBar('Team')),
                Expanded(
                  child: Center(
                    child: _error == null
                        ? const CircularProgressIndicator.adaptive()
                        : Text(_error!, style: F.body.copyWith(color: p.ink2)),
                  ),
                ),
              ]),
            )
          : Stack(children: [
              _Backdrop(TeamBanner(t.banner),
                  height: S.x16 * 5, strength: .9),
              SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x8),
                  children: [
                    SizedBox(
                      height: S.x16,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _RingButton(LucideIcons.chevronLeft, 'Back',
                            () => Navigator.maybePop(c)),
                      ),
                    ),
                    const SizedBox(height: S.x16 + S.x10),
                    Row(children: [
                      TeamLogo(t.logo, size: S.x16 + S.x2),
                      const SizedBox(width: S.x5),
                      Expanded(
                        child: Text(t.name.toUpperCase(),
                            style: F.t2.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2)),
                      ),
                    ]),
                    const SizedBox(height: S.x8),
                    if (t.description.isNotEmpty) ...[
                      _label(c, 'About'),
                      const SizedBox(height: S.x2),
                      Text(t.description, style: F.body.copyWith(color: p.ink2)),
                      const SizedBox(height: S.x6),
                    ],
                    _label(c, 'Data sharing'),
                    const SizedBox(height: S.x2),
                    _grey(c, t.boards.words),
                    const SizedBox(height: S.x1),
                    Text(
                      'Joining shows your ${t.boards.words.toLowerCase()} to its '
                      'members, with the numbers behind them'
                      '${t.boards.strain ? ' and your workouts' : ''}. Leave and '
                      'they stop seeing them.',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                    const SizedBox(height: S.x6),
                    _label(c, t.members == 1 ? '1 member' : '${groupThousands(t.members)} members',
                        color: p.ink3),
                    if (t.chatEnabled) ...[
                      const SizedBox(height: S.x2),
                      Text('Has a team chat', style: F.cap.copyWith(color: p.ink3)),
                    ],
                    const SizedBox(height: S.x10),
                    BigButton(t.joined ? 'Open team' : 'Join team', onTap: _join),
                    if (!t.joined) ...[
                      const SizedBox(height: S.x3),
                      Center(
                        child: TextAction('Decline', () => Navigator.maybePop(c)),
                      ),
                    ],
                  ],
                ),
              ),
            ]),
    );
  }
}
