# When MLB per-PA rates become reliable, and whether the matchup model shrinks them right

Stabilization study for the matchup model ([MATCHUP-PLAN.md](../MATCHUP-PLAN.md)), run 2026-10-05
after the frozen test, so nothing here changes a scored result. Script:
[`reliability.R`](../reliability.R). Generated tables, the alpha grid and the year-to-year pairs:
[`results/reliability/`](reliability/). Plot: [`reliability-alpha-vs-n.png`](reliability-alpha-vs-n.png).

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
Interested parties may contact Retrosheet at "www.retrosheet.org".

## Question

At what sample size does each per-PA rate become reliable for hitters, starting pitchers and
relievers, and do the shrink constants in the model (`BAT_CFG`, `PIT_CFG` in `matchup.R`, the
third number of each entry) match?

## The answer

- **Hitters** (k = sample at reliability 0.5): strikeouts about **45 PA**, unintentional walks
  **110**, home runs **150 to 170**, singles 200, outs in play 75, BABIP-like **365 to 400 balls
  in play** (about 580 PA).
- **Starters**: strikeouts about **75 BF**, walks **215 to 240**, home runs **740 to 900**,
  ground-ball share **63 batted balls**, BABIP-like **1,040 to 1,100 balls in play**, about two
  full seasons of balls in play. **Relievers**: strikeouts **60 BF**, walks **135 to 150**.
- **The FIP / xFIP / SIERA logic holds in this data.** For pitchers, strikeouts and ground-ball
  share settle in under 100 events, walks in 135 to 240, home runs in 600 to 900, and hits on balls
  in play take over 1,000 balls in play: one full starter season (about 550) gives BABIP a
  reliability near 0.35, and the year-to-year correlation for starters is 0.21. Hitters own their
  BABIP far more (k 365 to 400). The model's batted-ball expected home-run rate for pitchers
  stabilizes in about 80 to 106 BF, seven to ten times faster than actual home runs.
- **Where the model disagrees by 2x or more against both estimates:**
  - **Pitchers' batted-ball expected rates (all five, starters and relievers): far too much
    shrink.** `PIT_CFG` uses 1,300 to 3,000; the data say 70 to 220, a factor of 7 to 31. The
    home-run constant, 1,300, is the recency study's figure for *actual* home runs; the model has
    rated pitchers on batted-ball expected outcomes since iteration 2, and those settle an order of
    magnitude faster. For a starter with 600 BF of effective history, k = 1,300 keeps 32% of his
    expected-HR gap from league average; k = 106 would keep 85%.
  - **Hitters' singles (800 vs about 200), outs in play (800 vs about 75) and triples (1,500 vs
    about 540): too much shrink.**
  - **Relievers' walks (300 vs 134 to 149): too much shrink**, at about 2.0 to 2.2x.
  - Everything else is within 2x of both: hitter K, BB, HBP, HR and doubles; starter K, BB and
    HBP; reliever K and HBP. The largest of those gaps: reliever K (90 vs 60), hitter K (60 vs 43
    to 46) and starter HBP (500 vs 840 to 880, the only constant below both estimates).
  - **No outcome is shrunk too little.**
- Both methods agree within their intervals for most rates. Where the point estimates part by 20%
  or more (pitcher home runs, reliever BABIP), the cause is survivorship, shown below; hitter HBP
  (211 vs 256) is the one gap in the other direction.

## Data

- Retrosheet regular-season plate appearances, 2015-2022 for every estimate; 2023-2025 run the same
  way only as an era check (pitch clock, shift ban, bigger bases in 2023) and feed no choice.
  Intentional walks are dropped, as in `retro.R`.
- **Unit: a player-season in one role.** Hitters drop pitchers batting (BF >= PA that season).
  Pitchers drop position players pitching (PA > BF and fewer than 150 BF). A pitcher-season is a
  **starter** if half or more of its BF came in games he started, and the unit then holds only his
  BF in starts; a **reliever** unit holds only BF in relief. Openers who start most of their games
  count as starters.
