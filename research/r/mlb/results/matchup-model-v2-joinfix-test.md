# Matchup model: test

Generated 2026-10-06. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2023 | 2429 | 0.6799 | 0.6803 | 0.6793 | 0.6794 | 0.6792 | 0.6926 | 0.6815 | 0.6794 | 0.6824 | 0.6788 |
| 2024 | 2429 | 0.6787 | 0.6781 | 0.6766 | 0.6763 | 0.6771 | 0.6925 | 0.6799 | 0.6756 | 0.6826 | 0.6759 |
| 2025 | 2430 | 0.6804 | 0.6799 | 0.6772 | 0.6774 | 0.6765 | 0.6897 | 0.6776 | 0.6775 | 0.6831 | 0.6765 |
| pooled | 7288 | 0.6796 | 0.6794 | 0.6777 | 0.6777 | 0.6776 | 0.6916 | 0.6797 | 0.6775 | 0.6827 | 0.6771 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.55.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2023 | 2381 | 0.6767 | 0.6795 | 0.6796 | 0.6790 |
| 2024 | 2382 | 0.6702 | 0.6771 | 0.6755 | 0.6760 |
| 2025 | 1813 | 0.6764 | 0.6766 | 0.6772 | 0.6765 |

Close minus matchup per-game log loss (positive = matchup better): -0.00354 [-0.00550, -0.00170].
Blend fit on 2021-2022: logit p = 0.018 + 0.856 logit(close) + 0.173 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3315 | -0.042 |
| 0.02 | 2478 | -0.037 |
| 0.03 | 1723 | -0.034 |
| 0.04 | 1168 | -0.004 |
| 0.05 | 754 | 0.050 |
| 0.06 | 423 | 0.016 |

Chosen tau: 0.05.
Test 2023-2025 at tau 0.05: 988 bets, ROI -0.046, week-block 95% [-0.126, 0.040].
2023: -0.032 on 371; 2024: -0.092 on 377; 2025: 0.006 on 240

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4253 games: open 0.6691, close 0.6686, model 0.6707.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3368 | 0.82 | [0.71, 0.92] | -0.031 |
| 0.02 | 2581 | 1.00 | [0.88, 1.12] | -0.024 |
| 0.03 | 1872 | 1.19 | [1.06, 1.33] | -0.016 |
| 0.04 | 1271 | 1.36 | [1.16, 1.53] | -0.007 |
| 0.05 | 840 | 1.56 | [1.34, 1.75] | 0.039 |
| 0.06 | 503 | 1.70 | [1.43, 1.94] | 0.016 |
Test 2023-2025 at tau 0.06 (chosen on 2021-2022 by CLV): 577 bets, mean CLV 2.45 points [2.16, 2.73], ROI at median open 0.013 [-0.077, 0.103].

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
