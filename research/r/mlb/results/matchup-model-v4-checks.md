# Matchup model v4: robustness checks on the ablation

Generated 2026-10-06 by `matchup_v4_checks.R -v2r -v4-k -v4-switch -v4`. Validation seasons only; the 2023-2025 test is not read. Reference: `-v2r`.

Games: the 12142 pooled 2017-2022 games of matchup_model.R (2020 has no recency model and is out), 4857 of them in 2021-2022.
Differences are reference minus run log loss per game on each run's best variant (positive = run better), 1,000 draws.
Per-season and 2021-2022 columns resample home team-seasons. Two-way resamples home and away team-seasons independently and
weights each game by the product of its two draw counts. Week resamples ISO weeks within season. ECE: 10 equal-count bins of
the predicted home win probability, weighted mean of |mean prediction - win rate|.

| run | 2021 | 2022 | 2021-2022, home team-season | 2021-2022, two-way | 2021-2022, week blocks | ECE 2021-2022 | ECE pooled |
| --- | --- | --- | --- | --- | --- | --- | --- |
| -v2r | 0.00000 [0.00000, 0.00000] | 0.00000 [0.00000, 0.00000] | 0.00000 [0.00000, 0.00000] | 0.00000 [0.00000, 0.00000] | 0.00000 [0.00000, 0.00000] | 0.0136 | 0.0121 |
| -v4-k | 0.00025 [0.00009, 0.00042] | 0.00001 [-0.00015, 0.00017] | 0.00013 [0.00002, 0.00027] | 0.00013 [-0.00009, 0.00037] | 0.00013 [0.00001, 0.00027] | 0.0118 | 0.0116 |
| -v4-switch | 0.00006 [-0.00026, 0.00040] | 0.00000 [-0.00044, 0.00042] | 0.00003 [-0.00023, 0.00031] | 0.00003 [-0.00036, 0.00047] | 0.00003 [-0.00025, 0.00033] | 0.0156 | 0.0145 |
| -v4 | 0.00031 [-0.00007, 0.00068] | 0.00002 [-0.00047, 0.00047] | 0.00016 [-0.00015, 0.00046] | 0.00016 [-0.00032, 0.00066] | 0.00016 [-0.00013, 0.00046] | 0.0147 | 0.0135 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