- **2020 kept.** The 60-game season gives smaller units, but every estimator here conditions on
  each unit's own count and centres on each season's own league rate, so short units add
  information at small N and no bias. Dropping 2020 moves no k under 5,000 by more than 9%
  (liner shares; most move under 3%).
- **Batted-ball coding changed in 2020.** Retrosheet's popup share of balls in play is 0.2 to 1.2%
  in 2015-2019 and 6.7 to 7.2% from 2020 on; fly balls fall from 0.33-0.35 to 0.21-0.27 and liners
  rise from about 0.20 to 0.24 (0.28 in 2020). Fly, liner and popup shares are therefore
  estimated on 2020-2022 only. Ground-ball share (0.42 to 0.44 throughout) uses all eight seasons.
- Outcomes: the eight OUT8 outcomes per PA or BF (strikeout, unintentional walk, HBP, single,
  double, triple, home run, out in play); BABIP-like = hits / (hits + outs in play), home runs
  excluded, reached-on-error and fielder's choice count as outs, in balls-in-play units;
  batted-ball shares of all batted balls with a recorded type (home runs included).
- **Pitchers' model inputs.** `matchup_build.R` rates pitchers on batted-ball expected outcomes:
  each ball in play becomes the league outcome mix of its type (ground, fly, liner, popup) over the
  prior three seasons. Those continuous "x" rates are what `PIT_CFG` shrinks for single, double,
  triple, home run and out in play, so they get their own rows; the actual-outcome rows are the
  FIP/xFIP reference.
- Rates are raw, not park-neutralised (the model neutralises parks). The park effect is measured
  as a sensitivity below.

## Methods

1. **KR-21 alpha, Russell Carleton's method.** For each N on a grid of 25 to 800 events, every unit
   with at least N events contributes N events drawn in random order; KR-21 alpha of the N-event
   totals is computed and averaged over 100 random draws. Items are centred on the role-season
   league rate, so a league-wide level shift between seasons (strikeouts rose from 20.5% to 23.5%)
   is not counted as player spread. For continuous model inputs the same formula is the
   equal-item-variance Cronbach alpha. A grid point needs 30 units. **Split-half** r on two disjoint
   N-event halves (units with 2N or more events) is the second version of the same idea. The exact
   expectation of KR-21 over all possible draws (hypergeometric moments) is also computed: it
   matches the 100-draw average (cross-check table) and is what the bootstrap uses.
2. **Spearman-Brown fit.** alpha(N) = N / (N + k), fit by least squares over the whole grid,
   weighted by units at each N. k is the stabilization point (reliability 0.5); reliability 0.7
   needs 2.33 k.
3. **Random effects on every unit, no minimum.** Beta-binomial maximum likelihood with one mean per
   season and one common k = alpha + beta of the beta prior. For the continuous x rates, the one-way
   random-effects ANOVA moment estimator k = within-unit variance / between-unit variance, which
   is the same quantity (the beta-binomial k equals that ratio exactly). k is bounded at 100,000;
   at the bound there is no detectable player spread.
4. **Player-cluster bootstrap.** Players resampled with replacement, every season of a player
   following him; 200 replicates for 2015-2022, 100 for the era check; percentile 95% intervals
   for both k's.
5. **Year t to t+1.** Players with at least 300 PA (hitters), 300 BF (starters) or 150 BF
   (relievers) in the role in both seasons, pairs 2015-16 through 2018-19 and 2021-22 (2020 left
   out). r is the correlation of season-centred rates; "r if talent were stable" is
   1 / sqrt((1 + k E[1/n_t]) (1 + k E[1/n_t+1])) with k from the same paired units, so
   **persistence = r / r if stable** estimates the year-to-year correlation of true talent.

Verdict rule: the model's k is flagged when it is 2x or more (too much shrink) or half or less
(too little) of both estimates; "vs one only" when only one estimate crosses the line. The
beta-binomial k describes every player the model shrinks; the KR-21 k leans toward regulars.

## Results, 2015-2022

