# Matchup model: test

Generated 2026-10-05. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2023 | 2429 | 0.6816 | 0.6819 | 0.6800 | 0.6801 | 0.6799 | 0.6926 | 0.6814 | 0.6794 | 0.6824 | 0.6788 |
| 2024 | 2429 | 0.6810 | 0.6811 | 0.6784 | 0.6783 | 0.6789 | 0.6925 | 0.6796 | 0.6756 | 0.6826 | 0.6759 |
| 2025 | 2428 | 0.6809 | 0.6807 | 0.6778 | 0.6780 | 0.6772 | 0.6897 | 0.6780 | 0.6775 | 0.6830 | 0.6768 |
| pooled | 7286 | 0.6812 | 0.6812 | 0.6787 | 0.6788 | 0.6787 | 0.6916 | 0.6797 | 0.6775 | 0.6827 | 0.6772 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.3.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2023 | 2381 | 0.6767 | 0.6800 | 0.6796 | 0.6790 |
| 2024 | 2382 | 0.6702 | 0.6789 | 0.6755 | 0.6759 |
| 2025 | 1688 | 0.6768 | 0.6768 | 0.6775 | 0.6766 |

Close minus matchup per-game log loss (positive = matchup better): -0.00439 [-0.00657, -0.00228].
Blend fit on 2021-2022: logit p = 0.022 + 0.949 logit(close) + 0.059 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3439 | -0.043 |
| 0.02 | 2752 | -0.048 |
| 0.03 | 2140 | -0.028 |
| 0.04 | 1638 | -0.016 |
| 0.05 | 1205 | -0.023 |
| 0.06 | 848 | 0.001 |

Chosen tau: 0.06.
Test 2023-2025 at tau 0.06: 1210 bets, ROI -0.054, week-block 95% [-0.126, 0.017].
2023: -0.025 on 454; 2024: -0.135 on 445; 2025: 0.021 on 311

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6736.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3369 | 0.25 | [0.15, 0.36] | -0.025 |
| 0.02 | 2621 | 0.31 | [0.19, 0.42] | -0.042 |
| 0.03 | 1987 | 0.35 | [0.21, 0.49] | -0.036 |
| 0.04 | 1504 | 0.46 | [0.32, 0.59] | -0.030 |
| 0.05 | 1048 | 0.53 | [0.36, 0.68] | -0.057 |
| 0.06 | 713 | 0.71 | [0.53, 0.89] | -0.052 |
Test 2023-2025 at tau 0.06 (chosen on 2021-2022 by CLV): 975 bets, mean CLV 0.81 points [0.60, 1.02], ROI at median open 0.004 [-0.071, 0.079].

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
