// AI settings → Memory: what the person asked the AI to remember, each with
// its own delete, and a way to clear them all.

import 'package:flutter/material.dart';

import '../../coach/coach_memory.dart';
import '../profile/profile.dart' show moreCard;
import '../ui2.dart';
import 'home_screen.dart' show pad;

class CoachMemoryScreen extends StatefulWidget {
  const CoachMemoryScreen({super.key});

  @override
  State<CoachMemoryScreen> createState() => _CoachMemoryScreenState();
}

class _CoachMemoryScreenState extends State<CoachMemoryScreen> {
  List<String>? _notes;

  @override
  void initState() {
    super.initState();
    CoachMemory.changed.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    CoachMemory.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final n = await CoachMemory.all();
    if (mounted) setState(() => _notes = n);
  }

  Future<void> _clear() async {
    final ok = await AppDialog.show(
      context,
      title: 'Forget everything?',
      body: 'The AI loses every note on this list. Your data is not touched.',
      destructive: 'Forget all',
      secondary: 'Cancel',
    );
    if (ok == DialogChoice.destructive) await CoachMemory.clear();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final notes = _notes;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Memory'),
          ),
          Expanded(
            child: ListView(padding: pad, children: [
              Text(
                'Ask the AI to remember something ("don\'t use emojis", "I '
                'train for a half marathon") and it keeps a note here. Every '
                'chat and every outlook follows them. The notes stay on this '
                'phone and go to your model with each request.',
                style: F.cap.copyWith(color: p.ink3, height: 1.5),
              ),
              const SizedBox(height: S.x4),
              if (notes == null)
                const SizedBox.shrink()
              else if (notes.isEmpty)
                const StatusCard(
                  'Nothing remembered yet',
                  'Tell the AI what to keep in mind and it shows up here.',
                  icon: LucideIcons.brain,
                )
              else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
                  decoration: moreCard(p),
                  child: Column(children: [
                    for (var i = 0; i < notes.length; i++) ...[
                      if (i > 0) Divider(height: S.hair, color: p.line),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: S.x12),
                        child: Row(children: [
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: S.x3),
                              child: Text(notes[i],
                                  style: F.body
                                      .copyWith(color: p.ink, height: 1.4)),
                            ),
                          ),
                          Pressable(
                            onTap: () => CoachMemory.removeAt(i),
                            semanticLabel: 'Forget "${notes[i]}"',
                            child: SizedBox.square(
                              dimension: S.tap,
                              child: Icon(LucideIcons.x,
                                  size: I.sm, color: p.ink3),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: S.x4),
                BigButton('Forget all', soft: true, onTap: _clear),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
