# Matchup model: validation

Generated 2026-10-09. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6760 | 0.6763 | 0.6762 | 0.6768 | 0.6764 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6756 |
| 2018 |  2429 | 0.6720 | 0.6718 | 0.6707 | 0.6709 | 0.6707 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6699 |
| 2019 |  2429 | 0.6671 | 0.6662 | 0.6633 | 0.6635 | 0.6633 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6637 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6758 | 0.6743 | 0.6723 | 0.6724 | 0.6718 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6714 |
| 2022 |  2429 | 0.6710 | 0.6701 | 0.6686 | 0.6686 | 0.6678 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6679 |
| pooled | 12142 | 0.6724 | 0.6718 | 0.6702 | 0.6704 | 0.6700 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6697 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.6.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1911 | 0.6707 | 0.6723 | 0.6723 | 0.6718 |
| 2022 | 2342 | 0.6668 | 0.6684 | 0.6699 | 0.6685 |

Close minus matchup per-game log loss (positive = matchup better): -0.00156 [-0.00334, 0.00028].
Blend fit on 2021-2022: logit p = 0.015 + 0.763 logit(close) + 0.276 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3322 | -0.039 |
| 0.02 | 2484 | -0.017 |
| 0.03 | 1789 | -0.036 |
| 0.04 | 1207 | -0.014 |
| 0.05 | 743 | 0.061 |
| 0.06 | 445 | 0.058 |

Chosen tau: 0.05.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4253 games: open 0.6691, close 0.6686, model 0.6701.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3345 | 0.83 | [0.71, 0.94] | -0.022 |
| 0.02 | 2585 | 1.01 | [0.89, 1.13] | -0.018 |
| 0.03 | 1880 | 1.17 | [1.03, 1.31] | -0.012 |
| 0.04 | 1274 | 1.35 | [1.19, 1.49] | 0.017 |
| 0.05 | 834 | 1.51 | [1.33, 1.68] | 0.041 |
| 0.06 | 498 | 1.70 | [1.47, 1.91] | 0.045 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
