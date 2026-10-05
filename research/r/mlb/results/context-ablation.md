# Context features: ablation on validation seasons

Generated 2026-10-04 by research/r/mlb/context_features.R. Features for every 2016-2025 game are in data/mlb/matchup/context.rds;
the model below is fit and scored on 2016-2022 rows only (outcomes 2017-2022). Nothing was computed on 2023-2025.

Method: the matchup model's weekly walk-forward logistic (refit each Monday on every earlier game, predict that week),
base formula y ~ d12 + d3 + dpen + drd, then the base plus each context group alone and all groups together.
Paired difference = base log loss minus variant log loss per game (positive = the variant is better), with a
95% interval from 1000 cluster-bootstrap draws of home team-seasons.

## Reproducing the base

My base predictions match matchup_model.R's M3_plus_team on 13045 of 13045 games (max absolute difference 8.2e-15).
On the reference's own rows (12142 games with recency predictions, 2020 has none): reference 0.6705, mine 0.6705.
Over every non-tie game the pools below hold 12147 games excluding 2020 and 13045 including it.

## Features

| group | columns | definition |
| --- | --- | --- |
| defense | dder | Team BIP out rate allowed (homers out, reached-on-error not an out), park-neutralised by the site's 3 prior seasons, decayed h = 120 in-season days, carry 0.75, shrunk to the trailing-year league rate with 3000 BIP. Home minus away, in points. |
| umpire | ump_k, ump_bb, uk_x, ub_x | Plate umpire's as-of K and BB residual per PA against the matchup engine's expectation for each game he worked (so league, players and park are netted out), cumulative in season, carry 0.75, shrunk to zero with 3000 (K) and 5000 (BB) PA, in points. uk_x and ub_x multiply it by the home minus away expected K and BB counts. |
| weather | hr_temp, hr_wind, hr_dome | Home minus away expected homers (from features.rds) times temperature ((F - 72) / 10, zero under a roof), times wind out minus in (mph / 10, crosswinds zero), and times a closed-roof flag (Retrosheet sky = dome). |
| rest_travel | drest, dmoved, deast, dwest, ddgan | Home minus away: days since the previous game (capped at 3, 0 in a doubleheader nightcap), previous game at a different site, hours of time-zone change east and west from the previous site (48-site UTC table), day game after a night game the previous day. |
| dh_game2 | dh2 | Second game of a doubleheader. |
| pen_load | dload | Home minus away batters faced by relievers over the three previous days, in tens. Separate from the availability discount already inside dpen. |

Every shrink constant and window was set before scoring and never tuned on these outcomes.

## Log loss by season (lower is better)

| season | games | base | defense | umpire | weather | rest_travel | dh_game2 | pen_load | all |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2430 | 0.6760 | 0.6762 | 0.6771 | 0.6763 | 0.6771 | 0.6763 | 0.6761 | 0.6792 |
| 2018 |  2429 | 0.6715 | 0.6714 | 0.6716 | 0.6718 | 0.6714 | 0.6716 | 0.6715 | 0.6720 |
| 2019 |  2429 | 0.6633 | 0.6633 | 0.6634 | 0.6639 | 0.6636 | 0.6634 | 0.6634 | 0.6645 |
| 2020 |   898 | 0.6777 | 0.6772 | 0.6780 | 0.6782 | 0.6791 | 0.6779 | 0.6776 | 0.6797 |
| 2021 |  2429 | 0.6726 | 0.6720 | 0.6723 | 0.6726 | 0.6727 | 0.6725 | 0.6726 | 0.6721 |
| 2022 |  2430 | 0.6694 | 0.6686 | 0.6699 | 0.6691 | 0.6694 | 0.6695 | 0.6694 | 0.6689 |
| pooled excl. 2020 | 12147 | 0.6705 | 0.6703 | 0.6709 | 0.6707 | 0.6708 | 0.6707 | 0.6706 | 0.6713 |
| pooled 2017-2022 | 13045 | 0.6710 | 0.6708 | 0.6714 | 0.6712 | 0.6714 | 0.6712 | 0.6711 | 0.6719 |

## Paired difference against the base (positive = better), x 1000

| variant | 2017-2022 [95% CI] | excl. 2020 [95% CI] | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| defense | 0.231 [0.052, 0.429] | 0.213 [0.018, 0.402] | -0.242 | 0.055 | -0.039 | 0.480 | 0.511 | 0.780 | helps |
| umpire | -0.329 [-0.739, 0.075] | -0.331 [-0.744, 0.054] | -1.149 | -0.107 | -0.135 | -0.299 | 0.236 | -0.500 | no clear effect |
| weather | -0.206 [-0.591, 0.159] | -0.184 [-0.588, 0.236] | -0.266 | -0.321 | -0.569 | -0.511 | -0.072 | 0.309 | no clear effect |
| rest_travel | -0.365 [-0.668, -0.090] | -0.286 [-0.589, 0.023] | -1.072 | 0.036 | -0.262 | -1.424 | -0.125 | -0.008 | hurts |
| dh_game2 | -0.139 [-0.309, 0.017] | -0.134 [-0.321, 0.033] | -0.343 | -0.129 | -0.100 | -0.201 | 0.014 | -0.113 | no clear effect |
| pen_load | -0.063 [-0.141, 0.017] | -0.074 [-0.150, 0.010] | -0.088 | -0.061 | -0.113 | 0.089 | -0.072 | -0.038 | no clear effect |
| all | -0.874 [-1.512, -0.251] | -0.796 [-1.464, -0.096] | -3.221 | -0.501 | -1.199 | -1.935 | 0.496 | 0.447 | hurts |

Verdict rule: helps if the 2017-2022 interval sits above zero, hurts if below, otherwise no clear effect.

## All-groups model coefficients (fit on every 2016-2022 game; sign and size only)

| term | coef | z | coef x 1 sd |
| --- | --- | --- | --- |
| d12 | 0.6342 | 9.14 | 0.2270 |
| d3 | 0.1783 | 1.69 | 0.0579 |
| dpen | 0.3424 | 3.89 | 0.1484 |
| drd | 0.1018 | 3.53 | 0.1055 |
| dder | 0.0937 | 2.85 | 0.0595 |
| ump_k | -0.0054 | -0.13 | -0.0023 |
| ump_bb | 0.0189 | 0.22 | 0.0041 |
| uk_x | 0.0197 | 0.91 | 0.0180 |
| ub_x | 0.1845 | 1.77 | 0.0309 |
| hr_temp | 0.0258 | 0.39 | 0.0066 |
| hr_wind | 0.0499 | 0.51 | 0.0086 |
| hr_dome | -0.3002 | -1.66 | -0.0291 |
| drest | -0.0343 | -0.58 | -0.0099 |
| dmoved | -0.0169 | -0.35 | -0.0063 |
| deast | 0.0161 | 0.50 | 0.0087 |
| dwest | -0.0049 | -0.15 | -0.0026 |
| ddgan | 0.3905 | 1.53 | 0.0259 |
| dh2 | 0.0290 | 0.24 | 0.0040 |
| dload | -0.0045 | -0.46 | -0.0081 |

## Recommendation

Add: defense. Leave the other groups out.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
