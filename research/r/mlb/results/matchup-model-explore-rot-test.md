# Matchup model: test

Generated 2026-10-05. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2023 | 2429 | 0.6813 | 0.6815 | 0.6798 | 0.6799 | 0.6797 | 0.6926 | 0.6815 | 0.6794 | 0.6824 | 0.6788 |
| 2024 | 2429 | 0.6803 | 0.6803 | 0.6782 | 0.6781 | 0.6787 | 0.6925 | 0.6799 | 0.6756 | 0.6826 | 0.6758 |
| 2025 | 2429 | 0.6801 | 0.6798 | 0.6773 | 0.6775 | 0.6768 | 0.6898 | 0.6777 | 0.6776 | 0.6831 | 0.6767 |
| pooled | 7287 | 0.6806 | 0.6806 | 0.6785 | 0.6785 | 0.6784 | 0.6916 | 0.6797 | 0.6775 | 0.6827 | 0.6771 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.3.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2023 | 2381 | 0.6767 | 0.6798 | 0.6796 | 0.6790 |
| 2024 | 2382 | 0.6702 | 0.6787 | 0.6755 | 0.6758 |
| 2025 | 1688 | 0.6768 | 0.6766 | 0.6775 | 0.6766 |

Close minus matchup per-game log loss (positive = matchup better): -0.00420 [-0.00638, -0.00201].
Blend fit on 2021-2022: logit p = 0.023 + 0.978 logit(close) + 0.022 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3416 | -0.049 |
| 0.02 | 2734 | -0.037 |
| 0.03 | 2106 | -0.029 |
| 0.04 | 1571 | -0.038 |
| 0.05 | 1170 | -0.036 |
| 0.06 | 835 | -0.007 |

Chosen tau: 0.06.
Test 2023-2025 at tau 0.06: 1201 bets, ROI -0.029, week-block 95% [-0.105, 0.044].
2023: -0.003 on 450; 2024: -0.122 on 445; 2025: 0.069 on 306

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6737.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3411 | 0.31 | [0.20, 0.41] | -0.036 |
| 0.02 | 2640 | 0.37 | [0.25, 0.49] | -0.044 |
| 0.03 | 1968 | 0.45 | [0.31, 0.59] | -0.049 |
| 0.04 | 1469 | 0.50 | [0.34, 0.65] | -0.030 |
| 0.05 | 1032 | 0.58 | [0.42, 0.75] | -0.044 |
| 0.06 | 699 | 0.67 | [0.50, 0.85] | -0.036 |
Test 2023-2025 at tau 0.06 (chosen on 2021-2022 by CLV): 955 bets, mean CLV 0.73 points [0.53, 0.94], ROI at median open -0.014 [-0.097, 0.059].

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
