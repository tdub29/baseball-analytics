# Simulator validation (SIM-PLAN.md)

Generated 2026-10-06 by `Rscript research/r/mlb/simulate.R evaluate`. Validation seasons only: Retrosheet 2015-2022, nothing from 2023-2025. N = 2000 simulations per game (two halves of 1000). Per-game outputs stay in `data/mlb/sim/` (not committed).

## Verdict under the charter's rules

- Win probability, adds value over M5: **no**. Recalibrated (b) -0.00051 [-0.00140, 0.00038]; stack (c) -0.00026 [-0.00060, 0.00007]. The rule needs either interval above zero.
- Win probability, adds value over the ensemble: **no**. Recalibrated -0.00093 [-0.00179, -0.00005]; stack -0.00059 [-0.00122, -0.00001].
- Totals, beats T2 as simulated (N = 2000): **no**, -0.0030 [-0.0091, 0.0033]. Extrapolated to infinite N: 0.0085 [0.0023, 0.0148] (see the post-hoc checks in section 4).
- Reported, not gated: bullpen "pitched" log loss beats the naive window rate by 0.0385 [0.0371, 0.0399]; starter batters faced beats the normal baseline by 0.1190 [0.1035, 0.1364] in log score.

## Simulator calibration, 2017-2022

Means over games. sp_share = share of a team's plate appearances against the opposing starter; relievers = relievers used per team-game.

| season | games | runs_sim | runs_act | p_home_sim | home_win_act | sp_share_sim | sp_share_act | relievers_sim | relievers_act |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 | 2430 | 9.276 | 9.293 | 0.539 | 0.540 | 0.621 | 0.628 | 3.232 | 3.220 |
| 2018 | 2429 | 9.400 | 8.900 | 0.541 | 0.528 | 0.599 | 0.605 | 3.326 | 3.358 |
| 2019 | 2429 | 9.509 | 9.661 | 0.535 | 0.529 | 0.573 | 0.585 | 3.370 | 3.409 |
| 2020 | 898 | 9.522 | 9.292 | 0.534 | 0.557 | 0.556 | 0.558 | 3.416 | 3.430 |
| 2021 | 2429 | 9.331 | 9.061 | 0.528 | 0.539 | 0.552 | 0.577 | 3.501 | 3.432 |
| 2022 | 2430 | 9.451 | 8.567 | 0.533 | 0.533 | 0.557 | 0.591 | 3.526 | 3.296 |

## 1. Bullpen usage forecast: did this candidate pitch in this game?

Candidates per team-game: up to 22 (pitchers used by the team in its last 18 games before the date, minus the starter and anyone whose most recent appearance before the date was for another team). Coverage: 95.1% of actual relief appearances were by a listed candidate.

Log loss of "pitched" (lower is better); naive = the candidate's relief appearances over his team's games in the window.

| season | candidates | pitched_rate | sim | naive |
| --- | --- | --- | --- | --- |
| 2017 | 74655 | 0.2015 | 0.3762 | 0.4139 |
| 2018 | 76873 | 0.2027 | 0.3825 | 0.4185 |
| 2019 | 79171 | 0.1995 | 0.3863 | 0.4229 |
| 2020 | 33403 | 0.1712 | 0.3582 | 0.4031 |
| 2021 | 82142 | 0.1924 | 0.3706 | 0.4112 |
| 2022 | 81835 | 0.1854 | 0.3607 | 0.3994 |
| pooled | 428079 | 0.1942 | 0.3738 | 0.4123 |

Naive minus simulator, per candidate-game (positive = simulator better), team-season cluster bootstrap 95%: 0.0385 [0.0371, 0.0399].

Calibration by decile of the simulated probability (pooled):

| decile | n | mean_sim | observed | ebf_sim | bf_obs |
| --- | --- | --- | --- | --- | --- |
| 1 | 44234 | 0.001 | 0.000 | 0.006 | 0.003 |
| 2 | 42132 | 0.010 | 0.007 | 0.049 | 0.063 |
| 3 | 42424 | 0.027 | 0.017 | 0.134 | 0.129 |
| 4 | 42807 | 0.068 | 0.044 | 0.346 | 0.258 |
| 5 | 42557 | 0.127 | 0.087 | 0.638 | 0.452 |
| 6 | 42864 | 0.200 | 0.177 | 0.996 | 0.858 |
| 7 | 42663 | 0.279 | 0.288 | 1.349 | 1.330 |
| 8 | 42970 | 0.355 | 0.376 | 1.662 | 1.699 |
| 9 | 42754 | 0.436 | 0.443 | 1.988 | 1.935 |
| 10 | 42674 | 0.569 | 0.504 | 2.546 | 2.207 |

