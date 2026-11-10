// The token boundary. Nothing below this file defines a colour, a size, a
// radius or a duration — everything else in lib/ui2 spends what is declared
// here, and `test/ui2_tokens_test.dart` fails the build if it doesn't.
//
// Three things this file owns that the previous design system did not:
//
//   1. CONTRAST IS SOLVED, NOT ASSERTED. Muted ink and every accent used as
//      text or as a fill are pushed to a WCAG AA (4.5:1) floor by `P.on` /
//      `P.fill`, against the worst surface they can legally land on. The old
//      caption token measured 2.20–2.71:1 across 223 call sites; a token that
//      *can* be misused eventually is. `test/ui2_contrast_test.dart` proves
//      the floor holds in both themes for every accent.
//   2. MOTION IS GATED ONCE. `motion()` and `animate()` are the only way to
//      get a non-zero duration, and they return `Duration.zero` when the
//      platform asks for reduced motion. No call site can opt out, and the
//      tokens test forbids `.repeat(` anywhere in lib/ui2 so an infinite loop
//      can never survive the gate. That gate reaches the NAVIGATOR too:
//      `buildTheme` installs a `pageTransitionsTheme` that returns the page
//      unanimated (22 routes were sliding at full duration under Reduce
//      Motion), and `sheetMotion()` does the same for the four modal sheets,
//      which do not consult a theme at all. Dialogs still use Flutter's own
//      fade-and-scale — small, centred, and the least nauseogenic of the
//      three — so they are deliberately left alone.
//   3. BOTH THEMES ARE DESIGNED. Every colour is defined for light and dark in
//      the same expression. There is no token that exists only inside a
//      dark-mode branch.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// ── COLOUR ────────────────────────────────────────────────────────────────
///
/// Raw pigment. These are *not* safe to paint text with directly — most of
/// them fail AA on white. Run them through [P.on] (accent as text) or
/// [P.fill] (accent as a filled surface under [P.inkOn]) first.
class C {
  // ── Brand ── (DESIGN.md §2)
  //
  // One action colour. Replaced neon lime/volt with clean white to fit the design system.
  static const volt = Color(0xFFFFFFFF);

  /// Signal, not brand. NOT a red any more: red text and red lines on a dark
  /// card were lightened to a salmon pink nobody wanted. Destructive actions
  /// are a solid [danger] fill; the only other red is the recovery dial's.
  static const coral = dialStrain;

  /// Secondary dark chips and inactive controls on cream.
  static const slate = Color(0xFF3A444B);

  /// The two ends of the monochrome system. `char` is the dark ink on every
  /// light fill and the chrome on cream; `cream` is the light canvas and the
  /// ScallopBadge disc in BOTH themes.
  static const char = Color(0xFF0F1014);
  static const cream = Color(0xFFF2F1EC);

  // ── the data palette ── domain hues for charts, aurora, hero glow.
  // Every one clears 4.5:1 as text on the dark card2 and as a fill under
  // dark ink; in light they pass through [P.on] like any accent.
  /// The Total sleep hero's aurora (the one aurora left in the app) and the
  /// hypnogram's light-sleep step. Nothing else is lavender.
  static const lavender = Color(0xFFA99BFF);

  /// Cycle tracking's own hue.
  static const rose = Color(0xFFFF7A9A);

  /// The sync arrow.
  static const amber = Color(0xFFFFB547);

  /// Food: the Macros tab's one accent, and every control on it.
  static const foodRed = Color(0xFFE61C24);

  /// The one red for destructive actions and errors: a SOLID fill under white
  /// ink (4.6:1) or a small mark, never text. Red text on a dark card has to be
  /// lightened to stay readable, and lightened it is salmon pink, which is why
  /// nothing sets words in red any more.
  static const danger = foodRed;

  // Former Volt domain hues, now the redesign's.
  static const sky = dialStrain;
  static const sage = stressLow;
  static const aqua = stressLow;

  /// The hypnogram's lavender ramp, palest to deepest: awake, REM,
  /// light, deep. `lavender` is the light-sleep step; these are the other
  /// three. The painter solves each against the surface, so they are the HUE,
  /// not the lightness that is finally drawn.
  static const sleepAwake = Color(0xFFE6E1FF);
  static const sleepRem = Color(0xFFC7BDFF);
  static const sleepDeep = Color(0xFF6F5CF0);

  /// The bottom of the HR-zone ramp (slate-blue → sky → volt → amber →
  /// coral). The one hue here that is not a domain colour: zone 1 has to sit
  /// below [sky] without being grey, and nothing else needs it.
  static const blueSoft = Color(0xFF93A9C9);

  // ── the old accent names, kept as aliases ──
  //
  // Hundreds of call sites name these, so they stay, but each resolves to a
  // hue of the redesign palette (DESIGN.md §2.4) by what it was used FOR:
  // "good" is the optimal green, "low / destructive" the strain blue (heart rate's hue), the
  // blues are strain and activity, indigo is sleep, calm is the stress-low
  // blue, a warning is the "worse" orange. No off-palette colour survives.
  static const green = optimal;
  static const red = dialStrain;
  static const blue = dialStrain;
  static const purple = dialStrain;
  static const indigo = dialSleep;
  static const teal = stressLow;
  static const orange = strainDown;
  static const yellow = recYellow;
  static const pink = rose;

  /// The route ramp, and only the route ramp.
  ///
  /// Brighter and more saturated than the UI accents on purpose: this is the
  /// one mark in the app that is drawn over an arbitrary photograph and a
  /// darkened basemap rather than over a known surface, and the UI greens and
  /// reds — tuned to clear 4.5:1 as TEXT on a card — go muddy there.
  ///
  /// Deliberately NOT in [all]. `all` is the set the contrast sweep measures
  /// as ink and as fill, and these are neither: they are a line on a picture.
  /// Putting them in would be asking the wrong question of them.
  ///
  /// Slow to fast it runs blue, sky, amber, orange: the same direction as the
  /// in-app route (blue slower, orange faster), and no red against green for
  /// a colour-blind reader to lose.
  static const routeFast = Color(0xFFFF8A30);
  static const routeMid = Color(0xFFFFC83D);
  static const routeHard = Color(0xFF7DD3FC);
  static const routeSlow = Color(0xFF3D9BFF);

  /// The basemap's two ends, which is the whole of the map's styling: every
  /// tile pixel is mapped onto the line between them by `_themeFilter`.
  ///
  /// What makes the map READABLE is the distance between these two, not how
  /// low either one is. Both ends have been wrong once:
  ///
  ///   · ceiling `#4A5568` — OSM's land polygon is near-white and lands on
  ///     the ceiling, so the whole card became a mid-grey slab.
  ///   · ceiling `#232B39` — dark enough that land, water and roads all
  ///     collapsed into each other and the map vanished entirely. On a card
  ///     with no photo the map IS the content, so that is worse.
  ///
  /// This pair keeps the card unmistakably dark while leaving enough range
  /// between water, land and roads to read as a place. It is also the only
  /// lever there is on the labels and street names, which are rendered into
  /// the raster and cannot be asked for separately — they sit near the
  /// ceiling, so a ceiling this far down leaves them as texture, not type.
  static const mapFloor = Color(0xFF0A1018);
  static const mapCeil = Color(0xFF44536D);

