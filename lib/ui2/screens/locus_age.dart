// Locus Age: how old your habits and fitness make you, and how fast that is
// moving. The living blob holds the number; scrolling shrinks it to the top
// so the contributors can be read under it.
//
// Every figure comes from `compute/whoop_age.dart`. A contributor with no data
// has no row, and until the age unlocks no years are shown against any of them.

import '../../state/duration_format.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../compute/whoop_age.dart';
import '../../data/day_label.dart';
import '../ui2.dart';
import 'coach.dart';
import 'dial_parts.dart';
import 'home_screen.dart' show monthShortName, repoOf;
import 'locus_blob.dart';
import 'trend_view.dart';

// ─────────────────────── what each contributor is ───────────────────────

/// One line of a contributor's value: the figure and its unit.
typedef LocusValue = ({String value, String unit});

class LocusRow {
  final String key, title, name, trendId;
  final double min, max;
  final String minLabel, maxLabel;
  final bool higherBetter;
  final LocusValue Function(double) format;
  const LocusRow(
    this.key,
    this.title,
    this.name,
    this.trendId,
    this.min,
    this.max,
    this.minLabel,
    this.maxLabel,
    this.format, {
    this.higherBetter = true,
  });
}

LocusValue _hmmMinutes(double m) {
  return (value: durationText(m), unit: '');
}

LocusValue _hours(double h) => _hmmMinutes(h * 60);
LocusValue _percent(double v) => (value: '${v.round()}%', unit: '');
LocusValue _percent1(double v) => (value: '${v.toStringAsFixed(1)}%', unit: '');
LocusValue _vo2(double v) => (value: '${v.round()}', unit: 'mL/kg/min');
LocusValue _bpm(double v) => (value: '${v.round()}', unit: 'bpm');
LocusValue _steps(double v) {
  final s = v.round().toString();
  final head = s.length > 3 ? '${s.substring(0, s.length - 3)},' : '';
  return (
    value: '$head${s.length > 3 ? s.substring(s.length - 3) : s}',
    unit: 'Steps',
  );
}

const kLocusGroups = <(String, List<LocusRow>)>[
  (
    'Sleep',
    [
      LocusRow('consistency', 'Sleep consistency', 'sleep consistency',
          'consistency', 40, 100, '40%', '100%', _percent),
      LocusRow('sleep_hours', 'Hours of sleep', 'hours of sleep', 'hvn_hours',
          5, 8, '5h', '8h', _hours),
    ],
  ),
  (
    'Strain',
    [
      LocusRow('zones_13', 'Time in HR zones 1-3 (weekly)',
          'time in heart rate zones 1 to 3', 'zones_13', 0, 180, '0h', '3h',
          _hmmMinutes),
      LocusRow('zones_45', 'Time in HR zones 4-5 (weekly)',
          'time in heart rate zones 4 and 5', 'zones_45', 0, 60, '0h', '1h',
          _hmmMinutes),
      LocusRow('strength', 'Strength activity time (weekly)', 'strength time',
          'strength_time', 0, 180, '0h', '3h', _hmmMinutes),
      LocusRow('steps', 'Steps', 'steps', 'steps', 0, 16000, '0K', '16K',
          _steps),
    ],
  ),
  (
    'Fitness',
    [
      LocusRow('vo2max', 'VO₂ max', 'VO₂ max', 'vo2max', 15, 70, '15', '70',
          _vo2),
      LocusRow('resting_hr', 'RHR', 'resting heart rate', 'resting_hr', 40, 80,
          '40bpm', '80bpm', _bpm,
          higherBetter: false),
      LocusRow('lean_mass', 'Lean body mass', 'lean body mass', 'resting_hr',
          60, 90, '60%', '90%', _percent1),
    ],
  ),
];

LocusRow? _rowOf(String key) {
  for (final g in kLocusGroups) {
    for (final r in g.$2) {
      if (r.key == key) return r;
    }
  }
  return null;
}

// ───────────────────────── weeks and wording ────────────────────────────

/// Weeks run Sunday to Saturday. The last [n] Saturdays already over on
/// [today], newest first.
List<String> finishedSaturdays(String today, int n) {
  final t = DateTime.parse(today);
  var back = (t.weekday - DateTime.saturday) % 7;
  if (back == 0) back = 7;
  return [
    for (var i = 0; i < n; i++)
      dayLabelOf(DateTime(t.year, t.month, t.day - back - 7 * i)),
  ];
}

/// Days until the next week is finished and shown.
int daysToNextUpdate(String today) =>
    7 - DateTime.parse(today).weekday % 7;

/// The contributor that has moved most between the long and short windows, in
/// the bad direction when [worst], the good one otherwise. Null when none has.
String? biggestMover(WhoopAgeResult r, {required bool worst}) {
  String? best;
  var size = .02;
  for (final e in r.recent.entries) {
    final long = r.parts[e.key];
    if (long == null) continue;
    final gap = (e.value.years - long.years) * (worst ? 1 : -1);
    if (gap > size) {
      size = gap;
      best = e.key;
    }
  }
  return best;
}

String _capital(String s) => s[0].toUpperCase() + s.substring(1);

/// The note under the pace strip, from this week and the one before it.
({String title, String body}) paceInsight(
  WhoopAgeResult now,
  WhoopAgeResult? before,
) {
  final pace = now.pace;
  final age = now.whoopAge;
  final prior = before?.whoopAge;
  final delta = age == null || prior == null ? null : age - prior;
  final moved = delta == null
      ? 'This is your first full week of readings.'
      : delta.abs() < .05
          ? 'Your Locus Age did not move this week.'
          : 'Your Locus Age went ${delta > 0 ? 'up' : 'down'} by '
              '${delta.abs().toStringAsFixed(1)} this week.';
  final speed = pace == null
      ? ''
      : ' Your Pace of Aging is '
          '${pace < .9 ? 'slow' : pace <= 1.1 ? 'about one year per year' : 'fast'}.';
  final worst = pace != null && pace >= 1;
  final key = biggestMover(now, worst: worst);
  final name = key == null ? null : _rowOf(key)?.name;
  final lead = name == null
      ? ''
      : worst
          ? ' ${_capital(name)} has slipped the most lately, so a small '
              'change there is the quickest way to slow it down.'
          : ' ${_capital(name)} is helping the most lately, so keep it going.';
  final title = pace != null && pace > 1.1
      ? 'Picking up speed'
      : delta != null && delta <= -.05
          ? 'Moving the right way'
          : delta != null && delta >= .05
              ? 'Worth watching'
              : 'Holding steady';
  return (title: title, body: '$moved$speed$lead');
}