k is in PA for hitters and BF for pitchers, except BABIP-like (balls in play, no home runs) and the
batted-ball shares (batted balls). "Random effects" is the beta-binomial MLE on every unit, or the
ANOVA moment estimator for the x rows. "Model k" is the current `matchup.R` value; for pitchers,
`PIT_CFG` shrinks the x row of each hit outcome, so the actual-outcome rows show none. "Recency
study" is the single-point split-half fit in `results/recency/reliability-validation.csv`; its
walk rate includes HBP.

### Hitters

| Outcome | Rate | Units | k KR-21+SB [95% CI] | k random effects [95% CI] | N at 0.7 (KR / RE) | Model k | Recency study | Verdict |
|---|---|---|---|---|---|---|---|---|
| Strikeout | 0.217 | 5,079 | 46 [42, 51] | 43 [39, 47] | 108 / 100 | 60 | 58 | consistent (within 2x of both) |
| Unintentional walk | 0.081 | 5,079 | 109 [97, 122] | 110 [98, 122] | 254 / 257 | 110 | 113 | consistent (within 2x of both) |
| Hit by pitch | 0.010 | 5,079 | 211 [168, 261] | 256 [216, 302] | 493 / 596 | 300 |  | consistent (within 2x of both) |
| Single | 0.146 | 5,079 | 201 [182, 225] | 195 [176, 219] | 469 / 454 | 800 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Double | 0.045 | 5,079 | 1,170 [948, 1,480] | 1,040 [887, 1,330] | 2,730 / 2,430 | 1,000 |  | consistent (within 2x of both) |
| Triple | 0.004 | 5,079 | 544 [475, 627] | 534 [471, 618] | 1,270 / 1,250 | 1,500 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Home run | 0.032 | 5,079 | 167 [153, 186] | 151 [139, 170] | 389 / 352 | 200 | 201 | consistent (within 2x of both) |
| Out in play | 0.464 | 5,079 | 76 [68, 84] | 75 [68, 83] | 178 / 176 | 800 |  | TOO MUCH shrink: model k 2x+ both estimates |
| BABIP-like (hits / balls in play, no HR) | 0.296 | 5,059 | 399 [349, 472] | 365 [325, 435] | 931 / 852 | n/a |  | not a model rate |
| Ground ball share of batted balls | 0.437 | 5,056 | 66 [60, 73] | 65 [60, 72] | 156 / 153 | n/a |  | not a model rate |
| Fly ball share of batted balls | 0.253 | 1,914 | 84 [75, 95] | 85 [76, 97] | 198 / 199 | n/a |  | not a model rate |
| Line drive share of batted balls | 0.246 | 1,914 | 690 [529, 983] | 658 [518, 933] | 1,610 / 1,540 | n/a |  | not a model rate |
| Popup share of batted balls | 0.070 | 1,914 | 103 [88, 119] | 92 [81, 108] | 240 / 217 | n/a |  | not a model rate |

### Starting pitchers

