# Locus design system

This document describes how the app looks and behaves today. It covers colours, type, corners, gradients, icons, motion and gestures, the Home screen piece by piece, and the chart system: how a chart is drawn, how it reads a finger, how it zooms, and how it chooses its axis.

**This is the only design guidance in the project.** The earlier "Volt" brief, its audit, its image-prompt sheet and its mood board were deleted (they described a lime-on-black direction the app no longer has). `lib/ui2/README.md` documents how to call the components and carries no token values; code comments point here. Order of authority: the code (`lib/ui2/theme.dart` for tokens, `lib/ui2/grammar.dart` for components and gestures, `lib/ui2/scrub.dart` for charts), then this file. If they disagree, the code wins, and this file gets fixed in the same commit. Do not add a second design document; extend this one.

All numbers are logical pixels (dp/pt). `S.x4` means the spacing token, with its value in brackets where it helps.

---

## 1. Character

- **A night instrument.** The default is the dark theme: a blue-grey slate page that gets slightly darker downward, cards a step lighter, white type. The light theme ("Cream") exists and is fully tokenised, but the redesign was tuned in dark.
- **Colour only where there is data.** Chrome is monochrome (ink on slate). Colour appears in dials, chart marks, and status words and squares, and each hue has a fixed meaning (§2.4).
- **Numbers are the heroes.** Standalone figures use the D-DIN bold numeral face, set large and tight. Words are Figtree. Card titles are small, bold, tracked capitals.
- **Quiet, square-ish corners.** Corners run 14 for a card, 12 for an inner block, 8 for a button or square, and 6 for a chip. Only controls that are meant to look like pills are pills.
- **No outlines on cards.** In dark mode a card is a diagonal tonal gradient with no border and no shadow. In light mode it is white with one soft shadow.
- **Everything readable by touch.** Every chart can be scrubbed with a finger, and the readout above it follows. Lifting the finger always returns the chart to its default state, so nothing stays selected.
- **Honest absence.** A missing number is `--` in a slot that has to hold one (dial, row, chart readout). A missing metric as a whole is a `StatusCard` that says what is missing, why, and what fixes it. Nothing is invented to fill a gap (§15).
- **Copy the layout, not the brand.** Reference screens from other wearables are copied for proportions and behaviour only. No other brand's name, wordmark or copy ever appears. The wordmark is **LOCUS**.

---

## 2. Colour

### 2.1 Surfaces and ink (`P.of(context)`)

| Token | Dark | Light | Used for |
|---|---|---|---|
| `p.bgTop` | `#283239` | `#F2F1EC` | top of the page gradient; the folded-dials bar |
| `p.bg` | `#1A1F23` | `#F2F1EC` (cream) | page; knock-out rings round chart markers; label pills under figures |
| `p.card` | `#2B3136` | `#FFFFFF` | card base, sheets, dialogs, the selected range segment |
| `p.card2` | `#353B41` | `#E9E8E2` | recessed: fields, soft buttons, icon chips, the alarm button, the selected picker row |
| `p.line` | `#3D444A` | `#DCDBD4` | hairlines, chart gridlines, sheet grab handle |
| `p.track` | `#3A4046` | `#E2E1DA` | empty ring track, switch-off track, disabled step chevron |
| `p.ink` | `#FFFFFF` | `#0F1014` | primary text, numbers, active marks |
| `p.ink2` | `#C6CBD0` | `#474B53` | secondary text, icons in rows, legend words |
| `p.ink3` | `#AAB0B6` | `#5F646D` | captions, axis ticks, chevrons, times, units, inactive x labels |
| `p.inverse` / `p.onInverse` | `#F4F4F1` / char | char / `#F4F4F1` | snackbar, active `SubTabs` pill, inverse button |
| `p.glass` | card @ 72 % | card @ 72 % | under the 24 px blur of `Glass` |

`ink3` is hand-solved to clear 4.5:1 on `card2`, the worst surface it can land on, so it is legible on every surface.

**Page gradient.** Under every tab: `LinearGradient(topCenter → center, [bgTop, bg])`. The slate is lighter at the top and settles into `bg` by the middle of the screen. Only dark mode has a gradient (in light, `bgTop == bg`). Pushed screens use plain `p.bg`.

### 2.2 Card ground (`panelDecoration`, `Surface`)

Dark cards are graded diagonally (top-left → bottom-right) and have **no border and no shadow**:

| Tone | From | To | Where |
|---|---|---|---|
| `PanelTone.subtle` (default) | ink 3.5 % over `card` | char 16 % over `card` | every ordinary `Surface` |
| `PanelTone.rich` | ink 5 % over `bg` | char 40 % over `bg` | the figure panels under a dial: strain stats, sleep and recovery contributors |

Light cards are flat `card` plus `p.el(1)`: one shadow, 0/8/24, char at 6 %.

A `Surface(color: …)` or `elevation: 0` is drawn **flat** (no grading). This is used for `StatusCard` and for recessed `card2` panels.

### 2.3 Tonal recipes

These are the "ink over a surface" steps. Use them instead of inventing new greys:

| Recipe | Where |
|---|---|
| `ink` 4 % over `bg` | workout HR chart plot ground |
| `ink` 5 % over `bg` | day pager track; strain caret fill |
| `ink` 7 % | typical-range band in a line chart |
| `ink` 8 % | highlight column (the day a screen is about); activity row ground (over `card`); stat-panel dividers |
| `ink` 9 % | ADD / START ACTIVITY buttons |
| `ink` 10 % | scrub touch column; Strain & Recovery resting column; `_VsPill`; HR chart grid |
| `ink` 12 % | open plus button; RESET chip; Trend View metric pill (over `card2`); typical-range legend swatch |
| `ink` 15 % over `bg` | day pager date pill |
| `ink` 22 % | dead pager chevron; dock grab handle |
| `ink` 24 % over `track` | strain-target band on the dial track |
| `ink` 28 % | dashed average line in charts |
| `char` 45 % | plus menu barrier |
| `char` 50 % over `bg` | range segment track |
| `char` 55 % over `bg` | strain "vs. last 30 days" legend strip |
| `char` 60 % over `bg` | day-heart header strip |
| hue 18 % | delta chip ground (good/bad) |
| hue 20 % | Home monitor status square |

### 2.4 Hues and what they mean

Each hue below has one job. Do not reuse a hue for a different meaning.

**Dials and domains**

| Token | Hex | Meaning |
|---|---|---|
| `C.dialSleep` | `#7BA1BB` | sleep: dial arc, sleep columns, "hours" line, sleep bars on floating charts, night stretch on HR traces, milestone bar |
| `C.dialStrain` | `#0093E7` | strain and activity: dial arc, strain lines and columns, activity blocks, HR traces, START button, pulse disc, all line metrics in Trend View |
| `C.recGreen` | `#16EC06` | recovery 67–99; "connected" dot; ALARM ON; within range; wake line |
| `C.recYellow` | `#FFDE00` | recovery 34–66; alarm pending or unconfirmed; above or below range |
| `C.recRed` | `#FF0026` | recovery 1–33 |

`recoveryColor(v)`: `v ≥ 67` green, `v ≥ 34` yellow, else red. This one function colours the dial, recovery columns, Strain & Recovery points, and the recovery calendar.

**Verdicts (better or worse than before)**

| Token | Hex | Meaning |
|---|---|---|
| `C.optimal` | `#00F19F` | the change goes the way this metric wants; "optimal" contributor; sleep need line; recovery-group columns |
| `C.strainDown` | `#FFA624` | the change goes the wrong way (delta chips, stat-row triangles, 6M month notes) |
| `C.poor` | `#FFA733` | dashboard row triangle when worse; "poor" contributor tier |
| `C.n400` | `#8B9099` | a direction with no verdict (metric where neither way is better) |

Contributor tiers are `[C.poor, p.ink3, C.optimal]` = poor / sufficient / optimal.

**Strain bands** (Trend View "Strain breakdown", strain words):

| Band | Range | Colour |
|---|---|---|
| All out | > 18.0 | `C.dialStrain` `#0093E7` |
| Strenuous | 14.1–18.0 | `C.strainStrenuous` `#0480CA` |
| Moderate | 10.1–14.0 | `C.strainModerate` `#066DA7` |
| Light | 0.0–10.0 | `C.strainLight` `#0A5A8B` |

**HR zones 1–5** (`C.refZone1…5`), used for zone stacks, zone cards and the lit zone on the workout chart: `#AEC2CD`, `#479AC2`, `#59B896`, `#FBAC5D`, `#FF6422`.

**Stress** (`stressColor` interpolates 0 → 3 through the four stops): low `#70AADA`, medium `#02C986`, warm `#C9BC3A`, high `#FFA624`. The Health Monitor square uses `stressMedium` when every vital is in range and `stressHigh` when one is not.

**My Day blocks:** sleep `C.blockSleep #7F9DB5`, session `C.blockSession #3B8DE0`. These blocks carry white ink, bold display type only.

**Sleep stacks:** deep/SWS `C.trendSws #FA96F9`, REM `C.trendRem #AC5AED`. Unfocused floating bars are `C.barGrey #63676A`.

**Other:** sync arrow `C.orange` (= amber `#FFB547`); coach orb ring `#7E57C2 → #3FA7B5 → #7E57C2` (sweep); sleep-plan panel `C.mint #DFF8EF` with char ink; volt `#B1F002` is now spent only on the active tab pill, `AppSwitch` on-track and Material `primary` in dark.

### 2.5 Rules

- Raw pigment is not text-safe on every surface. Text or an icon in a hue on a plain surface goes through `p.on(hue)`. A filled surface goes through `p.fill(hue)` with `p.inkOn(fill)` on top. The dial and chart hues are drawn raw because they are marks on the dark ground, not text on a light one.
- **White on colour** is allowed only for bold display type on a saturated block (activity blocks, pulse disc, START pill), where 3:1 is the floor.
- Use the hues above. A new colour is declared in `theme.dart` (and added to `C.all` if it is ever ink or a fill); `Color(0x…)` anywhere else fails the token test.