/// The note in an opened row.
({String title, String body}) rowInsight(
  LocusRow row,
  WhoopAgePart long,
  WhoopAgePart? recent,
) {
  final gap = recent == null ? 0.0 : recent.years - long.years;
  if (gap <= -.2) {
    return (
      title: 'Improving',
      body: 'Your last 30 days beat your six month average for ${row.name}. '
          'Keep this up and your Locus Age should come down over time.',
    );
  }
  if (gap >= .2) {
    return (
      title: 'Slipping',
      body: 'Your last 30 days are behind your six month average for '
          '${row.name}. Getting back to it would slow your Pace of Aging.',
    );
  }
  if (long.years <= -.2) {
    return (
      title: 'Ahead of target',
      body: 'Your ${row.name} is taking years off your Locus Age. It is '
          'worth protecting.',
    );
  }
  if (long.years >= .2) {
    return (
      title: 'Room to gain',
      body: 'Your ${row.name} is adding to your Locus Age. Moving it toward '
          '${row.format(long.target).value} would take that back off.',
    );
  }
  return (
    title: 'On target',
    body: 'Your ${row.name} is close to where it needs to be, and is '
        'neither adding to nor taking from your Locus Age.',
  );
}

// ─────────────────────────────── screen ─────────────────────────────────

class _Week {
  final String end, label;
  final WhoopAgeResult r;
  const _Week(this.end, this.label, this.r);
}

class LocusAgeScreen extends StatefulWidget {
  /// Opened over another screen, with a way back, rather than as a tab.
  final bool page;

  /// Injected by tests and renders; production builds its own.
  final TrendLoader? loader;
  final String? today;

  const LocusAgeScreen({super.key, this.page = false, this.loader, this.today});

  @override
  State<LocusAgeScreen> createState() => _LocusAgeScreenState();
}

