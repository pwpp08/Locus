part of 'community.dart';

// The first visit: four slides, then the account is made and the tab opens.
// Photos over a fade, a title and a line, and one round button that fills a
// ring as the slides go by (refs 0.2-0.5).

class _Slide {
  final String? photo;
  final String title, body;
  const _Slide(this.photo, this.title, this.body);
}

const _slides = [
  _Slide('intro_1', 'Welcome to the Locus community',
      'Make or join a team: training partners, friendly rivalry and progress, together.'),
  _Slide(null, 'Find your team, fuel progress',
      'Browse public teams or enter a code to join a private one. Teams compete '
          'on leaderboards and track progress together.'),
  _Slide('intro_2', 'Make your own team',
      'Create a team, invite the people you want, and choose its leaderboards. '
          'Joining a team shares exactly those with it, nothing more.'),
  _Slide('intro_4', 'Motivation that lasts',
      'People who train with others keep at it. You can leave any team '
          'whenever you like.'),
];

class _CommunityIntro extends StatefulWidget {
  final VoidCallback onDone;
  const _CommunityIntro({required this.onDone});

  @override
  State<_CommunityIntro> createState() => _CommunityIntroState();
}

class _CommunityIntroState extends State<_CommunityIntro> {
  final _pages = PageController();
  int _at = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _step(int by) {
    final to = _at + by;
    if (to < 0) return;
    if (to >= _slides.length) {
      _finish();
      return;
    }
    if (Motion.enabled(context)) {
      _pages.animateToPage(to, duration: Motion.slow, curve: Ease.standard);
    } else {
      _pages.jumpToPage(to);
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _ensureSignedIn(context);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Prefs.setBool(CommunityService.kIntroSeen, true);
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final last = _at == _slides.length - 1;
    return Stack(children: [
      PageView.builder(
        controller: _pages,
        itemCount: _slides.length,
        onPageChanged: (i) => setState(() => _at = i),
        itemBuilder: (c, i) => _SlidePage(_slides[i]),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x2),
          child: Align(
            alignment: Alignment.topLeft,
            child: _at == 0
                ? const SizedBox.shrink()
                : Pressable(
                    onTap: () => _step(-1),
                    semanticLabel: 'Back',
                    child: SizedBox.square(
                      dimension: S.x12,
                      child: Icon(LucideIcons.chevronLeft, size: I.xl, color: p.ink),
                    ),
                  ),
          ),
        ),
      ),
      Positioned(
        right: S.gutter,
        bottom: S.navClear(c),
        child: Row(children: [
          Text(
            (_at == 0 ? 'Get started' : last ? 'Done' : 'Next').toUpperCase(),
            style: F.caps.copyWith(
                color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.6),
          ),
          const SizedBox(width: S.x4),
          _StepButton(
            progress: (_at + 1) / _slides.length,
            done: last,
            busy: _busy,
            onTap: () => _step(1),
          ),
        ]),
      ),
    ]);
  }
}

class _SlidePage extends StatelessWidget {
  final _Slide s;
  const _SlidePage(this.s);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Stack(fit: StackFit.expand, children: [
      if (s.photo != null) ...[
        _photo(s.photo!),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                p.bg.withValues(alpha: .15),
                p.bg.withValues(alpha: .1),
                p.bg.withValues(alpha: .92),
              ],
              stops: const [0, .45, .8],
            ),
          ),
        ),
      ] else
        const Align(alignment: Alignment(0, -.25), child: _TeamsMock()),
      Positioned(
        left: S.gutter,
        right: S.gutter,
        bottom: S.navClear(c) + S.x16 + S.x4,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.title, style: F.t2.copyWith(color: p.ink)),
          const SizedBox(height: S.x3),
          Text(s.body, style: F.body.copyWith(color: p.ink2, height: 1.5)),
        ]),
      ),
    ]);
  }
}

/// The round step button: an arrow inside a ring that fills slide by slide,
/// a tick on the last.
class _StepButton extends StatelessWidget {
  final double progress;
  final bool done, busy;
  final VoidCallback onTap;
  const _StepButton(
      {required this.progress,
      required this.done,
      required this.busy,
      required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const d = S.x16 + S.x6;
    return Pressable(
      onTap: busy ? null : onTap,
      semanticLabel: done ? 'Done' : 'Next',
      child: SizedBox.square(
        dimension: d,
        child: CustomPaint(
          painter: _RingPainter(
              color: C.dialStrain, track: p.track, fill: progress, stroke: S.x1),
          child: Padding(
            padding: const EdgeInsets.all(S.x2),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: done ? p.ink : p.card),
              child: busy
                  ? SizedBox.square(
                      dimension: I.md,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: done ? p.bg : p.ink))
                  : Icon(done ? LucideIcons.check : LucideIcons.arrowRight,
                      size: I.xl, color: done ? p.bg : p.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide two's picture: a small Teams card, as the tab will look.
class _TeamsMock extends StatelessWidget {
  const _TeamsMock();

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget row(IconData i, String t) => Container(
          margin: const EdgeInsets.only(top: S.x2),
          padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
          child: Row(children: [
            Icon(i, size: I.sm, color: p.ink3),
            const SizedBox(width: S.x3),
            Text(t, style: F.over.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
          ]),
        );
    Widget team(String banner, String logo, String name) => Expanded(
          child: Container(
            height: S.x16 * 2,
            margin: const EdgeInsets.only(right: S.x2),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: R.rMd, color: p.card2),
            child: Stack(fit: StackFit.expand, children: [
              Opacity(opacity: .45, child: TeamBanner(banner)),
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                TeamLogo(logo, size: S.x8),
                const SizedBox(height: S.x1),
                Text(name.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: F.over.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
              ]),
            ]),
          ),
        );
    return Container(
      width: S.x16 * 4.6,
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: R.rXl,
        border: Border.all(color: p.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Teams', style: F.head.copyWith(color: p.ink)),
        const SizedBox(height: S.x2),
        Text('GETTING STARTED', style: F.over.copyWith(color: p.ink3)),
        row(LucideIcons.users, 'ENTER INVITE CODE'),
        row(LucideIcons.circlePlus, 'CREATE TEAM'),
        const SizedBox(height: S.x4),
        Text('RECOMMENDED TEAMS', style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x2),
        Row(children: [
          team('banner_6', 'footprints', 'Run club'),
          team('banner_5', 'leaf', 'Yoga mornings'),
        ]),
      ]),
    );
  }
}
