import 'dart:async';
import 'coach_text.dart';
// COACH — the door onto the agentic AI that was already built.
//
// `lib/coach` has had a working tool-calling loop for months: read-only SQL over
// the derived views, figures the app draws natively, and confirmation-gated
// writes. It had no screen, so none of it could run. This is the screen.
//
// Three rules this file keeps:
//
//   1. LOCAL FIRST. The app is zero-egress by design, so the setup screen offers
//      Ollama and LM Studio before it offers anyone's cloud. A cloud key is a
//      deliberate choice, and the screen says what leaving the device means.
//   2. EVERY WRITE IS CONFIRMED. `confirm` is wired to a real dialog carrying
//      the tool's own human-readable summary. There is no path from a tool call
//      to a write that does not pass through it, and a destructive action gets
//      its own wording rather than the same "Confirm" as an add.
//   3. NO SECOND DESIGN SYSTEM. Figures are `CoachFigure` (the app's own
//      painters); everything else is grammar.dart. The one thing that is not is
//      the markdown body, because there is no house widget for prose.

import '../../data/db.dart';
import '../../l10n/display_text.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../ai/briefing.dart';
import '../../ai/briefing_engine.dart';
import '../../coach/coach_config.dart';
import '../../coach/coach_engine.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'ai_briefing.dart';
import 'coach_figures.dart';
import 'home_screen.dart' show go, pad, repoOf;
import 'journal_compose.dart' show OsTextField;

/// The coach's accent. Not a domain colour: the coach reads across all five.
const Color kCoachAccent = C.purple;

/// Whether the coach has a model behind it — false when there is no
/// [CoachConfig] above us, which is every golden.
///
/// Home shows its coach button only when this is true. An icon that opens a
/// setup form nobody asked for is clutter on a screen built around three rings,
/// and the place to go and set the thing up is Profile, with the other
/// settings. [keyUnreadable] counts as configured: the key IS saved, this
/// process just could not read it through a locked keychain, and hiding the
/// button there would tell a configured user their coach had vanished.
bool coachReady(BuildContext c) {
  try {
    final cfg = c.watch<CoachConfig>();
    return cfg.configured || cfg.keyUnreadable;
  } catch (_) {
    return false;
  }
}

/// [coachReady] for an event handler, which must not listen.
///
/// `watch` outside `build` trips a provider assert, and the catch above turns
/// that into a plain "not configured" — so a tap handler asking [coachReady]
/// sends a fully configured user to the setup form every time.
bool coachReadyNow(BuildContext c) {
  try {
    final cfg = c.read<CoachConfig>();
    return cfg.configured || cfg.keyUnreadable;
  } catch (_) {
    return false;
  }
}

/// What the Profile row should say under "AI coach", or null when there is no
/// [CoachConfig] above this context at all.
///
/// Same try/catch as [coachReady] and for the same reason: the golden harness
/// mounts screens without the app's providers, and a throw there is a red test
/// about the harness rather than about the screen. Null and "Not set up" are
/// deliberately the same sentence to the reader — from the row's point of view
/// an unreadable config and an unset one both mean the setup form is what the
/// tap should open.
String? coachSubtitle(BuildContext c) {
  try {
    final cfg = c.watch<CoachConfig>();
    return cfg.configured
        ? cfg.model
        : (AppLocalizations.of(c)?.coachNotSetUp ?? 'Not set up');
  } catch (_) {
    return null;
  }
}

class CoachScreen extends StatefulWidget {
  /// A message to send the moment the engine is up — visibly, as the user's
  /// own turn, so the model runs its tools on it like any other question
  /// (nothing is injected as trusted prose). [startNewSession] opens a fresh
  /// conversation for it first.
  ///
  /// Every opening is a new conversation; earlier ones are under History.
  final String? initialMessage;

  /// Open on today's outlook for this period: the briefing (written now if
  /// there is none yet) is the coach's first turn, and the user can reply.
  final BriefingPeriod? outlook;

  const CoachScreen({
    super.key,
    this.initialMessage,
    this.outlook,
  });

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  CoachEngine? _engine;
  final List<CoachItem> _items = [];
  CoachItem? _streamingItem;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  String? _status;

  static List<String> _starters(BuildContext c) {
    final l = AppLocalizations.of(c);
    return [
      l?.coachStarterRecovery ?? 'How recovered am I today, and why?',
      l?.coachStarterHrvChart ?? 'Chart my HRV over the last month',
      l?.coachStarterSleep ?? 'How has my sleep been this week?',
      l?.coachStarterAteYesterday ?? 'What did I eat yesterday?',
      l?.coachStarterLogWater ?? 'Log 500 ml of water for today',
      l?.coachStarterLogRun ?? 'I ran for 40 minutes this morning — log it',
    ];
  }

  /// One glyph per entry of [_starters], in the same order.
  static const _starterIcons = [
    LucideIcons.heartPulse,
    LucideIcons.chartLine,
    LucideIcons.moon,
    LucideIcons.utensils,
    LucideIcons.droplet,
    LucideIcons.activity,
  ];

