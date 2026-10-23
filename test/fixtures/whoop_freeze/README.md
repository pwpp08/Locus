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

- v114: regenerated (owner-requested test repair). Intended differences: the
  new `series.resp_timeline` (the overnight breathing line) and `algo_version`
  114 with the payload hashes that follow from them. One unrelated difference
  is also in these files: `dyn_p90` moved in its last float digit
  (0.016617360477042792 → 0.0166173604770428). It reproduces from the v113
  commit's own code on today's CI runners, so it is the toolchain, not a code
  change; the files were generated on CI (Linux, three zones) and were
  byte-identical across three separate runners.
