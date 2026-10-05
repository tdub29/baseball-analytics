# Matchup model: validation

Generated 2026-10-04. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6750 | 0.6755 | 0.6755 | 0.6761 | 0.6757 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6751 |
| 2018 |  2429 | 0.6736 | 0.6741 | 0.6728 | 0.6730 | 0.6728 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6708 |
| 2019 |  2429 | 0.6670 | 0.6667 | 0.6635 | 0.6638 | 0.6636 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6640 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6760 | 0.6754 | 0.6729 | 0.6730 | 0.6725 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6717 |
| 2022 |  2429 | 0.6716 | 0.6715 | 0.6697 | 0.6698 | 0.6690 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6685 |
| pooled | 12142 | 0.6727 | 0.6726 | 0.6709 | 0.6711 | 0.6707 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6700 |

Best matchup variant on these seasons: M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.5.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6737 | 0.6729 | 0.6727 |
| 2022 | 2342 | 0.6668 | 0.6695 | 0.6699 | 0.6692 |

Close minus matchup per-game log loss (positive = matchup better): -0.00239 [-0.00459, -0.00027].
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

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
