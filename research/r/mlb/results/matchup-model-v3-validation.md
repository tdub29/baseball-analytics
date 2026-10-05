# Matchup model: validation

Generated 2026-10-04. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6764 | 0.6766 | 0.6764 | 0.6770 | 0.6766 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6756 |
| 2018 |  2429 | 0.6713 | 0.6716 | 0.6706 | 0.6708 | 0.6706 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6698 |
| 2019 |  2429 | 0.6685 | 0.6681 | 0.6646 | 0.6649 | 0.6647 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6647 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6755 | 0.6745 | 0.6725 | 0.6726 | 0.6721 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6716 |
| 2022 |  2429 | 0.6726 | 0.6722 | 0.6706 | 0.6706 | 0.6700 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6691 |
| pooled | 12142 | 0.6729 | 0.6726 | 0.6709 | 0.6712 | 0.6708 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6702 |

Best matchup variant on these seasons: M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.5.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6736 | 0.6729 | 0.6728 |
| 2022 | 2342 | 0.6668 | 0.6706 | 0.6699 | 0.6698 |

Close minus matchup per-game log loss (positive = matchup better): -0.00301 [-0.00536, -0.00059].
Blend fit on 2021-2022: logit p = 0.023 + 0.959 logit(close) + 0.041 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3234 | -0.046 |
| 0.02 | 2441 | -0.051 |
| 0.03 | 1726 | -0.053 |
| 0.04 | 1203 | -0.012 |
| 0.05 | 791 | -0.001 |
| 0.06 | 473 | 0.034 |

Chosen tau: 0.06.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6719.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3278 | 0.82 | [0.72, 0.93] | -0.031 |
| 0.02 | 2526 | 0.97 | [0.84, 1.08] | -0.025 |
| 0.03 | 1838 | 1.06 | [0.91, 1.21] | -0.024 |
| 0.04 | 1303 | 1.18 | [1.00, 1.35] | -0.006 |
| 0.05 | 859 | 1.36 | [1.14, 1.58] | 0.007 |
| 0.06 | 525 | 1.54 | [1.28, 1.80] | -0.015 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