  // neutrals — warm greys between char and cream, matching the surfaces. Only
  // the steps something still names; the rest went with the aliases.
  static const n900 = char;
  static const n500 = Color(0xFF5F646D);
  static const n400 = Color(0xFF8B9099);

  static const white = Color(0xFFFFFFFF);

  /// What each domain's accent resolves to. The active tab is always volt;
  /// these are the redesign hues (DESIGN.md §2.4): today, activity and heart
  /// are the strain blue, sleep the sleep blue, mind the calm stress-low
  /// blue, food red.
  static const domHome = dialStrain;
  static const domSleep = dialSleep;
  static const domHealth = dialStrain;
  static const domFood = foodRed;
  static const domMove = dialStrain;
  static const domMind = stressLow;

  // ── the three dials ── the Home screen's score hues, one per dial. Sleep is
  // a steel blue, strain a saturated blue, and recovery is the traffic light
  // its own colour coding asks for: green 67–99, yellow 34–66, red 1–33.
  static const dialSleep = Color(0xFF7BA1BB);
  static const dialStrain = Color(0xFF0093E7);

  // The strain screen's own set, read off its reference: the three strain
  // bands Trend View counts days into (the top band is [dialStrain]), the
  // down-arrow orange, and the five HR zones as the stacked cards draw them.
  static const strainStrenuous = Color(0xFF0480CA);
  static const strainModerate = Color(0xFF066DA7);
  static const strainLight = Color(0xFF0A5A8B);
  static const strainDown = Color(0xFFFFA624);
  static const refZone1 = Color(0xFFAEC2CD);
  static const refZone2 = Color(0xFF479AC2);
  static const refZone3 = Color(0xFF59B896);
  static const refZone4 = Color(0xFFFBAC5D);
  static const refZone5 = Color(0xFFFF6422);

  // Stress Monitor: the three levels, and the warm stop the line and gauge pass
  // through between green and orange.
  static const stressLow = Color(0xFF70AADA);
  static const stressMedium = Color(0xFF02C986);
  static const stressWarm = Color(0xFFC9BC3A);
  static const stressHigh = Color(0xFFFFA624);

  // Sleep trends: deep (SWS) and REM as they stack, and the grey the bars that
  // are not the one in focus go.
  static const trendSws = Color(0xFFFA96F9);
  static const trendRem = Color(0xFFAC5AED);
  static const barGrey = Color(0xFF63676A);
  static const recGreen = Color(0xFF16EC06);
  static const recYellow = Color(0xFFFFDE00);
  static const recRed = Color(0xFFFF0026);

  /// A sleep-contributor bar: poor / sufficient / optimal.
  static const optimal = Color(0xFF00F19F);
  static const poor = Color(0xFFFFA733);

  /// The activity blocks in My Day: the night, and a session.
  static const blockSleep = Color(0xFF7F9DB5);
  static const blockSession = Color(0xFF3B8DE0);

  /// The coach card's border runs lavender into teal.
  static const coachEdgeA = Color(0xFF7E57C2);
  static const coachEdgeB = Color(0xFF3FA7B5);

  /// The coach's ground, top to bottom: a warm dusk grey under the header,
  /// slate behind the first lines, then near-black for the rest of the chat.
  static const coachSky = [
    Color(0xFF786C62),
    Color(0xFF4B5158),
    Color(0xFF29343F),
    Color(0xFF161B20),
    Color(0xFF111316),
  ];
  static const coachSkyStops = [0.0, 0.18, 0.36, 0.58, 1.0];

  /// The sleep recommendation's panel: a pale mint ground on the white sheet,
  /// inked in [char]. A ground, not an accent, so it is not in [all].
  static const mint = Color(0xFFDFF8EF);

  /// Every accent the contrast test sweeps. Adding a colour above without
  /// adding it here means it ships unverified.
  static const all = <Color>[
    volt, coral, slate, lavender, sky, rose, sage, amber, foodRed, aqua, blueSoft,
    sleepAwake, sleepRem, sleepDeep,
    green, blue, purple, orange, red, teal, yellow, pink, indigo,
    domHome, domSleep, domHealth, domFood, domMove, domMind,
    dialSleep, dialStrain, recGreen, recYellow, recRed, optimal, poor,
    blockSleep, blockSession,
  ];
}

/// ── SURFACES + LEGIBLE INK ────────────────────────────────────────────────
///
/// Brightness-resolved. `P.of(context)` in every build method.
class P {
  final bool dark;
  const P(this.dark);

  static P of(BuildContext c) => P(Theme.of(c).brightness == Brightness.dark);

  // ── surfaces ── Slate in dark: a blue-grey page with lifted grey cards,
  // the way a wearable's companion app reads at night. "Cream" in light.
  Color get bg => dark ? const Color(0xFF1A1F23) : C.cream;
  Color get card => dark ? const Color(0xFF2B3136) : C.white;
  Color get card2 => dark ? const Color(0xFF353B41) : const Color(0xFFE9E8E2);
  Color get line => dark ? const Color(0xFF3D444A) : const Color(0xFFDCDBD4);
  Color get track => dark ? const Color(0xFF3A4046) : const Color(0xFFE2E1DA);

  /// The top of the page gradient, above [bg]. Only the dark theme has one.
  Color get bgTop => dark ? const Color(0xFF283239) : C.cream;

  Color get ink => dark ? const Color(0xFFFFFFFF) : C.char;
  Color get ink2 => dark ? const Color(0xFFC6CBD0) : const Color(0xFF474B53);

  /// The muted caption ink. Hand-solved to clear 4.5:1 on [card2], the darkest
  /// (light theme) / lightest (dark theme) surface it can sit on — so it is
  /// legible on every surface, not just the one it was eyeballed against.
  Color get ink3 => dark ? const Color(0xFFAAB0B6) : const Color(0xFF5F646D);

  /// The frosted-glass tint: the card at 72%, under a 24 px blur. Its solid
  /// fallback (high contrast, `Perf.lowGlass`) is this blended over [bg].
  Color get glass => card.withValues(alpha: .72);

  /// Black chrome on cream, cream chrome on char — the round icon buttons,
  /// the active SubTabs pill, snackbars. Monochrome on purpose: volt is
  /// spent on action, not on "selected".
  Color get inverse => dark ? const Color(0xFFF4F4F1) : C.char;
  Color get onInverse => dark ? C.char : const Color(0xFFF4F4F1);

  /// The ink that goes on top of a [fill] — whichever of dark ink or white
  /// clears 4.5:1 on it, dark preferred. Volt, coral and every data hue take
  /// dark ink; only a fill dark enough to have been solved for white gets it.
  Color inkOn(Color fill) =>
      contrast(C.char, fill) >= _aa ? C.char : C.white;


