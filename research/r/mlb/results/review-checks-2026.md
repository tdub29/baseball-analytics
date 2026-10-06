# 2026 forward test: review checks, recomputed

Computed 2026-10-06 09:47 at commit fa0e7ce by `review_checks.R`. **Exploratory: computed after scoring; changes no number, threshold or verdict.** The pre-registered home-team intervals in `forward-test-2026.md` decide; this file only makes the independent post-scoring review's ad hoc checks (FORWARD-PLAN.md, 2026-10-06; REPORT.md section 9; MODEL-CARD.md) reproducible. 17 of 24 rows match.

Inputs: the four scored 2026 files (sha256 matched FORWARD-PLAN.md), 2429 games, 30 home-team clusters, 27 Monday weeks; earlier edges from `predictions-v2-test.csv` and `predictions-v2-validation.csv` with `sabr-predictions-validation.csv`. Every resample: 1,000 draws, seed 20261005, ratio of summed differences as `forward_score.R`. Baseline minus model per game; positive = model better.

## The ten comparisons

| model | vs | estimate | home-team 95%, as run | recomputed | SE | t(29) 95% | game 95% | week 95% | Holm p |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| v2 | B_home | 0.01028 | [0.00475, 0.01643] | [0.00475, 0.01643] | 0.00296 | [+0.0042, +0.0163] | [+0.0041, +0.0162] | [+0.0045, +0.0165] | 0.0044 |
| v2 | C_team_only | 0.00270 | [-0.00124, 0.00777] | [-0.00124, 0.00777] | 0.00223 | [-0.0019, +0.0073] | [-0.0008, +0.0060] | [-0.0008, +0.0059] | 1.0000 |
| v2 | S4 | 0.00048 | [-0.00198, 0.00298] | [-0.00198, 0.00298] | 0.00127 | [-0.0021, +0.0031] | [-0.0022, +0.0028] | [-0.0018, +0.0032] | 1.0000 |
| v2_dayahead | B_home | 0.01094 | [0.00515, 0.01711] | [0.00515, 0.01711] | 0.00303 | [+0.0048, +0.0171] | [+0.0051, +0.0168] | [+0.0053, +0.0169] | 0.0030 |
| v2_dayahead | C_team_only | 0.00337 | [-0.00017, 0.00793] | [-0.00017, 0.00793] | 0.00207 | [-0.0009, +0.0076] | [+0.0000, +0.0065] | [+0.0003, +0.0063] | 0.7307 |
| v2_dayahead | S4 | 0.00115 | [-0.00108, 0.00357] | [-0.00108, 0.00357] | 0.00119 | [-0.0013, +0.0036] | [-0.0016, +0.0035] | [-0.0012, +0.0040] | 1.0000 |
| v4 | B_home | 0.01025 | [0.00478, 0.01633] | [0.00478, 0.01633] | 0.00294 | [+0.0042, +0.0163] | [+0.0041, +0.0162] | [+0.0044, +0.0166] | 0.0044 |
| v4 | C_team_only | 0.00268 | [-0.00127, 0.00778] | [-0.00127, 0.00778] | 0.00225 | [-0.0019, +0.0073] | [-0.0008, +0.0060] | [-0.0009, +0.0058] | 1.0000 |
| v4 | S4 | 0.00046 | [-0.00195, 0.00297] | [-0.00195, 0.00297] | 0.00128 | [-0.0022, +0.0031] | [-0.0022, +0.0029] | [-0.0018, +0.0032] | 1.0000 |
| v4 | v2 | -0.00003 | [-0.00018, 0.00012] | [-0.00018, 0.00012] | 0.00007 | [-0.0002, +0.0001] | [-0.0002, +0.0001] | [-0.0002, +0.0001] | 1.0000 |

SE: standard deviation of the 1,000 home-team draws. t(29): estimate plus or minus qt(0.975, 29) times SE. Game: each game resampled. Week: Monday weeks resampled. Holm p: two-sided normal p from estimate / SE, Holm-adjusted over the ten.

## 1. Power of the 2026 test to detect the earlier edges (v2)

Two-sided 5% z test with the home-team SE; detectable edge = (1.96 + 0.84) x SE. Earlier edges: S4 minus M5 on the 2017-2022 validation games, team run margin minus M5 on the 2023-2025 test games. "About 15%" matches when the power rounds to 15%.

| quantity | published | recomputed | match |
| --- | --- | --- | --- |
| cluster SE, v2 vs S4 | 0.0013 | 0.0013 | MATCH |
| cluster SE, v2 vs team run margin | 0.0023 | 0.0022 | DIFFER |
| 80%-power detectable edge vs S4 | 0.0036 | 0.0036 | MATCH |
| 80%-power detectable edge vs team run margin | 0.0063 | 0.0063 | MATCH |
| earlier edge over S4 (2017-2022, 12,142 games) | 0.0011 | 0.0011 | MATCH |
| earlier edge over team run margin (2023-2025, 7,288 games) | 0.0021 | 0.0021 | MATCH |
| power for the earlier edge over team run margin | about 15% | 15.7% | DIFFER |
| power for the earlier edge over S4 | about 15% | 13.8% | DIFFER |
| 2026 interval contains the earlier edge (both) | yes | yes | MATCH |

