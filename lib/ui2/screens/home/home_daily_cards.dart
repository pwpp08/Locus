// The daily cards under Home's dials: what is worth a sentence about today,
// read off stored series and nothing else. Each kind fires only when every
// number it states is a stored value (or plain arithmetic on stored values),
// against the user's own history. No history, no card.

import 'dart:math' as math;
import 'dart:ui' show Color;

import '../../../compute/whoop_scores.dart' show whoopStrainTarget;
import '../../../data/day_label.dart' show dayLabelBefore;
import '../../../data/local_repository.dart' show kDefaultStepGoal;
import '../../../l10n/decimal_text.dart' show displayFixed;
import '../../../state/prefs.dart';
import '../../theme.dart' show C;
import 'home_data.dart' show HomeData, hm, recoveryColor, thousands;

/// Every threshold the cards use, in one place.
class DailyCardRules {
  DailyCardRules._();

  /// "Your usual" is the mean of this many days before today…
  static const usualDays = 30;

  /// …and means nothing until at least this many of them have a value.
  static const usualMin = 7;

  /// HRV this far off its usual, in percent, is worth saying.
  static const hrvPct = 10.0;

  /// Resting heart rate this far off its usual, bpm.
  static const rhrBpm = 3.0;

  /// Breathing rate this far above its usual, breaths a minute.
  static const respAbove = 1.0;

  /// Skin temperature this many of the user's own night-to-night swings off
  /// usual (the stored series is already that z-score).
  static const tempZ = 2.0;

  /// A "highest / lowest yet" needs this many earlier nights to beat.
  static const recordMin = 14;

  /// A red morning is "the first in a while" only when this many scored
  /// mornings in the last [usualDays] were all above red.
  static const redFreeMin = 14;

  /// Mornings below green in a row before green again is news.
  static const belowGreenRun = 2;

  /// Sleep debt (min) worth a card, and the most still counting as paid off.
  static const debtMin = 60.0;
  static const debtClearMax = 15.0;

  /// How many days back a paid-off debt may have been owed.
  static const debtLookback = 3;

  /// Sleep consistency (%) worth praising, and the slip that is worth naming:
  /// under [consistencyLow] AND [consistencySlip] points below the last week.
  static const consistencyHigh = 85.0;
  static const consistencyLow = 70.0;
  static const consistencySlip = 10.0;

  /// Deep + REM share of the night, points above its usual.
  static const restorativeAbove = 5.0;

  /// A deck longer than this is homework, not a glance.
  static const maxCards = 5;
}

/// The kinds, most important first: the deck is shown in this order.
enum DailyCardKind {
  firstRed,
  rhrHigh,
  respHigh,
  tempOff,
  hrvLow,
  debtBuilding,
  strainOver,
  backToGreen,
  greenTarget,
  hrvBest,
  rhrLowest,
  hrvHigh,
  rhrLow,
  sleptPlenty,
  debtPaid,
  restorative,
  consistencySlipping,
  consistencyHigh,
  targetReached,
  stepGoalToday,
  targetMet,
  stepGoal,
}

/// One card: a title and a sentence or two. A card about the week's recovery
/// also carries that week, oldest first and null where nothing was stored,
/// with today's bar in [lit].
class DailyCard {
  final DailyCardKind kind;
  final String title, body;
  final List<double?>? bars;
  final Color? lit;

  const DailyCard(this.kind, this.title, this.body, {this.bars, this.lit});
}

/// The getChart keys the cards read.
const kDailyCardSeries = [
  'recovery',
  'hrv',
  'resting_hr',
  'resp_rate',
  'skin_temp',
  'sleep_debt_min',
  'tst_min',
  'sleep_last_need_min',
  'deep_min',
  'rem_min',
  'sleep_consistency',
  'strain',
  'steps',
];

/// Today's cards for [d], off [series] (a getChart key → value per local day).
Future<List<DailyCard>> loadDailyCards(
  HomeData d,
  Future<Map<String, double>> Function(String key) series,
) async {
  final s = {for (final k in kDailyCardSeries) k: await series(k)};
  return dailyCardsFor(
    today: d.dayId ?? '',
    series: s,
    recovery: d.recoveryState == 'provisional'
        ? null
        : d.readiness.value?.toDouble(),
    strainTarget: (d.strainTarget?['value'] as num?)?.toDouble(),
    nightIsToday: d.heldOverNight == null,
    illnessShown: d.illnessState != null && d.illnessState != 'green',
    stepGoal: d.stepGoal,
    strainNow: d.strain.value?.toDouble(),
    stepsNow: d.steps.value?.toDouble(),
  );
}

