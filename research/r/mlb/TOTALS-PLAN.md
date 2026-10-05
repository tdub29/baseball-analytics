# Plan: can a run-total model beat the closing over/under?

Charter v1, 2026-10-04, written before any totals model prediction was compared with a totals line
or with an outcome. Changes after a validation result is seen are logged at the bottom with the
reason; a change after the test is scored makes that result exploratory.

## Question

Game totals are usually thought softer than moneylines. Using the existing matchup features
(`features.rds`, MATCHUP-PLAN.md), does a model of total runs (1) forecast over/under outcomes
better than the no-vig sportsbook closing total, (2) add information the closing total does not
already hold, and (3) make money betting at the median closing price?

The prior is the same as for moneylines: the close is hard to beat and a null result is a valid
answer.

## Data

- Matchup features `data/mlb/matchup/features.rds`, one row per game 2016-2025: per side, expected
  outcome counts against the starter (first and second time through, third and later) and the
  bullpen, park-adjusted. Another process may rebuild this file; the run records its md5 and the
  test refuses to run on a different file (re-run validation first).
- Retrosheet 2015-2025 (with the Retrosheet notice): game info (temperature, wind, sky, scheduled
  innings, home-plate umpire, final score) and plate appearances (umpire tendency, run values).
- Odds: `data/mlb/raw/odds/mlb_odds_dataset.json`, opening and current totals per book. No license,
  private research only, kept under `data/mlb/raw/odds/` (gitignored). Only aggregates leave it.
  "Current" on a finished game is taken as the closing line. 2021-09-01 to 2021-12-31 is excluded
  (those current lines were scraped after first pitch, MARKET-PLAN.md it 2); the run repeats the
  sanity check per month for totals (closing log loss, line moves from the open) and logs anything
  else that looks scraped in-game.
- Join: odds game to Retrosheet game by date, final score and both teams, the team-code-to-name map
  by majority vote within each season (handles renames such as Cleveland in 2022). Same teams,
  same day, same score (ambiguous doubleheaders) are dropped, never guessed. Match rate reported.

## Model (fixed now)

1. **Expected runs per side.** Run values per outcome from 2015-2016 team-games (linear model of
   runs on outcome counts, as `matchup_model.R`), intercept kept. xr = intercept + sum over the
   starter (both passes) and bullpen expected counts of count x run value. Park is already in the
   counts.
2. **Environment.** Temperature (degrees minus 72; missing or implausible values and domes set to
   72); wind out (mph when blowing to left, center or right field), wind in (mph when blowing from
   them), crosswinds ignored, zero in domes; dome indicator (Retrosheet sky = dome, so a closed
   roof); seven-inning games (2020-2021 doubleheaders) as an offset log(innings / 9).
3. **Umpire.** Home-plate umpire's strikeout and unintentional-walk tendency as of the day before:
   per plate appearance he called, outcome minus the league rate as of that date (30-day calendar
   half-life), summed over his earlier games with each prior season weighted 0.75, shrunk by
   (n + 4000). Expressed in percentage points per plate appearance. Missing umpire: 0.
4. **Distribution.** Negative binomial, fit walk-forward: for each calendar week, fit on every game
   before that week's Monday (2016 onward), weights 0.5^(age in days / 365), predict that week.
5. **Games that end early.** A game with fewer innings than scheduled (last plate appearance before
   the ninth, or the seventh in a seven-inning game) is dropped from fitting and scoring: books
   void totals on it, and the model predicts complete games. The count is reported.
6. **Over/under.** For a total L: P(over) = P(T > L), P(under) = P(T < L), P(push) = P(T = L) on
   integer lines. The model's over probability is P(over) / (P(over) + P(under)), the probability
   of over given no push, which is what a no-vig price measures.

Candidates (the only structural tuning; chosen on 2021-2022 by over/under log loss, lowest wins):

| Candidate | Response | Predictors |
|---|---|---|
| T1 total, full | total runs | log(xr home + xr away), temperature, wind out, wind in, dome, umpire K, umpire BB, offset |
| T2 sides, full | runs per side, independent; total by convolution | log(xr side), home, the same environment and umpire terms, offset |
| T3 total, runs only | total runs | log(xr home + xr away), offset |

Reference, never selected: B, total runs with the intercept and offset only (league run level).

## Market (fixed now)

Per book: decimal prices from American odds (lines with |odds| under 100 or totals outside 4 to 16
dropped), no-vig over probability = (1 / over price) / (1 / over price + 1 / under price). The
game's line is the closing total quoted by the most books; on a tie, the one whose median no-vig
over probability is closest to 0.5 (the main line), then the lower. Market probability = median
no-vig over probability across books at that line. Betting prices = median over and under decimal
prices across those books. Best-of-books prices are not used (the moneyline study found stale
quotes among them).

## Split (fixed now)

| Role | Seasons | Use |
|---|---|---|
| Model calibration, no market | 2017-2020 outcomes (2016 is history) | reported, untuned |
| Tuning and market validation | 2021, 2022 (odds from 2021-04-01) | candidate choice, blend, betting threshold |
| Test, scored once | 2023, 2024, 2025 (odds to 2025-08-16) | frozen, owner scores later |

Validation never reads a 2023-2025 row: features, Retrosheet and odds are filtered to 2022 and
earlier before anything is computed.

## Validation report (`results/totals-validation.md`)

1. Calibration of total runs vs outcomes, 2017-2022, per season: mean predicted vs actual total,
   log score of the actual total for every candidate and B; deciles of the selected candidate's
   predicted mean with predicted and observed P(total over 8.5); predicted vs observed variance.
