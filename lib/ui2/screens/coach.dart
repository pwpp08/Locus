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
import 'dart:convert' show utf8;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
import 'coach_parts.dart';
import 'coach_workout.dart';
import '../../coach/workout_plan.dart';
import 'home_screen.dart' show go, pad, repoOf;
import 'journal_compose.dart' show OsTextField;
import 'plus_menu.dart' show showAnchoredMenu;

/// The coach's accent. Not a domain colour: the coach reads across all five.
const Color kCoachAccent = C.dialStrain;

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

/// The coach as a sheet over whatever is on screen: what the floating AI
/// button opens. The same conversation machinery as [CoachScreen]; a fresh
/// conversation each time, the earlier ones under Chats.
Future<void> openCoachSheet(BuildContext c) {
  if (!coachReadyNow(c)) {
    go(c, const CoachSetup());
    return Future.value();
  }
  return AppSheet.open<void>(
    c,
    bare: true,
    scroll: true,
    builder: (_) => const CoachScreen(sheet: true),
  );
}

/// The doors behind the composer's (+).
enum _Plus { newChat, image, file, camera, suggest }

/// The text files the coach can be handed, read as UTF-8.
const _textFiles = ['txt', 'csv', 'tsv', 'md', 'json', 'log', 'xml', 'gpx'];

