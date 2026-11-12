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

**Other:** sync arrow (amber `#FFB547`); coach orb ring `#7E57C2 → #3FA7B5 → #7E57C2` (sweep), also the edge of the strength trainer's AI card; sleep-plan panel `C.mint #DFF8EF` with char ink; cycle tracking `C.rose #FF7A9A`; food `C.foodRed #E61C24` (`C.domFood`: the Macros tab's one accent; protein is the strain blue and "over" the warning orange so neither can be mistaken for it); `C.lavender #A99BFF` only on `AuroraTile`, the hypnogram's light-sleep lane and the strength milestone ring; `C.calibrate #C452D6` only for calibration progress (the timeline ring, the sleeps-logged pips, the milestone and "more nights to calibrate" segments, the lit nights of the onboarding wheel), a mark and never a word (VIEW DETAILS goes through `p.on`). Volt `#B1F002` is spent only on the active tab pill, the `AppSwitch` on-track and Material `primary` in dark: never a button, a dot, a chip or a chart.

**No legacy names.** The pre-redesign accent names (`C.green`, `C.red`, `C.coral`, `C.blue`, `C.sky`, `C.purple`, `C.indigo`, `C.teal`, `C.aqua`, `C.sage`, `C.orange`, `C.yellow`, `C.pink` and the `C.dom…` domain accents) are deleted; every call site names the redesign token for what it means. `C.danger` (`#E61C24`) stays: **the one red for destructive actions and errors**, a SOLID fill under white ink (`ButtonTone.danger`, 4.6:1), the 2 px error ring on a field, the mark in `ErrorLine` and a destructive row's glyph. Never the colour of words. The recovery dial's low band (`C.recRed`) is the only other red.

Every activity in the catalogue is `C.dialStrain`; the HR-zone ramp everywhere (`ZoneRows`, zone cards, stacks) is `refZone1…5`.

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
| `F.display` | 36/42 | 500 | −1.0 | token sheet only; no screen uses it |
| `F.t1` | 28/34 | 500 | −0.7 | Home section heads ("My Day", "My Dashboard"), `ScreenTitle` on Health and the other tab roots, onboarding headlines |
| `F.t2` | 22/28 | 600 | −0.5 | sheet and dialog titles, Start Activity title, popup menu items (w400) |
| `F.head` | 17/24 | 600 | −0.4 | `Section` titles at w700, `Recommendation` headline (w700), Trend View sentence (height 1.3) |
| `F.body` | 15/22 | 600 | −0.25 | body text, card headlines (w700), field text; the `BigButton` label at w800, uppercased, tracking 1.4 |
| `F.cap` | 13/18 | 600 | −0.15 | captions, notes, units, info rows, delta-chip text (w700) |
| `F.over` | 11/14 | 700 | +0.3 | tiny labels, uppercased by the caller: pager date, readout captions, x/y chart labels (via `F.num`) |
| `F.caps` | 12/16 | 700 | +0.35 | **the card-title voice**: dial names, card titles, row titles, buttons, legends, segments. Always uppercased by the caller. |
| `F.wordmark` | 24/1 | 400 | +1.5 | LOCUS in Super Bubble, drawn through `Wordmark` (never a bare `Text`): the pull-down, the boot cover, the strain ring (ink3), the share poster |

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
| `R.sm` | 6 | chips (delta chip, `_VsPill`, `Pill`), legend swatches, typical-range band, highlight columns, value-label pills, sleep-plan panel, axis tags |
| `R.md` | 8 | activity block, monitor square, plus button, fields, alarm button, detail link rows, popup menu, comparison legend strip |
| `R.lg` | 12 | inner rows and cards: activity rows, day buttons, week cards, zone cards, Trend View metric pill and picker rows, the selected range segment and `SubTabs` item, selection chips, the `ActionCard` action, snackbar |
| `R.xl` | 14 | every `Surface` card, dialogs, Strain & Recovery card, key-stat cards, picker card, the range segment and `SubTabs` track, dashed `StatusCard` outline |
| `R.xxl` | 18 | sheet top corners, date and time pickers' dialog shells |
| `R.pill` | 999 | tab bar, tab pill, `BigButton` (the compact one too), RESET chip, START pill and the live transport, switches, grab handles, onboarding step bar, progress tracks and pips |

A pill is for a **bar, a track or a full-width primary button** — never for a chip, a selection tile or a small button: those are `R.sm` (chip), `R.md` (button) or `R.lg` (row). The range segment is `RangeSegments`, not a hand-rolled row of pills.

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

Circles: dials, rings, the monitor stress square's contents, `IconChip` (32), an inverse or glass `RoundIconButton` (48), the coach orb (40), the + tab button (40), the knob (64), the pulse disc, markers.

---

## 6. Depth, gradients and effects

- **Elevation:** dark mode has none; depth is the tonal grading in §2.2. Light mode uses `el(1)` = 0/8/24 at 6 % char, and deeper levels multiply it.
- **The only real shadows** are the plus-menu panel (char 50 %, blur 32, y 8) and the strain-target knob glow (ink 18 %, blur 16, spread 4).
- **The tab bar** is an opaque char/slate rounded rectangle (`R.xxl`) with no shadow and no glow. Its only ornament is the rim: a `S.hair` gradient outline lit at the top-left corner and gone by a fifth of the way round — white 30 %, then 9 % at 18 %, 4 % at 45 %, and 4 % to the end — as if one light sat above and to the left. The selected tab carries a pool of light on its foot: a `S.x12 * 2` circle, radial white 26 % → 0 % in five stops, centred on the tab's bottom edge and clipped by the bar. The gradient reaches zero at the circle's own edge, so it has no outline to see.
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
| The one aurora (`AuroraTile`) | on no screen now that the Sleep screen's Total sleep hero is gone (it stays in the gallery): two soft radial fields of lavender, solved for `p.ink` (`p.aurora`), plus 4 % grain, radius 18. Every word on it is `p.ink`. **No other card is an aurora**; the scallop badge and the onboarding "river" are gone |

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
| `CoachMark` | a rounded-square speech bubble, its tail dropped square from the bottom edge, with a heartbeat across it; Lucide's 24 grid at 1.5, never under 1 px | the coach everywhere: `AiOrb`, the AI coach rows, the coach's insights and actions. The app has no sparkle, star or wand glyph |
| `SyncArrowMark` | flat-cut up arrow in orange | strap badge while syncing |
| `MarkCount` | count in a 1.5 px ring | grouped activity marks on charts |
| `clusterMarks` | groups marks whose centres are within `gap` of the group's mean; zooming spreads them apart again | day-heart and chart marks |

**The wordmark** is the one place the app's words are not Figtree: `F.wordmark` is `LOCUS` in Super Bubble (fsuarez913, dafont, free for personal and commercial use; `assets/fonts/SuperBubble/LICENSE.txt`), 24 px, tracking 1.5, never given a fallback because nothing else is ever set in it. The pull-down on Home, the boot cover, the strain ring and the share poster all use it. `Wordmark` is a lighter cut of the font than the file draws: the word is painted into its own layer under an erode filter of `kWordmarkThin` (1.2 px across a stroke), which eats the letters in from every edge and opens the heavy face's tiny counters (the O's hole, the U's slit); it works on the pixels, so it holds on gradients, and the font file itself is untouched. `WordmarkFill` is the gray word with white written into it from left to right (a soft edge): the refresh. Another "free" display font is not a substitute until its licence allows a public repo and APK: Mochi Boom DEMO, for one, is personal-use only and may not be published.

**The Locus mark** (`logo.dart`, geometry in `logo_geometry.dart`): a cursive L, one continuous stroke with a loop at the top and one at the foot. The outline is the source artwork traced (99.3 % pixel overlap, counters as even-odd holes) in a 1000 × 1000 box, the artwork's own framing; never redraw it by hand. `LocusTint`: `ink` (the theme's ink: white on dark, char on light; the default everywhere), `strain`, `recovery`, `sleep`, `dials` (strain blue → optimal). The brand files are cut from the same outline (`assets/brand/`: white and black marks, dark, light and dial-colour icons, an animated SVG), and so is the launcher icon (white on black; `adaptive_icon_background` black).

Chevron convention: `BoldChevron` where the chevron is part of a label (pager, dial name, monitor title). Lucide `chevronRight` (I.md ink3 or I.lg ink2) where the whole row or card is the door.

---

## 8. Motion

One gate: `motion(c, d)` returns zero under reduced motion, `animate(c, t)` returns 1, and `Motion.enabled(c)` lets code branch on it. Page transitions are the platform's own (Cupertino slide with swipe-back on iOS), gated by the theme. Sheets use `sheetMotion`. **No `.repeat(`**: a looping animation is an `AnimationController` that reverses itself from a status listener and stops when motion is off.

**The mark is written, not faded** (`LocusMark`, `Motion.logo` 2.4 s). A pen runs the stroke's own route (`kLocusRoute`: in at the crossbar, up and clockwise round the top loop, down the stem, round the foot loop, out along the leg) at 1.3 × the stroke's typical half-width, and the ink is clipped to the exact outline, so the finished drawing is the mark itself. Once (`animate`): the pen takes the first 80 % with `easeInOutCubic` and the mark holds. Looping (`loop`, the boot cover and Home's loading state): written in the first half, held, then lifted back off from where it started. Reduced motion shows it still.

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
| `RangeSegments` | the D / W / M / 6M switch over a `char` 50 % track (`R.xl`), the chosen one lifted onto a `card` tile (`R.lg`). Trend View, the strength trainer and the weight screen all wear this one; no screen rolls its own. |
| `WindowPager` | "‹ OCT 24 - OCT 30, 26 ›": which window the chart below shows. `BoldChevron` in a 36 × 44 target, dead at ink 22 %, the date `F.over` w800 at +1. |
| `DialScrubber` | a drag round a ring. The angle is measured clockwise from 12 o'clock. It never wraps: carried past 12, the value holds at the end it came from. A touch that starts inside 55 % of the radius (where the dial's own buttons sit) is ignored. Slider role. |
| `SwipeHandle` | a vertical swipe of 24 px or more fires once (up or down). A tap that moves less than 8 px toggles. |
| `Dismissible` | swiping the Calibration timeline card away hides it until tomorrow. |
| `SideDrag` | a sideways drag that reports its velocity on release, for a card thrown off a stack (the daily cards, §11.4a). A vertical drag stays with the page. It carries no semantics: a tap does the same job. |
| `LocusPullRefresh` | pull to sync on Home (today only, with a paired band): §11.1a. The page waits at most 90 s; the sync carries on in the background. |

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

Bar order, by default: **Home · Health · (+) · Strength · More**, and the user can reorder it or hide Strength and Health (below). The (+) is an action, not a destination.