---

## 3. Typography

Two bundled faces (SIL OFL, `assets/fonts`), the same on every platform:

- **Figtree** for words. Fallback chain: Manrope (covers Cyrillic), Helvetica Neue, Helvetica, Arial.
- **D-DIN Bold** (`DDINNums`, digits-only) for numbers that stand alone. Letters inside a numeral style fall through to Figtree.

**The numeral rule.** Only a number that stands on its own uses D-DIN: a dial figure, a card value, a chart tick or label, a time in a row. Use the `F.n*` steps, or `F.num(style)` to turn a word style into a numeral style at the same size. A digit inside a sentence stays Figtree.

### 3.1 Word steps

| Token | Size / line | Weight | Tracking | Use |
|---|---|---|---|---|
| `F.display` | 36/42 | 500 | −1.0 | `ScreenTitle` |
| `F.t1` | 28/34 | 500 | −0.7 | Home section heads: "My Day", "My Dashboard" |
| `F.t2` | 22/28 | 600 | −0.5 | sheet and dialog titles, Start Activity title, popup menu items (w400) |
| `F.head` | 17/24 | 600 | −0.4 | `Section` titles, BigButton label, Trend View sentence (height 1.3), screen sub-heads at w700 |
| `F.body` | 15/22 | 600 | −0.25 | body text, rows, `TextAction`, field text |
| `F.cap` | 13/18 | 600 | −0.15 | captions, notes, units, info rows, delta-chip text (w700) |
| `F.over` | 11/14 | 700 | +0.3 | tiny labels, uppercased by the caller: pager date, readout captions, x/y chart labels (via `F.num`) |
| `F.caps` | 12/16 | 700 | +0.35 | **the card-title voice**: dial names, card titles, row titles, buttons, legends, segments. Always uppercased by the caller. |
| `F.wordmark` | 22/1 | 300 | +5 | "LOCUS" over the dials (ink2) and inside the strain ring (ink3) |

**Tracking overrides used across the redesign** (letterSpacing on caps text):
- `.6`: ACTIVITIES, activity names, day buttons
- `1.0`: day pager date (`F.over` w800)
- `1.3`–`1.4`: workout header name, zone and stat labels, plus-menu labels, "STRAIN" over the day-heart reading
- `1.6`: "KEY STATISTICS", the START ACTIVITY pill
- `2.2`: "STRAIN" under the big strain figure

Weight w800 is used on caps labels that have to read as heavier than their neighbours: folded dial names, monitor titles and status words, zone and stat labels, the pager date, RESET.

### 3.2 Numeral steps (D-DIN Bold, tabular figures)

| Token | Size | Tracking | Use |
|---|---|---|---|
| `F.n80` | 80 | −0.8 | the figure inside a detail ring (strain page, strain-target dial when large) |
| `F.n64` | 64 | −0.6 | pulse disc HR; strain-target dial when small |
| `F.n48` | 48 | −0.5 | running rest clock |
| `F.n34` | 34 | −0.3 | Home dial figures; big chart readout; activity strain; key-stat cards; multi-readouts |
| `F.n24` | 24 | −0.1 | dashboard row value; activity block value; small readout; breakdown counts; bedtime and alarm times |
| `F.n17` | 17 | −0.1 | battery %; dial suffix "%"; stat-row value; stress score in its square |

Every numeral is height 1.0 and tabular, so a changing value never shifts the layout around it.

**Units** sit on the number's baseline (`Row` with `CrossAxisAlignment.baseline`), gap `S.x1`. With a big readout the unit is `F.head` w600 ink; with a small one it is `F.cap` w600. In the `Numeral` widget it is `F.body` or `F.cap` in ink3. A hero number that might outgrow its box is wrapped in `FittedBox(scaleDown)`: shrinking a number keeps it correct, truncating it changes it.

### 3.3 Number formats

| Kind | Format | Helper |
|---|---|---|
| Dial sleep hours | `7:06` | `hMinutes` |
| Durations | `7h 23m` / `45m` | `hm` |
| Trend durations | `7:30`, axis ticks `7h` / `7:30` | `hMm`, `_tickText` |
| Counts | `12,480` (locale grouping) | `thousands` |
| Big axis ticks | `1.5k` | `_tickText` |
| Strain | one decimal, `14.2` | |
| Percent | whole, `82%` | |
| bpm / ms / % in metric rows | whole numbers | `metricValue` |
| br/min, ° | one decimal | `metricValue` |
| Clock | user's 12/24 h choice | `formatClockOf`, `clock`, `clockOfTs` |
| A time on another day | `[Tue] 11:18 PM` | `_ActivityRow._when` |
| Absent | `--` (dial, row, readout, block). Never `0`, never blank. | |

---

## 4. Spacing and layout

**Grid:** 4 pt. `S.half 2`, `x1 4`, `x2 8`, `x3 12`, `x4 16`, `x5 20`, `x6 24`, `x8 32`, `x10 40`, `x12 48`, `x16 64`. Plus `S.tap 44` (the minimum touch target), `S.gutter 20`, `S.navBar 64`.

| Where | Value |
|---|---|
| Home side padding | `S.x4` (16) via `pad` |
| Sheets, dashboard editor | `S.gutter` (20) |
| Gap between cards on Home | `S.x3` (12) |
| Above a Home section head | `S.x6` (24); below it `S.x3` (12) |
| Above a `Section` title | `S.x8` (32); below `S.x3` |
| Standard card padding | `S.x5` (20); compact cards use 16 |
| Bottom of every tab's list | `S.navClear(c)` = safe area + 16 + 64 + 16 |
| Bottom of a pushed screen | `S.x16 + S.x8` (96) via `pad` |
| Header | top 12, bottom 16 |

Touch targets are never smaller than 44 even when the drawing is: the pager is drawn 32 tall and touched over 44, `BoldChevron` sits in a 36 × 44 box, the three-dot button is 52 × 44.

---

## 5. Corners

| Token | Radius | Used on |
|---|---|---|
| `R.sm` | 6 | chips (delta chip, `_VsPill`), legend swatches, typical-range band, highlight columns, value-label pills, sleep-plan panel, axis tags |
| `R.md` | 8 | activity block, monitor square, plus button, fields, alarm button, detail link rows, popup menu, comparison legend strip |
| `R.lg` | 12 | inner rows and cards: activity rows, day buttons, week cards, zone cards, Trend View metric pill and picker rows, selected range segment, snackbar |
| `R.xl` | 14 | every `Surface` card, dialogs, Strain & Recovery card, key-stat cards, picker card, range segment track, dashed `StatusCard` outline |
| `R.xxl` | 18 | sheet top corners, date and time pickers' dialog shells |
| `R.pill` | 999 | tab bar, tab pill, `BigButton`, `Pill`, `SubTabs` pill, RESET chip, START pill, switches, grab handles |

Corners derived from the scale:
- Day pager: `S.x2 + S.half` = **10**
- Strain-target dock top: `R.xxl + S.x3` = **30**
- Plus menu panel: `R.xxl + S.x3 + S.x1` = **34**

Corners inside charts:
- Scrub touch column: **4**
- Bar tops: **2** (`R.sm/3`); the bar foot is square
- Stacked segments: **min(3, width/3)**, with a 1.5 gap between segments; the bottom segment's foot is square
- Floating bars: **2**
- Zone bar: 30 % of its height

Circles: dials, rings, the monitor stress square's contents, `IconChip` (32), `RoundIconButton` (48), the coach orb (40), the + tab button (40), the knob (64), the pulse disc, markers.

---

## 6. Depth, gradients and effects

- **Elevation:** dark mode has none; depth is the tonal grading in §2.2. Light mode uses `el(1)` = 0/8/24 at 6 % char, and deeper levels multiply it.
- **The only real shadows** are the plus-menu panel (char 50 %, blur 32, y 8) and the strain-target knob glow (ink 18 %, blur 16, spread 4).
- **Glass:** a 24 px backdrop blur under `p.glass`, plus a white 8 % hairline (or `p.line` in light). It is budgeted to two on screen at once: the tab bar and the minimised-workout banner. It is never used in a list item. Under high contrast or `Perf.lowGlass` it is drawn solid.

**Gradient inventory** (do not add new ones without a reason this list does not already cover):

| Gradient | Definition |
|---|---|
| Page | `bgTop → bg`, top to centre |
| Card subtle / rich | §2.2, top-left to bottom-right |
| Plus menu panel | ink 11 % → ink 6 % over `card`, top-left to bottom-right, ink 8 % border |
| Start Activity ground | `dialStrain` 26 % over char → char, top-left to bottom-right, stops 0 / 0.8; the header band is a flat `dialStrain` 12 % over char |
| Line chart fill (`ScrubLine`) | hue 22 % → 0, top to bottom of the plot |
| `LineChart` painter fill | hue 12 % → 0 (only when an axis is given) |
| 6M ghost fill | hue 12 % → 0 |
| Workout HR fill | `dialStrain` 42 % → 2 % |
| Lit zone runs | zone hue 85 % → 8 % |
| Strain-target arc | sweep from `char 55 % over dialStrain` to `dialStrain`, so it deepens toward the knob |
| Stress gauge | sweep low (35 %→100 %) → medium → warm 55 % → high 55 % → 30 %, dimming at both ends |
| Unfinished `Ring` (non-solid) | sweep hue 55 % → 100 % (calibrating or provisional states only) |
| Coach orb | sweep `#7E57C2 → #3FA7B5 → #7E57C2` |

Nothing animates a gradient.

---

## 7. Icons and drawn marks

