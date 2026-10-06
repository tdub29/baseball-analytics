# Matchup model: validation

Generated 2026-10-06. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6757 | 0.6760 | 0.6759 | 0.6765 | 0.6761 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6754 |
| 2018 |  2429 | 0.6722 | 0.6726 | 0.6715 | 0.6718 | 0.6715 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6704 |
| 2019 |  2429 | 0.6668 | 0.6662 | 0.6632 | 0.6635 | 0.6633 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6637 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6751 | 0.6742 | 0.6723 | 0.6723 | 0.6717 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6714 |
| 2022 |  2429 | 0.6711 | 0.6709 | 0.6694 | 0.6694 | 0.6686 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6684 |
| pooled | 12142 | 0.6722 | 0.6720 | 0.6705 | 0.6707 | 0.6702 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6698 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.6.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6731 | 0.6729 | 0.6725 |
| 2022 | 2342 | 0.6668 | 0.6691 | 0.6699 | 0.6690 |

Close minus matchup per-game log loss (positive = matchup better): -0.00192 [-0.00396, 0.00020].
Blend fit on 2021-2022: logit p = 0.020 + 0.826 logit(close) + 0.188 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3204 | -0.042 |
| 0.02 | 2393 | -0.034 |
| 0.03 | 1643 | -0.024 |
| 0.04 | 1106 | 0.004 |
| 0.05 | 701 | 0.045 |
| 0.06 | 377 | 0.049 |

Chosen tau: 0.06.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6708.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3253 | 0.85 | [0.74, 0.96] | -0.028 |
| 0.02 | 2503 | 1.03 | [0.90, 1.15] | -0.019 |
| 0.03 | 1811 | 1.22 | [1.07, 1.36] | -0.019 |
| 0.04 | 1238 | 1.44 | [1.24, 1.61] | 0.007 |
| 0.05 | 791 | 1.57 | [1.35, 1.78] | 0.035 |
| 0.06 | 464 | 1.75 | [1.45, 2.03] | 0.020 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