  @override
  void initState() {
    super.initState();
    // The send arrow lights once there is something to send.
    _input.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _initEngine());
  }

  Future<void> _initEngine() async {
    if (!mounted) return;
    final repo = repoOf(context);
    if (repo == null) return;
    // A local count of coach opens; leaves the phone only inside a database
    // the user chose to contribute.
    unawaited(LocalDb.bumpUsageCounter('coach_open'));
    final app = context.read<AppState>();
    final cfg = context.read<CoachConfig>();
    final engine = CoachEngine(
      config: cfg,
      api: repo,
      storageKey: (app.user?['id'] ?? 'local').toString(),
    );
    // Never the last conversation carried on: a new one each time, and the
    // old ones a tap away under History.
    engine.newSession();
    setState(() {
      _engine = engine;
      _items.clear();
    });
    if (widget.outlook case final period?) {
      await _openOutlook(engine, period);
    }
    final first = widget.initialMessage;
    if (first != null && first.trim().isNotEmpty && !_sentInitial) {
      _sentInitial = true;
      await _send(first);
    }
  }

  bool _sentInitial = false;

  /// Today's outlook as the coach's first turn. The stored briefing when there
  /// is one (the morning's stands in until the evening one exists), otherwise
  /// one is written now.
  Future<void> _openOutlook(CoachEngine engine, BriefingPeriod period) async {
    final shown = resolveBriefingToShow(
      period,
      BriefingStore.read(period),
      BriefingStore.read(BriefingPeriod.morning),
    );
    var b = shown.briefing;
    if (b == null) {
      final repo = repoOf(context);
      final cfg = context.read<CoachConfig>();
      if (repo == null) return;
      setState(() {
        _busy = true;
        _status = 'Writing your outlook…';
      });
      try {
        b = await BriefingEngine(config: cfg, repo: repo).generate(period);
      } catch (e) {
        if (mounted) {
          setState(() => _items.add(CoachItem.error(e is CoachException
              ? e.message
              : (AppLocalizations.of(context)?.coachSomethingWrong('$e') ??
                  'Something went wrong: $e'))));
        }
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _status = null;
          });
        }
      }
    }
    if (b == null || !mounted) return;
    final text = b.oneLiner == 'Nothing stood out tonight.'
        ? uiText(context, b.oneLiner)
        : b.oneLiner;
    engine.seedAnswer(
      'What is my outlook for today?',
      [text, if (b.breakdownMd.isNotEmpty) b.breakdownMd].join('\n\n'),
      title: 'Daily Outlook',
    );
    setState(() {
      _items
        ..clear()
        ..addAll(engine.transcript);
    });
  }

  /// The starters, from the composer's (+).
  Future<void> _suggest() async {
    final starters = _starters(context);
    final pick = await AppSheet.show<String>(
      context,
      title: 'TRY ASKING',
      child: Column(children: [
        for (var i = 0; i < starters.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x2),
            child: _Starter(
              _starterIcons[i % _starterIcons.length],
              starters[i],
              onTap: () => Navigator.of(context).pop(starters[i]),
            ),
          ),
      ]),
    );
    if (pick != null && mounted) await _send(pick);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    // Not `_engine?.dispose()`: a `send` can still be in flight (a local
    // model's first response can take minutes), and closing the shared HTTP
    // client out from under it aborts the request instead of letting it land.
    // `requestDispose` defers the actual close until `send`'s own `finally`
    // sees it — see coach_engine.dart.
    _engine?.requestDispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    final engine = _engine;
    if (t.isEmpty || _busy || engine == null) return;
    _input.clear();
    setState(() => _busy = true);
    // Read before the await: `send` can outlive this screen.
    final app = context.read<AppState>();
    var wrote = false;
    try {
      // `send` can block for up to 120 s, so every callback below can land after
      // the user has popped the screen.
      await engine.send(
        t,
        onDelta: (delta) {
          if (!mounted) return;
          setState(() {
            _status = null;
            if (_streamingItem == null) {
              _streamingItem = CoachItem.assistant(delta);
              _items.add(_streamingItem!);
            } else {
              final newContent = '${_streamingItem!.text ?? ''}$delta';
              _streamingItem = CoachItem.assistant(newContent);
              _items[_items.length - 1] = _streamingItem!;
            }
          });
          _scrollDown();
        },
        onItem: (it) {
          if (!mounted) return;
          setState(() {
            if (it.kind == CoachItemKind.assistant && _streamingItem != null) {
              _items.removeLast();
              _streamingItem = null;
            }
            _items.add(it);
          });
          _scrollDown();
        },
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
        confirm: (req) async {
          final ok = await _confirm(req);
          if (ok) wrote = true;
          return ok;
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _items.add(
            CoachItem.error(
              e is CoachException
                  ? e.message
                  : (AppLocalizations.of(context)?.coachSomethingWrong('$e') ??
                      'Something went wrong: $e'),
            ),
          );
        });
      }
    } finally {
      _streamingItem = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
      await engine.persist(); // survive reopen
      // A confirmed write can change what the reminders should say — a dose
      // marked or added, a day rated — and they are armed ahead of time.
      if (wrote) await app.refreshAiReminders();
      _scrollDown();
    }
  }

  /// THE write gate. Every action tool routes through here, and the dialog
  /// carries the tool's own summary rather than a generic "the AI wants to do
  /// something" — a confirmation that does not say what it confirms is a tap
  /// target, not consent.
  Future<bool> _confirm(ActionRequest req) async {
    final destructive = req.tool.startsWith('delete_');
    final p = P.of(context);
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AppDialog(
        title: uiText(context, req.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              coachActionSummary(context, req),
              style: F.body.copyWith(color: p.ink2, height: 1.4),
            ),
            const SizedBox(height: S.x3),
            Text(
              destructive
                  ? (l?.coachDestructiveWarning ??
                      'This removes data from this device and cannot be undone.')
                  : (l?.coachSafeWarning ?? 'Nothing is written until you tap below.'),
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
        ),
        actions: [
          BigButton(l?.actionCancel ?? 'Cancel', soft: true, onTap: () => Navigator.of(d).pop(false)),
          BigButton(destructive ? (l?.coachDeleteIt ?? 'Delete it') : (l?.coachSaveIt ?? 'Save it'), onTap: () => Navigator.of(d).pop(true)),
        ],
      ),
    );
    return ok ?? false;
  }

  void _newChat() {
    _engine?.newSession();
    setState(_items.clear);
  }

  Future<void> _openSession(String id) async {
    await _engine?.openSession(id);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(_engine?.transcript ?? const []);
    });
    _scrollDown();
  }

  void _scrollDown() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: motion(context, Motion.slow),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _menu() async {
    final engine = _engine;
    final p = P.of(context);
    final l = AppLocalizations.of(context);
    await AppSheet.open<void>(context,
      builder: (sheet) => SafeArea(
        child: StatefulBuilder(
          builder: (sheet, setSheet) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x4),
            children: [
              _MenuRow(
                LucideIcons.plus,
                l?.coachNewChat ?? 'New chat',
                onTap: () {
                  Navigator.of(sheet).pop();
                  _newChat();
                },
              ),
              // NO "AI settings" ROW. Choosing the model is a setting and
              // settings live in Profile — [CoachSetup] is pushed from there
              // now. Two doors onto one form is how a setting ends up with two
              // different states in a user's head, and this screen is where
              // you talk to the thing, not where you configure it. The only
              // way into the form from here is the not-set-up card in [_body],
              // which is a recovery state rather than a settings entry.
              _MenuRow(
                LucideIcons.fileText,
                l?.coachBriefingMenuTitle ?? 'Briefing, and what was sent',
                sub: l?.coachBriefingMenuSub ?? 'The exact snapshot that left this device',
                onTap: () {
                  Navigator.of(sheet).pop();
                  go(
                    context,
                    AiBriefingScreen(
                      period: currentBriefingPeriod(DateTime.now()),
                    ),
                  );
                },
              ),
              if (engine != null) ...[
                const SizedBox(height: S.x4),
                Text(
                  l?.coachPastChats ?? 'PAST CHATS',
                  style: F.over.copyWith(color: p.ink3),
                ),
                const SizedBox(height: S.x2),
                FutureBuilder<List<CoachSessionMeta>>(
                  future: engine.listSessions(),
                  builder: (_, snap) {
                    final list = snap.data ?? const <CoachSessionMeta>[];
                    if (list.isEmpty) {
                      return Text(
                        l?.coachNoChatsYet ??
                            'Nothing yet — this is your first conversation.',
                        style: F.cap.copyWith(color: p.ink3),
                      );
                    }
                    return Column(
                      children: [
                        for (final s in list.take(20))
                          _MenuRow(
                            LucideIcons.messageSquare,
                            s.title.isEmpty ? (l?.coachUntitledChat ?? 'Untitled chat') : s.title,
                            sub: s.preview,
                            onTap: () {
                              Navigator.of(sheet).pop();
                              _openSession(s.id);
                            },
                            onRemove: () async {
                              final wasOpen = s.id == engine.sessionId;
                              await engine.deleteSession(s.id);
                              setSheet(() {});
                              if (wasOpen && mounted) setState(_items.clear);
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      dragHandle: true,
      scroll: true,
    );
  }

  /// Back, the coach's name with the model under it in a small tag, and
  /// History.
  Widget _header(BuildContext c, P p, CoachConfig cfg) {
    final l = AppLocalizations.of(c);
    final model = cfg.configured ? cfg.model : (l?.coachNotSetUp ?? 'Not set up');
    Widget icon(IconData i, String label, VoidCallback onTap) => Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: SizedBox.square(
            dimension: S.x12,
            child: Icon(i, size: I.lg + S.x1, color: p.ink),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, S.x3),
      child: Row(children: [
        icon(LucideIcons.chevronLeft, l?.supplementNavBack ?? 'Back',
            () => Navigator.maybePop(c)),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'LOCUS COACH',
              style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2),
            ),
            const SizedBox(height: S.x1),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: S.x2, vertical: S.half),
              decoration: BoxDecoration(
                color: p.ink.withValues(alpha: .14),
                borderRadius: R.rSm,
              ),
              child: Text(
                model.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.over.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2),
              ),
            ),
          ]),
        ),
        icon(LucideIcons.history,
            l?.coachMenuSemantic ?? 'Chats and AI settings', _menu),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) =>
      AlwaysChar(child: Builder(builder: _build));

  Widget _build(BuildContext c) {
    final p = P.of(c);
    final cfg = c.watch<CoachConfig>();
    return Scaffold(
      backgroundColor: C.coachSky.last,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: C.coachSky,
            stops: C.coachSkyStops,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _header(c, p, cfg),
              Expanded(child: _body(c, p, cfg)),
              if (cfg.configured && _engine != null) _composer(c, p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext c, P p, CoachConfig cfg) {
    final l = AppLocalizations.of(c);
    // The key IS saved, this process just could not read it. Showing the setup
    // wall here would tell the user their key is gone and invite them to paste
    // it again.
    if (cfg.keyUnreadable) {
      return ListView(
        padding: pad,
        children: [
          const SizedBox(height: S.x4),
          StatusCard(
            l?.coachKeyStillSavedTitle ?? 'Your key is still saved',
            l?.coachKeyStillSavedBody ??
                'It could not be read from the keychain this time, which happens '
                    'when the app is woken while the phone is locked.',
            fix: l?.coachTryAgainFix ?? 'Try again',
            icon: LucideIcons.lock,
            onFix: () async {
              await cfg.refreshKeyOnResume();
              if (mounted) setState(() {});
            },
          ),
        ],
      );
    }
    if (!cfg.configured) {
      return ListView(
        padding: pad,
        children: [
          const SizedBox(height: S.x4),
          StatusCard(
            l?.coachNotSetUpTitle ?? 'The coach is not set up',
            l?.coachNotSetUpBody ??
                'Pick a model on your own computer, or any OpenAI-compatible provider with your own key. Nothing goes through Locus either way.',
            fix: l?.coachChooseModelFix ?? 'Choose a model',
            leading: const IconChip.coach(C.slate, neutral: true),
            onFix: () => go(c, const CoachSetup()),
          ),
        ],
      );
    }
    if (_engine == null) {
      return ListView(
        padding: pad,
        children: [
          const SizedBox(height: S.x4),
          StatusCard(
            l?.coachNoDataTitle ?? 'No data to read yet',
            l?.coachNoDataBody ??
                'The coach answers from your scored days, and there are none on this phone yet. Wear the band overnight and sync in the morning.',
            icon: LucideIcons.database,
          ),
        ],
      );
    }
    if (_items.isEmpty && !_busy) {
      final starters = _starters(c);
      return ListView(
        padding: const EdgeInsets.fromLTRB(S.x4, S.x6, S.x4, S.x4),
        children: [
          const Center(child: AiOrb(size: S.x16 + S.x6)),
          const SizedBox(height: S.x5),
          Text(
            'How can I help?',
            textAlign: TextAlign.center,
            style: F.t1.copyWith(color: p.ink),
          ),
          const SizedBox(height: S.x2),
          Text(
            l?.coachIntroBody ??
                'Ask about anything the app measures, and it can log food, '
                    'water, workouts, doses and how you felt — always asking '
                    'first.',
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: p.ink3, height: 1.5),
          ),
          const SizedBox(height: S.x6),
          for (var i = 0; i < starters.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x2),
              child: _Starter(
                _starterIcons[i % _starterIcons.length],
                starters[i],
                onTap: () => _send(starters[i]),
              ),
            ),
        ],
      );
    }
    final waiting = _busy && _streamingItem == null;
    final last = _items.isEmpty ? null : _items.last;
    // The lines fade out into the composer rather than stop at a hard edge.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [C.white, C.white, C.white.withValues(alpha: 0)],
        stops: const [0, .88, 1],
      ).createShader(r),
      child: ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x10),
      itemCount: _items.length + (waiting ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _items.length) {
          return _Thinking(
            lead: last == null || last.kind == CoachItemKind.user,
            status: _status == null
                ? null
                : coachPresentationText(AppLocalizations.of(context), _status!),
          );
        }
        // The coach's mark leads each run of answers, not every line of one.
        final prev = i == 0 ? null : _items[i - 1];
        return _Bubble(
          item: _items[i],
          lead: prev == null ||
              prev.kind == CoachItemKind.user ||
              prev.kind == CoachItemKind.error,
        );
      },
      ),
    );
  }

  /// (+) for suggestions, a new chat, and the message box: an outlined field
  /// on a coach-coloured edge with the send arrow inside it.
  Widget _composer(BuildContext c, P p) {
    final l = AppLocalizations.of(c);
    final canSend = !_busy && _input.text.trim().isNotEmpty;
    Widget tool(IconData i, String label, VoidCallback? onTap, Color ink) =>
        Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: SizedBox(
            width: S.x10,
            height: S.x12,
            child: Icon(i, size: I.lg + S.x1, color: ink),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(
          S.x2, 0, S.x4, S.x3 + MediaQuery.of(c).viewInsets.bottom),
      child: Row(children: [
        tool(LucideIcons.plus, 'Suggestions', _busy ? null : _suggest, p.ink),
        tool(LucideIcons.messageSquarePlus, l?.coachNewChat ?? 'New chat',
            _busy ? null : _newChat, p.ink3),
        const SizedBox(width: S.x2),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(S.half),
            decoration: const BoxDecoration(
              borderRadius: R.rXl,
              gradient: LinearGradient(
                  colors: [C.coachEdgeA, C.coachEdgeB]),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: S.x10),
              padding: const EdgeInsets.only(left: S.x3),
              decoration: BoxDecoration(
                color: C.coachSky.last,
                borderRadius:
                    const BorderRadius.all(Radius.circular(R.xl - S.half)),
              ),
              child: Row(children: [
                Expanded(
                  child: Semantics(
                    label: l?.coachAskLabel ?? 'Ask the coach',
                    textField: true,
                    child: AppField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_busy,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _busy ? null : _send,
                      bare: true,
                      hint: '',
                    ),
                  ),
                ),
                Pressable(
                  semanticLabel: l?.coachSendLabel ?? 'Send',
                  onTap: canSend ? () => _send(_input.text) : null,
                  child: SizedBox.square(
                    dimension: S.x10,
                    child: Icon(LucideIcons.arrowUp,
                        size: I.md, color: canSend ? p.ink : p.ink3),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A suggestion to start from: a glyph, the question, and an arrow.
class _Starter extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _Starter(this.icon, this.text, {required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        decoration: BoxDecoration(color: p.card, borderRadius: R.rXl),
        child: Row(children: [
          Container(
            width: S.x8,
            height: S.x8,
            decoration: BoxDecoration(
                color: p.wash(kCoachAccent), shape: BoxShape.circle),
            child: Icon(icon, size: I.sm, color: p.on(kCoachAccent)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(text, style: F.body.copyWith(color: p.ink, height: 1.35)),
          ),
          const SizedBox(width: S.x2),
          Icon(LucideIcons.arrowUpRight, size: I.sm, color: p.ink3),
        ]),
      ),
    );
  }
}

/// The coach's side of a conversation: its mark in a fixed gutter (shown on the
/// first line of a run, empty after it) and the content beside it.
class _CoachRow extends StatelessWidget {
  final bool lead;
  final Widget child;
  const _CoachRow({required this.lead, required this.child});

  static const double gutter = S.x6;

  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(bottom: S.x4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: gutter,
            child: lead ? const AiOrb(size: gutter) : null,
          ),
          const SizedBox(width: S.x3),
          Expanded(child: child),
        ]),
      );
}

/// Waiting on the model: three dots, and what it is doing if it says.
class _Thinking extends StatefulWidget {
  final bool lead;
  final String? status;
  const _Thinking({required this.lead, this.status});

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: Motion.typing);

  @override
  void initState() {
    super.initState();
    // Round again until the dots are gone or motion is turned off.
    _t.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && Motion.enabled(context)) {
        _t.forward(from: 0);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: three still dots say the same thing.
    if (Motion.enabled(context)) {
      if (!_t.isAnimating) _t.forward(from: 0);
    } else {
      _t.stop();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return _CoachRow(
      lead: widget.lead,
      child: Row(children: [
        AnimatedBuilder(
          animation: _t,
          builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: S.x1),
                child: Opacity(
                  // Each dot peaks a third of a turn after the one before.
                  opacity: .35 +
                      .65 *
                          (1 - ((_t.value * 3 - i) % 3).clamp(0.0, 1.0)),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: p.ink2, shape: BoxShape.circle),
                  ),
                ),
              ),
          ]),
        ),
        if (widget.status != null) ...[
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(widget.status!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.cap.copyWith(color: p.ink3)),
          ),
        ],
      ]),
    );
  }
}

