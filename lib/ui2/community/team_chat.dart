part of 'community.dart';

// Team chat, where the admin has it on: messages by day, pictures and shared
// cards, and the composer with DATA (share a card of your numbers), ADD (a
// picture) and SEND (refs 6.12, 8.2-8.6, 9.2, humans_6).

class _ChatTab extends StatefulWidget {
  final CommunityTeam team;
  final List<TeamPerson> people;
  const _ChatTab({required this.team, required this.people});

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = const [];
  StreamSubscription<ChatMessage>? _sub;
  bool _loading = true, _sending = false;
  Uint8List? _image;
  String? _card;

  @override
  void initState() {
    super.initState();
    _svc.viewingChat = widget.team.id;
    _sub = _svc.newMessages.listen((m) {
      if (m.teamId != widget.team.id || !mounted) return;
      if (_messages.any((x) => x.id == m.id)) return;
      setState(() => _messages = [..._messages, m]);
      _toEnd();
    });
    _load();
    unawaited(_svc.markRead(widget.team.id));
  }

  @override
  void dispose() {
    if (_svc.viewingChat == widget.team.id) _svc.viewingChat = null;
    _sub?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await _svc.messages(widget.team.id);
      if (!mounted) return;
      setState(() {
        _messages = m;
        _loading = false;
      });
      _toEnd();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _say(context, communityError(e));
      }
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  bool get _canSend => !_sending && (_text.text.trim().isNotEmpty || _image != null);

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _sending = true);
    try {
      final body = _text.text.length > 2000
          ? _text.text.substring(0, 2000)
          : _text.text;
      await _svc.send(widget.team.id, body, image: _image, card: _card);
      _text.clear();
      _image = null;
      _card = null;
      await _load();
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addPicture() async {
    try {
      final f = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
      if (f == null) return;
      final b = await f.readAsBytes();
      if (mounted) {
        setState(() {
          _image = b;
          _card = null;
        });
      }
    } catch (_) {
      if (mounted) _say(context, 'Could not open your pictures.');
    }
  }

  Future<void> _shareData() async {
    final picked = await Navigator.of(context).push<(Uint8List, String)>(
        themedRoute((_) => const _ShareDataScreen(), name: 'ShareData'));
    if (picked == null || !mounted) return;
    setState(() {
      _image = picked.$1;
      _card = picked.$2;
    });
  }

  Future<void> _options(ChatMessage m) async {
    final mine = m.userId == _svc.myId;
    final pick = await AppSheet.open<String>(
      context,
      dragHandle: true,
      builder: (s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (mine || widget.team.isAdmin) ...[
              _actionRow(s, LucideIcons.trash2, 'Delete message',
                  () => Navigator.of(s).pop('delete')),
              const SizedBox(height: S.x3),
            ],
            if (!mine) ...[
              _actionRow(s, LucideIcons.flag, 'Report the message',
                  () => Navigator.of(s).pop('report')),
              const SizedBox(height: S.x3),
              _actionRow(s, LucideIcons.circleSlash, 'Block this person',
                  () => Navigator.of(s).pop('block')),
            ],
          ]),
        ),
      ),
    );
    if (!mounted || pick == null) return;
    try {
      switch (pick) {
        case 'delete':
          await _svc.deleteMessage(m);
          await _load();
        case 'report':
          await _svc.report(teamId: widget.team.id, messageId: m.id);
          if (mounted) _say(context, 'Reported. Thank you.');
        case 'block':
          await _svc.block(m.userId);
          await _load();
      }
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final people = {for (final m in widget.people) m.id: m};
    final me = people[_svc.myId];
    final items = <Widget>[];
    DateTime? day;
    for (final m in _messages) {
      final d = DateTime(m.at.year, m.at.month, m.at.day);
      if (day != null && d != day) items.add(_DatePill(d));
      day = d;
      items.add(_MessageView(
        m,
        person: people[m.userId],
        onLongPress: () => _options(m),
        onOpenPicture: m.imagePath == null
            ? null
            : () => go(c, _PicturePreview(message: m, person: people[m.userId])),
      ));
    }
    return Column(children: [
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator.adaptive())
            : _messages.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TeamLogo(widget.team.logo, size: S.x16 + S.x4),
                      const SizedBox(height: S.x6),
                      Text('NO MESSAGES YET.\nBE THE FIRST!',
                          textAlign: TextAlign.center,
                          style: F.caps.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2)),
                    ]),
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(S.gutter, S.x6, S.gutter, S.x4),
                    children: items,
                  ),
      ),
      Container(
        color: p.card.withValues(alpha: .6),
        padding: EdgeInsets.fromLTRB(
            S.gutter, S.x3, S.gutter, S.x1 + MediaQuery.paddingOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_image != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: S.x2),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: R.rMd,
                    child: Image.memory(_image!,
                        height: S.x16 * 1.8, fit: BoxFit.contain),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Pressable(
                      onTap: () => setState(() {
                        _image = null;
                        _card = null;
                      }),
                      semanticLabel: 'Remove the picture',
                      child: Container(
                        width: S.x8,
                        height: S.x8,
                        decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
                        child: Icon(LucideIcons.x, size: I.sm, color: p.bg),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: S.x3),
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius: R.rMd,
              border: Border.all(color: p.line),
            ),
            child: Row(children: [
              if (me != null) ...[
                CommunityAvatar(me.name, me.hue, size: S.x8, photo: me.avatarPath),
                const SizedBox(width: S.x3),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x3),
                  child: AppField(
                    controller: _text,
                    bare: true,
                    semanticLabel: 'Message',
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    hint: 'SAY SOMETHING',
                  ),
                ),
              ),
            ]),
          ),
          SizedBox(
            height: S.x12 + S.x2,
            child: Row(children: [
              _ComposerAction(LucideIcons.chartColumn, 'Data', _shareData),
              _rule(p),
              _ComposerAction(LucideIcons.circlePlus, 'Add', _addPicture),
              _rule(p),
              _ComposerAction(LucideIcons.send, 'Send', _canSend ? _send : null,
                  busy: _sending),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _rule(P p) => Container(width: S.hair, height: S.x8, color: p.line);
}

class _ComposerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  const _ComposerAction(this.icon, this.label, this.onTap, {this.busy = false});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ink = onTap == null ? p.ink3 : p.ink;
    return Expanded(
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          busy
              ? SizedBox.square(
                  dimension: I.md,
                  child: CircularProgressIndicator(strokeWidth: 2, color: ink))
              : Icon(icon, size: I.lg, color: ink),
          const SizedBox(width: S.x2),
          Text(label.toUpperCase(),
              style: F.caps.copyWith(
                  color: ink, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        ]),
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  final DateTime day;
  const _DatePill(this.day);

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x6, vertical: S.x1),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rPill),
          child: Text('${day.day} ${_months[day.month - 1]} ${day.year}',
              style: F.cap.copyWith(color: p.ink)),
        ),
      ),
    );
  }
}

