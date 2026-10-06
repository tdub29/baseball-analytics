# Matchup model: validation

Generated 2026-10-05. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6764 | 0.6767 | 0.6763 | 0.6769 | 0.6766 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6756 |
| 2018 |  2429 | 0.6722 | 0.6726 | 0.6716 | 0.6718 | 0.6716 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6704 |
| 2019 |  2429 | 0.6669 | 0.6663 | 0.6632 | 0.6634 | 0.6632 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6638 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6756 | 0.6746 | 0.6724 | 0.6725 | 0.6719 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6715 |
| 2022 |  2429 | 0.6712 | 0.6710 | 0.6694 | 0.6694 | 0.6686 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6684 |
| pooled | 12142 | 0.6725 | 0.6722 | 0.6706 | 0.6708 | 0.6704 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6699 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.55.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6734 | 0.6729 | 0.6727 |
| 2022 | 2342 | 0.6668 | 0.6691 | 0.6699 | 0.6690 |

Close minus matchup per-game log loss (positive = matchup better): -0.00206 [-0.00415, 0.00010].
Blend fit on 2021-2022: logit p = 0.020 + 0.847 logit(close) + 0.166 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3234 | -0.044 |
| 0.02 | 2380 | -0.029 |
| 0.03 | 1638 | -0.018 |
| 0.04 | 1109 | 0.004 |
| 0.05 | 695 | 0.025 |
| 0.06 | 399 | 0.017 |

Chosen tau: 0.05.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6710.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3255 | 0.84 | [0.73, 0.95] | -0.026 |
| 0.02 | 2477 | 1.00 | [0.87, 1.13] | -0.024 |
| 0.03 | 1752 | 1.24 | [1.10, 1.37] | -0.014 |
| 0.04 | 1206 | 1.40 | [1.22, 1.56] | -0.007 |
| 0.05 | 783 | 1.58 | [1.37, 1.78] | 0.024 |
| 0.06 | 462 | 1.72 | [1.44, 1.97] | -0.003 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