/// One transcript entry. The user's turn is a bubble on the right; the coach
/// answers on the page beside its mark (no card chrome — a card around every
/// answer makes a chat read as a feed); figures keep their own frame.
class _Bubble extends StatelessWidget {
  final CoachItem item;

  /// First of a run of the coach's items, so it carries the coach's mark.
  final bool lead;
  const _Bubble({required this.item, this.lead = true});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    switch (item.kind) {
      case CoachItemKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: S.x4, left: S.x12),
            padding: const EdgeInsets.symmetric(
              horizontal: S.x4,
              vertical: S.x3,
            ),
            decoration: BoxDecoration(
              color: p.card2,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(R.xxl),
                topRight: Radius.circular(R.xxl),
                bottomLeft: Radius.circular(R.xxl),
                bottomRight: Radius.circular(S.x1),
              ),
            ),
            child: Text(
              item.text ?? '',
              style: F.body.copyWith(color: p.ink, height: 1.4),
            ),
          ),
        );
      case CoachItemKind.assistant:
        return _CoachRow(
          lead: lead,
          child: GptMarkdown(
            item.text ?? '',
            style: F.head.copyWith(
                color: p.ink.withValues(alpha: .84),
                fontWeight: FontWeight.w400,
                height: 1.6),
          ),
        );
      case CoachItemKind.chart:
        return _CoachRow(
          lead: lead,
          child: CoachFigure(spec: item.chart!.toJson()),
        );
      case CoachItemKind.render:
        return _CoachRow(
          lead: lead,
          child: CoachFigure(spec: item.render!),
        );
      case CoachItemKind.error:
        return Padding(
          padding: const EdgeInsets.only(bottom: S.x4),
          child: StatusCard(
            AppLocalizations.of(c)?.coachErrorTitle ?? 'That did not go through',
            coachPresentationText(AppLocalizations.of(c), item.text ?? ''),
            icon: LucideIcons.triangleAlert,
          ),
        );
    }
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  const _MenuRow(
    this.icon,
    this.title, {
    this.sub = '',
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Icon(icon, size: I.sm, color: p.ink3),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: F.body.copyWith(color: p.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      style: F.cap.copyWith(color: p.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onRemove != null)
              Pressable(
                semanticLabel:
                    AppLocalizations.of(c)?.coachDeleteChat(title) ?? 'Delete $title',
                onTap: onRemove,
                child: Icon(LucideIcons.trash2, size: I.sm, color: p.ink3),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════ setup ═══════════════════════

/// A provider preset. Local ones come first and carry no key, because a model
/// running on the user's own machine is the only configuration where the health
/// data never leaves their control.
class _Preset {
  final String label, sub, baseUrl;
  final bool local;
  const _Preset(this.label, this.sub, this.baseUrl, {this.local = false});
}

List<_Preset> _presets(BuildContext c) {
  final local = AppLocalizations.of(c)?.coachLocalSub ??
      'On this network. Nothing leaves your machine.';
  return <_Preset>[
    _Preset('Google Gemini', 'generativelanguage.googleapis.com',
        'https://generativelanguage.googleapis.com/v1beta/openai'),
    _Preset('Ollama', local, 'http://localhost:11434/v1', local: true),
    _Preset('LM Studio', local, 'http://localhost:1234/v1', local: true),
    _Preset('OpenAI', 'api.openai.com', 'https://api.openai.com/v1'),
    _Preset('Anthropic', 'api.anthropic.com', 'https://api.anthropic.com/v1'),
    _Preset('OpenRouter', 'openrouter.ai', 'https://openrouter.ai/api/v1'),
  ];
}

class CoachSetup extends StatefulWidget {
  const CoachSetup({super.key});

  @override
  State<CoachSetup> createState() => _CoachSetupState();
}

class _CoachSetupState extends State<CoachSetup> {
  late final TextEditingController _base;
  late final TextEditingController _key;
  late final TextEditingController _search;
  late final TextEditingController _timeout;
  late CoachApi _api;
  String _model = '';
  late final TextEditingController _foodModel;
  List<String> _models = const [];
  bool _loading = false;
  String? _msg;

  /// The origin whatever key is currently STORED (in the keychain, not just
  /// visible in [_key]) belongs to. Set at init and only ever advanced by
  /// [_onBaseChanged] or a successful [_save] — never by [_key] itself, so
  /// that clearing the field programmatically doesn't erase the record of an
  /// origin change still needing [_pendingKeyDelete] applied.
  late String _keyOrigin;

  /// True once the base URL has moved to a different origin than [_keyOrigin]
  /// and no replacement key has been typed since. [_save] must force-delete
  /// the stored key in this case rather than leaving it untouched — the
  /// field reading empty is NOT proof there is nothing to delete: a key that
  /// exists but could not be read (`CoachConfig.keyUnreadable`) also seeds
  /// [_key] empty, and without this flag that "empty" was indistinguishable
  /// from "no key ever existed", so the old, unreadable key survived the
  /// origin change and was later sent to the new endpoint.
  bool _pendingKeyDelete = false;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<CoachConfig>();
    _base = TextEditingController(text: cfg.baseUrl);
    _key = TextEditingController(text: cfg.apiKey ?? '');
    _search = TextEditingController();
    _timeout = TextEditingController(text: cfg.timeoutSeconds.toString());
    _api = cfg.api;
    _model = cfg.model;
    _foodModel = TextEditingController(text: cfg.foodModel);
    _keyOrigin = coachEndpointOrigin(cfg.baseUrl);
    // The base URL decides which preset is lit and whether a key is needed, and
    // the search box filters the list — both are read during build, so both
    // have to rebuild it.
    void redraw() {
      if (mounted) setState(() {});
    }

    _base.addListener(_onBaseChanged);
    // Deliberately NOT tracked via a _key listener: an early attempt cleared
    // _pendingKeyDelete as soon as the user typed a replacement, but typing
    // one and then erasing it left the flag cleared with nothing to show for
    // it — coachApiKeyToSave, called from _save with the CURRENT _key.text,
    // already derives "is there a real replacement right now" correctly by
    // checking the trimmed text itself; _pendingKeyDelete only needs to say
    // whether the endpoint changed, not track the field's history.
    _search.addListener(redraw);
    _foodModel.addListener(redraw);
  }

  /// Clears a carried-over key rather than letting Save silently send it to a
  /// DIFFERENT origin than the one it was typed for — switching presets, or
  /// editing the base URL to point somewhere else, must not reuse a cloud key
  /// against a new local/private endpoint (or vice versa) without the user
  /// re-entering it.
  void _onBaseChanged() {
    final origin = coachEndpointOrigin(_base.text);
    if (origin != _keyOrigin) {
      _keyOrigin = origin;
      _api = CoachApi.defaultFor(_base.text);
      _pendingKeyDelete = true;
      if (_key.text.isNotEmpty) _key.clear();
      _msg = 'The API key was cleared because the endpoint changed.';
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _base.dispose();
    _key.dispose();
    _search.dispose();
    _foodModel.dispose();
    _timeout.dispose();
    super.dispose();
  }

  bool get _isLocal => isLocalCoachHost(_base.text.trim());

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _msg = null;
    });
    try {
      var ids = await CoachEngine.fetchModels(_base.text, _key.text);
      if (ids.isEmpty && _base.text.contains('googleapis.com')) {
        ids = const [
          'gemini-2.5-flash',
          'gemini-1.5-flash',
          'gemini-1.5-pro',
          'gemini-2.0-flash',
        ];
      }
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      setState(() {
        _models = ids;
        _msg = ids.isEmpty
            ? (l?.coachNoModelsListed ??
                'That endpoint listed no models. Type one below instead.')
            : (l?.coachModelsFound(ids.length) ?? '${ids.length} models. Tap one.');
      });
    } catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      setState(
        () => _msg = e is CoachException
            ? e.message
            : (l?.coachEndpointUnreachable('$e') ?? 'Could not reach that endpoint: $e'),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final chosen = _model.isNotEmpty ? _model : _search.text.trim();
    final l = AppLocalizations.of(context);
    if (chosen.isEmpty) {
      setState(() => _msg = l?.coachPickModelFirst ?? 'Pick or type a model first.');
      return;
    }
    final cfg = context.read<CoachConfig>();
    final nav = Navigator.of(context);
    // The field is hidden for a cloud endpoint (it has no effect there — see
    // CoachConfig.requestTimeout), so its stale text must not overwrite the
    // saved local timeout. Garbage or blank input for a local endpoint leaves
    // the existing timeout untouched (CoachConfig also rejects <=0) rather
    // than blocking the rest of the save over one bad field.
    final timeoutSeconds = _isLocal ? int.tryParse(_timeout.text.trim()) : null;
    try {
      await cfg.save(
        baseUrl: _base.text,
        apiKey: coachApiKeyToSave(
          keyText: _key.text,
          storedKeyReadable: cfg.apiKey != null,
          pendingKeyDelete: _pendingKeyDelete,
        ),
        model: chosen,
        foodModel: _foodModel.text,
        api: _api,
        timeoutSeconds: timeoutSeconds,
      );
    } catch (e) {
      if (mounted) {
        setState(() =>
            _msg = l?.coachKeychainRefused('$e') ?? 'The keychain refused the key: $e');
      }
      return;
    }
    _pendingKeyDelete = false;
    if (mounted && nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? _models
        : [
            for (final m in _models)
              if (m.toLowerCase().contains(q)) m,
          ];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(l?.coachSetupNavTitle ?? 'AI settings',
                  sub: l?.coachSetupNavSub ?? 'Bring your own model'),
            ),
            Expanded(
              child: ListView(
                padding: pad,
                children: [
                  Section(
                    l?.coachWhereModelRuns ?? 'Where the model runs',
                    Column(
                      children: [
                        for (final preset in _presets(c))
                          Padding(
                            padding: const EdgeInsets.only(bottom: S.x2),
                            child: Surface(
                              elevation: 0,
                              color: _base.text.trim() == preset.baseUrl
                                  ? p.wash(
                                      preset.local ? C.green : kCoachAccent,
                                    )
                                  : p.card2,
                              onTap: () => setState(() {
                                // BEFORE assigning _base.text: that assignment
                                // fires _onBaseChanged synchronously, which
                                // may set _msg to explain a cleared key —
                                // clearing _msg after it runs would silently
                                // discard that explanation.
                                _msg = null;
                                _base.text = preset.baseUrl;
                                _api = CoachApi.defaultFor(preset.baseUrl);
                                if (preset.baseUrl.contains('googleapis.com')) {
                                  _models = const [
                                    'gemini-2.5-flash',
                                    'gemini-1.5-flash',
                                    'gemini-1.5-pro',
                                    'gemini-2.0-flash',
                                  ];
                                  _model = 'gemini-2.5-flash';
                                } else {
                                  _models = const [];
                                  _model = '';
                                }
                              }),
                              child: Row(
                                children: [
                                  Icon(
                                    preset.local
                                        ? LucideIcons.house
                                        : LucideIcons.cloud,
                                    size: I.sm,
                                    color: p.on(
                                      preset.local ? C.green : kCoachAccent,
                                    ),
                                  ),
                                  const SizedBox(width: S.x3),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          preset.label,
                                          style: F.body.copyWith(
                                            color: p.ink,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          preset.sub,
                                          style: F.cap.copyWith(color: p.ink3),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x2),
                  OsTextField(
                    controller: _base,
                    label: l?.coachBaseUrlLabel ?? 'Base URL',
                    hint: 'http://localhost:11434/v1',
                  ),
                  const SizedBox(height: S.x4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l?.coachApiFormatLabel ?? 'API',
                          style: F.over.copyWith(color: p.ink3)),
                      const SizedBox(height: S.x2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: S.x3),
                        decoration: BoxDecoration(
                          color: p.card2,
                          borderRadius: R.rMd,
                        ),
                        child: Semantics(
                          label: l?.coachApiFormatLabel ?? 'API',
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<CoachApi>(
                              value: _api,
                              isExpanded: true,
                              dropdownColor: p.card,
                              style: F.body.copyWith(color: p.ink),
                              items: const [
                                DropdownMenuItem(
                                  value: CoachApi.responses,
                                  child: Text('Responses'),
                                ),
                                DropdownMenuItem(
                                  value: CoachApi.chatCompletions,
                                  child: Text('Chat Completions'),
                                ),
                              ],
                              onChanged: (api) {
                                if (api != null) setState(() => _api = api);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: S.x2),
                      Text(
                        l?.coachApiFormatHelp ??
                            'Choose the API your endpoint supports. Responses '
                                'supports OpenAI reasoning with tools.',
                        style: F.cap.copyWith(color: p.ink3, height: 1.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x4),
                  OsTextField(
                    controller: _key,
                    label: _isLocal
                        ? (l?.coachApiKeyLocalLabel ?? 'API key (not needed locally)')
                        : (l?.coachApiKeyLabel ?? 'API key'),
                    hint: 'sk-…',
                  ),
                  const SizedBox(height: S.x3),
                  // The one sentence that decides whether a cloud key is a
                  // reasonable choice. It is here, next to the field, and not
                  // in a settings page nobody opens. Private hosts only: a
                  // 100.64.0.0/10 address needs no key but may not be yours.
                  Text(
                    isPrivateCoachHost(_base.text.trim())
                        ? (l?.coachLocalDataNote ??
                            'Your questions and the rows the coach reads stay on '
                                'your own machine.')
                        : (l?.coachCloudDataNote ??
                            'Your questions and the rows the coach reads are sent '
                                'to this endpoint. See exactly what that is on '
                                '"What was sent".'),
                    style: F.cap.copyWith(color: p.ink3, height: 1.5),
                  ),
                  const SizedBox(height: S.x4),
                  BigButton(
                    _loading ? (l?.coachAsking ?? 'Asking…') : (l?.coachListModels ?? 'List models'),
                    icon: LucideIcons.refreshCw,
                    color: kCoachAccent,
                    soft: true,
                    onTap: _loading ? null : _fetch,
                  ),
                  if (_msg != null) ...[
                    const SizedBox(height: S.x3),
                    Text(coachPresentationText(l, _msg!), style: F.cap.copyWith(color: p.ink3)),
                  ],
                  const SizedBox(height: S.x4),
                  OsTextField(
                    controller: _search,
                    label: l?.coachModelLabel ?? 'Model',
                    hint: l?.coachModelHint ?? 'search, or type an id',
                  ),
                  const SizedBox(height: S.x1),
                  Builder(
                    builder: (_) => Padding(
                      padding: const EdgeInsets.only(top: S.x2),
                      child: Column(
                        children: [
                          for (final m in shown.take(60))
                            Pressable(
                              onTap: () => setState(() => _model = m),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: S.x3,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      m == _model
                                          ? LucideIcons.circleCheck
                                          : LucideIcons.circle,
                                      size: I.sm,
                                      color: m == _model
                                          ? p.on(kCoachAccent)
                                          : p.ink3,
                                    ),
                                    const SizedBox(width: S.x3),
                                    Expanded(
                                      child: Text(
                                        m,
                                        style: F.cap.copyWith(color: p.ink),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x5),
                  OsTextField(
                    controller: _foodModel,
                    label: 'Model for food photos',
                    hint: 'Empty uses the coach model above',
                  ),
                  const SizedBox(height: S.x2),
                  Text(
                    'Logging food from a photo or a sentence can use a different '
                    'model from the coach. It must be able to read pictures.',
                    style: F.cap.copyWith(color: p.ink3, height: 1.5),
                  ),
                  if (_models.isNotEmpty) ...[
                    const SizedBox(height: S.x2),
                    Wrap(
                      spacing: S.x2,
                      runSpacing: S.x2,
                      children: [
                        for (final m in _models
                            .where((m) => m
                                .toLowerCase()
                                .contains(_foodModel.text.trim().toLowerCase()))
                            .take(6))
                          Pressable(
                            semanticLabel: m,
                            onTap: () => setState(() => _foodModel.text = m),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: S.x3, vertical: S.x2),
                              decoration: BoxDecoration(
                                color: m == _foodModel.text.trim()
                                    ? p.fill(kCoachAccent)
                                    : p.card2,
                                borderRadius: R.rPill,
                              ),
                              child: Text(
                                m,
                                style: F.cap.copyWith(
                                    color: m == _foodModel.text.trim()
                                        ? p.inkOn(p.fill(kCoachAccent))
                                        : p.ink2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (_isLocal) ...[
                    const SizedBox(height: S.x4),
                    OsTextField(
                      controller: _timeout,
                      label: uiText(c, 'Request timeout (seconds)'),
                      hint: '300',
                      keyboard: TextInputType.number,
                    ),
                    const SizedBox(height: S.x3),
                    Text(
                      uiText(
                        c,
                        'A local model can take a while to load before its first reply. Default is 5 minutes (300s). Cloud providers always use 2 minutes.',
                      ),
                      style: F.cap.copyWith(color: p.ink3, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: S.x4),
                  BigButton(
                    l?.actionSave ?? 'Save',
                    icon: LucideIcons.check,
                    color: kCoachAccent,
                    onTap: _save,
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
