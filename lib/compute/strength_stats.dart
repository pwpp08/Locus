// STRENGTH, DERIVED ON READ — total volume by day, week or month, and the
// personal records and their progress. Nothing here is stored: it is all
// arithmetic over the sets the user logged (`strength_set`) plus the records
// they typed in by hand (`strength_record`), which is why a deleted session
// takes its volume with it and a record never drifts from what was lifted.
//
// A record is the heaviest load ever lifted for a reps-and-weight exercise, or
// the most reps in a set for one lifted with the body alone (a pull-up logged
// with no load). A record typed by hand is a PIN: it stands until something
// logged afterwards beats it, which is the only way a typed number and a
// measured one can both be honest about the same lift.

import 'dart:math' as math;

import '../data/day_label.dart';

/// One logged set, as the maths needs it. [ts] is epoch seconds.
typedef LoggedRow = ({String session, String key, int? reps, double? kg, int? ts});

/// What a record counts: the heaviest load (kg), or the most reps.
enum RecordKind { weight, reps }

/// A record the user typed by hand: a pin over [key].
typedef TypedRecord = ({String key, RecordKind kind, double value, int ts});

class PersonalRecord {
  final String key;
  final RecordKind kind;
  final double value;

  /// When it was lifted (or typed), epoch seconds; null when unknown.
  final int? ts;

  /// True when it is the user's own number rather than a logged set's.
  final bool typed;

  const PersonalRecord(this.key, this.kind, this.value, this.ts, this.typed);
}

/// The record a logged history gives for each exercise: the heaviest loaded
/// set (reps counting only when it has any), else the most reps unloaded.
/// Ties go to the earlier lift — the day it was first done.
Map<String, PersonalRecord> loggedRecords(Iterable<LoggedRow> rows) {
  final weight = <String, LoggedRow>{};
  final reps = <String, LoggedRow>{};
  for (final r in rows) {
    final n = r.reps ?? 0;
    if (n < 1) continue;
    final kg = r.kg;
    if (kg != null && kg > 0) {
      final b = weight[r.key];
      if (b == null || kg > b.kg! || (kg == b.kg && _before(r.ts, b.ts))) {
        weight[r.key] = r;
      }
    } else {
      final b = reps[r.key];
      if (b == null || n > b.reps! || (n == b.reps && _before(r.ts, b.ts))) {
        reps[r.key] = r;
      }
    }
  }
  return {
    for (final e in reps.entries)
      e.key: PersonalRecord(e.key, RecordKind.reps, e.value.reps!.toDouble(),
          e.value.ts, false),
    // A loaded lift outranks the same exercise done bare.
    for (final e in weight.entries)
      e.key: PersonalRecord(
          e.key, RecordKind.weight, e.value.kg!, e.value.ts, false),
  };
}

bool _before(int? a, int? b) => a != null && (b == null || a < b);

/// The records shown: each exercise's logged one, and the user's own pins. A
/// pin stands unless a logged record of the same kind is both higher and
/// later than it — then the lift has overtaken what was typed.
List<PersonalRecord> mergeRecords(
    Map<String, PersonalRecord> logged, Iterable<TypedRecord> typed) {
  final out = <String, PersonalRecord>{...logged};
  for (final t in typed) {
    final l = logged[t.key];
    final overtaken = l != null &&
        l.kind == t.kind &&
        l.value > t.value &&
        (l.ts ?? 0) > t.ts;
    if (!overtaken) {
      out[t.key] = PersonalRecord(t.key, t.kind, t.value, t.ts, true);
    }
  }
  final list = out.values.toList()
    ..sort((a, b) => (b.ts ?? 0).compareTo(a.ts ?? 0));
  return list;
}

/// The best of each session for one exercise, oldest first: the heaviest load
/// ([RecordKind.weight]) or the most reps ([RecordKind.reps]) in that session.
/// A typed record is a point of its own, on the day it was typed.
List<({int ts, double v})> recordProgress(
    String key, RecordKind kind, Iterable<LoggedRow> rows,
    {TypedRecord? typed}) {
  final bySession = <String, ({int ts, double v})>{};
  for (final r in rows) {
    if (r.key != key || r.ts == null) continue;
    final n = r.reps ?? 0;
    if (n < 1) continue;
    final double? v = switch (kind) {
      RecordKind.weight => (r.kg ?? 0) > 0 ? r.kg : null,
      RecordKind.reps => (r.kg ?? 0) > 0 ? null : n.toDouble(),
    };
    if (v == null) continue;
    final b = bySession[r.session];
    if (b == null || v > b.v) bySession[r.session] = (ts: r.ts!, v: v);
  }
  final out = bySession.values.toList()..sort((a, b) => a.ts.compareTo(b.ts));
  if (typed != null && typed.key == key && typed.kind == kind) {
    out
      ..add((ts: typed.ts, v: typed.value))
      ..sort((a, b) => a.ts.compareTo(b.ts));
  }
  return out;
}

