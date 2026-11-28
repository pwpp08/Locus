// TRAINING READINESS — the strain screen's card: one 0–100 score for how ready
// today is for hard training, and every factor it is made of on a row of its
// own, so the score can always be read back to what moved it. The arithmetic
// is `compute/training_readiness.dart`; this reads the stored inputs and lays
// them out, sized off the reference (DESIGN.md §14.1).

import '../../state/duration_format.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../compute/training_readiness.dart';
import '../../data/local_repository.dart';
import '../ui2.dart';
import 'dial_parts.dart' show dialSeries;
import 'home_screen.dart' show repoOf;
import 'stress_monitor.dart' show StressSource;
import 'trend_view.dart' show shiftDay;

/// What a factor is called on its row, its glyph, and how the sentence names
/// it when it is the one holding the day back.
const _factorRows = <ReadinessFactor, (String, IconData, String)>{
  ReadinessFactor.recoveryTime: ('Recovery time', LucideIcons.timer, 'your recovery time'),
  ReadinessFactor.sleep: ('Last night’s sleep', LucideIcons.moon, 'last night’s sleep'),
  ReadinessFactor.recovery: ('Recovery', LucideIcons.heartPulse, 'your recovery'),
  ReadinessFactor.hrv: ('HRV status', LucideIcons.activity, 'your HRV status'),
  ReadinessFactor.load: ('Load ratio', LucideIcons.gauge, 'your load ratio'),
  ReadinessFactor.sleepHistory: ('Sleep, last 3 nights', LucideIcons.bedDouble, 'your sleep over the last three nights'),
  ReadinessFactor.stressHistory: ('Stress, last 3 days', LucideIcons.brain, 'your stress over the last three days'),
};

String _levelWord(ReadinessLevel l) => switch (l) {
      ReadinessLevel.prime => 'PRIME',
      ReadinessLevel.high => 'HIGH',
      ReadinessLevel.moderate => 'MODERATE',
      ReadinessLevel.low => 'LOW',
      ReadinessLevel.poor => 'POOR',
    };

/// `3h 30m`, `45m`, `0m`.
String recoveryTimeText(double hours) => durationText(hours * 60);

/// Reads [day]'s inputs off the repo. [now] is the moment recovery time is
/// counted to.
///
/// The last 7 days' mean HRV up to [day], and the 30 days before them as a
/// mean and spread (null with under 14 of those days stored).
({double? week, ({double mean, double sd})? base}) hrvWeekAndBase(
    Map<String, double> hrv, String day) {
  double? mean(Iterable<double> xs) =>
      xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
  final week = mean([for (var i = 0; i < 7; i++) ?hrv[shiftDay(day, -i)]]);
  final past = [for (var i = 7; i < 37; i++) ?hrv[shiftDay(day, -i)]];
  if (past.length < 14) return (week: week, base: null);
  final m = mean(past)!;
  final sd = math.sqrt(
      past.fold<double>(0, (a, v) => a + (v - m) * (v - m)) / past.length);
  return (week: week, base: (mean: m, sd: sd));
}

/// The acute and chronic load stored for [day], each null when absent.
Future<({double? acute, double? chronic})> storedLoads(
    LocalRepository repo, String day) async {
  try {
    final load = (await repo.getDayStrain(day))['load'];
    final v = load is Map && load['value'] is Map ? load['value'] as Map : load;
    if (v is Map) {
      return (
        acute: (v['atl'] as num?)?.toDouble(),
        chronic: (v['ctl'] as num?)?.toDouble(),
      );
    }
  } catch (_) {}
  return (acute: null, chronic: null);
}

Future<TrainingReadiness> loadTrainingReadiness(
    LocalRepository repo, String day, DateTime now) async {
  final rec = await dialSeries(repo, 'recovery');
  final perf = await dialSeries(repo, 'sleep_performance');
  final hrv = await dialSeries(repo, 'hrv');

  final (week: hrv7, base: hrvBase) = hrvWeekAndBase(hrv, day);
  final (:acute, :chronic) = await storedLoads(repo, day);

  var stress3 = const <double>[];
  try {
    final days = [for (var i = 1; i <= 3; i++) shiftDay(day, -i)];
    final got = await StressSource(repo).avgByDay(days);
    stress3 = [for (final d in days) ?got[d]];
  } catch (_) {}

  List<(int, double)>? sessions;
  final nowSec = now.millisecondsSinceEpoch ~/ 1000;
  try {
    final rows = await repo.getSessions(
        from: nowSec - 72 * 3600, to: nowSec, includeDetected: false);
    sessions = [
      for (final r in rows)
        if (r['end_ts'] is num && r['strain'] is num)
          ((r['end_ts'] as num).toInt(), (r['strain'] as num).toDouble()),
    ];
  } catch (_) {}

  return trainingReadiness(
    sleepPerf: perf[day],
    recovery: rec[day],
    hrv7: hrv7,
    hrvBase: hrvBase,
    acute: acute,
    chronic: chronic,
    sleep3: [for (var i = 0; i < 3; i++) ?perf[shiftDay(day, -i)]],
    stress3: stress3,
    sessions: sessions,
    now: nowSec,
  );
}

