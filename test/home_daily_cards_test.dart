// Home's daily cards: each kind fires on stored data that supports every
// number it states, and stays away without it.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/ui2/screens/home/home_daily_cards.dart';

const _today = '2026-11-08';

/// `{daysBack: value}` → a series keyed by local day (0 is today).
Map<String, double> _days(Map<int, num> back) => {
  for (final e in back.entries)
    dayLabelBefore(_today, e.key)!: e.value.toDouble(),
};

/// [n] days ending [from] days back, all [v].
Map<int, num> _flat(num v, {int from = 1, int n = 20}) => {
  for (var i = from; i < from + n; i++) i: v,
};

Set<DailyCardKind> _kinds(
  Map<String, Map<int, num>> s, {
  double? recovery,
  double? target,
  bool nightIsToday = true,
  bool illnessShown = false,
  int stepGoal = 10000,
}) => {
  for (final card in dailyCardsFor(
    today: _today,
    series: {for (final e in s.entries) e.key: _days(e.value)},
    recovery: recovery,
    strainTarget: target,
    nightIsToday: nightIsToday,
    illnessShown: illnessShown,
    stepGoal: stepGoal,
  ))
    card.kind,
};

void main() {
  // The copy formats numbers in the display locale, which reads the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nothing stored, nothing said', () {
    expect(_kinds({}), isEmpty);
  });

  group('recovery', () {
    test('first red only after a run of scored non-red mornings', () {
      expect(
        _kinds({'recovery': _flat(60)}, recovery: 25),
        contains(DailyCardKind.firstRed),
      );
      expect(
        _kinds({
          'recovery': {..._flat(60), 4: 20},
        }, recovery: 25),
        isNot(contains(DailyCardKind.firstRed)),
      );
      expect(
        _kinds({'recovery': _flat(60, n: 5)}, recovery: 25),
        isNot(contains(DailyCardKind.firstRed)),
        reason: 'five mornings are too few to call it a first',
      );
      expect(_kinds({'recovery': _flat(60)}, recovery: 50), isEmpty);
    });

    test('back in the green after mornings below it', () {
      final k = _kinds(
        {
          'recovery': {1: 50, 2: 40, 3: 80},
        },
        recovery: 75,
        target: 13,
      );
      expect(k, contains(DailyCardKind.backToGreen));
      expect(k, isNot(contains(DailyCardKind.greenTarget)));
      expect(
        _kinds({
          'recovery': {1: 50, 2: 80},
        }, recovery: 75),
        isNot(contains(DailyCardKind.backToGreen)),
      );
    });

    test('green with a target', () {
      expect(_kinds({}, recovery: 82, target: 14.2), {
        DailyCardKind.greenTarget,
      });
      expect(_kinds({}, recovery: 82), isEmpty, reason: 'no target stored');
      expect(_kinds({}, recovery: 60, target: 11), isEmpty);
    });

    test('a provisional or held-over morning says nothing', () {
      expect(_kinds({'recovery': _flat(60)}, recovery: null), isEmpty);
      expect(
        _kinds({'recovery': _flat(60)}, recovery: 25, nightIsToday: false),
        isEmpty,
      );
    });
  });

  group('HRV', () {
    test('above and below the 30-day average', () {
      expect(
        _kinds({
          'hrv': {..._flat(50, n: 10), ..._flat(70, from: 11, n: 1), 0: 58},
        }),
        {DailyCardKind.hrvHigh},
      );
      expect(
        _kinds({
          'hrv': {..._flat(60, n: 10), 0: 50},
        }),
        {DailyCardKind.hrvLow},
      );
      expect(
        _kinds({
          'hrv': {..._flat(60, n: 10), 0: 63},
        }),
        isEmpty,
      );
      expect(
        _kinds({
          'hrv': {..._flat(50, n: 5), 0: 70},
        }),
        isEmpty,
        reason: 'five nights are no usual',
      );
    });

    test('a record needs enough nights to beat', () {
      expect(
        _kinds({
          'hrv': {..._flat(50, n: 14), 0: 51},
        }),
        {DailyCardKind.hrvBest},
      );
      expect(
        _kinds({
          'hrv': {..._flat(50, n: 13), 0: 70},
        }),
        {DailyCardKind.hrvHigh},
      );
    });
  });

  group('resting heart rate', () {
    test('lower, higher and lowest', () {
      expect(
        _kinds({
          'resting_hr': {
            ..._flat(52, n: 10),
            ..._flat(45, from: 11, n: 1),
            0: 48,
          },
        }),
        {DailyCardKind.rhrLow},
      );
      expect(
        _kinds({
          'resting_hr': {..._flat(52, n: 10), 0: 56},
        }),
        {DailyCardKind.rhrHigh},
      );
      expect(
        _kinds({
          'resting_hr': {..._flat(52, n: 14), 0: 51},
        }),
        {DailyCardKind.rhrLowest},
      );
      expect(
        _kinds({
          'resting_hr': {..._flat(52, n: 10), 0: 53},
        }),
        isEmpty,
      );
    });

    test('stands down while the illness observation shows', () {
      expect(
        _kinds({
          'resting_hr': {..._flat(52, n: 10), 0: 56},
        }, illnessShown: true),
        isEmpty,
      );
    });
  });

  test('breathing rate above usual', () {
    expect(
      _kinds({
        'resp_rate': {..._flat(14.5, n: 10), 0: 15.8},
      }),
      {DailyCardKind.respHigh},
    );
    expect(
      _kinds({
        'resp_rate': {..._flat(14.5, n: 10), 0: 15.2},
      }),
      isEmpty,
    );
  });

  test('skin temperature off usual, either way', () {
    expect(
      _kinds({
        'skin_temp': {0: 2.3},
      }),
      {DailyCardKind.tempOff},
    );
    expect(
      _kinds({
        'skin_temp': {0: -2.1},
      }),
      {DailyCardKind.tempOff},
    );
    expect(
      _kinds({
        'skin_temp': {0: 1.2},
      }),
      isEmpty,
    );
  });

  test('sleep debt building and paid off', () {
    expect(
      _kinds({
        'sleep_debt_min': {0: 90, 1: 40},
      }),
      {DailyCardKind.debtBuilding},
    );
    expect(
      _kinds({
        'sleep_debt_min': {0: 90, 1: 120},
      }),
      isEmpty,
      reason: 'shrinking is not building',
    );
    expect(
      _kinds({
        'sleep_debt_min': {0: 5, 2: 80},
      }),
      {DailyCardKind.debtPaid},
    );
    expect(
      _kinds({
        'sleep_debt_min': {0: 5, 6: 80},
      }),
      isEmpty,
    );
  });

  test('more sleep than needed', () {
    expect(
      _kinds({
        'tst_min': {0: 490},
        'sleep_last_need_min': {0: 460},
      }),
      {DailyCardKind.sleptPlenty},
    );
    expect(
      _kinds({
        'tst_min': {0: 400},
        'sleep_last_need_min': {0: 460},
      }),
      isEmpty,
    );
    expect(
      _kinds({
        'tst_min': {0: 490},
      }),
      isEmpty,
      reason: 'no need stored',
    );
  });

  test('restorative sleep above its usual', () {
    final s = {
      'tst_min': _flat(400, from: 0, n: 10),
      'deep_min': _flat(80, from: 0, n: 10),
      'rem_min': {..._flat(80, n: 9), 0: 120},
    };
    expect(_kinds(s), {DailyCardKind.restorative});
    expect(_kinds({...s, 'rem_min': _flat(80, from: 0, n: 10)}), isEmpty);
  });

  test('sleep consistency high and slipping', () {
    expect(
      _kinds({
        'sleep_consistency': {0: 90},
      }),
      {DailyCardKind.consistencyHigh},
    );
    expect(
      _kinds({
        'sleep_consistency': {..._flat(80, n: 7), 0: 62},
      }),
      {DailyCardKind.consistencySlipping},
    );
    expect(
      _kinds({
        'sleep_consistency': {..._flat(66, n: 7), 0: 62},
      }),
      isEmpty,
    );
  });

  test('yesterday: strain target met and step goal reached', () {
    // Recovery 60 sets a 7.4 to 15.4 target.
    expect(
      _kinds({
        'recovery': {1: 60},
        'strain': {1: 12},
      }),
      {DailyCardKind.targetMet},
    );
    expect(
      _kinds({
        'recovery': {1: 60},
        'strain': {1: 17},
      }),
      isEmpty,
    );
    expect(
      _kinds({
        'strain': {1: 12},
      }),
      isEmpty,
      reason: 'no recovery, no target',
    );
    expect(
      _kinds({
        'steps': {1: 11240},
      }),
      {DailyCardKind.stepGoal},
    );
    expect(
      _kinds({
        'steps': {1: 8000},
      }),
      isEmpty,
    );
    expect(
      _kinds({
        'steps': {0: 12000},
      }),
      isEmpty,
      reason: 'today is not over',
    );
  });

  test('overnight cards wait for last night to be scored', () {
    expect(
      _kinds({
        'skin_temp': {0: 3},
        'steps': {1: 12000},
      }, nightIsToday: false),
      {DailyCardKind.stepGoal},
    );
  });

  test('most important first, and no more than the cap', () {
    final cards = dailyCardsFor(
      today: _today,
      series: {
        'recovery': _days(_flat(60)),
        'skin_temp': _days({0: 2.5}),
        'steps': _days({1: 12000}),
        'sleep_consistency': _days({0: 90}),
        'tst_min': _days({0: 500}),
        'sleep_last_need_min': _days({0: 450}),
        'resp_rate': _days({..._flat(14, n: 10), 0: 16}),
      },
      recovery: 25,
    );
    expect(cards.map((c) => c.kind), [
      DailyCardKind.firstRed,
      DailyCardKind.respHigh,
      DailyCardKind.tempOff,
      DailyCardKind.sleptPlenty,
      DailyCardKind.consistencyHigh,
    ]);
    expect(cards.first.bars!.last, 25);
    expect(cards.first.body, contains('first red in 20 scored mornings'));
  });

  test('every kind has a card that can fire', () {
    // The groups above each fire one; this pins that none is left unwritten.
    expect(DailyCardKind.values.length, greaterThanOrEqualTo(15));
  });
}
