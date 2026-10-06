# Matchup model: test

Generated 2026-10-06. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2023 | 2429 | 0.6815 | 0.6819 | 0.6804 | 0.6804 | 0.6802 | 0.6926 | 0.6815 | 0.6794 | 0.6824 | 0.6793 |
| 2024 | 2429 | 0.6787 | 0.6782 | 0.6766 | 0.6764 | 0.6771 | 0.6925 | 0.6799 | 0.6756 | 0.6826 | 0.6758 |
| 2025 | 2429 | 0.6795 | 0.6792 | 0.6767 | 0.6769 | 0.6760 | 0.6898 | 0.6777 | 0.6776 | 0.6831 | 0.6763 |
| pooled | 7287 | 0.6799 | 0.6798 | 0.6779 | 0.6779 | 0.6778 | 0.6916 | 0.6797 | 0.6775 | 0.6827 | 0.6771 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.5.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2023 | 2381 | 0.6767 | 0.6805 | 0.6796 | 0.6795 |
| 2024 | 2382 | 0.6702 | 0.6770 | 0.6755 | 0.6757 |
| 2025 | 1812 | 0.6765 | 0.6763 | 0.6773 | 0.6763 |

Close minus matchup per-game log loss (positive = matchup better): -0.00374 [-0.00560, -0.00199].
Blend fit on 2021-2022: logit p = 0.017 + 0.852 logit(close) + 0.181 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3394 | -0.046 |
| 0.02 | 2568 | -0.032 |
| 0.03 | 1837 | -0.011 |
| 0.04 | 1270 | 0.005 |
| 0.05 | 832 | 0.011 |
| 0.06 | 510 | 0.055 |

Chosen tau: 0.06.
Test 2023-2025 at tau 0.06: 718 bets, ROI -0.031, week-block 95% [-0.126, 0.073].
2023: -0.022 on 274; 2024: -0.12 on 279; 2025: 0.106 on 165

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4253 games: open 0.6691, close 0.6686, model 0.6709.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3358 | 0.64 | [0.54, 0.72] | -0.020 |
| 0.02 | 2567 | 0.76 | [0.63, 0.88] | -0.014 |
| 0.03 | 1840 | 0.92 | [0.78, 1.07] | -0.013 |
| 0.04 | 1267 | 1.02 | [0.87, 1.19] | 0.007 |
| 0.05 | 798 | 1.21 | [1.03, 1.41] | 0.015 |
| 0.06 | 492 | 1.33 | [1.10, 1.57] | 0.010 |
Test 2023-2025 at tau 0.06 (chosen on 2021-2022 by CLV): 573 bets, mean CLV 2.01 points [1.67, 2.36], ROI at median open 0.046 [-0.052, 0.136].

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
