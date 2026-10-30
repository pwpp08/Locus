// The shell.
//
// Home · Health · (+) · AI · More. Home is today; Health is the longer-term
// picture; More is the profile, devices and settings. Between them sit two
// buttons that are NOT destinations: the Action (+) button, the quickest way
// to start an activity, write the journal or go live, and the coach. A button
// opens something over the shell and leaves the selected tab where it was.
//
// The bar is a frosted Glass pill that FLOATS over the tabs, which run
// full-bleed behind it; the active tab is a volt pill with dark ink. Every
// tab's scroll view ends in `S.navClear(context)` of padding so its last row
// can be lifted clear of it.
//
// There is no fourth tab, and the type system is what says so — [ShellDomain]
// is a closed enum and [AppShell] takes a builder keyed by it, so "just add a
// tab for X" is a change to this file with a reviewer attached, not something
// a screen can do on its own. Anything that feels like another destination is
// a section or a pushed screen inside the domain that owns it — Sleep and
// Strain are the deep dives behind their dials on Home.

import 'package:flutter/material.dart';
import 'lucide.dart';

import '../l10n/app_localizations.dart';
import 'grammar.dart';
import 'theme.dart';

/// The four destinations, in bar order.
enum ShellDomain {
  today('Home', LucideIcons.house, C.domHome),
  strength('Strength', LucideIcons.dumbbell, C.domMove),
  macros('Macros', LucideIcons.utensils, C.domFood),
  more('More', LucideIcons.menu, C.domMind);

  const ShellDomain(this.label, this.icon, this.accent);

  final String label;
  final IconData icon;

  /// [label] in the user's language. Own keys rather than the screen titles,
  /// so two tabs can never end up with the same translated word.
  String title(BuildContext c) {
    final l = AppLocalizations.of(c);
    return switch (this) {
          ShellDomain.today => l?.tabHome,
          ShellDomain.strength => 'Strength',
          ShellDomain.macros => 'Macros',
          ShellDomain.more => l?.tabMore,
        } ??
        label;
  }

  /// The domain's pigment — the hue of its hero glow, NOT of the tab bar.
  /// Use `P.of(context).on(accent)` for text and `.fill(accent)` for a filled
  /// surface — the raw value is not AA-safe.
  final Color accent;
}

// There is no `Domain` InheritedWidget. Screens take their accent as a
// parameter, which is honest about where it comes from.

class AppShell extends StatefulWidget {
  /// Builds the body of one domain. Called lazily — a tab is not built until
  /// it is first selected, then kept alive by the [IndexedStack].
  final Widget Function(BuildContext context, ShellDomain domain) builder;

  final ShellDomain initial;

  /// Notified on every tab change, including a re-tap of the current tab
  /// (which domains conventionally use to scroll to top) and a return via Back.
  final void Function(ShellDomain domain)? onSelect;

  /// The Action (+) button. Null hides it.
  final void Function(BuildContext context)? onAction;

  /// The coach button. Null hides it.
  final void Function(BuildContext context)? onAi;

  /// Pinned between the domain and the tab bar, above every tab. This is not
  /// a general slot — it exists for state that is RUNNING and is not on
  /// screen, which today means a minimised workout. A domain's own content
  /// belongs inside the domain.
  final Widget? banner;

