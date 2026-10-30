// THE MOVEMENT LANE — columns under a heart-rate chart, one a minute: the
// taller the column, the more of that minute the wrist was turning. It is the
// same measure as the day breakdown's "Moving" band (compute/movement.dart),
// read per minute from the band's own seconds while they are kept, and from
// the day's stored five-minute curve after they are pruned — coarser, but
// still measured. A stretch with neither has no column, never a zero one.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../ui2.dart';

/// One column: the bucket's start (epoch seconds), its width in seconds (60,
/// or 300 for the stored curve) and the share of it spent moving, 0…1.
typedef MovePoint = ({int t, int span, double v});

/// Movement from [from] to [to]: per minute from the band's seconds, else the
/// stored five-minute curve of [day] (needs [repo]). Empty when neither exists.
Future<List<MovePoint>> readMovement(
  int from,
  int to, {
  LocalRepository? repo,
  String? day,
}) async {
  try {
    final m = await LocalDb.movementPerMinuteBetween(from, to);
    if (m.isNotEmpty) return [for (final e in m) (t: e.t, span: 60, v: e.v)];
  } catch (_) {}
  if (repo == null || day == null) return const [];
  try {
    final tl = await repo.getDayTimeline(day);
    return [
      for (final e in (tl['activity'] as List?) ?? const [])
        if (e is Map &&
            e['t'] is num &&
            e['v'] is num &&
            (e['t'] as num) + 300 > from &&
            (e['t'] as num) < to)
          (t: (e['t'] as num).toInt(), span: 300, v: (e['v'] as num).toDouble()),
    ];
  } catch (_) {
    return const [];
  }
}

/// Draws [pts] into [lane]: one column per bucket, its height the share of
/// the bucket spent moving, its foot on the lane's floor. [xOf] maps epoch
/// seconds to x, the same mapping the chart above uses, so a column sits
/// under the minute of heart rate it belongs to.
void paintMovement(
  Canvas canvas,
  Rect lane,
  List<MovePoint> pts,
  double Function(num t) xOf,
  Color color,
) {
  if (pts.isEmpty) return;
  canvas.save();
  canvas.clipRect(lane);
  final paint = Paint()..color = color;
  for (final m in pts) {
    if (m.v <= 0) continue;
    final x0 = xOf(m.t), x1 = xOf(m.t + m.span);
    if (x1 < lane.left || x0 > lane.right) continue;
    final w = x1 - x0;
    // A gap between columns once they are wide enough to show one.
    final gap = w > S.x1 ? math.min(S.half, w * .2) : 0.0;
    final h = math.max(S.half / 2, m.v.clamp(0.0, 1.0) * lane.height);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(x0 + gap / 2, lane.bottom - h, x1 - gap / 2, lane.bottom),
        topLeft: const Radius.circular(R.sm / 3),
        topRight: const Radius.circular(R.sm / 3),
      ),
      paint,
    );
  }
  canvas.restore();
}

/// The movement share at [t], or null where nothing was measured.
double? movementAt(List<MovePoint> pts, int t) {
  for (final m in pts) {
    if (t >= m.t && t < m.t + m.span) return m.v;
  }
  return null;
}