class _LocusAgeScreenState extends State<LocusAgeScreen>
    with RevisionReload, SingleTickerProviderStateMixin {
  // The two poses of the blob, in points below the top inset.
  static const _heroD = 274.0, _heroY = 209.0, _smallD = 100.0, _smallY = 58.0;
  static const _headerFull = 366.0, _headerSmall = 118.0;

  final _sim = BlobSim();
  final _frame = ValueNotifier<int>(0);
  final _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  Duration? _downAt;
  Offset? _downPos;
  bool _touching = false;

  WhoopAgeResult? _latest;
  List<_Week> _weeks = const [];
  int _at = 0;
  bool _loaded = false, _bannerGone = false;
  final _open = <String>{'consistency'};

  String get _today => widget.today ?? todayLabel();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.enabled(context)) {
      if (!_ticker.isActive) {
        _last = Duration.zero;
        unawaited(_ticker.start());
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
    if (!_loaded && _latest == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
  }

  @override
  bool get revisionReloads => widget.loader == null;

  @override
  void reload() => unawaited(_load());

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = now;
    _sim.step(dt);
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = beginRead(#age);
    final loader = widget.loader ?? TrendLoader(repoOf(context));
    final latest = await loader.whoopAge(asOf: _today);
    final weeks = <_Week>[];
    for (final end in finishedSaturdays(_today, 26).reversed) {
      final r = await loader.whoopAge(asOf: end);
      if (r.whoopAge != null) weeks.add(_Week(end, _weekLabel(end), r));
    }
    if (!mounted || !stillNewest(#age, token)) return;
    setState(() {
      _latest = latest;
      _loaded = true;
      if (weeks.isEmpty && latest.whoopAge != null) {
        weeks.add(_Week(_today, 'THIS WEEK', latest));
      }
      _weeks = weeks;
      _at = math.max(0, weeks.length - 1);
    });
  }

  String _weekLabel(String end) {
    final e = DateTime.parse(end);
    final s = DateTime(e.year, e.month, e.day - 6);
    String part(DateTime d) => '${monthShortName(d.month, null)} ${d.day}';
    return '${part(s)} – ${part(e)}'.toUpperCase();
  }

  _Week? get _week => _weeks.isEmpty ? null : _weeks[_at];

  /// Unlocked, the chosen week; until then, today's progress towards it.
  WhoopAgeResult get _shown =>
      _week?.r ?? _latest ?? const WhoopAgeResult(why: 'no_data');

  (double, Offset) _pose(double t, double width, double top) {
    final d = _heroD + (_smallD - _heroD) * t;
    final y = top + _heroY + (_smallY - _heroY) * t;
    return (d, Offset(width / 2, y));
  }

  double get _t {
    if (!_scroll.hasClients) return 0;
    return (_scroll.offset / (_headerFull - _headerSmall)).clamp(0.0, 1.0);
  }

  // This only watches where the finger is. A touch that lands on the blob is
  // claimed by [_blobGrab], so the page does not scroll under it: playing
  // with the blob used to drag the page along.
  Offset? _unit(Offset pos, double width, double top) {
    final (d, c) = _pose(_t, width, top);
    final u = (pos - c) / (d / 2);
    return u;
  }

  void _down(PointerDownEvent e, double width, double top) {
    final u = _unit(e.localPosition, width, top);
    if (u == null || u.distance > 1.15) return;
    _touching = true;
    _downAt = e.timeStamp;
    _downPos = e.localPosition;
    _sim.press(u.dx, u.dy);
    unawaited(HapticFeedback.selectionClick());
  }

  void _move(PointerMoveEvent e, double width, double top) {
    if (!_touching) return;
    final u = _unit(e.localPosition, width, top);
    if (u != null) _sim.press(u.dx, u.dy);
  }

  void _up(PointerEvent e, double width, double top) {
    if (!_touching) return;
    _touching = false;
    _sim.release();
    final at = _downAt, pos = _downPos;
    if (e is PointerUpEvent &&
        at != null &&
        pos != null &&
        e.timeStamp - at < Motion.slow &&
        (e.localPosition - pos).distance < S.x3) {
      final u = _unit(e.localPosition, width, top);
      if (u != null) {
        _sim.tap(u.dx, u.dy);
        unawaited(HapticFeedback.lightImpact());
      }
    }
  }

  (Color, Color, Color) _tones() {
    final r = _shown;
    final age = r.whoopAge, base = r.age;
    if (age == null || base == null) {
      return (AC.lockedTop, AC.lockedBottom, DC.ink3);
    }
    final delta = age - base;
    if (delta > -.05) return (AC.olderTop, AC.olderBottom, AC.olderText);
    if (delta > -4) return (AC.tealTop, AC.tealBottom, AC.tealText);
    return (AC.greenTop, AC.greenBottom, AC.greenText);
  }

  String _deltaWords() {
    final r = _shown;
    final age = r.whoopAge, base = r.age;
    if (age != null && base != null) {
      final d = age - base;
      final n = d.abs().toStringAsFixed(1);
      return d.abs() < .05
          ? 'same as your age'
          : '$n years ${d > 0 ? 'older' : 'younger'}';
    }
    final why = _latest?.why ?? '';
    final have = RegExp(r'have=(\d+)').firstMatch(why)?.group(1);
    if (have != null) return '$have of $kWhoopAgeUnlockRecoveries recoveries';
    return switch (why) {
      'needs_age' => 'add your birth date',
      'under_18' => 'for adults only',
      _ => 'not enough data yet',
    };
  }

  @override
  Widget build(BuildContext c) {
    final mq = MediaQuery.of(c);
    final top = mq.padding.top;
    final width = mq.size.width;
    final r = _shown;
    final (toneTop, toneBottom, toneText) = _tones();

    final body = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: _list(c, top, r),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _scroll,
              builder: (_, _) => _overlay(
                c, top, width, r, toneTop, toneBottom, toneText,
              ),
            ),
          ),
        ),
        _blobGrab(top, width),
        // Above the overlay: these two must stay tappable.
        Positioned(
          top: top + S.x1,
          right: S.x4,
          child: SizedBox(
            width: S.x10,
            height: S.x10,
            child: Center(
              child: DialInfo('Locus Age', _aboutWithUpdate(_today)),
            ),
          ),
        ),
        if (widget.page)
          Positioned(
            top: top + S.x1,
            left: S.x2,
            child: Pressable(
              semanticLabel: 'Back',
              onTap: () => Navigator.of(c).maybePop(),
              child: const SizedBox(
                width: S.x10,
                height: S.x10,
                child: Icon(LucideIcons.chevronLeft, size: I.lg, color: DC.ink),
              ),
            ),
          ),
        if (_week != null) _pager(c, top),
      ],
    );

    return Scaffold(
        backgroundColor: AC.page,
        body: TouchWatcher(
          onDown: (e) => _down(e, width, top),
          onMove: (e) => _move(e, width, top),
          onUp: (e) => _up(e, width, top),
          onCancel: (e) => _up(e, width, top),
          child: body,
        ),
      );
  }

  /// A circle over the blob, wherever it is posed, that wins every touch
  /// landing on it the moment it lands: the list's drag never gets it. The
  /// blob still reads the finger through [TouchWatcher].
  Widget _blobGrab(double top, double width) => AnimatedBuilder(
    animation: _scroll,
    builder: (_, _) {
      final (d, c) = _pose(_t, width, top);
      return Positioned(
        left: c.dx - d / 2,
        top: c.dy - d / 2,
        width: d,
        height: d,
        child: const ClipOval(child: TouchClaim()),
      );
    },
  );

  Widget _pager(BuildContext c, double top) {
    final week = _week!;
    final canBack = _at > 0, canNext = _at < _weeks.length - 1;
    return AnimatedBuilder(
      animation: _scroll,
      builder: (_, _) {
        final fade = (1 - _t * 3).clamp(0.0, 1.0);
        // On the info button's line: the countdown lives in its sheet.
        return Positioned(
          top: top + S.x1,
          left: S.x10 + S.x4,
          right: S.x10 + S.x4,
          child: IgnorePointer(
            ignoring: fade < .5,
            child: Opacity(
              opacity: fade,
              child: Column(
                children: [
                  SizedBox(
                    height: S.x10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _chevron(LucideIcons.chevronLeft, canBack, -1),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              week.label,
                              style: F.dLabel.copyWith(color: DC.ink),
                            ),
                          ),
                        ),
                        _chevron(LucideIcons.chevronRight, canNext, 1),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chevron(IconData icon, bool on, int by) => Pressable(
    semanticLabel: by < 0 ? 'Earlier week' : 'Later week',
    onTap: on ? () => setState(() => _at += by) : null,
    child: SizedBox(
      width: S.x10,
      height: S.x10,
      child: Icon(icon, size: I.md, color: on ? DC.ink : DC.dim),
    ),
  );

  Widget _overlay(
    BuildContext c,
    double top,
    double width,
    WhoopAgeResult r,
    Color toneTop,
    Color toneBottom,
    Color toneText,
  ) {
    final t = _t;
    final (d, centre) = _pose(t, width, top);
    final canvas = d * 1.5;
    final head = top + _headerFull + (_headerSmall - _headerFull) * t;
    final sides = ((t - .55) / .45).clamp(0.0, 1.0);
    final subFade = (1 - t * 3).clamp(0.0, 1.0);
    final sideW = (width - _smallD) / 2 - S.x3;
    final age = r.whoopAge;
    final base = r.age;
    final delta = age == null || base == null ? null : age - base;
    return Stack(
      children: [
        if (t > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: head + S.x4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AC.page, AC.page, AC.page.withValues(alpha: 0)],
                  stops: [0, head / (head + S.x4), 1],
                ),
              ),
            ),
          ),
        Positioned(
          left: centre.dx - canvas / 2,
          top: centre.dy - canvas / 2,
          width: canvas,
          height: canvas,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: LocusBlobPainter(
                sim: _sim,
                radius: d / 2,
                top: toneTop,
                bottom: toneBottom,
                repaint: _frame,
              ),
            ),
          ),
        ),
        Positioned(
          left: centre.dx - d / 2,
          top: centre.dy - d / 2,
          width: d,
          height: d,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(d * .12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      age == null ? '--' : age.toStringAsFixed(1),
                      style: TextStyle.lerp(AC.ageNum, AC.ageNumSmall, t)!
                          .copyWith(color: DC.ink),
                    ),
                    SizedBox(height: S.x2 * (1 - t) + S.x1),
                    Text(
                      'LOCUS AGE',
                      style: TextStyle.lerp(AC.ageLabel, AC.ageLabelSmall, t)!
                          .copyWith(color: DC.ink2),
                    ),
                    if (subFade > 0) ...[
                      SizedBox(height: S.x1 * subFade),
                      Opacity(
                        opacity: subFade,
                        child: Text(
                          _deltaWords(),
                          style: AC.ageDelta.copyWith(color: toneText),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (sides > 0) ...[
          Positioned(
            left: S.x2,
            width: sideW,
            top: centre.dy - S.x5,
            child: Opacity(
              opacity: sides,
              child: _sideStat(
                delta == null ? '--' : delta.abs().toStringAsFixed(1),
                delta == null
                    ? 'YEARS'
                    : delta > 0
                        ? 'YEARS OLDER'
                        : 'YEARS YOUNGER',
                toneText,
              ),
            ),
          ),
          Positioned(
            right: S.x2,
            width: sideW,
            top: centre.dy - S.x5,
            child: Opacity(
              opacity: sides,
              child: _sideStat(
                r.pace == null ? '--' : '${r.pace!.toStringAsFixed(1)}x',
                'PACE OF AGING',
                DC.ink,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sideStat(String value, String label, Color colour) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Column(
      children: [
        Text(value, style: AC.sideNum.copyWith(color: colour)),
        const SizedBox(height: S.x1),
        Text(label, style: F.dLabel.copyWith(color: DC.ink)),
      ],
    ),
  );

  Widget _list(BuildContext c, double top, WhoopAgeResult r) {
    final unlocked = r.whoopAge != null;
    final before = _at > 0 ? _weeks[_at - 1].r : null;
    final insight = unlocked ? paceInsight(r, before) : null;
    final showBanner = !_bannerGone && _loaded && _weeks.length < 6;
    final have = RegExp(r'have=(\d+)').firstMatch(_latest?.why ?? '')?.group(1);
    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: top + _headerFull,
        bottom: S.navClear(c) + S.x6,
      ),
      children: [
        if (showBanner)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x5),
            child: _Banner(
              body: unlocked
                  ? 'Your history is still short, so expect this number to '
                      'move around. It settles as more weeks build up.'
                  : have == null
                      ? 'Locus Age needs your birth date and '
                          '$kWhoopAgeUnlockRecoveries recoveries in '
                          '$kWhoopAgeUnlockWindow days.'
                      : 'Your first reading needs '
                          '$kWhoopAgeUnlockRecoveries recoveries in '
                          '$kWhoopAgeUnlockWindow days. You have $have so '
                          'far. Importing older data counts too.',
              onClose: () => setState(() => _bannerGone = true),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x5),
          child: _PaceStrip(pace: r.pace),
        ),
        if (insight != null) ...[
          const SizedBox(height: S.x5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: _InsightCard(
              title: insight.title,
              body: insight.body,
              onCoach: () => openCoachSheet(c),
            ),
          ),
        ],
        for (final g in kLocusGroups)
          if (g.$2.any((row) => r.parts.containsKey(row.key)))
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x8, S.x4, 0),
              child: _section(c, g.$1, g.$2, r, unlocked),
            ),
        if (_weeks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x4, S.x8, S.x4, S.x3),
            child: Text(
              'Trend View',
              style: AC.section.copyWith(color: DC.ink),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: LocusAgeTrends(
              weeks: [for (final w in _weeks) (end: w.end, r: w.r)],
            ),
          ),
        ],
      ],
    );
  }

  Widget _section(
    BuildContext c,
    String title,
    List<LocusRow> rows,
    WhoopAgeResult r,
    bool unlocked,
  ) {
    final shown = [for (final row in rows) if (r.parts.containsKey(row.key)) row];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: S.x1,
          children: [
            SizedBox(
              width: double.infinity,
              child: Row(
                children: [
                  Text(title, style: AC.section.copyWith(color: DC.ink)),
                  const Spacer(),
                  const _Legend(),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x3),
        ClipRRect(
          borderRadius: R.rXl,
          child: ColoredBox(
            color: AC.row,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++)
                  _Contributor(
                    row: shown[i],
                    long: r.parts[shown[i].key]!,
                    recent: r.recent[shown[i].key],
                    showYears: unlocked,
                    open: _open.contains(shown[i].key),
                    // No rule under an open row: its darker ground is the edge.
                    divider: i > 0 && !_open.contains(shown[i - 1].key),
                    onToggle: () => setState(() {
                      if (!_open.remove(shown[i].key)) _open.add(shown[i].key);
                    }),
                    onTrend: () => Navigator.of(c).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            TrendViewScreen(initial: shown[i].trendId),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The info sheet's words, with when the next weekly reading lands.
String _aboutWithUpdate(String today) {
  final days = daysToNextUpdate(today);
  final when = days == 1 ? 'tomorrow' : 'in $days days';
  return 'Locus Age updates once a week, on Sunday. The next update is '
      '$when.\n\n$_about';
}

const _about =
    'Locus Age estimates how old your sleep, activity and fitness habits '
    'make you, compared with your real age. Each one is held against a '
    'target from published mortality research, and the years add up over '
    'the last six months.\n\n'
    'Pace of Aging asks how fast that age would move if your last 30 days '
    'carried on. 1.0x is one year per year.\n\n'
    'The way the pieces are combined is our own estimate, and it is not '
    'medical advice.';

// ──────────────────────────────── parts ─────────────────────────────────

class _Banner extends StatelessWidget {
  final String body;
  final VoidCallback onClose;
  const _Banner({required this.body, required this.onClose});

  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x2, S.x4),
    decoration: const BoxDecoration(color: AC.banner, borderRadius: R.rXl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.lightbulb, size: I.sm, color: AC.olderText),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text(
                'Locus Age is calibrating',
                style: F.dBody.copyWith(color: AC.olderText),
              ),
            ),
            Pressable(
              semanticLabel: 'Dismiss',
              onTap: onClose,
              child: const SizedBox(
                width: S.x10,
                height: S.x8,
                child: Icon(LucideIcons.x, size: I.sm, color: DC.ink2),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: S.x2),
          child: Text(body, style: AC.body.copyWith(color: DC.ink)),
        ),
      ],
    ),
  );
}

class _PaceStrip extends StatelessWidget {
  final double? pace;
  const _PaceStrip({required this.pace});

  @override
  Widget build(BuildContext c) {
    final p = pace;
    final at = p == null ? null : (p + 1) / 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PACE OF AGING', style: F.dLabel.copyWith(color: DC.ink)),
        const SizedBox(height: S.x1),
        SizedBox(
          height: S.x6,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Align(
                alignment: Alignment.bottomLeft,
                child: _end(LucideIcons.turtle, 'Slow', false),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: _end(LucideIcons.rabbit, 'Fast', true),
              ),
              Align(
                // Clear of the two end words, however extreme the pace.
                alignment: Alignment(
                  (at ?? .5).clamp(.18, .82) * 2 - 1,
                  1,
                ),
                child: Text(
                  p == null ? '--' : '${p.toStringAsFixed(1)}x',
                  style: AC.sideNum.copyWith(color: DC.ink),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x1),
        CustomPaint(
          size: const Size(double.infinity, S.x8),
          painter: _TicksPainter(at),
        ),
        const SizedBox(height: S.x1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final l in const ['-1.0x', '1.0x', '3.0x'])
              Text(l, style: AC.barLabel.copyWith(color: DC.ink3)),
          ],
        ),
      ],
    );
  }

  Widget _end(IconData icon, String word, bool iconLast) {
    final bits = [
      Icon(icon, size: I.sm - S.half, color: DC.ink3),
      const SizedBox(width: S.x1),
      Text(word, style: AC.barLabelMid.copyWith(color: DC.ink3)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: iconLast ? bits.reversed.toList() : bits,
    );
  }
}

class _TicksPainter extends CustomPainter {
  final double? at;
  const _TicksPainter(this.at);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 100;
    final paint = Paint()..strokeWidth = S.hair;
    final mid = size.height / 2;
    for (var i = 0; i <= n; i++) {
      final f = i / n;
      final near = at == null ? 0.0 : math.exp(-math.pow((f - at!) / .035, 2));
      final centre = i == n ~/ 2;
      final h = size.height * (.62 + .22 * near + (centre ? .2 : 0));
      paint.color = DC.ink.withValues(
        alpha: (centre ? .55 : .22) + .55 * near,
      );
      final x = f * size.width;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
    if (at case final a?) {
      final x = a.clamp(0.0, 1.0) * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..strokeWidth = S.half
          ..color = DC.ink,
      );
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => old.at != at;
}

class _InsightCard extends StatelessWidget {
  final String title, body;
  final VoidCallback onCoach;
  const _InsightCard({
    required this.title,
    required this.body,
    required this.onCoach,
  });

  @override
  Widget build(BuildContext c) => Column(
    children: [
      const CustomPaint(size: Size(S.x4, S.x2), painter: _NotchPainter()),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x4),
        decoration: const BoxDecoration(color: AC.card, borderRadius: R.rXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AC.rowTitle.copyWith(color: DC.ink)),
            const SizedBox(height: S.x1),
            Text(body, style: AC.body.copyWith(color: DC.ink2)),
            const SizedBox(height: S.x3),
            _LinkLabel('ASK THE COACH ABOUT THIS', AC.coach, onCoach),
          ],
        ),
      ),
    ],
  );
}

