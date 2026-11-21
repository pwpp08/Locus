// AI settings → Memory: what the coach knows about the person. Laid out on
// the reference memory page (measured at 3 px to the dp): a close bar, a two
// line headline with the person's mark beside it, a card to add a note, doors
// to the chat history and a summary, then tabs over the notes as cards.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../coach/coach_memory.dart';
import '../ui2.dart';
import 'journal_compose.dart' show OsTextField;
import 'coach_history_sheet.dart';

class CoachMemoryScreen extends StatefulWidget {
  /// Whose chats the history door lists; null hides that door.
  final String? storageKey;

  /// Asks the coach to sum up what it knows; null hides that door.
  final VoidCallback? onSnapshot;

  /// Opens a past chat in the coach.
  final ValueChanged<String>? onOpenChat;

  /// What the coach is sent; null hides that door.
  final VoidCallback? onSent;

  const CoachMemoryScreen({
    super.key,
    this.storageKey,
    this.onSnapshot,
    this.onOpenChat,
    this.onSent,
  });

  @override
  State<CoachMemoryScreen> createState() => _CoachMemoryScreenState();
}

/// The tabs, in the reference's order: everything by date, then by kind.
enum _Tab { timeline, preference, goal, about }

extension on _Tab {
  String get label => switch (this) {
        _Tab.timeline => 'Timeline',
        _Tab.preference => 'Coaching preferences',
        _Tab.goal => 'Goals',
        _Tab.about => 'About you',
      };

  bool shows(MemoryNote n) => switch (this) {
        _Tab.timeline => true,
        _Tab.preference => n.kind == MemoryKind.preference,
        _Tab.goal => n.kind == MemoryKind.goal,
        _Tab.about => n.kind == MemoryKind.about,
      };
}

