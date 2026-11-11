// watch_compare_screen.dart — the band and another watch, side by side, for
// the same day. The other watch's numbers come out of Health Connect / HealthKit
// (see lib/health/watch_compare.dart) and are shown under that app's name; they
// are never blended into anything the band measured.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../health/watch_compare.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart';
import '../ui2.dart';
import 'home_screen.dart' show repoOf;
import 'metric_detail.dart' show detailScaffold;

class WatchCompareScreen extends StatefulWidget {
  const WatchCompareScreen({super.key, this.reader});

  /// Injectable for tests.
  final WatchCompareReader? reader;

  @override
  State<WatchCompareScreen> createState() => _WatchCompareScreenState();
}

/// The band's side of one day, in the shapes this screen compares.
class _BandDay {
  _BandDay({
    required this.hr,
    this.onset,
    this.wake,
    this.asleepMin,
    this.stageMin = const {},
    this.restingHr,
    this.hrv,
    this.resp,
    this.steps,
  });

  final List<(int, double)> hr;
  final DateTime? onset, wake;
  final int? asleepMin;
  final Map<String, int> stageMin;
  final double? restingHr, hrv, resp;
  final int? steps;
}

enum _Span { day, night }

class _WatchCompareScreenState extends State<WatchCompareScreen>
    with WidgetsBindingObserver {
  late final WatchCompareReader _reader = widget.reader ?? WatchCompareReader();

  DateTime _day = DateTime.now();
  _Span _span = _Span.day;
  bool _loading = true;
  bool? _permitted;
  String? _error;
  List<String> _sources = const [];
  String? _source;
  _BandDay? _band;
  WatchWindow? _watch;

  /// The 5-minute column under the finger on the heart-rate chart.
  int? _at;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Health Connect's own screen: look again.
    if (state == AppLifecycleState.resumed && _permitted == false) _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openHealthConnect() =>
      context.read<AppState>().openHealthConnect();

  Future<void> _init() async {
    final ok = await _reader.requestPermission();
    if (!mounted) return;
    setState(() => _permitted = ok);
    if (ok) await _load();
  }

  DateTime get _dayStart => DateTime(_day.year, _day.month, _day.day);
  DateTime get _dayEnd => DateTime(_day.year, _day.month, _day.day + 1);

  /// The read window: the calendar day plus the evening before, so a night
  /// that started before midnight is read whole.
  DateTime get _readStart => DateTime(_day.year, _day.month, _day.day, -12);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final band = await _loadBand(dayLabelOf(_day));
      final sources = await _reader.sources(_readStart, _dayEnd);
      final source = _source != null && sources.contains(_source)
          ? _source
          : sources.contains(kSamsungHealthPackage)
          ? kSamsungHealthPackage
          : sources.isNotEmpty
          ? sources.first
          : null;
      final watch = source == null
          ? null
          : await _reader.read(_readStart, _dayEnd, source: source);
      if (!mounted) return;
      setState(() {
        _band = band;
        _sources = sources;
        _source = source;
        _watch = watch;
        _loading = false;
        _at = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<_BandDay?> _loadBand(String day) async {
    final repo = repoOf(context);
    if (repo == null) return null;
    final timeline = await repo.getDayTimeline(day);
    final night = await repo.getDaySleepV2(day);
    final overview = await repo.getDayOverview(day);
    final hrv = await repo.getDayHrv(day);
    Map<String, dynamic> steps = const {};
    try {
      steps = await repo.getDaySteps(day);
    } catch (_) {}
    final hr = <(int, double)>[
      for (final e in (timeline['hr'] as List?) ?? const [])
        if (e is Map && e['t'] is num && e['v'] is num && (e['v'] as num) > 0)
          ((e['t'] as num).round(), (e['v'] as num).toDouble()),
    ];
    DateTime? ts(Object? v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.round() * 1000) : null;
    final has = night['has_sleep'] == true;
    final resp = night['resp'];
    return _BandDay(
      hr: hr,
      onset: has ? ts(night['onset_ts']) : null,
      wake: has ? ts(night['wake_ts']) : null,
      asleepMin: has ? (night['duration_min'] as num?)?.round() : null,
      stageMin: has
          ? {
              for (final k in const ['deep', 'light', 'rem', 'awake'])
                if (night['${k}_min'] is num)
                  k: (night['${k}_min'] as num).round(),
            }
          : const {},
      restingHr: (overview['resting_hr'] as num?)?.toDouble(),
      hrv: (hrv['rmssd'] as num?)?.toDouble(),
      resp: resp is Map ? (resp['value'] as num?)?.toDouble() : null,
      steps: (steps['day_total'] as num?)?.round(),
    );
  }

  void _shiftDay(int by) {
    final next = DateTime(_day.year, _day.month, _day.day + by, 12);
    // By calendar day, not instant: today at noon is "today" at 08:00 too.
    if (dayLabelOf(next).compareTo(todayLabel()) > 0) return;
    setState(() => _day = next);
    _load();
  }

  static String _sourceLabel(String s) => switch (s) {
    kSamsungHealthPackage => 'Galaxy Watch (Samsung Health)',
    'com.google.android.apps.fitness' => 'Google Health',
    'com.fitbit.FitbitMobile' => 'Google Health (Fitbit)',
    'com.google.android.apps.adm' => 'Pixel Watch',
    'com.garmin.android.apps.connectmobile' => 'Garmin Connect',
    _ => s,
  };

  static String _hm(int? min) => min == null
      ? '--'
      : '${min ~/ 60}h ${(min % 60).toString().padLeft(2, '0')}m';

  static String _clock(DateTime? t) => t == null ? '--' : formatClockOf(t);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return detailScaffold(c, 'Compare devices', [
      _dayBar(p),
      const SizedBox(height: S.x4),
      if (_permitted == false)
        StatusCard(
          'Health Connect access needed',
          'Allow this app to read heart rate, sleep and steps in Health '
              'Connect. The app your watch uses must also be set to sync there, '
              'in its own settings.',
          fix: 'Open Health Connect',
          onFix: _openHealthConnect,
          icon: LucideIcons.heartHandshake,
        )
      else if (_loading)
        const Padding(
          padding: EdgeInsets.all(S.x8),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_error != null)
        StatusCard(
          'Could not read Health Connect',
          _error!,
          fix: 'Retry',
          onFix: _load,
          icon: LucideIcons.triangleAlert,
        )
      else if (_watch == null)
        StatusCard(
          'No other watch data for this day',
          'Nothing from another app is in Health Connect for this day. In '
              'the app your watch uses (Samsung Health, Google Health, Garmin '
              'Connect), turn on Health Connect sync, then open it once so '
              'it pushes the latest data.',
          icon: LucideIcons.watch,
        )
      else ...[
        if (_sources.length > 1) _sourcePicker(p),
        _hrCard(p),
        const SizedBox(height: S.x4),
        Section('Side by side', _table(p)),
        const SizedBox(height: S.x3),
        Text(
          'Both devices estimate these with their own methods, so a steady '
          'offset is normal. Sleep stages in particular are estimates on any '
          'wrist device and often disagree by 20–40 minutes per stage.',
          style: F.cap.copyWith(color: p.ink3, height: 1.5),
        ),
      ],
    ]);
  }

  Widget _dayBar(P p) {
    final isToday = dayLabelOf(_day) == todayLabel();
    return Center(
      child: WindowPager(
        isToday ? 'TODAY' : dayLabelOf(_day),
        onEarlier: () => _shiftDay(-1),
        onLater: isToday ? null : () => _shiftDay(1),
      ),
    );
  }

  /// The other app the watch's numbers are read from: its name, and a sheet
  /// of the others to choose from.
  Widget _sourcePicker(P p) => Padding(
    padding: const EdgeInsets.only(bottom: S.x4),
    child: Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      onTap: () => _chooseSource(),
      semanticLabel: 'Other device: ${_sourceLabel(_source ?? '')}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: S.x12 + S.x1),
        child: Row(
          children: [
            Icon(LucideIcons.watch, size: I.lg, color: p.ink2),
            const SizedBox(width: S.x4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OTHER DEVICE',
                    style: F.over.copyWith(
                      color: p.ink3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _sourceLabel(_source ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.body.copyWith(color: p.ink),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: I.md, color: p.ink3),
          ],
        ),
      ),
    ),
  );

  Future<void> _chooseSource() async {
    final picked = await AppSheet.show<String>(
      context,
      title: 'Other device',
      child: Builder(
        builder: (c) {
          final p = P.of(c);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in _sources)
                Pressable(
                  onTap: () => Navigator.of(c).pop(s),
                  semanticLabel: _sourceLabel(s),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: S.tap + S.x1),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sourceLabel(s),
                            style: F.body.copyWith(color: p.ink),
                          ),
                        ),
                        if (s == _source)
                          Icon(LucideIcons.check, size: I.md, color: p.ink),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
    if (picked == null || picked == _source || !mounted) return;
    setState(() => _source = picked);
    _load();
  }

  /// The window the heart-rate chart covers: the calendar day, or the band's
  /// night (falling back to the watch's own night when the band has none).
  (DateTime, DateTime)? _hrWindow() {
    if (_span == _Span.day) return (_dayStart, _dayEnd);
    final b = _band;
    if (b?.onset != null && b?.wake != null) return (b!.onset!, b.wake!);
    final n = _watch?.longestEndingIn(_readStart, _dayEnd);
    return n == null ? null : (n.start, n.end);
  }

  Widget _hrCard(P p) {
    final win = _hrWindow();
    final watchName = _sourceLabel(_watch!.source);
    final band = _band?.hr ?? const <(int, double)>[];
    final watch = _watch!.hr;
    List<(int, double)> clip(List<(int, double)> l) => win == null
        ? const []
        : [
            for (final e in l)
              if (e.$1 >= win.$1.millisecondsSinceEpoch ~/ 1000 &&
                  e.$1 < win.$2.millisecondsSinceEpoch ~/ 1000)
                e,
          ];
    final b = clip(band), w = clip(watch);
    final agree = HrAgreement.of(b, w);

    // One column per 5 minutes across the window, each side bucket-averaged;
    // an empty bucket is a hole, not a zero.
    final cols = win == null
        ? 0
        : (win.$2.difference(win.$1).inMinutes / 5).ceil().clamp(2, 300);
    List<double?> grid(List<(int, double)> l) {
      final sum = List<double>.filled(cols, 0), n = List<int>.filled(cols, 0);
      final t0 = win!.$1.millisecondsSinceEpoch ~/ 1000;
      for (final (t, v) in l) {
        final i = ((t - t0) ~/ 300).clamp(0, cols - 1);
        sum[i] += v;
        n[i]++;
      }
      return [for (var i = 0; i < cols; i++) n[i] == 0 ? null : sum[i] / n[i]];
    }

    final gb = cols == 0 ? const <double?>[] : grid(b);
    final gw = cols == 0 ? const <double?>[] : grid(w);
    final all = [...gb.whereType<double>(), ...gw.whereType<double>()];
    // A scale in tens with a little room either side of what was measured.
    final lo = all.isEmpty
        ? 40.0
        : ((all.reduce((a, v) => a < v ? a : v) - 5) / 10).floorToDouble() * 10;
    final hi = all.isEmpty
        ? 120.0
        : ((all.reduce((a, v) => a > v ? a : v) + 5) / 10).ceilToDouble() * 10;
    final mid = ((lo + hi) / 20).roundToDouble() * 10;
    DateTime at(int i) => DateTime.fromMillisecondsSinceEpoch(
        win!.$1.millisecondsSinceEpoch + i * 300000);
    final xs = [
      for (var i = 0; i < cols; i++)
        i == 0 ||
                (i < cols - 1 &&
                    at(i).hour != at(i - 1).hour &&
                    at(i).hour % 6 == 0)
            ? _clock(at(i))
            : '',
    ];
    final watchCol = p.ink2;
    final k = _at;
    String bpm(double? v) => v == null ? '--' : '${v.round()}';

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'HEART RATE',
                  style: F.caps.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              RangeSegments(
                const ['DAY', 'NIGHT'],
                _span.index,
                (i) => setState(() {
                  _span = _Span.values[i];
                  _at = null;
                }),
                width: S.x16 * 2 + S.x4,
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          ScrubReadout(
            caption: k == null || win == null
                ? (_span == _Span.day ? 'Through the day' : 'Through the night')
                : _clock(at(k)),
            value: k == null ? '' : bpm(gb[k]),
            unit: k == null || gb[k] == null ? null : 'bpm',
            under: k == null
                ? null
                : Text(
                    '$watchName ${bpm(gw[k])}',
                    style: F.cap.copyWith(color: p.ink2),
                  ),
            big: false,
          ),
          const SizedBox(height: S.x3),
          if (cols == 0 || all.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: S.x8),
              child: Center(child: NoData()),
            )
          else
            ScrubLine(
              values: gb,
              xLabels: xs,
              lo: lo,
              hi: hi,
              ticks: [lo, mid, hi],
              tickText: (t) => '${t.round()}',
              color: C.dialStrain,
              markers: false,
              slots: false,
              fill: false,
              // A quarter of an hour unmeasured breaks the line.
              gap: 3,
              stroke: 2,
              height: S.x16 * 3,
              label: 'Heart rate, band and $watchName',
              paintOver: (cv, plot, xOf, yOf) {
                // The other watch, in the same weight, on the same scale.
                final paint = Paint()
                  ..color = watchCol
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2
                  ..strokeJoin = StrokeJoin.round;
                Path? path;
                int? last;
                for (var i = 0; i < gw.length; i++) {
                  final v = gw[i];
                  if (v == null) continue;
                  final o = Offset(xOf(i), yOf(v));
                  if (path == null || last == null || i - last > 3) {
                    if (path != null) cv.drawPath(path, paint);
                    path = Path()..moveTo(o.dx, o.dy);
                  } else {
                    path.lineTo(o.dx, o.dy);
                  }
                  last = i;
                }
                if (path != null) cv.drawPath(path, paint);
              },
              onScrub: (i) => setState(() => _at = i),
            ),
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x4,
            runSpacing: S.x1,
            children: [
              for (final (name, color) in [
                ('BAND', C.dialStrain),
                (watchName.toUpperCase(), watchCol),
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: S.x3,
                      height: S.half,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: R.rSm,
                      ),
                    ),
                    const SizedBox(width: S.x2),
                    Text(
                      name,
                      style: F.over.copyWith(
                        color: p.ink2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: S.x4),
          if (agree == null)
            Text(
              'Too few minutes where both devices measured heart rate to '
              'compare them. Some watches log heart rate only every 10 minutes '
              'at rest unless continuous measurement is on.',
              style: F.cap.copyWith(color: p.ink3, height: 1.5),
            )
          else
            InlineMetrics([
              (
                'AVG DIFF',
                '${agree.meanDiff >= 0 ? '+' : ''}${agree.meanDiff.toStringAsFixed(1)} bpm',
                p.ink2,
              ),
              (
                'TYPICAL GAP',
                '${agree.meanAbsDiff.toStringAsFixed(1)} bpm',
                p.ink2,
              ),
              (
                'AGREEMENT',
                agree.r == null ? '--' : 'r ${agree.r!.toStringAsFixed(2)}',
                p.ink2,
              ),
            ]),
          if (agree != null) ...[
            const SizedBox(height: S.x2),
            Text(
              'Over ${agree.pairedMinutes} minutes both measured. Avg diff is '
              '$watchName minus the band.',
              style: F.over.copyWith(color: p.ink3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _table(P p) {
    final b = _band;
    final w = _watch!;
    final bandNight = b?.onset != null && b?.wake != null
        ? (b!.onset!, b.wake!)
        : null;
    final wn = bandNight != null
        ? w.nightOverlapping(bandNight.$1, bandNight.$2)
        : w.longestEndingIn(_readStart, _dayEnd);

    String n1(double? v, [String unit = '']) =>
        v == null ? '--' : '${v.toStringAsFixed(v >= 100 ? 0 : 1)}$unit';
    String diff(num? a, num? bb, {String unit = '', bool minutes = false}) {
      if (a == null || bb == null) return '';
      final d = bb - a;
      if (minutes) {
        final m = d.round();
        return '${m >= 0 ? '+' : '−'}${_hm(m.abs())}';
      }
      return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(d.abs() >= 100 ? 0 : 1)}$unit';
    }

    int? clockDiffMin(DateTime? a, DateTime? bb) =>
        a == null || bb == null ? null : bb.difference(a).inMinutes;

    final rows = <(String, String, String, String)>[
      (
        'Fell asleep',
        _clock(b?.onset),
        _clock(wn?.start),
        diff(0, clockDiffMin(b?.onset, wn?.start), minutes: true),
      ),
      (
        'Woke up',
        _clock(b?.wake),
        _clock(wn?.end),
        diff(0, clockDiffMin(b?.wake, wn?.end), minutes: true),
      ),
      (
        'Asleep',
        _hm(b?.asleepMin),
        _hm(wn?.asleepMin),
        diff(b?.asleepMin, wn?.asleepMin, minutes: true),
      ),
      for (final (k, label) in const [
        ('deep', 'Deep'),
        ('light', 'Light'),
        ('rem', 'REM'),
        ('awake', 'Awake'),
      ])
        (
          label,
          _hm(b?.stageMin[k]),
          _hm(wn?.stageMin[k]),
          diff(b?.stageMin[k], wn?.stageMin[k], minutes: true),
        ),
      (
        'Resting HR',
        n1(b?.restingHr, ' bpm'),
        n1(w.restingHr, ' bpm'),
        diff(b?.restingHr, w.restingHr),
      ),
      (
        'HRV (RMSSD)',
        n1(b?.hrv, ' ms'),
        n1(w.hrvRmssd, ' ms'),
        diff(b?.hrv, w.hrvRmssd),
      ),
      (
        'Breathing',
        n1(b?.resp, ' /min'),
        n1(w.resp, ' /min'),
        diff(b?.resp, w.resp),
      ),
      ('Blood oxygen', '--', n1(w.spo2, '%'), ''),
      (
        'Steps',
        b?.steps?.toString() ?? '--',
        w.steps?.toString() ?? '--',
        diff(b?.steps, w.steps),
      ),
    ];

    final head = F.over.copyWith(color: p.ink3, fontWeight: FontWeight.w700);
    return Surface(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(flex: 4, child: SizedBox.shrink()),
              Expanded(flex: 3, child: Text('BAND', style: head)),
              Expanded(
                flex: 3,
                child: Text(
                  _sourceLabel(w.source).split(' ').first,
                  style: head,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(flex: 3, child: Text('DIFF', style: head)),
            ],
          ),
          for (final (label, a, bb, d) in rows) ...[
            Divider(height: S.x5, color: p.line),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(label, style: F.cap.copyWith(color: p.ink2)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(a, style: F.cap.copyWith(color: p.ink)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(bb, style: F.cap.copyWith(color: p.ink)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(d, style: F.cap.copyWith(color: p.ink3)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