class _NotchPainter extends CustomPainter {
  const _NotchPainter();
  @override
  void paint(Canvas canvas, Size s) => canvas.drawPath(
    Path()
      ..moveTo(0, s.height)
      ..lineTo(s.width / 2, 0)
      ..lineTo(s.width, s.height)
      ..close(),
    Paint()..color = AC.card,
  );
  @override
  bool shouldRepaint(_NotchPainter old) => false;
}

class _LinkLabel extends StatelessWidget {
  final String label;
  final Color colour;
  final VoidCallback onTap;
  const _LinkLabel(this.label, this.colour, this.onTap);

  @override
  Widget build(BuildContext c) => Pressable(
    semanticLabel: label,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, style: F.dLabel.copyWith(color: colour)),
          ),
          const SizedBox(width: S.x2),
          Icon(LucideIcons.arrowRight, size: I.sm, color: colour),
        ],
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CustomPaint(
        size: Size(S.x2 + S.x1, S.x2),
        painter: _MarkPainter(down: true, colour: DC.ink),
      ),
      const SizedBox(width: S.x1 + S.half),
      Text('6 Month avg.', style: AC.barLabelMid.copyWith(color: DC.ink2)),
      const SizedBox(width: S.x3),
      Container(width: S.hair, height: S.x4, color: DC.line),
      const SizedBox(width: S.x3),
      const CustomPaint(
        size: Size(S.x2 + S.x1, S.x2),
        painter: _MarkPainter(down: false, colour: DC.ink3),
      ),
      const SizedBox(width: S.x1 + S.half),
      Text('30 Day avg.', style: AC.barLabelMid.copyWith(color: DC.ink3)),
    ],
  );
}

