// The shell.
//
// Home · Health · (+) · Strength · More. Home is today; Health is the longer-term
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
// The bar is the user's: a long press on a tab opens a sheet to reorder the
// tabs and hide the ones they never use (Home and More always stay: Home is the
// way back into the app, More is where Settings and the way to undo this live).
// The choice is kept in [Prefs.navTabs]; a hidden tab is still built and kept
// alive the same way, it just has no button.
//
// There is no fourth tab, and the type system is what says so — [ShellDomain]
// is a closed enum and [AppShell] takes a builder keyed by it, so "just add a
// tab for X" is a change to this file with a reviewer attached, not something
// a screen can do on its own. Anything that feels like another destination is
// a section or a pushed screen inside the domain that owns it — Sleep and
// Strain are the deep dives behind their dials on Home.

import 'package:flutter/material.dart';
import 'lucide.dart';
import 'marks.dart';

import '../l10n/app_localizations.dart';
import '../state/prefs.dart';
import 'grammar.dart';
import 'theme.dart';

/// The four destinations. The order is stored (a tab's index): the bar's own
/// order is [kDefaultTabs].
enum ShellDomain {
  today('Home', LucideIcons.house, C.dialStrain),
  strength('Strength', LucideIcons.dumbbell, C.dialStrain),
  health('Health', LucideIcons.heartPulse, C.dialStrain),
  more('More', LucideIcons.menu, C.stressLow);

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
          ShellDomain.health => 'Health',
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

/// The bar as it ships, and as "Reset" restores it.
const List<ShellDomain> kDefaultTabs = [
  ShellDomain.today,
  ShellDomain.health,
  ShellDomain.strength,
  ShellDomain.more,
];

/// Tabs that cannot be hidden.
const Set<ShellDomain> kPinnedTabs = {ShellDomain.today, ShellDomain.more};

/// The bar a saved string describes. Anything unreadable, empty or repeated
/// falls back toward the default, and a pinned tab missing from a stored list
/// is put back: a bar with no More has no way to be undone.
List<ShellDomain> tabsFromPref(String raw) {
  final out = <ShellDomain>[];
  for (final name in raw.split(',')) {
    // Macros was this tab's name before the meal tracker went.
    final wanted = name.trim() == 'macros' ? ShellDomain.health.name : name.trim();
    for (final d in ShellDomain.values) {
      if (d.name == wanted && !out.contains(d)) out.add(d);
    }
  }
  if (out.isEmpty) return [...kDefaultTabs];
  if (!out.contains(ShellDomain.today)) out.insert(0, ShellDomain.today);
  if (!out.contains(ShellDomain.more)) out.add(ShellDomain.more);
  return out;
}

String tabsToPref(List<ShellDomain> tabs) => tabs.map((d) => d.name).join(',');

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
  /// The tabs on the bar, in order. A tab that is not here is hidden.
  late List<ShellDomain> _tabs =
      tabsFromPref(Prefs.getString(Prefs.navTabs, ''));
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

