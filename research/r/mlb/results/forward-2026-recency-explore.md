# 2026: recency model E and the M5 + E ensemble (exploratory, post hoc)

**Exploratory and post hoc.** E and the ensemble were not in FORWARD-PLAN.md, and this file was produced after
the forward test was scored (forward-test-2026.md). No result here changes any model, threshold, recipe or
verdict, and it does not settle the MODEL-CARD.md trigger "M5 fails to beat E's log loss in the next held-out
season": that check stays unchecked for 2026 and carries to 2027 as the card says.

Generated 2026-10-06 by `Rscript research/r/mlb/forward_recency_explore.R`, after `Rscript research/r/mlb/recency_model.R forward`.

## How E and the ensemble were produced

- E is the frozen recency spec, unchanged: windows from `results/recency/picks-validation.csv` and
  `grid-validation.csv`, the same six home-minus-away gaps (lineup, starter, bullpen, fatigue over 1 and 3 days,
  run margin per game), and the same weekly walk-forward refit on every game from 2016 dated before each Monday.
  The only change is the data range: 2015-2026 loaded, 2021-2026 predicted, 2026 StatsAPI game logs fetched
  key-free into the existing cache.
- The ensemble is the logit blend `plogis(w * logit(M5) + (1 - w) * logit(E))` with w = 0.55, re-derived on
  2017-2019 by the matchup_model.R rule and equal to the frozen weight in MODEL-CARD.md.
- M5 is the forward test's v2 file (`predictions-v2-forward.csv`, sha256 matches FORWARD-PLAN.md), best variant M5_plus_defense.
- E predictions: `results/recency/model-predictions-forward.csv` (sha256 `fa97b0efd0497c55f55cc22fd39e8a49470091791909d7ccaaf67723e8f04865`).

## Reproduction check (2021-2025 rows of the forward run vs the committed test predictions)

| tier | games | exactly equal | max abs difference | log loss, forward run | log loss, committed |
| --- | --- | --- | --- | --- | --- |
| B | 12148 | 12148 | 0.0e+00 | 0.691217 | 0.691217 |
| C | 12148 | 12148 | 0.0e+00 | 0.680330 | 0.680330 |
| D | 12148 | 12148 | 0.0e+00 | 0.677465 | 0.677465 |
| E0 | 12148 | 90 | 4.1e-13 | 0.677469 | 0.677469 |
| E | 12148 | 0 | 1.0e-08 | 0.674756 | 0.674756 |

The committed test predictions (commit 2b4b366) predate the asof_decay precision fix (a0ac7df). A rerun of the
test spec with the pre-fix windows.R reproduces the committed file exactly, and a rerun with the current code
matches the forward run's 2021-2025 rows exactly, so adding 2026 rows changes no earlier prediction and the
differences above are the precision fix alone.

## 2026 outcomes (2429 games; lower log loss and Brier are better; slope 1 = calibrated)

| model | log loss | Brier | accuracy at 50% | calibration slope |
| --- | --- | --- | --- | --- |
| v2 | 0.6813 | 0.2441 | 0.564 | 0.933 |
| E | 0.6820 | 0.2445 | 0.556 | 0.875 |
| ENS | 0.6811 | 0.2441 | 0.562 | 0.943 |
| B_home | 0.6916 | 0.2492 | 0.529 | -40.406 |
| C_team_only | 0.6840 | 0.2454 | 0.557 | 0.889 |
| S4 | 0.6818 | 0.2444 | 0.560 | 0.921 |

v2 is M5 (the matchup model), E the recency model, ENS the ensemble; B_home, C_team_only and S4 are the forward
test's baselines, as scored there.

## Paired comparisons (baseline minus model per game; positive = model better)

| model | vs | difference | 95% interval | reading |
| --- | --- | --- | --- | --- |
| v2 | E | 0.00076 | [-0.00186, 0.00326] | no detectable difference |
| ENS | v2 | 0.00013 | [-0.00101, 0.00131] | no detectable difference |
| ENS | E | 0.00089 | [-0.00054, 0.00226] | no detectable difference |
| E | B_home | 0.00952 | [0.00313, 0.01637] | model better |
| E | C_team_only | 0.00194 | [-0.00131, 0.00594] | no detectable difference |
| E | S4 | -0.00028 | [-0.00153, 0.00101] | no detectable difference |
| ENS | B_home | 0.01041 | [0.00443, 0.01658] | model better |
| ENS | C_team_only | 0.00283 | [-0.00055, 0.00713] | no detectable difference |
| ENS | S4 | 0.00061 | [-0.00086, 0.00224] | no detectable difference |

Intervals resample the 30 home teams (1,000 draws, seed 20261005), as in forward_score.R. No odds are used.

Descriptively, M5's 2026 log loss was below E's (0.6813 vs 0.6820). One post hoc season; not a verdict.

## Caveats

- Decision time is first pitch, as in the 2021-2025 test and v2: the starter is StatsAPI's probable pitcher,
  which in history is the man who started, and the lineup is the posted starting nine.
- Every E input uses only games dated before the game's date (as-of rule in windows.R); park factors for 2026
  come from 2023-2025, and a venue with no prior history gets a factor of 1. Same-day doubleheader games do
  not see each other. A suspended game keeps its official (original) date, so innings played on resumption
  count from that date, as in the 2021-2025 test.
- The 2026 schedule has 2,429 final games, all with both posted lineups; 2 are missing a probable starter
  and use league rates for it, the frozen rule for an unknown starter.
- The bullpen term weights relievers by relief batters faced in the last 21 days only, as frozen.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
2026 games and plate appearances: MLB StatsAPI, copyright MLB Advanced Media, L.P., used for private research.