  /// [accent] rendered as TEXT on one of this brightness' surfaces, nudged
  /// toward the page ink until it clears [_aa] against the worst legal
  /// surface ([card2]). `C.volt` on cream measures 1.3:1 raw; `on(C.volt)`
  /// clears 4.5:1 and still reads as a green.
  ///
  /// Solved TWICE, against the two worst surfaces it can land on. `card2` is
  /// the flat one; the other is `wash(accent)` over it — the Pill and the
  /// active SubTabs chip put this ink on a tinted background nothing was
  /// solving against, and five of six accents measured 4.30–4.49 there. The
  /// solver only ever nudges toward the page ink, so clearing the second
  /// surface cannot un-clear the first.
  Color on(Color accent) {
    final toward = dark ? ink : C.n900;
    final flat = _solve(accent, toward, card2, dark);
    return _solve(flat, toward, Color.alphaBlend(wash(accent), card2), dark);
  }

  /// [accent] rendered as a FILLED surface under [inkOn]. Buttons, chips,
  /// CTA badges.
  ///
  /// The pure pigment whenever dark ink clears [_aa] on it — volt stays volt
  /// instead of being darkened into olive for white text. Only a pigment too
  /// dark for dark ink (slate, say) falls back to the old solve: darkened
  /// until WHITE clears [_aa], and [inkOn] then picks white.
  Color fill(Color accent) => contrast(C.char, accent) >= _aa
      ? accent
      : _solve(accent, const Color(0xFF000000), C.white, false);

  /// A tinted wash of [accent] — the InsightCard / Pill / active-tab
  /// background. Never carries text of its own colour; pair it with [on].
  ///
  /// [strength] is capped at 1: full strength is the tint [on] and [ink3] were
  /// solved against, and a caller asking for 1.6 was pushing muted ink to
  /// 2.99:1 on its own card. A wash darker than a wash is a fill.
  Color wash(Color accent, {double strength = 1}) =>
      accent.withValues(alpha: (dark ? .18 : .11) * strength.clamp(0.0, 1.0));

  /// The brightest point of an AuroraTile's gradient of [hue], already
  /// blended over the card: the surface the tile's text has to clear 4.5:1
  /// on. Solved, not chosen — the hue's alpha is the most the page [ink] can
  /// take, capped where a colour field stops being a wash and becomes a fill.
  Color aurora(Color hue) {
    final key = Object.hash(hue.toARGB32(), dark, 'aurora');
    final hit = _cache[key];
    if (hit != null) return hit;
    Color at(double a) => Color.alphaBlend(hue.withValues(alpha: a), card);
    var lo = 0.0, hi = dark ? .55 : .45;
    if (contrast(ink, at(hi)) < _aa) {
      for (var i = 0; i < 24; i++) {
        final mid = (lo + hi) / 2;
        if (contrast(ink, at(mid)) >= _aa) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      hi = lo;
    }
    return _cache[key] = at(hi);
  }

  /// Elevation. Dark has no shadow and no outline: depth is the tonal grading in DESIGN.md §2.2.
  /// Light gets one soft shadow: 0 / 8 / 24, ink at 6%, deepening per level.
  List<BoxShadow> el(int level) {
    if (level <= 0 || dark) return const [];
    return [
      BoxShadow(
        color: C.char.withValues(alpha: .06 * level.clamp(1, 3)),
        blurRadius: 24.0 * level,
        offset: Offset(0, 8.0 * level),
      ),
    ];
  }

  // ── the solver ──────────────────────────────────────────────────────────
  // WCAG 2.1 AA for body text. Non-text UI is allowed 3:1, but a caption that
  // is "technically an indicator" is how the 2.20:1 tokens got shipped, so
  // there is one floor here and it is the strict one.
  static const _aa = 4.5;

  static final _cache = <int, Color>{};

  /// Binary-search the lerp from [c] toward [toward] for the first colour that
  /// clears [_aa] against [against]. 24 steps is well past 8-bit resolution.
  static Color _solve(Color c, Color toward, Color against, bool dark) {
    final key = Object.hash(c.toARGB32(), toward.toARGB32(),
        against.toARGB32(), dark);
    final hit = _cache[key];
    if (hit != null) return hit;
    var out = c;
    if (contrast(c, against) < _aa) {
      var lo = 0.0, hi = 1.0;
      for (var i = 0; i < 24; i++) {
        final mid = (lo + hi) / 2;
        if (contrast(Color.lerp(c, toward, mid)!, against) >= _aa) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      out = Color.lerp(c, toward, hi)!;
    }
    // Bounded: one entry per (accent, brightness) pair actually used, and the
    // accent set is a compile-time constant.
    _cache[key] = out;
    return out;
  }

  /// WCAG 2.1 contrast ratio, 1.0 … 21.0. Public so the contrast test and any
  /// future palette work measure with exactly the same function the tokens do.
  /// Luminance is `Color.computeLuminance()` — same WCAG formula, no need to
  /// carry our own copy of it.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// ── TYPE ── 7 steps + 5 numerals, tabular figures on anything that changes ─
///
/// Words are Figtree, numbers are D-DIN, both bundled (SIL OFL,
/// assets/fonts) so iOS, Android and the golden tests render the same design.
/// D-DIN is bundled as a digits-only face, [numerals]. Only a number that
/// stands on its own uses it (a dial's score, a card's figure, a chart's
/// labels): the numeral steps below, and [num] for a word style that holds
/// nothing but a number. A digit inside a sentence stays in Figtree, where it
/// sits with the words around it. Figtree has no Cyrillic: Russian falls
/// through to the bundled Manrope, and anything past that to the platform's
/// Helvetica Neue / Helvetica / Arial.
///
/// Headlines are short, uppercase and set close, tracked at about 3 % ([caps]); body text is
/// Figtree semibold; numerals are D-DIN bold.
class F {
  static const family = 'Figtree';
  static const numerals = 'DDINNums';
  static const _f = family;
  static const _n = numerals;
  static const _nb = [
    family,
    'Manrope',
    'Helvetica Neue',
    'Helvetica',
    'Arial',
  ];
  static const _fb = [
    'Manrope',
    'Helvetica Neue',
    'Helvetica',
    'Arial',
  ];
  static const _tab = [FontFeature.tabularFigures()];

  // The 7 steps.
  static const display = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 36,
      height: 42 / 36,
      fontWeight: FontWeight.w500,
      letterSpacing: -1.0);
  static const t1 = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 28,
      height: 34 / 28,
      fontWeight: FontWeight.w500,
      letterSpacing: -.7);
  static const t2 = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w600,
      letterSpacing: -.5);
  static const head = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 17,
      height: 24 / 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -.4);
  static const body = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w600,
      letterSpacing: -.25);
  static const cap = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w600,
      letterSpacing: -.15);
  /// Callers uppercase it.
  static const over = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w700,
      letterSpacing: .3);

  /// Widely tracked capitals: card titles, dial names, section kickers.
  /// Callers uppercase it.
  static const caps = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w700,
      letterSpacing: .35);

  /// The LOCUS wordmark, in Super Bubble: the one place the app's words are
  /// not Figtree. Only the word LOCUS is ever set in it, so no fallback.
  static const wordmark = TextStyle(
      fontFamily: 'SuperBubble',
      fontSize: 24,
      height: 1,
      fontWeight: FontWeight.w400,
      letterSpacing: 1.5);

  // Numerals — a parallel display ramp. Tabular, so a live value never jitters
  // its own layout as digits change. Units sit beside them in cap/body, ink3.
  /// The figure inside a dial.
  static const n80 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 80,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.8,
      fontFeatures: _tab);
  static const n64 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 64,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.6,
      fontFeatures: _tab);
  static const n48 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 48,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.5,
      fontFeatures: _tab);
  static const n34 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 34,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.3,
      fontFeatures: _tab);
  static const n24 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 24,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.1,
      fontFeatures: _tab);
  static const n17 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 17,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.1,
      fontFeatures: _tab);

  // ── The dial detail screens' measured steps (see [DC]). ──
  static const dNav = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1);
  static const dLabel = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.05);
  static const dHero = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 14,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6);
  static const dTitle = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 21,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1);
  static const dText = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 13,
      height: 1.25,
      fontWeight: FontWeight.w500,
      letterSpacing: 0);
  static const dBody = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w500,
      letterSpacing: 0);

  /// The Daily Outlook strip's words: 14 medium, a touch tight.
  static const dOutlook = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 14,
      height: 1,
      fontWeight: FontWeight.w500,
      letterSpacing: -.25);
  static const dHead = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: -.1);
  static const dInsight = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.05);
  static const dLegend = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 11.5,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: 0);
  static const dTiny = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: 0);
  static const nDial = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 80,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      fontFeatures: _tab);
  static const nDialPct = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 48,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFeatures: _tab);
  static const nCard = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 28,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      fontFeatures: _tab);
  static const nRow = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 18,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
      fontFeatures: _tab);
  static const nWeek = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 15.5,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFeatures: _tab);
  static const nImpact = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 22,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFeatures: _tab);
  static const nSmall = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 14,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFeatures: _tab);
  static const nTiny = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 12,
      height: 1,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      fontFeatures: _tab);

  /// [style] (a word style) for a number that stands alone: D-DIN digits, with
  /// everything else as it was.
  static TextStyle num(TextStyle style) =>
      style.copyWith(fontFamily: _n, fontFamilyFallback: _nb);
}

