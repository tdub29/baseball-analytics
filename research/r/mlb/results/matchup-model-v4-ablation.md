# Matchup model v4: validation ablation against v2

Generated 2026-10-06 by `matchup_compare.R -v2r -v4-switch -v4-regime -v4-k -v4-recal -v4-all3 -v4-all -v4`. Validation seasons only; the 2023-2025 test is not read.

Reference: `-v2r`. Log loss on the 12142 games of matchup_model.R's pooled 2017-2022 row (2020 has no recency model, so it is
out of every pooled number). "Best" is each run's best matchup variant on 2017-2022; "vs ref" is reference minus run per game
(positive = run better) with a team-season cluster bootstrap 95% interval. Calibration slope: logistic slope of the outcome on the
logit of the best variant (1 = calibrated, below 1 = too extreme); 2017-2020 includes 2020. "Close" is matchup_model.R's close minus
matchup on 2021-2022 games with odds (positive = model better).

| run | best | log loss | log loss 2021-2022 | ensemble | best vs ref | ensemble vs ref | best vs ref, 2021-2022 | slope 2017-2020 | slope 2021-2022 | close minus model, 2021-2022 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| -v2r | M5_plus_defense | 0.6703 | 0.6703 | 0.6699 | 0.00000 [0.00000, 0.00000] | 0.00000 [0.00000, 0.00000] | 0.00000 [0.00000, 0.00000] | 0.978 | 0.994 | -0.00207 [-0.00415, 0.00007] |
| -v4-switch | M5_plus_defense | 0.6704 | 0.6703 | 0.6699 | -0.00006 [-0.00025, 0.00014] | -0.00004 [-0.00014, 0.00007] | 0.00003 [-0.00023, 0.00031] | 0.982 | 0.999 | -0.00206 [-0.00415, 0.00010] |
| -v4-regime | M5_plus_defense | 0.6704 | 0.6706 | 0.6700 | -0.00010 [-0.00017, -0.00004] | -0.00006 [-0.00010, -0.00002] | -0.00026 [-0.00042, -0.00008] | 0.978 | 0.983 | -0.00229 [-0.00431, -0.00017] |
| -v4-k | M5_plus_defense | 0.6702 | 0.6702 | 0.6698 | 0.00008 [-0.00002, 0.00019] | 0.00005 [-0.00003, 0.00014] | 0.00013 [0.00002, 0.00027] | 0.982 | 0.995 | -0.00192 [-0.00396, 0.00020] |
| -v4-recal | M5_plus_defense | 0.6703 | 0.6703 | 0.6699 | -0.00002 [-0.00013, 0.00010] | -0.00002 [-0.00008, 0.00004] | -0.00000 [-0.00019, 0.00019] | 1.000 | 1.016 | -0.00203 [-0.00410, 0.00011] |
| -v4-all3 | M5_plus_defense | 0.6704 | 0.6704 | 0.6700 | -0.00010 [-0.00036, 0.00013] | -0.00006 [-0.00019, 0.00007] | -0.00014 [-0.00055, 0.00022] | 0.985 | 0.988 | -0.00217 [-0.00427, 0.00006] |
| -v4-all | M5_plus_defense | 0.6704 | 0.6704 | 0.6700 | -0.00012 [-0.00038, 0.00013] | -0.00007 [-0.00022, 0.00006] | -0.00014 [-0.00054, 0.00024] | 1.000 | 1.003 | -0.00214 [-0.00428, 0.00008] |
| -v4 | M5_plus_defense | 0.6703 | 0.6701 | 0.6699 | 0.00002 [-0.00022, 0.00025] | 0.00001 [-0.00012, 0.00014] | 0.00016 [-0.00015, 0.00046] | 0.986 | 1.001 | -0.00191 [-0.00394, 0.00023] |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
