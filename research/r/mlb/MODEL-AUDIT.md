# MLB model audit, 2026-09-17

Read against the code as it stands, not against the consolidation plan. The 5b rebuild split
a 604-line monolith into testable functions and that part holds up. What it did NOT do is
make the predictive half correct, because it deliberately preserved legacy arithmetic to keep
the diff honest. This file is the list of what that leaves.

Ranked by how much each one inflates a backtest.

## 1. The predictive half is not wired into the entry point (FIXED 2026-09-30)

Fixed by `walk_forward()` in `model.R` and `backtest.R`: `fit_win_model()` maps the predicted run
gap to `win_pct`, one row per game from the home side, and both `evaluate.R` consumers now run on it.
Original entry below.

`main()` in `run_season.R` runs ingest, features, and `add_expected_scores`, then writes
`mlb_games.csv`. It never calls `add_historical_predictions`. Nothing calls
`fit_expected_score`, `to_team_rows`, `evaluate_model` or `calibration_table` either, outside
the unit tests.

The consequence worth knowing: **`win_pct` is consumed by two functions in `evaluate.R` and
produced by nothing in the repo.** `win_rate_above` and `calibration_table` both filter on it.

**Corrected 2026-09-27.** This entry previously said running either on real pipeline output
gives "zero rows, not an error", i.e. a silent bug reading as "no qualifying games". That is
wrong, and it overstated the severity. Both functions reach the column through the `.data`
pronoun (`.data$win_pct`), which raises rather than returning `NULL`. Exercised against
dplyr on R 4.6.1, `dplyr::filter(df, !is.na(.data$win_pct), .data$win_pct > 0.55)` on a frame
with `score` and `win` and no `win_pct` returns:

```
In argument: `!is.na(.data$win_pct)`.
Caused by error in `.data$win_pct`:
! Column `win_pct` not found in `.data`.
```

So the failure is loud and names the missing column. The defect is real and item 1 stays
open, but it is an unwired capability, not a silent-wrong-number bug, and it does not need a
guard clause added on top of an error that already fires. Bare `win_pct` (no `.data`) would
have had the shape this entry described; the code does not use it.

So the honest status of the MLB track is: the feature pipeline runs, the model does not.

## 2. Look-ahead in the comparable lookup (FIXED 2026-09-17)

`comparable_outcomes()` took a `history` frame and searched all of it for games whose
`exscore` sat within `tol`. No date filter. Predicting a July game against a full season means
September games are eligible comparables, so the prediction is partly arithmetic on the answer
key, and every metric downstream of it is inflated.

Fixed by requiring an `as_of` date whenever `history` carries a `Date` column, and erroring
rather than defaulting when it is missing. An undated fixture stays exempt, because there is
no time to leak in one. Three tests cover it, including the negative control.

The guard errors instead of silently defaulting on purpose: the caller who forgets the date is
exactly the caller who ships a good-looking wrong number.

## 3. The shrinkage target is computed from the prediction set (FIXED 2026-09-30)

`add_historical_predictions()` now takes `population_mean` as an argument; `walk_forward()` passes
the mean realised score of team-games before the block.

In `add_historical_predictions`:

```r
home_pred = regress_to_mean(.data$home_pred, .data$home_p,
                            mean(.data$home_pred, na.rm = TRUE))
```

That population mean is taken over every row being predicted, the future ones included. Same
class of leak as 2, smaller magnitude. The fix is the same shape: compute the mean from games
before the as-of date, or from a fixed prior season, and pass it in.

## 4. Every reported fit is in-sample (FIXED 2026-09-30)

Every block is predicted from games before its Monday only, and a test scrambles everything
after the cutoff and asserts the prediction is unchanged. `EXPECTED_SCORE_COEF` turned out not
to reach a prediction at all: the comparables match on `raw_exscore()`, which has no coefficients.

`fit_expected_score()` fits `lm(score ~ expected_score)` on a frame and `evaluate_model()`
reports the R-squared of that same frame. There is no split, no holdout, no walk-forward.

`EXPECTED_SCORE_COEF` compounds it: those coefficients were fitted on 2016 to 2019 and are
carried forward verbatim, so scoring any of those seasons is scoring the training set.

For a game-by-game system the correct shape is walk-forward: refit on everything before date
`d`, predict `d`, step, and never let a fitted object see a date at or after the one it
predicts. That is also the natural home for the as-of parameter added in 2.

## 5. The 0.55 confidence threshold is selected on the data it is evaluated on (FIXED 2026-09-30)

`choose_threshold()` takes validation predictions only (2017-2018) and the test season is quoted
at that cutoff with n and a Wilson interval.

`win_rate_above(threshold = 0.55)`. Picking the cut and measuring the win rate above it on one
dataset overstates what that cut would have returned live. Choose it on a training slice, quote
it on a held-out one.

Credit where due: the rebuild already fixed the worst version of this. The legacy code printed
a bare percentage with no denominator, so 3-for-4 and 300-for-400 both read as 75 percent.
`n` is returned alongside the rate now.

## 6. Mean imputation over the full frame (FIXED 2026-09-30)

Split into `fit_means()` / `apply_means()`; each block is imputed with means from earlier games.

`impute_column_means()` fills NAs with the column mean over every row it is handed. Under a
walk-forward loop that mean must come from the training slice only. Preserved deliberately in
the rebuild to keep the coefficient diff against the original clean, which was the right call
then and is worth revisiting now.

## What is actually good here

Worth stating, because a list of defects reads as if nothing works.

- **The feature side is clean, and this is the part most people get wrong.** `fetch_rolling()`
  requests the trailing window `[d - window_days, d]` and stamps it `as_of = d + 1`, so a line
  is only known the morning after the window closes, and the feature joins key on that. There
  is no look-ahead in the inputs.
- Per-window `min_pa` filtering, rather than the legacy season-scale threshold applied after
  the loop, which had been filtering early-season windows against a full-season bar.
- `calibration_table()` is new and is the right check to have added. A model can carry a
  respectable R-squared on runs scored and still be badly calibrated on the win probability
  that actually gets acted on.
- Network failures no longer lose the run. The legacy loop had no error handling, so one API
  failure on day 84 cost the other 180 days.

## Suggested order

All done 2026-09-30 per [ACCURACY-PLAN.md](ACCURACY-PLAN.md). Two further defects surfaced while
building it and were fixed before any season was scored: each side read its own bullpen instead
of the opponent's, and the comparables matched the weighted score against the raw index.

Expect the headline numbers to get worse when 2 through 4 land. That is the point: the current
ones are measuring a model that can see the future.