Batters faced, log score of the actual count in bins 0, 1, ..., 8, 9+ (higher is better; naive = pitched rate times the prior seasons' relief distribution); mae_sim = mean absolute error of the simulated expected batters faced:

| season | sim | naive | mae_sim |
| --- | --- | --- | --- |
| 2017 | -0.7675 | -0.8152 | 1.1759 |
| 2018 | -0.7737 | -0.8225 | 1.2010 |
| 2019 | -0.7735 | -0.8254 | 1.2517 |
| 2020 | -0.6827 | -0.7395 | 1.1574 |
| 2021 | -0.7295 | -0.7833 | 1.2043 |
| 2022 | -0.7042 | -0.7556 | 1.1869 |
| pooled | -0.7437 | -0.7950 | 1.2005 |

Simulator minus naive log score per candidate-game: 0.0513 [0.0497, 0.0528].

## 2. Starter hook: batters faced

Log score of the starter's actual batters faced (higher is better) under the simulated distribution and under a normal around the v2 build's expected batters faced with the prior seasons' residual spread; mean absolute error of each mean; share of starts inside the simulated 10%-90% range.

| season | starts | actual_bf | sim_mean | build_exp_bf | ls_sim | ls_normal | mae_sim | mae_build | cover80 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 | 4860 | 23.636 | 23.827 | 23.980 | -2.721 | -2.795 | 2.880 | 2.870 | 0.869 |
| 2018 | 4858 | 22.716 | 23.033 | 23.232 | -2.785 | -2.902 | 3.075 | 3.104 | 0.860 |
| 2019 | 4858 | 22.127 | 22.069 | 22.628 | -2.775 | -2.945 | 3.187 | 3.220 | 0.853 |
| 2020 | 1796 | 20.371 | 20.597 | 21.285 | -2.937 | -3.049 | 3.654 | 3.698 | 0.826 |
| 2021 | 4858 | 21.314 | 20.794 | 21.672 | -2.837 | -2.954 | 3.450 | 3.341 | 0.839 |
| 2022 | 4860 | 21.916 | 21.265 | 21.985 | -2.757 | -2.877 | 3.167 | 3.054 | 0.861 |
| pooled | 26090 | 22.206 | 22.088 | 22.602 | -2.786 | -2.905 | 3.186 | 3.158 | 0.854 |

Simulated minus normal log score per start: 0.1190 [0.1035, 0.1364].

## 3. Value: win probability vs M5 and the ensemble

12142 games (2017-2019, 2021-2022) where M5 and the ensemble exist in `predictions-v2-validation.csv`; ties dropped. Log loss, lower is better. sim_raw = simulated P(home win); sim_raw_inf = per-game split-half extrapolation to infinite N; sim_recal = weekly walk-forward logistic on logit(sim) + run-margin gap + defensive-efficiency gap; stack = weekly walk-forward logistic on logit(M5) + logit(sim), 2018-2022 only.

| season | games | M5 | ENS | sim_raw | sim_raw_inf | sim_recal | stack |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 | 2427 | 0.6763 | 0.6755 | 0.6775 | 0.6772 | 0.6777 | NA |
| 2018 | 2429 | 0.6714 | 0.6703 | 0.6730 | 0.6727 | 0.6708 | 0.6717 |
| 2019 | 2429 | 0.6633 | 0.6639 | 0.6690 | 0.6688 | 0.6642 | 0.6638 |
| 2021 | 2428 | 0.6720 | 0.6715 | 0.6765 | 0.6762 | 0.6739 | 0.6720 |
| 2022 | 2429 | 0.6686 | 0.6684 | 0.6707 | 0.6705 | 0.6675 | 0.6690 |
| pooled | 12142 | 0.6703 | 0.6699 | 0.6733 | 0.6731 | 0.6708 | NA |
| pooled 2018-2022 | 9715 | 0.6688 | 0.6685 | 0.6723 | 0.6721 | 0.6691 | 0.6691 |

Paired per-game differences, baseline minus candidate (positive = simulator better), home team-season cluster bootstrap 95%:

- M5 minus sim raw: -0.00301 [-0.00461, -0.00144] (interval below zero).
- M5 minus sim raw, extrapolated to infinite N: -0.00277 [-0.00436, -0.00119].
- M5 minus sim recalibrated: -0.00051 [-0.00140, 0.00038] (interval spans zero).
- Ensemble minus sim raw: -0.00344 [-0.00495, -0.00190]; ensemble minus sim recalibrated: -0.00093 [-0.00179, -0.00005] (interval below zero).
- M5 minus stack (2018-2022): -0.00026 [-0.00060, 0.00007] (interval spans zero); ensemble minus stack: -0.00059 [-0.00122, -0.00001] (interval below zero).

Monte Carlo: the expected log-loss penalty of N = 2000 is about 1 / (2N) = 0.00025; measured, full minus extrapolated: 0.00025. Correlation of logit(M5) and logit(sim): 0.947. Last recalibration fit: (Intercept) 0.001, lsim 0.952, drd 0.102, dder 0.099. Last stack fit: (Intercept) 0.007, stats::qlogis(M5) 1.011, lsim -0.028.
2020 (no ensemble; not in the comparison): 898 games, M5 0.6772, sim raw 0.6792, sim recalibrated 0.6806.

Reliability by decile of sim P(home win):

| decile | games | sim_raw | sim_recal | M5 | home_won |
| --- | --- | --- | --- | --- | --- |
| 1 | 1222 | 0.407 | 0.366 | 0.370 | 0.371 |
| 2 | 1210 | 0.457 | 0.428 | 0.432 | 0.410 |
| 3 | 1232 | 0.483 | 0.462 | 0.467 | 0.482 |
| 4 | 1209 | 0.506 | 0.490 | 0.495 | 0.501 |
| 5 | 1215 | 0.525 | 0.516 | 0.521 | 0.510 |
| 6 | 1213 | 0.545 | 0.541 | 0.546 | 0.566 |
| 7 | 1215 | 0.565 | 0.569 | 0.575 | 0.563 |
| 8 | 1203 | 0.587 | 0.596 | 0.600 | 0.603 |
| 9 | 1215 | 0.615 | 0.631 | 0.637 | 0.638 |
| 10 | 1208 | 0.664 | 0.691 | 0.696 | 0.697 |

## 4. Totals: simulated run distributions vs the totals study's T2

T2 reproduced walk-forward here (frozen v2 features, md5 67b60417...): pooled 2017-2022 log score -2.8616 on 13010 complete games (totals-validation.md: -2.8616 on 13,010). Log score of the actual total, higher is better. Simulated distribution = histogram of total runs mixed 99/1 with a negative binomial matched to its mean and variance; sim_inf = split-half extrapolation to infinite N.

| season | games | actual | sim_mean | T2 | sim | sim_inf |
| --- | --- | --- | --- | --- | --- | --- |
| 2017 | 2428 | 9.2928 | 9.2765 | -2.8642 | -2.8655 | -2.8533 |
| 2018 | 2424 | 8.8977 | 9.3997 | -2.8682 | -2.8685 | -2.8553 |
| 2019 | 2419 | 9.6726 | 9.5106 | -2.9111 | -2.9096 | -2.8977 |
| 2020 | 897 | 9.2965 | 9.5225 | -2.8604 | -2.8520 | -2.8419 |
| 2021 | 2422 | 9.0636 | 9.3300 | -2.8452 | -2.8515 | -2.8397 |
| 2022 | 2420 | 8.5682 | 9.4498 | -2.8196 | -2.8325 | -2.8239 |
| pooled | 13010 | 9.1126 | 9.4021 | -2.8616 | -2.8646 | -2.8531 |

Simulator minus T2, per game (positive = simulator better), home team-season cluster bootstrap 95%: -0.0030 [-0.0091, 0.0033] (interval spans zero); extrapolated: 0.0085 [0.0023, 0.0148].

Post-hoc checks on the extrapolation (SIM-PLAN.md it 3, added after this result was seen; they do not change the rule): the delta-method expected finite-N penalty of the histogram, mean of (1 - p) / (2 N p) at the actual total, is 0.0085, against a measured full minus extrapolated 0.0114. The moment-matched negative binomial alone (simulated mean and variance, almost no Monte Carlo error) scores -2.8716; minus T2: -0.0100 [-0.0131, -0.0070].

## 5. Matchup probabilities, one game

CHA202208010, KCA at CHA (2022-08-01), simulated 20000 times with every plate appearance tracked. P(home win) 0.623; actual 2-1. Probabilities are aggregates of the simulation, no odds.

**CHA pitching** (starter Michael Kopech: simulated batters faced 20.4, actual 27). Relievers most likely to pitch:

| reliever | P(pitches) | E[batters faced] | most likely hitters faced, P(at least one PA) |
| --- | --- | --- | --- |
| Jimmy Lambert | 0.70 | 3.38 | Hunter Dozier 0.38, Nick Pratto 0.38, Michael Taylor 0.38 |
| Kendall Graveman | 0.53 | 2.49 | Hunter Dozier 0.28, Michael Taylor 0.28, Nick Pratto 0.27 |
| Matt Foster | 0.53 | 2.30 | Michael Taylor 0.26, Maikel García 0.26, Hunter Dozier 0.26 |
| José Ruiz | 0.49 | 2.19 | Hunter Dozier 0.25, Michael Taylor 0.24, Maikel García 0.24 |
| Joe Kelly | 0.39 | 1.71 | Michael Taylor 0.19, Nicky Lopez 0.19, Maikel García 0.19 |
| Reynaldo López | 0.32 | 1.49 | Michael Taylor 0.17, Hunter Dozier 0.16, Nick Pratto 0.16 |

Expected plate appearances against the starter, batting order 1-9: 2.73, 2.63, 2.51, 2.39, 2.26, 2.14, 2.02, 1.91, 1.82.

**KCA pitching** (starter Daniel Lynch: simulated batters faced 21.3, actual 22). Relievers most likely to pitch:

| reliever | P(pitches) | E[batters faced] | most likely hitters faced, P(at least one PA) |
| --- | --- | --- | --- |
| Dylan Coleman | 0.53 | 2.44 | Seby Zavala 0.28, Adam Engel 0.27, Leury García 0.27 |
| Josh Staumont | 0.49 | 2.11 | Seby Zavala 0.24, Adam Engel 0.24, Yasmani Grandal 0.24 |
| Jackson Kowar | 0.46 | 3.72 | Seby Zavala 0.34, Leury García 0.34, Adam Engel 0.34 |
| Scott Barlow | 0.42 | 1.81 | Leury García 0.20, Seby Zavala 0.20, Yasmani Grandal 0.20 |
| Wyatt Mills | 0.40 | 1.98 | Leury García 0.22, Adam Engel 0.22, Yasmani Grandal 0.22 |
| José Cuas | 0.29 | 1.24 | Seby Zavala 0.14, Leury García 0.14, Adam Engel 0.14 |

Expected plate appearances against the starter, batting order 1-9: 2.81, 2.72, 2.62, 2.50, 2.37, 2.24, 2.12, 2.00, 1.90.

Relievers who actually pitched: José Ruiz (CHA, 3 BF); Jimmy Lambert (CHA, 3 BF); Wyatt Mills (KCA, 4 BF); Dylan Coleman (KCA, 4 BF); Scott Barlow (KCA, 7 BF).

## Fitted pieces

Who enters: conditional logit fit on 2019-2021 relief entries (the 2022 fit). Candidate terms, and interactions with the situation at entry: lLI = log LI; save9 = last scheduled inning or later, leading by 1-3; early = inning 5 or before; blow = margin 5+; late = the inning before the last scheduled one or later. p1-p3 = pitches on each of the three previous days, in tens.

| term | coef | se |
| --- | --- | --- |
| gm | 1.051 | 0.036 |
| fin | -1.502 | 0.041 |
| lmbf | -0.612 | 0.045 |
| ss | -2.531 | 0.049 |
| p1 | -1.231 | 0.015 |
| p2 | -0.392 | 0.008 |
| p3 | -0.146 | 0.006 |
| b2b | -1.550 | 0.053 |
| lds | -0.902 | 0.013 |
| n14 | 0.159 | 0.005 |
| same | 0.724 | 0.015 |
| gm:lLI | 0.975 | 0.029 |
| fin:save9 | 7.934 | 0.140 |
| lmbf:early | 3.276 | 0.077 |
| lmbf:blow | 0.595 | 0.082 |
| ss:early | 1.630 | 0.077 |
| gm:blow | -0.492 | 0.102 |
| share3:late | -0.057 | 0.039 |

Per season: relief entries in the training window and those whose reliever was a listed candidate (the rest are dropped from the fit), and the hazard models' rows and deviance explained.

| season | choice_events | choice_kept | hook_rows | hook_dev_expl | exit_rows | exit_dev_expl |
| --- | --- | --- | --- | --- | --- | --- |
| 2016 | 15096 | 14337 | 119140 | 0.477 | 59630 | 0.366 |
| 2017 | 30396 | 28973 | 235879 | 0.483 | 122615 | 0.378 |
| 2018 | 46047 | 44014 | 350690 | 0.481 | 188239 | 0.376 |
| 2019 | 47262 | 45260 | 341860 | 0.478 | 198443 | 0.384 |
| 2020 | 48525 | 46418 | 303431 | 0.458 | 125363 | 0.321 |
| 2021 | 39034 | 37097 | 231304 | 0.440 | 104176 | 0.316 |
| 2022 | 39397 | 37321 | 224482 | 0.427 | 106368 | 0.322 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet. Interested parties may contact Retrosheet at "www.retrosheet.org".
