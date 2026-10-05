# Totals study: validation

Generated 2026-10-04 by `Rscript research/r/mlb/totals_study.R validation`. Charter: TOTALS-PLAN.md. features.rds md5 67b60417d85f10baa823bc4f5ca9922f.
Validation only: no 2023-2025 row was read (features, Retrosheet and odds were filtered to 2022 and earlier first).

## Data

- Games 2016-2022 after dropping 42 that ended before their scheduled innings (2016: 7, 2017: 2, 2018: 5, 2019: 10, 2020: 1, 2021: 7, 2022: 10).
- Odds file starts 2021-04-01 (not 2021-03-20). 4237 matched games in 2021-2022 outside the excluded window, 96.4% of the 4397 Retrosheet games from the first odds date; 0 dropped as ambiguous (same teams, day and score). 422 more in 2021-09-01..2021-12-31 excluded.
- Market rows scored: 4237 games, 178 pushes (4.2%), 46.1% of lines whole numbers; books per game 5.0, at the main line 4.1; median closing overround 1.047.
- Temperature missing or implausible outdoors, set to 72: 0 games. Run values (2015-2016 team-games): intercept -1.903, k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Calibration of total runs vs outcomes (no market)

Walk-forward weekly, 2017-2022. Mean predicted total and log score of the actual total (higher is better).

| season | games | actual | mean_T1 | mean_T2 | mean_T3 | mean_B | logscore_T1 | logscore_T2 | logscore_T3 | logscore_B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 | 2428 | 9.2928 | 9.2109 | 9.2328 | 9.2050 | 9.0934 | -2.8637 | -2.8640 | -2.8667 | -2.8782 |
| 2018 | 2424 | 8.8977 | 9.1569 | 9.1797 | 9.1639 | 9.0773 | -2.8682 | -2.8683 | -2.8702 | -2.8798 |
| 2019 | 2419 | 9.6726 | 9.3104 | 9.3263 | 9.3051 | 9.2039 | -2.9122 | -2.9116 | -2.9150 | -2.9332 |
| 2020 | 897 | 9.2965 | 9.3865 | 9.4170 | 9.3296 | 9.1388 | -2.8604 | -2.8615 | -2.8673 | -2.8753 |
| 2021 | 2422 | 9.0636 | 9.0096 | 8.9960 | 8.9899 | 9.1931 | -2.8450 | -2.8449 | -2.8510 | -2.8673 |
| 2022 | 2420 | 8.5682 | 8.9847 | 8.9730 | 8.9919 | 9.0645 | -2.8202 | -2.8202 | -2.8264 | -2.8395 |
| pooled | 13010 | 9.1126 | 9.1519 | 9.1606 | 9.1449 | 9.1273 | -2.8618 | -2.8618 | -2.8659 | -2.8793 |

Selected candidate (lowest 2021-2022 over/under log loss): **T2**. Deciles of its predicted mean, pooled:

| decile | games | pred_mean | actual_mean | pred_over85 | obs_over85 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1301 | 7.5085 | 7.7248 | 0.3529 | 0.3728 |
| 2 | 1301 | 8.1544 | 8.3828 | 0.4160 | 0.4404 |
| 3 | 1301 | 8.4884 | 8.4266 | 0.4476 | 0.4458 |
| 4 | 1301 | 8.7640 | 8.6841 | 0.4730 | 0.5027 |
| 5 | 1301 | 9.0092 | 8.7725 | 0.4950 | 0.4835 |
| 6 | 1301 | 9.2452 | 9.3305 | 0.5157 | 0.5327 |
| 7 | 1301 | 9.4957 | 9.2836 | 0.5370 | 0.5419 |
| 8 | 1301 | 9.7796 | 9.5296 | 0.5602 | 0.5496 |
| 9 | 1301 | 10.1512 | 10.1199 | 0.5894 | 0.5957 |
| 10 | 1301 | 11.0096 | 10.8716 | 0.6497 | 0.6495 |

Variance, predicted vs observed squared error: T1 20.25 vs 20.06; T2 20.34 vs 20.07; T3 20.39 vs 20.24; B 20.83 vs 20.80.

Last weekly fit, T1: (Intercept) -0.7187, lxr 1.3097, temp_c 0.0049, wind_out 0.0044, wind_in -0.0018, dome 0.0125, ump_k 0.0182, ump_bb 0.0835; theta 7.68.
Last weekly fit, T2 (per side): (Intercept) -0.8225, lxr 1.5128, home 0.0155, temp_c 0.0048, wind_out 0.0045, wind_in -0.0017, dome 0.0208, ump_k 0.0185, ump_bb 0.0835; theta 3.76.

## Market sanity by month, 2021-2022

Closing (current) line vs opening line, overround and no-vig closing log loss on non-push games. In-game scrapes show as big moves and low log loss.