/// ── THE DIAL DETAIL SCREENS ── (Sleep, Recovery, Behavior Insights)
///
/// Measured off the reference recordings (590 px across = 393 dp, so 1.5 px to
/// the dp). These screens are always char ([AlwaysChar]), so the page ground and
/// its cards are fixed colours rather than the theme's. A card is a veil of
/// white over the page, which is why it darkens toward the foot of the screen.
/// Locus Age: the blob's tones by how the age compares, and the page's type.
class AC {
  static const page = Color(0xFF07090B);
  static const card = Color(0xFF1C2024);
  static const cardOpen = Color(0xFF16191D);
  static const banner = Color(0xFF17283A);
  static const chip = Color(0xFF17283A);
  static const coach = Color(0xFF9B8CFF);

  static const olderTop = Color(0xFF4F93C9);
  static const olderBottom = Color(0xFF86DCC4);
  static const olderText = Color(0xFF79C4F0);
  static const tealTop = Color(0xFF3AA3A0);
  static const tealBottom = Color(0xFF5ACBB6);
  static const tealText = Color(0xFF7FE0D0);
  static const greenTop = Color(0xFF45B97A);
  static const greenBottom = Color(0xFF5CD892);
  static const greenText = Color(0xFF6FE3A1);
  static const lockedTop = Color(0xFF5E7280);
  static const lockedBottom = Color(0xFF85A0A2);

  static const blobGlow = Color(0x38000000);
  static const blobCore = Color(0xFF040506);
  static const blobCore86 = Color(0xDB040506);
  static const blobCore40 = Color(0x66040506);
  static const blobCore0 = Color(0x00040506);
  static const blobSpeck = Color(0xFFEFFFFA);

  static const segAmber = Color(0xFFF2B15C);
  static const segGreen = Color(0xFF5BE39B);
  static const segGrey = Color(0xFF8F9296);

  static final ageNum = F.n48.copyWith(fontSize: 40);
  static final ageNumSmall = F.n24.copyWith(fontSize: 24);
  static final ageLabel = F.dLabel.copyWith(fontSize: 13);
  static final ageLabelSmall = F.dLabel.copyWith(fontSize: 9);
  static final ageDelta = F.dBody.copyWith(fontSize: 13, fontWeight: FontWeight.w600);
  static final sideNum = F.n17.copyWith(fontSize: 18);
  static final section = F.dTitle.copyWith(fontSize: 20, fontWeight: FontWeight.w500);
  static final rowTitle = F.dBody.copyWith(fontSize: 15, fontWeight: FontWeight.w500);
  static final rowValue = F.nTiny.copyWith(fontSize: 13);
  static final rowYears = F.n17.copyWith(fontSize: 16);
  static final body = F.dBody.copyWith(fontSize: 13, height: 1.35);
  static final barLabel = F.dLabel.copyWith(fontSize: 9, letterSpacing: .4);
  static final barLabelMid = F.dBody.copyWith(fontSize: 11, height: 1.2);
}

class DC {
  static const bgTop = Color(0xFF283238);
  static const bgMid = Color(0xFF15181F);
  static const bgFoot = Color(0xFF0F1317);

  static const ink = Color(0xFFEBECEF);
  static const ink2 = Color(0xFFA6AAAE);
  static const ink3 = Color(0xFF85898D);

  static const card = Color(0x10FFFFFF);
  static const weekCard = Color(0x1AFFFFFF);
  static const edge = Color(0x1FFFFFFF);
  static const line = Color(0x1CFFFFFF);
  static const grid = Color(0x12FFFFFF);
  static const well = Color(0xFF090A0D);
  static const inset = Color(0x66000000);
  static const track = Color(0xFF32373D);
  static const tierOff = Color(0xFF383C40);
  static const tierMid = Color(0xFF8F8E93);
  static const hatchBase = Color(0x0AFFFFFF);
  static const hatchLine = Color(0x1CFFFFFF);
  static const typical = Color(0x2EFFFFFF);
  static const pressGlow = Color(0xFF2C3034);
  static const column = Color(0x14FFFFFF);
  static const columnFoot = Color(0x24FFFFFF);
  static const pastBar = Color(0xFF636669);
  static const needMin = Color(0xFF4A5053);
  static const weekHole = Color(0xFF2A2E32);
  static const dim = Color(0xFF465058);
  static const shade = Color(0x8C0B0D10);

  /// The Daily Outlook strip: warm tan into slate, sampled off the reference,
  /// and the near-white of its two glyphs.
  static const outlookWarm = Color(0xFF8A8273);
  static const outlookMid = Color(0xFF686866);
  static const outlookSlate = Color(0xFF394753);
  static const outlookGlyph = Color(0xE6FFFFFF);

  static const stageAwake = Color(0xFFC8C8C8);
  static const stageLight = Color(0xFFA4A2F2);
  static const stageDeep = Color(0xFFFB96F6);
  static const stageRem = Color(0xFFAE58EB);
  static const line2 = Color(0xFF64A8E8);