**Lucide at the 300 weight (1.5 px stroke).** Every icon comes from `lib/ui2/lucide.dart`, which re-exports Lucide's `…300` glyphs. Never import the package directly. A name not listed there does not exist yet: add it to the file.

**Sizes:** `I.sm 16`, `I.md 20`, `I.lg 24`, `I.xl 32`, `I.hero 48` (offsets like `I.lg + S.x1` are allowed). Typical colours are ink3 for a trailing chevron or decorative row icon, ink2 for a row or menu icon, and ink for an action icon.

| Size | Typical use |
|---|---|
| 16 | battery glyph, info rows, RESET zoom glyph, `IconChip`, pill icons |
| 20 | trailing chevrons, maximize, pencil, monitor square glyphs, menu-less actions, `BigButton` glyph, `RoundIconButton` glyph |
| 24 | activity icons (in blocks, white), plus-menu icons (ink2), tab icons, picker rows, chevrons in week cards and Trend View pill |
| 28 | strain stat icons (`I.lg + S.x1`), workout header icon |
| 32 | NavBar back chevron, Trend View metric icon, day-heart close and zoom |

**Drawn marks** (`lib/ui2/marks.dart`), used where the font's stroke is not right:

| Mark | Look | Where |
|---|---|---|
| `BoldChevron` | thick chevron, stroke = 22 % of its height, round caps and joins; width = height × 11/15 | day pager (height 12, ink; dead = ink 22 %), dial names and monitor titles (12, ink3), workout back (20) |
| `DeltaTriangle` | solid triangle, softened corners, height 0.8 × width | dashboard rows (10), stat rows and legend (12), `_VsPill` (12, ink2) |
| `StatIcon` | fine 1.35-unit line icons on a 24 grid: heart with bands (zones 1–3), heart with chevrons (zones 4–5), barbell (strength), shoe (steps) | strain stats panel |
| `StrapIcon` | the band drawn from the side, open at the right; a badge sits in the gap | top-right device status (height 24) |
| `SyncArrowMark` | flat-cut up arrow in orange | strap badge while syncing |
| `MarkCount` | count in a 1.5 px ring | grouped activity marks on charts |
| `clusterMarks` | groups marks whose centres are within `gap` of the group's mean; zooming spreads them apart again | day-heart and chart marks |

Chevron convention: `BoldChevron` where the chevron is part of a label (pager, dial name, monitor title). Lucide `chevronRight` (I.md ink3 or I.lg ink2) where the whole row or card is the door.

---

## 8. Motion

One gate: `motion(c, d)` returns zero under reduced motion, `animate(c, t)` returns 1, and `Motion.enabled(c)` lets code branch on it. Page transitions are the platform's own (Cupertino slide with swipe-back on iOS), gated by the theme. Sheets use `sheetMotion`. **No `.repeat(`**: a looping animation is an `AnimationController` that reverses itself from a status listener and stops when motion is off.

| Token | Duration | Used for |
|---|---|---|
| `Motion.fast` | 120 ms | `Pressable` press scale (→ 0.98) |
| `Motion.base` | 180 ms | tab pill, `SubTabs`, plus menu fade |
| `Motion.slow` | 280 ms | strain-target dock opening and closing |
| `Motion.slow × 2` | 560 ms per swing | sync arrow bob |
| `Motion.hero` | 420 ms | one-time draw-ins (scallop) |
| `Motion.tick` | 1 s | real clocks (live session, running rest). This one is **not** gated, because reduced motion should not stop time. |

Curves: `Ease.standard` = easeOutCubic for anything that moves. `Ease.emphasized` = easeOutBack, for **scale only**. `Curves.easeInOut` for ping-pong loops. `Curves.easeInOutCubic` for the scroll-driven dial fold.

**Living elements:**
- **Sync arrow:** bobs up `S.x1` (4 px) and back, easeInOut, 560 ms each way, only while data is arriving. When motion is off it sits still.
- **Pulse disc:** each half-beat lasts `30 000 / HR` ms, clamped 240–700 (500 with no reading). The disc scales by 1.035 and a halo grows to 1.38× while fading from 16 %. When motion is off it sits still.
- **Dial fold:** driven by scroll position, not time (§11.3).
- **Rings** draw complete (`t = animate(c, 1)`); the draw-in hook exists, but Home does not sweep its dials in.

---

## 9. Interaction grammar

Gestures are built only from `lib/ui2/grammar.dart`. The token test fails on a raw `GestureDetector`, `Listener` or `InkWell` anywhere else.

| Primitive | Behaviour |
|---|---|
| `Pressable` | a tap; forces a 44 × 44 minimum target; scales to 0.98 on press (120 ms); carries the button role and a label |
| `Scrubber` | the one horizontal drag. The finger's x maps to 0…1. A tap jumps straight to that point. It carries the slider role: increase and decrease step by `step` (default 0.05), and `describe` says the value aloud. |
| `Scrubber(yieldToScroll)` | a drag that runs mostly vertical (`dy > dx` and more than 8 px) is handed to the page. The scrub stops and `onLift` fires, so a chart in a list never scrubs while the list scrolls. |
| `Scrubber(onPinch)` | two fingers end the scrub and start a pinch. It reports `scale` (spread ÷ starting spread), `focal` (the starting midpoint, 0…1) and `pan` (how far the midpoint moved, as a fraction of the width). A scale recognizer is placed in the gesture arena so the page's scroll cannot steal the second finger. |
| `Scrubber(hold)` | press and hold instead, for a chart inside a tappable card: a tap opens the card and a hold reads a value. |
| `DialScrubber` | a drag round a ring. The angle is measured clockwise from 12 o'clock. It never wraps: carried past 12, the value holds at the end it came from. A touch that starts inside 55 % of the radius (where the dial's own buttons sit) is ignored. Slider role. |
| `SwipeHandle` | a vertical swipe of 24 px or more fires once (up or down). A tap that moves less than 8 px toggles. |
| `Dismissible` | swiping the "Your first weeks" card away hides it until tomorrow. |
| `RefreshIndicator` | pull to sync on Home (today only, with a paired band). The spinner releases after 90 s; the sync carries on in the background. |

**Navigation:**
- `go(c, screen)` pushes through `themedRoute`, which keeps the platform transition and iOS swipe-back.
- Tab state is kept alive. Android Back walks the tab history, with Home always last.
- A dial, row or card that opens something gets a chevron or is wholly a `Surface(onTap)`.

**Feedback rules:**
- A scrub never leaves a selection behind. Lift the finger and the chart and its readout return to their default state.
- Zoom state resets whenever the range, the window or the metric changes.
- A control with nothing behind it is drawn disabled (dimmed chevron, `p.track` step arrow, `card2` disabled tab) and still has a label. It does not disappear.

---

## 10. Components

### 10.1 Shell (`app_shell.dart`)

Bar order: **Home · Health · (+) · AI · More**. The (+) and AI buttons are actions, not destinations.

- **Bar:** a floating `Glass` pill, inset 16 from the sides and from the bottom safe area, minimum height 64, inner padding 4, `p.line` border.
- **Tabs:** icon `I.lg` above a label in `F.over` (w700 active, w600 inactive). Text scale is clamped at 1.3 inside the bar.
- **Active tab:** a volt pill (`p.fill(C.volt)`) with char ink, animated over `Motion.base` with `Ease.standard`. Inactive tabs are bare ink3.
- **(+):** a 40 circle in `card2` with a `plus` icon at I.lg.
- **AI:** the coach orb (40): a sweep ring round a `card` disc with `sparkles` at I.md.
- **Banner:** a minimised workout floats as its own `Glass` pill 8 above the bar.

### 10.2 Home header

A `Stack` of three things, so the pager sits on the true centre of the screen:
- **Left:** `ProfileAvatar`, diameter 38.4 (`S.x12 × 0.8`).
- **Centre:** the `DayPager`.
- **Right:** device status. Battery reads `78%` in `F.n17` w700 (ink, or `p.on(red)` when low), then 8, then a `StrapIcon` 24 tall. In the strap's gap sits either a 10 px dot (`recGreen` when connected, ink3 when not) or the bobbing orange sync arrow. Tapping it opens My Devices.

### 10.3 `DayPager`: `< TODAY >`

- **Size:** 168 wide (`S.x16 × 2 + S.x8 + S.x1 × 2`), drawn 32 tall, touched over 44.
- **Track:** full width, ink 5 % over `bg`, radius 10.
- **Date pill:** fills the middle, ink 15 % over `bg`, radius 10. The label is `TODAY` or `MON, OCT 26` in `F.over` w800, tracking 1, height 1, inside `FittedBox`.
- **Chevrons:** `BoldChevron` height 12 in 36 × 44 boxes.
- **Stepping:** moves through **days on record**, not calendar days. "Newer" from the newest past day lands on today. A dead end draws the chevron at ink 22 % and keeps its label.
- **Tap the date:** opens the recovery calendar. Days are coloured by recovery; grey days cannot be opened. Key: `<34%`, `34% - 66%`, `>66%`.
- `DetailDayPager` is the same pager, centred, on the Sleep, Recovery and Strain detail screens.

### 10.4 Pushed-screen header (`NavBar`, `detailScaffold`)

- Minimum height 64.
- **Back:** a bare Lucide `chevronLeft` at I.xl, left-aligned in a 48 box, with no disc behind it.
- **Title:** centred, uppercased, `F.caps` ink, with an optional sub-line in `F.over` ink3.
- **Trailing slot:** 48 wide.
- `detailScaffold` wraps a `NavBar` and a `ListView` with 16 side padding and 48 at the bottom.

The workout screen uses its own header: `BoldChevron` 20, the activity icon at I.lg+4, the name in `F.cap` w800 tracking 1.3, the date and time in `F.over` w500 ink3, and a **three-dot** button (three 10 px rings with a 2 px border, 4 apart, in a 52 × 44 box). That button opens a white popup menu (radius 8, items 64 tall, `F.t2` w400 in char: Share / Edit / Delete).

