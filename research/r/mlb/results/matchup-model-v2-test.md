# Matchup model: test

Generated 2026-10-04. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

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
| 2025 | 1688 | 0.6768 | 0.6768 | 0.6775 | 0.6767 |

Close minus matchup per-game log loss (positive = matchup better): -0.00356 [-0.00543, -0.00164].
Blend fit on 2021-2022: logit p = 0.020 + 0.847 logit(close) + 0.166 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3215 | -0.045 |
| 0.02 | 2399 | -0.040 |
| 0.03 | 1661 | -0.034 |
| 0.04 | 1115 | -0.001 |
| 0.05 | 715 | 0.059 |
| 0.06 | 395 | 0.024 |

Chosen tau: 0.05.
Test 2023-2025 at tau 0.05: 965 bets, ROI -0.044, week-block 95% [-0.126, 0.042].
2023: -0.032 on 371; 2024: -0.092 on 377; 2025: 0.019 on 217

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6710.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3263 | 0.84 | [0.73, 0.94] | -0.031 |
| 0.02 | 2499 | 1.02 | [0.88, 1.14] | -0.026 |
| 0.03 | 1805 | 1.21 | [1.07, 1.35] | -0.019 |
| 0.04 | 1223 | 1.38 | [1.17, 1.56] | -0.008 |
| 0.05 | 806 | 1.57 | [1.35, 1.77] | 0.043 |
| 0.06 | 478 | 1.70 | [1.43, 1.96] | 0.018 |
Test 2023-2025 at tau 0.06 (chosen on 2021-2022 by CLV): 561 bets, mean CLV 2.44 points [2.15, 2.71], ROI at median open 0.018 [-0.076, 0.109].

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
