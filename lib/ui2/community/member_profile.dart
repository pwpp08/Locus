part of 'community.dart';

// A teammate's or a followed person's profile (humans_7/8): their card, the
// follow button, today's rings and the week, then the same Data Highlights
// and Activity Summary your own profile has, from what they let you see.

class MemberProfile extends StatefulWidget {
  final String userId, name;
  final int hue;
  const MemberProfile(
      {super.key, required this.userId, required this.name, this.hue = 0});

  @override
  State<MemberProfile> createState() => _MemberProfileState();
}

class _MemberProfileState extends State<MemberProfile> {
  Human? _h;
  List<DayScore> _days = const [];
  List<SharedActivity> _acts = const [];
  bool _loading = true, _busyFollow = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _svc.ensureReady();
      final h = await _svc.human(widget.userId);
      final m = await _svc.member(widget.userId);
      if (!mounted) return;
      setState(() {
        _h = h;
        _days = m.days;
        _acts = m.activities;
        _loading = false;
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

  Future<void> _follow() async {
    final h = _h;
    if (h == null || _busyFollow) return;
    if (h.following_ || h.requested) {
      final ok = await _confirm(
          context,
          h.requested ? 'CANCEL REQUEST?' : 'UNFOLLOW?',
          h.requested
              ? 'Your request to follow ${h.name} is taken back.'
              : 'You stop seeing ${h.name}\'s numbers.',
          h.requested ? 'Cancel it' : 'Unfollow');
      if (!ok || !mounted) return;
    }
    setState(() => _busyFollow = true);
    try {
      if (h.following_ || h.requested) {
        await _svc.unfollow(h.id);
      } else {
        await _svc.follow(h.id);
      }
      final again = await _svc.human(h.id);
      if (mounted) setState(() => _h = again ?? h);
    } catch (e) {
      if (mounted) _say(context, communityError(e));
    } finally {
      if (mounted) setState(() => _busyFollow = false);
    }
  }

  /// Their days as the profile's series, keyed by day label.
  Map<String, Map<String, double>> get _series {
    final out = <String, Map<String, double>>{};
    void put(String k, DateTime d, double? v) {
      if (v != null) (out[k] ??= {})[dayLabelOf(d)] = v;
    }

    for (final d in _days) {
      put('sleep_performance', d.day, d.sleepPerf);
      put('recovery', d.day, d.recovery);
      put('strain', d.day, d.strain);
      put('resting_hr', d.day, d.rhr);
      put('hrv', d.day, d.hrv);
      put('tst_min', d.day, d.sleepMin);
      put('calories', d.day, d.calories);
      put('hr_max', d.day, d.hrMax);
    }
    return out;
  }

  List<Map<String, dynamic>> get _sessions => [
        for (final a in _acts)
          {
            'start_ts': a.startedAt.millisecondsSinceEpoch ~/ 1000,
            'end_ts': a.startedAt.millisecondsSinceEpoch ~/ 1000,
            'type': a.kind,
            'strain': ?a.strain,
          },
      ];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    if (_loading || _error != null) {
      return Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x4),
                child: NavBar(widget.name)),
            Expanded(
              child: Center(
                child: _error == null
                    ? const CircularProgressIndicator.adaptive()
                    : Padding(
                        padding: const EdgeInsets.all(S.gutter),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: F.body.copyWith(color: p.ink2)),
                      ),
              ),
            ),
          ]),
        ),
      );
    }
    final h = _h;
    final mine = widget.userId == _svc.myId;
    return DataHighlightsScreen(
      title: h?.name ?? widget.name,
      series: _series,
      sessions: _sessions,
      header: [
        _ProfileCard(
          human: h,
          name: widget.name,
          hue: widget.hue,
          recoveryDays: _days.where((d) => d.recovery != null).length,
          streak: _streak(_days),
          busy: _busyFollow,
          onFollow: mine || h == null ? null : _follow,
        ),
        const SizedBox(height: S.x6),
        _TodayRings(_days),
        if (_days.length > 1) ...[
          const SizedBox(height: S.x6),
          _WeekTrend(_days),
        ],
        if (_days.isEmpty) ...[
          const SizedBox(height: S.x4),
          Text(
            mine
                ? 'Nothing shared yet.'
                : '${h?.name ?? widget.name} shares no numbers with you yet.'
                    '${h != null && !h.following_ && !h.requested ? ' Follow to ask for them.' : ''}',
            textAlign: TextAlign.center,
            style: F.body.copyWith(color: p.ink3),
          ),
        ],
      ],
    );
  }
}