### 10.5 Cards

- **`Surface`:** radius 14, padding 20, graded ground. With `onTap`, the whole card is the door.
- **Card title voice:** `F.caps` uppercase ink, often with a trailing `BoldChevron` (ink3, 12) or a Lucide icon in a 44 box (info, maximize, chevron).
- **Dark inner block on a card:** ink 8 % over `card`, radius 12.
- **`StatusCard`** (something absent or uncertain):
  - A flat card with a **dashed 1 px ink3 outline**: 4 on, 4 off, round the radius-14 shape. Absence reads as an outline, presence as a filled card.
  - A neutral `IconChip` (32 circle in `card2`, icon 16 in ink2), then the title in `F.body` w600.
  - The why in `F.cap` ink2, height 1.5.
  - The fix as a soft `BigButton` only when it can be pressed. Advice with nothing behind it stays plain text.
- **`Observation`:** used on Home for the illness watch only.

### 10.6 Buttons and controls

| Control | Spec |
|---|---|
| `BigButton` | minimum height 56 (`S.x12 + S.x2`), full width, pill, padding 20/12, label `F.head` (2 lines max), optional icon 20 + 8. Primary is `p.fill(color)` with `inkOn`. `soft` is `card2` + ink. `inverse` is the black or cream pill. `danger` is coral text on `card2`. `round` is a 56 circle. `busy` swaps the icon for a 16 spinner. |
| Home day buttons (ADD / START ACTIVITY) | height 52, ink 9 %, radius 12, icon I.md + 8 + `F.caps` tracking .6, `FittedBox` |
| Alarm button | `card2`, radius 8, 16 vertical padding, pencil I.md + 12 + `F.caps` |
| `PlusButton` | 44 square (`S.x10 + S.x1`), radius 8, ink fill with a `plus` at I.md in `bg` colour. Open state: ink 12 % with an `x` at I.lg in ink. |
| RESET chip | height 32, horizontal padding 12, ink 12 %, pill, `zoomOut` I.sm + 4 + `RESET` in `F.over` w800 |
| START pill (Start Activity) | `dialStrain`, pill, fills a 64 bar, `F.body` w800 tracking 1.6 white (50 % alpha while starting) |
| `TextAction` | `F.body` w600 ink (coral for danger), optional trailing icon I.sm |
| `RoundIconButton` | 48 circle, `card2` (or inverse, or glass), icon I.md, label required |
| `AppSwitch` | Material switch: on is a volt track with a char thumb, off is `track` with an ink3 thumb, no outline |
| `AppField` | label `F.cap` ink2 above, a gap of 8, then a field filled `card2` with radius 8 and padding 16/12, no border. Focused: a 2 px ink ring (never volt). Error: a 2 px coral ring. `bare` drops the box. |
| `SubTabs` | horizontal pills 44 tall (scaled with text), padding 16, gap 8. Active is an `inverse` fill with `onInverse` text (w600). Disabled is a `card2` fill with ink3 text. A scroll hint replaces the chevron. |
| `Pill` | padding 12/4, `p.wash(hue)` with `p.on(hue)` text, `F.cap` w600 |

### 10.7 Overlays

- **`AppSheet`:** `card`, top radius 18, padding 20/12/20/(20 + safe area), a grab handle 40 × 4 in `p.line`, title `F.t2`, content scrolls, actions stacked with 12 between. `AppSheet.open(…, bare: true)` lets a sheet paint its own ground.
- **`AppDialog`:** `card`, radius 14, inset 16/24, padding 24, title `F.t2`, body `F.body` ink2. Buttons are full-width `BigButton`s stacked with 8 between: primary, then destructive, then secondary.
- **Plus menu:** §11.6.
- **Snackbar:** floating, `inverse` ground, `F.body` `onInverse`, radius 12.

---

## 11. Home, top to bottom

```
[avatar]        < TODAY >        78% [strap]
                    LOCUS
   ( 82% )        ( 67% )        ( 9.4 )
   SLEEP ›       RECOVERY ›      STRAIN ›
┌ HEALTH MONITOR › ┐ ┌ STRESS MONITOR › ┐
│ [✓] WITHIN RANGE │ │ [1.2] MEDIUM     │
│     4/4 Metrics  │ │      14:20       │
└──────────────────┘ └──────────────────┘
(wearable cells) (detected activities)
My Day                                [+]
┌ ACTIVITIES                         ⤢ ┐
│ [☾ 7:12] SLEEP          11:02 PM  ┊  │
│ [🏃 9.8] RUNNING         7:15 AM  ┊  │
│ [+ ADD ACTIVITY] [⏱ START ACTIVITY]  │
└──────────────────────────────────────┘
┌ TONIGHT'S SLEEP                     › ┐
│ 🌅 10:40 PM   - - - -   ⏰ 6:30 AM     │
│ RECOMMENDED            ● ALARM ON     │
│ BEDTIME                               │
│ [✎ EDIT ALARM]                        │
└──────────────────────────────────────┘
My Dashboard                CUSTOMIZE ✎
┌ STRAIN & RECOVERY chart ┐
┌ ♥ HEART RATE VARIABILITY      62 ▲ ┐
│                               58   │
…
```

### 11.1 Order and conditions

1. **Header** (§10.2).
2. A **database-rebuilt** `StatusCard` (only after a rebuild; it outranks everything else).
3. The **illness watch** `Observation`: only at amber or red, and only for a recent night. On ordinary days it does not appear.
4. The **wordmark**, then 20.
5. Sync and phase status card (today, only while connecting, syncing or analysing).
6. **Either** a bare-day card (nothing measured; while a workout runs this becomes "A workout is still running") **or** the **dials** plus the **monitors**. If no dial has anything to draw, a single "Recovery is not scored today" card replaces them.
7. Stale-insights card, then "Your first weeks" (swipeable).
8. Wearable cells (only for non-WHOOP devices), then detected activities.
9. **My Day:** a section head with the plus button, the ACTIVITIES card, then TONIGHT'S SLEEP (today only).
10. **My Dashboard:** a section head with CUSTOMIZE, then the chosen tiles in the user's order.

**"Quiet day" rule.** It is past midnight, nothing has been scored for today, earlier nights exist, and the band has sent data in the last 6 hours. The dials then show empty with the line "No sleep yet today." instead of a card asking the user to sync.

### 11.2 The three dials (Sleep · Recovery · Strain)

- **Layout:** a row of three `Expanded` columns with 12 between them. Each dial is capped at 144 wide and drawn at 85 % of its column, square.
- **Ring:** `Ring(solid: true, flatStart: true)`.
  - Stroke is **5.8 % of the dial's width**: a thin ring.
  - Track is `p.track`.
  - The arc starts **square at 12 o'clock** and ends in a **round cap** (a dot of half the stroke). A full turn has no cap.
- **Strain target** (strain dial only): the target band is drawn on the track in ink 24 % over track. A tick crosses the track at the band's low end, ink, 16 % of the stroke wide. Both draw under the arc.
- **Figure:** centred, inset by stroke + 8, `F.n34` w700 ink (ink3 when provisional), in a `FittedBox`. A `%` suffix sits on the baseline in `F.n17`.
- **Under the dial:** 12, then the name in `F.caps` ink, then 8 and a `BoldChevron` (ink3, 12). Provisional or calibrating dials add a sub-line in `F.over` ink3.

| Dial | Value | Arc | Fraction |
|---|---|---|---|
| Sleep | sleep performance = slept ÷ need × 100, capped at 100, `82%`. With no need: hours `7:06` and an **open track** (no arc). | `dialSleep` | perf / 100 |
| Recovery | `67%` | `recoveryColor(v)`; ink3 while provisional | v / 100 |
| Strain | `9.4` | `dialStrain` | v / 21 |
| Absent | `--` | none | none |
| Calibrating | `--` | `DashedRing`: `need` beads (default 24), each 30 % of its slot, filled ones ink3 | nights so far / need |

Tapping a dial opens Recovery, Strain or Sleep detail for the day being shown. A note may appear under the row ("Updated 9:12", or the quiet-day line) in `F.cap` ink3.

### 11.3 Dials folding into the top bar on scroll

As the page scrolls, the dials do not just scroll away. Each ring flies into a compact bar pinned to the top:

- After every build, each big dial's resting centre and diameter are measured.
- **Per dial:** `progress = scrollOffset / (restY − barY)`, clamped 0–1 and eased with `easeInOutCubic`. The ring follows the page up, then slides sideways into its slot and shrinks:
  - Position goes from its rest position to the slot centre.
  - Diameter goes from its rest size to **32**.
  - Stroke grows from 5.8 % to 12.5 % of the diameter, so the small ring still reads.
  - The figure fades out early (`opacity = 1 − e × 2.4`).
  - The strain-target band is shown only while `e < .5`.
- **Bar:** 56 tall (32 + 2 × 12), split into three equal columns across `width − 2 × 20`. Its ground is `p.bgTop` with a `p.line` bottom border.
  - It fades in once the furthest dial passes 35 % of its travel (`(max − .35) / .65`), sliding down 8 px as it appears.
  - **Names** fade in over the last 25 % (`F.caps` w800 ink, 8 to the right of the ring) and only become tappable at 99 %.
- The big dial is hidden (opacity 0) the moment the page moves at all, so the flying copy is the only one visible.
- Tapping a name in the bar opens the same detail screen as the dial.

### 11.4 Monitors (under the dials)

- Two `Surface`s side by side with 12 between, at equal heights (`IntrinsicHeight`). Padding 16/16/12/16.
- **Title:** `F.caps` w800 ink in a `FittedBox`, with a `BoldChevron` at the end. Then a gap of 20.
- **Status square:** 40 × 40, radius 8, its hue at 20 %:
  - Health: a check, a triangle-alert or a minus.
  - Stress: the score `1.2` in `F.n17` w700.
