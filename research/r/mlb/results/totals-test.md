# Totals study: test

Generated 2026-10-05 by `Rscript research/r/mlb/totals_study.R test`. Charter: TOTALS-PLAN.md. features.rds md5 67b60417d85f10baa823bc4f5ca9922f.


## Data

- Games 2016-2025 after dropping 54 that ended before their scheduled innings (2016: 7, 2017: 2, 2018: 5, 2019: 10, 2020: 1, 2021: 7, 2022: 10, 2023: 3, 2024: 4, 2025: 5).
- Odds file starts 2021-04-01 (not 2021-03-20). 6565 matched games in 2023-2025 outside the excluded window, NA% of the 4397 Retrosheet games from the first odds date; 2 dropped as ambiguous (same teams, day and score). 422 more in 2021-09-01..2021-12-31 excluded.
- Market rows scored: 6565 games, 255 pushes (3.9%), 43.9% of lines whole numbers; books per game 6.0, at the main line 4.9; median closing overround 1.047.
- Temperature missing or implausible outdoors, set to 72: 0 games. Run values (2015-2016 team-games): intercept -1.903, k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.
- Run environment (it 3, chosen on 2017-2020 by `totals_study.R tune`, results/totals-tune.md): fit weights half-life 365 days; as-of league runs per nine innings as a predictor, half-life 15 days.

## Calibration of total runs vs outcomes (no market)

Walk-forward weekly, 2021-2025. Mean predicted total and log score of the actual total (higher is better).

| season | games | actual | mean_T1 | mean_T2 | mean_T3 | mean_B | logscore_T1 | logscore_T2 | logscore_T3 | logscore_B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2023 | 2427 | 9.2386 | 8.9946 | 8.9834 | 9.0559 | 8.9784 | -2.8851 | -2.8858 | -2.8889 | -2.9004 |
| 2024 | 2425 | 8.7872 | 8.9439 | 8.9303 | 8.9170 | 8.9949 | -2.8167 | -2.8176 | -2.8222 | -2.8297 |
| 2025 | 2425 | 8.8986 | 8.8562 | 8.8491 | 8.8513 | 8.8928 | -2.8714 | -2.8711 | -2.8737 | -2.8829 |
| pooled | 7277 | 8.9749 | 8.9316 | 8.9209 | 8.9414 | 8.9554 | -2.8577 | -2.8581 | -2.8616 | -2.8710 |

Selected candidate (lowest 2021-2022 over/under log loss): **T2**. Deciles of its predicted mean, pooled:

| decile | games | pred_mean | actual_mean | pred_over85 | obs_over85 |
| --- | --- | --- | --- | --- | --- |
| 1 | 728 | 7.4208 | 7.9354 | 0.3443 | 0.3942 |
| 2 | 728 | 7.9804 | 8.2761 | 0.3990 | 0.4409 |
| 3 | 727 | 8.2871 | 8.5048 | 0.4283 | 0.4608 |
| 4 | 728 | 8.5462 | 8.5495 | 0.4524 | 0.4615 |
| 5 | 728 | 8.7862 | 8.7239 | 0.4742 | 0.4794 |
| 6 | 727 | 9.0081 | 8.9794 | 0.4939 | 0.5007 |
| 7 | 728 | 9.2385 | 9.1937 | 0.5139 | 0.5220 |
| 8 | 727 | 9.5012 | 9.2930 | 0.5361 | 0.5530 |
| 9 | 728 | 9.8502 | 9.5343 | 0.5642 | 0.5467 |
| 10 | 728 | 10.5908 | 10.7582 | 0.6189 | 0.6360 |

Variance, predicted vs observed squared error: T1 19.55 vs 19.71; T2 19.82 vs 19.72; T3 19.77 vs 19.87; B 20.26 vs 20.27.

Last weekly fit, T1: (Intercept) -0.3647, lxr 1.1577, temp_c 0.0039, wind_out 0.0047, wind_in -0.0002, dome -0.0013, ump_k -0.0337, ump_bb 0.0522, lenv 0.1659; theta 7.33.
Last weekly fit, T2 (per side): (Intercept) -0.5163, lxr 1.3289, home 0.0043, temp_c 0.0038, wind_out 0.0048, wind_in -0.0001, dome -0.0001, ump_k -0.0343, ump_bb 0.0511, lenv 0.1610; theta 3.54.

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

## Over/under log loss vs the no-vig close, 2023-2025 (frozen, scored once)

Pushes excluded. Lower is better.

| season | games | market | T1 | T2 | T3 | B |
| --- | --- | --- | --- | --- | --- | --- |
| 2023 | 2300 | 0.6934 | 0.6975 | 0.6984 | 0.7016 | 0.7079 |
| 2024 | 2282 | 0.6930 | 0.6950 | 0.6956 | 0.6995 | 0.7042 |
| 2025 | 1728 | 0.6925 | 0.7016 | 0.7014 | 0.7026 | 0.7090 |
| pooled | 6310 | 0.6930 | 0.6977 | 0.6982 | 0.7011 | 0.7069 |

Market minus T2, per game (positive = model better): -0.00520 [-0.00867, -0.00201], home-team-season cluster bootstrap 95%.
Over rate on non-push games: actual 0.4933, market mean 0.5004, T2 mean 0.4864. Model mean total minus line 0.421 runs (a right-skewed count's mean sits above the median the line targets, so this alone is not bias); correlation of model mean with the line 0.723.

Blend fit on 2021-2022: logit p = -0.050 + 1.831 logit(market) + 0.351 logit(T2). Gain over the market alone on 2023-2025: -0.00082 [-0.00241, 0.00069].

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

Chosen tau 0.1. On 2023-2025: 718 bets, 20 pushes, 33.2 units, ROI 0.046, week-block 95% [-0.030, 0.120].

| season | bets | pushes | units | roi |
| --- | --- | --- | --- | --- |
| 2023 | 326 | 4 | 23.226 | 0.071 |
| 2024 | 203 | 7 | 18.562 | 0.091 |
| 2025 | 189 | 9 | -8.603 | -0.046 |

## Decision rules (TOTALS-PLAN.md)

- Forecast: does not beat the closing total.
- Information: adds no information to the close.
- Betting: not profitable.

Private research on scraped odds; not betting advice.
The information used here was obtained free of charge from and is copyrighted by Retrosheet.
