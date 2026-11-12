# Market blend weight out of sample (review queue item 10)

Generated 2026-10-09 by `blend_oos.R`. Registered in MATCHUP-PLAN.md (2026-10-09) before scoring. Model: v2 M5_plus_defense, frozen
walk-forward predictions. Close: proportional no-vig consensus closing line, corrected odds join. Blend: logit p = a + b logit(close)
+ c logit(model). "Close minus blend" is per-game log loss, positive when the blend beats the close; 95% intervals resample home
team-seasons (1,000 draws, seed 20261004).

Parity: the 2021-2022 fit reproduces the published blend, a 0.018, b 0.856, c 0.173, on 4253 games.

## (a) Cross-fit on the market-tuning seasons

| fit on | scored on | games | b (close) | c (model) | close minus blend | recalibrated close minus blend |
| --- | --- | --- | --- | --- | --- | --- |
| 2021 | 2022 | 2342 | 0.879 | 0.127 | -0.00010 [-0.00116, 0.00094] | 0.00011 [-0.00024, 0.00051] |
| 2022 | 2021 (backward in time) | 1911 | 0.845 | 0.198 | 0.00005 [-0.00048, 0.00058] | 0.00003 [-0.00041, 0.00051] |

Pooled over both scored seasons (4253 games): -0.00003 [-0.00061, 0.00062] against the raw close; 0.00007 [-0.00018, 0.00036] against the close recalibrated alone (the nested test of M5's information).

## (b) Uncertainty in the model weight

c on 2021-2022: 0.173 [-0.139, 0.494] (home team-season bootstrap).

## (c) Post hoc: the frozen 2021-2022 blend on the spent 2023-2025 test

Post hoc. The test was scored once on 2026-10-04; this reads it again and changes nothing.

| season | games | close minus blend |
| --- | --- | --- |
| 2023 | 2381 | -0.00041 [-0.00116, 0.00035] |
| 2024 | 2382 | -0.00083 [-0.00132, -0.00023] |
| 2025 | 1813 | 0.00047 [-0.00016, 0.00108] |

Pooled (6576 games): -0.00032 [-0.00071, 0.00006] against the raw close; -0.00020 [-0.00051, 0.00009] against the close recalibrated alone on 2021-2022. Refit on 2023-2025 (in sample, descriptive only): a -0.003, b 1.099, c -0.137.

Without the 12 late-close dates (`close_timing.R`'s rule, 6436 games): -0.00010 [-0.00049, 0.00027] against the raw close; 0.00002 [-0.00027, 0.00030] against the recalibrated close. Refit: a 0.001, b 0.826, c 0.111.

## Reading under the registered claim rule

The pooled cross-fit interval does not lie above zero, so the report does not say M5 adds information to the close out of sample. The 0.17 weight is an in-sample fit.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
