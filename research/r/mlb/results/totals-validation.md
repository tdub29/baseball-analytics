# Totals study: validation

Generated 2026-10-05 by `Rscript research/r/mlb/totals_study.R validation`. Charter: TOTALS-PLAN.md. features.rds md5 67b60417d85f10baa823bc4f5ca9922f.
Validation only: no 2023-2025 row was read (features, Retrosheet and odds were filtered to 2022 and earlier first).

## Data

- Games 2016-2022 after dropping 42 that ended before their scheduled innings (2016: 7, 2017: 2, 2018: 5, 2019: 10, 2020: 1, 2021: 7, 2022: 10).
- Odds file starts 2021-04-01 (not 2021-03-20). 4237 matched games in 2021-2022 outside the excluded window, 96.4% of the 4397 Retrosheet games from the first odds date; 0 dropped as ambiguous (same teams, day and score). 422 more in 2021-09-01..2021-12-31 excluded.
- Market rows scored: 4237 games, 178 pushes (4.2%), 46.1% of lines whole numbers; books per game 5.0, at the main line 4.1; median closing overround 1.047.
- Temperature missing or implausible outdoors, set to 72: 0 games. Run values (2015-2016 team-games): intercept -1.903, k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.
- Run environment (it 3, chosen on 2017-2020 by `totals_study.R tune`, results/totals-tune.md): fit weights half-life 365 days; as-of league runs per nine innings as a predictor, half-life 15 days.

## Calibration of total runs vs outcomes (no market)

Walk-forward weekly, 2017-2022. Mean predicted total and log score of the actual total (higher is better).

| season | games | actual | mean_T1 | mean_T2 | mean_T3 | mean_B | logscore_T1 | logscore_T2 | logscore_T3 | logscore_B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 | 2428 | 9.2928 | 9.2707 | 9.2856 | 9.3123 | 9.0934 | -2.8639 | -2.8642 | -2.8663 | -2.8782 |
| 2018 | 2424 | 8.8977 | 9.1273 | 9.1530 | 9.1023 | 9.0773 | -2.8681 | -2.8682 | -2.8697 | -2.8798 |
| 2019 | 2419 | 9.6726 | 9.4494 | 9.4616 | 9.4887 | 9.2039 | -2.9117 | -2.9111 | -2.9137 | -2.9332 |
| 2020 | 897 | 9.2965 | 9.4111 | 9.4427 | 9.3620 | 9.1388 | -2.8593 | -2.8604 | -2.8661 | -2.8753 |
| 2021 | 2422 | 9.0636 | 8.9769 | 8.9640 | 8.9464 | 9.1931 | -2.8454 | -2.8452 | -2.8512 | -2.8673 |
| 2022 | 2420 | 8.5682 | 8.8906 | 8.8829 | 8.8057 | 9.0645 | -2.8195 | -2.8196 | -2.8243 | -2.8395 |
| pooled | 13010 | 9.1126 | 9.1615 | 9.1697 | 9.1470 | 9.1273 | -2.8615 | -2.8616 | -2.8651 | -2.8793 |

Selected candidate (lowest 2021-2022 over/under log loss): **T2**. Deciles of its predicted mean, pooled:

| decile | games | pred_mean | actual_mean | pred_over85 | obs_over85 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1301 | 7.4910 | 7.7602 | 0.3511 | 0.3743 |
| 2 | 1301 | 8.1476 | 8.2575 | 0.4154 | 0.4312 |
| 3 | 1301 | 8.4839 | 8.5657 | 0.4472 | 0.4543 |
| 4 | 1301 | 8.7654 | 8.5742 | 0.4732 | 0.4896 |
| 5 | 1301 | 9.0189 | 8.9085 | 0.4959 | 0.5004 |
| 6 | 1301 | 9.2550 | 9.1507 | 0.5165 | 0.5288 |
| 7 | 1301 | 9.5109 | 9.4573 | 0.5383 | 0.5488 |
| 8 | 1301 | 9.7986 | 9.4450 | 0.5618 | 0.5396 |
| 9 | 1301 | 10.1757 | 10.0953 | 0.5914 | 0.5972 |
| 10 | 1301 | 11.0497 | 10.9116 | 0.6524 | 0.6503 |

Variance, predicted vs observed squared error: T1 20.27 vs 20.06; T2 20.37 vs 20.06; T3 20.37 vs 20.21; B 20.83 vs 20.80.

Last weekly fit, T1: (Intercept) -0.6803, lxr 1.2947, temp_c 0.0046, wind_out 0.0043, wind_in -0.0017, dome 0.0119, ump_k 0.0146, ump_bb 0.0794, lenv 0.3390; theta 7.70.
Last weekly fit, T2 (per side): (Intercept) -0.8082, lxr 1.5067, home 0.0154, temp_c 0.0045, wind_out 0.0044, wind_in -0.0016, dome 0.0205, ump_k 0.0149, ump_bb 0.0794, lenv 0.3323; theta 3.77.

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
| 2021 | 1826 | 0.6927 | 0.6902 | 0.6899 | 0.6965 | 0.7049 |
| 2022 | 2233 | 0.6914 | 0.6980 | 0.6978 | 0.7013 | 0.7117 |
| pooled | 4059 | 0.6919 | 0.6945 | 0.6943 | 0.6991 | 0.7087 |

Market minus T2, per game (positive = model better): -0.00232 [-0.00553, 0.00088], home-team-season cluster bootstrap 95%.
Over rate on non-push games: actual 0.4876, market mean 0.5002, T2 mean 0.4989. Model mean total minus line 0.546 runs (a right-skewed count's mean sits above the median the line targets, so this alone is not bias); correlation of model mean with the line 0.772.

Blend fit on 2021-2022: logit p = -0.050 + 1.831 logit(market) + 0.351 logit(T2). Gain over the market alone on 2021-2022: 0.00179 [0.00049, 0.00321].

## Betting at the median closing price

Every threshold on 2021-2022 (T2, one unit per bet, pushes refund):

| tau | bets | overs | pushes | wins | units | roi |
| --- | --- | --- | --- | --- | --- | --- |
| 0.010 | 3721 | 1847 | 162 | 1835 | -60.348 | -0.016 |
| 0.020 | 3187 | 1583 | 136 | 1583 | -31.722 | -0.010 |
| 0.030 | 2694 | 1322 | 115 | 1344 | -16.269 | -0.006 |
| 0.040 | 2207 | 1085 | 95 | 1108 | 0.150 | 0.000 |
| 0.050 | 1778 | 887 | 78 | 895 | 6.520 | 0.004 |
| 0.060 | 1401 | 697 | 63 | 723 | 41.673 | 0.030 |
| 0.080 | 821 | 393 | 37 | 420 | 17.400 | 0.021 |
| 0.100 | 446 | 202 | 20 | 234 | 20.813 | 0.047 |

Chosen tau 0.1. On 2021-2022: 446 bets, 20 pushes, 20.8 units, ROI 0.047, week-block 95% [-0.034, 0.129].

| season | bets | pushes | units | roi |
| --- | --- | --- | --- | --- |
| 2021 | 171 | 9 | 19.894 | 0.116 |
| 2022 | 275 | 11 | 0.919 | 0.003 |

## Decision rules applied to 2021-2022 (code-path check only; the real verdict is the test)

- Forecast: does not beat the closing total.
- Information: adds information to the close.
- Betting: not profitable.

Private research on scraped odds; not betting advice.
The information used here was obtained free of charge from and is copyrighted by Retrosheet.
