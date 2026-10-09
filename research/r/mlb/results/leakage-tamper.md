# Leakage tamper test: matchup model M5 v2, 2017-2025 features

Generated 2026-10-08 by `research/r/mlb/leakage_tamper.R`. Overall verdict: **PASS, with 1 documented exception(s): suspended games straddling a truncation cutoff, see Participation test**.

## Method

For a cutoff D, every outcome dated on or after D is shuffled among the rows dated on or after D, with fixed seeds
(`tamper.R`): each plate appearance's outcome, batted-ball type, runs on the play and outs before it, jointly; each
game's final score (away and home runs together); and the reached-on-error count of each fielding team-game, which
`der_gap()` reads from the plays file for defensive efficiency. Game id, date, sequence, batter, pitcher, hands,
teams, park, umpire and lineup stay. The features are rebuilt (`matchup_build.R`) and the model rerun
(`matchup_model.R`), whose own inputs are tampered the same way: the team run margin `drd` from the shuffled
scores and `dder` recomputed by `der_gap()` from the shuffled plays.
Inputs that are as of the game must leave every game dated on or before D bit-identical to an untampered run;
games after D must change, or the scramble did nothing. Both cutoffs are Mondays, so D's walk-forward week is
fit on games before D and every prediction dated on or before D must also be identical.

The untampered reference for a cutoff is the base run: `TAMPER_FROM` past the data, so nothing is shuffled but
`dder` comes from `der_gap()` exactly as in the tampered runs. Differences are exact (absolute value of the
difference of the stored doubles; 0 means bit-identical).

## No-op proof (TAMPER_FROM unset)

- Rebuilt features against `features.rds`: 22762 games, 67 of 67 columns equal under `all.equal`, `identical()` TRUE.
- Validation predictions against `predictions-v2-validation.csv`: 13045 games, 15 of 15 prediction and label columns equal under `all.equal`. The evaluation column `p_close` is not a model output: the frozen CSV predates the 2026-10-06 odds team-name fix (commit 6d2503c), so 123 more games now carry a closing line, and every game priced in both agrees to 0.
- `der_gap()` against `context.rds` (the frozen `dder`): max absolute difference 0 on 22761 games; base predictions against the none run, every model column: 6.1e-16 (the CSV keeps 15 significant digits).

## Results by cutoff

| cutoff D | mode | features: games on or before D | max abs feature diff | model inputs: max abs diff (d12 ... dder) | predictions on or before D | max abs diff M1-M5 | games after D: features changed | after D: M5 changed | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2019-07-01 | validation | 8,547 | 0 | 0 | 6,119 | 0 | 100.0% | 100.0% | PASS |
| 2024-07-01 | test | 19,168 | 0 | 0 | 3,695 | 0 | 100.0% | 100.0% | PASS |

Detail:

As first run (same outputs), the verdict read FAIL from two comparison errors, not leaks: the model-input check included the label y for games dated D, which the scramble shuffles by design, and the no-op check included `p_close`. Both are fixed in the comparison; no model, feature or tamper output changed.

- D = 2019-07-01 (validation mode, base vs tampered): outcome labels (vruns, hruns) identical before D: max diff 0; model inputs on 8546 games on or before D, per column d12 0, d3 0, dpen 0, drd 0, dder 0, drest 0, dmoved 0; outcome y before D: 0.
  Predictions on or before D, per column: M1_runs_ratio 0, M2_components 0, M3_plus_team 0, M4_plus_rest 0, M5_plus_defense 0, B_home 0, C_team_only 0, E_recency Inf, C_incumbent Inf, ENS Inf.
  Strictly before D: M1_runs_ratio 0, M2_components 0, M3_plus_team 0, M4_plus_rest 0, M5_plus_defense 0, B_home 0, C_team_only 0, E_recency 0, C_incumbent 0, ENS 1.2e-02. The 5 games dated D itself have shuffled final scores, which the E and C join key reads.
  After D: 100.0% of 14215 games' features changed; drd changed for 99.9% and dder for 100.0% of model rows; M5 changed for 100.0% of 6926 predictions (max abs 2.8e-01).
  Ensemble weight on the best variant (chosen on 2017-2019): base 0.55, tampered 0.55. Best variant (chosen on 2017-2022): base M5_plus_defense, tampered M3_plus_team.