| month | games | abs_move | moved_15 | overround | push_rate | market_ll | excluded |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2021-04 | 367 | 0.2909 | 0.0082 | 1.0474 | 0.0409 | 0.6934 | FALSE |
| 2021-05 | 399 | 0.2632 | 0.0000 | 1.0474 | 0.0251 | 0.6927 | FALSE |
| 2021-06 | 386 | 0.3251 | 0.0026 | 1.0475 | 0.0440 | 0.6903 | FALSE |
| 2021-07 | 348 | 0.2787 | 0.0029 | 1.0472 | 0.0460 | 0.6929 | FALSE |
| 2021-08 | 405 | 0.2420 | 0.0025 | 1.0469 | 0.0519 | 0.6939 | FALSE |
| 2021-09 | 378 | 0.4464 | 0.0635 | 1.0483 | 0.0503 | 0.6897 | TRUE |
| 2021-10 | 44 | 0.5114 | 0.0909 | 1.0482 | 0.0909 | 0.6888 | TRUE |
| 2022-04 | 311 | 0.3223 | 0.0096 | 1.0478 | 0.0354 | 0.6907 | FALSE |
| 2022-05 | 392 | 0.2915 | 0.0051 | 1.0477 | 0.0459 | 0.6907 | FALSE |
| 2022-06 | 392 | 0.3278 | 0.0077 | 1.0480 | 0.0383 | 0.6922 | FALSE |
| 2022-07 | 379 | 0.2803 | 0.0106 | 1.0479 | 0.0369 | 0.6921 | FALSE |
| 2022-08 | 410 | 0.2860 | 0.0073 | 1.0489 | 0.0610 | 0.6909 | FALSE |
| 2022-09 | 380 | 0.2520 | 0.0026 | 1.0485 | 0.0342 | 0.6919 | FALSE |
| 2022-10 | 68 | 0.2390 | 0.0000 | 1.0493 | 0.0441 | 0.6894 | FALSE |

## Over/under log loss vs the no-vig close, 2021-2022 (in-sample: the candidate, blend and tau were chosen here)

Pushes excluded. Lower is better.

| season | games | market | T1 | T2 | T3 | B |
| --- | --- | --- | --- | --- | --- | --- |
| 2021 | 1826 | 0.6927 | 0.6896 | 0.6894 | 0.6961 | 0.7049 |
| 2022 | 2233 | 0.6914 | 0.6985 | 0.6983 | 0.7029 | 0.7117 |
| pooled | 4059 | 0.6919 | 0.6945 | 0.6943 | 0.6998 | 0.7087 |

Market minus T2, per game (positive = model better): -0.00231 [-0.00593, 0.00126], home-team-season cluster bootstrap 95%.
Over rate on non-push games: actual 0.4876, market mean 0.5002, T2 mean 0.5050. Model mean total minus line 0.614 runs (a right-skewed count's mean sits above the median the line targets, so this alone is not bias); correlation of model mean with the line 0.758.

Blend fit on 2021-2022: logit p = -0.059 + 1.798 logit(market) + 0.380 logit(T2). Gain over the market alone on 2021-2022: 0.00202 [0.00060, 0.00357].

## Betting at the median closing price

Every threshold on 2021-2022 (T2, one unit per bet, pushes refund):

| tau | bets | overs | pushes | wins | units | roi |
| --- | --- | --- | --- | --- | --- | --- |
| 0.010 | 3725 | 2006 | 160 | 1860 | -20.042 | -0.005 |
| 0.020 | 3246 | 1766 | 139 | 1626 | -6.976 | -0.002 |
| 0.030 | 2729 | 1486 | 114 | 1348 | -45.216 | -0.017 |
| 0.040 | 2253 | 1232 | 96 | 1126 | -10.574 | -0.005 |
| 0.050 | 1827 | 1029 | 76 | 922 | 5.976 | 0.003 |
| 0.060 | 1459 | 828 | 63 | 743 | 21.168 | 0.015 |
| 0.080 | 907 | 519 | 38 | 463 | 14.105 | 0.016 |
| 0.100 | 494 | 273 | 22 | 257 | 18.406 | 0.037 |

Chosen tau 0.1. On 2021-2022: 494 bets, 22 pushes, 18.4 units, ROI 0.037, week-block 95% [-0.037, 0.113].

| season | bets | pushes | units | roi |
| --- | --- | --- | --- | --- |
| 2021 | 171 | 9 | 21.730 | 0.127 |
| 2022 | 323 | 13 | -3.324 | -0.010 |

## Decision rules applied to 2021-2022 (code-path check only; the real verdict is the test)

- Forecast: does not beat the closing total.
- Information: adds information to the close.
- Betting: not profitable.

Private research on scraped odds; not betting advice.
The information used here was obtained free of charge from and is copyrighted by Retrosheet.