- **Beside the square:** the word in `F.caps` w800 in the hue (`WITHIN RANGE` / `OUT OF RANGE` / `NO DATA`, or `LOW` / `MEDIUM` / `HIGH` / `BUILDING` / `NO READING`), then the sub-line in `F.num(F.cap)` w600 ink2 (`4/4 Metrics`, `14:20`, `Needs a night`).

### 11.5 My Day

- **Section head:** "My Day" in `F.t1`. The trailing `PlusButton` opens the plus menu (§11.6).
- **ACTIVITIES card:** a `Surface` with padding 16/8/16/16.
  - **Header:** `ACTIVITIES` in `F.caps` tracking .6 (indented 4). On the right, a `maximize2` icon (I.md ink3) in a 44 box opens the sideways day-HR screen (§14.3).
  - **Rows:** last night's sleep first, then the day's sessions oldest first, 12 apart. The empty state is "Nothing recorded for this day yet." in `F.body` ink3.
  - **Each row:** ground ink 8 % over `card`, radius 12, padding 8/8/16/8.
    - A **block**: minimum 112 × 48, radius 8, horizontal padding 16. It is `blockSleep` or `blockSession` in colour, with a white icon at I.lg, 12, and a white value in `F.n24` w700. The value is the session's strain, or its length when it has no strain.
    - 20, then the name in `F.caps` tracking .6 (2 lines).
    - The start time over the end time in `F.num(F.cap)` w700 ink3, 8 apart.
    - A **span mark** 8 × 40: a 2.5 px vertical line in the row's colour with white dots of radius 3 at both ends.
  - **Buttons:** 24 below the rows, ADD ACTIVITY and START ACTIVITY side by side with 12 between. START appears only on today.
  - Tapping a sleep row opens Sleep detail. Tapping a session opens the recorded-activity screen (§14.2), and Home reloads if it changed.
- **TONIGHT'S SLEEP** (today only):
  - The header row opens the Sleep Planner.
  - **Two halves** with a `- - - -` between them (ink3, 16 down). Each half is an icon at I.lg in ink2, 8, and a time in `F.n24` w700. Under that:
    - Left: `RECOMMENDED\nBEDTIME` in `F.over` w700 ink2.
    - Right: an 8 px status dot and its word: `ALARM ON` (green), `SENDING TO BAND` or `NOT CONFIRMED` (yellow), `ALARM OFF` (ink3, with the word in ink2).
  - Then 16, and the SET / EDIT ALARM button.

### 11.6 Plus menu

- **Barrier:** char at 45 %. The menu fades in over 180 ms (`Ease.standard`). Tapping outside dismisses it.
- **Panel:** 252 wide, rows 66 tall, 14 padding above and below, radius 34. Gradient and border as in §6, plus the shadow.
  - **Placement:** its bottom edge sits on the button's centre line and its right edge 28 in from the button's right edge, so it opens upward. Too close to the top, it opens downward instead.
- **Rows:** a 28 indent, the icon at I.lg ink2 in a 24 box, 16, then the label uppercased in `F.cap` w800 tracking 1.4:
  - `START ACTIVITY` (timer)
  - `ADD ACTIVITY` (plus)
  - `STRENGTH TRAINER` (dumbbell)
  - `ADD TO MY JOURNAL` (notebook-pen)
- While the menu is open, a cross version of the plus button is drawn in exactly the button's place, so the button seems to turn into an ×.

### 11.7 My Dashboard

- **Section head:** "My Dashboard" with `CUSTOMIZE` (`F.caps`) and a pencil (I.md) on the right.
- **Editor:** a scrolling sheet titled `MY DASHBOARD`, with the sub-line "Choose what to show and drag to reorder."
  - A reorderable list, 55 % of the screen tall. Each row: a grip handle in a 44 box, the metric icon at I.md ink2, the title in `F.body`, and an `AppSwitch`.
  - **Save** is a white `BigButton`.
- **Default tiles:** Strain & Recovery chart, HRV, resting HR, steps, zones 1–3, zones 4–5, sleep performance.
- **Metric row:** a `Surface` with padding 16 that opens Trend View on that metric.
  - The icon at I.md ink3, 12, then the title in `F.caps` (2 lines).
  - On the right: the value in `F.n24` w700, a 10 px `DeltaTriangle`, and the comparison under it in `F.num(F.cap)` w600 ink3.
  - A row with no arrow keeps half a triangle's width of space, so every figure lines up on one edge.
  - **Arrow colour:** `optimal` when the change goes the way the metric wants, `poor` when it does not, `n400` when neither direction is better. No arrow when there is no comparison.
  - **What is compared:** a weekly metric shows this week's total against last week's. Any other metric shows its newest value within 7 days against the mean of the 7 days before that value.
- **Strain & Recovery tile:** §12.8.

---

## 12. The chart system (`lib/ui2/scrub.dart`)

### 12.1 One anatomy for every chart

```
 CAPTION (date or "Average")            ┌ D  W  M  6M ┐
 72 bpm   [▲ 4% vs. prior week]         └─────────────┘
                                   ‹  APR 10 - APR 16, 26  ›
 Sentence that says what the chart says.
                                        ▢ TYPICAL RANGE
   80 ─────────────────────────────────────────
                 ▓        ▓
   60 ──────▓────▓────▓───▓────────▓──── (gridlines p.line)
        ▓   ▓    ▓    ▓   ▓   ▓    ▓
   40 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   (average, dashed)
       Mon  Tue  Wed  Thu  Fri  Sat  Sun   (x labels)
        6    7    8    9   10   11   12
```

- **The chart draws itself; `ScrubArea` reads the finger and draws the guide.** Both measure the plot with the same `plotRect(size, inset)`, so the guide and the drawn point always agree.
- **Insets** (around the plot):

| Chart type | Left gutter | Top | Right | Bottom band |
|---|---|---|---|---|
| `ScrubColumns` | 40 (ticks) | 24 | 0 | 32 (x labels) |
| `ScrubLine` | 40 | 24 | 0 (slots) / 8 (edge-to-edge) | 32 |
| `ScrubRanges`, `ScrubPair` | 40 | 32 | 0 | 32 |
| `ScrubMonths` | 40 | 32 | 8 | 32 |

  A card with no axis labels passes `gutter: 0` (the week cards).
- **Slots or edges.** Days and bars sit in the **middle of equal slots** (`slots: true`). Minute and 6-month series run **edge to edge** (`slots: false`): index 0 is the left edge and the last index is the right edge.

### 12.2 Shared drawing rules

| Element | Spec |
|---|---|
| Gridlines | solid 1 px `p.line`, one per tick, across the plot |
| Y tick labels | `F.num(F.over)` w600 ink3, right-aligned in the gutter (gutter − 8 wide), centred on the line |
| Average | **dashed** 1 px, ink 28 %, 4 on / 4 off, behind the data, **unlabelled** (the readout above carries the number) |
| Typical range | a band, ink 7 %, radius 6, behind the data; only for line metrics on W and M |
| Highlight column | the day the screen is about: ink 8 %, width 76 % of the slot (12 % inset), from 8 above the plot to its foot, radius 6 |
| X labels | `F.num(F.over)` w600 ink3, line height 1.15, 4 below the plot, up to two lines (`Mon\n12`). The focused label (touched or highlighted) turns ink and w800. Labels near an edge are pulled inside it. `''` means no label. |
| Gaps | `null` is never zero. A bar is simply not drawn. A line breaks when two points are more than `gap` slots apart (1 for daily lines, 3 for hourly, 25 minutes for minute lines). |

### 12.3 The finger

**One finger down** (anywhere on the chart, including a tap):
- The nearest point is selected and `onScrub(i)` fires.
- A **soft rounded column** is drawn behind that point: ink 10 %, radius 4, from 12 above the plot down to the very foot, so it also covers the x label. Width: `min(80 % of slot, 48)` for bars, 16 for lines, or the **whole month** on a 6-month chart.
- Every **other** bar dims toward `bg` by 72 %. The touched bar's value label and x label turn ink.
- On a line, a **dot** sits on the touched point: radius 6 in ink, in a radius 8 ring of `bg`.
- The **readout above the chart** changes:
  - The caption becomes the date ("Wed, Apr 12, 2026"), the week ("Apr 6 - Sun, Apr 12, 2026") or the clock time ("14:05", "14:00 - 15:00").
  - The value becomes that point's value.
  - The delta chip hides.
  - A stacked column **splits into its layers** (Zone 3 over Zone 2 over Zone 1, each in its colour). A dual chart shows both figures for that day.

**Moving** follows the finger. **Lifting** clears everything, so the chart, the readout and the chip return to their default state. **A mostly vertical drag** gives the gesture to the page.

**Rest state:** some cards keep a column at rest on the newest day (`highlight: last` on week cards; the Strain & Recovery tile). A touch moves the column to the finger, and lifting puts it back.

For a screen reader, the chart is one slider: its label is the chart's name, increase and decrease walk the points, and `describe(i)` says the date and value.

### 12.4 Columns (`ScrubColumns`)

- **Bar width:** `barWidth`, or by count: ≤ 4 bars use 62 % of the slot, ≤ 8 use **38 %** (a week: slim bars with air between), more use 56 %. Bars are centred in their slots.
- **Shape:** grown from zero (or from `lo` if `lo > 0`), top corners radius 2, square foot.
- **Colour:** `color`, or per bar through `colorOf` (recovery uses the traffic light).
- **Stacks:** segments from the bottom up in `segmentColors`, a 1.5 gap between them, each with corners of `min(3, width/3)`, the bottom one square. The bar's value is the sum.
- **Value labels:** above each bar (or stack) in `F.num(F.cap)` w700, in the bar's colour or `labelColor` (zone charts use ink), 2 above the top. Shown on **week** ranges only; a month has too many bars.
- **Month marks** (6M weekly or stacked): a short **white 2.5 px round-capped line** at each month's average across that month's columns (inset 2). Its figure sits on a `bg` 55 % pill (radius 6) 8 above the line, only when the stretch is at least 40 wide.