2. Market sanity per month 2021-2022 (including the excluded window, marked).
3. Over/under log loss on 2021-2022, pushes excluded: market vs every candidate and B, per season
   and pooled; for the selected candidate, the paired per-game difference (market minus model,
   positive = model better) with a home-team-season cluster bootstrap (2,000 draws) 95% interval.
4. Blend fit on 2021-2022: over ~ logit(market) + logit(model) (weight on the model; in-sample).
5. Betting: one unit on over when model minus market over probability is at least tau, on under
   when the same holds for under, at the median closing price; pushes refund. tau in {0.01, 0.02,
   0.03, 0.04, 0.05, 0.06, 0.08, 0.10}, every threshold reported (bets, overs, pushes, units,
   ROI). tau chosen by ROI among thresholds with at least 200 bets on 2021-2022; its in-sample ROI
   gets a week-block bootstrap interval and is optimistic by construction.

## Decision rules for the test (fixed now)

Scored once by `Rscript research/r/mlb/totals_study.R test` (refuses to overwrite
`results/totals-test.md`), with the candidate, tau and blend frozen from 2021-2022.

- **Beats the closing total** only if the pooled 2023-2025 paired log-loss difference (market minus
  model) has its 95% home-team-season cluster interval above zero. Otherwise "does not beat the
  closing total", with the numbers.
- **Adds information** only if the frozen blend's log-loss gain over the market alone on 2023-2025
  has its 95% cluster interval above zero.
- **Profitable** only if, at the frozen tau and median closing prices, the pooled 2023-2025 ROI has
  its week-block bootstrap 95% interval above zero AND ROI is positive in at least 2 of the 3 test
  seasons. Fewer than 100 test bets means no profitability claim either way.
- Calibration of total runs on 2023-2025 is reported descriptively; it decides nothing.
- Anything else is reported as "does not beat the market".

## Iteration log

- 2026-10-04, it 1: charter written after inspecting the odds schema (totals per book with opening
  and current total, over and under odds; 6 books; about 42% of book lines are whole numbers, so
  pushes matter) and the feature columns, before any model or market number was computed.
- 2026-10-04, it 2: validation run (`results/totals-validation.md`, features.rds md5 67b60417...).
  Two report-only fixes after the first run, no model, market or selection change: table rows
  printed one cell per line, and "model mean minus line" (+0.61 runs) was misleading on its own
  because a right-skewed count's mean sits above the median the line targets, so the actual,
  market and model over rates are now printed beside it. Selected T2 (0.6943 vs T1 0.6945 on
  2021-2022); pooled it trails the no-vig close 0.6919 by 0.0023 [-0.0059, +0.0013] (2021 better,
  2022 worse: the walk-forward run level lagged the 2022 scoring drop by about 0.4 runs a game).
  Chosen tau 0.10. Data findings: odds start 2021-04-01, not 2021-03-20; Sept-Oct 2021 totals
  also look partly in-game (6-9% of lines moved 1.5+ runs from the open vs under 1% in other
  months, lower closing log loss), confirming the exclusion. Charter frozen for the test as is.
- 2026-10-04, it 3: run-environment fix, tuned on 2017-2020 only. The it 2 calibration table
  confirms the lag: T2 mean total minus actual was -0.06 (2017), +0.28 (2018), -0.35 (2019),
  +0.12 (2020), -0.07 (2021), +0.40 (2022), each against the sign of that season's change in league
  scoring, roughly half of the change missed. Charter v1 fits were already weighted
  0.5^(age / 365), not equally, so the lag is a one-year half-life meeting offseason shifts (ball,
  rules) that as-of data cannot see until games are played. Added `totals_study.R tune` (reads
  nothing after 2020 and no odds) with a 10-config grid and rule fixed before the run: fit-weight
  half-life H in {365, 180, 120, 90, 60, 30} days, or H 365 plus an as-of league runs per nine
  scheduled innings predictor, log(level / 9), calendar half-life h in {15, 30, 60, 120} days
  (`decay_sum`, games before the date only, Retrosheet 2015 onward), in T1, T2 and T3 (B
  unchanged); highest pooled 2017-2020 T2 log score of the actual total wins. Shorter fit weights
  remove the per-season bias (H 60: within 0.21 runs every season) but score worse because the
  slopes get noisy (H 60 -2.8813, H 30 -2.8883, v1 -2.8791). Chosen: H 365, h 15
  (`results/totals-tune.md`), -2.8789 vs -2.8791, paired gain +0.00025 [-0.00029, +0.00081]
  (week-block bootstrap 95%, 8,168 games): within noise. Bias left 2018 +0.26, 2019 -0.21, 2020
  +0.15; the league-level coefficient in the last fit is 0.33, so about a third of a level shift
  carries. Frozen in the script as FIT_H 365, LRPG_H 15. Validation rerun (same features.rds md5
  67b60417...): T2 still selected (0.6943 vs T1 0.6945); 2022 bias +0.40 to +0.31 runs, 2021
  -0.07 to -0.10; over/under log loss 2021 0.6899 (was 0.6894), 2022 0.6978 (was 0.6983), pooled
  0.6943 vs the no-vig close 0.6919, market minus model -0.0023 [-0.0055, +0.0009] (it 2: -0.0023
  [-0.0059, +0.0013]). Blend gain +0.0018 [+0.0005, +0.0032], in-sample. Betting: ROI negative
  for tau 0.01-0.03, flat at 0.04, positive from 0.05; tau 0.10 chosen again, 446 bets, +20.8
  units, ROI +0.047 [-0.034, +0.129] week-block (2021 +0.116, 2022 +0.003), in-sample and
  optimistic. 2021-2022 rule check: does not beat the close, adds information, not profitable.
  Conclusion: the lag is mostly not forecastable as of the game from league scoring; the fix
  narrows it without moving the market comparison. Charter re-frozen for the test with this
  specification (the test reads FIT_H and LRPG_H from the script).
