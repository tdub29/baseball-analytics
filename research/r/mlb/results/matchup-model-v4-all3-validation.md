# Matchup model: validation

Generated 2026-10-06. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6761 | 0.6764 | 0.6762 | 0.6768 | 0.6764 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6756 |
| 2018 |  2429 | 0.6724 | 0.6728 | 0.6717 | 0.6719 | 0.6717 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6704 |
| 2019 |  2429 | 0.6667 | 0.6661 | 0.6631 | 0.6634 | 0.6632 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6638 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6756 | 0.6746 | 0.6725 | 0.6726 | 0.6720 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6715 |
| 2022 |  2429 | 0.6716 | 0.6714 | 0.6697 | 0.6697 | 0.6689 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6686 |
| pooled | 12142 | 0.6725 | 0.6723 | 0.6706 | 0.6709 | 0.6704 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6700 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.55.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6734 | 0.6729 | 0.6727 |
| 2022 | 2342 | 0.6668 | 0.6694 | 0.6699 | 0.6691 |

Close minus matchup per-game log loss (positive = matchup better): -0.00217 [-0.00427, 0.00006].
Blend fit on 2021-2022: logit p = 0.021 + 0.864 logit(close) + 0.147 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3240 | -0.043 |
| 0.02 | 2390 | -0.037 |
| 0.03 | 1650 | -0.037 |
| 0.04 | 1111 | 0.004 |
| 0.05 | 715 | 0.000 |
| 0.06 | 393 | 0.071 |

Chosen tau: 0.06.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6711.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3263 | 0.84 | [0.73, 0.94] | -0.031 |
| 0.02 | 2491 | 1.02 | [0.89, 1.14] | -0.020 |
| 0.03 | 1789 | 1.23 | [1.09, 1.37] | -0.015 |
| 0.04 | 1211 | 1.43 | [1.24, 1.61] | -0.008 |
| 0.05 | 785 | 1.54 | [1.33, 1.76] | 0.035 |
| 0.06 | 474 | 1.76 | [1.46, 2.04] | -0.019 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
