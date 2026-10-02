# MLB walk-forward backtest: 2019

Generated 2026-10-02 by `Rscript research/r/mlb/backtest.R 2016 2019 --test 2019`. Predictions: `data/mlb/backtest/predictions.csv`.

Threshold, chosen on validation games only (best favourite win rate among cutoffs covering at least 10% of games): **0.610**.

## Test 2019, scored once

| predictor | games | accuracy | log loss | Brier |
| --- | --- | --- | --- | --- |
| model | 2,429 | 59.7% | 0.6706 | 0.2390 |
| home team always | 2,429 | 52.9% | 0.6915 | 0.2492 |
| coin flip | 2,429 | 50.0% | 0.6931 | 0.2500 |

Edge over "home team always", 1,000 game resamples (positive = model better):

| metric | estimate | 95% interval |
| --- | --- | --- |
| accuracy gap | 0.0671 | [0.0440, 0.0906] |
| log-loss gain | 0.0209 | [0.0148, 0.0269] |

Favourites above the 0.610 threshold: 452 of 2429 games (18.6%), won 69.7%, Wilson 95% [65.3%, 73.7%].

Calibration, home win probability:

| bucket | games | predicted | actual | gap |
| --- | --- | --- | --- | --- |
| (0.2,0.3] |    2 | 29.7% | 50.0% | 20.3% |
| (0.3,0.4] |  126 | 36.8% | 27.0% | -9.8% |
| (0.4,0.5] |  699 | 46.4% | 42.5% | -3.9% |
| (0.5,0.6] | 1165 | 54.9% | 56.5% | 1.6% |
| (0.6,0.7] |  410 | 63.8% | 67.3% | 3.5% |
| (0.7,0.8] |   27 | 72.6% | 74.1% | 1.4% |

**Slide gate: PASS.** Needs the accuracy gap's 95% interval above zero (it is [0.0440, 0.0906]) and model log loss under home's (0.6706 vs 0.6915).

## Validation 2017-2018 (threshold chosen here)

| predictor | games | accuracy | log loss | Brier |
| --- | --- | --- | --- | --- |
| model | 4,861 | 56.7% | 0.6802 | 0.2436 |
| home team always | 4,861 | 53.4% | 0.6910 | 0.2489 |
| coin flip | 4,861 | 50.0% | 0.6931 | 0.2500 |

Edge over "home team always", 1,000 game resamples (positive = model better):

| metric | estimate | 95% interval |
| --- | --- | --- |
| accuracy gap | 0.0331 | [0.0179, 0.0484] |
| log-loss gain | 0.0108 | [0.0073, 0.0141] |

Favourites above the 0.610 threshold: 530 of 4861 games (10.9%), won 68.3%, Wilson 95% [64.2%, 72.1%].

Calibration, home win probability:

| bucket | games | predicted | actual | gap |
| --- | --- | --- | --- | --- |
| (0.3,0.4] |   87 | 37.5% | 27.6% | -9.9% |
| (0.4,0.5] | 1302 | 46.7% | 45.3% | -1.4% |
| (0.5,0.6] | 2821 | 54.6% | 55.0% | 0.4% |
| (0.6,0.7] |  635 | 62.5% | 65.5% | 3.0% |
| (0.7,0.8] |   16 | 71.2% | 81.2% | 10.1% |

## Coverage

- Games predicted: 7,290. Every final game is kept; nothing is dropped for thin data.
- Sides with no comparable past team-game (fell back to the training mean): 0.1%.
- Games with at least one score input imputed from earlier games' means: 20.9%. Most are the first ~16 days of each season, before a 15-day window exists.
- Both probable starters listed by StatsAPI: 99.9%. Mapped to a Baseball-Reference id via Chadwick: home 100.0%, away 99.9%.
- Starter has a trailing-window line (none on a first start or a return from injury): home 85.5%, away 86.1%.
- Team batting line joined: home 93.2%, away 93.2%. Bullpen line joined: home 93.2%, away 93.2%.

## Method

- Burn-in 2016 (training only). Validation 2017-2018. Test 2019. 2020 excluded.
- Each Monday-to-Sunday block is predicted from games before that Monday only: imputation means, the comparable pool, the shrink target and the win model are all refit per block.
- A side's predicted runs are the mean realised score of past team-games whose raw index sat within 5% of its own, shrunk toward the training mean by 0.2 + 0.5p when the Jarque-Bera p exceeds 0.05. All three constants are the legacy values, frozen before any season was scored.
- The comparables match on the raw index, which has no fitted coefficients, so the shipped EXPECTED_SCORE_COEF (fitted on 2016-2019) never reach a prediction. The plan's per-fold coefficient refit was therefore unnecessary.
- Win probability: logistic regression of home win on the predicted run gap and on the gap in season-to-date run differential per game (each side's runs scored minus allowed in this season's games before the block, over games played plus 20); the intercept carries home field. One row per game, home perspective.
- Chosen on validation, so validation rates flatter the model: the run-differential term (added after the first validation run showed the run gap alone tied home field, 53.3% vs 53.4%), its shrink of 20 games (fit 2017, scored 2018; flat from 10 to 40) and the threshold. The test season is the only clean number.
- Two rebuild defects were fixed before any season was scored: each side read its own bullpen instead of the opponent's, and the comparables matched the weighted score against the raw index (different units).
- The bootstrap resamples games independently. Games share teams and dates, so the true interval is if anything wider.

