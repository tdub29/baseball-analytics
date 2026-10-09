# Matchup model: test

Generated 2026-10-07. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2023 | 2429 | 0.6815 | 0.6818 | 0.6803 | 0.6803 | 0.6801 | 0.6926 | 0.6815 | 0.6794 | 0.6824 | 0.6792 |
| 2024 | 2429 | 0.6787 | 0.6781 | 0.6766 | 0.6764 | 0.6771 | 0.6925 | 0.6799 | 0.6756 | 0.6826 | 0.6759 |
| 2025 | 2429 | 0.6794 | 0.6790 | 0.6765 | 0.6767 | 0.6759 | 0.6898 | 0.6777 | 0.6776 | 0.6831 | 0.6762 |
| pooled | 7287 | 0.6798 | 0.6796 | 0.6778 | 0.6778 | 0.6777 | 0.6916 | 0.6797 | 0.6775 | 0.6827 | 0.6771 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.55.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2023 | 2381 | 0.6767 | 0.6804 | 0.6796 | 0.6795 |
| 2024 | 2382 | 0.6702 | 0.6770 | 0.6755 | 0.6758 |
| 2025 | 1812 | 0.6765 | 0.6762 | 0.6773 | 0.6763 |

Close minus matchup per-game log loss (positive = matchup better): -0.00368 [-0.00556, -0.00194].
Blend fit on 2021-2022: logit p = 0.017 + 0.865 logit(close) + 0.168 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3385 | -0.050 |
| 0.02 | 2564 | -0.033 |
| 0.03 | 1831 | -0.008 |
| 0.04 | 1259 | -0.002 |
| 0.05 | 831 | 0.013 |
| 0.06 | 504 | 0.074 |

Chosen tau: 0.06.
Test 2023-2025 at tau 0.06: 718 bets, ROI -0.027, week-block 95% [-0.119, 0.078].
2023: -0.016 on 274; 2024: -0.124 on 280; 2025: 0.118 on 164

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4253 games: open 0.6691, close 0.6686, model 0.6710.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3364 | 0.64 | [0.54, 0.73] | -0.024 |
| 0.02 | 2559 | 0.75 | [0.62, 0.87] | -0.018 |
| 0.03 | 1837 | 0.90 | [0.76, 1.05] | -0.008 |
| 0.04 | 1261 | 1.03 | [0.87, 1.19] | -0.000 |
| 0.05 | 796 | 1.23 | [1.03, 1.43] | 0.031 |
| 0.06 | 490 | 1.36 | [1.13, 1.61] | -0.009 |
Test 2023-2025 at tau 0.06 (chosen on 2021-2022 by CLV): 558 bets, mean CLV 1.97 points [1.62, 2.30], ROI at median open 0.044 [-0.056, 0.136].

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