### 12.5 Lines (`ScrubLine`)

- **Daily lines** (`markers: true`, week): the line is 2.5 px at 55 % of the hue, with a **ring marker** on every point (a `bg` disc of radius 6 with a hue ring of radius 5 and stroke 3). The value floats 20 above each point on a `bg` 45 % pill (radius 6), in the hue, turning ink when touched.
- **Dense lines** (`markers: false`: month, minute and hour lines): 1.5 px at full hue.
- **Fill:** under every run, the hue at 22 % fading to 0 by the plot's foot. (`colorAt` lines have no fill.)
- **`smooth`:** a cardinal spline **through** every point, with each control point clamped between its neighbours' heights, so a peak is never overshot. Used for hourly HRV.
- **`colorAt`:** each segment is coloured by the mean of its two ends, 2 px.
- **Hooks:** `paintUnder` (for example the night shaded at `dialSleep` 16 %, radius 6, on the HRV day chart) and `paintOver` (for example a hue dot of radius 3 on every hour that has a value).

### 12.6 Floating bars (`ScrubRanges`): bed to wake

- **The time axis runs down:** evening at the top, morning at the bottom. Values are minutes after noon.
- **Clock axis:** a 4-hour grid starting at 19:00, normally 19:00–11:00. It extends by 4 hours whenever a night comes within 90 minutes of an edge, so the times written above and below the bars always fit.
- **Bars:** 38 % of the slot (≤ 8 nights) or 56 %, radius 2.
- **Times:** the bedtime is written above the bar and the wake time below it, `F.num(F.cap)` w700, 4 away. Written on every bar for a week, otherwise only on the focused bar.
- **Consistency mode** (`emphasis`): only the newest or touched bar is coloured; the rest turn `barGrey`. A **dashed "usual" line** (ink 35 %, 2 px, 4 on / 6 off) runs through the mean bed and wake times of the 7 nights before each night, drawn only when at least 3 of those nights exist.
- **Month tags:** a dashed ink 30 % line at the average bed and wake time, with the time in an **ink pill** (radius 6, text in `bg` colour, w800) at the left edge, covering the tick labels it replaces.

### 12.7 Two lines (`ScrubPair`) and six months (`ScrubMonths`)

**`ScrubPair`** (sleep need against hours slept):
- Two lines on one scale from zero, each 2.5 px at 60 %, with ring markers.
- Series A's numbers sit above its points; series B's sit below.
- Colours: need is `optimal`, hours is `dialSleep`.

**`ScrubMonths`** (6M of a daily metric):
- **Background:** every day drawn as a faint ghost. A line at hue 22 % (1.5 px) with a 12 % → 0 fill, or for floating metrics thin ghost bars at hue 16 %.
- **Per month:**
  - A **short 2.5 px line at the month's average**, spanning that month's days. It is ink when lit and 60 % when another month is touched.
  - The figure sits above the line in `F.num(F.cap)` w700.
  - The **newest month** also shows its change on the month before (`+8%`) under the line. Both the line and the note take `optimal` or `strainDown` when the metric has a better direction.
  - The month's name is centred under its days.
  - Months shorter than 40 wide skip the labels.
- **Touch:** selects a whole month. The column spans the month and the readout shows that month's average.

### 12.8 Strain & Recovery (Home tile)

The week's two stories on one chart.
- **Card:** flat `card`, radius 14, padding 20. Title `STRAIN & RECOVERY` with an info icon (I.lg ink2) that opens an explanation sheet.
- **Chart:** height 258, insets 24 / 32 / 36 / 40 (left, top, right, bottom).
- **Grid:** four gridlines. Left labels are strain `0 7 14 21` in `dialStrain`. Right labels are recovery `0% 33% 66% 100%`, each in its own recovery colour. All are `F.num(F.over)` w700.
- **Lines:** recovery in ink2 at 70 % and strain in `dialStrain` at 60 %, both 2.2 px with round joins. Gaps break the lines.
- **Markers:** a `bg` disc of radius 6.5 with a 5-radius ring at 2.4 stroke. Recovery points take their band colour; strain points are blue.
- **Labels:** `82%` and `9.4` in `F.num(F.cap)` w700, 12 from their points. **When the two points of a day are close, the lower one's number goes under it and the higher one's over it**, so neither covers the other. The focused day's labels turn ink.
- **At rest** the newest day carries the column (ink 10 %). A touch moves it.
- X labels are `Mon\n12`, 12 below the plot, line height 1.2.
- **Empty:** "Nothing recorded this week." centred in a 128-tall box.

### 12.9 The readout (`ScrubReadout`)

```
WEDNESDAY, APR 12, 2026        ← caption: F.num(F.over) ink2, uppercased
72 bpm                          ← F.n34 w700 ink + unit F.head w600 (big)
[▲ 4% vs. prior week]           ← `under`, 8 below
```

- **Small variant** (`big: false`, used in cards): the value is `F.n24` and the unit is `F.cap`.
- The value always sits in a `FittedBox(scaleDown)` aligned left.
- **Multi-readout:**
  - For a dual chart: two figures, each in its hue in `F.n34`, with a name under each (`AVG. NEED`, `AVG. HOURS`) and its own delta chip.
  - For a touched stack: one row per layer, top layer first.

### 12.10 Axes (`trendAxis`)

The axis follows the data. There are no fixed ranges unless the scale has its own ceiling.
- **Columns start at 0.** Their top is the largest value.
- **Lines** add room on both sides of their range: `max(12 % of the range, 2 % of |max| + 0.5)`. They never go below 0 unless the metric is signed.
- **Step:** the finest "nice" step (1, 2, 2.5 or 5 × 10ⁿ; for durations 30, 60, 120, 180, 240, 360, 480, 720 or 1440 minutes) that needs at most **6 intervals** for columns or **7** for lines. Both ends are then rounded out to that step.
- **Ceilings:** a scale with a ceiling (strain 21, percentages 100) stops at it and is cut evenly at the top: `0 7 14 21` or `0 25 50 75 100`.
- **Zoom:** on a zoomed minute chart the axis rescales to the minutes in view.
- **Tick text:** durations `7h` / `7:30`, `1.5k` from 1,000, decimals only where the metric uses them.

Fixed-scale exceptions (charts drawn outside `trendAxis`):
- Workout HR: rounded to 25 bpm with 4 bpm of padding and at least 50 bpm of span. The scale stays the **session's own** while zooming.
- Day heart rate: 20–220 bpm, grid every 40.
- Strain-through-the-day curve: 0–21, 4 ticks.
- Week cards: 0 to 1.12 × max, no labels.

### 12.11 Zoom

Minute-resolution charts zoom: the Trend View day line, the recorded-activity HR chart and the day heart rate.
- **Pinch:** the new span is the starting span ÷ scale, clamped to a minimum (Trend day 30 min, activity 2 min, day heart 30 min) and to the full span.
- **The point under the fingers stays under them:** `from = under − (focal + pan) × span`. Moving both fingers sideways pans the view.
- **One finger** still scrubs on the Trend day chart and the activity chart. On the sideways day heart chart, one finger **pans** a zoomed view instead.
- **Reset:**
  - Trend View: a "Reset zoom" `TextAction` with `zoomOut` in a 44-tall slot above the chart. The slot is always reserved, so the chart does not jump when the action appears.
  - Activity chart: the RESET chip, top-right.
  - Day heart: a magnifier that toggles between the last 4 hours and the whole day.
- **X labels on a zoomed day** step at the finest of 360/240/180/120/60/30/15/10/5/2 minutes that leaves at least about 3 labels. Unzoomed: `00:00 06:00 12:00 18:00 24:00`.
- Selection and zoom both reset when the range, the window or the metric changes.

### 12.12 Data-shape rules for every chart

- Lay data out **dense by calendar day** (`denseDays`): one slot per day, `null` for a day with no row. A stored list can skip days, so the newest point is not necessarily "today", and a line must not be drawn straight through a gap as if it had been measured.
- Label the x axis from **each point's own date**, never its index.
- **Today is left out of averages** while it is still in progress. When that happens, an info row under the chart says "Average does not include today (Oct 26)".
- Weekly metrics (zones, strength time, volume) are **totals**: the week is one total, and a month or 6 months show the average week. Strength days with nothing logged count as zero (`zeroFill`).
- **Typical range** = mean ± 1 SD of the 28 days before the window starts, and only when at least 7 of those days exist.

---

## 13. Trend View (`trend_view.dart`)

Opened from a dashboard row, a week card chevron, or a detail screen. One metric at a time.

- **NavBar** "Trend View".
- **Metric pill:** 64 tall, padding 20, ink 12 % over `card2`, radius 12. The icon at I.xl, 20, the title in `F.caps` w700, and a chevron (I.lg) that points down, or up while open.
  - Tapping it opens the **picker** in place: a `card` with radius 14, grouped Strain / Recovery / Sleep. Each group header is `F.over` w700 ink2 followed by a hairline. Rows have an icon at I.lg ink2, 16, the title in `F.caps`, and the current row on `card2` with radius 12.
  - The picker lists only the metrics that are on the dashboard (or all of them until the dashboard has been saved once).
- **Readout row:** the readout on the left and the **range segments** on the right.
  - Segments: 179 wide, 44 tall. The track is char 50 % over `bg`, radius 14, padding 4. The selected segment is a `card` fill with radius 12 and `F.caps` ink; the others are ink3.
  - Labels are `D W M 6M`. `D` appears only for metrics with a day shape. The width stays the same whether there are 3 or 4 segments.
