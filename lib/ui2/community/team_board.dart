part of 'community.dart';

// A board: the filter, DAILY / MON - SUN / MONTHLY (or BACK TO TODAY once a
// past window is picked), the board's average and when it last moved, then
// the ranked members with your own place pinned when it is out of sight
// (refs 1.7-1.9, 3.1-3.4, 6.13-6.14, humans_4-5).

class _BoardTab extends StatefulWidget {
  final CommunityTeam team;
  final List<TeamPerson> people;
  final BoardMetric metric;
  const _BoardTab(
      {super.key, required this.team, required this.people, required this.metric});

  @override
  State<_BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends State<_BoardTab> {
  DateTime _anchor = DateTime.now();
  BoardPeriod _period = BoardPeriod.day;
  late BoardSort _sort = BoardSort.of(widget.metric).first;
  List<DayScore> _scores = const [];
  List<SharedActivity> _acts = const [];
  bool _loading = true;
  String? _error;

  bool get _isToday {
    final (f, t) = _period.window(DateTime.now());
    final (af, at) = _period.window(_anchor);
    return f == af && t == at;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (from, to) = _period.window(_anchor);
    try {
      final scores = await _svc.scores(widget.team.id, from, to);
      final acts = widget.metric == BoardMetric.strain
          ? await _svc.activities(widget.team.id, from, to)
          : const <SharedActivity>[];
      if (!mounted) return;
      setState(() {
        _scores = scores;
        _acts = acts;
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

  Color get _ink => switch (widget.metric) {
        BoardMetric.strain => C.dialStrain,
        BoardMetric.recovery => C.recGreen,
        BoardMetric.sleep => C.dialSleep,
      };

  String get _metricName => switch (widget.metric) {
        BoardMetric.strain => 'Day Strain',
        BoardMetric.recovery => 'Recovery',
        BoardMetric.sleep => 'Sleep Performance',
      };

  static const _wd = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];

  String _dm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  String get _windowText {
    if (_isToday && _period == BoardPeriod.day) return 'TODAY';
    final (f, t) = _period.window(_anchor);
    return switch (_period) {
      BoardPeriod.day => '${_wd[f.weekday - 1]}, ${_dm(f)}',
      BoardPeriod.week =>
        '${_wd[f.weekday - 1]}, ${_dm(f)} - ${_wd[t.weekday - 1]}, ${_dm(t)}',
      BoardPeriod.month => '${_months[f.month - 1]} ${f.year}'.toUpperCase(),
    };
  }

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')}${t.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _filter() async {
    final r = await AppSheet.open<(BoardPeriod, DateTime, BoardSort)>(
      context,
      scroll: true,
      dragHandle: true,
      builder: (s) => _FilterSheet(
          metric: widget.metric, period: _period, anchor: _anchor, sort: _sort),
    );
    if (r == null || !mounted) return;
    setState(() {
      _period = r.$1;
      _anchor = r.$2;
      _sort = r.$3;
    });
    await _load();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final (from, to) = _period.window(_anchor);
    final rows = rankBoard(_scores, widget.metric, from, to,
        sort: _sort,
        activities: [
          for (final a in _acts)
            BoardActivity(a.userId, a.day, a.kind, strain: a.strain, calories: a.calories),
        ]);
    final avg = boardAverage(rows);
    final updated = _scores
        .map((s) => s.updatedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final people = {for (final m in widget.people) m.id: m};
    final me = _svc.myId;
    final myIndex = rows.indexWhere((r) => r.userId == me);
    return Column(children: [
      const SizedBox(height: S.x16 + S.x6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.gutter),
        child: Row(children: [
          _RingButton(LucideIcons.sliders, 'Filter', _filter),
          const SizedBox(width: S.x3),
          Expanded(
            child: _isToday
                ? RangeSegments(
                    [for (final x in BoardPeriod.values) x.label],
                    _period.index,
                    (i) {
                      setState(() => _period = BoardPeriod.values[i]);
                      _load();
                    },
                    width: null,
                  )
                : BigButton('Back to today', compact: true, fill: true, soft: true,
                    onTap: () {
                    setState(() => _anchor = DateTime.now());
                    _load();
                  }),
          ),
        ]),
      ),
      const SizedBox(height: S.x3),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.gutter),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_metricName.toUpperCase(),
                  style: F.caps.copyWith(
                      color: p.on(_ink), fontWeight: FontWeight.w800, letterSpacing: 1.4)),
              if (avg != null)
                Text('${boardValue(widget.metric, avg)} avg',
                    style: F.cap.copyWith(color: p.on(_ink).withValues(alpha: .8))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_windowText,
                style: F.caps.copyWith(color: p.ink, fontWeight: FontWeight.w800)),
            if (updated != null)
              Text('Last Updated: ${_clock(updated)}',
                  style: F.cap.copyWith(color: p.ink3)),
          ]),
        ]),
      ),
      const SizedBox(height: S.x2),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator.adaptive())
            : _error != null
                ? ListView(padding: const EdgeInsets.all(S.gutter), children: [
                    StatusCard('The board did not load', _error!,
                        fix: 'Try again', icon: LucideIcons.cloudOff, onFix: _load),
                  ])
                : rows.isEmpty
                    ? ListView(padding: const EdgeInsets.all(S.gutter), children: [
                        const SizedBox(height: S.x8),
                        Text(
                          'Nobody has a ${_metricName.toLowerCase()} figure for '
                          '${_isToday && _period == BoardPeriod.day ? 'today' : 'this window'} yet.',
                          textAlign: TextAlign.center,
                          style: F.body.copyWith(color: p.ink3),
                        ),
                      ])
                    : Stack(children: [
                        RefreshIndicator.adaptive(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter,
                                myIndex >= 5 ? S.x16 * 2 : S.x10),
                            itemCount: rows.length,
                            itemBuilder: (c, i) => _BoardRowView(
                              rank: i + 1,
                              row: rows[i],
                              person: people[rows[i].userId],
                              metric: widget.metric,
                              period: _period,
                            ),
                          ),
                        ),
                        if (myIndex >= 5)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: C.char,
                              padding: EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter,
                                  S.x2 + MediaQuery.paddingOf(c).bottom),
                              child: _BoardRowView(
                                rank: myIndex + 1,
                                row: rows[myIndex],
                                person: people[me],
                                metric: widget.metric,
                                period: _period,
                                compact: true,
                              ),
                            ),
                          ),
                      ]),
      ),
    ]);
  }
}