  /// The sheet behind a long press on any tab.
  Future<void> _customise(BuildContext c) async {
    final next = await AppSheet.open<List<ShellDomain>>(c,
        scroll: true, builder: (_) => NavBarEditor(tabs: _tabs));
    if (next == null || !mounted) return;
    setState(() => _tabs = next);
    Prefs.setString(Prefs.navTabs, tabsToPref(next));
    // Hiding the tab you are standing on would leave the bar with nothing lit.
    if (!next.contains(_current)) _select(ShellDomain.today);
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
                  // The Health tab paints up behind the status bar.
                  top: _current != ShellDomain.health,
                  child: IndexedStack(
                    index: _current.index,
                    children: [
                      // An unvisited tab is an empty box, not a built screen.
                      for (final d in ShellDomain.values)
                        if (_built.contains(d))
                          // A tab kept alive off screen stops its animations.
                          TickerMode(
                            enabled: d == _current,
                            child: widget.builder(c, d),
                          )
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
                    tabs: _tabs,
                    current: _current,
                    onTap: _select,
                    onLongPress: () => _customise(c),
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
  final List<ShellDomain> tabs;
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;
  final VoidCallback? onAction, onAi, onLongPress;

  const _TabBar(
      {required this.tabs,
      required this.current,
      required this.onTap,
      this.onLongPress,
      this.onAction,
      this.onAi});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    Widget tab(ShellDomain d) => Expanded(
          child: _Tab(
              domain: d,
              on: d == current,
              onTap: () => onTap(d),
              onLongPress: onLongPress),
        );
    // The (+) sits in the middle of whatever is left.
    final plusAt = (tabs.length + 1) ~/ 2;
    final plus = onAction == null
        ? null
        : Expanded(
            child: Center(
              child: Pressable(
                onTap: onAction,
                onLongPress: onLongPress,
                semanticLabel: l?.workoutStartWorkoutFix ?? 'Actions',
                child: Container(
                  width: S.x10,
                  height: S.x10,
                  decoration:
                      BoxDecoration(color: p.card2, shape: BoxShape.circle),
                  child: Icon(LucideIcons.plus, size: I.lg, color: p.ink),
                ),
              ),
            ),
          );
    // A dark rounded rectangle floating over the tabs. Its only decoration is
    // the rim: a hairline lit at the top-left corner and gone by a third of
    // the way round, as if one light sat above and to the left, and dark
    // everywhere past it. No glow, no
    // shadow. The selected tab carries a soft pool of light at its foot.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: R.rXxl,
        // An ellipse centred on the corner: long along the top, gone before
        // the foot of the left side.
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1,
          transform: const _RimLight(),
          colors: [
            C.white.withValues(alpha: .34),
            C.white.withValues(alpha: .13),
            C.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.42, 0.8],
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
                    for (var i = 0; i < tabs.length; i++) ...[
                      if (i == plusAt) ?plus,
                      tab(tabs[i]),
                    ],
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

/// Stretches the rim's light sideways from the bar's top-left corner.
class _RimLight extends GradientTransform {
  const _RimLight();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.identity()
        ..translateByDouble(bounds.left, bounds.top, 0, 1)
        ..scaleByDouble(2.4, 1, 1, 1)
        ..translateByDouble(-bounds.left, -bounds.top, 0, 1);
}

/// The coach's orb: a dark disc in a lavender-to-teal ring, with the
/// [CoachMark] inside. The same orb floats on screens that offer the coach.
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
        child: Center(
          child: CoachMark(
              size: size == S.x12 ? I.md : size * .42, color: p.ink),
        ),
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
  final VoidCallback? onLongPress;

  const _Tab(
      {required this.domain,
      required this.on,
      required this.onTap,
      this.onLongPress});

  @override
  Widget build(BuildContext c) {
    final label = domain.title(c);
    final p = P.of(c);
    final tabColor = on ? C.white : p.ink3;
    return Semantics(
      selected: on,
      child: Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
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

/// The sheet a long press on the bar opens: drag to reorder, switch a tab off
/// to hide it. Home and More cannot be switched off. Pops the new bar.
class NavBarEditor extends StatefulWidget {
  final List<ShellDomain> tabs;
  const NavBarEditor({super.key, required this.tabs});

  @override
  State<NavBarEditor> createState() => _NavBarEditorState();
}

class _NavBarEditorState extends State<NavBarEditor> {
  // Hidden tabs ride along at the foot, in their usual order, so switching one
  // back on puts it somewhere sensible.
  late final List<ShellDomain> _order = [
    ...widget.tabs,
    for (final d in kDefaultTabs)
      if (!widget.tabs.contains(d)) d,
  ];
  late final Set<ShellDomain> _on = {...widget.tabs};

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x5, S.gutter, S.x4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('CUSTOMISE TABS', style: F.caps.copyWith(color: p.ink)),
          const SizedBox(height: S.x1),
          Text('Drag to reorder. Switch off the ones you do not use.',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(height: S.x3),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            onReorder: (from, to) => setState(() {
              if (to > from) to--;
              _order.insert(to, _order.removeAt(from));
            }),
            itemBuilder: (c, i) {
              final d = _order[i];
              final pinned = kPinnedTabs.contains(d);
              return Padding(
                key: ValueKey(d),
                padding: const EdgeInsets.symmetric(vertical: S.x1),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: SizedBox(
                      width: S.tap,
                      height: S.tap,
                      child: Icon(LucideIcons.gripVertical,
                          size: I.md, color: p.ink3),
                    ),
                  ),
                  Icon(d.icon, size: I.md, color: p.ink2),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(d.title(c),
                        style: F.body.copyWith(
                            color: _on.contains(d) ? p.ink : p.ink3)),
                  ),
                  if (pinned)
                    Text('Always on', style: F.cap.copyWith(color: p.ink3))
                  else
                    AppSwitch(
                      _on.contains(d),
                      (v) => setState(() => v ? _on.add(d) : _on.remove(d)),
                      semanticLabel: d.title(c),
                    ),
                ]),
              );
            },
          ),
          const SizedBox(height: S.x3),
          BigButton(
            l?.actionSave ?? 'Save',
            color: C.white,
            onTap: () => Navigator.of(c).pop<List<ShellDomain>>([
              for (final d in _order)
                if (_on.contains(d)) d,
            ]),
          ),
          const SizedBox(height: S.x2),
          BigButton(
            'Reset to default',
            soft: true,
            onTap: () =>
                Navigator.of(c).pop<List<ShellDomain>>([...kDefaultTabs]),
          ),
        ]),
      ),
    );
  }
}