- **Window stepper:** right-aligned. ‹ and › chevrons (I.md, in 32 × 44 boxes; › is drawn in `p.track` and disabled when the window ends today) around `APR 10 - APR 16, 26` (or the day's name) in `F.over` w700.
- **Sentence:** `F.head`, line height 1.3. It says what the chart says, with the numbers in it:
  - Week with a typical band: "Your average HRV during this 7-day period was within its typical range (52 - 64) at the time."
  - Weekly metric: "During this 7-day period, your total time in HR zones 1-3 (3:12) was above your previous 7-day total of 2:40."
  - Day: "Your average heart rate variability asleep today is 58 ms."
- **Legend** (right-aligned, items 20 apart): a 16 swatch with radius 6, 12, then `F.caps`. Examples: `TYPICAL RANGE` (ink 12 %), `SLEEP` (`dialSleep` 40 %), `SWS (DEEP)` / `REM`, or a dashed stroke for "Usual bed/waketime".
- **Chart:** 24 below, 288 tall (320 for floating and 6M floating charts).
- **Under the chart, as relevant:**
  - The "does not include today" info row, or "Zone time is derived from your heart rate."
  - **Strain breakdown (days):** a 12-tall bar split by band, each segment radius 6 with 2 gaps. Then rows of a 12 swatch, the count `3x` in `F.n24` w700, and the band name in `F.body` ink2.
  - **HR zones breakdown (weekly total / avg. weekly total):** the same shape, with times.
  - The VO₂ max source panel.
  - A **"What is X?"** card.

**Range behaviour:**
- **Opening range:** D when the metric has a day shape and the screen opened on today; otherwise W. If D has nothing to draw and the user has not chosen a range yet, it falls back to W by itself.
- **Window lengths:** D 1 day, W 7, M 30 (28 for weekly metrics, as 4 whole-week columns), 6M 182 days (26 weekly columns, or the month-at-a-time chart for daily metrics).
- **X labels:**
  - W: `Mon\n12`.
  - M: `Apr\n16` on every 7th day counted back from the end; weekly metrics use `Apr 1 - 7`.
  - 6M: the month name on the first column of each month.
- **Headline:**
  - W/M/6M: "Average", or "Weekly total" / "Avg. weekly total" for weekly metrics, plus a **delta chip** against the previous window of the same length.
  - D: "Total" (running totals and hourly counts) or "Average".
- **Delta chip:** padding 8/4, radius 6, ground at the verdict hue's 18 % (or `card2` with no verdict). A 12 × 10 triangle, 8, then `12% vs. prior week` in `F.cap` w700 in the hue: `optimal` when better, `strainDown` when worse, ink2 when there is no verdict.
  - Signed metrics, or a previous value of 0, show the change in their own units instead of a percentage.
  - 0 % shows no triangle.
- **Colours:** every line metric is `dialStrain`. Columns take their group's hue: strain `dialStrain`, recovery `optimal` (recovery itself uses the traffic light per bar), sleep `dialSleep`. Zones use the zone hues; restorative sleep uses REM under SWS.

**Metric catalogue** (`kTrendCatalogue`):

| Group | Metrics |
|---|---|
| Strain | day strain (0–21, minute day line, cumulative), steps (hourly bars), HR zones 1–3, 4–5 and all (stacked, weekly), strength time (weekly, zero-filled), total volume load (weekly, kg), average HR (line, minute day), calories (hourly), VO₂ max (line) |
| Recovery | recovery (%, traffic light), HRV (line, hourly day with the night shaded), resting HR (line, lower is better), respiratory rate (line) |
| Sleep | sleep performance, time in bed (floating), hours vs. needed in hours (dual) and as %, consistency (floating with "usual"), restorative % and hours (stacked), efficiency, sleep debt (signed, never below 0) |

---

## 14. Detail screens built on this language

### 14.1 Strain detail (`activity/day_strain.dart`)

- **Day pager** under the NavBar.
- **Ring:**
  - Side `min(84 % of the width, 346)`, stroke 6.4 % of the side, track `p.track`, a `dialStrain` arc with a round cap.
  - The **30-day average** is a white tick across the ring, exactly as long as the ring is thick (15 % of the stroke wide, butt cap).
  - Inside: `LOCUS` (wordmark, ink3), the value in `F.n80`, and `STRAIN` in `F.caps` tracking 2.2. The whole block scales to fit inside the ring.
- **Caret** (20 × 8, ink 5 % over `bg`, with an ink 9 % edge) pointing up at the ring from the **rich stats panel**.
- **Stats panel:** four rows (zones 1–3, zones 4–5, strength time, steps).
  - Each row: padding 20/16, a `StatIcon` at 28 ink2, 16, the label in `F.caps` w700, the value in `F.n17` over the 30-day average in `F.num(F.cap)` ink3, and a 12 triangle in a 24 slot (`optimal` above the average, `strainDown` below).
  - Rows are divided by ink 8 % hairlines indented 20.
- **Comparison legend:** a strip of char 55 % over `bg` with radius 8 and padding 16/12. Both triangles, then `Sun, Oct 26` (`F.cap` w700) and ` vs. last 30 days` (ink2 w500).
- **Band sentence** in `F.body` w500, line height 1.4. Light < 10, moderate 10–13.9, strenuous 14–17.9, all out 18+.
- **Today's Activities** (`F.head` w700): cards of radius 12 with padding 8.
  - Each card: a `dialStrain` block 112 × 48 (radius 8, white icon and `F.n24`), the name in `F.caps` w700, times in 24-hour `H:mm`, and a 3 × 32 `dialStrain` bar.
  - Tapping a card opens the recorded activity.
- **Weekly Trends:** one card per metric (strain, zones 1–3, zones 4–5, steps, calories).
  - Each card: radius 12, padding 16. The title in `F.caps` w700 with a chevron (I.lg ink2) that opens Trend View on that metric. A small readout for the touched or newest day. A legend of 10 swatches for stacks. A **192-tall column chart** with no gutter and no ticks, value labels in ink, and the newest day highlighted at rest. Each card scrubs on its own.
- **Strain through the day** (`ChartFrame` with a 0–21 axis, `LineChart` in lavender) with its own readout.
- **Time in zones** and **What this is made of** (`card2` panel, `F.cap` ink3).

### 14.2 Recorded activity (`workout_detail.dart`)

- **Header:** §10.4.
- **Strain row** (64 tall): the strain in `F.n34` in `dialStrain`, a `_VsPill` (ink 10 %, radius 6, a 12 triangle in ink2 and the sport's 30-day average in `F.num(F.body)` w700 ink2), then `ACTIVITY STRAIN` in `F.over` w800 tracking 1.4 ink3.
  - **While a finger is on the chart, this row becomes the reading:** `143` + `bpm` in `dialStrain` and the clock time under it. It keeps the same size and place.
- **HR chart** (216 tall):
  - **Plot:** ground ink 4 % over `bg`. Grid in ink 10 %: a line every 25 bpm and the width in quarters. Tick labels `F.num(F.cap)` ink3 at the left edge, over the grid.
  - **Trace:** a `dialStrain` line at 2 px over a fill from 42 % to 2 %.
  - **Session edges:** start and end are dashed lines (ink 80 %, 1.5 px, 4/4) with a dot of radius 4 at the foot and the clock time under each.
  - **Finger:** a dotted ink line down the chart and a dot on the reading (an ink disc of radius 10 with a `dialStrain` centre of radius 8).
  - **Zoom:** pinch to zoom and pan, down to 2 minutes. RESET chip.
  - **Lit zone:** when a zone card is selected, the trace turns ink3 at 1.4 px and each stretch in that zone fills in the zone's colour (85 % → 8 %) with a 2 px edge. Consecutive stretches are separated by a thin line in the ground colour.
- **Legend row:** a `TYPICAL RANGE` key (a box with dashed sides) and `DURATION 0:42:13` (`F.num(F.t2)`).
- **Zone cards** (zone 5 first):
  - `card`, radius 12, padding 18/20. `ZONE 3`, the bpm range, and the percentage in the zone's colour, all `F.caps` w800/w700 with tracking. On the right, the time in `F.num(F.t2)` with `:ss` in `F.num(F.body)` ink3.
  - **Bar** (24 tall): a hatched track (ink 14 %, 2 px diagonal lines every 6), the share filled in the zone's colour, and the sport's **typical range** as a dashed-sided ink 12 % box.
  - **Tap:** lights that zone on the chart. The bar then shows *when* the session was in that zone, laid along the session's length. A zone with no time is dimmed to 28 % and cannot be tapped.
- **Key statistics:** `KEY STATISTICS` (`F.body` w800 tracking 1.6) with `VS. 30 DAY AVERAGE` on the right.
  - A horizontal row of cards, each 43 % of the screen wide and 144 tall, radius 14, padding 16/16/12/16: icon and label, the value in `F.n34` (plus `:ss` and unit), and a `_VsPill`.
- **Milestone card:** an outline (ink 16 %, 1.5 px, radius 14) with a char disc ringed in lavender, `12/25` (count in `dialStrain`), "13 more until your next milestone", and an 8 px pill progress bar in `dialSleep`.
- **Edit** opens Add Activity's sheet in edit mode.

### 14.3 The day's heart rate, sideways (`day_heart.dart`)

Opened from ACTIVITIES ⤢. It **forces landscape** and restores the app's orientations on close.
- **Header strip:** `min(128, 30 % of the height)` tall, char 60 % over `bg`, with 2 px char borders. Over it, each mark (the night, each activity) shows its icon (I.lg) and figure (`F.num(F.n24)`) centred on its stretch. Marks that would overlap merge into a `MarkCount`, and zooming spreads them apart again. Under each mark, a 4-tall bar the width of its stretch in `dialSleep` or `dialStrain`.
- **Plot:** from 11.5 % to 83.5 % of the width, a fixed 20–220 bpm scale, grid every 40 (ink 8 %), tick labels `F.num(F.head)` ink3 in the left margin.
  - Stretches are shaded: the night at ink 6 %, activities at `dialStrain` 10 %.
  - **Trace colour by context:** the night in `dialSleep`, activities in `dialStrain`, the rest of the day in ink3 at 75 %. 1.6 px, broken across gaps of more than 5 minutes.
  - The **wake** is a dashed `recGreen` line and the **last reading** a dashed `dialStrain` line, with `STRAIN 12.4` written over the last reading.
  - **Clock labels** along the foot: the start, every 1, 2 or 4 hours depending on the span, and the end. Labels are never closer than 64; the ends win.
- **Gestures:** pinch zoom (minimum 30 minutes), one finger pans a zoomed day, and the magnifier toggles between the last 4 hours and the whole day. Close × at the top left.

### 14.4 Start Activity (`start_activity.dart`)

- **Always dark:** the char ground with the blue diagonal gradient, and a header band.
- **Header:** × (I.lg, white), the activity icon, the name in `F.t2` w600 white, and a `chevronDown` that opens the activity chooser (which includes Sleep and Nap).
- **TRACK ROUTE** with an `AppSwitch`, for route sports.
- **Pulse disc:** diameter `min(37.5 % of the width, 166)`, `dialStrain`, with a heart and the live HR in `F.n64` white. It beats as described in §8.
- **Strain-target dock:**
  - Collapsed it is 89 tall: `card` with a top radius of 30, and a handle 64 × 4 at ink 22 %. The row holds a mini ring (32, stroke 4) with the goal, `STRAIN TARGET`, a switch and `ON`/`OFF`.
  - **Swipe up or tap** and it grows to fill the space between the header and the start bar (280 ms, `Ease.standard`).
  - **Open:**
    - **Ring:** diameter `max(128, min(69 % of the width, 60 % of the free height))`, stroke 6.25 %, the deepening arc.
    - **Knob:** 64 across, ink 92 %, glowing, riding the ring at the goal's angle.
    - **Centre:** `ACTIVITY STRAIN`, the goal in `F.n80` or `F.n64`, its level word, and a reset button (a 32 ring with `rotateCcw`) that sets the goal to today's recommended strain (or 10).
    - **Interaction:** drag the knob or the ring round (`DialScrubber`, steps of 0.5, rounded to 0.1).
    - **Footer:** "A 14.0 Activity Strain represents strenuous cardiovascular exertion."
  - **Levels:** > 18 all-out, > 14 strenuous, > 10 moderate, otherwise light.
- **Start bar:** char, 64 + 24 + safe area tall, holding the START ACTIVITY pill. A sleep or nap in progress shows a running clock (`F.n48`), `SLEEP · SINCE 23:10`, and END and DISCARD controls.

### 14.5 Stress Monitor gauge

- The arc opens at the bottom, starting at 146° and sweeping 248°. Radius 44 % and stroke 3.5 % of its box.
- It is drawn as a blue → green → warm → orange sweep that dims at both ends, with an ink needle.
- `0.0` and `3.0` are written under the two ends.
- `stressColor(score)` interpolates the four stops.

### 14.6 Strength trainer

- Two tabs, PROGRESS and MY WORKOUTS.
- **Progress:** total volume load with its own W / M / 6M segments and page chevrons, drawn with `ScrubColumns` at a fixed slim bar width. A Personal Records list with ADD; tapping a record shows its progress as a `ScrubLine` with the same readout, once there are at least two sessions.
- **My Workouts:** Start a Workout (Quick Start), Generate with AI, Build a Workout, and saved workouts with a three-dot menu.
- Exercise photos from the bundled Free Exercise DB are cover-cropped thumbnails. A placeholder dumbbell tile stands in when there is no photo.

---

## 15. Honesty and copy

- **Never invent a value.** A figure that is missing is `--`. A metric that is missing as a whole is a `StatusCard`: *what* is missing → *why* (the pipeline's own reason first, a measured wear gap next, the screen's fallback last; "Nothing recorded says why" when nothing knows) → *what fixes it* (a button only if pressing it can change the outcome).
- **Stale is absent.** A number from an earlier night is not shown in today's slot; the reason is shown instead ("Last night is still being worked out.").
- **No streaks**, no "you have", no severity words on respiratory or illness surfaces. Observations state a pattern against the user's own baseline, never a cause.
- **Voice:**
  - Card titles are UPPERCASE `F.caps`.
  - Sentences are sentence case and plain ("Your average HRV this week is 58 ms.").
  - Empty states are short and factual ("Nothing recorded for this day yet.", "No strain recorded this period.").
  - Buttons are verbs in caps (`ADD ACTIVITY`, `SET ALARM`, `START ACTIVITY`) or sentence-case `BigButton` labels ("Sync the band", "See what was missing").
- **No other brand's name** anywhere in the UI. The wordmark is LOCUS.

---

## 16. Accessibility

- 44 pt minimum on every `Pressable` (enforced, and measured by the component sweep).
- Every icon-only control has a `semanticLabel`. Dead controls keep a label and report themselves as disabled.
- Charts are **sliders**: a label, increase and decrease, and `describe(i)` saying the date and value. A painter with no reading has no screen-reader form, so every chart must carry one.
- Hue is never the only carrier of meaning. Triangles carry the direction, words carry the status ("WITHIN RANGE", "ALARM ON"), legends name every colour, zones are named on their rows.
- **Text scale:**
  - The sweep test runs every component at 1.0, 1.4, 2.0, 3.0 and 3.1× and fails on any overflow.
  - Headline numbers sit in `FittedBox(scaleDown)`.
  - Tab labels are clamped at 1.3×.
  - Past 1.3× (`bigText`), `Numeral` wraps its unit under the number.
- **Reduced motion:** every animation lands on its finished state. Loops (sync arrow, pulse) stand still. Page transitions are cut. Clocks still count.
- **Contrast:** `ink3` and every `p.on(hue)` clear 4.5:1 on their worst surface. `ui2_contrast_test` sweeps every accent against every surface in both themes.

---

## 17. Enforcement, checklist, and known gaps

**`test/ui2_tokens_test.dart` fails the build on any of these in `lib/ui2`:**

| Banned | Use |
|---|---|
| `fontSize:` | `F.*` |
| `Color(0x…)` (except transparent) | `C.*`, `P.*` (only `theme.dart` declares pigment) |
| `Colors.white` / `Colors.black` | `C.white`, `C.char`, `p.ink`, `p.inkOn` |
| `BorderRadius.circular(<number>)` | `R.r*`, or `BorderRadius.circular(R.sm / 3)` and other token arithmetic |
| `.repeat(` | a self-reversing controller |
| `Duration(…)` | `Motion.*` via `motion()` |
| `GestureDetector` / `InkWell` / `Listener` / `RawGestureDetector` | `Pressable`, `Scrubber`, `DialScrubber`, `SwipeHandle` |
| `BackdropFilter(` | `Glass` |
| `TextButton`, `AlertDialog(`, `showModalBottomSheet(`, `TextField(`, `Switch(` | `TextAction`, `AppDialog`, `AppSheet`, `AppField`, `AppSwitch` |
| numeric `Icon(size:)` | `I.*` |
| numeric `EdgeInsets` | `S.*` |
| `Image.asset(` | `Art.*` |

Every new public widget needs a case in `lib/ui2/profile/gallery.dart` (or an entry in `_notComponents` if it is a screen), and every ui2 file is exported from `lib/ui2/ui2.dart`.

**Checklist for a new screen or chart:**
1. `final p = P.of(c);` first. Tokens only.
2. Cards: a `Surface` (graded) with a `F.caps` title. Radius 14 for the card, 12 inside it, 8 for a block or square.
3. Numbers: `F.n*` or `F.num()` on the baseline with their unit. `--` when absent.
4. Charts: `ScrubColumns`, `ScrubLine`, `ScrubRanges`, `ScrubPair` or `ScrubMonths` (or `ScrubArea` with your own painter), a `ScrubReadout` above, data laid out dense by day, `trendAxis` or a deliberate fixed scale, `describe` for the screen reader, and `yieldToScroll` when the chart sits in a list.
5. Minute data: `onPinch` with the focal-point formula and a reset.
6. Every hue from §2.4 with the meaning listed there.
7. Run the gallery sweep, the contrast test and the token test.

**Known gaps** (fix them when you touch the area):
- The hypnogram and `MetricDetail` charts still use their own scrubbing and guide lines rather than `ScrubArea`.
- The Recovery and Sleep dial detail screens have not been redrawn against references yet. Strain detail is the model to follow.
- `_PulseState` draws a Material `Icons.favorite` (filled) heart rather than a Lucide glyph.
- Some screens write their own 24-hour `H:mm` clock (`_ActivityCard` on the strain page) instead of following the user's 12/24 h choice through `formatClockOf`.
- Light theme: every token is defined and contrast-tested, but the reference matching was done in dark. Check new work in both themes.

---

## 18. Imagery

- Images are bundled and offline; nothing is fetched at runtime. A screen never writes an asset path: it uses `Art.<slot>.image()` (`theme.dart`), which draws nothing, never a broken-image icon, when a file is missing.
- Device pictures (`bandHero`, `bandSide`, `bandTop`) are WebP with 2.0x and 3.0x siblings. Everything else (ring, watch, chest strap, workout, wellness, sleep, food, heart) is a flat, hand-cut SVG silhouette in one cream and one data hue, on a 400 × 400 viewBox, centred.
- Art is decorative unless given a `semanticLabel`. It never carries another maker's logo or name: devices are generic.
- Exercise photos come from the bundled Free Exercise DB (public domain, credited in `NOTICE.md`), cover-cropped 192 × 128 JPEG thumbnails, with a dumbbell tile as the placeholder.
- The `AuroraTile` grain is `assets/images/grain.png` tiled at 4 % opacity, painted once behind a `RepaintBoundary`.