  static const body = Color(0xFFC4C6C9);
  static const pure = Color(0xFFFFFFFF);
  static const scrim = Color(0xFF000000);
  static const sheetTop = Color(0xFF293741);
  static const sheetFoot = Color(0xFF182226);
  static const chip = Color(0xFF3A4249);
  static const field = Color(0xFF2E353B);
  static const grab = Color(0xFF56616A);

  /// The daily cards: the halo round a card, and the coin's metal.
  static const cardHalo = Color(0x4D000000);
  static const coinHi = Color(0xFF7C7F84);
  static const coinLo = Color(0xFF4B4E53);
  static const coinEdgeHi = Color(0xFF5A5D61);
  static const coinEdgeLo = Color(0xFF2B2D30);
  static const coinInk = Color(0xFF2F3134);
  static const coinShine = Color(0x38FFFFFF);
  static const coinShade = Color(0x73000000);

  /// The week's bars on a recovery card, lit down the left edge.
  static const barEdge = Color(0xFF696A6E);
  static const barFace = Color(0xFF595A5E);
  static const barSide = Color(0xFF514F54);

  /// The goal cards' box.
  static const boxFront = Color(0xFF4E5256);
  static const boxInner = Color(0xFF63686C);
  static const boxLedge = Color(0xFF6E7376);
  static const boxLidHi = Color(0xFF5B5F62);
  static const boxLidLo = Color(0xFF494D50);
  static const boxLidEdge = Color(0xFF3F4346);
  static const boxInk = Color(0xFF34383B);
  static const boxGlow = Color(0xFFC277CC);
  static const boxGlowHi = Color(0xFFE3A6EA);
  static const hurtChip = Color(0x33FFA733);
  static const helpChip = Color(0x3300F19F);
  static const sparkChip = Color(0xFF263B50);
  static const adviceTop = Color(0xFF1E3040);
  static const adviceFoot = Color(0xFF16222C);
  static const heroGlow = Color(0xFF3A3F49);
  static const journalBody = Color(0xFF5B6065);
  static const journalEdge = Color(0xFF3B3F44);
}

/// ── PROFILE ── the Data Highlights page, measured off its reference at
/// 1.5 px to the dp. The ground and cards are the dial screens' ([DC]).
class PH {
  static const gold = Color(0xFFF4D694);
  static const well = Color(0xFF1C2024);
  static const pill = Color(0xFF33373B);
  static const hatch = Color(0x3DFFFFFF);

  // The page.
  static const barHeight = 68.0;
  static const toHeading = 21.0;
  static const headingGap = 15.0;
  static const cardGap = 27.0;
  static const hair = 2 / 3;
  static const cardFoot = 9.33;

  // The period switch.
  static const periodHeight = 44.67;
  static const periodInset = 4.67;

  // The circles, the streaks and the rows, top to bottom.
  static const toRings = 28.0;
  static const ring = 81.33;
  static const ringStroke = 5.33;
  static const ringToLabel = 8.0;
  static const toStreaks = 27.0;
  static const kickerGap = 9.33;
  static const toBadges = 19.0;
  static const streakNudge = 2.67;
  static const badge = 38.67;
  static const badgeStroke = 1.1;
  static const badgeToDays = 9.67;
  static const toNotable = 26.67;
  static const toFirstRow = .67;
  static const rowHeight = 78.0;
  static const badgeToTitle = 15.33;
  static const unitGap = 5.0;
  static const pctGap = 1.0;

  // The detected-activity list.
  static const pickTop = Color(0xFF1F242A);
  static const pickGround = Color(0xFF15181D);
  static const pickHandle = 57.33;
  static const pickSearch = 43.67;
  static const pickRow = 50.67;
  static const pickGap = 7.0;
  static const pickPad = 14.67;
  static const ruleToPick = 14.0;
  static const pickToRule = 18.0;

  // Activity Summary.
  static const toTotal = 22.67;
  static const totalGap = 2.67;
  static const toHeader = 18.67;
  static const toFirstActivity = 27.33;
  static const activityLine = 24.0;
  static const activityIcon = 20.67;
  static const activityIconGap = 8.67;
  static const lineToBar = 7.67;
  static const bar = 9.33;
  static const barToRule = 27.33;
  static const ruleToRow = 26.67;
  static const collapsedRows = 3;

  static const period = TextStyle(
      fontFamily: F.family,
      fontFamilyFallback: F._fb,
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.05);
  static const kicker = TextStyle(
      fontFamily: F.family,
      fontFamilyFallback: F._fb,
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.05);
  static const figure = TextStyle(
      fontFamily: F.numerals,
      fontFamilyFallback: F._nb,
      fontSize: 23,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: .3,
      fontFeatures: [FontFeature.tabularFigures()]);
  /// A daily card's sentence, set small enough to leave its coin room.
  static const cardBody = TextStyle(
      fontFamily: F.family,
      fontFamilyFallback: F._fb,
      fontSize: 12.5,
      height: 16.2 / 12.5,
      fontWeight: FontWeight.w500);

  /// The sentence of a card that is only words.
  static const cardWords = TextStyle(
      fontFamily: F.family,
      fontFamilyFallback: F._fb,
      fontSize: 14.5,
      height: 19.5 / 14.5,
      fontWeight: FontWeight.w500);

  /// The detected-activity sheet: its title, search box, line and rules.
  static const pickTitle = TextStyle(
      fontFamily: F.family,
      fontFamilyFallback: F._fb,
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2);
  static const pickField = TextStyle(
      fontFamily: F.family,
      fontFamilyFallback: F._fb,
      fontSize: 12.5,
      height: 1.2,
      fontWeight: FontWeight.w500);
  static const pickNote = TextStyle(
      fontFamily: F.family,
      fontFamilyFallback: F._fb,
      fontSize: 11.5,
      height: 14.5 / 11.5,
      fontWeight: FontWeight.w500);
  static const pickRule = TextStyle(
      fontFamily: F.family,
      fontFamilyFallback: F._fb,
      fontSize: 10,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: .8);
  static const figureUnit = TextStyle(
      fontFamily: F.numerals,
      fontFamilyFallback: F._nb,
      fontSize: 15,
      height: 1,
      fontWeight: FontWeight.w700);
  static const sub = TextStyle(
      fontFamily: F.family,
      fontFamilyFallback: F._fb,
      fontSize: 12,
      height: 1.25,
      fontWeight: FontWeight.w500);
  static const total = TextStyle(
      fontFamily: F.numerals,
      fontFamilyFallback: F._nb,
      fontSize: 25,
      height: 1,
      fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()]);
  static const count = TextStyle(
      fontFamily: F.numerals,
      fontFamilyFallback: F._nb,
      fontSize: 18,
      height: 1,
      fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()]);
  static const avg = TextStyle(
      fontFamily: F.numerals,
      fontFamilyFallback: F._nb,
      fontSize: 14,
      height: 1,
      fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()]);
}

/// ── HEALTH MONITOR ── measured off its reference (1180 px across = 393 dp,
/// so 3 px to the dp). Always char: the page runs from slate at the top to
/// near-black at the foot, and every card is a veil of white over it, which is
/// why the cards darken down the page with it.
class HM {
  static const page = [
    Color(0xFF282F37), Color(0xFF1E2327), Color(0xFF15181D), Color(0xFF0E1215),
  ];
  static const pageStops = [0.0, .26, .47, 1.0];
  static const foot = Color(0xFF0E1215);