class _CoachMemoryScreenState extends State<CoachMemoryScreen> {
  List<MemoryNote>? _notes;
  _Tab _tab = _Tab.timeline;

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
    final n = await CoachMemory.notes();
    if (mounted) setState(() => _notes = n);
  }

  Future<void> _write() async {
    final kept = await showMemoryNoteSheet(context);
    if (kept != null && mounted) {
      setState(() => _tab = _Tab.timeline);
    }
  }

  Future<void> _open(MemoryNote n) async {
    final p = P.of(context);
    await AppSheet.show<void>(
      context,
      title: n.kind.label,
      child: Builder(
        builder: (sheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(n.text, style: F.body.copyWith(color: p.ink, height: 1.45)),
            if (n.at > 0) ...[
              const SizedBox(height: S.x3),
              Text(_kept(n.at), style: F.cap.copyWith(color: MEM.violet)),
            ],
            const SizedBox(height: S.x5),
            BigButton('Forget this', soft: true, compact: true, onTap: () {
              Navigator.of(sheet).pop();
              CoachMemory.remove(n);
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _clear() async {
    final ok = await AppDialog.show(
      context,
      title: 'Forget everything?',
      body: 'The AI loses every note on this page. Your data is not touched.',
      destructive: 'Forget all',
      secondary: 'Cancel',
    );
    if (ok == DialogChoice.destructive) await CoachMemory.clear();
  }

  void _history() => openCoachHistory(context,
      storageKey: widget.storageKey!, onOpen: widget.onOpenChat);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _kept(int at) {
    final d = DateTime.fromMillisecondsSinceEpoch(at);
    return 'Kept on ${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final all = _notes;
    final shown = all == null
        ? const <MemoryNote>[]
        : (all.where(_tab.shows).toList()
          ..sort((a, b) => b.at.compareTo(a.at)));
    return Scaffold(
      backgroundColor: DS.foot,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: DS.page,
            stops: DS.pageStops,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            _topBar(c, p),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(S.x4, S.x6, S.x4,
                    MediaQuery.viewPaddingOf(c).bottom + S.x6),
                children: [
                  _hero(p),
                  const SizedBox(height: S.x6 + S.x1),
                  _share(p),
                  const SizedBox(height: S.x8),
                  for (final (icon, title, tap) in [
                    if (widget.storageKey != null)
                      (LucideIcons.history, 'Chat history', _history),
                    if (widget.onSnapshot case final f?)
                      (LucideIcons.lightbulb, 'What it knows about you', f),
                    if (widget.onSent case final f?)
                      (LucideIcons.fileText, 'What leaves the phone', f),
                  ]) ...[
                    _Door(icon, title, onTap: tap),
                    const SizedBox(height: S.x2),
                  ],
                  const SizedBox(height: S.x4),
                  _tabs(),
                  const SizedBox(height: S.x4),
                  if (all != null && shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.x6),
                      child: Text(
                        _tab == _Tab.timeline
                            ? 'Nothing kept yet. Tell the AI about your goals '
                                'and how you like to be coached, in a chat or '
                                'with Write above, and it shows up here.'
                            : 'Nothing kept under ${_tab.label.toLowerCase()} '
                                'yet.',
                        textAlign: TextAlign.center,
                        style: F.cap.copyWith(color: MEM.sub, height: 1.5),
                      ),
                    ),
                  for (final n in shown) ...[
                    _NoteCard(n, kept: _kept(n.at), onTap: () => _open(n)),
                    const SizedBox(height: S.x4),
                  ],
                  if (all != null && all.isNotEmpty) ...[
                    const SizedBox(height: S.x2),
                    BigButton('Forget all', soft: true, compact: true,
                        onTap: _clear),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext c, P p) => SizedBox(
        height: S.x12 + S.x2,
        child: Row(children: [
          const SizedBox(width: S.x2),
          Pressable(
            semanticLabel: 'Back',
            onTap: () => Navigator.of(c).maybePop(),
            child: SizedBox.square(
              dimension: S.tap + S.x2,
              child: Icon(LucideIcons.chevronLeft,
                  size: I.xl + S.x2, color: p.ink),
            ),
          ),
          Expanded(
            child: Text('MY MEMORY',
                textAlign: TextAlign.center,
                style: F.cap.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
          ),
          const SizedBox.square(dimension: S.tap + S.x4),
        ]),
      );

  Widget _hero(P p) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Teach your coach who you are.',
                    style: MEM.headline.copyWith(color: p.ink)),
                const SizedBox(height: S.x2),
                Text('The more it knows, the better its advice fits.',
                    style: MEM.lede.copyWith(color: MEM.sub)),
              ],
            ),
          ),
          const SizedBox(width: S.x4),
          const _Mark(),
          const SizedBox(width: S.x4),
        ],
      );

  Widget _share(P p) => Container(
        padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x4),
        decoration: BoxDecoration(
          borderRadius: R.rXxl,
          border: Border.all(color: MEM.shareEdge, width: S.hair),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [MEM.shareA, MEM.shareB],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(LucideIcons.sparkles, size: I.md, color: MEM.violet),
              const SizedBox(width: S.x3),
              Text('Tell it something new',
                  style: MEM.row.copyWith(
                      color: p.ink, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: S.x3),
            Pressable(
              onTap: _write,
              semanticLabel: 'Write a note for the AI',
              child: Container(
                height: S.x10,
                decoration: BoxDecoration(
                  color: MEM.button,
                  borderRadius: R.rLg,
                  border: Border.all(color: MEM.buttonEdge, width: S.hair),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.pencil, size: I.sm, color: p.ink),
                    const SizedBox(width: S.x3),
                    Text('WRITE',
                        style: F.cap.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _tabs() => SizedBox(
        height: S.x8 + S.half,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _Tab.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: S.x3),
          itemBuilder: (_, i) {
            final t = _Tab.values[i];
            final on = t == _tab;
            return Pressable(
              onTap: () => setState(() => _tab = t),
              semanticLabel: t.label,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: S.x3),
                decoration: BoxDecoration(
                  color: on ? MEM.tabOn : MEM.tabOff,
                  borderRadius: R.rLg,
                ),
                child: Text(t.label,
                    style: F.body.copyWith(
                        color: on ? MEM.tabOnInk : C.white,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -.1)),
              ),
            );
          },
        ),
      );
}

/// The person's mark beside the headline: a grey puck seen a little from
/// above, its face sunk into a well lit violet over the top and blue down the
/// right, a head and shoulders standing in the well.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext c) => const ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(S.x12 + S.x1),
          painter: _MarkPainter(),
        ),
      );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width;
    Offset at(double x, double y) => Offset(x * u, y * u);

    // The edge: the face pushed down and right, joined to it.
    final face = at(.457, .457), back = at(.543, .543), r = .457 * u;
    final sideShader = LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: const [MEM.markSideA, MEM.markSideB],
    ).createShader(Offset.zero & size);
    canvas.drawLine(
        face,
        back,
        Paint()
          ..shader = sideShader
          ..strokeWidth = 2 * r
          ..strokeCap = StrokeCap.round);

    // The face.
    canvas.drawCircle(
        face,
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [MEM.markFaceA, MEM.markFaceB],
          ).createShader(Rect.fromCircle(center: face, radius: r)));

    // The well, and everything in it clipped to it.
    final well = at(.457, .479), wr = .368 * u;
    final wellRect = Rect.fromCircle(center: well, radius: wr);
    canvas.drawCircle(
        well,
        wr,
        Paint()
          ..shader = const LinearGradient(
            colors: [MEM.markWellA, MEM.markWellB],
          ).createShader(wellRect));

    // The two lights, each fading in and out along its arc.
    void light(Color col, double from, double sweep) {
      final rad = math.pi / 180;
      canvas.drawArc(
          wellRect.deflate(.012 * u),
          from * rad,
          sweep * rad,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .024 * u
            ..strokeCap = StrokeCap.round
            // Turned to the arc's start, so an arc through 0° keeps its fade.
            ..shader = SweepGradient(
              endAngle: sweep * rad,
              colors: [col.withValues(alpha: 0), col, col, col.withValues(alpha: 0)],
              stops: const [0, .15, .85, 1],
              transform: GradientRotation(from * rad),
            ).createShader(wellRect));
    }

    light(MEM.markViolet, 130, 175);
    light(MEM.markBlue, 315, 140);

    canvas.save();
    canvas.clipPath(Path()..addOval(wellRect));
    final fig = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [MEM.markFigA, MEM.markFigB],
      ).createShader(Offset.zero & size);
    final shade = Paint()..color = MEM.markFigShade;
    final head = RRect.fromRectAndRadius(
        Rect.fromLTWH(.315 * u, .265 * u, .264 * u, .291 * u),
        Radius.circular(.105 * u));
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(.145 * u, .612 * u, .562 * u, .45 * u),
        Radius.circular(.085 * u));
    final lift = at(.018, .018);
    canvas
      ..drawRRect(head.shift(lift), shade)
      ..drawRRect(body.shift(lift), shade)
      ..drawRRect(head, fig)
      ..drawRRect(body, fig)
      ..restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}