/// The most of one file that goes to the model; the rest is cut, and the
/// model is told so.
const _maxFileChars = 60000;

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

  /// Drawn as the floating button's sheet rather than a page.
  final bool sheet;

  const CoachScreen({
    super.key,
    this.initialMessage,
    this.outlook,
    this.sheet = false,
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

  /// What waits in the composer to go with the next message.
  final List<CoachImage> _images = [];
  ({String name, String text})? _file;

  /// The last question asked, for Retry on an error.
  String? _lastAsked;
  final _plusKey = GlobalKey();

  /// Scrolled up far enough from the newest line to offer the way back.
  bool _farFromEnd = false;

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
    _scroll.addListener(() {
      final far = _scroll.hasClients &&
          _scroll.position.maxScrollExtent - _scroll.offset > S.x16 * 2;
      if (far != _farFromEnd && mounted) setState(() => _farFromEnd = far);
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

  /// The composer's (+): a new conversation, a picture or a file to send, or
  /// something to try asking.
  Future<void> _plus() async {
    final box = _plusKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final at = box.localToGlobal(Offset.zero) & box.size;
    final l = AppLocalizations.of(context);
    final pick = await showAnchoredMenu<_Plus>(context, at, [
      (_Plus.newChat, LucideIcons.messageSquarePlus, 'New conversation'),
      (_Plus.image, LucideIcons.image, 'Upload image'),
      (_Plus.file, LucideIcons.fileText, 'Upload file'),
      (_Plus.camera, LucideIcons.camera, 'Take picture'),
      (_Plus.suggest, LucideIcons.lightbulb, l?.coachTryAsking ?? 'Try asking'),
    ]);
    if (!mounted) return;
    switch (pick) {
      case _Plus.newChat:
        _newChat();
      case _Plus.image:
        await _pickImage(ImageSource.gallery);
      case _Plus.camera:
        await _pickImage(ImageSource.camera);
      case _Plus.file:
        await _pickFile();
      case _Plus.suggest:
        await _suggest();
      case null:
        break;
    }
  }

  void _attachError(String message) {
    if (mounted) setState(() => _items.add(CoachItem.error(message)));
  }

  /// A picture, scaled down on the phone before it is ever read: a 1600 px
  /// JPEG is plenty for a model to read a label or a plate, and a fraction of
  /// the original's size.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      if (bytes.length > CoachImage.maxBytes) {
        _attachError('That picture is too large to send '
            '(${bytes.length ~/ 1024} KB; the limit is '
            '${CoachImage.maxBytes ~/ 1024} KB).');
        return;
      }
      setState(() {
        // Three at most: the oldest makes way.
        if (_images.length >= 3) _images.removeAt(0);
        _images.add(CoachImage(x.mimeType ?? imageMimeFor(x.name), bytes));
      });
    } catch (e) {
      _attachError(source == ImageSource.camera
          ? 'The camera could not be opened: $e'
          : 'The picture could not be opened: $e');
    }
  }

  /// A text file — a CSV export, notes, a GPX track — read whole and sent
  /// after the question.
  Future<void> _pickFile() async {
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _textFiles,
        withData: true,
      );
      final f = r?.files.single;
      final bytes = f?.bytes;
      if (f == null || bytes == null || !mounted) return;
      final String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        _attachError('${f.name} is not a text file the coach can read.');
        return;
      }
      setState(() => _file = (name: f.name, text: clipFileText(text)));
    } catch (e) {
      _attachError('The file could not be opened: $e');
    }
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

  /// Ask the latest question again for a new answer.
  Future<void> _regenerate() async {
    final engine = _engine;
    final q = engine?.takeBackLastTurn();
    if (engine == null || q == null) return;
    setState(() {
      _items
        ..clear()
        ..addAll(engine.transcript);
    });
    // A file sent with it goes again, but the bubble shows the question.
    final i = q.indexOf('\n\n--- ');
    await _send(q, display: i < 0 ? null : q.substring(0, i));
  }

  Future<void> _send(String text, {String? display}) async {
    var t = text.trim();
    final engine = _engine;
    final images = List<CoachImage>.of(_images);
    final file = _file;
    final attached = images.isNotEmpty || file != null;
    if ((t.isEmpty && !attached) || _busy || engine == null) return;
    if (t.isEmpty) {
      t = images.isNotEmpty
          ? 'Have a look at this picture.'
          : 'Have a look at this file.';
    }
    _lastAsked = t;
    // The bubble names what went with the question; the file itself goes to
    // the model in full, after it.
    final shown = display ??
        (!attached
        ? null
        : [
            t,
            if (images.length == 1) '(a picture attached)',
            if (images.length > 1) '(${images.length} pictures attached)',
            if (file != null) '(attached: ${file.name})',
          ].join('\n'));
    final sent =
        file == null ? t : '$t\n\n--- ${file.name} ---\n${file.text}';
    _input.clear();
    setState(() {
      _busy = true;
      _images.clear();
      _file = null;
    });
    // Read before the await: `send` can outlive this screen.
    final app = context.read<AppState>();
    var wrote = false;
    try {
      // `send` can block for up to 120 s, so every callback below can land after
      // the user has popped the screen.
      await engine.send(
        sent,
        images: images,
        shown: shown,
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

  /// The model the coach runs on, for its tag.
  String _modelLabel(BuildContext c, CoachConfig cfg) => cfg.configured
      ? cfg.model
      : (AppLocalizations.of(c)?.coachNotSetUp ?? 'Not set up');

  Widget _historyButton(BuildContext c) => Pressable(
        onTap: _menu,
        semanticLabel: AppLocalizations.of(c)?.coachMenuSemantic ??
            'Chats and AI settings',
        child: const SizedBox.square(
          dimension: S.tap,
          child: Icon(LucideIcons.history, size: I.lg, color: C.white),
        ),
      );

  /// The sheet's top: the grab bar, the coach's tag, and past chats.
  Widget _sheetHeader(BuildContext c, CoachConfig cfg) => Padding(
        padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x2, S.x1),
        child: Column(children: [
          Container(
            width: S.x10,
            height: S.x1,
            decoration: BoxDecoration(
                color: C.white.withValues(alpha: .3), borderRadius: R.rPill),
          ),
          const SizedBox(height: S.x2),
          Row(children: [
            Flexible(child: CoachTag(_modelLabel(c, cfg))),
            const Spacer(),
            _historyButton(c),
          ]),
        ]),
      );

  /// Back, the coach's tag in the middle, and past chats.
  Widget _header(BuildContext c, CoachConfig cfg) => Padding(
        padding: const EdgeInsets.fromLTRB(S.x1, S.x2, S.x1, S.x2),
        child: Row(children: [
          Pressable(
            onTap: () => Navigator.maybePop(c),
            semanticLabel:
                AppLocalizations.of(c)?.supplementNavBack ?? 'Back',
            child: const SizedBox.square(
              dimension: S.tap,
              child: Icon(LucideIcons.chevronLeft, size: I.lg, color: C.white),
            ),
          ),
          Expanded(child: Center(child: CoachTag(_modelLabel(c, cfg)))),
          _historyButton(c),
        ]),
      );

  @override
  Widget build(BuildContext c) =>
      AlwaysChar(child: Builder(builder: _build));

  Widget _build(BuildContext c) {
    final p = P.of(c);
    final cfg = c.watch<CoachConfig>();
    final ready = cfg.configured && _engine != null;
    final replies = ready && !_busy ? _replies() : const <String>[];
    final column = Column(children: [
      widget.sheet ? _sheetHeader(c, cfg) : _header(c, cfg),
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: _body(c, p, cfg)),
          if (_farFromEnd)
            Positioned(
              left: 0,
              right: 0,
              bottom: S.x2,
              child: Center(child: CoachScrollDown(onTap: _scrollDown)),
            ),
        ]),
      ),
      if (replies.isNotEmpty) ...[
        CoachReplyChips(replies, onTap: _send),
        const SizedBox(height: S.x2),
      ],
      if (ready) _composer(c, p),
    ]);
    if (widget.sheet) {
      return FractionallySizedBox(
        heightFactor: .92,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(R.xxl)),
          child: CoachGround(
            child: SafeArea(top: false, child: column),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: C.coachNight.last,
      body: CoachGround(child: SafeArea(child: column)),
    );
  }

  /// The latest answer's suggested replies, until the person says anything.
  List<String> _replies() {
    for (var i = _items.length - 1; i >= 0; i--) {
      final it = _items[i];
      if (it.kind == CoachItemKind.user || it.kind == CoachItemKind.error) {
        return const [];
      }
      if (it.kind == CoachItemKind.assistant && it.replies.isNotEmpty) {
        return it.replies;
      }
    }
    return const [];
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
    final lastAnswer =
        _items.lastIndexWhere((i) => i.kind == CoachItemKind.assistant);
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
            status: _status == null
                ? null
                : coachPresentationText(AppLocalizations.of(context), _status!),
          );
        }
        final asked = _lastAsked;
        return _Bubble(
          item: _items[i],
          onAlternatives: !_busy && i == _items.length - 1 ||
                  !_busy && i == _items.length - 2 &&
                      _items.last.kind == CoachItemKind.assistant
              ? () => _send('Give me different options.')
              : null,
          streaming: identical(_items[i], _streamingItem),
          onRegenerate: !_busy && i == lastAnswer ? _regenerate : null,
          // Only the latest error, and only once nothing is on its way.
          // ponytail: the failed question stays in the history, so a retry
          // sends it a second time; models take two user turns in a row.
          onRetry: i == _items.length - 1 &&
                  _items[i].kind == CoachItemKind.error &&
                  asked != null &&
                  !_busy
              ? () => _send(asked)
              : null,
        );
      },
      ),
    );
  }

  /// The (+) square, and the message box: a dark field in a violet-to-blue
  /// edge with the send arrow inside it.
  Widget _composer(BuildContext c, P p) {
    final l = AppLocalizations.of(c);
    final attached = _images.isNotEmpty || _file != null;
    final canSend = !_busy && (_input.text.trim().isNotEmpty || attached);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          S.x4, S.x1, S.x4, S.x3 + MediaQuery.of(c).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (attached) _attachments(c, p),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          KeyedSubtree(
            key: _plusKey,
            child: Pressable(
              onTap: _busy ? null : _plus,
              semanticLabel: 'New conversation, a picture or a file',
              child: Container(
                width: S.tap + S.x1,
                height: S.tap + S.x1,
                decoration: const BoxDecoration(
                    color: C.coachPlus, borderRadius: R.rLg),
                child: Icon(LucideIcons.plus,
                    size: I.lg, color: _busy ? p.ink3 : C.white),
              ),
            ),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(S.hair + S.half / 4),
              decoration: BoxDecoration(
                borderRadius: R.rXl,
                // Lit at the left, fading into the ground at the right.
                gradient: LinearGradient(colors: [
                  C.coachGoA,
                  C.coachGoB.withValues(alpha: .35),
                ]),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: S.tap),
                padding: const EdgeInsets.only(left: S.x4),
                decoration: const BoxDecoration(
                  color: C.coachField,
                  borderRadius:
                      BorderRadius.all(Radius.circular(R.xl - S.hair)),
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
                        hint: 'Ask Locus anything',
                      ),
                    ),
                  ),
                  Pressable(
                    semanticLabel: l?.coachSendLabel ?? 'Send',
                    onTap: canSend ? () => _send(_input.text) : null,
                    child: SizedBox.square(
                      dimension: S.tap,
                      child: Icon(LucideIcons.arrowUp,
                          size: I.md, color: canSend ? C.white : p.ink3),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  /// What will go with the next message: each picture as a thumbnail and the
  /// file by name, each with its own cross.
  Widget _attachments(BuildContext c, P p) {
    Widget remove(String label, VoidCallback onTap) => Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: Icon(LucideIcons.x, size: I.sm, color: p.ink2),
        );
    return Padding(
      padding: const EdgeInsets.only(left: S.x2, bottom: S.x2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: S.x2,
          runSpacing: S.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _images.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                  borderRadius: R.rSm,
                  child: Image.memory(_images[i].bytes,
                      width: S.x12, height: S.x12, fit: BoxFit.cover),
                ),
                remove('Remove the picture',
                    () => setState(() => _images.removeAt(i))),
              ]),
            if (_file case final f?)
              Container(
                padding: const EdgeInsets.only(left: S.x3),
                decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.fileText, size: I.sm, color: p.ink2),
                  const SizedBox(width: S.x2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.cap.copyWith(color: p.ink)),
                  ),
                  remove('Remove ${f.name}', () => setState(() => _file = null)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// The media type for a picked picture whose picker did not say.
String imageMimeFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

/// [text] as it goes to the model: whole, or its first [_maxFileChars]
/// characters with a line saying the rest was left out.
String clipFileText(String text) => text.length <= _maxFileChars
    ? text
    : '${text.substring(0, _maxFileChars)}\n'
        '[the rest of the file, ${text.length - _maxFileChars} more '
        'characters, was left out]';

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
        decoration: BoxDecoration(
            color: C.white.withValues(alpha: .07), borderRadius: R.rXl),
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

/// Waiting on the model: three dots, and what it is doing if it says.
class _Thinking extends StatefulWidget {
  final String? status;
  const _Thinking({this.status});

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
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x5),
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

/// One transcript entry: the person's turn in a bubble on the right, the
/// coach's on the ground, its figures in a coach card.
class _Bubble extends StatelessWidget {
  final CoachItem item;

  /// Still arriving: no copy row yet, and the replies line held back.
  final bool streaming;

  /// Answer again; null shows no button (only the latest answer has one).
  final VoidCallback? onRegenerate;

  /// An error's Retry; null shows none.
  final VoidCallback? onRetry;

  /// Ask for other workouts; only on the latest proposal.
  final VoidCallback? onAlternatives;
  const _Bubble({
    required this.item,
    this.onAlternatives,
    this.streaming = false,
    this.onRegenerate,
    this.onRetry,
  });

  @override
  Widget build(BuildContext c) {
    Widget figure(Map<String, dynamic> spec) => Padding(
          padding: const EdgeInsets.only(bottom: S.x5),
          child: CoachCard(
            padding: const EdgeInsets.all(S.x3),
            child: CoachFigure(spec: spec),
          ),
        );
    switch (item.kind) {
      case CoachItemKind.user:
        return CoachUserBubble(item.text ?? '');
      case CoachItemKind.assistant:
        final text = item.text ?? '';
        return CoachAnswer(
          streaming ? withoutRepliesTail(text) : text,
          actions: !streaming,
          onRegenerate: onRegenerate,
        );
      case CoachItemKind.chart:
        return figure(item.chart!.toJson());
      case CoachItemKind.render:
        final spec = item.render!;
        if (spec['type'] == 'workout') {
          final plans = [
            for (final o in (spec['options'] as List? ?? const []))
              ?WorkoutPlan.fromJson(o),
          ];
          return Padding(
            padding: const EdgeInsets.only(bottom: S.x4),
            child: ValueListenableBuilder<int>(
              valueListenable: WorkoutPlanStore.changed,
              builder: (_, _, _) => CoachWorkoutOptions(
                plans: plans,
                committed: WorkoutPlanStore.current,
                onCommit: WorkoutPlanStore.save,
                onAlternatives: onAlternatives,
              ),
            ),
          );
        }
        return figure(spec);
      case CoachItemKind.error:
        return Padding(
          padding: const EdgeInsets.only(bottom: S.x4),
          child: StatusCard(
            AppLocalizations.of(c)?.coachErrorTitle ?? 'That did not go through',
            coachPresentationText(AppLocalizations.of(c), item.text ?? ''),
            icon: LucideIcons.triangleAlert,
            fix: onRetry == null ? '' : 'Retry',
            onFix: onRetry,
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

/// Words in a model id that mark it as not a general chat model, or not a
/// settled one: media, speech, embeddings, search, previews and experiments.
const _notStandard = [
  'embed', 'tts', 'audio', 'image', 'imagen', 'veo', 'live', 'aqa',
  'learnlm', 'transcribe', 'realtime', 'search', 'moderation', 'whisper',
  'dall-e', 'babbage', 'davinci', 'computer-use', 'robotics', 'exp',
  'preview', 'thinking', 'native', 'lyria', 'gemma',
];

/// Words that mark a hosted model as a legacy completions model (OpenAI's
/// `gpt-3.5-turbo-instruct`), but are the NORMAL chat build on a local server
/// (`qwen2.5:7b-instruct`, `llama3.1:8b-instruct-q4_K_M`).
const _notStandardHosted = ['instruct'];

/// The ids worth offering without a search: general chat models under their
/// plain names. Pinned builds (`-001`, `-0613`, `-2024-08-06`) are dropped
/// when the plain name is listed too. All of [ids] when the filter would
/// leave none, so an unusual endpoint never shows an empty list. [local] is a
/// server on this machine or network, where `-instruct` is how chat models
/// are named.
List<String> standardModels(List<String> ids, {bool local = false}) {
  String bare(String id) => id.toLowerCase().replaceFirst('models/', '');
  bool notStandard(String id) =>
      _notStandard.any(bare(id).contains) ||
      (!local && _notStandardHosted.any(bare(id).contains));
  final pin = RegExp(r'-(\d{3,4}|\d{4}-\d{2}-\d{2})$');
  final plain = {for (final id in ids) bare(id)};
  final kept = [
    for (final id in ids)
      if (!notStandard(id) &&
          !(pin.hasMatch(bare(id)) &&
              plain.contains(bare(id).replaceFirst(pin, ''))))
        id,
  ];
  return kept.isEmpty ? ids : kept;
}

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
          'gemini-2.5-pro',
          'gemini-2.5-flash-lite',
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
        // The separate food-photo model is gone from this screen; clearing it
        // here means food logging uses the coach's model, rather than one the
        // user can no longer see or change.
        foodModel: '',
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
    // Without a search, the standard models only; a search reaches them all.
    final standard = standardModels(_models, local: _isLocal);
    final shown = q.isEmpty
        ? [
            if (_model.isNotEmpty && !standard.contains(_model)) _model,
            ...standard,
          ]
        : [
            for (final m in _models)
              if (m.toLowerCase().contains(q)) m,
          ];
    final presets = _presets(c);
    final presetAt =
        presets.indexWhere((x) => x.baseUrl == _base.text.trim());
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
                  AppDropdown(
                    label: l?.coachWhereModelRuns ?? 'Where the model runs',
                    options: [for (final x in presets) x.label],
                    index: presetAt,
                    hint: 'Custom endpoint',
                    onChanged: (i) => setState(() {
                      final preset = presets[i];
                      // BEFORE assigning _base.text: that assignment fires
                      // _onBaseChanged synchronously, which may set _msg to
                      // explain a cleared key — clearing _msg after it runs
                      // would silently discard that explanation.
                      _msg = null;
                      _base.text = preset.baseUrl;
                      _api = CoachApi.defaultFor(preset.baseUrl);
                      if (preset.baseUrl.contains('googleapis.com')) {
                        _models = const [
                          'gemini-2.5-flash',
                          'gemini-2.5-pro',
                          'gemini-2.5-flash-lite',
                        ];
                        _model = 'gemini-2.5-flash';
                      } else {
                        _models = const [];
                        _model = '';
                      }
                    }),
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
                      RangeSegments(
                        const ['RESPONSES', 'CHAT COMPLETIONS'],
                        _api == CoachApi.chatCompletions ? 1 : 0,
                        (i) => setState(() => _api = i == 1
                            ? CoachApi.chatCompletions
                            : CoachApi.responses),
                        width: null,
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
                  if (q.isEmpty && shown.length < _models.length)
                    Padding(
                      padding: const EdgeInsets.only(top: S.x1),
                      child: Text(
                        'Previews, pinned builds and image, audio and '
                        'embedding models are hidden. Search to see all '
                        '${_models.length}.',
                        style: F.cap.copyWith(color: p.ink3, height: 1.5),
                      ),
                    ),
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
