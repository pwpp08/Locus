// TRAINING STATUS — the strain screen's card under training readiness: the
// last week's training in one word, where that word sits among the five, and
// the two numbers it was read from. The arithmetic is
// `compute/training_status.dart`. With under three weeks of strain behind it
// there is no status and the card is not drawn.

import 'package:flutter/material.dart';

import '../../compute/training_status.dart';
import '../../data/local_repository.dart';
import '../ui2.dart';
import 'dial_parts.dart' show dialSeries;
import 'home_screen.dart' show repoOf;
import 'training_readiness_card.dart' show hrvWeekAndBase, storedLoads;
import 'trend_view.dart' show shiftDay;

/// Left to right as load rises, which is the order the scale draws them in.
const _order = [
  TrainingStatus.detraining,
  TrainingStatus.recovering,
  TrainingStatus.maintaining,
  TrainingStatus.productive,
  TrainingStatus.overreaching,
];

String _word(TrainingStatus s) => switch (s) {
      TrainingStatus.detraining => 'Detraining',
      TrainingStatus.recovering => 'Recovering',
      TrainingStatus.maintaining => 'Maintaining',
      TrainingStatus.productive => 'Productive',
      TrainingStatus.overreaching => 'Overreaching',
    };

String _sentence(TrainingStatusResult r) {
  final strained = (r.hrvZ ?? 0) < -1;
  return switch (r.status!) {
    TrainingStatus.detraining =>
      'This week’s load is well under your six-week norm. Fitness fades '
          'if it stays there.',
    TrainingStatus.recovering =>
      'You have eased off after a heavier week. This is where the work '
          'sinks in.',
    TrainingStatus.maintaining => strained
        ? 'You are doing a little more than your norm, but your HRV is under '
            'its usual range, so it is holding, not building.'
        : 'This week’s load is about your six-week norm: enough to hold '
            'what you have.',
    TrainingStatus.productive =>
      'You are doing more than your norm${r.hrvZ == null ? '' : ' and your HRV is taking it well'}.',
    TrainingStatus.overreaching => strained && (r.ratio ?? 0) <= 1.3
        ? 'Load is up and your HRV is under its usual range. Ease off for a '
            'few days.'
        : 'This week’s load is far above your six-week norm. Ease off for '
            'a few days.',
  };
}

Future<TrainingStatusResult> loadTrainingStatus(
    LocalRepository repo, String day) async {
  final hrv = hrvWeekAndBase(await dialSeries(repo, 'hrv'), day);
  final strain = await dialSeries(repo, 'strain');
  final days = [
    for (var i = 0; i < 28; i++) ?strain[shiftDay(day, -i)],
  ].length;
  final now = await storedLoads(repo, day);
  final then = await storedLoads(repo, shiftDay(day, -7));
  return trainingStatus(
    acute: now.acute,
    chronic: now.chronic,
    days: days,
    ratioWeekAgo: then.acute == null || then.chronic == null || then.chronic! <= 0
        ? null
        : then.acute! / then.chronic!,
    hrv7: hrv.week,
    hrvBase: hrv.base,
  );
}

class TrainingStatusCard extends StatefulWidget {
  final String day;

  /// Injected by tests; production reads the repo.
  final Future<TrainingStatusResult> Function()? load;
  const TrainingStatusCard({super.key, required this.day, this.load});

  @override
  State<TrainingStatusCard> createState() => _TrainingStatusCardState();
}

class _TrainingStatusCardState extends State<TrainingStatusCard> {
  Future<TrainingStatusResult>? _f;

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
              ? Future.value(const TrainingStatusResult(
                  status: null, ratio: null, hrvZ: null, days: 0))
              : loadTrainingStatus(repo, widget.day);
        }();
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<TrainingStatusResult>(
        future: _f,
        builder: (c, snap) {
          final r = snap.data;
          if (r == null || r.status == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: S.x4),
            child: TrainingStatusView(r),
          );
        },
      );
}

/// The card itself, for a status already worked out ([r.status] not null).
class TrainingStatusView extends StatelessWidget {
  final TrainingStatusResult r;
  const TrainingStatusView(this.r, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final status = r.status!;
    final labelStyle = F.over.copyWith(
        color: p.ink, fontWeight: FontWeight.w700, letterSpacing: 1.2);
    final z = r.hrvZ;
    final rows = <(IconData, String, String)>[
      (LucideIcons.gauge, 'Load ratio', r.ratio!.toStringAsFixed(2)),
      (
        LucideIcons.activity,
        'HRV vs usual',
        z == null
            ? '--'
            : z < -1
                ? 'Below'
                : z > 1
                    ? 'Above'
                    : 'In range',
      ),
    ];
    return Surface(
      pad: const EdgeInsets.fromLTRB(S.x5, S.x2 + S.hair, S.x5, S.x2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('TRAINING STATUS', style: labelStyle)),
          Pressable(
            onTap: () => _info(c),
            semanticLabel: 'About training status',
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
        Text(_word(status),
            style: F.head.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: S.x3),
        // Where the word sits among the five, low load to high.
        Semantics(
          label: '${_order.indexOf(status) + 1} of ${_order.length}, '
              'from detraining to overreaching',
          child: Row(children: [
            for (final s in _order) ...[
              if (s != _order.first) const SizedBox(width: S.x1),
              Expanded(
                child: Container(
                  height: S.x1,
                  decoration: BoxDecoration(
                    color: s == status
                        ? C.dialStrain
                        : p.ink.withValues(alpha: .12),
                    borderRadius: R.rPill,
                  ),
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(height: S.x3),
        Text(_sentence(r),
            style: F.body.copyWith(color: p.ink2, fontWeight: FontWeight.w400)),
        const SizedBox(height: S.x2),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Container(height: S.hair, color: p.ink.withValues(alpha: .08)),
          SizedBox(
            height: S.tap,
            child: Row(children: [
              SizedBox(
                width: I.md,
                child: Icon(rows[i].$1, size: I.md, color: p.ink3),
              ),
              const SizedBox(width: S.x4 + S.hair),
              Expanded(
                child: Text(rows[i].$2.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle),
              ),
              const SizedBox(width: S.x2),
              Text(rows[i].$3,
                  style: F.num(F.body)
                      .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ]),
    );
  }

  void _info(BuildContext c) {
    showInfoSheet(
      c,
      'Training status',
      'What your last week of training is doing, in one word. It reads '
      'your load ratio (the last week’s load over the last six weeks’): under '
      '0.80 is detraining, or recovering if the week before was above your '
      'norm; 0.80 to 1.00 is maintaining; 1.00 to 1.30 is productive; past '
      '1.30 is overreaching. Your HRV over the last week is the check on '
      'it: when it sits below its usual range, productive reads as '
      'maintaining and a ratio past 1.10 reads as overreaching. It needs '
      '$kStatusMinDays days of strain in the last 28, and is a guide, not '
      'a measurement.',
    );
  }
}
