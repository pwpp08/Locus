# WHOOP parity research

Date: 2026-11-07. Goal: for each metric, find what is closest to WHOOP's own algorithm, then choose
between WHOOP's method (where known), Pulse's, ours, or a better option.

## Sources and how much to trust them

| Tag | Source | Trust |
|---|---|---|
| **SUP** | WHOOP support articles (Recovery, Sleep, Strain, Strain Target), read 2026-11-07 | Official, but no formulas |
| **LOC** | WHOOP Locker articles (HR zones, Stress Monitor, Health Monitor, Strain Target) | Official, partly marketing |
| **WP** | *The WHOOP Healthspan Feature* white paper (2025, 42 pp.) | Official method, constants partly unpublished |
| **PAT** | WHOOP patents US9750415B2 and US11574722B2 ("Heart rate variability with sleep detection", "Determining a recovery indicator...") | Real WHOOP filings; an "embodiment" is not proof of what ships, unless a number matches |
| **FIT** | reinmaker/noop "Yoop" fork: formulas fitted to one user's WHOOP export (121 days, Jun–Oct 2026), tested on held-out days and against live WHOOP app readings | Empirical, n = 1 person. Good for shape and constants, not universal |

Licence: noop is **PolyForm Noncommercial 1.0.0**; this repo is **AGPL-3.0**. Do not copy noop code. Formulas and
published constants can be reimplemented from the descriptions below, with credit.

## Metric by metric

### Recovery

- **WHOOP (SUP):** bands green ≥ 67, yellow 34–66, red ≤ 33. HRV and RHR are "the two biggest contributors".
  HRV is compared against a 30-day baseline. Also listed as inputs: respiratory rate, sleep hours vs need, light
  sleep/wake, skin temperature (either direction), SpO₂, cycle phase.
- **WHOOP HRV (SUP, PAT):** RMSSD, "weighted average across your entire night of sleep, with more weight given to
  slow-wave sleep and later stages of the night". The older patent took a fixed window inside the last SWS
  period before waking, picking the window with the best signal quality.
- **WHOOP RHR (LOC):** "dynamic average weighted toward your last period of slow-wave sleep".
- **FIT (best evidence of the actual output):**
  `Recovery = 100 / (1 + e^-(0.7325 + 0.5978·z_HRV + 0.0877·z_RHR + 0.0582·z_resp))`, each z against the previous
  **14** nights (mean and 1.253 × mean absolute deviation; at least 5 nights). Lower RHR and resp count as better.
  RMSE 6 points; colour band right 82% of the time. A night at baseline reads **67.5%**. Adding sleep or skin temp
  did not improve the fit.
- **Pulse:** HRV 55 / RHR 20 / sleep 15 / resp 5 / temp 5, S-curve slope 1.6, about 58% at baseline. Not fitted to WHOOP.
- **Ours:** HRV+RHR 0.70 (combined), resp 0.20, temp 0.10; median/MAD z; logistic with 50 at baseline;
  self-recalibration; bands 26/37/61.
- **Decision:** adopt the FIT formula. Use WHOOP's 67/34 bands. Keep our robust baseline engine but switch to a
  14-night window for the score. Optionally weight HRV windows toward late night and deep sleep. Resp weight
  becomes small (0.058 vs our 0.20) and temp drops out of the score; both still feed Health Monitor and illness.
  Our personal recalibration is removed: WHOOP has none, and the fitted intercept already puts a normal night at 67.5.

### Strain

- **WHOOP (SUP, LOC):** 0–21, non-linear; cardiovascular load from HR plus muscular load (strength, HIIT, yoga,
  Pilates estimated from activity type and **duration** when not logged). 21 ≈ "max heart rate for 24 straight
  hours". Anchors: 1 h walking ≈ 6.5, 1 h running ≈ 12.0, functional fitness ≈ 10.1, average member day ≈ 11.0.
  Bands Light 0–9, Moderate 10–13, High 14–17, All out 18–21.
- **PAT:** `v = (HR − RHR)/(HRmax − RHR)`; weighted with `w = 0 / 1 / 18 / 42` for HRR = 0, ≤ AT, AT–CPT, > CPT;
  integrated, normalised by `w(1)·24 h`, then mapped by `21·0.5·(arctan(N(x−p))/(π/2) + 1)`. AT, CPT, N and p are
  not given.
- **FIT:** per-minute load `max(x·e^(4.025x) − 0.1735·e^(4.025·0.1735), 0)` with x = HRR fraction; Strain =
  `3.584·ln(1 + load/11.48)`, capped at 21. RMSE 1.3 per activity. Checks against WHOOP's anchors: 1 h at 35% HRR
  gives 6.8 (WHOOP's walk: 6.5); 1 h at 60% gives 12.7 (WHOOP's run: 12.0). Unlogged strength adds
  `0.0773·minutes²` of load (fit to 36 lifting sessions, error 0.18).