| Outcome | Rate | Units | k KR-21+SB [95% CI] | k random effects [95% CI] | N at 0.7 (KR / RE) | Model k | Recency study | Verdict |
|---|---|---|---|---|---|---|---|---|
| Strikeout | 0.213 | 2,125 | 73 [64, 85] | 76 [67, 88] | 172 / 178 | 90 | 89 | consistent (within 2x of both) |
| Unintentional walk | 0.075 | 2,125 | 241 [205, 280] | 216 [184, 251] | 562 / 503 | 300 | 305 | consistent (within 2x of both) |
| Hit by pitch | 0.010 | 2,125 | 880 [700, 1,110] | 839 [678, 1,050] | 2,050 / 1,960 | 500 |  | consistent (within 2x of both) |
| Single | 0.146 | 2,125 | 510 [430, 613] | 503 [427, 606] | 1,190 / 1,170 | n/a |  | model shrinks the x version instead |
| Double | 0.046 | 2,125 | 1,720 [1,330, 2,710] | 1,580 [1,240, 2,510] | 4,020 / 3,680 | n/a |  | model shrinks the x version instead |
| Triple | 0.004 | 2,125 | 2,220 [1,530, 3,950] | 2,090 [1,480, 3,610] | 5,180 / 4,870 | n/a |  | model shrinks the x version instead |
| Home run | 0.033 | 2,125 | 897 [721, 1,170] | 743 [617, 943] | 2,090 / 1,730 | n/a | 1,290 | model shrinks the x version instead |
| Out in play | 0.473 | 2,125 | 252 [217, 294] | 252 [219, 296] | 588 / 589 | n/a |  | model shrinks the x version instead |
| Single (x, model input) | 0.150 | 2,125 | 157 [137, 184] | 157 [137, 184] | 367 / 366 | 1,500 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Double (x, model input) | 0.046 | 2,125 | 219 [194, 251] | 210 [186, 240] | 510 / 489 | 1,500 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Triple (x, model input) | 0.005 | 2,125 | 127 [111, 147] | 129 [113, 149] | 297 / 300 | 3,000 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Home run (x, model input) | 0.029 | 2,125 | 106 [92, 122] | 106 [94, 122] | 246 / 247 | 1,300 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Out in play (x, model input) | 0.473 | 2,125 | 120 [105, 137] | 121 [106, 139] | 279 / 282 | 1,500 |  | TOO MUCH shrink: model k 2x+ both estimates |
| BABIP-like (hits / balls in play, no HR) | 0.294 | 2,125 | 1,100 [839, 1,570] | 1,040 [814, 1,510] | 2,570 / 2,420 | n/a |  | not a model rate |
| Ground ball share of batted balls | 0.438 | 2,125 | 63 [55, 74] | 63 [56, 74] | 147 / 148 | n/a |  | not a model rate |
| Fly ball share of batted balls | 0.253 | 788 | 107 [86, 132] | 102 [81, 127] | 249 / 237 | n/a |  | not a model rate |
| Line drive share of batted balls | 0.249 | 788 | 4,180 [1,640, > 100,000] | 4,270 [1,500, > 100,000] | 9,750 / 9,970 | n/a |  | not a model rate |
| Popup share of batted balls | 0.068 | 788 | 159 [132, 201] | 157 [130, 200] | 370 / 365 | n/a |  | not a model rate |

### Relievers

| Outcome | Rate | Units | k KR-21+SB [95% CI] | k random effects [95% CI] | N at 0.7 (KR / RE) | Model k | Recency study | Verdict |
|---|---|---|---|---|---|---|---|---|
| Strikeout | 0.238 | 3,928 | 60 [53, 69] | 60 [53, 68] | 142 / 141 | 90 |  | consistent (within 2x of both) |
| Unintentional walk | 0.087 | 3,928 | 149 [129, 171] | 134 [117, 155] | 347 / 312 | 300 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Hit by pitch | 0.011 | 3,928 | 428 [316, 605] | 415 [325, 529] | 1,000 / 969 | 500 |  | consistent (within 2x of both) |
| Single | 0.140 | 3,928 | 339 [286, 421] | 319 [268, 400] | 790 / 745 | n/a |  | model shrinks the x version instead |
| Double | 0.042 | 3,928 | 908 [669, 1,240] | 801 [602, 1,060] | 2,120 / 1,870 | n/a |  | model shrinks the x version instead |
| Triple | 0.004 | 3,928 | 2,420 [1,470, 10,800] | 2,280 [1,360, 10,800] | 5,650 / 5,310 | n/a |  | model shrinks the x version instead |
| Home run | 0.029 | 3,928 | 816 [641, 1,110] | 593 [471, 774] | 1,900 / 1,380 | n/a |  | model shrinks the x version instead |
| Out in play | 0.449 | 3,928 | 143 [122, 167] | 144 [122, 167] | 334 / 335 | n/a |  | model shrinks the x version instead |
| Single (x, model input) | 0.141 | 3,928 | 91 [80, 104] | 89 [78, 103] | 212 / 208 | 1,500 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Double (x, model input) | 0.043 | 3,928 | 170 [143, 199] | 152 [130, 175] | 397 / 355 | 1,500 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Triple (x, model input) | 0.004 | 3,928 | 102 [86, 117] | 97 [83, 110] | 237 / 227 | 3,000 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Home run (x, model input) | 0.028 | 3,928 | 81 [71, 90] | 79 [70, 89] | 190 / 186 | 1,300 |  | TOO MUCH shrink: model k 2x+ both estimates |
| Out in play (x, model input) | 0.448 | 3,928 | 71 [62, 79] | 69 [60, 79] | 166 / 163 | 1,500 |  | TOO MUCH shrink: model k 2x+ both estimates |
| BABIP-like (hits / balls in play, no HR) | 0.293 | 3,919 | 1,600 [931, 8,210] | 1,060 [705, 2,600] | 3,730 / 2,470 | n/a |  | not a model rate |
| Ground ball share of batted balls | 0.443 | 3,920 | 35 [30, 40] | 35 [30, 40] | 82 / 82 | n/a |  | not a model rate |
| Fly ball share of batted balls | 0.250 | 1,574 | 73 [61, 87] | 70 [60, 85] | 170 / 165 | n/a |  | not a model rate |
| Line drive share of batted balls | 0.241 | 1,574 | 672 [416, 2,060] | 630 [391, 1,490] | 1,570 / 1,470 | n/a |  | not a model rate |
| Popup share of batted balls | 0.072 | 1,574 | 122 [101, 154] | 119 [98, 152] | 285 / 278 | n/a |  | not a model rate |

