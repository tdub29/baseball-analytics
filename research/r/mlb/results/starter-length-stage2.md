# Starter length, stage 2: M5 with rebuilt game features against v2

Generated 2026-10-09 by `matchup_compare.R -v2 -sl-cand -sl-oracle`. Validation seasons only; the 2023-2025 test is not read.

Reference: `-v2`. Log loss on the 12142 games of matchup_model.R's pooled 2017-2022 row (2020 has no recency model, so it is
out of every pooled number). "Best" is each run's best matchup variant on 2017-2022; "vs ref" is reference minus run per game
(positive = run better) with a team-season cluster bootstrap 95% interval. Calibration slope: logistic slope of the outcome on the
logit of the best variant (1 = calibrated, below 1 = too extreme); 2017-2020 includes 2020. "Close" is matchup_model.R's close minus
matchup on 2021-2022 games with odds (positive = model better).
MODEL=M5_plus_defense: "best" in every column below is that variant, not each run's best.

| run | best | log loss | log loss 2021-2022 | ensemble | best vs ref | ensemble vs ref | best vs ref, 2021-2022 | slope 2017-2020 | slope 2021-2022 | close minus model, 2021-2022 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| -v2 | M5_plus_defense | 0.6703 | 0.6703 | 0.6699 | 0.00000 [0.00000, 0.00000] | 0.00000 [0.00000, 0.00000] | 0.00000 [0.00000, 0.00000] | 0.978 | 0.994 | -0.00207 [-0.00415, 0.00007] |
| -sl-cand | M5_plus_defense | 0.6700 | 0.6698 | 0.6697 | 0.00033 [-0.00003, 0.00069] | 0.00022 [-0.00000, 0.00044] | 0.00051 [-0.00004, 0.00111] | 0.987 | 1.007 | -0.00156 [-0.00334, 0.00028] |
| -sl-oracle | M5_plus_defense | 0.6590 | 0.6623 | 0.6586 | 0.01134 [0.00775, 0.01470] | 0.01126 [0.00800, 0.01434] | 0.00804 [0.00351, 0.01205] | 0.952 | 0.920 | 0.00647 [0.00187, 0.01065] |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
