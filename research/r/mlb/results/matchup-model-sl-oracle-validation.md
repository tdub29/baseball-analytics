# Matchup model: validation

Generated 2026-10-09. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6768 | 0.6611 | 0.6611 | 0.6617 | 0.6614 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6613 |
| 2018 |  2429 | 0.6729 | 0.6611 | 0.6599 | 0.6601 | 0.6595 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6588 |
| 2019 |  2429 | 0.6679 | 0.6525 | 0.6493 | 0.6496 | 0.6494 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6495 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6760 | 0.6647 | 0.6628 | 0.6628 | 0.6622 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6618 |
| 2022 |  2429 | 0.6719 | 0.6646 | 0.6631 | 0.6630 | 0.6623 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6618 |
| pooled | 12142 | 0.6731 | 0.6608 | 0.6592 | 0.6595 | 0.6590 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6586 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.9.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1911 | 0.6707 | 0.6602 | 0.6723 | 0.6600 |
| 2022 | 2342 | 0.6668 | 0.6636 | 0.6699 | 0.6631 |

Close minus matchup per-game log loss (positive = matchup better): 0.00647 [0.00187, 0.01065].
Blend fit on 2021-2022: logit p = 0.014 + 0.316 logit(close) + 0.735 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3832 | 0.060 |
| 0.02 | 3404 | 0.070 |
| 0.03 | 3026 | 0.072 |
| 0.04 | 2666 | 0.079 |
| 0.05 | 2322 | 0.100 |
| 0.06 | 1981 | 0.120 |

Chosen tau: 0.06.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4253 games: open 0.6691, close 0.6686, model 0.6621.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3844 | 0.38 | [0.29, 0.46] | 0.059 |
| 0.02 | 3433 | 0.41 | [0.32, 0.49] | 0.075 |
| 0.03 | 3057 | 0.43 | [0.34, 0.52] | 0.086 |
| 0.04 | 2703 | 0.45 | [0.35, 0.56] | 0.102 |
| 0.05 | 2337 | 0.51 | [0.40, 0.61] | 0.101 |
| 0.06 | 1998 | 0.54 | [0.43, 0.66] | 0.128 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
