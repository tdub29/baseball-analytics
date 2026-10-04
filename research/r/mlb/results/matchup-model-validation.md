# Matchup model: validation

Generated 2026-10-04. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6760 | 0.6763 | 0.6760 | 0.6766 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6754 |
| 2018 |  2429 | 0.6720 | 0.6724 | 0.6715 | 0.6717 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6704 |
| 2019 |  2429 | 0.6670 | 0.6664 | 0.6633 | 0.6636 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6638 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6756 | 0.6746 | 0.6725 | 0.6726 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6719 |
| 2022 |  2429 | 0.6712 | 0.6710 | 0.6694 | 0.6694 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6689 |
| pooled | 12142 | 0.6723 | 0.6721 | 0.6705 | 0.6708 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6701 |

Best matchup variant on these seasons: M3_plus_team.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.6.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6735 | 0.6729 | 0.6728 |
| 2022 | 2342 | 0.6668 | 0.6699 | 0.6699 | 0.6695 |

Close minus matchup per-game log loss (positive = matchup better): -0.00256 [-0.00463, -0.00034].
Blend fit on 2021-2022: logit p = 0.022 + 0.933 logit(close) + 0.070 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3217 | -0.040 |
| 0.02 | 2394 | -0.040 |
| 0.03 | 1652 | -0.035 |
| 0.04 | 1094 | -0.033 |
| 0.05 | 669 | 0.016 |
| 0.06 | 390 | 0.021 |

Chosen tau: 0.06.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