  /// The heart-rate line, its heart and the light it throws down the grid.
  static const line = Color(0xFF4A8DD1);
  static const heart = Color(0xFF3F90E0);
  static const glow = Color(0x214A8DD1);
  static const grid = Color(0x0BFFFFFF);
  static const dash = Color(0xFF9CA1A5);

  /// BPM and the zone line under the number.
  static const caption = Color(0xFFC4C8CB);

  /// An unlit zone segment: a veil over the page.
  static const segment = Color(0x17FFFFFF);

  /// A card's veil and the faint light along its top edge.
  static const card = Color(0x1AFFFFFF);
  static const cardTop = Color(0x0AFFFFFF);
  static const label = Color(0xFFC6C8CC);
  static const icon = Color(0xFF9EA2A5);

  /// The verdict pill inside the usual range, and with no range to read.
  static const withinChip = Color(0xFF334C46);
  static const within = Color(0xFF72E2A8);
  static const noneChip = Color(0x14FFFFFF);

  static const shareIcon = Color(0xFF6E6F71);
  static const footnote = Color(0xFF626669);

  static const title = TextStyle(
      fontFamily: F.family,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 2);
  static const kicker = TextStyle(
      fontFamily: F.family,
      fontSize: 12.5,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.9);
  static const caps = TextStyle(
      fontFamily: F.family,
      fontSize: 10,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4);
  static const zone = TextStyle(
      fontFamily: F.family,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: .2);
  static const name = TextStyle(
      fontFamily: F.family,
      fontSize: 10,
      height: 1.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5);
  static const unit = TextStyle(
      fontFamily: F.family,
      fontSize: 15,
      height: 1,
      fontWeight: FontWeight.w600,
      letterSpacing: 0);
  static const percent = TextStyle(
      fontFamily: F.numerals,
      fontFamilyFallback: [F.family],
      fontSize: 24,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0);
  static const verdict = TextStyle(
      fontFamily: F.family,
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: .1);
  static const share = TextStyle(
      fontFamily: F.family,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 2);
  static const note = TextStyle(
      fontFamily: F.family,
      fontSize: 13,
      height: 1.3,
      fontWeight: FontWeight.w400,
      letterSpacing: 0);
  static const value = TextStyle(
      fontFamily: F.numerals,
      fontFamilyFallback: [F.family],
      fontSize: 34,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: .4,
      fontFeatures: [FontFeature.tabularFigures()]);
}

/// ── THE JOURNAL ── (`journal_compose.dart`, `select_behaviors_sheet.dart`)
///
/// Measured off the reference screenshots: 921 px across = 393 dp, so 2.34 px
/// to the dp. The journal is always char, so its page and its rows are fixed
/// colours: the page runs from a warm tan at the top through grey into the
/// app's near-black, and every row, button and day pill is a veil of white
/// over it, which is why they warm and cool with the page behind them.
class JC {
  // ── the page ──
  static const pageColors = [
    Color(0xFFCAAD8D), Color(0xFFCAAD8D), Color(0xFFA2917D), Color(0xFF76736C),
    Color(0xFF555D60), Color(0xFF384A56), Color(0xFF293946), Color(0xFF1E2B33),
    Color(0xFF141B21), Color(0xFF111619), Color(0xFF101518),
  ];
  static const pageStops = [
    0.0, .13, .20, .32, .40, .48, .56, .64, .72, .76, 1.0,
  ];
  static const foot = Color(0xFF101518);

  static const ink = Color(0xFFFFFFFF);
  static const label = Color(0xFFBCC1C7);
  static const dim = Color(0x73FFFFFF);
  static const hairline = Color(0x1FFFFFFF);

  /// A row card, and a ✕ / ✓ button on it: each a tenth of white.
  static const card = Color(0x1AFFFFFF);
  static const button = Color(0x1AFFFFFF);
  static const chosen = Color(0xFFFFFFFF);
  static const onChosen = Color(0xFF101518);

  /// The day pills: a veil, a brighter dot, and a white rim on the chosen day.
  static const pill = Color(0x1FFFFFFF);
  static const dot = Color(0x57FFFFFF);
  static const dotLogged = Color(0xE6FFFFFF);

  // ── the SELECT BEHAVIORS sheet ──
  static const sheetColors = [
    Color(0xFF2F3D46), Color(0xFF28353D), Color(0xFF222B32), Color(0xFF1B2228),
    Color(0xFF1A2127),
  ];
  static const sheetStops = [0.0, .30, .53, .66, 1.0];
  static const scrim = Color(0xE6000000);
  static const grab = Color(0xFF576268);
  static const search = Color(0xFF131B1E);
  static const searchEdge = Color(0x0FFFFFFF);
  static const placeholder = Color(0xFF8C8D91);
  static const tabOff = Color(0xFFBEC3C7);
  static const sectionInk = Color(0xFF959AA0);
  static const question = Color(0xFFBDC2C6);
  static const box = Color(0xFF67AEE6);
  static const tickOn = Color(0xFF000000);

  // ── sizes (dp) ──
  static const gutter = 18.0;
  static const header = 60.0;
  static const closeIcon = 36.0;
  static const editIcon = 28.0;
  static const pillW = 49.4;
  static const pillH = 79.0;
  static const pillGap = 14.0;
  static const pillDot = 18.0;
  static const pillRim = 1.5;
  static const rowH = 63.0;
  static const rowGap = 10.0;
  static const rowPad = 14.0;
  static const answer = 36.0;
  static const doneH = 52.0;
  static const doneFoot = 18.0;
  static const listFoot = 25.0;
  static const sheetTop = 16.0;
  static const grabW = 73.4;
  static const grabH = 5.2;
  static const searchH = 51.0;
  static const boxSide = 24.2;
  static const boxRim = 2.0;
  static const tick = 26.0;
  static const tabMin = 96.0;
  static const tabPad = 20.5;
  static const tabLine = 2.0;
  static const pickRowH = 54.4;
  static const rRow = BorderRadius.all(Radius.circular(13));
  static const rAnswer = BorderRadius.all(Radius.circular(7));
  static const rSearch = BorderRadius.all(Radius.circular(13));
  static const rBox = BorderRadius.all(Radius.circular(3));

  // ── type ──
  static const _f = F.family;
  static const _fb = ['Manrope', 'Helvetica Neue', 'Helvetica', 'Arial'];

