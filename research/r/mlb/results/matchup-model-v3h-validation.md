# Matchup model: validation

Generated 2026-10-04. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6771 | 0.6773 | 0.6770 | 0.6776 | 0.6771 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6759 |
| 2018 |  2429 | 0.6715 | 0.6719 | 0.6707 | 0.6709 | 0.6707 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6699 |
| 2019 |  2429 | 0.6683 | 0.6679 | 0.6643 | 0.6646 | 0.6644 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6646 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6753 | 0.6743 | 0.6724 | 0.6725 | 0.6720 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6715 |
| 2022 |  2429 | 0.6735 | 0.6731 | 0.6711 | 0.6712 | 0.6706 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6694 |
| pooled | 12142 | 0.6732 | 0.6729 | 0.6711 | 0.6713 | 0.6710 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6703 |

Best matchup variant on these seasons: M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.5.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6737 | 0.6729 | 0.6729 |
| 2022 | 2342 | 0.6668 | 0.6712 | 0.6699 | 0.6701 |

Close minus matchup per-game log loss (positive = matchup better): -0.00339 [-0.00593, -0.00073].
Blend fit on 2021-2022: logit p = 0.023 + 0.987 logit(close) + 0.009 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3294 | -0.043 |
| 0.02 | 2482 | -0.040 |
| 0.03 | 1804 | -0.045 |
| 0.04 | 1244 | -0.042 |
| 0.05 | 831 | -0.028 |
| 0.06 | 541 | 0.027 |

Chosen tau: 0.06.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6723.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3296 | 0.82 | [0.73, 0.91] | -0.031 |
| 0.02 | 2577 | 0.94 | [0.82, 1.05] | -0.039 |
| 0.03 | 1937 | 1.03 | [0.89, 1.16] | -0.031 |
| 0.04 | 1349 | 1.16 | [0.97, 1.32] | -0.011 |
| 0.05 | 912 | 1.32 | [1.10, 1.51] | -0.008 |
| 0.06 | 578 | 1.50 | [1.25, 1.73] | -0.011 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