class _MarkPainter extends CustomPainter {
  final bool down;
  final Color colour;
  const _MarkPainter({required this.down, required this.colour});

  @override
  void paint(Canvas canvas, Size s) {
    final p = down
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(s.width, 0)
            ..lineTo(s.width / 2, s.height))
        : (Path()
            ..moveTo(0, s.height)
            ..lineTo(s.width, s.height)
            ..lineTo(s.width / 2, 0));
    canvas.drawPath(p..close(), Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.down != down || old.colour != colour;
}

/// One segment of a contributor's bar: the coloured edge along its top (the
/// whole of a closed bar) and the wash under it (an open bar's body).
typedef LocusSeg = ({Color line, Color fill});

/// A segment's colours, measured off the reference. Short of the target it
/// is amber, past it green; the nearer the target the dimmer, reaching full
/// amber a tenth of the range away and full green a little further out.
LocusSeg locusSegment(double v, LocusRow row, double target) {
  final span = row.max - row.min;
  final d = (v - target) / span * (row.higherBetter ? 1 : -1);
  if (d < 0) {
    final t = ((-d - .03) / .1).clamp(0.0, 1.0);
    return (
      line: Color.lerp(AC.segAmberDim, AC.segAmber, t)!,
      fill: Color.lerp(AC.segAmberFillDim, AC.segAmberFill, t)!,
    );
  }
  final t = ((d - .05) / .18).clamp(0.0, 1.0);
  return (
    line: Color.lerp(AC.segGreenDim, AC.segGreen, t)!,
    fill: Color.lerp(AC.segGreenFillDim, AC.segGreenFill, t)!,
  );
}

/// The segments of a bar. Ten, as the reference; the one the target falls
/// inside (not on an edge of) is the grey one.
List<LocusSeg> locusSegments(LocusRow row, double target) {
  const n = 10;
  final step = (row.max - row.min) / n;
  return [
    for (var i = 0; i < n; i++)
      target > row.min + step * i + 1e-9 &&
              target < row.min + step * (i + 1) - 1e-9
          ? (line: AC.segGrey, fill: AC.segGreyFill)
          : locusSegment(row.min + step * (i + .5), row, target),
  ];
}

class _Contributor extends StatelessWidget {
  final LocusRow row;
  final WhoopAgePart long;
  final WhoopAgePart? recent;
  final bool showYears, open, divider;
  final VoidCallback onToggle, onTrend;

