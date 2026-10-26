// An exercise's photo: the two frames of the movement the Free Exercise DB
// ships (public domain), bundled with the app and shown as a still, or swapped
// once a second like a short gif. An exercise with no photo shows its muscle
// group's mark on a plain tile instead; nothing is fetched.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../lucide.dart';
import '../theme.dart';
import 'catalogue.dart';

/// The step-by-step instructions of an exercise with a photo, or empty.
/// Read from one bundled file the first time, then kept.
Future<List<String>> exerciseSteps(ExerciseDef? def) async {
  final id = def?.imageId;
  if (id == null) return const [];
  _steps ??= () async {
    try {
      final j = jsonDecode(
          await rootBundle.loadString('assets/exercises/instructions.json'));
      return {
        if (j is Map)
          for (final e in j.entries)
            e.key as String: [
              if (e.value is List) for (final s in e.value as List) '$s',
            ],
      };
    } catch (_) {
      return <String, List<String>>{};
    }
  }();
  return (await _steps!)[id] ?? const [];
}

Future<Map<String, List<String>>>? _steps;

class ExerciseImage extends StatefulWidget {
  final ExerciseDef? def;
  final double width, height;
  final BorderRadius radius;

  /// Swap between the two frames, once a second, unless motion is reduced.
  final bool animate;

  const ExerciseImage({
    super.key,
    required this.def,
    this.width = S.x16 + S.x4,
    this.height = S.x16 - S.x2,
    this.radius = R.rMd,
    this.animate = false,
  });

  @override
  State<ExerciseImage> createState() => _ExerciseImageState();
}

class _ExerciseImageState extends State<ExerciseImage> {
  Timer? _t;
  int _frame = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ExerciseImage old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final want = widget.animate &&
        Motion.enabled(context) &&
        (widget.def == null ? 0 : photoOf(widget.def!)?.imageFrames ?? 0) > 1;
    if (!want) {
      _t?.cancel();
      _t = null;
      _frame = 0;
    } else {
      _t ??= Timer.periodic(Motion.tick, (_) {
        if (mounted) setState(() => _frame = 1 - _frame);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = widget.def;
    final path = (d == null ? null : photoOf(d))?.imagePath(_frame);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: widget.radius,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: path == null
              ? ColoredBox(
                  color: p.ink.withValues(alpha: .08),
                  child: Center(
                      child: Icon(LucideIcons.dumbbell,
                          size: I.lg, color: p.ink3)),
                )
              : Image(
                  image: AssetImage(path),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: p.ink.withValues(alpha: .08),
                    child: Center(
                        child: Icon(LucideIcons.dumbbell,
                            size: I.lg, color: p.ink3)),
                  ),
                ),
        ),
      ),
    );
  }
}