Fly, liner and popup shares are 2020-2022 only (coding change); everything else 2015-2022.

## Survivorship: why the two methods sometimes part

KR-21 at N uses only player-seasons with N or more events; the beta-binomial uses every
player-season. Players who reach large samples are selected (regulars, healthy starters) and more
alike, so their talent spread is narrower and their k larger. Three pieces of evidence:

- **k implied at each N climbs with N** where selection bites: starter walks 172 at N = 25 to
  290 to 310 at N = 500 to 700; starter home runs 395 at N = 25 to about 1,170 at N = 500 to 600;
  hitter strikeouts 41 at N = 25 to 64 at N = 600. Hitter walks (112 to 95) and ground-ball
  shares do not climb. In the plot, the KR-21 points at large N fall below both fitted curves for
  home runs and BABIP.
- **Same units, same answer.** The beta-binomial fit on only the units with N* or more events
  (N* = 200, relievers 100) matches KR-21's implied k at N*: hitter K 51 vs 51, starter walks 250
  vs 244, reliever K 64 vs 62.
- **Different units, different answer.** The beta-binomial on survivors vs on all units: hitter K
  51 vs 43, starter walks 250 vs 216, starter home runs 877 vs 743, reliever home runs 779 vs 593,
  reliever BABIP 1,740 vs 1,060.

The KR-21 fit across the grid is weighted by units, so the small-N points, where nearly every unit
qualifies, dominate it, and that is why the two headline k's usually agree. The beta-binomial k is
the right target for the model, since the model shrinks every player it sees, including call-ups;
the survivor k is the right description of regulars.

## Cross-checks

- **Random draws vs exact expectation.** The 100-draw KR-21 average and its exact expectation over
  all draws differ by at most 0.009 in alpha at any grid point (largest Monte Carlo standard error
  0.007); the fitted k's agree within 2.3%.
- **Split-half.** The Spearman-Brown k from split-half r is within 8% of the KR-21 k for every
  rate except reliever liners (+15%) and reliever triples (+12%).
- **2020.** Dropping it moves no k under 5,000 by more than 9% (liner shares); most move under 3%.
- **Parks** (ANOVA estimator, raw vs park-neutral, park factors by site and batter hand pooled over
  2015-2022): parks add spread mainly to extra-base hits. Hitter doubles +23%, triples +14%, HBP
  +9%, HR +6%; starter triples +25%, doubles +11%, HR +9%, K +7%; nearly everything else under 5%.
