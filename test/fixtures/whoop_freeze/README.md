# WHOOP freeze goldens

Byte-identical pins of everything the band path stores for three synthetic
days (gen4 and gen5, full profile, 14 seeded baseline days), one file per
family and timezone. Written by `test/whoop_freeze_golden_test.dart`; see its
header for how to run each zone and which branches (zone sources, saved-session
HR ceiling, a confirmed nap, review suggestions) it forces. CI runs all three
zones (`.github/workflows/test.yml`).

Regenerate (`GENERATE_GOLDEN=1`) only with owner approval. A failing golden
means a WHOOP number moved. Fix the change, not the golden.

## History

- v116: regenerated with the owner's approval, for WHOOP parity
  (`compute/whoop_scores.dart`). Recovery is WHOOP's fitted logistic, so
  `readiness`, its `composite_z`, drivers (HRV, RHR, RR; temp leaves) and note
  moved, the baseline note reads `need=5`, and the calibration night count
  reads 0 (the WHOOP fit does not self-calibrate). The sleep coach gains
  `debt_min`, `last_night_need_min` and `consistency` (null on these days).
  No strain or zone value moved on the synthetic days. `two_device_day_expected`
  moved the same way. Generated on CI under UTC, +05:30 and -04:00
  (temporary `golden-regen-v116` branch).

- v115: regenerated with the owner's approval, for the strain-never-falls
  change (`compute/strain_peak.dart`). The only difference in any of the six
  files is `algo_version` 114 → 115 (nine places each); no stored value moved,
  because the synthetic days' strain only climbs. Generated on CI under UTC,
  +05:30 and -04:00.

- v114: regenerated (owner-requested test repair). Intended differences: the
  new `series.resp_timeline` (the overnight breathing line) and `algo_version`
  114 with the payload hashes that follow from them. One unrelated difference
  is also in these files: `dyn_p90` moved in its last float digit
  (0.016617360477042792 → 0.0166173604770428). It reproduces from the v113
  commit's own code on today's CI runners, so it is the toolchain, not a code
  change; the files were generated on CI (Linux, three zones) and were
  byte-identical across three separate runners.