  const _Contributor({
    required this.row,
    required this.long,
    required this.recent,
    required this.showYears,
    required this.open,
    required this.divider,
    required this.onToggle,
    required this.onTrend,
  });

  double _pos(double v) =>
      ((v - row.min) / (row.max - row.min)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext c) {
    final now = row.format(long.value);
    final thirty = recent == null ? null : row.format(recent!.value);
    final at = _pos(long.value);
    final at30 = recent == null ? null : _pos(recent!.value);
    final years = long.years;
    final yearsColour = !showYears || years.abs() < .05
        ? DC.ink
        : years > 0
            ? AC.segAmber
            : AC.segGreen;
    final yearsText = !showYears
        ? '--'
        : years.abs() < .05
            ? '0.0'
            : '${years > 0 ? '+' : '-'}${years.abs().toStringAsFixed(1)}';
    final insight = rowInsight(row, long, recent);
    final segs = locusSegments(row, long.target);
    Widget valueLine(LocusValue v, TextStyle s, TextStyle u) => Text.rich(
      TextSpan(
        children: [
          TextSpan(text: v.value, style: s),
          if (v.unit.isNotEmpty) TextSpan(text: ' ${v.unit}', style: u),
        ],
      ),
      maxLines: 1,
    );
    final valueStyle = AC.rowValue.copyWith(color: DC.ink);
    final unitStyle = AC.barLabelMid.copyWith(color: DC.ink3);

    return ColoredBox(
      color: open ? AC.rowOpen : AC.row,
      child: Column(
        children: [
          if (divider && !open)
            const Divider(
              height: S.hair,
              thickness: S.hair,
              indent: S.x4,
              endIndent: S.x4,
              color: DC.line,
            ),
          Pressable(
            semanticLabel: row.title,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.title.toUpperCase(),
                      style: F.dLabel.copyWith(color: DC.ink),
                    ),
                  ),
                  const SizedBox(width: S.x2),
                  Icon(
                    open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: I.sm,
                    color: DC.ink2,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment(at * 2 - 1, 0),
                        child: open
                            ? Column(
                                children: [
                                  Text(
                                    '6 Month avg.',
                                    style: AC.barLabelMid.copyWith(
                                      color: DC.ink,
                                    ),
                                  ),
                                  valueLine(now, valueStyle, unitStyle),
                                ],
                              )
                            : valueLine(now, valueStyle, unitStyle),
                      ),
                      const SizedBox(height: S.half),
                      Stack(
                        children: [
                          CustomPaint(
                            size: Size(
                              double.infinity,
                              _BandPainter.heightFor(thick: open),
                            ),
                            painter: _BandPainter(
                              segs: segs,
                              at: at,
                              at30: at30,
                              thick: open,
                            ),
                          ),
                          if (open)
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: S.x1,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      row.minLabel,
                                      style: AC.barLabel.copyWith(
                                        color: segs.first.line,
                                      ),
                                    ),
                                    Text(
                                      row.maxLabel,
                                      style: AC.barLabel.copyWith(
                                        color: segs.last.line,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (!open)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              row.minLabel,
                              style: AC.barLabel.copyWith(
                                color: segs.first.line,
                              ),
                            ),
                            Text(
                              row.maxLabel,
                              style: AC.barLabel.copyWith(
                                color: segs.last.line,
                              ),
                            ),
                          ],
                        ),
                      if (open && thirty != null && at30 != null)
                        Align(
                          alignment: Alignment(at30 * 2 - 1, 0),
                          child: Column(
                            children: [
                              valueLine(thirty, valueStyle, unitStyle),
                              Text(
                                '30 Day avg.',
                                style: AC.barLabelMid.copyWith(color: DC.ink),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // A narrow years column, so the bar runs as wide as the
                // reference's.
                const SizedBox(width: S.x1),
                SizedBox(
                  width: S.x10,
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          yearsText,
                          style: AC.rowYears.copyWith(color: yearsColour),
                        ),
                      ),
                      Text(
                        'years',
                        style: AC.barLabelMid.copyWith(color: DC.ink3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.title,
                      style: AC.rowTitle.copyWith(color: DC.ink),
                    ),
                    const SizedBox(height: S.x1),
                    Text(
                      insight.body,
                      style: AC.body.copyWith(color: DC.ink2),
                    ),
                    if (row.key != 'lean_mass') ...[
                      const SizedBox(height: S.x3),
                      _LinkLabel('VIEW TREND', AC.olderText, onTrend),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BandPainter extends CustomPainter {
  static const _tip = 6.0, _under = 5.0, _thin = 4.0, _thick = 19.0;
  static const _edge = 3.5, _gap = 1.0, _round = 2.0;

  /// The first marker, the band, and the small marker under it.
  static double heightFor({required bool thick}) =>
      _tip + (thick ? _thick : _thin) + _under + S.half;

  final List<LocusSeg> segs;
  final double at;
  final double? at30;
  final bool thick;
  const _BandPainter({
    required this.segs,
    required this.at,
    required this.at30,
    required this.thick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bandTop = _tip;
    final bandH = thick ? _thick : _thin;
    final bar = Rect.fromLTWH(0, bandTop, size.width, bandH);
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(_round)));
    final w = (size.width - _gap * (segs.length - 1)) / segs.length;
    for (var i = 0; i < segs.length; i++) {
      final x = i * (w + _gap);
      if (thick) {
        canvas.drawRect(Rect.fromLTWH(x, bandTop, w, bandH),
            Paint()..color = segs[i].fill);
      }
      canvas.drawRect(Rect.fromLTWH(x, bandTop, w, thick ? _edge : bandH),
          Paint()..color = segs[i].line);
    }
    canvas.restore();
    final x = at * size.width;
    canvas.drawPath(
      Path()
        ..moveTo(x - 5, 0)
        ..lineTo(x + 5, 0)
        ..lineTo(x, _tip)
        ..close(),
      Paint()..color = DC.ink,
    );
    final a30 = at30;
    if (a30 != null) {
      final x2 = a30 * size.width;
      final y = bandTop + bandH;
      canvas.drawPath(
        Path()
          ..moveTo(x2 - 3.5, y + _under)
          ..lineTo(x2 + 3.5, y + _under)
          ..lineTo(x2, y)
          ..close(),
        Paint()..color = DC.ink2,
      );
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.at != at || old.at30 != at30 || old.thick != thick || old.segs != segs;
}

/// The two trend cards under the page, Locus Age over Pace of Aging, as the
/// reference stacks them. [weeks] are the finished weeks, oldest first.
class LocusAgeTrends extends StatelessWidget {
  final List<({String end, WhoopAgeResult r})> weeks;
  const LocusAgeTrends({super.key, required this.weeks});

  @override
  Widget build(BuildContext c) {
    final w = [
      for (final x in weeks)
        if (x.r.whoopAge != null) _Week(x.end, '', x.r),
    ];
    return Column(
      children: [
        if (w.isNotEmpty) ...[
          _TrendCard.age(w),
          const SizedBox(height: S.x3),
        ],
        _TrendCard.pace(w),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  final String title;

  /// One point per finished week, oldest first, with the week's last day.
  final List<({String day, double v})> points;

  /// The chronological age each week (it rises with the calendar); null
  /// draws none. [flat] is a level reference instead (1.0x for the pace).
  final List<double>? reference;
  final double? flat;
  final double lo, hi, step;
  final String Function(double) label;
  final Color colour;
  final bool age;

  const _TrendCard._({
    required this.title,
    required this.points,
    this.reference,
    this.flat,
    required this.lo,
    required this.hi,
    required this.step,
    required this.label,
    required this.colour,
    this.age = false,
  });

  factory _TrendCard.pace(List<_Week> weeks) => _TrendCard._(
    title: 'PACE OF AGING TREND',
    points: [
      for (final w in weeks)
        if (w.r.pace != null) (day: w.end, v: w.r.pace!),
    ],
    flat: 1,
    lo: -1,
    hi: 3,
    step: 1,
    label: (v) => '${v.toStringAsFixed(1)}x',
    colour: AC.olderText,
  );

  factory _TrendCard.age(List<_Week> weeks) {
    final ages = [for (final w in weeks) w.r.whoopAge!];
    final real = [for (final w in weeks) ?w.r.age];
    final all = [...ages, ...real];
    var lo = (all.reduce(math.min) / 5).floorToDouble() * 5;
    var hi = (all.reduce(math.max) / 5).ceilToDouble() * 5;
    if (hi - lo < 10) {
      lo -= 5;
      hi += 5;
    }
    return _TrendCard._(
      title: 'LOCUS AGE TREND',
      points: [for (final w in weeks) (day: w.end, v: w.r.whoopAge!)],
      reference: real.length == weeks.length ? real : null,
      lo: lo,
      hi: hi,
      step: 5,
      label: (v) => v.toStringAsFixed(1),
      colour: AC.tealText,
      age: true,
    );
  }

  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x4),
    decoration: const BoxDecoration(color: AC.card, borderRadius: R.rXl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: F.dLabel.copyWith(color: DC.ink)),
        if (age) ...[
          const SizedBox(height: S.x4),
          Center(
            child: Wrap(
              spacing: S.x5,
              runSpacing: S.x1,
              children: [
                _key(
                  const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(S.half)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AC.segAmber, AC.segGreen],
                    ),
                  ),
                  'YOUR LOCUS AGE',
                ),
                _key(
                  const BoxDecoration(color: DC.ink, borderRadius: BorderRadius.all(Radius.circular(S.half))),
                  'CHRONOLOGICAL AGE',
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: S.x3),
        if (points.length < 2)
          Text(
            'Two finished weeks draw this line.',
            style: AC.body.copyWith(color: DC.ink3),
          )
        else
          CustomPaint(
            size: const Size(double.infinity, S.x16 * 3),
            painter: _TrendPainter(
              points: points,
              reference: reference,
              flat: flat,
              lo: lo,
              hi: hi,
              step: step,
              label: label,
              colour: colour,
              stepped: age,
            ),
          ),
      ],
    ),
  );

  Widget _key(BoxDecoration swatch, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: S.x3, height: S.x3, decoration: swatch),
      const SizedBox(width: S.x2),
      Flexible(child: Text(text, style: AC.barLabel.copyWith(color: DC.ink))),
    ],
  );
}

/// A trend over the finished weeks, as the reference draws it: grid and
/// values down the left, month names along the bottom, the reference (real
/// age, or 1.0x) in white, the reading in its colour (stepped week to week
/// for the age, a plain line for the pace) and the ends labelled.
class _TrendPainter extends CustomPainter {
  final List<({String day, double v})> points;
  final List<double>? reference;
  final double? flat;
  final double lo, hi, step;
  final String Function(double) label;
  final Color colour;
  final bool stepped;

  const _TrendPainter({
    required this.points,
    required this.reference,
    required this.flat,
    required this.lo,
    required this.hi,
    required this.step,
    required this.label,
    required this.colour,
    required this.stepped,
  });

  TextPainter _text(String s, Color c, {bool bold = false}) => TextPainter(
    text: TextSpan(
      text: s,
      style: AC.barLabel.copyWith(
        color: c,
        fontWeight: bold ? FontWeight.w700 : null,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    const left = S.x10 + S.x2, right = S.x8, top = S.x2, foot = S.x6;
    final h = size.height - top - foot;
    double y(double v) => top + h * (1 - (v - lo) / (hi - lo));
    final w = size.width - left - right;
    final days = [for (final p in points) DateTime.parse(p.day)];
    final t0 = days.first.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, days.last.millisecondsSinceEpoch - t0);
    double xAt(DateTime d) => left + w * (d.millisecondsSinceEpoch - t0) / span;
    double x(int i) => xAt(days[i]);

    for (var v = lo; v <= hi + .001; v += step) {
      canvas.drawLine(
        Offset(left, y(v)),
        Offset(size.width, y(v)),
        Paint()
          ..color = DC.grid
          ..strokeWidth = S.hair,
      );
      final t = _text(label(v), DC.ink3);
      t.paint(canvas, Offset(0, y(v) - t.height / 2));
      t.dispose();
    }

    // The months along the bottom, each at its first day.
    var m = DateTime(days.first.year, days.first.month + 1);
    while (!m.isAfter(days.last)) {
      final t = _text(monthShortName(m.month, null), DC.ink3);
      final mx = xAt(m);
      if (mx - t.width / 2 >= left - S.x1 && mx + t.width / 2 <= size.width) {
        t.paint(canvas, Offset(mx - t.width / 2, size.height - t.height));
      }
      t.dispose();
      m = DateTime(m.year, m.month + 1);
    }

    final white = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = S.half / 1.5
      ..color = DC.ink;
    final ref = reference;
    final f = flat;
    Offset? refEnd;
    if (ref != null && ref.length == points.length) {
      final path = Path()..moveTo(x(0), y(ref.first));
      for (var i = 1; i < ref.length; i++) {
        path.lineTo(x(i), y(ref[i]));
      }
      canvas.drawPath(path, white);
      refEnd = Offset(x(ref.length - 1), y(ref.last));
    } else if (f != null) {
      canvas.drawLine(Offset(x(0), y(f)), Offset(left + w, y(f)), white);
    }

    // Older than the real age is the reference's dim olive, younger teal.
    bool older(int i) => ref != null && points[i].v > ref[i] + .05;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = S.half / 1.25
      ..strokeJoin = StrokeJoin.round;
    for (var i = 1; i < points.length; i++) {
      final a = Offset(x(i - 1), y(points[i - 1].v));
      final b = Offset(x(i), y(points[i].v));
      line.color = stepped && older(i - 1) ? AC.ageOlderLine : colour;
      final path = Path()..moveTo(a.dx, a.dy);
      if (stepped) {
        path
          ..lineTo(b.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      } else {
        path.lineTo(b.dx, b.dy);
      }
      canvas.drawPath(path, line);
    }

    final last = points.length - 1;
    final end = Offset(x(last), y(points.last.v));
    final endColour = stepped && older(last) ? AC.ageOlderLine : colour;

    void dot(Offset at, Color c) {
      canvas.drawCircle(at, S.x1 + S.half, Paint()..color = AC.page);
      canvas.drawCircle(
        at,
        S.x1 + S.half,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = S.half
          ..color = c,
      );
    }

    void chip(
      String s,
      Color ink,
      Color ground,
      Offset at, {
      required bool above,
    }) {
      final t = _text(s, ink, bold: true);
      final o = Offset(
        (at.dx - t.width / 2).clamp(left, size.width - t.width - S.half),
        above ? at.dy - t.height - S.x3 : at.dy + S.x3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (o & t.size).inflate(S.half + S.hair),
          const Radius.circular(S.x1),
        ),
        Paint()..color = ground,
      );
      t.paint(canvas, o);
      t.dispose();
    }

    final re = refEnd;
    if (re != null) {
      dot(re, DC.ink);
      chip(label(ref!.last), DC.ink, AC.page, re, above: re.dy <= end.dy);
      chip(
        label(points.last.v),
        endColour,
        AC.chipDark,
        end,
        above: re.dy > end.dy,
      );
    } else {
      chip(label(points.last.v), endColour, AC.page, end, above: true);
    }
    dot(end, endColour);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.reference != reference || old.lo != lo;
}