String _timeOf(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

/// One message: avatar, NAME @handle and time, the words, the picture.
class _MessageView extends StatelessWidget {
  final ChatMessage m;
  final TeamPerson? person;
  final VoidCallback onLongPress;
  final VoidCallback? onOpenPicture;
  const _MessageView(this.m,
      {required this.person, required this.onLongPress, this.onOpenPicture});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final name = person?.name ?? 'Former member';
    return Pressable(
      onTap: onLongPress,
      onLongPress: onLongPress,
      semanticLabel: 'Message from $name',
      child: Padding(
        padding: const EdgeInsets.only(bottom: S.x5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CommunityAvatar(name, person?.hue ?? 0,
              size: S.x10, photo: person?.avatarPath),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: name.toUpperCase(),
                    style: F.caps.copyWith(
                        color: p.on(C.dialStrain),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                if (person?.username != null)
                  TextSpan(
                      text: '  @${person!.username}',
                      style: F.cap.copyWith(color: p.ink3)),
                TextSpan(
                    text: '  ${_timeOf(m.at)}',
                    style: F.cap.copyWith(color: p.ink3)),
              ])),
              if (m.imagePath != null) ...[
                const SizedBox(height: S.x2),
                Pressable(
                  onTap: onOpenPicture,
                  semanticLabel: m.card ?? 'Picture',
                  child: ClipRRect(
                    borderRadius: R.rMd,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: S.x16 * 5),
                      child: _RemoteImage('posts', m.imagePath!, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ],
              if (m.body.isNotEmpty) ...[
                const SizedBox(height: S.x1),
                Text(m.body, style: F.body.copyWith(color: p.ink)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A shared picture full screen, with share and "1 OF 1" (9.2).
class _PicturePreview extends StatelessWidget {
  final ChatMessage message;
  final TeamPerson? person;
  const _PicturePreview({required this.message, this.person});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: S.x16,
            child: Row(children: [
              Pressable(
                onTap: () => Navigator.maybePop(c),
                semanticLabel: 'Close',
                child: SizedBox.square(
                    dimension: S.x12,
                    child: Icon(LucideIcons.x, size: I.lg, color: p.ink)),
              ),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text((person?.username ?? person?.name ?? '').toUpperCase(),
                      style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
                  Text(_timeOf(message.at), style: F.cap.copyWith(color: p.ink3)),
                ]),
              ),
              const SizedBox(width: S.x12),
            ]),
          ),
          Expanded(
            child: InteractiveViewer(
              child: Center(
                child: _RemoteImage('posts', message.imagePath!, fit: BoxFit.contain),
              ),
            ),
          ),
          Container(
            color: p.card.withValues(alpha: .6),
            height: S.x16,
            padding: const EdgeInsets.symmetric(horizontal: S.x3),
            child: Row(children: [
              Pressable(
                onTap: () async {
                  final url = await _svc.pictureUrl(message.imagePath!);
                  await Share.shareUri(Uri.parse(url));
                },
                semanticLabel: 'Share',
                child: SizedBox.square(
                    dimension: S.x12,
                    child: Icon(LucideIcons.share, size: I.lg, color: p.ink)),
              ),
              Expanded(
                child: Text('1 OF 1',
                    textAlign: TextAlign.center,
                    style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: S.x12),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── sharing your numbers ────────────────────────────────────────────────────

/// Your own figures for the cards: today, and the last seven days.
class _MyNumbers {
  final double? recovery, strain, sleepPerf, sleepMin;
  final List<(DateTime, double?)> weekRecovery, weekStrain;
  final String name;
  final String? handle;
  const _MyNumbers({
    this.recovery,
    this.strain,
    this.sleepPerf,
    this.sleepMin,
    this.weekRecovery = const [],
    this.weekStrain = const [],
    required this.name,
    this.handle,
  });

  static Future<_MyNumbers> load(BuildContext c) async {
    final repo = repoOf(c);
    final me = _svc.profile;
    final name = me?.name ?? 'Me';
    if (repo == null) return _MyNumbers(name: name, handle: me?.username);
    Future<Map<String, double>> s(String k) =>
        dialSeries(repo, k).catchError((_) => <String, double>{});
    final rec = await s('recovery'), str = await s('strain');
    final perf = await s('sleep_performance'), tst = await s('tst_min');
    final today = DateTime.now();
    final key = todayLabel();
    final week = [
      for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i),
    ];
    return _MyNumbers(
      recovery: rec[key],
      strain: str[key],
      sleepPerf: perf[key],
      sleepMin: tst[key],
      weekRecovery: [for (final d in week) (d, rec[dayLabelOf(d)])],
      weekStrain: [for (final d in week) (d, str[dayLabelOf(d)])],
      name: name,
      handle: me?.username,
    );
  }
}

/// SHARE DATA: the cards you can post, by group (8.3). Tapping one hands its
/// picture back to the composer.
class _ShareDataScreen extends StatefulWidget {
  const _ShareDataScreen();

  @override
  State<_ShareDataScreen> createState() => _ShareDataScreenState();
}

class _ShareDataScreenState extends State<_ShareDataScreen> {
  _MyNumbers? _n;
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _MyNumbers.load(context).then((n) {
      if (mounted) setState(() => _n = n);
    });
  }

  Future<void> _pick(String name) async {
    final b = _keys[name]?.currentContext?.findRenderObject();
    if (b is! RenderRepaintBoundary) return;
    final img = await b.toImage(pixelRatio: 3);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    if (png == null || !mounted) return;
    Navigator.of(context).pop((png.buffer.asUint8List(), name));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final n = _n;
    Widget thumb(String name, Widget card) {
      final k = _keys.putIfAbsent(name, GlobalKey.new);
      return Pressable(
        onTap: () => _pick(name),
        semanticLabel: 'Share $name',
        child: SizedBox(
          width: S.x16 * 2.1,
          child: Column(children: [
            SizedBox.square(
              dimension: S.x16 * 2.1,
              child: FittedBox(
                child: RepaintBoundary(key: k, child: card),
              ),
            ),
            const SizedBox(height: S.x2),
            Text(name.toUpperCase(),
                textAlign: TextAlign.center,
                style: F.over.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
    }

    Widget group(String title, List<Widget> cards) => cards.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: S.x6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _label(c, title, color: p.ink2),
                const SizedBox(width: S.x3),
                Expanded(child: Divider(color: p.line, height: S.hair)),
              ]),
              const SizedBox(height: S.x3),
              Wrap(spacing: S.x3, runSpacing: S.x3, children: cards),
            ]),
          );

    final week = n == null ? const <(DateTime, double?)>[] : n.weekRecovery;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: S.x16,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x3),
              child: Row(children: [
                _RingButton(LucideIcons.x, 'Close', () => Navigator.maybePop(c)),
                Expanded(
                  child: Text('SHARE DATA',
                      textAlign: TextAlign.center,
                      style: F.caps.copyWith(
                          color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 2)),
                ),
                const SizedBox(width: S.tap),
              ]),
            ),
          ),
          Expanded(
            child: n == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x8),
                    children: [
                      group('Overview', [
                        if (n.recovery != null || n.strain != null)
                          thumb('Daily overview', _OverviewCard(n)),
                      ]),
                      group('Strain', [
                        if (n.strain != null)
                          thumb('Day strain',
                              _DialCard(n, 'DAY STRAIN', n.strain!.toStringAsFixed(1),
                                  n.strain! / 21, C.dialStrain)),
                        if (n.weekStrain.any((d) => d.$2 != null))
                          thumb('Weekly strain',
                              _WeekCard(n, 'WEEKLY STRAIN', n.weekStrain, BoardMetric.strain)),
                      ]),
                      group('Recovery', [
                        if (n.recovery != null)
                          thumb('Recovery',
                              _DialCard(n, 'RECOVERY', '${n.recovery!.round()}%',
                                  n.recovery! / 100, _recoveryInk(n.recovery!))),
                        if (week.any((d) => d.$2 != null))
                          thumb('Weekly recovery',
                              _WeekCard(n, 'WEEKLY RECOVERY', week, BoardMetric.recovery)),
                      ]),
                      group('Sleep', [
                        if (n.sleepPerf != null)
                          thumb('Sleep',
                              _DialCard(n, 'SLEEP PERFORMANCE',
                                  '${n.sleepPerf!.round()}%', n.sleepPerf! / 100,
                                  C.dialSleep,
                                  under: n.sleepMin == null
                                      ? null
                                      : '${hoursClock(n.sleepMin!)} HOURS OF SLEEP')),
                      ]),
                      if (n.recovery == null &&
                          n.strain == null &&
                          n.sleepPerf == null &&
                          !n.weekStrain.any((d) => d.$2 != null))
                        Padding(
                          padding: const EdgeInsets.only(top: S.x8),
                          child: Text('Nothing to share yet: no numbers for today '
                              'or this week.',
                              textAlign: TextAlign.center,
                              style: F.body.copyWith(color: p.ink3)),
                        ),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}

Color _recoveryInk(double v) =>
    v >= 67 ? C.recGreen : v >= 34 ? C.recYellow : C.recRed;

/// The frame every shared card has: title, date, the LOCUS mark, the body,
/// and the sharer's name along the foot.
class _CardFrame extends StatelessWidget {
  final _MyNumbers n;
  final String title, date;
  final Widget body;
  const _CardFrame(this.n, this.title, this.date, this.body);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      width: S.x16 * 5,
      height: S.x16 * 5,
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(
        borderRadius: R.rLg,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.bgTop, p.bg],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: F.caps.copyWith(
                      color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
              Text(date, style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
          Text('LOCUS', style: F.caps.copyWith(color: p.ink2, letterSpacing: 2)),
        ]),
        Expanded(child: body),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
          color: C.char,
          child: Row(children: [
            Text(n.name.toUpperCase(),
                style: F.over.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
            if (n.handle != null) ...[
              const SizedBox(width: S.x2),
              Text('@${n.handle}', style: F.over.copyWith(color: p.ink3)),
            ],
          ]),
        ),
      ]),
    );
  }
}

String _cardDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

/// DAILY OVERVIEW: recovery left, strain right, both rings in the middle.
class _OverviewCard extends StatelessWidget {
  final _MyNumbers n;
  const _OverviewCard(this.n);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final rec = n.recovery, str = n.strain;
    Widget side(String v, String label, Color ink) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(v, style: F.t2.copyWith(color: p.on(ink))),
            Text(label, style: F.over.copyWith(color: p.on(ink), fontWeight: FontWeight.w800)),
          ],
        );
    return _CardFrame(
      n,
      'DAILY OVERVIEW',
      _cardDate(DateTime.now()),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        side(rec == null ? '--' : '${rec.round()}%', 'RECOVERY',
            rec == null ? p.ink3 : _recoveryInk(rec)),
        SizedBox.square(
          dimension: S.x16 + S.x4,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: const Size.square(S.x16 + S.x4),
              painter: _RingPainter(
                  color: C.dialStrain,
                  track: p.track,
                  fill: (str ?? 0) / 21,
                  stroke: S.x1),
            ),
            SizedBox.square(
              dimension: S.x16 - S.x1,
              child: CustomPaint(
                painter: _RingPainter(
                    color: rec == null ? p.ink3 : _recoveryInk(rec),
                    track: p.track,
                    fill: (rec ?? 0) / 100,
                    stroke: S.x2),
              ),
            ),
          ]),
        ),
        side(str == null ? '--' : str.toStringAsFixed(1), 'STRAIN', C.dialStrain),
      ]),
    );
  }
}