- **ANOVA moments vs beta-binomial** agree within 10% for strikeouts, walks, singles, outs in play,
  every batted-ball share and every x rate. They are 15 to 65% apart for the rare pitcher outcomes
  (HBP, doubles, triples, home runs, BABIP), where the two weight small and large units
  differently and the intervals are wide.

Full cross-check table (KR-21 simulated, exact and split-half; random effects on all units and on
survivors; ANOVA raw and park-neutral; drop-2020): [`reliability/tables.md`](reliability/tables.md).

## Talent drift: year t to t+1

Pairs with 300 PA (hitters), 300 BF (starters) or 150 BF (relievers) in both seasons. "Persistence"
is the observed correlation over the correlation that stable talent would give with these samples,
so it estimates the year-to-year correlation of true talent.

| Role | Rate | Pairs | r [95% CI] | r if stable | Persistence [95% CI] |
|---|---|---|---|---|---|
| hitter | Strikeout | 1013 | 0.83 [0.81, 0.85] | 0.90 | 0.92 [0.90, 0.94] |
| hitter | Unintentional walk | 1013 | 0.72 [0.67, 0.75] | 0.83 | 0.87 [0.83, 0.90] |
| hitter | Home run | 1013 | 0.64 [0.60, 0.68] | 0.74 | 0.87 [0.83, 0.91] |
| hitter | BABIP-like | 1013 | 0.41 [0.35, 0.47] | 0.45 | 0.92 [0.80, 1.08] |
| starter | Strikeout | 516 | 0.75 [0.70, 0.80] | 0.88 | 0.86 [0.81, 0.90] |
| starter | Unintentional walk | 516 | 0.57 [0.49, 0.64] | 0.69 | 0.82 [0.74, 0.92] |
| starter | Home run | 516 | 0.28 [0.19, 0.37] | 0.35 | 0.79 [0.54, 1.07] |
| starter | Home run (x, model input) | 516 | 0.74 [0.70, 0.78] | 0.84 | 0.88 [0.84, 0.92] |
| starter | BABIP-like | 516 | 0.21 [0.12, 0.28] | 0.26 | 0.80 [0.47, 1.19] |
| starter | Ground ball share | 516 | 0.76 [0.71, 0.81] | 0.86 | 0.89 [0.85, 0.92] |
| reliever | Strikeout | 605 | 0.61 [0.54, 0.68] | 0.79 | 0.77 [0.71, 0.83] |
| reliever | Unintentional walk | 605 | 0.54 [0.48, 0.60] | 0.60 | 0.89 [0.80, 1.00] |
| reliever | Home run | 605 | 0.16 [0.07, 0.22] | 0.19 | 0.87 [0.43, 1.36] |
| reliever | Home run (x, model input) | 605 | 0.67 [0.60, 0.72] | 0.75 | 0.89 [0.82, 0.94] |
| reliever | BABIP-like | 605 | 0.06 [-0.01, 0.13] | 0.07 | 0.91 [-0.35, 27.13] |
| reliever | Ground ball share | 605 | 0.76 [0.71, 0.80] | 0.83 | 0.92 [0.88, 0.96] |