- D = 2024-07-01 (test mode, base vs tampered): outcome labels (vruns, hruns) identical before D: max diff 0; model inputs on 19167 games on or before D, per column d12 0, d3 0, dpen 0, drd 0, dder 0, drest 0, dmoved 0; outcome y before D: 0.
  Predictions on or before D, per column: M1_runs_ratio 0, M2_components 0, M3_plus_team 0, M4_plus_rest 0, M5_plus_defense 0, B_home 0, C_team_only 0, E_recency Inf, C_incumbent Inf, ENS Inf.
  Strictly before D: M1_runs_ratio 0, M2_components 0, M3_plus_team 0, M4_plus_rest 0, M5_plus_defense 0, B_home 0, C_team_only 0, E_recency 0, C_incumbent 0, ENS 0. The 3 games dated D itself have shuffled final scores, which the E and C join key reads.
  After D: 100.0% of 3594 games' features changed; drd changed for 99.7% and dder for 100.0% of model rows; M5 changed for 100.0% of 3594 predictions (max abs 2.8e-01).
  Ensemble weight on the best variant (chosen on 2017-2019): base 0.55, tampered 0.55. Best variant (chosen on 2017-2022): base M5_plus_defense, tampered M5_plus_defense.

## Participation test (truncation)

The scramble keeps who played. This test removes it: every play and every game dated on or after D is dropped
(`TRUNCATE_FROM`) before the build, before the model's own inputs (team run margin, rest and travel, `der_gap()`),
and before the walk-forward. Starter length, bullpen usage, lineups and the schedule after D are then gone, not
shuffled. Every game dated before D must match the untampered base run exactly. Games dated D are dropped too,
because the actual-starter build reads the day's own starter from that game's plays.

A suspended game is the one place the cut falls inside a game: Retrosheet dates the game row on the day it started
and each play on the day it was played, so a game suspended before D and finished on or after D keeps its row but
loses its own later plays. Its lineup (the first nine batters in its plays) and everything built on it can then
differ. Those games are reported apart below, with both the all-games and the excluding-straddlers maxima.

| cutoff D | mode | games before D | straddling games | max abs feature diff: all / excl. | model inputs (d12 ... dder, y): all / excl. | predictions | max abs diff M1-M5: all / excl. | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2019-07-01 | validation | 8,542 | 1 | 0 / 0 | 0 / 0 | 6,114 | 0 / 0 | PASS |
| 2024-07-01 | test | 19,165 | 1 | 5.0e+00 / 0 | 7.9e-01 / 0 | 3,692 | 3.2e-01 / 0 | PASS excl. straddler |

- D = 2019-07-01: straddling DET201905190 (started 2019-05-19, finished 2019-09-06); differing none. M5 home win probability, base against truncated: DET201905190 0.360 vs 0.360.
- D = 2024-07-01: straddling BOS202406260 (started 2024-06-26, finished 2024-08-26); differing BOS202406260. M5 home win probability, base against truncated: BOS202406260 0.608 vs 0.439.

As first run, this comparison counted every game before D and read FAIL at 2024-07-01 on that one game. No other
game moved by any amount, so no play-dated input leaked across D; the difference is the straddling game's own
lineup read from its completion-day plays. That is an actual-lineup oracle property of the frozen v2 build,
recorded under Limits, and the comparison now shows such games apart instead of hiding them. The truncated
probability reflects a partial lineup (only the batters who came up on the start day), so it does not measure
how much the oracle is worth. Truncation drops rows by their own date, so it cannot see facts stored on a game
row dated at the start (the final score, the reached-on-error count); those are covered under Limits.

## Every other input matchup_model.R reads