// ── total volume ──────────────────────────────────────────────────────────

/// How the volume is cut: a week by its days, a month by its weeks (five of
/// them), six months by their months.
enum VolumeSpan { week, month, sixMonths }

class VolumeBar {
  /// The first local day the bar covers, `yyyy-MM-dd`, and the last.
  final String from, to;

  /// Σ reps × load over the loaded sets in it, in kg. Null when the stretch
  /// has no logged set at all (no bar), 0 is never invented.
  final double? kg;

  const VolumeBar(this.from, this.to, this.kg);
}

class VolumeWindow {
  final VolumeSpan span;
  final List<VolumeBar> bars;

  /// The first and last local day of the whole window.
  final String from, to;

  /// The mean of the bars that have a figure, or null when none does.
  final double? average;

  const VolumeWindow(this.span, this.bars, this.from, this.to, this.average);
}

DateTime _d(String label) {
  final p = label.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String _lab(DateTime d) => dayLabelOf(DateTime(d.year, d.month, d.day, 12));

/// The window [back] pages before the one that holds [today], cut by [span],
/// and each bar's volume. Weeks run Monday to Sunday.
VolumeWindow volumeWindow(Iterable<LoggedRow> rows, VolumeSpan span,
    {required String today, int back = 0}) {
  final t = _d(today);
  final starts = <DateTime>[];
  final ends = <DateTime>[];
  switch (span) {
    case VolumeSpan.week:
      final mon = DateTime(t.year, t.month, t.day - (t.weekday - 1) - 7 * back);
      for (var i = 0; i < 7; i++) {
        final d = DateTime(mon.year, mon.month, mon.day + i);
        starts.add(d);
        ends.add(d);
      }
    case VolumeSpan.month:
      // Five whole weeks, the last of them holding today.
      final mon = DateTime(
          t.year, t.month, t.day - (t.weekday - 1) - 28 - 35 * back);
      for (var i = 0; i < 5; i++) {
        final a = DateTime(mon.year, mon.month, mon.day + 7 * i);
        starts.add(a);
        ends.add(DateTime(a.year, a.month, a.day + 6));
      }
    case VolumeSpan.sixMonths:
      // Six calendar months, the last of them holding today.
      final first = DateTime(t.year, t.month - 5 - 6 * back);
      for (var i = 0; i < 6; i++) {
        final a = DateTime(first.year, first.month + i);
        starts.add(a);
        ends.add(DateTime(a.year, a.month + 1, 0));
      }
  }
  final sums = List<double?>.filled(starts.length, null);
  final from = _lab(starts.first), to = _lab(ends.last);
  final labels = [for (final s in starts) _lab(s)];
  final endLabels = [for (final e in ends) _lab(e)];
  for (final r in rows) {
    final ts = r.ts;
    if (ts == null) continue;
    final day = dayLabelOf(DateTime.fromMillisecondsSinceEpoch(ts * 1000));
    if (day.compareTo(from) < 0 || day.compareTo(to) > 0) continue;
    final kg = r.kg, reps = r.reps ?? 0;
    // A set with no load has no volume, but it was still a set that day.
    var i = 0;
    while (i < labels.length - 1 && day.compareTo(labels[i + 1]) >= 0) {
      i++;
    }
    sums[i] ??= 0;
    if (kg != null && kg > 0 && reps > 0) sums[i] = sums[i]! + kg * reps;
  }
  final bars = [
    for (var i = 0; i < labels.length; i++)
      VolumeBar(labels[i], endLabels[i], sums[i] == 0 ? null : sums[i]),
  ];
  final have = [for (final b in bars) if (b.kg != null) b.kg!];
  return VolumeWindow(span, bars, from, to,
      have.isEmpty ? null : have.reduce((a, b) => a + b) / have.length);
}

/// A tidy axis for [top] kg: the step (a 1, 2 or 5 times a power of ten) and a
/// ceiling one whole step above the tallest bar, so it never touches the top.
({double hi, double step}) volumeAxis(double top) {
  if (top <= 0) return (hi: 6000, step: 2000);
  final raw = top / 3;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / mag;
  final step = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * mag;
  return (hi: ((top / step).ceil() + 1) * step, step: step);
}
