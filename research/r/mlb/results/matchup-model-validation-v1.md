# Matchup model: validation

Generated 2026-10-04. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | B_home | C_team_only | E_recency | C_incumbent |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6780 | 0.6784 | 0.6780 | 0.6787 | 0.6902 | 0.6822 | 0.6759 | 0.6836 |
| 2018 |  2429 | 0.6714 | 0.6718 | 0.6709 | 0.6710 | 0.6918 | 0.6736 | 0.6705 | 0.6751 |
| 2019 |  2429 | 0.6683 | 0.6680 | 0.6648 | 0.6650 | 0.6915 | 0.6660 | 0.6657 | 0.6707 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6763 | 0.6758 | 0.6738 | 0.6739 | 0.6902 | 0.6761 | 0.6720 | 0.6777 |
| 2022 |  2429 | 0.6696 | 0.6695 | 0.6688 | 0.6688 | 0.6910 | 0.6738 | 0.6691 | 0.6757 |
| pooled | 12142 | 0.6727 | 0.6727 | 0.6713 | 0.6715 | 0.6909 | 0.6743 | 0.6706 | 0.6766 |

Best matchup variant on these seasons: M3_plus_team.

## Against the no-vig closing line (games with odds)

| season | games | close | matchup | recency E |
| --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6749 | 0.6729 |
| 2022 | 2342 | 0.6668 | 0.6695 | 0.6699 |

Close minus matchup per-game log loss (positive = matchup better): -0.00292 [-0.00511, -0.00073].
Blend fit on 2021-2022: logit p = 0.023 + 0.979 logit(close) + 0.020 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3275 | -0.042 |
| 0.02 | 2436 | -0.037 |
| 0.03 | 1703 | -0.034 |
| 0.04 | 1132 | -0.058 |
| 0.05 | 714 | -0.021 |
| 0.06 | 414 | -0.021 |

Chosen tau: 0.05.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