class TrainingReadinessCard extends StatefulWidget {
  final String day;

  /// Injected by tests; production reads the repo.
  final Future<TrainingReadiness> Function()? load;
  const TrainingReadinessCard({super.key, required this.day, this.load});

  @override
  State<TrainingReadinessCard> createState() => _TrainingReadinessCardState();
}

class _TrainingReadinessCardState extends State<TrainingReadinessCard> {
  Future<TrainingReadiness>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= widget.load?.call() ??
        () {
          LocalRepository? repo;
          try {
            repo = repoOf(context);
          } catch (_) {}
          return repo == null
              ? Future.value(
                  const TrainingReadiness(score: null, factors: {}))
              : loadTrainingReadiness(repo, widget.day, DateTime.now());
        }();
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<TrainingReadiness>(
        future: _f,
        builder: (c, snap) {
          final r = snap.data;
          if (r == null || r.factors.isEmpty) return const SizedBox.shrink();
          return TrainingReadinessView(r);
        },
      );
}

/// A factor row: 44 from one hairline to the next. The reference's 64.6 made
/// the seven rows the tallest thing on the strain screen.
const double _rowH = S.tap;

/// The card itself, for a readiness already worked out.
class TrainingReadinessView extends StatelessWidget {
  final TrainingReadiness r;
  const TrainingReadinessView(this.r, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final level = r.level;
    final weakest = r.weakest;
    final sentence = r.score == null
        ? 'It needs at least $kReadinessMinFactors of these to score.'
        : weakest == null
            ? 'Everything that feeds it is in good shape.'
            : 'Held back most by ${_factorRows[weakest]!.$3}.';
    final labelStyle = F.over.copyWith(
        color: p.ink, fontWeight: FontWeight.w700, letterSpacing: 1.2);
    final rows = [
      for (final f in ReadinessFactor.values) (f, _factorRows[f]!),
    ];

    return Surface(
      pad: const EdgeInsets.fromLTRB(S.x5, S.x2 + S.hair, S.x5, S.x4 + S.hair),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('TRAINING READINESS', style: labelStyle)),
          Pressable(
            onTap: () => _info(c),
            semanticLabel: 'About training readiness',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(LucideIcons.info, size: I.md, color: p.ink2),
              ),
            ),
          ),
        ]),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(r.score?.toString() ?? '--',
                style: F.n34.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
            const SizedBox(width: S.x1),
            Text('of 100', style: F.cap.copyWith(color: p.ink2)),
          ],
        ),
        if (level != null) ...[
          const SizedBox(height: S.x1 + S.half),
          Text(_levelWord(level), style: labelStyle.copyWith(color: p.ink2)),
        ],
        const SizedBox(height: S.x2),
        Text(sentence,
            style: F.body.copyWith(color: p.ink2, fontWeight: FontWeight.w400)),
        const SizedBox(height: S.x2),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Container(height: S.hair, color: p.ink.withValues(alpha: .08)),
          SizedBox(
            height: _rowH,
            child: Row(children: [
              SizedBox(
                width: I.md,
                child: Icon(rows[i].$2.$2, size: I.md, color: p.ink3),
              ),
              const SizedBox(width: S.x4 + S.hair),
              Expanded(
                child: Text(rows[i].$2.$1.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle),
              ),
              const SizedBox(width: S.x2),
              Text(_valueOf(rows[i].$1),
                  style: F.num(F.body)
                      .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ]),
    );
  }

  String _valueOf(ReadinessFactor f) {
    if (f == ReadinessFactor.recoveryTime) {
      final h = r.recoveryHours;
      return h == null ? '--' : recoveryTimeText(h);
    }
    // The ratio the row is named for, not its 0–100 share of the score.
    if (f == ReadinessFactor.load) {
      final x = r.loadRatio;
      return x == null ? '--' : x.toStringAsFixed(2);
    }
    return r.factors[f]?.toString() ?? '--';
  }

  void _info(BuildContext c) {
    showInfoSheet(
      c,
      'Training readiness',
      'How ready today is for hard training, 0 to 100. Each row is one '
      'thing that feeds it, scored 0 to 100: last night’s sleep and the '
      'two nights before, your recovery, your HRV against its usual range, '
      'your load ratio (the last week’s load over the last six weeks’; up '
      'to 1.30 is productive, past it the score falls, to 0 at 2.00), your stress '
      'over the last three days, and the recovery time still owed from '
      'recent sessions. The score is their average, pulled toward the '
      'weakest, so one poor input holds the day back. A row with nothing '
      'stored is left out.',
    );
  }
}
