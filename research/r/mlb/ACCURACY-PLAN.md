# Plan: one honest out-of-sample MLB accuracy number

Written 2026-09-30. Closes the open items in [MODEL-AUDIT.md](MODEL-AUDIT.md) (#1, #3, #4, #5, #6).

## Goal

A game-by-game win prediction for one full season that the model never saw, scored against a
baseline, with the count of games beside every rate. If it beats home field, it can go on the
twhite.dev Sports Modeling slide. If it does not, that is the answer and the slide stays as is.

Expect the number to be modest. The pitching features correlate with runs at under 0.09, the home
team wins about 53% of MLB games (the harness computes the exact figure), and the betting-market
favorite is commonly cited at roughly 57 to 59% (not verified here). A clean 54% beats a leaky 60%.

## Season split (settles the 2015-2019 vs 2019-2023 drift in the docs)

| Role | Seasons | Use |
|---|---|---|
| Burn-in | 2016 | training only, nothing predicted |
| Validation | 2017, 2018 | walk-forward predictions; tune `tol`, the shrink constants and the threshold here |
| Test | 2019 | walk-forward predictions, **scored once** |

2020 (60 games) is excluded. 2019 is the test year even though the shipped `EXPECTED_SCORE_COEF`
was fitted on 2016-2019, because the comparables match on the raw index, which has no fitted
coefficients, so those values never touch a 2019 prediction (found while building step 3). If anything is changed after the 2019 score is seen, 2019 is
spent and the fresh test becomes 2021-2023. Update the README season ranges to match this table.

## Done when

1. `Rscript research/r/mlb/backtest.R 2016 2019 --test 2019` writes `data/mlb/backtest/predictions.csv`
   (one row per game, home perspective) and `results/backtest-2019.md`.
2. Every 2019 prediction for date d used only games before d, and a test proves it (step 6).
3. The report has, for 2019: n games, accuracy, log loss, Brier, a calibration table, and win rate
   above the frozen threshold with n and a 95% interval, each beside the home-team and coin-flip baselines.
4. The 59 existing tests plus the new ones pass offline.

## Steps

**0. Make it runnable (~20 min).** R 4.6.1 is installed at `C:\Program Files\R\R-4.6.1\bin\Rscript.exe`
but is not on PATH. Confirm `Rscript research/r/tests/testthat.R` is still 59 green before touching code.

**1. Cache the raw pulls (~1 h code, ~2 h unattended fetch).** Nothing is cached today, and
`fetch_daily_batting` / `fetch_daily_pitching` hit Baseball-Reference once per day per season,
which throttles at about 20 requests a minute and locks you out for an hour past that. Wrap the
`fetch` argument of `fetch_rolling()` so each (source, date) lands once in `data/mlb/raw/<source>/<date>.rds`
and is read from disk after that. As built: an 8 s pause between live Baseball-Reference calls
(3.5 s still tripped the hour-long lockout), about 1,460 calls for four seasons, and the probables
come from one StatsAPI schedule call per season with `hydrate=probablePitcher` instead of ~9,700
`mlb_probables` calls. `Rscript research/r/mlb/fetch_cache.R batter|pitcher|mlb 2016 2019` fills
it; a rerun resumes from the cache, and failed calls are never cached.

**2. Produce `win_pct` and wire the model in (audit #1, ~1 h).** Nothing maps predicted runs to a
win probability today, which is why `win_rate_above()` and `calibration_table()` error. Add
`fit_win_model(train)` = `glm(home_win ~ home_advantage, family = binomial)` (the intercept carries
home field) and `predict_win_pct(model, games)`. Score one row per game from the home side. The
current `to_team_rows()` counts every game twice as mirrored rows, which doubles n and makes the
calibration table symmetric by construction, so it stays for the score model only.

**3. Walk-forward harness (audit #3, #4, #6, ~3 h).** `backtest.R` drives
`walk_forward(games, predict_seasons, block = "week")` in `model.R`. For each weekly block starting on date d:

- `train` = every game with `Date < d` (prior seasons plus earlier this season); `test` = the block.
- Impute `test` with column means from `train` only. Split `impute_column_means()` into
  `fit_means(train)` and `apply_means(df, means)`.
- ~~Refit the expected-score coefficients on `train`.~~ Dropped: the comparables match on
  `raw_exscore()`, which has no coefficients, so `EXPECTED_SCORE_COEF` never reaches a prediction.
- `comparable_outcomes(..., history = train, as_of = d)`; the guard from audit #2 already enforces this.
- Shrinkage target = mean realised score in `train`, passed into `add_historical_predictions()`
  as an argument instead of `mean(.data$home_pred)` over the prediction set.
- Fit the step 2 win model on `train` predictions, predict `test`.

Weekly refits with the cutoff at the block start carry no look-ahead and are ~7x cheaper than daily.

**4. Pick the threshold out of sample (audit #5, ~30 min).** `choose_threshold(validation_preds, min_share = 0.10)`
takes the 2017-2018 predictions only, returns the cutoff with the best win rate among cutoffs that
still cover at least 10% of games, and that value is written to the report before 2019 is scored.
Quote 2019's win rate above it with n and a Wilson 95% interval.

**5. Metrics and baselines (~1 h).** `score_predictions(preds)` in `evaluate.R` returns n, accuracy,
log loss and Brier for the model, for "home team always wins" (constant probability = the training
home win rate) and for 50/50 (log loss 0.693). Add a 1,000-resample bootstrap over games for the
accuracy and log-loss gaps against the home baseline. Point `calibration_table()` at the per-game frame.

**6. Tests (offline, ~1 h).** The one that matters is the leak test: build a small dated fixture,
predict date d, then delete or scramble every row after d and assert the prediction for d is
identical. Also: the shrink target and the imputation means change when only training rows change
and not when only test rows change; `win_pct` is in [0, 1]; `choose_threshold()` has no argument
that could receive test rows.

**7. Run, report, decide (~30 min).** Run validation, freeze every setting, score 2019 once, write
`results/backtest-2019.md`, commit. Then add a line to MODEL-AUDIT.md closing items 1, 3, 4, 5, 6.

## Slide gate

The number goes on slide 3 only if 2019 accuracy beats the home-team baseline with the bootstrap 95%
interval on the gap above zero, and log loss beats the baseline too. Caption form:
"54.1% on 2019, walk-forward out of sample, 2,430 games" (numbers illustrative). Otherwise the slide
keeps the rebuild-and-tests story it tells today.

Total: about 8 hours hands-on plus the unattended fetch.