- **Bar:** a floating `Glass` pill, inset 16 from the sides and from the bottom safe area, minimum height 64, inner padding 4, `p.line` border.
- **Tabs:** icon `I.lg` above a label in `F.over` (w700 active, w600 inactive). Text scale is clamped at 1.3 inside the bar.
- **Active tab:** a volt pill (`p.fill(C.volt)`) with char ink, animated over `Motion.base` with `Ease.standard`. Inactive tabs are bare ink3.
- **(+):** a 40 circle in `card2` with a `plus` icon at I.lg.
- **AI:** the coach orb (`AiOrb`): a sweep ring round a `card` disc with the `CoachMark`, the glyph scaled to the disc (I.md at 48). It is the coach's mark everywhere: the round button under My Day (56), the chat header (24) and the gutter beside each answer (24).
- **Customising the bar:** a long press on any tab (or the (+)) opens the **Customise tabs** sheet (`NavBarEditor`): drag to reorder, switch a tab off to hide it, Save, or Reset to default. **Home and More always stay** (they read "Always on"): Home is the way back into the app, More is where Settings live. The (+) sits in the middle of whatever tabs are left. The order is stored in `Prefs.navTabs` (comma-separated `ShellDomain` names; empty means the default; `tabsFromPref` repairs anything unreadable and puts a missing Home or More back). A hidden tab is still built the same way, it just has no button; hiding the tab you are on drops you back on Home.
- **Banner:** a minimised workout floats as its own `Glass` pill 8 above the bar.
- **More tab** (`ProfileHomeView`): the photo header, then **seven doors, each a `MoreRow` opening a page of its own**, 12 apart, with outline glyphs and a small gear badge on the doors that are settings OF something: *My profile* (`circleUserRound`) → `MyProfileSettings`: Edit profile, Weight. *Reports* (`clipboardPenLine`) → the reports screen. *Device settings* (`watch` + gear) → `DeviceSettings` (§ Device settings below). *Heart rate zones* (`heartPulse` + gear) → `HeartRateSettingsScreen` directly. *Notifications* (`bell`) → `NotificationSettings`. *Your data* (`inboxDown`) → `YourDataSettings`: *In and out* (Import WHOOP data; Write to Health Connect / Apple Health) and *Copies and room* (Export and backup, Cloud account, Storage). *Settings* (`smartphone` + gear; `Update ready` on the right when one is) → the app's own settings. No door carries a weight or a battery value. **Every setting is behind exactly one door.** Journal and Locus Age live in the Health tab; the AI coach is opened from Home and the plus menu; there is no Alarm, Appearance (the app is always dark), Cycle tracking, Sleep goal or step-counter row anywhere (phone steps keep counting underneath; the planner keeps its stored goal). Each page is `settingsPage`: the `NavBar` with its name over `settingsGroup`s of `SetRow`s.
  - **Device settings** (`device_settings.dart`, `DeviceSettingsView`), laid out after the reference's device page: a 48 bar with × (close) left, `DEVICE SETTINGS` in the row-title caps centred, ⓘ right (the band's detail page). Then, 20 in: `CONNECTED TO` (optimal) / `NOT CONNECTED` (ink3) / `NO BAND PAIRED` in `F.over` w800 tracked 1.4 over the band's name in `F.head` w800 caps tracked 1.6 with a pencil (rename, only while connected); on the right `SYNCED TO` / `CATCHING UP` over the newest data's `MMM d, clock`, and a `cloudUpload` that syncs now. Two tabs, `STATUS` and `ADVANCED`, in `F.cap` w700 (ink lit, ink3 not) with a 3-tall ink underline under the lit one. **Status**: the band (`assets/images/band.webp`, a supplied product render cut out of its black ground, no maker's mark in frame) bleeding 64 off the left edge, and in the lower right the battery in `F.n48` with `%` in `F.n24`, the model under it in `F.cap` ink3, and a 6 × 88 vertical pill filled from the foot (`recGreen` 50 %+, `recYellow` 20 %+, `recRed` under). **Advanced**: the device ID and the firmware (each only when known) as two centred facts (a 32 glyph in ink3, the label in `F.over` w800 tracked, the value in `F.num(F.cap)` w700); then one `MoreRow` per action with a line under it in `F.cap` ink3 (16 in, 12 above, 24 below): Pair another band / Pair a band, Unpair band, Other devices (the sensor list), Band buzzes (Android), Double-tap, Compare with watch. Left out on purpose: broadcast heart rate, firmware check, erase and reboot (blocked or dangerous opcodes) and the maker's regulatory pages.
  - **Settings** (`MoreSettingsView`), the app itself, groups named for the question they answer, in this order: *Display* (Units: Metric / Imperial; Time format: System / 24-hour / 12-hour, each a `SetDropdown`). *Updates* (App updates: its value says what you have, what is ready or that it is checking, and a tap checks now; Check automatically; the release-server check where the build has one). *Connected apps* (Tasker and Shortcuts). *AI provider* (Model and key). *Privacy* (Crash reports; Contribute my health data where offered). *Help and about* (Report an issue, Notices and licences, Version: seven taps reveal *Developer*). Then the one destructive action alone at the end: a compact danger `BigButton` *Reset all data* with one line under it.
  - **Notifications** (`NotificationSettingsView`): *Health* (health exceptions, recovery ready, weekly lookback), *Band and alarm* (band alerts and the battery level they fire at, alarm not confirmed, no-alarm check-in), *Activity* (detected workouts, detected naps, HR zone alert with its target zone as a `SetDropdown` under it while it is on, movement nudge, step goal), *Reminders* (wind-down, medication, daily check-in, water and its interval), *Quiet hours*.
  - **`SetRow`** and **`settingsGroup`** (every settings-style list: Settings, notifications, devices, data, the band's pages): the More tab's anatomy. Each row is a card of its own (`moreCard`: `R.rXl`, the ink 5 % → `card` gradient), at least 60 tall, 12 apart, padding 16 across and 12 down; a 24 outline glyph in ink2 (a destructive row's glyph is `C.danger`; its words stay ink), 20, the name in spaced caps (`F.cap` w800, tracking 1.5) with an optional line under it in `F.over` ink3. On the right: an `AppSwitch` for an on/off setting (`switchValue`; the row and the switch do the same thing), a value in `F.cap` ink3, or a `chevronRight` at I.md ink3 when the row is a door. The group title is the `moreGroup` one: `F.caps` w700 ink2 tracked 1.6, 24 above, 12 below.
  - **`SetDropdown`**: a setting with a few named choices, as one `SetRow`: the chosen option in `F.cap` ink2 and a `chevronDown` (`I.sm` ink3) on the right; a tap on the row opens `showChoiceMenu` under it. **`showChoiceMenu`** is the app's one dropdown: a `card2` menu, `R.rLg`, an ink 10 % hairline, items 44 tall in `F.body` (the chosen one w700 with a check). **`AppDropdown`** is the same menu behind a labelled 44-tall `card2` field (`R.rLg`, the choice in `F.body` w600, a chevron), for forms such as the AI provider.
  - **`MoreRow`**: each row is a card of its own, **60 tall, 12 apart**, `R.rXl` (14), padding 16, a faint top-left gradient (ink 5 % over `card` → `card`). A 24 outline glyph in ink2 (in a 28 box), 20, then the name in **spaced caps** (`F.cap` w800, tracking 1.5, ink), and at most a short value at the right in `F.cap` ink3. No sub-line. `MoreRow.brand` takes a brand mark (the coach) in place of the glyph; `badge` adds a 11 glyph on a `card` disc at the glyph's lower right.
  - **`moreGroup`**: 24 above, the title in `F.caps` w700 ink2 tracked 1.6, 12, then the rows.

### 10.2 Home header

A `Stack` of three things, so the pager sits on the true centre of the screen:
- **Left:** `ProfileAvatar`, diameter 38.4 (`S.x12 × 0.8`). Opens the Profile page (`DataHighlightsScreen`): the period's best scores, streaks, notable stats and activity summary.
- **Centre:** the `DayPager`.
- **Right:** device status. Battery reads `78%` in `F.n17` w700 (ink, or `p.on(red)` when low), then 8, then a `StrapIcon` 24 tall. In the strap's gap sits either a 10 px dot (`recGreen` when connected, ink3 when not) or the bobbing orange sync arrow. Tapping it opens My Devices.
- Nothing sits under the header while numbers are being worked out: what is calculating is on **My sources** (§14.9).

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
- **`Observation`:** used on Home for the illness watch only. A graded card, a stethoscope at I.md and `HEALTH OBSERVATION` in `F.caps` w800 in the orange, then the headline in `F.body` w700.
- **The card components share one voice.** `SignalCard`, `TrendCard`, `ProgressCard`, `DeepDiveCard`, `GoalTrajectory` and `MetricRow` start with a bare icon (I.md ink3, never a chip) and an uppercased `F.caps` title, then the figure in a bold numeral (`F.n24`; `F.n34` for a trend card) with its unit on the baseline. Directions are `DeltaTriangle`s (10 in rows, 12 in cards), `optimal` when good and `poor` when not; "steady" is a short ink3 dash. A `TrendCard`'s sparkline is strain blue (sleep blue for sleep), like every line metric. `InsightCard` and `ActionCard` use a bare icon in the hue and a bold `F.body` headline; their actions are uppercased `F.caps` (with a chevron when they go somewhere), the `ActionCard` action on an ink 9 % block, radius 12. `InlineMetrics` labels are `F.over` w800 tracking 1.4 ink3 over `F.n24` ink figures. Progress bars are 8 tall pills, the hue on ink 12 %. `Consistency` dots are strain blue on ink 9 %.
- **`ChartFrame`** (the frame of the older painters) speaks the scrub charts' language: title uppercased in `F.caps`, the unit in `F.num(F.cap)` ink3, solid 1 px `p.line` gridlines, tick and x labels in `F.num(F.over)` w600 ink3, legend keys as 10 px squares (radius 6) with uppercased `F.over` w700 ink2 names, a usual-range band at ink 7 %.
- **`DayNav`** (metric screens) is drawn like Home's pager: a 32 tall track of ink 5 % over `bg`, radius 10, bold chevrons, the day uppercased in `F.over` w800 tracking 1.
- **Onboarding** (`OnboardingPage`, welcome.dart) is Char in both themes and stands on the dial screens' ground (`kDialGround`), with the dial margin, 16 above and 20 below. **One idea per page.** From the top: the progress (`OnboardingStep`), three equal segments across the page, 4 tall and 6 apart, white up to the current step and `DC.dim` after it, told to a screen reader as "Step 1 of 3"; then a picture centred in the room left over, 24 above and below; the headline in `F.t1` `DC.ink` (height 1.2), 12, the line in `F.dBody` ink2 (height 1.45), both **centred** under a picture and left-aligned on a page without one; what the state adds; then, at least 32 lower and pinned to the foot while the page is short, the actions: **one** ink `BigButton`, and 8 under it any second way on as an `OnboardingLink` (the words alone in `F.dNav` w700 ink2, tracked 1.2, caps, a full 44 tall, no ground). No footnotes under the actions. A page taller than the screen scrolls as one. The pictures are half the page wide, never over 200, and decorative (no semantics): **Welcome**, the Locus mark writing itself at 96 and the wordmark 24 under it, nothing else, then under the line a centred 16 optimal shield and `LOCAL · NO CLOUD` in `F.dLabel` ink2 (no chip ground); actions *Set up my band* and the link *Bring my history first*. **Pairing** (step 2), four hairline rings (white at 13 % fading to 4 % outward) round a disc 34 % of the side (`DC.weekCard`) holding the state's 32 glyph: bluetooth in strain blue (idle; searching while it scans), bluetooth-off in amber (the phone blocks it), search-x, unlink, alert or bluetooth in ink2 for the failures, a check on an optimal-green disc with green rings once paired. While it scans, two 2-wide strain-blue ripples grow out of the disc and fade, half a `Motion.logo` apart; reduced motion keeps them still. *Skip for now* is the link. **About you** (step 3) has no picture: `SEX` in `F.dLabel` ink2, 12, the `RangeSegments` switcher; 24; `OPTIONAL`, then one dial card of age, height and weight, rows 64 tall on hairlines, the name in `F.dNav` and the figure typed into a 72 × 40 `DC.field` well, `F.n24` flush right, then its unit in a 36 slot, so the three figures line up. The splash and the band picker (step 2, its skip the same link) stand on the same ground, with the same margin.

### 10.6 Buttons and controls

| Control | Spec |
|---|---|
| `BigButton` | minimum height 56 (`S.x12 + S.x2`), full width, pill, padding 20/12, label **uppercased** in `F.body` w800 tracking 1.4 (2 lines max), optional icon I.md + 8. **Primary is the ink pill**: `p.ink` ground with `p.bg` type (white with dark type on the dark page). A `color` other than `C.optimal` makes it a hue fill under `inkOn` (the strain-blue pill). `soft` is ink 9 % with ink type. `inverse` is the `p.inverse` pill. `danger` is red type on ink 9 %. `round` is a 56 circle. `busy` swaps the icon for a 16 spinner. | A `compact` button is one line, scaled down to fit and never broken mid-word; where three answers would not fit abreast, the primary one takes its own line and the others share the next. `ButtonTone.danger` is a solid `C.danger` pill with white ink.
| Home day buttons (ADD / START ACTIVITY) | height 52, ink 9 %, radius 12, icon I.md + 8 + `F.caps` tracking .6, `FittedBox` |
| Alarm button | `card2`, radius 8, 16 vertical padding, pencil I.md + 12 + `F.caps` |
| `PlusButton` | 44 square (`S.x10 + S.x1`), radius 8, ink fill with a `plus` at I.md in `bg` colour. Open state: ink 12 % with an `x` at I.lg in ink. |
| RESET chip | height 32, horizontal padding 12, ink 12 %, pill, `zoomOut` I.sm + 4 + `RESET` in `F.over` w800 |
| START pill (Start Activity) | `dialStrain`, pill, fills a 64 bar, `F.body` w800 tracking 1.6 white (50 % alpha while starting) |
| `TextAction` | the "CUSTOMIZE" voice: label uppercased in `F.caps` ink, optional trailing icon I.md 8 after it |
| `RoundIconButton` | a bare glyph at I.lg in a 48 target, no disc (like the reference close and back marks). `inverse` keeps a `p.inverse` disc and `glass` a frosted one, for a control over imagery. Label required |
| `AppSwitch` | Material switch: on is a volt track with a char thumb, off is `track` with an ink3 thumb, no outline |
| `AppField` | label `F.cap` ink2 above, a gap of 8, then a field filled `card2` with radius 8 and padding 16/12, no border. Focused: a 2 px ink ring (never volt). Error: a 2 px `C.danger` ring and the message in ink. `bare` drops the box. |
| `pickDate` (`date_picker.dart`) | a sheet laid out as the recovery calendar: grab handle, the title in `F.t2`, `BoldChevron`s (16, ink; dead at 22 %) either side of `NOVEMBER 2026` in `F.num(F.head)` w800 tracking 1.2, the weekdays in `F.caps` w800 ink3, the days in `F.n17` w700 (ink2; today and the chosen day ink; out of range ink 22 % and not tappable), the chosen one on an ink 12 % square of radius 12. Replaces Material's date picker everywhere. |
| `SubTabs` | Trend View's range segments, scrolling: a track of char 50 % over `bg`, radius 14, padding 4, 44 + 8 tall (scaled with text); items padding 16, no gap. The chosen one is lifted out as a `card` fill, radius 12, label uppercased in `F.caps` ink; the rest ink3; a disabled one ink3 at 45 %. A scroll hint replaces the chevron. |
| `Pill` | a chip: padding 8/4, radius 6, `p.wash(hue)` with `p.on(hue)` text, `F.cap` w700 |
| Selection chips (weekdays) | radius 12, uppercased `F.caps`. Selected: `p.ink` ground with `p.bg` type. Unselected: ink 9 % with ink2 type. No borders. **Sex is not a chip row**: it is the `RangeSegments` switcher (MALE / FEMALE / OTHER), in Edit profile and in onboarding alike |

### 10.7 Overlays

- **`AppSheet`:** `card`, top radius 18, padding 20/12/20/(20 + safe area), a grab handle 40 × 4 in `p.line`, title `F.t2`, content scrolls, actions stacked with 12 between. `AppSheet.open(…, bare: true)` lets a sheet paint its own ground.
- **`AppDialog`:** `card`, radius 14, inset 16/24, padding 24, title `F.t2`, body `F.body` ink2. Buttons are full-width `BigButton`s stacked with 8 between: primary, then destructive, then secondary.
- **`pickTime` / `TimePickerSheet`** (`time_picker.dart`): every time of day in the app is chosen on this one sheet, never on Material's clock face. An `AppSheet` with the grab bar, the title in `F.t2` ("Alarm time", "Start time"), then **two columns that scroll up and down**: hours and minutes in `F.n34`, five rows high (48 each), each looping (23 → 00, 59 → 00) and snapping onto a value, a `card2` band (`R.lg`) behind the centre row, rows fading to the sheet's colour above and below, a colon between, and a `selectionClick` as each value passes under the band. Under a 12-hour clock the hours read "7 AM … 12 PM" in the same one column, so there are always exactly two. One full-width `BigButton` "Set time". Dates still use the platform date picker.
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
1a. **Sync bar** (`HomeSyncBar`, today only, once the band has ever sent data), 8 under the header: a black (`DC.syncBar`) bar, one compact line at least 40 tall, radius 10, padding 12 / 8. A `cloud` at `I.md` ink3, 8, then the state in `F.dLabel` white; on the right `SYNCED TO` and the time of the newest data on the same line (a clock for today, day and time before; it wraps under itself at large text), then 8 and the mark. Three states: **Catching up** while the band is sending (the time in amber, a 20 ring turning: a 2-wide `DC.syncTrack` track and a white 1.75 rad arc, round cap); **Caught up** within 30 min of the newest data (`kCaughtUpMinutes`; the time and a 16 check in `optimal`); otherwise **Data not up to date** (the time in ink2, a 16 `refreshCw` in ink3). A tap syncs. Reduced motion stops the ring. **It folds away once caught up** (`HomeSyncBanner`): opened on current data there is no bar; after a catch-up lands, *Caught up* shows for `kCaughtUpShown` (`Motion.linger`, 1.3 s) and then folds shut over `Motion.slow`; *Catching up* and *Data not up to date* stay.
2. A **database-rebuilt** `StatusCard` (only after a rebuild; it outranks everything else).
3. The **illness watch** `Observation`: only at amber or red, and only for a recent night. On ordinary days it does not appear.
4. 20 of air. The wordmark is not on the page: it lives above the top and comes down only on a pull (§11.1a).
5. Sync and phase status card (today, only while connecting, syncing or analysing).
6. **Either** a bare-day card (nothing measured; while a workout runs this becomes "A workout is still running") **or** the **dials**, the **daily cards** (today only, §11.4a) and the **monitors**. If no dial has anything to draw, a single "Recovery is not scored today" card replaces them.
7. Stale-insights card, then the Calibration timeline card (swipeable) while any milestone is still locked (§14.13).
8. Wearable cells (only for non-WHOOP devices), then detected activities.
    - **Detected activity card** (`ActivityProposalCard`): caps title with a bare `ink3` icon, the dates, then a `WindowPreview(zoomable: true, onChanged:)`: caps `HEART RATE` and `bpm` above, the chart with the detected window shaded and its two lines, and under the heart rate the wrist's **movement lane** (one column a minute on the same clock, `paintMovement`, ink 45 %; none where nothing was measured). **Two fingers zoom; one finger on the start or end line moves that line (snapped to the minute, kept inside what the chart can show, start before end), one finger anywhere else pans.** There is no range bar and no drag handles to zoom, here or anywhere (the day breakdown's heart rate zooms by pinch and pans by one finger too). The dates and the length above follow the lines as they move, and CONFIRM saves the window as it is shown. `CONFIRM` is a full-width ink `BigButton` on its own line; under it, 8 apart and of one width, the edit (compact, soft) and the discard (compact, `ButtonTone.danger`, a solid red pill). Three across left no room for the words and broke them ("CONFIR / M").
9. **My Day:** a section head with the plus button, the ACTIVITIES card, then TONIGHT'S SLEEP (today only).
10. **My Dashboard:** a section head with CUSTOMIZE, then the chosen tiles in the user's order.

**"Quiet day" rule.** It is past midnight, nothing has been scored for today, earlier nights exist, and the band has sent data in the last 6 hours. The dials then show empty with the line "No sleep yet today." instead of a card asking the user to sync.

### 11.2 The three dials (Sleep · Recovery · Strain)

- **Layout:** a row of three `Expanded` columns with 12 between them. Each dial is capped at 144 wide and drawn at 85 % of its column, square.
- **Ring:** `Ring(solid: true, flatStart: true)`.
  - Stroke is **5.8 % of the dial's width**: a thin ring.
  - Track is `p.track`.
  - The arc starts **square at 12 o'clock** and ends in a **round cap** (a dot of half the stroke). A full turn has no cap.
- **Strain target** (strain dial only): the target band is drawn on the track in ink 24 % over track. A white tick crosses the track at the target's optimal, as long as the ring is thick and 26 % of the stroke wide: the same band and tick as the strain screen's ring (§14.1). Both draw under the arc.
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

- Each big dial's resting centre and diameter are measured **after** a frame (layout and scroll offset agree then): after every build and after every scroll frame. A dial scrolled out of the list keeps its last measurement, so the rings never snap into the bar or start from where the dials sat before a card above them loaded.
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
- **Beside the square:** the word in `F.caps` w800 in the hue (`WITHIN RANGE` / `OUT OF RANGE` / `NO DATA` / `CALIBRATING`, or `LOW` / `MEDIUM` / `HIGH` / `CALIBRATING` / `NO READING`), then the sub-line in `F.num(F.cap)` w600 ink2 (`4/4 Metrics`, `14:20`, `Needs a night`, `13 more nights`, `2 more days`). While calibrating, the square holds an hourglass (health) or `--` (stress) in ink3, and a `SegmentBar` sits under the row, `S.x3` below it.

### 11.4a Daily cards (between the dials and the monitors, today only)

A stack of small cards, each one thing worth a sentence today, read off stored series by `dailyCardsFor` (`home/home_daily_cards.dart`; every threshold is in `DailyCardRules`). A card appears only when every number it states is stored; "your usual" is the mean of the 30 days before today and needs 7 of them. Overnight cards wait for last night to be scored; recovery cards skip a provisional score. At most five, most important first (`DailyCardKind` order). Hidden when there are none, and on past days.

- **Card** (`DailyCardFace`): the graded `Surface` ground, radius 14, padding 20 (56 on the right, for the badge). Title `F.dBody` ink. **Most cards are only words**: the sentence in `PH.cardWords` ink2. A picture is kept for what is rare, and its sentence drops to `PH.cardBody`: a **coin** for a record (`hrvBest`, `rhrLowest`, 74 × 85, gold rim, the metric's mark struck in), **slabs** for a turn in the week's recovery (`firstRed`, `backToGreen`, 83 × 92, seven slabs coming toward you, today's in its recovery colour, a day with no score left empty), and an **open box** with light coming out of it for a goal reached (`targetMet`, `stepGoal`, 76 × 74). A soft halo (`DC.cardHalo`, blur 20) on every side.
- **Badge**: 24 × 46, radius 6, ink 10 %, 8 in from the top and right: a check at `I.sm` over the count of cards left in `F.num(F.body)` ink2. Tapping it throws the top card off. The count rolls (fade and rise, `Motion.base`).
- **Stack**: the card beneath peeks 10 under the top one, 12 narrower on each side, at 55 %. All cards in the deck are as tall as the tallest; that height eases (`Motion.slow`) when it changes, and to nothing with the gap above it when the last card goes.
- **Throw**: the top card follows the finger sideways, tilting up to 0.1 rad about its foot. Let go past 35 % of the width, or flicked faster than 700 px/s, and it flies off at the finger's speed (`easeOutCubic`, `Motion.fast`…`Motion.slow`), fading after 45 % of the width, with a `selectionClick`. Anything less springs back (stiffness 420, damping 0.78); a finger can catch it mid-spring. The card beneath rises to full size and fades its words in over the first 60 % of the throw. Reduced motion: the card still follows the finger, and everything after lands at once.
- **Once a day**: a card put away (thrown or checked off) is stored against the local day in `Prefs.dailyCardsDismissed` and does not come back that day; the next day overwrites the key.
- **During the day**: three cards come from today as it happens, read off today's live strain and steps rather than a stored night. **Strain target reached** (`targetReached`, the open box) once today's strain is inside the target this morning's recovery set; **Past today's strain target** (`strainOver`, words only, ranked with the warnings) once it is over the top of it; **Step goal reached** (`stepGoalToday`, the open box) once today's steps pass the goal. Each needs this morning's recovery (or the goal) and today's figure; either missing, no card.

### 11.5 My Day

- **Section head:** "My Day" in `F.t1`. The trailing `PlusButton` opens the plus menu (§11.6).
- **Daily Outlook card** (today only), directly under the head: one full-width `Surface`, 56 tall, padding 16 across: a sunrise glyph (sunset from 17:00) at I.lg in **ink3, no colour**, 12, "Daily Outlook" in `F.head` w500 ink, and a chevron at I.lg ink3. No coach orb beside it. It opens the coach on today's outlook (§14.10).
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
    - Right, with an alarm: the alarm's time, an 8 px status dot and its word: `ALARM ON` (green), `SENDING TO BAND` or `NOT CONFIRMED` (yellow).
    - Right, with an alarm on My Schedule the band has not armed yet: that alarm's time (alarm-clock icon) over `NOT ON THE BAND YET`.
    - Right, with no alarm: the **recommended wake** time (sunrise icon) over `RECOMMENDED WAKE`.
    - **The first alarm is the wake time**: the next one to ring from My Schedule, else the one armed on the band. Only with no alarm does the Sleep Planner's typed wake time count, and then the usual wake. The bedtime is counted back from it, here and in the planner.
  - Then 16, and the SET / EDIT ALARM button.

### 11.1a Pull to refresh (`pull_refresh.dart`)

Home is a `CustomScrollView` with `kPullPhysics` (always scrollable, bouncing) and `LocusPullRefresh` first. Pulling the page down opens a gap at the top and the word LOCUS slides into it in step with the page, gray (ink3 at 45 %) and unfilled, growing from 1.05× to 1.3× and fading up as the pull nears the line. A tick (`selectionClick`) the moment the pull is enough (88). **The white starts filling the moment the pull is enough**, under the finger (`Motion.write`, 1.5 s, `easeInOutCubic`), not after letting go; pulled back under the line it empties. Let go and the page holds at 64 while the refresh runs. The page never lets go before the whole word is white plus a beat (`Motion.write + Motion.slow`) to see it, and never holds longer than 8 s for the work itself, so **the word always goes back up**: Home's pull waits only for its quick re-read, the band sync carries on in the background and the page re-reads when it lands. Then the page rises and takes the word up with it, gray again for the next time. Reduced motion fills it at once.

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
| Strain | day strain (0–21, minute day line, cumulative: drawn as the strain the rest of the day kept — the lowest figure from each minute on, so it only climbs or holds, ends on the headline, holds across gaps from midnight; a 2.5 trace), steps (hourly bars), HR zones 1–3, 4–5 and all (stacked, weekly), strength time (weekly, zero-filled), total volume load (weekly, kg), average HR (line, minute day), calories (hourly), VO₂ max (line) |
| Recovery | recovery (%, traffic light), HRV (line, hourly day with the night shaded), resting HR (line, lower is better), respiratory rate (line) |
| Sleep | sleep performance, time in bed (floating), hours vs. needed in hours (dual) and as %, consistency (floating with "usual"), restorative % and hours (stacked), efficiency, sleep debt (signed, never below 0) |

---

**The readout row.** The figure and its caption sit left, `RangeSegments` right. The change against the window before (`_DeltaChip`) rides the **pager's** row, left of `WindowPager`, on ONE line always: the chip says only the percentage (`▼ 6%`, `F.num(F.over)` in an `R.sm` chip) — the pager beside it already names the window, so "vs. prior week" is spoken (its `Semantics` label) but not printed. The pager takes the rest of the row and ellipsizes its date before it ever wraps.

**Logging a weight.** Saving turns the sheet into the result: the new figure rolls in from the last logged one like an odometer (`RollingNumber`, `Motion.roll`, eased out), a selection tick per turn of the last digit no closer than `Motion.tickGap`, one soft tap as it settles (the unit on the figure's baseline), the change since last time under it (neutral triangle and ink: a gain is not good or bad), and the sheet closes after `Motion.linger`.

**My Dashboard, expanded.** Customize sets each metric to a slim row or its week in full (`ExpandedTrendCard`, `Prefs.dashboardExpanded`). The card is Trend View's W range on Home with no range switch: caps title and a chevron (the door into Trend View), the readout, the chip with the week's dates, then the chart the W range draws, by the same builder: nights floating on a clock for time in bed and consistency (`ScrubRanges`), need against achieved for hours vs. needed (`ScrubPair`), the layers stacked in their own colours for zones and restorative sleep, otherwise `ScrubLine` / `ScrubColumns` (value labels over each day, the average dashed). Home loads the layers and bed/wake spans for its tiles alongside the daily figures. Strain & Recovery is always a chart.

**Compare metrics** (`compare_metrics.dart`, `kCompareTile`) is a tile and a Trend View entry of its own (the picker's top row), never a strip under another metric. It has the Strain & Recovery card's anatomy: `p.card`, `R.rXl`, padding 20; the title `COMPARE METRICS` in `F.caps` w700 on a 44 row with the chevron on the right when it opens Trend View; 8; **the two readouts are the pickers**: each a full half, the first left, the second right-aligned, a dot in its series colour, the name (`compareChipName`, `F.over` w800 ink2) and a 16 `chevronDown` (a tap opens the metric list; picking the other slot's metric swaps the two, `Prefs.comparePair`), the week's figure (`F.num(F.n24)`, average or a weekly metric's total) or the touched day's, and what it is. 8, then **one chart, two axes**: the first metric on the left axis, the second on the right, each axis's labels `F.num(F.over)` w700 in its metric's colour, gridlines on the left one's ticks; untouched, the newest day carries the column band (ink 10 %), as on Strain & Recovery. Each metric keeps its Trend View shape: a line (2.2 px, round joins, a break on a missing day, each day the card's ring marker: a 6.5 `p.bg` disc and a 5-radius 2.4-wide ring), columns, zones stacked in their colours, or nights as bed-to-wake ranges on a clock running down. Two column metrics stand side by side in each day's slot; a line runs over any columns. Day labels `F.num(F.over)` ink3 w600, the focused one ink w800, 12 under the plot. 8, then the `WindowPager`, centred; it is always one week. **No sentence under the chart.** One finger reads a day out for both.

## 14. Detail screens built on this language

### 14.1 Strain detail (`activity/day_strain.dart`)

- **No day pager:** the NavBar names the day (`SUN, MAY 18`); the ring sits straight under it.
- **Ring** (`Ring` from `charts.dart`, the home dial's painter):
  - Side `min(84 % of the width, 346)`, stroke 6.1 % of the side, track `p.track`, a `dialStrain` arc that starts square at the top and ends in a round cap.
  - **The strain target** that morning's recovery set (`whoopStrainTarget`): its range is a lighter stretch of the track (ink 24 % over `track`) from low to high, and its optimal a white tick across the ring, as long as the ring is thick and 26 % of the stroke wide. Both draw under the day's arc. No recovery that morning, no band and no tick.
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
- **Strain through the day** (`ScrubLine`, 0–21 axis, `dialStrain`) with its own readout. The trace is **2.5** wide, the HRV chart's weight. Each of the day's activities is a tinted span (its catalogue colour at 16 %) with its icon in a small disc of that colour above it, at the top of the plot.
- **Today's projection** (`compute/strain_projection.dart`): from now to midnight, a dotted `dialStrain` line (round dots 2.5 across, 5 apart along the line). It is where the last 14 days went from this minute on: each earlier day's load gained after now (strain is a log of load, so the sum is taken in load), averaged and added to today's load so far. It needs three earlier days with a whole curve; otherwise there is no line. Scrubbing past now reads the projection (`18:00 · projected`), and the footnote says how many days it came from.
- **Strain never falls through a day.** The headline and the curve are the analytics' net curve held at its running peak (`compute/strain_peak.dart`, `kAlgoVersion` 115): effort once earned stays earned. Peak HR and Worn under the curve sit inset `S.x5`, under the plot rather than the axis.
- **Time in zones** and **What this is made of** (`card2` panel, `F.cap` ink3). The zones card's link, "How these are set", opens **Heart rate settings** (the same screen Settings opens: personalized zones, resting and max HR). There is no second zones screen.

### 14.1-r Training readiness (`training_readiness_card.dart`, `compute/training_readiness.dart`, today's Strain only)

Under the band sentence, a `Surface` (padding 20/9/20/17; the score sits right under the title row): `TRAINING READINESS` in `F.over` w700 tracking 1.2 with an ⓘ at `I.md` ink2; the score in `F.n34` w700 with `of 100` in `F.cap` ink2 on its baseline; the level (`PRIME` 95+, `HIGH` 75+, `MODERATE` 50+, `LOW` 25+, `POOR`) in the label style ink2; one sentence in `F.body` w400 ink2 naming the weakest factor under 75, if any; then seven rows 44 tall on ink 8 % hairlines: a factor icon at `I.md` ink3, the label, and its value in `F.num(F.body)` w700. The sentence sits 8 under the level and 8 over the rows. The rows: Recovery time (`timer`, hours still owed, 0.2 · strain² per session over the last 72 h), Last night's sleep (`moon`), Recovery (`heartPulse`), HRV status (`activity`, the 7-night mean against the 30 nights before), Load ratio (`gauge`, 7-day over 42-day load, shown as the ratio itself, `1.24`; days before the band first measured load are unknown, not rest, so they do not count), Sleep, last 3 nights (`bedDouble`), Stress, last 3 days (`brain`). Each factor scores 0–100; the score is 0.7 of their mean plus 0.3 of the lowest, so one poor factor holds it back. Fewer than four factors with stored inputs and there is no score.

### 14.1a The dial screens' parts (`dial_parts.dart`, tokens in `theme.dart` `DC`)

Sleep, Recovery, Behavior Insights and Behavior Details are one family, measured from the user's reference recordings at 1.5 px per dp. The sizes below are the reference's: check against it before changing one, not against what looks comfortable.

- **`DialScaffold`:** a slate-to-black page gradient, a painted back chevron, the day in caps (`FRI, MAY 16`). There is no day pager on these screens.
- **`DialRing`:** side 75 % of the width, stroke 6 % of the side, on `DC.tierOff` with a soft start (`Ring.softStart`). Inside: `LOCUS`, the figure in `F.nDial` with its `%` in `F.nDialPct`, then the label in `F.dHero`.
- **`CaretPanel`:** the graded panel with a caret pointing up at the ring.
- **`TierBar`:** three segments for the Poor, Sufficient and Optimal bands, the band it falls in lit (orange, grey, green).
- **`WeekCard`:** a week of a metric, the newest day highlighted, with a chevron into Trend View where it has one. `WeekChart` is columns, `WeekLine` the line form with its own axis, `WeekColumn.floatLabel` a value over a column. Each card scrubs on its own.
- **`ValueDelta` and `deltaMark`:** the value with a triangle against the prior 30 days. Green up and orange down follow whether higher is better for that metric. With no prior figure there is no triangle.
- **`DialInfo`:** the circled `i` on a card's title, opening a sheet that says what the card means in our own words.
- **`HatchBar`:** a stage's bar over a hatched track, its typical range a darker hatched box.
- **Absence:** every value without a measurement is `--`. Comparison lines say "vs. prior 30 days" (Sleep) or "vs. last 30 days" (Recovery), counting the prior days only, never the day itself.

### 14.1b Sleep detail (`sleep_detail.dart`)

Top to bottom: the ring (`SLEEP PERFORMANCE`, `dialSleep`), the contributors panel, Last Night's Sleep, the need, then the weekly cards.

- **Contributors:** Hours vs. Needed, Sleep Consistency, Sleep Efficiency and High Sleep Stress, each with a `StatMark`, a `TierBar` and its figure, over the Poor / Sufficient / Optimal legend.
- **Last Night's Sleep** (`F.dHead`, with EDIT and a pencil at the right; EDIT opens §14.1c):
  - **Hours of Sleep** card: the figure over the prior 30 days' figure, and the night's heart rate edge to edge on a fixed 30–170 axis, with dashed lines at onset and wake. The chart scrubs. Past the raw store's retention it draws the day bundle's own curve, and it says nothing if there is neither.
  - **Stage rows:** TYPICAL RANGE and DURATION, then Awake, Light, SWS (Deep) and REM with a share, minutes and a `HatchBar`. Tapping a stage's circle picks it: the chart colours that stage's runs and the other rows dim. Scrubbing names the stage under the finger.
  - **Restorative Sleep** (deep + REM, against its prior 30 days) and **Sleep Latency**. Latency is shown only on a window the user set or confirmed (`sleep_source` `manual` or `confirmed`). An automatic window's onset is the stager's own guess, so nothing can be measured back from it and the row reads `--`.
  - Other devices' staging keeps its picker and its "Staged by X, which does not report …" line.
- **Hours vs. Needed:** the share, then hours of sleep over the need, split into Healthy Minimum, Recent Strain and Sleep Debt (`NeedParts`, rebuilt from the stored series with the same arithmetic as the need). With any input missing the split is absent; it is never estimated.
- **Sleep Consistency** (bed and wake across the week), **Sleep Efficiency** and **Sleep Stress** (share of sleeping minutes by level, `SleepStress.low`, `medium`, `high`, and the night's `curve`).
- **Weekly cards:** sleep performance, hours vs. needed (hours and %), restorative sleep, consistency, time in bed, efficiency, sleep debt and sleep stress.
- **No night:** "No sleep recorded / Set one manually" opens the window editor (§14.4c). A provisional night is still marked as one.

### 14.1c Edit Time in Bed (`edit_time_in_bed.dart`)

A bare sheet over a black scrim: the night's bed and wake, each a date chip and a time chip, "Where did you wear your band?" (stored per night under `wearLocationKey`, read only by this sheet), SAVE, and DELETE SLEEP. Saving goes through the same `setSleepOverride` path as the window editor and re-derives the night. Deleting marks the night `rejected`.

### 14.1d Recovery detail (`readiness_detail.dart`)

- **Ring:** `RECOVERY` in the tier's colour, with no target tick.
- **Contributors panel:** Heart Rate Variability, Resting Heart Rate, Respiratory Rate and Sleep Performance, each with a `StatMark`, the value in `F.nRow` over its 30-day figure in `F.nTiny`, and a triangle.
- **Comparison strip:** both triangles, then `Fri, May 16 vs. last 30 days`.
- **Behavior Insights door:** a `bulb` mark, the title and one line, opening §14.1e.
- **Weekly cards:** recovery, HRV, resting heart rate, respiratory rate and sleep performance.
- **Other states:** the calibrating, provisional and absent states are kept as they were. A held-over night says so. A missing score is a `--` with its reason, never a substituted one.

### 14.1e Behavior Insights and Behavior Details (`behavior_insights.dart`, `compute/behavior_impact.dart`)

- **Impact is the difference in mean recovery** between days that had the behavior and days that did not, drawn as a bar either side of zero. **It is association, not cause**, and the copy says "lines up with", never "causes" or "improves".
- **`kBehaviorMinDays` (5) on each side**, or the row is locked and shows how far along it is. Nothing is estimated to fill a row.
- **The app's own behaviors:** 75 %+ sleep performance, consistent bed and wake time (within `kConsistentWithinMin` of the person's median), early workout (before `kEarlyWorkoutHour`), hard strain (`kHardStrain`+), and high-stress days (over `kHighStressDayPct` % high, from `StressSource.highPctByDay`, off the UI isolate, needing `kStressDayMinScored` scored minutes).
- **Journal tags** come after those, each tag's day moved by its own lag (`journalTagLagDays`, the analytics' table).
- **Behavior Details** explains the page: an abstract glow where the reference has a photo (we copy no photograph), a text in our own words, and the Explore card with its painted notebook. "Outdoor Time" is omitted because nothing measures it.

### 14.1f The journal (`journal_compose.dart`, `select_behaviors_sheet.dart`, tokens in `theme.dart` `JC`)

Measured off the reference screenshots at 2.34 px per dp; check against them before changing a size.

- **Page:** always char. A full-screen gradient from warm tan (`JC.pageColors`) through grey into the app's near-black. Top bar 60 tall: a hairline ✕ (closes without saving), `JOURNAL` in `JC.title` (13 bold, tracked), the pencil (opens SELECT BEHAVIORS).
- **Only the top bar stays put.** The day pager, the pill strip and everything under them scroll up with the page.
- **Days:** `‹ TODAY ›` (`YESTERDAY`, then `SAT, NOV 1`), the dead-end chevron dim. Under it a strip of day pills, 49.4 × 79, 14 apart, today at the right gutter, scrolling back a month: weekday, date, and an 18 dot that turns white once the day holds anything. The open day wears a 1.5 white rim. Moving to another day writes the one being left.
- **Heading:** `What's happening today, November 7?` (`What happened yesterday, …`, `What happened on Wednesday, …`) in `JC.heading`.
- **BEHAVIORS:** the label and a hairline to the edge, then one card per question, 63 tall, radius 13, white at 10 %, 10 apart. A yes/no has ✕ and ✓, 36 square, radius 7, 9 apart; the chosen answer is white with a dark glyph, and tapping it again takes it back to unanswered. A rating has one square per step under the question; an amount has − and + with what is logged (and the last-one time) under the question; weight keeps its typed entry and its trend. NOTES is the same card holding the day's note.
- **DONE:** a white pill 338 × 52, 18 off the bottom of the screen, the list ending 25 above it.
- **Storage:** every question is a `journal_metric` field. A yes/no is the habit shape (ceiling one: 1 yes, 0 no, nothing unanswered); built-in numbers keep their keys. A catalogue question that a preset tag used to answer (`JournalBehavior.tag`) keeps the tag in step. The chosen questions are `Prefs` `journal.behaviors`; before anything is chosen the journal asks whatever its owner has logged before, or a starter set. A question answered on a day is shown that day whether chosen or not.
- **SELECT BEHAVIORS:** a sheet 16 below the status bar, radius 18, its own slate gradient. Grab 73 × 5, the title, a dark search field 51 tall (radius 13) that searches every category, then tabs (All, Custom Behaviors, Drugs & Medication, Hormonal Health, Lifestyle, Mental Wellbeing, Nutrition, Recovery, Sleep, Training) with a 2 underline under the active one, which slides to the middle. CURRENTLY SELECTED and NOT SELECTED, each sorted by name: name in `JC.row`, the question in `JC.sub` grey, a 24.2 checkbox (blue `JC.box` with a dark tick, or a 2 white outline). "Write your own" heads All and Custom (and a search with no match) and opens a compact sheet: the question, how it is answered (yes or no by default, a 1–5 rating, an amount or minutes with unit, step and ceiling), ADD QUESTION. SAVE BEHAVIORS is the DONE pill at 356 wide.
- **Catalogue:** `kJournalBehaviors` in `journal_fields.dart`, over a hundred generic questions. No product or brand is a behavior.
- **Behavior Insights:** yes/no answers are compared yes against no (`answerBehaviors`); unanswered days count for neither side.

### 14.2 Recorded activity (`workout_detail.dart`)

- **Header:** §10.4.
- **Strain row** (64 tall): the strain in `F.n34` in `dialStrain`, a `_VsPill` (ink 10 %, radius 6, a 12 triangle in ink2 and the sport's 30-day average in `F.num(F.body)` w700 ink2), then `ACTIVITY STRAIN` in `F.over` w800 tracking 1.4 ink3.
  - **While a finger is on the chart, this row becomes the reading:** `143` + `bpm` in `dialStrain` and the clock time under it. It keeps the same size and place.
- **HR chart** (216 tall):
  - **Plot:** ground ink 4 % over `bg`. Grid in ink 10 %: a line every 25 bpm and the width in quarters. Tick labels `F.num(F.cap)` ink3 at the left edge, over the grid.
  - **Trace:** a `dialStrain` line at 2 px over a fill from 42 % to 2 %.
  - **Session edges:** start and end are dashed lines (ink 80 %, 1.5 px, 4/4) with a dot of radius 4 at the foot and the clock time under each. Whatever is drawn beyond them is at 28 % (`paintWindowed`), so the axis reads through it.
  - **Finger:** a dotted ink line down the chart and a dot on the reading (an ink disc of radius 10 with a `dialStrain` centre of radius 8).
  - **Zoom:** pinch to zoom and pan, down to 2 minutes; a double tap zooms in 2× around the tap, on every chart that pinches. RESET chip.
  - **Lit zone:** when a zone card is selected, the trace turns ink3 at 1.4 px and each stretch in that zone fills in the zone's colour (85 % → 8 %) with a 2 px edge. The stretches are cut where the **drawn line** crosses the zone's edges (`zoneSpans`, interpolated between points), and the fill is the area under the line itself clipped to them, so the colour follows the line exactly. A run the band's own seconds spent in the zone but the averaged line never reaches (a 20 s peak inside a 24 s bucket) is still lit, as a column under the line over that run (`litSpans`): the chart never hides time the zone card counts. Consecutive stretches are separated by a thin line in the ground colour.
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
- **Edge to edge:** the strip and the chart run under the side insets; only labels and the close button keep clear of a notch.
- **Header strip:** `min(128, 30 % of the height)` tall, char 60 % over `bg`, with 2 px char borders. Over it, each mark (the night, each activity) shows its icon (I.lg) and figure (`F.num(F.n24)`) centred on its stretch. Marks that would overlap merge into a `MarkCount`, and zooming spreads them apart again. Under each mark, a 4-tall bar the width of its stretch in `dialSleep` or `dialStrain`.
- **Plot:** from the left inset + 48 (the tick-label gutter) to the right inset − 20, a fixed 20–220 bpm scale, grid every 40 (ink 8 %), tick labels `F.num(F.head)` ink3 in the gutter.
  - Stretches are shaded: the night at ink 6 %, activities at `dialStrain` 10 %. The shading runs **down through the MOVE lane**, so an activity's movement sits inside its colour.
  - **Trace colour by context:** the night in `dialSleep`, activities in `dialStrain`, the rest of the day in ink3 at 75 %. 1.6 px, broken across gaps of more than 5 minutes.
  - The **wake** is a dashed `recGreen` line and the **last reading** a dashed `dialStrain` line, with `STRAIN 12.4` written over the last reading — or just beside the activity mark it would land on, never over it.
  - **Clock labels** along the foot: the start, every 1, 2 or 4 hours depending on the span, and the end. Labels are never closer than 64; the ends win.
- **Gestures:** pinch zoom (minimum 30 minutes) and one finger pans a zoomed day. There is no magnifier; the chart has that room. Close × at the top left.

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
- **Alarm countdown** (`AlarmCountdown`): the rest alarm card says how long until it rings ("Rings in 7 h 32 min", `F.cap`, rounded up to the minute, ticking each minute), and the same line sits centred in `F.num(F.head)` on top of My Schedule, the alarm page ("No alarm set" without one).

### 14.4b Turning off a repeating alarm (`profile/alarm.dart`)

Each alarm card on My Schedule carries its own switch. Switching off a **repeating** alarm asks first, in a sheet titled TURN OFF RECURRING ALARM?: three 48-tall centred rows with hairlines between them — **Skip tomorrow** (or Skip Wednesday, for the next one that would ring), **Turn off recurring alarm**, **Cancel** (ink2). A skip keeps the alarm on and drops that one morning: the card says `Skipping Thu 7 Nov` in `F.cap` ink2 with an **Undo** text action. A one-shot alarm just switches off.
- **Shake to stop** shows, under its switch, what the last alarm's watch saw: `Last alarm: 7:00 · 140 frames · rest 1.00 g · peak 2.1× · stopped` (`F.cap` ink3), so a shake that did nothing says why.

### 14.4a Edit alarm (`profile/alarm.dart`)

A standard sheet (`AppSheet.open`, scrolling, the grab bar, `F.t2` title "Edit alarm"), padded to the gutter.
- **The time:** a `card2` panel (radius `R.xl`, 20 above and below) with the time in `F.n80`, and under it, in `F.cap` ink3, how long until it rings ("Rings in 7 h 32 min", read from the time and days as edited). Tapping it opens the time picker.
- **REPEAT** (`F.over` ink3): `RangeSegments` of three, Once · Weekdays · Every day, stretched to the width (none lit when the days are custom), and under it seven equal day circles (S M T W T F S, 40 across, `card2`, lit in `dialStrain` when on). The presets and the circles are one state.
- **Label:** `OsTextField`.
- **Rows** in a `Surface` of `SetRow`s: Alarm on (the switch) and Alarm mode (its blurb, its name, a chevron into the mode sheet). For an exact alarm only, a second `Surface`: waves icon, "Smart wake" and what it does, over `RangeSegments` Off · 15 · 30 · 45 min.
- **Save** is the sheet's one primary action (the ink `BigButton`, check icon); **Delete alarm** is a `ButtonTone.danger` pill under it. No trash can beside the title, no native dropdown.

### 14.4c Set sleep (`window_editor.dart`)

- **Set sleep** (the window editor): the heart-rate chart with the two window lines, `+` / `−` at its top right to zoom (and two fingers); **no interval buttons** (30M, 2H, 6H, 1D, 2D are gone). Start and End tiles open the time picker (§10.7).
- **The activity's heart-rate window** (`WindowPreview`): one card, ink 8 % over `card`, `R.lg`, no border, padding 16/4/4/16. Its head, 44 tall, is the chart system's: `HEART RATE` in `F.caps` with `bpm` in `F.num(F.cap)` ink3 beside it; on the right one zoom chip (the RESET chip's ground: ink 12 %, pill, 32 tall) holding minus and plus as bare `I.sm` ink glyphs 40 wide with a hairline between, and, where there is a full editor, a bare maximise at `I.sm` ink2. The chart is drawn like the workout HR chart (§14.2): gridlines on a bpm scale in 25 bpm steps (`windowHrScale`), labelled right-aligned in a 40 gutter (`WindowTicks`); the trace a `dialStrain` line at 2 px over a fill from 42 % to 2 %, both dimmed to 28 % outside the window; the window a soft ink 6 % column (radius 4) from 8 above the plot to its foot. Each handle is a session edge, dashed ink 80 % 1.5 px (4/4), with a slim grip (4 × 16, knocked out of the ground) at mid-height and a dot of radius 4 in a ground of radius 6 at its foot. Under the chart: the range and its length (`15:22 - 16:15 · 53m`) in `F.num(F.cap)` w700 ink and, right-aligned, "Drag a line or the middle. Pinch to zoom." in `F.cap` ink3.
- **An existing night is edited from Edit Time in Bed** (§14.1c). The old sleep-window sheet is gone with the Total sleep hero. There is no "Back to automatic".
- **Ending a started sleep or nap** is instant: the window is saved and the screen closes; the night re-derives in the background and Home re-reads when it lands.

### 14.4d The activity chooser (`add_activity.dart`)

One list names an activity everywhere the app asks: Add activity, Start activity, correcting a session's type, naming a window in Log workout. `ActivityChooser` / `chooseActivity(context, sleep: …)`: a search field, tabs ALL · STRAIN · RECOVERY · SLEEP, then rows (`ink` 9 % ground, `R.xl`, icon + caps name). **On ALL, Sleep and Nap are pinned above the A–Z list** (and filter with the search); the SLEEP tab holds them alone. Where only an activity makes sense, `sleep: false` removes the SLEEP tab and the pinned rows. The old full-screen picker and its collapsed groups are gone.

### 14.4e Updates (`lib/updater`, `ui2/components/update_dialog.dart`)

- **Settings → Updates:** *App updates* (its line says what you have, what is ready or that it is checking) and *Check automatically*: on launch **and every time the app comes back to the foreground** (Android mostly resumes rather than relaunches), at most every 15 minutes. "Later" declines that one build: the automatic check stays quiet about it, a manual check still shows it.
- **How a build knows it is old.** Every CI build carries its commit count as its build number (Android's versionCode, which only grows along main) and is named `locus-0.11.4.<count>-<commit>.apk`, released as "Locus 0.11.4 build <count>". Tagged releases (`build.yml`) use the same counter, so a release never installs as a downgrade over a CI build. Between two numbered builds the build number decides. A build without one falls back to the commit and publish time: a release is an update when its commit is not the installed one **and** it was published after the installed build was made. The check reads GitHub's release *list* (the rolling `latest` build is a pre-release, which `/releases/latest` never returns).
- **The sheet** is a dial sheet (`DC.sheetTop` → `DC.sheetFoot`, `R.xxl` top corners, the grab bar): the Locus mark at 48, `UPDATE AVAILABLE` in `F.dLabel` ink2, the new build (`v0.11.4 · build 87`) in `F.dHead`; a dial card of rows 48 tall on hairlines, the name in `F.dLabel` ink2 and the value flush right in `F.dText` w600 (*Installed*, *New* in optimal, *Published*, *Download*); a *WHAT'S NEW* card with the commit message (no co-author lines, no boilerplate); then **Update now**: the APK downloads inside the app (checked against the SHA-256 GitHub publishes), a 6-tall strain-blue bar on `DC.track` with `DOWNLOADING n%`, then Android's installer. A refusal is said plainly in `strainDown` with **Try again** and **Open in browser**; **Later** is the soft pill. The downloaded file is deleted the next time the app starts.
- The workflows publish the plain `.apk` as a release asset; they no longer upload it as a zipped run artifact.

### 14.4b Sleep Planner (`screens/sleep_planner.dart`)

Top to bottom on the slate-to-bg gradient: the nav row (back, `SLEEP PLANNER`, and the schedule button: a 36 ring with a calendar and a moon in it, centred on the title's line, its ON/OFF tag hanging under it without taking any of the row's height); 8; the Locus mark in a 36 ring; 16; the headline in `F.head` w500, always three lines high so nothing under it moves; `TOMORROW I WANT TO` and the goal as a **full pill** (ink 1 px border, `F.body` caps); then, with twice the room above and below it, the night: the suggested bedtime and the wake time in `F.n34` over two-line captions, dashed drops to the ends of a strip edged top and bottom with hairlines and hatched between two ink end caps; **TIME IN BED** over a pill (not a rectangle) with the length in `F.n24`, no icon: **tapping it opens YOUR SLEEP RECOMMENDATION**, a dialog on `card` (radius `R.xl`, padding 24, a 44 close ×): the title in `F.caps`, one paragraph on how Locus sets the time in bed in `F.body` ink2, then a panel tinted `optimal` 10 % over the card (`R.sm`): `SLEEP NEED`, a dashed ink3 rule, its parts indented 8 in ink3/ink2 (baseline, recent strain, sleep debt, recent naps), another rule, `SLEEP GOAL` and `AVERAGE AWAKE TIME`, a 2 ink rule, and `RECOMMENDED TIME IN BED` with the figure in `F.n34` w700. Values flush right. **The strip slides under a finger** (`SideDrag`): it follows at first and stiffens to 64 px (a rubber band), and on release springs back over `Motion.slow` with `Ease.emphasized`, the time in bed centred again; the band runs past both screen edges, so its end never shows. Under it, **OPTIMAL** and the optimal night, `bed – wake` (the bedtime that covers the whole need before your usual wake time) with its dashed bracket on the strip, or, with fewer than three nights, why there is none. **The suggestion follows the goal.** *Sleep need* suggests the bedtime that covers tonight's need by the wake time. *Consistency* suggests **the bedtime you actually keep**: the median onset of the last seven recorded nights, three at least (`habit_bed_min` from the cross-day rollup): "Try getting to bed by 22:40, your usual time, to stay consistent. It covers 92% of your Sleep Need by 07:00." With too few nights to know the usual: "Sleep Planner needs a few nights to learn your usual bedtime." Home's tonight card uses the same `plannedBedMin`. **The wake time** is the first alarm that rings on the next wake day (tomorrow from midday, today before it). A skipped morning (`skipDay`) has none, and the band's armed alarm counts only when it is for that morning, since after a skip it already holds the next one. With no alarm that morning, a wake time typed here for it (it lasts that one morning; choosing an alarm with it clears it), else **your consistent wake time** (`habit_wake_min`, else the usual one the coach learned). `ALARM SET TO` reads `SKIPPED` on a skipped morning. The dock: a card with `R.xl` top corners, the strap, `ALARM` and the switch, and two boxes 20 apart, `R.sm` corners and a darker edge.

### 14.5a Band buzz patterns (`notify/notification_relay.dart`)

With band notifications on and permitted, two phone events have a buzz pattern of their own and need no app picked: an **incoming call** (the dialer's notification) is **three long buzzes**, once per call (a 45 s cooldown keeps the ongoing-call update from buzzing again); a **Google Tasks reminder** is **two short buzzes**. Everything else is the one short buzz it always was. Each pattern has its own On/Off row under *Patterns* in Band notifications, on by default. 4.0 plays its short pulse or a longer waveform effect; the 5.0/MG's only known waveform is repeated (once short, three times long). Nothing buzzes while the band is disconnected.

### 14.5b Band battery alerts (`notify/device_alerts.dart`)

*Low battery* and *Charging* as before, and **Fully charged**: one card when the band reports 100 % on the charger ("Your band is at 100%. You can take it off the charger."), latched per charge (it re-arms only after the charge has fallen under 90 %, and survives a restart), cleared when the band comes off the charger, and, like the others, never spent on a card the quiet hours dropped.

### 14.5 Stress Monitor gauge

- The arc opens at the bottom, starting at 146° and sweeping 248°. Radius 44 % and stroke 3.5 % of its box.
- It is drawn as a blue → green → warm → orange sweep that dims at both ends, with an ink needle.
- `0.0` and `3.0` are written under the two ends.
- `stressColor(score)` interpolates the four stops.
- **30-DAY TREND** (`StressTrendCard`), 32 under the day's chart: a `Surface` with the title in `F.caps` w700 and an ⓘ at `I.lg` ink2 in a 44 box; a `ScrubReadout` (`Average` or the touched day, one decimal); then a `ScrubColumns` of each day's mean stress (a day needs 6 h scored), 0–3 with ticks at 0, 1, 2, 3, **each level the month never reaches squeezed to 30 % of its height** (`StressAxis`, through the chart's `fraction`), so a calm month draws a shorter chart and the levels with data keep their full height, every column in its **level's** colour (low blue, medium green, high orange: `_levelColor(stressLevel(v))`, never a blend, which made a calm day and a medium one two shades of one teal), the dashed 30-day average across, and a date under every seventh column from the newest. While today is running it is left out of the average, and a line under the chart says so.

### 14.5a Health Monitor (`health_monitor.dart`, tokens in `theme.dart` `HM`)

Measured off a 1180 px reference (3 px to the dp) and checked against a 3× render of the screen. Always char.

- **Page.** A gradient `HM.page` (slate `#282F37` → `#0E1215`, stops 0 / .26 / .47 / 1). Bar 64 tall: a 41 dp chevron at the left, "HEALTH MONITOR" centred in `HM.title` (13 w700, tracking 2).
- **Hero** (168.7 tall). A 15 dp grid (`HM.grid`, white 4 %) from 7 to 142. The heart-rate line (`HM.line`, 2 dp) runs at 88.3, fading in from about 17 % of the width under the text, with a 13 % glow under it. It ends in an 8 dp white dot 32.7 from the right edge, on a dashed vertical (`HM.dash`, 3 on, 2 off, from 14.3 to 131). While live, the line is the live trace and slides.
- **Hero text** (left 24). "HEART RATE" in `HM.kicker`. Under it, the heart: traced off the reference (`_heartHalf`, mirrored), 22.28 × 19.1, `HM.heart` `#3F90E0`, 1.27 left of the text edge. It swells 8 % on each beat while live and motion is on. Then the number in `HM.value` (D-DIN 34), BPM in `HM.caps` (`HM.caption`), and under that the zone ("Zone N" from the zone table) or, without a live beat, "Last recorded HH:MM" / "No Device Paired" / "Device Disconnected" / "Waiting for a reading". Five 20 × 2 zone segments at 142; only the current zone's is lit, in its zone colour.
- **Tiles.** Two columns, 16 margins, 12 gutter, 12 between rows, radius 10, `HM.card` veil, padding 10 / 8 / 10 / 10. The header is a 20 dp line icon (`_Glyph`: 24-unit square, 1.4 strokes, round ends, `HM.icon`), 8 gap, then the label in caps (`HM.name`, 10 w700, tracking 1.5, line 1.5).
  - A one-line label sits 3 dp lower when its row has a wrapped one. A number sits 18 under a one-line label and 16 under a wrapped one, so a row's numbers are not level, as on the reference. The row is as tall as its taller tile.
  - Value in `HM.value`, unit in `HM.unit` (15 w600; "%" in D-DIN 24). The pill is 17 below: 18 tall, radius 3, `HM.verdict` 11 w700. Inside the range: a check and `HM.within` on `HM.withinChip`. Far out on the harmful side: `C.poor` on `DC.hurtChip`. No data: `DC.ink3` on `HM.noneChip`.
  - Order: Respiratory Rate, Blood Oxygen (SpO₂), RHR, HRV, Skin Temp (from baseline).
  - The pill writes the range in the value's own unit and never names a unit the tile does not show. Skin temperature shown in °C is ranged in SD, so its pill says "within usual range" / "elevated" / "low" with no numbers.
  - Blood oxygen is a ring's nightly figure (`getNightSpo2`) held against 95–100 %. The band's SpO2 byte is recorded for research only and never shown.
- **Share.** A 56-tall card 40 below the tiles: share glyph (26) and "SHARE YOUR HEALTH REPORT" in `HM.share`. It shares the readings as plain text through the system sheet. The footnote under it is in `HM.note` / `HM.footnote`.

### 14.6 Nap (`nap_detail.dart`)

Laid out like a recorded activity: the header on the LEFT (back chevron, the lounger mark, "NAP", the window), TIME ASLEEP in `C.dialSleep` `F.n34`, the heart rate filled in `C.dialSleep` as an activity's is in strain blue, the movement lane under it, then KEY STATISTICS as compact cards (`F.num(F.head)`): in bed, asleep, average and lowest heart rate (lowest whole minute), moving %. **No stages.** The pipeline stores a nap as a window and its minutes asleep; a stage split, wake events, latency, efficiency bands and "typical ranges" would all be invented, and so would "this nap reduced your sleep need by N minutes" (the sleep coach's applied credit is not the raw nap minutes).

**The movement lane** (`movement_lane.dart`) is one column a minute under a heart-rate chart, its height the share of the minute the wrist turned more than 5° (`compute/movement.dart`, the same measure as the day's stored five-minute curve). Ink 40–45 %, tops rounded `R.sm/3`, on the chart's own clock. Read from the band's seconds while they are kept, from the stored five-minute curve after; nothing measured is no column. It sits under the nap chart and under the day's sideways heart rate (§14.3), whose top strip is now slim (`S.x16 + S.x2`, `I.md` marks, `F.num(F.head)` figures) to make the room.

**A recorded activity's strain** (§14.2) rides over its heart rate: the headline strain re-scored over each growing stretch of the session (`strainCurveOf`, the live gauge's own sequence), in ink, on the dial's 0–21 scale at the right edge, with a key under the chart. Drawn only when it ends at the headline figure.

### 14.7 Strength trainer

- Two tabs, PROGRESS and MY WORKOUTS.
- **Progress:** total volume load with its own W / M / 6M segments and page chevrons, drawn with `ScrubColumns` at a fixed slim bar width. A Personal Records list with ADD; tapping a record shows its progress as a `ScrubLine` with the same readout, once there are at least two sessions.
- **My Workouts:** the title with a compact **+ BUILD** pill (32 tall, `card`) at its right, opening a sheet of two rows: Build it yourself, Generate with AI. Then the saved workouts with a three-dot menu, and Start a Workout (Quick Start, a 44 pill).
- Progress reloads whenever the app's session ends (finished here, from the minimised bar, or from a saved workout), so its sets count in the volume and records at once.
- Exercise photos from the bundled Free Exercise DB are cover-cropped thumbnails. A placeholder dumbbell tile stands in when there is no photo.

### 14.8a Live strength workout (`activity/live.dart`, `LiveStrength`)

The whole session as exercise cards, each with its own set table. Sizes are the compact reference's.
- **Header:** a bare 40 **⋯** at the left, the **workout's name** (`F.caps` w800, the saved workout's name or the activity's) over the session clock `00:30:54` (`F.body` w600 tabular, ink2) with the heart rate after it (`128` w700, `BPM` `F.over` ink3; nothing when the band is not reading), and a bare 40 **+** (add exercise) at the right.
- **Tabs:** LIVE SESSION · EXERCISES, `F.caps` w800, 40 tall, a 2 px `optimal` underline under the chosen one over a `line` hairline.
- **Exercise card** (`card`, `R.lg`, padding 12, 12 apart): a 44 thumbnail (`R.md`), the name in `F.body` w700 over `3 Sets` in `F.cap` ink3, and a grip handle (32) that **drags the card to reorder the session**, mid-workout.
  - The table: `SET · REPS · WEIGHT (KG)` in `F.over` ink3, then a row per planned set: the number (32 column), two **36-tall `card2` inputs** (`R.sm`, `F.body` w700, typed in place), and a 32 ▶. The row being lifted is outlined `optimal` 1.5 (`R.md`). A logged row reads back what was lifted with a check in place of the ▶; only each exercise's next row has a live ▶.
  - Under it, 32 round `card2` − and + (remove / add a planned set) and, while nothing is logged on it, a trash to remove the exercise.
  - A dumbbell lift adds "If lifting two dumbbells, enter the combined weight of both." in `F.cap` ink3.
- **Bottom bar:** an outlined **START SET** pill (44 tall, `optimal` 1.5 border and text, `F.caps` w800) with a 44 `card2` stop circle beside it. START SET opens the set and the pill becomes `FINISH SET · 0:23` on an `optimal` 14 % wash; FINISH SET logs the outlined row. A finished exercise hands over to the next one with rows left. No rest countdown; the rest actually taken is recorded from the gap between sets.
- **EXERCISES tab:** the order at a glance: a row per exercise (36 thumbnail, name, `2/3`, a check when done, the grip), reorderable, tap to go to it.
- **⋯ opens a sheet:** **Minimise** first (the session lives on `LiveDraft`; the bar above the tab bar brings it back, as does Android back), then Swap, Add, Skip exercise, Log the rest as bodyweight, and Effort (RPE) 6 to 10.
- Starting from a saved workout carries its plan (rows) and its name into the session.

### 14.7a The Health tab (`health_tab.dart`)

Age and Journal behind one `RangeSegments` (`AGE` / `JOURNAL`, the default 179 wide, 44 tall), centred at the top over the page; each page starts under it and paints up behind it. The tab keeps the page last shown while the app runs; a fresh launch opens on Age.

### 14.8 Locus Age (`locus_age.dart`, `locus_blob.dart`, in the Health tab)

The Health tab (`health_tab.dart`) is two pages under a small `AGE | JOURNAL` switch, always char, painted up behind the status bar.

- **Header:** `NEXT UPDATE IN n DAYS` and a week pager. Weeks run Sunday to Saturday and only finished ones are shown. Unlocked weeks only; while locked there is no pager.
- **The blob:** 274 across at rest, a `BlobSim` of 72 spring nodes and 340 specks, stepped by a ticker and painted through its own notifier so no widget rebuilds. A finger pulls the rim toward it and scatters the specks; a tap gives way and ripples. **A finger that lands on the blob does not scroll the page**: an eager recognizer over the blob's circle wins the arena. A drag that starts anywhere else scrolls as usual. Reduced motion: the ticker never starts.
- **Tone** is how the age compares: older blue to mint, a little younger teal, 4 or more years younger green, no reading slate.
- **Scrolling** shrinks it to 100 at the top between `YEARS OLDER` and `PACE OF AGING`. The header fills solid behind it so the rows slide under.
- **Below:** the calibrating banner while history is under six weeks, the pace strip (−1.0x to 3.0x, needle and number above it), the week's note, then Sleep, Strain and Fitness rows and the two trend charts.
- **A row:** 12 segments, grey around the target, amber short of it and green past it, brighter the further away. ▼ six month average, ▲ 30 day average, years on the right. Opened: a thick band, both labelled, a note and `VIEW TREND`.
- **Honesty:** no data, no row. Until 21 recoveries in 31 days the age, pace and every row's years read `--`.

---

### 14.8a Energy reserve (`home/home_energy.dart`, Home)

The level, a 46-tick bar, the wake level, the day's line on 0-100 with 33 / 67 guides (a compact chart, 102 tall; on today's chart a dotted line from now to midnight at today's own pace outside workouts and naps, `projectEnergy`, once an hour of ordinary minutes is known, with one `F.over` ink3 line under the chart giving the midnight level), CHARGED and DRAINED tiles and any effort listed under them. Green from 67, yellow from 34, red under it. Worked out minute by minute (`compute/energy_reserve.dart`), the way a body-battery reserve is described: it runs 5–100 and carries over from one day to the next. Asleep it charges up to 0.2 a minute, less the more stressed the night (0.11 a minute where sleep stress is not scored). Awake and calm (stress under 25 % of the scale) it charges up to 0.05 a minute; above that, stress drains it from 0.03 to 0.12 a minute; effort (heart-rate reserve over 40 %) drains at its own rate. Last night starts from where yesterday's reserve stood at sleep onset; without that, from the morning's recovery (25 + 0.7 × recovery). CHARGED and DRAINED count from midnight. Any missing input hides the card.

### 14.8b Reports (`screens/reports.dart`, `compute/period_report.dart`, More → Reports)

Two dial screens (§14.1a: `DialScaffold`, `dialCard`, page margin 18).

- **Reports**: `RangeSegments` WEEKLY / MONTHLY across the page, then the periods newest first, grouped under their month (a week files under the month it starts in; months under their year) in `F.dInsight` ink, 18 above and 10 below. Each row is a `dialCard` 63.6 tall, 9 apart, padding 18: the range (`2 NOV - 8 NOV`, or the month) in `F.dInsight` white, `Partial week` / `Partial month` under it in `F.dLegend` ink2 while the period holds today; then a 24 recovery ring (stroke 3.5, `DC.track`), its mean in `F.nSmall` right-aligned in 40, and a chevron at `I.lg` ink2.
- **Weekly / Monthly Report**: the share icon (`share2`, `I.lg`) shares the report as text. Under the bar: the period in a `WindowPager` spread across a 195 `DC.chip` pill; `RangeSegments` WEEK / MONTH, 151 wide; then
  - **three rings** (`ScoreRing`), each in a third of the width, 83 % of it across, stroke 6.6 % of the ring, flat start, solid on `DC.track`: average sleep performance (`dialSleep`), recovery (`recoveryColor`) and strain (`dialStrain`, 0–21, no %). The figure fitted to 22.9 % of the ring's height (its capitals), `F.n34` with an `F.n24` unit 1 apart; `AVG SLEEP` in `F.dNav` ink 8 under the ring, 6 above the change; the change on the period before in `F.dTiny`, `optimal` when better, `strainDown` when worse, ink2 for strain or no change.
  - **the summary**: one or two sentences in `F.dBody` w400, line height 1.38, inside a 1 px `coachEdgeB` → `coachEdgeA` edge, `R.xl`, no fill.
  - **cards**, each a `dialCard` with the title in `F.dLabel`, a note ("Days", "vs. last") in `F.dTiny` ink2 and a `DialInfo`: **Recovery Breakdown** (a 13.5 bar split green / yellow / red with 2 gaps, then a 25.6-pitch legend: 12 dot, the count in `F.n17`, the band in `F.dLabel` ink2); **Averages** (seven rows 63.6 tall on `DC.line` hairlines: the name, then flush right the value in `F.nRow` with its unit in `F.dText`, last period's under it in `F.dLegend` ink2, and a 9 triangle in a fixed 24 slot: green for better, `strainDown` for worse, ink2 for strain); **Training Balance** (7-day over 42-day mean strain: Easing off under 0.8, Balanced to 1.3, Overreaching over it, in `F.t2` w700; the ratio in `F.dTiny`; a sentence; it needs 14 days of strain in the 42); **Top Journal Effects** (`VIEW ALL` opens Behavior Insights; Behavior Insights' column heads; the three journal entries with the biggest effect, each in a `DC.weekCard` block with its impact bar, figure and "20 days with, 60 without. 90% CI −33% to −22%"); **Best and Worst Day** (rows 106 tall: the day and its date, then flush right a 64 `ScoreRing` over `Recovery` and the day's strain in `F.n24` `dialStrain` over `Strain`, captions on one line; tapping the row opens that day on Home, `openDayOnHome`, as if the user had stepped back to it). Only periods with stored data are listed, and the pager skips empty ones. **Top Journal Effects** shows while it is locked too: each entry needs 5 days with and 5 without, and the card lists how far each has got.
  - Gaps: 26 under the rings' captions, 39 and 37 under the summary and the breakdown, 16 between the rest.
  - At large text sizes rows grow and figures shrink to fit; nothing is cut.
- **What counts**: weeks run Monday to Sunday, months the calendar month. Recovery and sleep count today once they are in; today's strain does not, nor does it count against its target. Every figure is a mean of the stored days that have it, `--` when none do. The journal's 90% interval is the difference of the two means ± 1.645 standard errors (unpooled).

---

## 15. Honesty and copy

- **Never invent a value.** A figure that is missing is `--`. A metric that is missing as a whole is a `StatusCard`: *what* is missing → *why* (the pipeline's own reason first, a measured wear gap next, the screen's fallback last; "Nothing recorded says why" when nothing knows) → *what fixes it* (a button only if pressing it can change the outcome).
- **Stale is absent.** A number from an earlier night is not shown in today's slot; the reason is shown instead ("Last night is still being worked out.").
- **No streaks** outside the Profile page's Data Highlights (the longest run in the chosen period, a fact and never a nag), no "you have", no severity words on respiratory or illness surfaces. Observations state a pattern against the user's own baseline, never a cause.
- **Voice:**
  - Card titles are UPPERCASE `F.caps`.
  - Sentences are sentence case and plain ("Your average HRV this week is 58 ms.").
  - Empty states are short and factual ("Nothing recorded for this day yet.", "No strain recorded this period.").
  - Buttons and text actions are written in sentence case in code ("Sync the band") and **drawn uppercased** (`SYNC THE BAND`), like `ADD ACTIVITY` and `SET ALARM`.
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
| `SegmentedButton`, `DropdownButton`, `FilledButton` / `ElevatedButton` / `OutlinedButton`, `IconButton`, `showDatePicker` / `showTimePicker`, `SwitchListTile` and the other Material list tiles | `RangeSegments`, an `AppSheet` list, `BigButton` / `TextAction`, `RoundIconButton`, `pickDate` / `pickTime`, `SetRow(switchValue:)` |
| numeric `Icon(size:)` | `I.*` |
| numeric `EdgeInsets` | `S.*` |
| `Image.asset(` | nothing: the app has no bundled pictures (Lucide and `marks.dart`) |

No file is exempt (`_pendingOverhaul` is empty). Every new public widget needs a case in `lib/ui2/profile/gallery.dart` (or an entry in `_notComponents` if it is a screen), and every ui2 file is exported from `lib/ui2/ui2.dart`.

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
- The share posters (`activity/poster.dart`) keep their own art direction (sport-tinted gradients over a map or photo): they are exported images, not app chrome.
- The hypnogram keeps its lavender lane ramp, and the drawn `Art` SVGs keep their baked-in hues.
- Some screens write their own 24-hour `H:mm` clock (`_ActivityCard` on the strain page) instead of following the user's 12/24 h choice through `formatClockOf`.
- Light theme: every token is defined and contrast-tested, but the reference matching was done in dark. Check new work in both themes.

---

## 18. Imagery

- **No drawn pictures.** The old SVG silhouettes (`Art`: ring, watch, chest strap, workout, wellness, sleep, food, heart) are deleted, and so is `StatusCard.art`: an empty state is the card's Lucide glyph and its words. Nothing is fetched at runtime. There are no bitmap device photographs. The welcome and pairing screens show no device at all: the welcome draws only the Locus mark writing itself over the wordmark, pairing draws hairline range rings round a glyph (§10.5, Onboarding). The sensor rows in the device picker are icon rows.
- Nothing drawn carries another maker's logo or name: devices are generic glyphs.
- Exercise photos come from the bundled Free Exercise DB (public domain, credited in `NOTICE.md`), cover-cropped 192 × 128 JPEG thumbnails, with a dumbbell tile as the placeholder.
- The `AuroraTile` grain is `assets/images/grain.png` tiled at 4 % opacity, painted once behind a `RepaintBoundary`.

### 14.8c Rebuilt on the system (band battery, step counter, cloud account, compare devices)

- **Band battery** (`battery_detail_screen.dart`, from the battery line on Home and My devices): a `Surface` with `BATTERY NOW` as a big `ScrubReadout`, a 8-tall bar (`track`; ink, `recGreen` while charging, `strainDown` at 20 % or under) and the time left; `RangeSegments` DAY / WEEK; a `ScrubLine` of the band's battery samples (15-minute slots over 24 h, hourly over 7 days, an hour without one breaks the line, 0/50/100 % ticks) with charging stretches shaded `recGreen` at 16 %; and a DRAIN card that gives the rate, a day's worth and when it runs out, only when the forecaster has enough discharge readings (otherwise it says so; it never assumes a rate).
- **Step counter** (`step_calibration_screen.dart`, Settings → Band): the correction the derivation has learned for the paired band's family and how it is worn (`×1.08`, or `--` with the reason), and how it is learned (phone days, 30 of them, pulled toward ×1.00, needs three, 1,000 phone steps a day, clamped ×0.50–×2.00). The old walk test is gone: it read a counter that only runs in a workout and saved a factor under a key the step engine never reads.
- **Cloud account** (`account_screen.dart`): signed in, a `settingsGroup` of who, last backup, server and the auto-backup switch, then `BACK UP NOW` and a `SIGN OUT` text action; signed out, one sentence, `AppField`s for email, password (obscured) and server, and `SIGN IN`.
- **Compare devices** (`watch_compare_screen.dart`): a `WindowPager` for the day, the other app as a card that opens an `AppSheet` list, a heart-rate card with `RangeSegments` DAY / NIGHT and a `ScrubLine` (the band in `dialStrain`, the other watch in ink2 painted on the same scale, 5-minute columns, a quarter hour unmeasured breaks either line), and the side-by-side table with `--` for an absent value. The band is called the band, not by its maker's name.

### 14.9 My sources and the band's page (`profile/devices.dart`)

- **Calculating:** under the synced-through line, while the derive queue has work, one `Surface` (padding 16): a 16 spinner (ink3, 2 wide), 12, then a title in `F.body` w600 and a detail in `F.cap` ink3 (`deriveStatusText`). Running a full pass: `Calculating sleep, recovery and strain` / `Tue, Nov 4 done, 2 of 5 days`. Running the light pass: `Updating the latest day` / strain, heart rate and steps from the newest band data. Queued: `Calculation queued` / what, and what it waits for (the band to finish sending, the workout to end, the app to be open, or a few seconds).
- **My sources** lists LIVE sources, each a `SourceRow`. Under the band's row sits `BandStats`, one `Surface` of three rows, so nobody has to open the band to read them: **Battery** (the percentage, and under it only how long is left: "about 3 days left", or "Charging"), **Last data**, and **Calibration** (the band generation, value only). The band's percentage is therefore not repeated on its `SourceRow`. There is **no quality ladder** on this screen; the tier is still named by the pill on each row and by the tier card on a source's own page.
- **The band's page** keeps Name, Worn on, Battery (same line as above: no charge history, no millivolts), Last data, Calibration (value only, no explanation), Buzz the band and Forget. **No heart-rate row**: the live heart rate is on Home and the monitors, and the page no longer holds the live stream open.

### 14.10 The coach (`screens/coach.dart`)

Every AI chat is this one screen, in the dark palette whatever the theme (`AlwaysChar`).

- **Ground:** `C.coachSky`, a vertical gradient from a warm dusk grey under the header, through slate, to near-black by just past the middle (`C.coachSkyStops`).
- **Header:** a bare back chevron, then centred `LOCUS COACH` in `F.body` w700 tracked 2.2 with the model in a small tag under it (ink 14 % ground, `R.sm`, `F.over` w700 caps), and a **History** glyph on the right that opens the past chats (and New chat, and the briefing disclosure).
- **Every opening is a new chat.** Nothing carries on from last time; earlier chats are under History.
- **Daily Outlook:** opened from Home, the chat starts with today's briefing as the coach's first turn (the stored one, the morning's standing in until the evening's exists, or written there and then with the thinking dots). The question it answers is kept in the history, so a reply has context.
- **Thread:** the coach's turns sit beside its orb (24, on the first item of a run) in `F.head` size, regular weight, ink at 84 % so bold figures stand out; the user's turns are right-aligned `card2` bubbles. The list fades out into the composer.
- **Composer:** a (+) that opens suggested questions, a new-chat glyph (ink3), then the message box: a `R.xl` field outlined by a 2 px coach-orb gradient (`coachEdgeA → coachEdgeB`), filled with the bottom of the sky, the send arrow inside it (ink once there is text, ink3 before).
- **Empty new chat:** a large orb, "How can I help?", the intro line and the starter cards.

### 14.11 App start

- **A launch always opens on Home.** The tab last shown is not stored, so closing the app (swiping it away) and opening it again starts fresh, never on the screen from last time. A notification's own destination still wins.

The Locus mark writes itself **once** on the cold-start cover (`BootSplash`, then the wordmark under it) and holds; the cover leaves when the app is ready and the stroke has finished. It never loops. Reduced motion shows it still and drops the cover the moment the app is ready.

### 14.13 Calibration (`screens/calibration.dart`, `onboarding/what_to_expect.dart`)

The first two weeks, while Locus learns your normal. Each metric unlocks on its own count, the same gate its number uses: sleep after night 1, strain from day `quietHrrMinDays + 1` (4), the stress monitor after `kStressBaselineDays` (3) usable days, recovery and the health monitor after 14 nights (`readinessCompositeMinBaseline`, `kWhoopMonitorMinNights`). `Calibration.of` builds this from Home's data; a count that has caught up while the metric still abstains fills every segment but one, never all. Progress is drawn in `C.calibrate`, empty segments in ink 20 %.

- **`SegmentBar`:** one segment per night or day, `S.x1` tall, pill ends, `S.x1` apart, each at most `S.x6` wide.
- **`CalibrationStrip`:** the foot of a card still calibrating: "Wear the band to sleep for N more nights to calibrate" (or "…for N more days…") in `F.cap` ink over its `SegmentBar`, on a `p.bg` panel, `R.md`, padding `S.x3`. Under the Strain & Recovery tile while recovery calibrates, at the top of the Health Monitor while it has fewer than 14 nights, and on the Stress Monitor (in a `Surface` under `CALIBRATING` and one sentence) instead of the old "Building your baseline" card.
- **Calibration timeline card (Home):** `Surface`, padding `S.x4`. `CALIBRATION TIMELINE` in `F.caps` w800 with the chevron at the right; under it the sentence in `F.cap` ink2 and, to its right, the `CalibrationRing`: 48 across, a 4 pt ink 12 % track with the nights arc in `C.calibrate` from twelve o'clock, round cap, `1` in `F.n17` and `/14` in `F.num(F.over)` ink3. Tap: the milestones. Swipe: gone until tomorrow.
- **Milestones screen:** `p.bg` with a `C.calibrate` 22 % (light 12 %) wash at the top fading out by 40 %. Close × at the left, `YOUR FIRST TWO WEEKS` centred in `F.caps` tracking 1.3. `Unlock key milestones` in `F.t2`, a sentence in `F.body` ink2, then `SLEEPS LOGGED n/14` in `F.num(F.over)` ink3 tracking 1.0 with a hairline to the edge, then `NightPips`: 32 pt circles, 12 apart, seven to a row, the nights logged ringed 2 pt in `C.calibrate` over an 18 % fill. `Your key milestones` in `F.head` w700, then one `MilestoneCard` each, 12 apart: unlocked is a `Surface` (56 pt icon tile on `card2`, title `F.body` w700, sentence `F.cap` ink2, `VIEW DETAILS →` in `F.caps` through `p.on(C.calibrate)`); locked is an ink 14 % outline at `R.xl` with the tile at ink 5 %, "Log 14 sleeps to unlock" / "Wear the band 4 days to unlock" and the `SegmentBar`, and an info glyph top right that opens a sheet. "How calibration works" (`TextAction`) closes the list.
- **What to expect (`WhatToExpectScreen`):** shown once, the first time the shell opens after onboarding, and from the milestones. Always char. `NightWheel`: fourteen ring segments (14 % of the wheel thick, ink 10 %), numbered 24 pt pips on `p.bg` at each night's end, the nights logged and tonight lit in a `C.calibrate` sweep standing 15 % proud, and each metric's glyph on the night it unlocks; the Locus mark and `NEW FEATURES / UNLOCK NIGHT / BY NIGHT` (`F.over` tracking 1.3) in the middle. `What to expect next` in `F.t2`, a sentence in `F.body` ink2, then `FINISH` in `F.caps` beside a 64 pt `C.optimal` disc with a check. A 12 % `C.optimal` glow rises from the bottom-left corner.

### 14.12 Small screens

- **Alarm editor** (sheet): fits one screen. The time is the control, with no box drawn round it, "Rings in…" under it; REPEAT presets and the day circles; the label; one card with Alarm on, Alarm mode (value only) and Smart wake (value only, opens a picker); Save, then Delete.
- **Weight trend:** the logged weights are joined point to point across the days between them in strain blue, with a ring on each logged day, like the trend view's lines; the 7-day trend is a thin faint line behind it. Axis labels never climb into the legend.
- **Charts open on the week.** Trend View, metric detail (7 days, or Today while there is less than a week of history), battery and weight all start on the week view; the day view is one tap away.
- **Compare metrics** draws its two series in strain blue and amber, `C.dialStrain` and `C.amber` (`kCompareColours`), whatever the metrics: opposite on the wheel, never two shades of one family.
- **Paired line labels** (`ScrubPair`): on each day the higher value is labelled above its point and the lower below, so close values never print over each other.
- **My workouts:** the saved workouts come first, then Generate with AI and Build a workout, then Start a Workout.
