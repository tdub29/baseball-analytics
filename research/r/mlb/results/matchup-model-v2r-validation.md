# Matchup model: validation

Generated 2026-10-06. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6760 | 0.6763 | 0.6760 | 0.6766 | 0.6763 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6755 |
| 2018 |  2429 | 0.6720 | 0.6724 | 0.6715 | 0.6717 | 0.6714 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6703 |
| 2019 |  2429 | 0.6670 | 0.6664 | 0.6633 | 0.6636 | 0.6633 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6639 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6756 | 0.6746 | 0.6725 | 0.6726 | 0.6720 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6715 |
| 2022 |  2429 | 0.6712 | 0.6710 | 0.6694 | 0.6694 | 0.6686 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6684 |
| pooled | 12142 | 0.6723 | 0.6721 | 0.6705 | 0.6708 | 0.6703 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6699 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.55.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6734 | 0.6729 | 0.6727 |
| 2022 | 2342 | 0.6668 | 0.6692 | 0.6699 | 0.6690 |

Close minus matchup per-game log loss (positive = matchup better): -0.00207 [-0.00415, 0.00007].
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

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
