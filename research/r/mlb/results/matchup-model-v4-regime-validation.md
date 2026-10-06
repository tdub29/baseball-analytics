# Matchup model: validation

Generated 2026-10-06. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6760 | 0.6763 | 0.6760 | 0.6766 | 0.6763 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6755 |
| 2018 |  2429 | 0.6720 | 0.6724 | 0.6715 | 0.6717 | 0.6714 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6703 |
| 2019 |  2429 | 0.6670 | 0.6664 | 0.6633 | 0.6636 | 0.6633 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6639 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6760 | 0.6750 | 0.6728 | 0.6729 | 0.6723 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6717 |
| 2022 |  2429 | 0.6715 | 0.6713 | 0.6696 | 0.6696 | 0.6688 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6685 |
| pooled | 12142 | 0.6725 | 0.6723 | 0.6706 | 0.6709 | 0.6704 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6700 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.55.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6737 | 0.6729 | 0.6728 |
| 2022 | 2342 | 0.6668 | 0.6694 | 0.6699 | 0.6692 |

Close minus matchup per-game log loss (positive = matchup better): -0.00229 [-0.00431, -0.00017].
Blend fit on 2021-2022: logit p = 0.021 + 0.877 logit(close) + 0.131 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3240 | -0.047 |
| 0.02 | 2412 | -0.044 |
| 0.03 | 1665 | -0.040 |
| 0.04 | 1126 | -0.008 |
| 0.05 | 727 | 0.045 |
| 0.06 | 409 | 0.024 |

Chosen tau: 0.05.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6712.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3272 | 0.85 | [0.74, 0.95] | -0.030 |
| 0.02 | 2515 | 1.03 | [0.89, 1.15] | -0.028 |
| 0.03 | 1817 | 1.19 | [1.05, 1.33] | -0.017 |
| 0.04 | 1248 | 1.42 | [1.23, 1.60] | -0.002 |
| 0.05 | 817 | 1.54 | [1.33, 1.74] | 0.030 |
| 0.06 | 479 | 1.71 | [1.42, 1.98] | -0.015 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