/// The cards [today]'s stored data supports, most important first.
///
/// [recovery] is the score the dial shows (null when it is provisional or
/// absent). [nightIsToday] is false when last night has not been scored, so
/// nothing overnight is said about it. [illnessShown]: Home already carries
/// the raised-resting-heart-rate observation, so that card stands down.
/// [strainNow] and [stepsNow] are today's running figures: the cards they
/// raise appear the moment the day earns them, not the morning after.
List<DailyCard> dailyCardsFor({
  required String today,
  required Map<String, Map<String, double>> series,
  double? recovery,
  double? strainTarget,
  bool nightIsToday = true,
  bool illnessShown = false,
  int stepGoal = kDefaultStepGoal,
  double? strainNow,
  double? stepsNow,
}) {
  final out = <DailyCard>[];
  String? dayBack(int n) => dayLabelBefore(today, n);
  final yesterday = dayBack(1);
  Map<String, double> of(String k) => series[k] ?? const {};

  /// Values on the [n] days before today that have one.
  List<double> prior(Map<String, double> m, int n) => [
    for (var i = 1; i <= n; i++) ?m[dayBack(i)],
  ];

  /// Every value stored before today.
  List<double> before(Map<String, double> m) => [
    for (final e in m.entries)
      if (e.key.compareTo(today) < 0) e.value,
  ];

  double? usual(Map<String, double> m) {
    final xs = prior(m, DailyCardRules.usualDays);
    return xs.length < DailyCardRules.usualMin
        ? null
        : xs.reduce((a, b) => a + b) / xs.length;
  }

  /// Seven days ending today, oldest first.
  List<double?> week(Map<String, double> m, double todayValue) => [
    for (var i = 6; i >= 1; i--) m[dayBack(i)],
    todayValue,
  ];

  String whole(num v) => v.round().toString();
  String one(num v) => displayFixed(v, 1);

  // ── recovery ──
  final rec = nightIsToday ? recovery : null;
  if (rec != null) {
    final recs = of('recovery');
    if (rec < 34) {
      final last = prior(recs, DailyCardRules.usualDays);
      if (last.length >= DailyCardRules.redFreeMin &&
          last.every((v) => v >= 34)) {
        out.add(
          DailyCard(
            DailyCardKind.firstRed,
            'First red in a while',
            'Recovery is ${whole(rec)}%, your first red in ${last.length} '
                'scored mornings. One low morning is a cue to go easy, not a '
                'trend.',
            bars: week(recs, rec),
            lit: C.recRed,
          ),
        );
      }
    }
    if (rec >= 67) {
      var run = 0;
      for (var i = 1; i <= DailyCardRules.usualDays; i++) {
        final v = recs[dayBack(i)];
        if (v == null || v >= 67) break;
        run++;
      }
      final aim = strainTarget == null
          ? ''
          : ' A strain around ${one(strainTarget)} fits today.';
      if (run >= DailyCardRules.belowGreenRun) {
        out.add(
          DailyCard(
            DailyCardKind.backToGreen,
            'Back in the green',
            'After $run mornings below green, recovery is back at '
                '${whole(rec)}%.$aim',
            bars: week(recs, rec),
            lit: recoveryColor(rec),
          ),
        );
      } else if (strainTarget != null) {
        out.add(
          DailyCard(
            DailyCardKind.greenTarget,
            'Ready for a big day',
            'Recovery is ${whole(rec)}%, so your body can take real load. '
                'Aim for a strain around ${one(strainTarget)} today.',
          ),
        );
      }
    }
  }

  // ── HRV and resting heart rate ──
  if (nightIsToday) {
    final hrv = of('hrv');
    final h = hrv[today];
    final hu = usual(hrv);
    if (h != null) {
      final earlier = before(hrv);
      if (earlier.length >= DailyCardRules.recordMin &&
          h > earlier.reduce(math.max)) {
        out.add(
          DailyCard(
            DailyCardKind.hrvBest,
            'Your highest HRV yet',
            '${whole(h)} ms last night is the highest of the '
                '${earlier.length + 1} nights on record.',
          ),
        );
      } else if (hu != null) {
        final pct = (h / hu - 1) * 100;
        if (pct >= DailyCardRules.hrvPct) {
          out.add(
            DailyCard(
              DailyCardKind.hrvHigh,
              'HRV above your usual',
              'Last night\'s HRV of ${whole(h)} ms was ${whole(pct)}% above '
                  'your 30-day average of ${whole(hu)} ms. Your body is '
                  'handling its load well.',
            ),
          );
        } else if (pct <= -DailyCardRules.hrvPct) {
          out.add(
            DailyCard(
              DailyCardKind.hrvLow,
              'HRV below your usual',
              'Last night\'s HRV of ${whole(h)} ms was ${whole(-pct)}% under '
                  'your 30-day average of ${whole(hu)} ms. A lighter day '
                  'gives it room to come back.',
            ),
          );
        }
      }
    }

    final rhr = of('resting_hr');
    final r = rhr[today];
    final ru = usual(rhr);
    if (r != null) {
      final earlier = before(rhr);
      if (earlier.length >= DailyCardRules.recordMin &&
          r < earlier.reduce(math.min)) {
        out.add(
          DailyCard(
            DailyCardKind.rhrLowest,
            'Your lowest resting heart rate yet',
            '${whole(r)} bpm last night is the lowest of the '
                '${earlier.length + 1} nights on record.',
          ),
        );
      } else if (ru != null) {
        final diff = r - ru;
        if (diff <= -DailyCardRules.rhrBpm) {
          out.add(
            DailyCard(
              DailyCardKind.rhrLow,
              'Resting heart rate below usual',
              '${whole(r)} bpm last night, ${whole(-diff)} under your 30-day '
                  'average of ${whole(ru)} bpm.',
            ),
          );
        } else if (diff >= DailyCardRules.rhrBpm && !illnessShown) {
          out.add(
            DailyCard(
              DailyCardKind.rhrHigh,
              'Resting heart rate above usual',
              '${whole(r)} bpm last night, ${whole(diff)} over your 30-day '
                  'average of ${whole(ru)} bpm. Worth an easier day if it '
                  'stays up.',
            ),
          );
        }
      }
    }

    // ── breathing and skin temperature: a pattern, never a cause ──
    final resp = of('resp_rate');
    final b = resp[today];
    final bu = usual(resp);
    if (b != null && bu != null && b - bu >= DailyCardRules.respAbove) {
      out.add(
        DailyCard(
          DailyCardKind.respHigh,
          'Breathing rate above usual',
          '${one(b)} breaths a minute last night, ${one(b - bu)} above your '
              '30-day average of ${one(bu)}.',
        ),
      );
    }
    final z = of('skin_temp')[today];
    if (z != null && z.abs() >= DailyCardRules.tempZ) {
      out.add(
        DailyCard(
          DailyCardKind.tempOff,
          'Skin temperature off your usual',
          'Last night ran ${z > 0 ? 'warmer' : 'cooler'} than usual for you: '
              '${one(z.abs())} times your normal night-to-night swing.',
        ),
      );
    }

    // ── sleep ──
    final debts = of('sleep_debt_min');
    final debt = debts[today];
    if (debt != null) {
      final was = yesterday == null ? null : debts[yesterday];
      if (debt >= DailyCardRules.debtMin && was != null && debt > was) {
        out.add(
          DailyCard(
            DailyCardKind.debtBuilding,
            'Sleep debt is building',
            'You carry ${hm(debt)} of sleep debt into tonight, up from '
                '${hm(math.max(0, was))}. An earlier night starts paying it '
                'back.',
          ),
        );
      } else if (debt <= DailyCardRules.debtClearMax) {
        for (var i = 1; i <= DailyCardRules.debtLookback; i++) {
          final owed = debts[dayBack(i)];
          if (owed != null && owed >= DailyCardRules.debtMin) {
            out.add(
              DailyCard(
                DailyCardKind.debtPaid,
                'Sleep debt paid off',
                '${i == 1 ? 'Yesterday' : '$i days ago'} you owed ${hm(owed)} '
                    'of sleep. Last night cleared it.',
              ),
            );
            break;
          }
        }
      }
    }

    final tst = of('tst_min')[today];
    final need = of('sleep_last_need_min')[today];
    if (tst != null && need != null && need > 0 && tst >= need) {
      out.add(
        DailyCard(
          DailyCardKind.sleptPlenty,
          'More sleep than you needed',
          'Last night gave you ${hm(tst)} of sleep against a need of '
              '${hm(need)}.',
        ),
      );
    }

    double? restorative(String day) {
      final deep = of('deep_min')[day], rem = of('rem_min')[day];
      final t = of('tst_min')[day];
      if (deep == null || rem == null || t == null || t <= 0) return null;
      return (deep + rem) / t * 100;
    }

    final rp = restorative(today);
    if (rp != null) {
      final xs = [
        for (var i = 1; i <= DailyCardRules.usualDays; i++)
          ?restorative(dayBack(i) ?? ''),
      ];
      if (xs.length >= DailyCardRules.usualMin) {
        final ru = xs.reduce((a, b) => a + b) / xs.length;
        if (rp - ru >= DailyCardRules.restorativeAbove) {
          out.add(
            DailyCard(
              DailyCardKind.restorative,
              'Plenty of restorative sleep',
              'Deep and REM sleep made up ${whole(rp)}% of last night, '
                  'against your usual ${whole(ru)}%.',
            ),
          );
        }
      }
    }

    final cons = of('sleep_consistency');
    final cn = cons[today];
    if (cn != null) {
      final xs = prior(cons, 7);
      final cu = xs.length < 4 ? null : xs.reduce((a, b) => a + b) / xs.length;
      if (cn >= DailyCardRules.consistencyHigh) {
        out.add(
          DailyCard(
            DailyCardKind.consistencyHigh,
            'A steady sleep schedule',
            'Your sleep consistency is ${whole(cn)}%. Going to bed and waking '
                'at similar times helps every night count.',
          ),
        );
      } else if (cu != null &&
          cn < DailyCardRules.consistencyLow &&
          cu - cn >= DailyCardRules.consistencySlip) {
        out.add(
          DailyCard(
            DailyCardKind.consistencySlipping,
            'Your sleep schedule is slipping',
            'Sleep consistency fell to ${whole(cn)}%, from a 7-night average '
                'of ${whole(cu)}%. Bed and wake times have been moving around.',
          ),
        );
      }
    }
  }

  // ── today, as it happens ──
  final target = whoopStrainTarget(rec);
  if (strainNow != null && target != null) {
    if (strainNow > target.hi) {
      out.add(
        DailyCard(
          DailyCardKind.strainOver,
          "Past today's strain target",
          'Strain is ${one(strainNow)}, over the ${one(target.lo)}–'
              '${one(target.hi)} your recovery set. Anything more today adds '
              'to what tonight has to recover.',
        ),
      );
    } else if (strainNow >= target.lo) {
      out.add(
        DailyCard(
          DailyCardKind.targetReached,
          'Strain target reached',
          "Today's strain of ${one(strainNow)} is inside the "
              '${one(target.lo)}–${one(target.hi)} target your recovery set.',
        ),
      );
    }
  }
  if (stepsNow != null && stepGoal > 0 && stepsNow >= stepGoal) {
    out.add(
      DailyCard(
        DailyCardKind.stepGoalToday,
        'Step goal reached',
        '${thousands(stepsNow)} steps so far today, past your goal of '
            '${thousands(stepGoal)}.',
      ),
    );
  }

  // ── yesterday, which is finished ──
  if (yesterday != null) {
    final s = of('strain')[yesterday];
    final t = whoopStrainTarget(of('recovery')[yesterday]);
    if (s != null && t != null && s >= t.lo && s <= t.hi) {
      out.add(
        DailyCard(
          DailyCardKind.targetMet,
          'Strain target met',
          'Yesterday\'s strain of ${one(s)} landed inside the '
              '${one(t.lo)}–${one(t.hi)} target your recovery set.',
        ),
      );
    }
    final steps = of('steps')[yesterday];
    if (steps != null && stepGoal > 0 && steps >= stepGoal) {
      out.add(
        DailyCard(
          DailyCardKind.stepGoal,
          'Step goal reached',
          'You walked ${thousands(steps)} steps yesterday, past your goal of '
              '${thousands(stepGoal)}.',
        ),
      );
    }
  }

  out.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return out.take(DailyCardRules.maxCards).toList();
}

/// The kinds put away on [day] (a local day label). Another day's list is
/// stale: it reads as nothing and is cleared.
Set<String> dismissedCardsOn(String day) {
  final raw = Prefs.getString(Prefs.dailyCardsDismissed, '');
  final bar = raw.indexOf('|');
  if (bar < 0 || raw.substring(0, bar) != day) {
    if (raw.isNotEmpty) Prefs.setString(Prefs.dailyCardsDismissed, '');
    return {};
  }
  return {
    for (final k in raw.substring(bar + 1).split(','))
      if (k.isNotEmpty) k,
  };
}

/// Put [kind] away for the rest of [day].
void dismissCardOn(String day, DailyCardKind kind) {
  final kinds = {...dismissedCardsOn(day), kind.name};
  Prefs.setString(Prefs.dailyCardsDismissed, '$day|${kinds.join(',')}');
}