  const AppShell({
    super.key,
    required this.builder,
    this.initial = ShellDomain.today,
    this.onSelect,
    this.onAction,
    this.onAi,
    this.banner,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late ShellDomain _current = widget.initial;
  late final Set<ShellDomain> _built = {widget.initial};
  // Tabs are kept alive, not pushed onto the Navigator. Keep their history
  // here so Android Back can return to the previous tab. A restored tab or
  // cold-launch deep link has Home as its way back into the app.
  late final List<ShellDomain> _history = [
    if (widget.initial != ShellDomain.today) ShellDomain.today,
  ];

  void _select(ShellDomain d) {
    setState(() {
      // Each tab at most once, most recent last, so switching back and forth
      // between two tabs does not add a Back press per switch. Home stays in
      // as the way back into the app even while it is the tab on screen.
      if (d != _current) {
        _history.remove(_current);
        // Leaving Home puts it back at the bottom, never on top: it is the
        // last stop before Back leaves the app.
        if (_current == ShellDomain.today) {
          _history.insert(0, _current);
        } else {
          _history.add(_current);
        }
        if (d != ShellDomain.today) _history.remove(d);
      }
      _current = d;
      _built.add(d);
    });
    widget.onSelect?.call(d);
  }

  void _back() {
    if (_history.isEmpty) return;
    setState(() {
      _current = _history.removeLast();
      _built.add(_current);
    });
    widget.onSelect?.call(_current);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return PopScope<Object?>(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: p.bg,
        // The tabs run behind the bar; each one clears it with S.navClear.
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                // The page darkens downward, lighter slate at the top.
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [p.bgTop, p.bg],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: IndexedStack(
                    index: _current.index,
                    children: [
                      // An unvisited tab is an empty box, not a built screen.
                      for (final d in ShellDomain.values)
                        if (_built.contains(d))
                          widget.builder(c, d)
                        else
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: S.x4,
              right: S.x4,
              bottom: (S.x2 + 2.0) + MediaQuery.paddingOf(c).bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The minimised workout floats just above the bar as its
                  // own glass pill. Two blurs on screen, the glass budget in DESIGN.md.
                  if (widget.banner != null) ...[
                    Glass(radius: R.rPill, child: widget.banner!),
                    const SizedBox(height: S.x2),
                  ],
                  _TabBar(
                    current: _current,
                    onTap: _select,
                    onAction: widget.onAction == null
                        ? null
                        : () => widget.onAction!(c),
                    onAi: widget.onAi == null ? null : () => widget.onAi!(c),
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

class _TabBar extends StatelessWidget {
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;
  final VoidCallback? onAction, onAi;

  const _TabBar(
      {required this.current, required this.onTap, this.onAction, this.onAi});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    Widget tab(ShellDomain d) => Expanded(
          child: _Tab(domain: d, on: d == current, onTap: () => onTap(d)),
        );
    // A dark rounded rectangle floating over the tabs. Its only decoration is
    // the rim: a hairline lit at the top-left corner and gone by a third of
    // the way round, as if one light sat above and to the left. No glow, no
    // shadow. The selected tab carries a soft pool of light at its foot.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: R.rXxl,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            C.white.withValues(alpha: .30),
            C.white.withValues(alpha: .09),
            C.white.withValues(alpha: .04),
            C.white.withValues(alpha: .04),
          ],
          stops: const [0.0, 0.18, 0.45, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(S.hair),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: R.rXxl,
            color: Color.alphaBlend(C.slate.withValues(alpha: .4), C.char),
          ),
          child: ClipRRect(
            borderRadius: R.rXxl,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: S.navBar),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: S.x2, vertical: S.x1),
                child: Row(
                  children: [
                    tab(ShellDomain.today),
                    tab(ShellDomain.strength),
                    if (onAction != null)
                      Expanded(
                        child: Center(
                          child: Pressable(
                            onTap: onAction,
                            semanticLabel:
                                l?.workoutStartWorkoutFix ?? 'Actions',
                            child: Container(
                              width: S.x10,
                              height: S.x10,
                              decoration: BoxDecoration(
                                  color: p.card2, shape: BoxShape.circle),
                              child: Icon(LucideIcons.plus,
                                  size: I.lg, color: p.ink),
                            ),
                          ),
                        ),
                      ),
                    tab(ShellDomain.macros),
                    tab(ShellDomain.more),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The coach's mark: a dark disc in a lavender-to-teal ring, with the
/// sparkle inside. The same mark floats on screens that offer the coach.
class AiOrb extends StatelessWidget {
  final double size;
  const AiOrb({super.key, this.size = S.x12});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(S.half),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
            colors: [C.coachEdgeA, C.coachEdgeB, C.coachEdgeA]),
      ),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.card),
        child: Icon(LucideIcons.sparkles, size: I.md, color: p.ink),
      ),
    );
  }
}

/// One destination: icon over label. The active one has a subtle upward-fading
/// white spotlight glow and white icon/text; inactive tabs use muted grey.
class _Tab extends StatelessWidget {
  final ShellDomain domain;
  final bool on;
  final VoidCallback onTap;

  const _Tab({required this.domain, required this.on, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final label = domain.title(c);
    final p = P.of(c);
    final tabColor = on ? C.white : p.ink3;
    return Semantics(
      selected: on,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: SizedBox(
          height: S.navBar - S.x2,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (on)
                // A round pool of light centred on the tab's foot. The
                // gradient is zero at the circle's own edge, so nothing in it
                // has a boundary to see; the bar clips what falls below.
                Positioned(
                  bottom: -S.x12,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: S.x12 * 2,
                      height: S.x12 * 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              C.white.withValues(alpha: .26),
                              C.white.withValues(alpha: .16),
                              C.white.withValues(alpha: .07),
                              C.white.withValues(alpha: .02),
                              C.white.withValues(alpha: 0),
                            ],
                            stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: S.x1, vertical: S.x1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(domain.icon, size: I.lg, color: tabColor),
                    const SizedBox(height: S.half),
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: F.over.copyWith(
                            color: tabColor,
                            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
