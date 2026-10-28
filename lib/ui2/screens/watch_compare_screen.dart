// watch_compare_screen.dart — the band and another watch, side by side, for
// the same day. The other watch's numbers come out of Health Connect / HealthKit
// (see lib/health/watch_compare.dart) and are shown under that app's name; they
// are never blended into anything the band measured.

import 'package:flutter/material.dart';

import '../../data/day_label.dart';
import '../../health/watch_compare.dart';
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

class _WatchCompareScreenState extends State<WatchCompareScreen> {
  late final WatchCompareReader _reader =
      widget.reader ?? WatchCompareReader();

  DateTime _day = DateTime.now();
  _Span _span = _Span.day;
  bool _loading = true;
  bool? _permitted;
  String? _error;
  List<String> _sources = const [];
  String? _source;
  _BandDay? _band;
  WatchWindow? _watch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

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
    DateTime? ts(Object? v) => v is num
        ? DateTime.fromMillisecondsSinceEpoch(v.round() * 1000)
        : null;
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
        'com.google.android.apps.fitness' => 'Google Fit',
        'com.fitbit.FitbitMobile' => 'Fitbit',
        'com.garmin.android.apps.connectmobile' => 'Garmin Connect',
        _ => s,
      };

  static String _hm(int? min) =>
      min == null ? '—' : '${min ~/ 60}h ${(min % 60).toString().padLeft(2, '0')}m';

  static String _clock(DateTime? t) => t == null
      ? '—'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
              'Connect. Samsung Health must also be set to sync to Health '
              'Connect (Samsung Health › Settings › Health Connect).',
          fix: 'Try again',
          onFix: _init,
          icon: LucideIcons.heartHandshake,
        )
      else if (_loading)
        const Padding(
          padding: EdgeInsets.all(S.x8),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_error != null)
        StatusCard('Could not read Health Connect', _error!,
            fix: 'Retry', onFix: _load, icon: LucideIcons.triangleAlert)
      else if (_watch == null)
        StatusCard(
          'No other watch data for this day',
          'Nothing from another app is in Health Connect for this day. In '
              'Samsung Health, turn on Settings › Health Connect sync, then '
              'open Samsung Health once so it pushes the latest data.',
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
    Widget arrow(bool left, VoidCallback? onTap) => Pressable(
          onTap: onTap,
          semanticLabel: left ? 'Previous day' : 'Next day',
          child: SizedBox(
            width: S.x8 + S.x1,
            height: S.tap,
            child: Center(
              child: BoldChevron(
                  left: left,
                  height: S.x3,
                  color: onTap == null ? p.ink.withValues(alpha: .22) : p.ink),
            ),
          ),
        );
    return Row(children: [
      arrow(true, () => _shiftDay(-1)),
      Expanded(
        child: Center(
          child: Text((isToday ? 'Today' : dayLabelOf(_day)).toUpperCase(),
              style: F.over.copyWith(
                  color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      ),
      arrow(false, isToday ? null : () => _shiftDay(1)),
    ]);
  }

  Widget _sourcePicker(P p) => Padding(
        padding: const EdgeInsets.only(bottom: S.x3),
        child: Row(children: [
          Text('Other device', style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(width: S.x3),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _source,
              underline: const SizedBox.shrink(),
              items: [
                for (final s in _sources)
                  DropdownMenuItem(
                      value: s,
                      child: Text(_sourceLabel(s),
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v == null || v == _source) return;
                setState(() => _source = v);
                _load();
              },
            ),
          ),
        ]),
      );

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
    final axis = AxisSpec.of([
      for (final v in gb) ?v,
      for (final v in gw) ?v,
    ]);
    final bandCol = p.on(C.red), watchCol = p.on(C.blue);

    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Heart rate',
                style: F.t2.copyWith(color: p.ink)),
          ),
          SegmentedButton<_Span>(
            segments: const [
              ButtonSegment(value: _Span.day, label: Text('Day')),
              ButtonSegment(value: _Span.night, label: Text('Night')),
            ],
            selected: {_span},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _span = s.first),
          ),
        ]),
        const SizedBox(height: S.x4),
        ChartFrame(
          title: _span == _Span.day ? 'Through the day' : 'Through the night',
          unit: 'bpm',
          height: 150,
          yAxis: axis,
          xLabels: win == null ? const [] : [_clock(win.$1), _clock(win.$2)],
          legend: [('WHOOP', bandCol), (watchName, watchCol)],
          series: gb,
          empty: axis == null ? const NoData() : null,
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                  painter: LineChart(gb, bandCol, fill: false, axis: axis)),
            ),
            Positioned.fill(
              child: CustomPaint(
                  painter: LineChart(gw, watchCol, fill: false, axis: axis)),
            ),
          ]),
        ),
        const SizedBox(height: S.x4),
        if (agree == null)
          Text(
            'Too few minutes where both devices measured heart rate to '
            'compare them. Samsung watches log heart rate every 10 minutes at '
            'rest unless continuous measurement is on.',
            style: F.cap.copyWith(color: p.ink3, height: 1.5),
          )
        else
          InlineMetrics([
            ('AVG DIFF',
                '${agree.meanDiff >= 0 ? '+' : ''}${agree.meanDiff.toStringAsFixed(1)} bpm',
                C.blue),
            ('TYPICAL GAP', '${agree.meanAbsDiff.toStringAsFixed(1)} bpm',
                C.orange),
            ('AGREEMENT',
                agree.r == null ? '—' : 'r ${agree.r!.toStringAsFixed(2)}',
                C.green),
          ]),
        if (agree != null) ...[
          const SizedBox(height: S.x2),
          Text(
            'Over ${agree.pairedMinutes} minutes both measured. Avg diff is '
            '$watchName minus WHOOP.',
            style: F.over.copyWith(color: p.ink3),
          ),
        ],
      ]),
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
        v == null ? '—' : '${v.toStringAsFixed(v >= 100 ? 0 : 1)}$unit';
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
      ('Fell asleep', _clock(b?.onset), _clock(wn?.start),
          diff(0, clockDiffMin(b?.onset, wn?.start), minutes: true)),
      ('Woke up', _clock(b?.wake), _clock(wn?.end),
          diff(0, clockDiffMin(b?.wake, wn?.end), minutes: true)),
      ('Asleep', _hm(b?.asleepMin), _hm(wn?.asleepMin),
          diff(b?.asleepMin, wn?.asleepMin, minutes: true)),
      for (final (k, label) in const [
        ('deep', 'Deep'),
        ('light', 'Light'),
        ('rem', 'REM'),
        ('awake', 'Awake'),
      ])
        (label, _hm(b?.stageMin[k]), _hm(wn?.stageMin[k]),
            diff(b?.stageMin[k], wn?.stageMin[k], minutes: true)),
      ('Resting HR', n1(b?.restingHr, ' bpm'), n1(w.restingHr, ' bpm'),
          diff(b?.restingHr, w.restingHr)),
      ('HRV (RMSSD)', n1(b?.hrv, ' ms'), n1(w.hrvRmssd, ' ms'),
          diff(b?.hrv, w.hrvRmssd)),
      ('Breathing', n1(b?.resp, ' /min'), n1(w.resp, ' /min'),
          diff(b?.resp, w.resp)),
      ('Blood oxygen', '—', n1(w.spo2, '%'), ''),
      ('Steps', b?.steps?.toString() ?? '—', w.steps?.toString() ?? '—',
          diff(b?.steps, w.steps)),
    ];

    TextStyle head = F.over.copyWith(color: p.ink3);
    return Surface(
      child: Column(children: [
        Row(children: [
          const Expanded(flex: 4, child: SizedBox.shrink()),
          Expanded(flex: 3, child: Text('WHOOP', style: head)),
          Expanded(
              flex: 3,
              child: Text(_sourceLabel(w.source).split(' ').first,
                  style: head, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 3, child: Text('DIFF', style: head)),
        ]),
        for (final (label, a, bb, d) in rows) ...[
          Divider(height: S.x5, color: p.line),
          Row(children: [
            Expanded(
                flex: 4,
                child: Text(label, style: F.cap.copyWith(color: p.ink2))),
            Expanded(
                flex: 3,
                child: Text(a, style: F.cap.copyWith(color: p.ink))),
            Expanded(
                flex: 3,
                child: Text(bb, style: F.cap.copyWith(color: p.ink))),
            Expanded(
                flex: 3,
                child: Text(d, style: F.cap.copyWith(color: p.ink3))),
          ]),
        ],
      ]),
    );
  }
}
