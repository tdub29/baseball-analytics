# Matchup model: validation

Generated 2026-10-06. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6760 | 0.6763 | 0.6760 | 0.6766 | 0.6762 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6754 |
| 2018 |  2429 | 0.6720 | 0.6724 | 0.6715 | 0.6717 | 0.6714 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6703 |
| 2019 |  2429 | 0.6670 | 0.6664 | 0.6633 | 0.6636 | 0.6635 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6640 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6756 | 0.6746 | 0.6725 | 0.6726 | 0.6719 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6715 |
| 2022 |  2429 | 0.6712 | 0.6710 | 0.6694 | 0.6694 | 0.6687 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6684 |
| pooled | 12142 | 0.6723 | 0.6721 | 0.6705 | 0.6708 | 0.6703 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6699 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

RECAL=1: M5_plus_defense recalibrated as logit p' = 0.010 + 0.978 logit p, fit on its 2017-2020 walk-forward predictions (in sample there).

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.55.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6733 | 0.6729 | 0.6726 |
| 2022 | 2342 | 0.6668 | 0.6692 | 0.6699 | 0.6691 |

Close minus matchup per-game log loss (positive = matchup better): -0.00203 [-0.00410, 0.00011].
Blend fit on 2021-2022: logit p = 0.018 + 0.847 logit(close) + 0.169 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3234 | -0.046 |
| 0.02 | 2391 | -0.038 |
| 0.03 | 1674 | -0.035 |
| 0.04 | 1111 | 0.013 |
| 0.05 | 700 | 0.059 |
| 0.06 | 396 | 0.035 |

Chosen tau: 0.05.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6710.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3254 | 0.86 | [0.76, 0.96] | -0.037 |
| 0.02 | 2494 | 1.02 | [0.88, 1.15] | -0.025 |
| 0.03 | 1810 | 1.21 | [1.07, 1.34] | -0.015 |
| 0.04 | 1213 | 1.38 | [1.17, 1.57] | 0.003 |
| 0.05 | 806 | 1.53 | [1.30, 1.73] | 0.054 |
| 0.06 | 479 | 1.70 | [1.42, 1.96] | 0.024 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