/// A door off the memory page: a glyph, its name, a violet arrow.
class _Door extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _Door(this.icon, this.title, {required this.onTap});

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        semanticLabel: title,
        child: Container(
          height: S.x12 + S.x2,
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          decoration: const BoxDecoration(
            borderRadius: R.rXl,
            gradient: LinearGradient(colors: [MEM.rowA, MEM.rowB]),
          ),
          child: Row(children: [
            Icon(icon, size: I.lg, color: C.white),
            const SizedBox(width: S.x3),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MEM.row.copyWith(
                      color: C.white, fontWeight: FontWeight.w500)),
            ),
            const Icon(LucideIcons.arrowRight, size: I.md, color: MEM.violet),
          ]),
        ),
      );
}

/// One kept note: its words, its kind as a chip, and the day it was kept.
class _NoteCard extends StatelessWidget {
  final MemoryNote note;
  final String kept;
  final VoidCallback onTap;
  const _NoteCard(this.note, {required this.kept, required this.onTap});

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        semanticLabel: note.text,
        child: Container(
          padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x4, S.x5),
          decoration: const BoxDecoration(
            borderRadius: R.rXxl,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [MEM.rowA, MEM.rowB],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(note.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: MEM.row.copyWith(
                          color: C.white,
                          fontWeight: FontWeight.w500,
                          height: 1.4)),
                ),
                const SizedBox(width: S.x3),
                const Icon(LucideIcons.chevronRight,
                    size: I.md, color: MEM.sub),
              ]),
              const SizedBox(height: S.x3),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: S.x2 + S.half, vertical: S.half),
                decoration: BoxDecoration(
                  borderRadius: R.rMd,
                  border: Border.all(color: MEM.chipEdge, width: S.hair),
                ),
                child: Text(note.kind.label,
                    style: MEM.chip.copyWith(color: MEM.chipInk)),
              ),
              if (note.at > 0) ...[
                const SizedBox(height: S.x3),
                Row(children: [
                  Container(
                    width: S.x2,
                    height: S.x2,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: MEM.violet),
                  ),
                  const SizedBox(width: S.x2),
                  Text(kept,
                      style: MEM.date.copyWith(color: MEM.violet)),
                ]),
              ],
            ],
          ),
        ),
      );
}

/// A sheet to write a note for the AI and say what kind it is. Returns the
/// note kept, or null when it was dismissed or empty.
Future<String?> showMemoryNoteSheet(BuildContext context) {
  final text = TextEditingController();
  var kind = MemoryKind.goal;
  return AppSheet.show<String>(
    context,
    title: 'Tell it something new',
    child: StatefulBuilder(
      builder: (sheet, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RangeSegments(
            [for (final k in MemoryKind.values) k.label],
            kind.index,
            (i) => set(() => kind = MemoryKind.values[i]),
          ),
          const SizedBox(height: S.x4),
          OsTextField(
            controller: text,
            label: 'What should it know?',
            hint: switch (kind) {
              MemoryKind.goal => 'I want to run a half marathon in April',
              MemoryKind.preference => 'Keep answers short, with the numbers',
              MemoryKind.about => 'I work night shifts on weekends',
            },
            lines: 3,
          ),
          const SizedBox(height: S.x4),
          BigButton('Keep it', compact: true, onTap: () async {
            final kept = await CoachMemory.add(text.text, kind: kind);
            if (sheet.mounted) Navigator.of(sheet).pop(kept);
          }),
        ],
      ),
    ),
  );
}