  /// JOURNAL, SELECT BEHAVIORS, DONE: 13 bold, tracked wide.
  static const title = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 13, height: 1.2,
      fontWeight: FontWeight.w700, letterSpacing: 1.0);

  /// TODAY.
  static const day = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 12, height: 1.2,
      fontWeight: FontWeight.w700, letterSpacing: 1.8);
  static const pillDay = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 11.5, height: 1.2,
      fontWeight: FontWeight.w500, letterSpacing: 0);
  static const pillDate = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 15.5, height: 1.2,
      fontWeight: FontWeight.w700, letterSpacing: 0);

  /// "What's happening today, November 7?"
  static const heading = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 20.5, height: 1.4,
      fontWeight: FontWeight.w600, letterSpacing: 0);

  /// BEHAVIORS, CURRENTLY SELECTED.
  static const sectionText = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 10, height: 1.2,
      fontWeight: FontWeight.w700, letterSpacing: 1.6);

  /// The question on a row, and a behavior's name on the sheet.
  static const row = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 15, height: 1.25,
      fontWeight: FontWeight.w500, letterSpacing: 0);

  /// The question under a name on the sheet, and a row's small print.
  static const sub = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 12.5, height: 1.25,
      fontWeight: FontWeight.w500, letterSpacing: 0);
  static const searchText = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 15.5, height: 1.2,
      fontWeight: FontWeight.w400, letterSpacing: 0);
  static const tab = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 11, height: 1.2,
      fontWeight: FontWeight.w700, letterSpacing: 1.2);
  static const value = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 14, height: 1.2,
      fontWeight: FontWeight.w600, letterSpacing: 0);
}

/// ── SPACING ── 4pt base ───────────────────────────────────────────────────
class S {
  /// Half a step: the 2 pt optical nudge (a text baseline against an icon).
  static const half = 2.0;
  /// One device-independent pixel: a rim or hairline's width.
  static const hair = 1.0;
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x12 = 48.0;
  static const x16 = 64.0;

  /// The minimum comfortable target, enforced inside `Pressable`. Apple HIG
  /// and WCAG 2.5.5 both land here.
  static const tap = 44.0;

  /// Screen side padding, one value for every screen.
  static const gutter = 20.0;

  /// The floating tab bar's height.
  static const navBar = 64.0;

  /// Bottom padding for a tab's scroll view so its last row clears the
  /// floating bar: the bar, its gap above the safe area, and air above it.
  /// A function, not a constant — the safe area is the phone's.
  static double navClear(BuildContext c) =>
      MediaQuery.paddingOf(c).bottom + x4 + navBar + x4;
}

/// ── RADII ─────────────────────────────────────────────────────────────────
///
/// The corner scale (DESIGN.md §5): every `Surface` card is [xl] (14), hero tiles and
/// sheet tops [xxl], inner blocks and buttons [md]/[sm]; chips, toggles and
/// the floating nav stay a [pill].
class R {
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const xl = 14.0;
  static const xxl = 18.0;
  static const pill = 999.0;

  static const rSm = BorderRadius.all(Radius.circular(sm));
  static const rMd = BorderRadius.all(Radius.circular(md));
  static const rLg = BorderRadius.all(Radius.circular(lg));
  static const rXl = BorderRadius.all(Radius.circular(xl));
  static const rXxl = BorderRadius.all(Radius.circular(xxl));
  static const rPill = BorderRadius.all(Radius.circular(pill));
}

/// ── ICON SIZES ── five steps; every `Icon(size:)` in lib/ui2 uses one ────
class I {
  static const sm = 16.0;
  static const md = 20.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const hero = 48.0;
}

/// ── ART ── the bundled imagery slots ───────────────────────────────
///
/// The ONLY way a screen names an image: no screen writes an asset path. Files
/// are SVGs under assets/images/; see DESIGN.md §18. A slot whose
/// file has not landed yet draws NOTHING — never a broken-image icon — so
/// code can ship before art does.
enum Art {
  // Everything is drawn: flat, hand-cut silhouettes in one cream and one
  // data hue, as SVG — a few hundred bytes each, sharp at any size, and the
  // same on every platform. 400 x 400 viewBox, centred.
  ring('art_ring', 'svg'),
  watch('art_watch', 'svg'),
  chestStrap('art_chest_strap', 'svg'),
  workout('art_workout', 'svg'),
  wellness('art_wellness', 'svg'),
  sleep('art_sleep', 'svg'),
  food('art_food', 'svg'),
  heart('art_heart', 'svg');

  const Art(this.stem, this.ext);
  final String stem, ext;

  String get asset => 'assets/images/$stem.$ext';