## 2. Holm adjustment over the ten comparisons

| quantity | published | recomputed | match |
| --- | --- | --- | --- |
| home-field wins significant after Holm (of 3) | 3 | 3 | MATCH |
| largest Holm-adjusted p among them | at most 0.006 | 0.0044 | MATCH |
| other comparisons significant after Holm (of 7) | 0 (nothing else comes close) | 0 (smallest adjusted p 0.731) | MATCH |

## 3. t(29) widening for 30 home-team clusters

| quantity | published | recomputed | match |
| --- | --- | --- | --- |
| interval widening, t(29) over normal | about 4% | 4.4% | MATCH |
| verdicts flipped (of 10) | 0 | 0 | MATCH |

## 4. Game-level and week-block resampling beside the home-team clusters

| quantity | published | recomputed | match |
| --- | --- | --- | --- |
| home-team intervals equal to forward-test-2026.md (5 decimals) | 10 of 10 | 10 of 10 | MATCH |
| v2_dayahead vs team run margin, game resample | [+0.0001, +0.0066] | [+0.0000, +0.0065] | DIFFER |
| v2_dayahead vs team run margin, week resample | [+0.0004, +0.0063] | [+0.0003, +0.0063] | DIFFER |
| comparisons whose verdict changes under game or week resampling | 1: v2_dayahead vs C_team_only | 1: v2_dayahead vs C_team_only | MATCH |

## 5. Calibration slope of v2

Slope of logit(p) in a logistic refit of outcomes; interval: 1,000 home-team cluster draws, refit each time, 2.5% and 97.5% quantiles.

| quantity | published | recomputed | match |
| --- | --- | --- | --- |
| calibration slope, v2 | 0.933 | 0.933 | MATCH |
| home-team cluster 95% interval | [0.705, 1.151] | [0.723, 1.181] | DIFFER |
| maintenance trigger (interval excludes 1) | not triggered | not triggered | MATCH |

## 6. Projected-lineup edge over v2 (also a review check in REPORT.md section 9)

| quantity | published | recomputed | match |
| --- | --- | --- | --- |
| v2_dayahead minus v2 log loss saved per game | 0.0007 | 0.0007 | MATCH |
| standard error (home-team draws) | 0.0005 | 0.0005 | MATCH |
| share of the edge from March games | most of it | 40% | DIFFER |

## Notes on the differences

One line per DIFFER row, computed by this script. The published column keeps the values as originally published; seeds other than 20261005 appear only here.

- cluster SE, v2 vs team run margin: 0.0023 is the interval width / 3.92 (0.00230); the SD of the draws is 0.00223. The published detectable edge 0.0063 fits 0.00223 (it would be 0.0064 with 0.00230), so the published SE and detectable edge came from two different SE estimates. Corrected in REPORT.md on 2026-10-06 to 0.0022.
- power for the earlier edge over team run margin: 15.7% with the SD of the draws; 15.1% with the interval-width SE 0.00230, which rounds to the published 15%. Corrected in REPORT.md on 2026-10-06 to 16%.
- power for the earlier edge over S4: 13.8% (13.4% with the rounded SE 0.0013): about 14%, so "about 15%" for both earlier edges was loose for S4. Corrected in REPORT.md on 2026-10-06 to 14%.
- v2_dayahead vs team run margin, game resample: Monte Carlo noise, no correction needed: the same game resample at seed 20261005 and at seeds 1, 42, 2026, 20261004, 20261006 gives lower bounds -0.0001 to +0.0003 and upper bounds +0.0063 to +0.0066; the published interval lies inside that range. At some seeds the lower bound is below zero, so whether this comparison clears zero under game resampling is itself seed-dependent.
- v2_dayahead vs team run margin, week resample: Monte Carlo noise or the week definition, no correction needed: the same week resample at seed 20261005 and at seeds 1, 42, 2026, 20261004, 20261006 gives lower bounds +0.0003 to +0.0007 and upper bounds +0.0060 to +0.0064; the published interval lies inside that range. Sunday-start weeks (28) at seed 20261005 give [+0.0004, +0.0063], the published interval exactly, so the review may have used Sunday weeks.
- home-team cluster 95% interval: Monte Carlo noise, no correction needed: the same cluster bootstrap at seed 20261005 and at seeds 1, 42, 2026, 20261004, 20261006 gives lower bounds 0.691 to 0.723 and upper bounds 1.150 to 1.181; the published interval lies inside that range. The trigger fires at none of those seeds.
- share of the edge from March games: March holds 76 of 2,429 games (3%) and supplies 0.642 of the 1.613 total log loss saved (40%). The March per-game edge is 0.0084 against 0.0004 in the other months: concentrated in March per game, but not most of the total. Corrected in REPORT.md on 2026-10-06 to "40% of it from the 76 March games".

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
2026 games and plate appearances: MLB StatsAPI, copyright MLB Advanced Media, L.P., used for private research.