/// Days in a row up to today (or yesterday) with any number at all.
int _streak(List<DayScore> days) {
  final have = {
    for (final d in days)
      if (d.recovery != null || d.strain != null || d.sleepMin != null)
        dayLabelOf(d.day),
  };
  var day = DateTime.now();
  if (!have.contains(dayLabelOf(day))) {
    day = DateTime(day.year, day.month, day.day - 1);
  }
  var n = 0;
  while (have.contains(dayLabelOf(day))) {
    n++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return n;
}

class _ProfileCard extends StatelessWidget {
  final Human? human;
  final String name;
  final int hue, recoveryDays, streak;
  final bool busy;
  final VoidCallback? onFollow;
  const _ProfileCard({
    required this.human,
    required this.name,
    required this.hue,
    required this.recoveryDays,
    required this.streak,
    required this.busy,
    this.onFollow,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final h = human;
    final line = h?.handleLine(DateTime.now()) ?? '';
    final since = h?.memberSince;
    Widget stat(String v, String label) => Column(children: [
          Text(v, style: F.head.copyWith(color: p.ink)),
          Text(label.toUpperCase(),
              style: F.over.copyWith(color: p.ink3, letterSpacing: 1)),
        ]);
    final (String follow, bool soft) = h == null
        ? ('Follow', false)
        : h.following_
            ? ('Following', true)
            : h.requested
                ? ('Requested', true)
                : (h.followsMe ? 'Follow back' : 'Follow', false);
    return Column(children: [
      const SizedBox(height: S.x4),
      CommunityAvatar(h?.name ?? name, h?.hue ?? hue,
          size: S.x16 + S.x8, photo: h?.avatarPath),
      const SizedBox(height: S.x4),
      Text((h?.name ?? name).toUpperCase(),
          textAlign: TextAlign.center,
          style: F.t2.copyWith(
              color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
      if (line.isNotEmpty) ...[
        const SizedBox(height: S.x1),
        Text(line, style: F.body.copyWith(color: p.ink2)),
      ],
      if (since != null) ...[
        const SizedBox(height: S.half),
        Text('Member since ${_months[since.month - 1]} ${since.year}',
            style: F.cap.copyWith(color: p.ink3)),
      ],
      const SizedBox(height: S.x5),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        stat('$recoveryDays', 'Level'),
        stat('$streak', 'Day streak'),
        if (h?.followers != null) stat('${h!.followers}', 'Followers'),
        if (h?.following != null) stat('${h!.following}', 'Following'),
      ]),
      if (onFollow != null) ...[
        const SizedBox(height: S.x5),
        BigButton(follow,
            compact: true,
            soft: soft,
            busy: busy,
            icon: soft ? LucideIcons.userCheck : LucideIcons.userRoundPlus,
            onTap: onFollow),
      ],
    ]);
  }
}

/// Today's three rings, where they share them.
class _TodayRings extends StatelessWidget {
  final List<DayScore> days;
  const _TodayRings(this.days);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final key = todayLabel();
    final t = days.where((d) => dayLabelOf(d.day) == key).firstOrNull;
    if (t == null) return const SizedBox.shrink();
    Widget ring(String label, double? v, double top, Color ink, String text) =>
        Expanded(
          child: Column(children: [
            SizedBox.square(
              dimension: S.x16 + S.x4,
              child: CustomPaint(
                painter: _RingPainter(
                    color: v == null ? p.ink3 : ink,
                    track: p.track,
                    fill: v == null ? 0 : (v / top).clamp(0, 1),
                    stroke: S.x1 + S.half),
                child: Center(
                  child: Text(v == null ? '--' : text,
                      style: F.head.copyWith(color: p.ink)),
                ),
              ),
            ),
            const SizedBox(height: S.x2),
            Text(label.toUpperCase(),
                style: F.over.copyWith(color: p.ink2, fontWeight: FontWeight.w800)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: S.x5, horizontal: S.x3),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
      child: Column(children: [
        _label(c, 'Today', color: p.ink2),
        const SizedBox(height: S.x4),
        Row(children: [
          ring('Sleep', t.sleepPerf, 100, C.dialSleep,
              '${(t.sleepPerf ?? 0).round()}%'),
          ring('Recovery', t.recovery, 100, _recoveryInk(t.recovery ?? 0),
              '${(t.recovery ?? 0).round()}%'),
          ring('Strain', t.strain, 21, C.dialStrain,
              (t.strain ?? 0).toStringAsFixed(1)),
        ]),
      ]),
    );
  }
}

/// The last seven days, recovery and strain bars side by side.
class _WeekTrend extends StatelessWidget {
  final List<DayScore> days;
  const _WeekTrend(this.days);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final now = DateTime.now();
    final by = {for (final d in days) dayLabelOf(d.day): d};
    final week = [
      for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i),
    ];
    final rows = [for (final d in week) (d, by[dayLabelOf(d)])];
    if (rows.every((r) => r.$2 == null)) return const SizedBox.shrink();
    const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const h = S.x16;
    return Container(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x5, S.x4, S.x4),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(c, 'This week', color: p.ink2),
        const SizedBox(height: S.x4),
        SizedBox(
          height: h,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (_, d) in rows)
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: S.x2,
                      height: d?.recovery == null
                          ? 0
                          : (d!.recovery! / 100).clamp(.04, 1) * h,
                      decoration: BoxDecoration(
                          color: _recoveryInk(d?.recovery ?? 0),
                          borderRadius: R.rPill),
                    ),
                    const SizedBox(width: S.half),
                    Container(
                      width: S.x2,
                      height:
                          d?.strain == null ? 0 : (d!.strain! / 21).clamp(.04, 1) * h,
                      decoration: BoxDecoration(
                          color: C.dialStrain, borderRadius: R.rPill),
                    ),
                  ],
                ),
              ),
          ]),
        ),
        const SizedBox(height: S.x2),
        Row(children: [
          for (final (d, _) in rows)
            Expanded(
              child: Text(wd[d.weekday - 1],
                  textAlign: TextAlign.center,
                  style: F.over.copyWith(color: p.ink3)),
            ),
        ]),
        const SizedBox(height: S.x3),
        Row(children: [
          _key(c, C.recGreen, 'Recovery'),
          const SizedBox(width: S.x4),
          _key(c, C.dialStrain, 'Strain'),
        ]),
      ]),
    );
  }

  Widget _key(BuildContext c, Color color, String text) => Row(children: [
        Container(
            width: S.x2,
            height: S.x2,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: S.x1),
        Text(text, style: F.cap.copyWith(color: P.of(c).ink3)),
      ]);
}
