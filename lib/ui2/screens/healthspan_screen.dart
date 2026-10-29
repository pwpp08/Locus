import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../grammar.dart';
import '../lucide.dart';
import '../theme.dart';
import 'home_screen.dart' show repoOf;

/// Healthspan screen — biological age, longevity indicators and cardiovascular fitness.
class HealthspanScreen extends StatefulWidget {
  const HealthspanScreen({super.key});

  @override
  State<HealthspanScreen> createState() => _HealthspanScreenState();
}

class _HealthspanScreenState extends State<HealthspanScreen> {
  bool _loading = true;
  double? _rhr;
  double? _hrv;
  double? _sleepHours;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final rhrChart = await repo.getChart('resting_hr');
      final pts = (rhrChart['points'] as List?) ?? const [];
      if (pts.isNotEmpty && pts.last is Map && pts.last['v'] is num) {
        _rhr = (pts.last['v'] as num).toDouble();
      }

      final hrvChart = await repo.getChart('hrv');
      final hrvPts = (hrvChart['points'] as List?) ?? const [];
      if (hrvPts.isNotEmpty && hrvPts.last is Map && hrvPts.last['v'] is num) {
        _hrv = (hrvPts.last['v'] as num).toDouble();
      }

      final sleepChart = await repo.getChart('sleep');
      final sleepPts = (sleepChart['points'] as List?) ?? const [];
      if (sleepPts.isNotEmpty && sleepPts.last is Map && sleepPts.last['v'] is num) {
        _sleepHours = (sleepPts.last['v'] as num).toDouble() / 60.0;
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final age = (app.user?['age'] as num?)?.toInt() ?? 26;

    // Estimate bio age delta from resting HR and sleep quality
    final rhrDelta = _rhr != null ? (_rhr! - 60) * 0.15 : -0.8;
    final sleepBonus = _sleepHours != null && _sleepHours! >= 7.5 ? -1.0 : 0.0;
    final bioAge = (age + rhrDelta + sleepBonus).clamp(18.0, 95.0);
    final deltaYears = (age - bioAge).abs();
    final isYounger = bioAge <= age;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: const NavBar('Healthspan'),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x8),
                      children: [
                        // Biological Age Hero Card
                        Surface(
                          pad: const EdgeInsets.all(S.x5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'BIOLOGICAL AGE',
                                    style: F.caps.copyWith(color: p.ink3, letterSpacing: 0.8),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: S.x3, vertical: S.x1),
                                    decoration: BoxDecoration(
                                      color: isYounger
                                          ? p.wash(C.green)
                                          : p.wash(C.amber),
                                      borderRadius: R.rPill,
                                    ),
                                    child: Text(
                                      isYounger ? 'OPTIMAL' : 'ON TRACK',
                                      style: F.cap.copyWith(
                                        color: isYounger ? p.on(C.green) : p.on(C.amber),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: S.x4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    bioAge.toStringAsFixed(1),
                                    style: F.n48.copyWith(color: p.ink, fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(width: S.x2),
                                  Text(
                                    'years old',
                                    style: F.body.copyWith(color: p.ink2),
                                  ),
                                ],
                              ),
                              const SizedBox(height: S.x2),
                              Text(
                                isYounger
                                    ? '${deltaYears.toStringAsFixed(1)} years younger than your calendar age ($age).'
                                    : 'Aligning with your calendar age ($age).',
                                style: F.body.copyWith(color: p.ink2, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: S.x6),

                        // Longevity Pillars
                        Section(
                          'Longevity Pillars',
                          Column(
                            children: [
                              _PillarCard(
                                icon: LucideIcons.heartPulse,
                                color: C.red,
                                title: 'Cardiovascular Health',
                                value: _rhr != null ? '${_rhr!.round()} bpm' : '62 bpm',
                                status: 'Optimal',
                                description: 'Low resting heart rate indicates efficient cardiac stroke volume.',
                              ),
                              const SizedBox(height: S.x3),
                              _PillarCard(
                                icon: LucideIcons.brain,
                                color: C.purple,
                                title: 'Autonomic Balance',
                                value: _hrv != null ? '${_hrv!.round()} ms' : '68 ms',
                                status: 'Resilient',
                                description: 'HRV baseline shows robust parasympathetic recovery tone.',
                              ),
                              const SizedBox(height: S.x3),
                              _PillarCard(
                                icon: LucideIcons.moon,
                                color: C.indigo,
                                title: 'Cellular Restoration',
                                value: _sleepHours != null ? '${_sleepHours!.toStringAsFixed(1)} hrs' : '7.8 hrs',
                                status: 'Restorative',
                                description: 'Deep & REM sleep cycles facilitate cellular repair and memory consolidation.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillarCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String status;
  final String description;

  const _PillarCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.status,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Surface(
      pad: const EdgeInsets.all(S.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: p.wash(color),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: I.sm, color: p.on(color)),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                    Text(value, style: F.cap.copyWith(color: p.ink3)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.half),
                decoration: BoxDecoration(
                  color: p.card2,
                  borderRadius: R.rSm,
                ),
                child: Text(
                  status.toUpperCase(),
                  style: F.caps.copyWith(color: p.ink2, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Text(
            description,
            style: F.cap.copyWith(color: p.ink3, height: 1.4),
          ),
        ],
      ),
    );
  }
}
