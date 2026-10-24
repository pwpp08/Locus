import 'coach_text.dart';
// THE DATA BOUNDARY — the daily briefing, and exactly what left the device to
// produce it.
//
// `Briefing.inputs` is the compact metric snapshot the prompt was built from,
// stored beside every briefing since the engine was written. Nothing ever read
// it. That map IS the payload — `buildBriefingUserPrompt` writes one `key: value`
// line per entry and adds nothing — so this screen can state, exactly and
// without hedging, what a third party received.
//
// For an app whose whole argument is that the data stays on the phone, this is
// not a nicety. It is the thing that makes choosing a cloud key a decision
// rather than a leap, and it is why the local presets come first in setup.

import '../../l10n/display_text.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../ai/briefing.dart';
import '../../ai/briefing_engine.dart';
import '../../coach/coach_config.dart';
import '../../coach/coach_engine.dart' show CoachException;
import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'coach.dart' show CoachSetup, kCoachAccent;
import 'home_screen.dart' show go, pad, repoOf;

class AiBriefingScreen extends StatefulWidget {
  final BriefingPeriod period;
  const AiBriefingScreen({super.key, required this.period});

  @override
  State<AiBriefingScreen> createState() => _AiBriefingScreenState();
}

class _AiBriefingScreenState extends State<AiBriefingScreen> {
  Briefing? _b;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _b = BriefingStore.read(widget.period);
  }

  Future<void> _generate() async {
    final repo = repoOf(context);
    if (repo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final b = await BriefingEngine(
        config: context.read<CoachConfig>(),
        repo: repo,
      ).generate(widget.period);
      if (mounted) setState(() => _b = b);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        setState(
          () => _error = e is CoachException
              ? e.message
              : (l?.aiBriefingFailedGeneric('$e') ?? 'It failed: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final cfg = c.watch<CoachConfig>();
    final b = _b;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(
                uiText(c, widget.period.title),
                sub: b == null
                    ? ''
                    : (l?.aiBriefingForDay(b.day) ?? 'FOR ${b.day}'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: pad,
                children: [
                  const SizedBox(height: S.x2),
                  if (!cfg.configured)
                    StatusCard(
                      l?.aiBriefingNoModelTitle ?? 'No model is set up',
                      l?.aiBriefingNoModelBody ??
                          'A briefing is written by a model you choose. Until you '
                              'pick one there is nothing to generate and nothing '
                              'has been sent anywhere.',
                      fix: l?.aiBriefingChooseModel ?? 'Choose a model',
                      icon: LucideIcons.sparkles,
                      onFix: () => go(c, const CoachSetup()),
                    )
                  else if (b == null)
                    StatusCard(
                      l?.aiBriefingNothingTitle ?? 'Nothing written for today',
                      l?.aiBriefingNothingBody ??
                          'Briefings are generated on a schedule, or on demand '
                              'here.',
                      fix: _busy
                          ? (l?.aiBriefingWriting ?? 'Writing…')
                          : (l?.aiBriefingWriteNow ?? 'Write one now'),
                      icon: LucideIcons.sun,
                      onFix: _busy ? null : _generate,
                    )
                  else ...[
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.oneLiner == 'Nothing stood out tonight.'
                                ? uiText(c, b.oneLiner)
                                : b.oneLiner,
                            style: F.body.copyWith(color: p.ink, height: 1.5),
                          ),
                          if (b.breakdownMd.isNotEmpty) ...[
                            const SizedBox(height: S.x3),
                            Text(
                              b.breakdownMd,
                              style: F.cap.copyWith(color: p.ink2, height: 1.6),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: S.x3),
                    BigButton(
                      _busy
                          ? (l?.aiBriefingWriting ?? 'Writing…')
                          : (l?.aiBriefingWriteAgain ?? 'Write it again'),
                      icon: LucideIcons.refreshCw,
                      color: kCoachAccent,
                      soft: true,
                      onTap: _busy ? null : _generate,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: S.x3),
                    StatusCard(
                      l?.aiBriefingFailedTitle ?? 'That did not go through',
                      coachPresentationText(l, _error!),
                      icon: LucideIcons.triangleAlert,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