Talent moves between seasons: true strikeout and walk talent correlates about 0.82 to 0.92 year to
year (relievers' strikeouts 0.77). That is why the recency study's best windows carry only 50 to
100% of each earlier season, and why within-season reliability is the right yardstick for a shrink
constant applied to decayed data. Pitchers' batted-ball expected rates repeat well (r 0.47 to 0.74),
while their actual hit rates repeat little (starter BABIP r = 0.21, reliever BABIP 0.06, reliever
doubles 0.07).

## Era check, 2023-2025 (not used for any choice)

Same code, 2023-2025 seasons, 100 bootstrap replicates
([`reliability/tables.md`](reliability/tables.md) has every row). Most k's are equal or somewhat
larger after the 2023 rule changes, which means a slightly narrower spread of talent:

- Strikeouts: starters 87 to 89 (vs 73 to 76), relievers 78 to 79 (vs 60); intervals overlap.
- Hitter singles 254 to 263 (vs 195 to 201, intervals apart) and BABIP-like 486 to 530 (vs 365
  to 399).
- Pitchers' x rates settle a little more slowly (starter x home runs 159 to 162 vs 106) but still
  in 84 to 289 events, 5 to 20 times below `PIT_CFG`.
- The verdicts hold except reliever walks: 160 to 186, so 300 is 1.6 to 1.9x, under the 2x line.
  Hitter singles (3x), outs in play (10x) and triples (3x) stay flagged.

## Interpretation for the model

1. **Re-tune `PIT_CFG` for the five batted-ball expected outcomes.** The data put k near 90 to 160
   for singles, 150 to 220 for doubles, 95 to 130 for triples, 80 to 110 for home runs and 70 to
   120 for outs in play, against 1,300 to 3,000 in the model. Today the model washes most of a
   pitcher's contact-quality signal (grounders vs fly balls) back to league average.
2. **Hitters' singles and outs in play are shrunk about 4x and 10x too hard.** Outs in play per PA
   is mostly 1 minus strikeouts, walks and hits, so it settles about as fast as strikeouts do.
   Because the model shrinks each outcome separately and then renormalises to sum to one, an
   over-shrunk out-in-play rate also dilutes the lightly shrunk strikeout signal of a high- or
   low-strikeout hitter.
3. Reliability is not predictive optimality. The model's constants act on decayed multi-season
   counts, so they matter most for players with thin histories, and the best k for log loss can
   differ from the reliability k (for example, newcomers are worse than league average, which a
   single league-mean prior ignores). These numbers say where to look; any change should be chosen
   on the 2017-2022 validation seasons, not here, and the test seasons are already spent.

## Limits

- **Batted-ball coding break in 2020, and the model inherits it.** `matchup_build.R` builds each
  season's expected-outcome mix from the prior three seasons, so 2020-2022 pitchers are scored
  with mixes from the old coding. League expected home runs over actual: 1.00 in 2015, 0.84 to
  1.00 in 2016-2019, **0.58 in 2020**, 0.84 in 2021, 1.13 in 2022, 1.00 to 1.07 in 2023-2025.
  Part of the 2016-2022 swings is the changing ball, which a three-season mix cannot track; the
  2020 drop is the coding break. This study centres each season, so its k's are unaffected; the
  model's 2020-2022 pitcher x rates carry a level bias.
- Rates are not park-neutralised. Parks add some spread to hitters' extra-base rates (park-neutral
  ANOVA k for hitter HR 190 vs 179 raw, doubles 1,730 vs 1,410), so raw k's for those are a little
  low.
- Within-season talent is treated as constant; injuries and mechanical changes make "talent" a
  season average.
- The beta-binomial uses one league mean per season. Fringe players have worse talent on average;
  that mean gap counts as spread, which is right for a model that shrinks everyone to one mean and
  not for a playing-time-aware prior.
- For rare pitcher outcomes the estimators weight units differently and disagree more (reliever
  home runs: KR-21 816, beta-binomial 593, ANOVA moments 322); intervals for triples, liners and
  BABIP are wide, and the starter liner interval reaches the 100,000 bound.
- Starter vs reliever by share of BF in starts; openers who mostly start count as starters.
- Platoon splits (the model's `K_SPLIT_BAT` and `K_SPLIT_PIT` of 600) were not studied.
- Percentile intervals from 200 player-cluster replicates (100 in the era check).

## Reproduce

```
Rscript research/r/mlb/reliability.R     # from the repo root, about 40 minutes with 10 workers
```

Environment: `REL_D` random draws (100), `REL_B` bootstrap replicates (200), `REL_B_ERA` (100),
`REL_WORKERS` (10). Reads the cached `retro_pa()` files and the recency study's reliability CSV;
writes `results/reliability/` and `results/reliability-alpha-vs-n.png`.