- `context.rds` (`dder`): built from plate-appearance outcomes and reached-on-error counts, so it is not used under tamper; `der_gap()` recomputes it from the shuffled data (no-op proof above shows it reproduces the frozen file).
- Team run margin `drd`: from Retrosheet final scores, shuffled with the game scores and decayed as of the day before each game.
- Rest and travel (`drest`, `dmoved`): days since each team's previous game and whether the park changed. Schedule facts read backward only (`shift()` over each team's games in date order); no outcome enters.
- Run values (`rv_fit`): fit on 2015-2016 team-games, before both cutoffs; fixed.
- Recency model `E_recency` and incumbent `C_incumbent`: read from the frozen `results/recency/model-predictions-*.csv`, not regenerated here. They enter only the ensemble column `ENS` and the complete-case filter of the score tables, never M1-M5. E is a weekly walk-forward model with its own independent real-data tamper test (`RECENCY-PLAN.md`, iteration 8). Under tamper their join key, which matches StatsAPI games on date and final score, fails for most shuffled games after D, so after D the tampered run has fewer E rows; before D it is unchanged.
- Odds (`market-joined.csv`): evaluation only, never a model input; joined after the predictions are made.
- Inside the build: park factors and the batted-ball outcome mix use the three prior seasons, and every hitter, pitcher, league, starter-length and bullpen input is an as-of window; the tamper result above is the end-to-end check on all of them.

## Limits

- The scramble moves outcomes, not participation; the truncation test above covers participation by removing everything dated on or after D. Both tests run on the frozen v2 build (actual starters and lineups). The exploratory day-ahead, rotation and probable-starter builds share its as-of windows but were not rerun under either test.
- `E_recency`, `C_incumbent` and `ENS` are outside both tests: E and C are frozen CSVs, and ENS blends them.
- `ENS` is not part of M5. Its weight is chosen in sample on 2017-2019 and the best variant on 2017-2022 by design (`MATCHUP-PLAN.md`, iteration 5), so when D falls inside those seasons a tampered run may pick a different weight and `ENS` before D moves. That is a model-selection property recorded above, not a feature leak, but it makes validation-season scores for the best variant and ENS optimistic; only 2023-2025 is free of that selection.
- Suspended games (34 in 2015-2025 have plays on two dates). The v2 lineup for such a game is its first nine batters across all its plays, so it can include a batter whose first plate appearance came on the completion day: 10 of 68 team-lineups in 6 games do (some may be original starters who had not yet batted). v2 already reads actual lineups, so this extends a known oracle within the game. Separately, `drd` counts a suspended game's final score from the day it started: re-dating those scores to the completion day changes `drd` for 15,894 of 20,305 games in 2017-2025 by at most 0.132 runs (mean over all games 7.7e-04), and in the 2023-2025 test seasons by at most 0.113 (mean 5.9e-04). That look-ahead reaches other games, and the truncation test cannot see it, because the final score sits on the game row dated at the start.
- For the same reason, `der_gap()` (matchup.R) joins a game's whole reached-on-error count by game id onto each of its dated rows, so a suspended game's start-date row carries completion-day errors and the count is taken off both dates. BOS202406260 had none, so the truncation test does not exercise this path. Unmeasured beyond that game.
- The day-ahead lineup build (matchup_build.R, `LINEUP_MODE = "projected"`) picks each source game by its start date and copies that game's full lineup, so completion-day batters of a suspended game can enter later games' projected lineups. Not tested and not measured; v2 itself uses actual lineups.
- v2 is frozen, so all of the above are recorded, not fixed. The next pre-registered version should date suspended scores and errors on completion and take lineups from the start-day lineup card.
- Two cutoffs and one seed per cutoff.
- Independent review (2026-10-07) checked the comparison fixes above and the as-of boundaries: every window reads rows dated before the game (decayed sums on the day before, bullpen and lineup windows on earlier dates, weekly fits on earlier weeks).

## Runtime

Logged steps, minutes each (steps in a group ran side by side, on different days per group): build-2024 24, build-none 24, build-2019 24, model-none 6, model-2019 6, model-base-validation 7, model-base-test 9, model-2024 10, trunc-model-2019 20, trunc-model-2024 55.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
