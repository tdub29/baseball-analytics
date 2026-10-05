# Matchup model: test

Generated 2026-10-04. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

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
| 2025 | 1688 | 0.6768 | 0.6765 | 0.6775 | 0.6765 |

Close minus matchup per-game log loss (positive = matchup better): -0.00383 [-0.00548, -0.00204].
Blend fit on 2021-2022: logit p = 0.020 + 0.857 logit(close) + 0.157 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3291 | -0.049 |
| 0.02 | 2481 | -0.037 |
| 0.03 | 1770 | -0.013 |
| 0.04 | 1217 | 0.003 |
| 0.05 | 799 | 0.016 |
| 0.06 | 487 | 0.065 |

Chosen tau: 0.06.
Test 2023-2025 at tau 0.06: 704 bets, ROI -0.033, week-block 95% [-0.128, 0.073].
2023: -0.022 on 274; 2024: -0.12 on 279; 2025: 0.109 on 151

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6713.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3256 | 0.65 | [0.55, 0.75] | -0.023 |
| 0.02 | 2478 | 0.77 | [0.64, 0.90] | -0.015 |
| 0.03 | 1773 | 0.94 | [0.78, 1.08] | -0.012 |
| 0.04 | 1213 | 1.05 | [0.88, 1.22] | 0.007 |
| 0.05 | 764 | 1.25 | [1.05, 1.45] | 0.016 |
| 0.06 | 468 | 1.37 | [1.14, 1.59] | 0.012 |
Test 2023-2025 at tau 0.06 (chosen on 2021-2022 by CLV): 561 bets, mean CLV 2.01 points [1.67, 2.35], ROI at median open 0.047 [-0.050, 0.137].

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