  /// The picture, or nothing. Decorative unless [semanticLabel] is given, in
  /// which case a screen reader says it.
  Widget image({String? semanticLabel, double? height, BoxFit fit = BoxFit.contain}) {
    if (ext == 'svg') {
      return SvgPicture.asset(
        asset,
        height: height,
        fit: fit,
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
        // A missing file draws nothing, never an error box.
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return Image.asset(
      asset,
      height: height,
      fit: fit,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// ── EFFECTS ── the numbers behind Glass and the one AuroraTile ─────────────
class Fx {
  /// Glass blur radius (both axes), under a [P.glass] tint.
  static const glassBlur = 24.0;

  /// The AuroraTile grain (assets/images/grain.png), tiled, at this opacity.
  static const grainOpacity = .04;
  static const grainAsset = 'assets/images/grain.png';

}

/// ── PERFORMANCE ── escape hatches ─────────────────────────────────
class Perf {
  /// When true every `Glass` renders solid, with no BackdropFilter. Wired to
  /// nothing yet: it is the switch to throw if Android jank shows up.
  static const lowGlass = false;
}

/// ── MOTION ── one gate, no exceptions ─────────────────────────────────────
///
/// The audit found zero reduced-motion support and 13 infinite `.repeat()`
/// loops. Both are structural problems, so both get structural answers: these
/// are the only durations in the system, and `test/ui2_tokens_test.dart`
/// forbids `.repeat(` in lib/ui2 outright. Ambient motion that genuinely needs
/// to loop takes its phase from a caller-owned value (see `BreathRing.t`), so
/// the screen owns the ticker and the same gate stops it.
class Motion {
  /// True when the platform is NOT asking for reduced motion.
  static bool enabled(BuildContext c) =>
      MediaQuery.maybeDisableAnimationsOf(c) != true;

  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 280);

  /// One-time hero draw-ins only — a ring filling, the scallop arriving.
  /// Never on layout, never looped.
  static const hero = Duration(milliseconds: 420);

  /// A figure rolling to its new value ([RollingNumber]), and how long the
  /// result then stays before the sheet that showed it closes.
  static const roll = Duration(milliseconds: 1100);

  /// One writing of the Locus mark ([LocusMark]): the pen's run and a hold,
  /// and when it loops, the ink lifting back off.
  static const logo = Duration(milliseconds: 2400);

  /// One pass of the three dots while the coach is thinking (the coach thinking dots).
  static const typing = Duration(milliseconds: 1200);
  static const linger = Duration(milliseconds: 1300);

  /// White filling the word LOCUS on the pull to refresh ([WordmarkFill]).
  static const write = Duration(milliseconds: 1500);

  /// The longest the pull to refresh holds the page open for the work itself,
  /// so the word always goes back up ([LocusPullRefresh]).
  static const refreshCap = Duration(seconds: 8);

  /// The least time between two haptic ticks of a rolling figure, so a long
  /// roll reads as a smooth run of taps and not a buzz.
  static const tickGap = Duration(milliseconds: 80);

  /// The session clock. A live workout counts REAL seconds, so this is the one
  /// duration that must NOT pass through [motion] — reduced motion silences
  /// animation, it does not stop time. It lives here because theme.dart is the
  /// only file allowed to write a `Duration(…)`, and a screen inventing its own
  /// tick is how thirteen ungated tickers happened last time.
  static const tick = Duration(seconds: 1);

  /// One full breath cycle for the paced-breathing ring — 5 s in, 5 s out is
  /// the pace the breathing session already uses. The PHASE is still owned by
  /// the screen (see `BreathRing.t`); this is only how long a cycle lasts, and
  /// the screen must not start it at all when [enabled] is false.
  static const breath = Duration(seconds: 5);

  /// One pulse of the ECG capture screen's contact rings. Phase is owned by
  /// the screen (like [breath]); nothing runs when [enabled] is false.
  static const ecgPulse = Duration(seconds: 2);

  /// The ECG live-preview repaint cadence: incoming packets only mark the
  /// ring dirty, and the screen's clock repaints at most this often.
  static const ecgPreviewTick = Duration(milliseconds: 100);
}

/// The two curves. [emphasized] overshoots, so it is for SCALE only — on a
/// layout property the overshoot would push its neighbours around.
class Ease {
  static const standard = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutBack;
}

/// Collapse [d] to zero when the user has asked for reduced motion. Every
/// `AnimatedFoo`, `AnimationController` and implicit transition in lib/ui2
/// takes its duration from here.
Duration motion(BuildContext c, Duration d) =>
    Motion.enabled(c) ? d : Duration.zero;

/// The animated-progress form: returns `1` (finished) instead of `t` when
/// motion is off, so a chart that draws itself in still ends up fully drawn.
double animate(BuildContext c, double t) => Motion.enabled(c) ? t : 1;

/// The motion gate for `showModalBottomSheet`, which takes an [AnimationStyle]
/// rather than reading [ThemeData.pageTransitionsTheme] like a route does.
/// Null keeps the platform default; [AnimationStyle.noAnimation] cuts straight
/// to the open sheet.
AnimationStyle? sheetMotion(BuildContext c) =>
    Motion.enabled(c) ? null : AnimationStyle.noAnimation;

/// True once the user's text scale has passed the point where a card's header
/// can no longer be one line. The number is not a device class — it is where
/// `label · value · unit` stops fitting a phone's width — and it is shared so
/// that every card that has to restack does it at the same moment.
bool bigText(BuildContext c) => MediaQuery.textScalerOf(c).scale(1) > 1.3;

/// Reduced motion has to reach the NAVIGATOR, not only the widgets inside it.
/// `TransitionRoute` builds its controller straight from `transitionDuration`
/// and never asks whether animations are disabled, so before this every push
/// slid at full duration for exactly the people who turned the setting on —
/// and a full-screen slide is the most nauseogenic thing the app does.
///
/// Sheets and dialogs do not consult a theme at all; those pass
/// `AnimationStyle.noAnimation` at their call sites.
class _Gated extends PageTransitionsBuilder {
  /// Whatever the SDK ships for this platform — taken from the default theme
  /// rather than named here, so the app keeps the native transition and this
  /// gate does not quietly become a second opinion about what it should be.
  final PageTransitionsBuilder inner;
  const _Gated(this.inner);

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext c,
      Animation<double> animation, Animation<double> secondary, Widget child) {
    if (!Motion.enabled(c)) return child;
    return inner.buildTransitions(route, c, animation, secondary, child);
  }
}

/// The Material theme. ui2 components never read it — they spend `P` and `F`
/// directly — so this exists for the Material widgets screens still use
/// (pickers, snackbars, dividers, progress, dialogs, sheets).
/// Each gets a sub-theme here instead of an edit at ~180 call
/// sites.
///
/// `primary` is the colour Material spends on TEXT (dialog actions, the
/// selected day in a picker's header), so it is volt only where volt is
/// legible as text: in dark. In light it is the char ink, and volt appears
/// only as a fill under dark ink.
ThemeData buildTheme(Brightness b) {
  final p = P(b == Brightness.dark);
  final primary = p.dark ? C.volt : C.char;
  final scheme = ColorScheme.fromSeed(
    seedColor: C.volt,
    brightness: b,
    surface: p.card,
  ).copyWith(
    primary: primary,
    onPrimary: p.inkOn(primary),
    primaryContainer: p.fill(C.volt),
    onPrimaryContainer: p.inkOn(p.fill(C.volt)),
    secondary: p.inverse,
    onSecondary: p.onInverse,
    surface: p.card,
    onSurface: p.ink,
    onSurfaceVariant: p.ink2,
    surfaceContainerHighest: p.card2,
    surfaceContainerHigh: p.card2,
    surfaceContainer: p.card,
    surfaceContainerLow: p.card,
    outline: p.line,
    outlineVariant: p.line,
    error: p.on(C.coral),
    onError: p.card,
  );
  const sheetTop = BorderRadius.vertical(top: Radius.circular(R.xxl));
  return ThemeData(
    brightness: b,
    scaffoldBackgroundColor: p.bg,
    colorScheme: scheme,
    fontFamily: F.family,
    fontFamilyFallback: const ['Manrope'],
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x00000000),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.ink,
      linearTrackColor: p.track,
      circularTrackColor: const Color(0x00000000),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.inverse,
      contentTextStyle: F.body.copyWith(color: p.onInverse),
      actionTextColor: p.onInverse,
      shape: const RoundedRectangleBorder(borderRadius: R.rLg),
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(borderRadius: R.rXl),
      titleTextStyle: F.t2.copyWith(color: p.ink),
      contentTextStyle: F.body.copyWith(color: p.ink2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      modalBackgroundColor: p.card,
      surfaceTintColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(borderRadius: sheetTop),
      dragHandleColor: p.line,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: p.card,
      surfaceTintColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(borderRadius: R.rXl),
      headerForegroundColor: p.ink,
      dividerColor: p.line,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(borderRadius: R.rXl),
      dialBackgroundColor: p.card2,
      hourMinuteShape: const RoundedRectangleBorder(borderRadius: R.rMd),
      dayPeriodShape: const RoundedRectangleBorder(borderRadius: R.rMd),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      surfaceTintColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(borderRadius: R.rLg),
      textStyle: F.body.copyWith(color: p.ink),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: F.body.copyWith(color: p.ink),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.card),
        shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: R.rLg)),
      ),
    ),
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final e in const PageTransitionsTheme().builders.entries)
        e.key: _Gated(e.value),
    }),
  );
}

/// Char in both themes: the two surfaces allowed to stay dark when the app is
/// light — onboarding and the live workout (DESIGN.md §2).
///
/// The ONE theme override in lib/ui2. `P.of` reads the ambient [Theme], so a
/// subtree that must be Char needs one, and keeping it here means no screen
/// writes its own `Theme(...)`. The dark theme is built once and shared.
class AlwaysChar extends StatelessWidget {
  final Widget child;
  const AlwaysChar({super.key, required this.child});

  static final _char = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext c) => AnnotatedRegion<SystemUiOverlayStyle>(
        // Light status-bar glyphs over the char page, whatever the app is.
        value: SystemUiOverlayStyle.light,
        child: Theme(data: _char, child: child),
      );
}