/// One ring with its figure inside (day strain, recovery, sleep).
class _DialCard extends StatelessWidget {
  final _MyNumbers n;
  final String title, value;
  final double fill;
  final Color ink;
  final String? under;
  const _DialCard(this.n, this.title, this.value, this.fill, this.ink, {this.under});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return _CardFrame(
      n,
      title,
      _cardDate(DateTime.now()),
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox.square(
          dimension: S.x16 * 1.7,
          child: CustomPaint(
            painter: _RingPainter(color: ink, track: p.track, fill: fill, stroke: S.x2),
            child: Center(
              child: Text(value, style: F.t1.copyWith(color: p.ink)),
            ),
          ),
        ),
        if (under != null) ...[
          const SizedBox(height: S.x2),
          Text(under!, style: F.over.copyWith(color: p.ink2, fontWeight: FontWeight.w800)),
        ],
      ]),
    );
  }
}

/// Seven bars of the week with a dashed average (8.6).
class _WeekCard extends StatelessWidget {
  final _MyNumbers n;
  final String title;
  final List<(DateTime, double?)> week;
  final BoardMetric metric;
  const _WeekCard(this.n, this.title, this.week, this.metric);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final top = metric == BoardMetric.strain ? 21.0 : 100.0;
    final vals = [for (final d in week) ?d.$2];
    final avg = vals.isEmpty ? null : vals.reduce((a, b) => a + b) / vals.length;
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return _CardFrame(
      n,
      title,
      '${_cardDate(week.first.$1)} - ${_cardDate(week.last.$1)}',
      Padding(
        padding: const EdgeInsets.only(top: S.x3, bottom: S.x2),
        child: Column(children: [
          Expanded(
            child: CustomPaint(
              painter: _AvgLine(
                  avg == null ? null : avg / top, p.ink2.withValues(alpha: .7)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (_, v) in week)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.x1),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (v != null)
                          Text(
                              metric == BoardMetric.strain
                                  ? v.toStringAsFixed(1)
                                  : '${v.round()}%',
                              style: F.over.copyWith(
                                  color: metric == BoardMetric.strain
                                      ? p.on(C.dialStrain)
                                      : p.on(_recoveryInk(v)))),
                        FractionallySizedBox(
                          widthFactor: 1,
                          child: Container(
                            height: v == null ? 0 : (v / top).clamp(.02, 1) * S.x16 * 1.6,
                            color: (metric == BoardMetric.strain
                                    ? C.dialStrain
                                    : _recoveryInk(v ?? 0))
                                .withValues(alpha: .7),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: S.x1),
          Row(children: [
            for (final (d, _) in week)
              Expanded(
                child: Text('${wd[d.weekday - 1]}\n${d.day}',
                    textAlign: TextAlign.center,
                    style: F.over.copyWith(color: p.ink3)),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _AvgLine extends CustomPainter {
  final double? at;
  final Color color;
  const _AvgLine(this.at, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final a = at;
    if (a == null) return;
    // The bars stand on the bottom and reach S.x16 * 1.6 at the top value.
    final y = size.height - a.clamp(0.0, 1.0) * S.x16 * 1.6;
    final p = Paint()
      ..color = color
      ..strokeWidth = S.hair;
    for (var x = 0.0; x < size.width; x += S.x2) {
      canvas.drawLine(Offset(x, y), Offset(x + S.x1, y), p);
    }
  }

  @override
  bool shouldRepaint(_AvgLine o) => o.at != at || o.color != color;
}

/// From an activity's share sheet: posts [image] with a caption into the chat
/// of a team the person picks (or [only]). Only teams with chat on take
/// pictures. True when it went up.
Future<bool> shareToTeam(BuildContext c, List<int> image,
    {String mime = 'image/png', String? only}) async {
  await _svc.ensureReady();
  if (!c.mounted) return false;
  if (!_svc.signedIn) {
    go(c, const CommunityScreen());
    return false;
  }
  final teams = [for (final t in _svc.teams) if (t.hasChat) t];
  if (teams.isEmpty) {
    _say(c, 'None of your teams has a chat. An admin can turn it on.');
    return false;
  }
  final bytes = image is Uint8List ? image : Uint8List.fromList(image);
  final caption = TextEditingController();
  var chosen = only ?? teams.first.id;
  var busy = false;
  final posted = await AppSheet.open<bool>(
    c,
    scroll: true,
    dragHandle: true,
    builder: (s) => StatefulBuilder(
      builder: (s, setS) => Padding(
        padding: EdgeInsets.fromLTRB(
            S.gutter, 0, S.gutter, S.x4 + MediaQuery.viewInsetsOf(s).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label(s, 'Share to team chat', color: P.of(s).ink2),
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
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 4),
              if (only == null && teams.length > 1)
                for (final t in teams)
                  _Radio(t.name, chosen == t.id, () => setS(() => chosen = t.id)),
              const SizedBox(height: S.x3),
              BigButton('Send', busy: busy, onTap: () async {
                setS(() => busy = true);
                try {
                  await _svc.send(chosen, caption.text, image: bytes, mime: mime);
                  if (s.mounted) Navigator.of(s).pop(true);
                } catch (e) {
                  setS(() => busy = false);
                  if (s.mounted) _say(s, communityError(e));
                }
              }),
            ],
          ),
        ),
      ),
    ),
  );
  caption.dispose();
  if (posted == true && c.mounted) _say(c, 'Sent');
  return posted == true;
}