- **Pulse:** Edwards zone points from 50% HRR, `21·ln(p+1)/ln 7201`. Ours: Banister TRIMP above a personal
  quiet-waking level, 400 net TRIMP = 21 (saturates after about 3 h at 160 bpm).
- **Decision:** adopt the FIT curve on the user's own HRR (FIT used a fixed 190 bpm HRmax yardstick; ours uses
  the real profile HRmax, so re-check the anchors after switching). Add the duration-based muscular term for
  strength-type activities. Drop the 400-TRIMP map: it reaches 21 far too early compared with WHOOP.

### HR zones and max HR

- **WHOOP (LOC, WP):** HRR (Karvonen). Z1 40–60%, Z2 60–70%, Z3 70–80%, Z4 80–90%, Z5 90–100%. RHR used for zones is
  refreshed **monthly**. HRmax starts from age (support also mentions sex and weight) and is raised automatically
  when a workout exceeds it.
- **Pulse:** Z1 from 50%. **Decision:** use WHOOP's boundaries (Z1 from 40%). Auto-raise HRmax from observed peaks.

### Sleep need, sleep debt, naps

- **WHOOP (SUP):** need = baseline + strain + debt − naps; average baseline 7.6 h; naps reduce need, not debt.
- **PAT, confirmed numerically:** strain add-on `f(i) = 1.7 / (1 + e^((17 − i)/3.5))` **hours**. Strain 15 → 36.8 min
  (WHOOP's own example: 37); 10.2 → 12 min and 11.1 → 16 min (two live WHOOP app readings in FIT). All match.
- **FIT debt:** `debt(t) = 0.5 × max(0, need(t−1) − asleep(t−1))`, one night only; RMSE 5.7 min against WHOOP's debt
  column. Pulse's 55% / 14-night ledger overstated it by about 70 min.
- **Ours:** strain add-on `strain/21 × 45 min`; debt = full (personal need − typical night). **Pulse:** 3 min per
  point above the 28-day mean; 20% of a decaying ledger.
- **Decision:** patent sigmoid for strain, the FIT one-night 50% debt, naps subtracted. Keep our personal baseline
  (upper quartile, 7–9.5 h), but fall back to WHOOP's 7.6 h population average on a cold start rather than
  showing nothing.

### Sleep Performance

- **WHOOP (SUP):** sufficiency (hours vs needed) + consistency + efficiency + **sleep stress**; weighted, no
  weights published. Bands: score 85/70; hours vs needed 85/70; consistency 80/70; efficiency 90/80;
  sleep stress < 1% / 1–5% / > 5%. Consistency needs 3 consecutive nights. **Restorative sleep is not part of
  it** (Pulse's 20% restorative weight is not WHOOP).
- **FIT:** `0.272·HvN(capped 100) + 0.327·consistency + 0.368·efficiency`; RMSE 3 points (hours vs needed alone:
  11). Without consistency, the other two are scaled by 0.967/0.640. Sleep stress was not needed for the fit.
- **Ours:** 65% duration / 20% efficiency / 15% restorative, with efficiency and restorative floored at 50.
- **Decision:** adopt the FIT weights. Drop restorative from the score (keep it as a displayed stat). Remove the
  50 floors. Add WHOOP's per-component bands.

### Sleep Consistency

- **WHOOP (WP):** "how similar sleep and wake times are over the last 24 hours compared to the previous 4 days",
  0–100%. Healthspan target ≥ 70%.
- **FIT:** compare tonight's sleep-onset and wake clock times with each of the previous 3 nights:
  `pair = max(0, 1 − ((|Δbed| + |Δwake|)/700 min)^0.75)`, mean × 100. Nights are asleep-to-awake windows
  (records < 2 h apart merged; windows < 3 h are naps and excluded).
- **Pulse/ours:** Phillips SRI over 7 days (a different, research metric).
- **Decision:** add the FIT 4-night score as "Sleep Consistency" (feeds Sleep Performance and WHOOP Age); keep SRI
  as an extra.

### Strain Target

- **WHOOP (SUP):** depends on today's Recovery, Strain already accumulated, and cycle phase. It "does not directly
  factor in past activity levels". One example: Recovery 70% → optimal 12.3, range 8.3–16.3 (±4). States:
  restorative / optimal / overreaching; intent picker restorative, maintenance (default) or overreaching.
- **Pulse:** 28-day strain mean × colour multiplier; this is the opposite of WHOOP's stated rule.
  **Ours:** fixed bands by recovery, nudged by fatigue and freshness.
- **No formula is published. My proposal:** optimal = 6 + 0.09 × Recovery (0 → 6, 70 → 12.3, 100 → 15), range ±4
  clamped to 0–21; intent shifts the centre by −2 / 0 / +2. It passes WHOOP's one example. Label it an estimate.

### Stress Monitor

- **WHOOP (LOC):** HR **and HRV** right now vs a 14-day personal baseline, motion accounted for, 0–3 (3 = your peak).
- **Pulse:** HR only. **Ours:** HR z + ln(RMSSD) z vs a 14-day quiet-minute baseline with motion damping; this
  already matches WHOOP's description.
- **Decision:** keep ours. Add **Sleep Stress** = share of sleep minutes scored high (≥ 2), with WHOOP's
  < 1 / 1–5 / > 5% bands; that is my reading of "time in high stress through the night", not a published formula.

### Health Monitor

- **WHOOP (LOC):** five vitals (resp, SpO₂, RHR, HRV, skin temp) vs personal range; green / orange / red.
- **FIT:** WHOOP's printed "typical range" = **25th–75th percentile of the last 30 nights**. That reproduced
  WHOOP's printed ranges for skin temp, RHR and resp to the digit, and HRV's lower end. A value just outside is
  still green; only readings far out on the **harmful side** are flagged (HRV down; RHR, resp, temp up), at
  about 1.4–3.5 SD, so FIT flags at 2 SD. SpO₂ uses fixed bands: 95–100 typical, ≥ 90 fine, ≤ 89 flagged.
- **Ours:** ±1.253 × spread (about ±1 SD), both directions; 4 vitals.
- **Decision:** adopt the 30-night IQR display, a one-sided 2 SD flag, and fixed SpO₂ bands. Our WHOOP 4.0 SpO₂ is
  relative ADC only, so show it once a calibrated absolute value exists, or show it as relative.

### WHOOP Age and Pace of Aging

- **WHOOP (WP):** each contributor → hazard ratio vs a health-optimised referent; `years = 10 × ln(HR)`
  (+10% mortality per year of age); WHOOP Age = age + Σ years over 6 months, with an SEM-based overlap correction
  (factors unpublished). Pace = (projected age if the last 30 days continue for 6 months − current) ÷ 0.5 years,
  shown from −1.0× to 3.0×. Not shown under 18. Unlock after 21 recoveries in the first month.
- **Targets (WP Table 1):** sleep 7–9 h (< 7 adds years, 7–9 small benefit, > 9 neutral); consistency ≥ 70%;
  steps 8,000 (younger) / 5,600 (older); zones 1–3 ≥ 100 min/week (70 when older); zones 4–5 ≥ 10 min/week (7 when
  older), benefit up to about 600 min/week; strength ≥ 40 min/week, no extra benefit past 2 h; RHR 60 (M) / 64 (F);
  VO₂max by age and sex (M 46 at 20–25 down to 21 at 100; F 40 down to 18); lean mass ≥ 80% (M) / 67% (F) at 30,
  no effect if not entered.
- **Evidence for the HRs:** RHR +9% risk per 10 bpm; steps −23% per 1,000/day (plateau 8–10k); short sleep +12%;
  regular sleep 20–48% lower; strength 30–60 min/week 10–30% lower; body fat +11% per 10%.
- **FIT:** a full implementation, with curve scales calibrated to one WHOOP readout and the white paper's Table 2
  (members aged 30: −1.6 y; US adult aged 30: about +6 y M / +7.5 y F).
- **Pulse:** 25% flat overlap discount, "doubling every 8 years", different references (RHR 60 for all, 10k steps,
  150/75 zone minutes).
- **Ours:** placeholder `age + (RHR−60)×0.15 − 1`, with a fallback age of 26.
- **Decision:** implement the white-paper method with WHOOP's targets. Test against Table 2 (−1.6 for a member at
  30) so the scales stay honest.

### VO₂max

- **WHOOP (LOC):** three tiers (passive from demographics + HR/zone data; GPS outdoor runs; lab entry); needs 14
  recoveries in the last 21 days; claims ±3.3–3.7 ml/kg/min vs 248 lab tests.
- **Ours:** the same three-tier structure and the same 14/21 rule. **Keep.** Use WP's VO₂ targets for WHOOP Age
  instead of a FRIEND percentile.

### Calories

- **FIT (low confidence, one person, not weight-normalised):** active kcal/min = −16.43 + 0.1988 × bpm (zero at
  82.6 bpm); Keytel read about 2× high below 110 bpm for that user.
- **Decision:** not enough evidence to switch. Option: calibrate Keytel against imported WHOOP workouts when an
  export is present.

### Not WHOOP features (keep as extras or skip)

Energy Bank (Pulse) is not a WHOOP metric; skip it, as our code already decides. Training balance / ACWR and
fitness–fatigue–form are not WHOOP features; keep them as extras. Pulse's Fitness Level percentile is not
WHOOP's; WHOOP compares VO₂max to its age/sex target table.

## Side effect worth noting

WHOOP's fitted Recovery uses no sleep stages, and its fitted Sleep Performance uses none either. After switching,
our weak stager (kappa 0.128 vs PSG) only affects the displayed hypnogram and restorative stats, not the
headline scores.
