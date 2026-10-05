# Matchup model: validation

Generated 2026-10-04. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6754 | 0.6760 | 0.6759 | 0.6765 | 0.6761 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6753 |
| 2018 |  2429 | 0.6730 | 0.6734 | 0.6720 | 0.6722 | 0.6720 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6704 |
| 2019 |  2429 | 0.6685 | 0.6683 | 0.6647 | 0.6649 | 0.6648 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6647 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6756 | 0.6749 | 0.6728 | 0.6728 | 0.6723 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6716 |
| 2022 |  2429 | 0.6729 | 0.6725 | 0.6707 | 0.6708 | 0.6702 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6690 |
| pooled | 12142 | 0.6731 | 0.6730 | 0.6712 | 0.6714 | 0.6711 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6702 |

Best matchup variant on these seasons: M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.45.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6737 | 0.6729 | 0.6727 |
| 2022 | 2342 | 0.6668 | 0.6708 | 0.6699 | 0.6697 |

Close minus matchup per-game log loss (positive = matchup better): -0.00309 [-0.00545, -0.00068].
Blend fit on 2021-2022: logit p = 0.022 + 0.935 logit(close) + 0.068 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3308 | -0.049 |
| 0.02 | 2544 | -0.033 |
| 0.03 | 1874 | -0.025 |
| 0.04 | 1276 | -0.023 |
| 0.05 | 832 | -0.011 |
| 0.06 | 541 | 0.009 |

Chosen tau: 0.06.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6720.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3301 | 0.63 | [0.54, 0.72] | -0.020 |
| 0.02 | 2508 | 0.72 | [0.60, 0.84] | -0.030 |
| 0.03 | 1817 | 0.86 | [0.70, 1.01] | -0.025 |
| 0.04 | 1256 | 0.94 | [0.78, 1.11] | -0.001 |
| 0.05 | 815 | 1.12 | [0.91, 1.33] | -0.022 |
| 0.06 | 518 | 1.25 | [1.01, 1.49] | -0.047 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