/// "1. Josh Atkins 20.6 / Running 20.6 / 3,720 Calories".
class _BoardRowView extends StatelessWidget {
  final int rank;
  final BoardRow row;
  final TeamPerson? person;
  final BoardMetric metric;
  final BoardPeriod period;
  final bool compact;
  const _BoardRowView({
    required this.rank,
    required this.row,
    required this.person,
    required this.metric,
    required this.period,
    this.compact = false,
  });

  Color _valueInk(P p) => switch (metric) {
        BoardMetric.strain => C.dialStrain,
        BoardMetric.sleep => C.dialSleep,
        BoardMetric.recovery => row.headline >= 67
            ? C.recGreen
            : row.headline >= 34
                ? C.recYellow
                : C.recRed,
      };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final name = person?.name ?? 'Member';
    String actName(String kind) =>
        activityByName(kind)?.displayName(c) ?? kind;
    String one(double? v) => v == null ? '--' : v.toStringAsFixed(1);
    final lines = <String>[];
    switch (metric) {
      case BoardMetric.strain:
        if (period == BoardPeriod.day) {
          if (row.activities.isNotEmpty) {
            lines.add(row.activities
                .map((a) => '${actName(a.kind)} ${one(a.strain)}')
                .join(', '));
          }
        } else if (row.activities.isNotEmpty) {
          final a = row.activities.first;
          lines.add('${actName(a.kind)} ${one(a.strain)} on '
              '${a.day.day.toString().padLeft(2, '0')}/${a.day.month.toString().padLeft(2, '0')}');
        }
        if (row.calories != null) {
          lines.add('${groupThousands(row.calories!.round())} Calories');
        }
      case BoardMetric.recovery:
        final parts = [
          if (row.hrv != null) 'HRV: ${row.hrv!.round()}',
          if (row.rhr != null) 'RHR: ${row.rhr!.round()}',
        ];
        if (parts.isNotEmpty) lines.add(parts.join(', '));
      case BoardMetric.sleep:
        if (row.sleepMin != null) {
          lines.add('${hoursClock(row.sleepMin!)} hours of sleep');
        }
    }
    final fill = switch (metric) {
      BoardMetric.strain => row.headline / 21,
      _ => row.headline / 100,
    };
    final ink = _valueInk(p);
    return Pressable(
      onTap: person == null
          ? null
          : () => go(c, MemberProfile(userId: row.userId, name: name, hue: person!.hue)),
      semanticLabel: '$rank. $name ${boardValue(metric, row.headline)}',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? S.x1 : S.x3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CommunityAvatar(name, person?.hue ?? 0,
              size: S.x16, photo: person?.avatarPath, ring: ink, fill: fill),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: S.x1),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '$rank. $name  ',
                      style: F.head.copyWith(color: p.ink)),
                  TextSpan(
                      text: boardValue(metric, row.headline),
                      style: F.head.copyWith(color: p.on(ink))),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              for (final l in lines)
                Text(l,
                    maxLines: compact ? 1 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: F.body.copyWith(color: p.ink3, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The filter: the window kind, a month calendar to pick the day, week or
/// month, and what the board is sorted by (3.2-3.3).
class _FilterSheet extends StatefulWidget {
  final BoardMetric metric;
  final BoardPeriod period;
  final DateTime anchor;
  final BoardSort sort;
  const _FilterSheet(
      {required this.metric,
      required this.period,
      required this.anchor,
      required this.sort});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late var _period = widget.period;
  late var _anchor = widget.anchor;
  late var _sort = widget.sort;
  late var _month = DateTime(widget.anchor.year, widget.anchor.month);

  bool _picked(DateTime d) {
    final (f, t) = _period.window(_anchor);
    return !d.isBefore(f) && !d.isAfter(t);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final today = DateTime.now();
    final last = DateTime(today.year, today.month, today.day);
    final sorts = BoardSort.of(widget.metric);
    final first = DateTime(_month.year, _month.month, 1);
    final lead = first.weekday - 1;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = [
      for (var i = 0; i < lead; i++) DateTime(_month.year, _month.month, 1 - lead + i),
      for (var d = 1; d <= days; d++) DateTime(_month.year, _month.month, d),
    ];
    for (var k = 1; cells.length % 7 != 0; k++) {
      cells.add(DateTime(_month.year, _month.month, days + k));
    }
    final rows = [for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7)];
    final nextMonth = DateTime(_month.year, _month.month + 1);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RangeSegments([for (final x in BoardPeriod.values) x.label], _period.index,
                (i) => setState(() => _period = BoardPeriod.values[i]),
                width: null),
            const SizedBox(height: S.x3),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Pressable(
                onTap: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1)),
                semanticLabel: 'Earlier month',
                child: SizedBox.square(
                    dimension: S.tap,
                    child: Icon(LucideIcons.chevronLeft, size: I.md, color: p.ink)),
              ),
              SizedBox(
                width: S.x16 * 2.4,
                child: Text(
                    '${_FilterSheetState._monthNames[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: F.head.copyWith(color: p.ink)),
              ),
              Pressable(
                onTap: nextMonth.isAfter(last)
                    ? null
                    : () => setState(() => _month = nextMonth),
                semanticLabel: 'Later month',
                child: SizedBox.square(
                    dimension: S.tap,
                    child: Icon(LucideIcons.chevronRight,
                        size: I.md,
                        color: nextMonth.isAfter(last) ? p.ink3 : p.ink)),
              ),
            ]),
            const SizedBox(height: S.x2),
            Row(children: [
              for (final w in _BoardTabState._wd)
                Expanded(
                  child: Text(w,
                      textAlign: TextAlign.center,
                      style: F.over.copyWith(color: p.ink3)),
                ),
            ]),
            const SizedBox(height: S.x2),
            for (final week in rows)
              Container(
                height: S.tap,
                decoration: _period == BoardPeriod.week && week.any(_picked)
                    ? BoxDecoration(
                        borderRadius: R.rPill,
                        border: Border.all(color: C.dialStrain, width: S.half))
                    : null,
                child: Row(children: [
                  for (final d in week)
                    Expanded(
                      child: Pressable(
                        onTap: d.isAfter(last) ? null : () => setState(() => _anchor = d),
                        semanticLabel: '${d.day}',
                        child: Center(
                          child: Container(
                            width: S.x10 - S.x1,
                            height: S.x10 - S.x1,
                            alignment: Alignment.center,
                            decoration: _period == BoardPeriod.day && _picked(d)
                                ? BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: C.dialStrain, width: S.half))
                                : _period == BoardPeriod.month &&
                                        _picked(d) &&
                                        d.month == _month.month
                                    ? BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: C.dialStrain.withValues(alpha: .25))
                                    : null,
                            child: Text(d.day.toString().padLeft(2, '0'),
                                style: F.body.copyWith(
                                    color: d.month != _month.month || d.isAfter(last)
                                        ? p.ink3.withValues(alpha: .5)
                                        : p.ink)),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: S.x4),
            Divider(color: p.line, height: S.hair),
            const SizedBox(height: S.x4),
            _label(c, 'Sort by', color: p.ink3),
            const SizedBox(height: S.x3),
            RangeSegments([for (final s in sorts) s.label], sorts.indexOf(_sort),
                (i) => setState(() => _sort = sorts[i]),
                width: null),
            const SizedBox(height: S.x6),
            BigButton('Apply',
                onTap: () => Navigator.of(c).pop((_period, _anchor, _sort))),
          ],
        ),
      ),
    );
  }

  static const _monthNames = _BoardTabState._months;
}
