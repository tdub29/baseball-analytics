# Plan: can the game-by-game model beat the betting market?

Charter v1, 2026-10-04, written before any model prediction was compared with a betting line.
Changes after a market result is seen are logged at the bottom with the reason; a change after the
test is scored makes that result exploratory.

## Question

Against the sportsbook closing line, does the frozen recency model (E, `recency_model.R`, frozen at
5899385) (1) predict MLB winners better, (2) add information the line does not already hold, and
(3) make money betting at the closing prices it would actually have to take?

The honest prior: the closing line is the hardest baseline in sports. Matching it would already be
strong; a null result is a valid answer and is reported as such.

## Data

- Odds: `ArnavSaraogi/mlb-odds-scraper` release dataset (SportsBookReview scrape): opening and
  current moneylines from FanDuel, DraftKings and Bet365, 2021-03-20 to 2025-08-16. No license is
  stated, so it is used for private research only and never committed or redistributed; it lives
  under `data/mlb/raw/odds/` (gitignored). "Current" on a finished game is taken as the closing line
  and checked for sanity (implied probabilities sum above 1, closing log loss in the usual range).
- Model: E's walk-forward predictions for 2021-2025 (`results/recency/model-predictions-test.csv`),
  made before any odds were loaded. No refit for Q1.
- Join: StatsAPI game to odds game by date and both team names; doubleheaders by start time. The
  match rate is reported; unmatched games are listed, never imputed.

## Market probability

Per book: decimal price from American odds, implied p = 1 / decimal, vig removed by normalising the
two sides to sum to 1. Consensus = mean of the books' no-vig home probabilities. Prices taken for a
bet are the best available closing price for that side across the three books.

## Decision time

E predicts at first pitch (posted lineups, actual starter). The closing line is also set at first
pitch, so the close is the fair comparison and betting at closing prices is realistic. The opening
line is not: E would know lineups the opener did not. Opening-line results are descriptive only.

## Split (fixed now)

| Role | Games | Use |
|---|---|---|
| Q1, no tuning | every matched game 2021-03-20 to 2025-08-16 | E vs the no-vig close, as is |
| Market validation | 2021, 2022 | choose blend form and the betting threshold |
| Market test, scored once | 2023, 2024, 2025 (to 2025-08-16) | everything frozen, reported per season |

## Tests and metrics

1. **Q1 forecast.** Log loss (primary), Brier and accuracy of E vs the no-vig consensus close, per
   season and pooled; paired per-game log-loss difference with a team-season cluster bootstrap.
2. **Q2 information.** On 2021-2022 fit `logit(p) = a + b logit(market) + c logit(E)`; score it on
   2023-2025 against the market alone. E adds information only if the test log-loss gain's 95%
   interval is above zero.
3. **Q3 betting.** Bet one unit on a side when E's probability exceeds that side's no-vig close
   probability by at least tau, at the best closing price across books. tau from {0.01, 0.02, 0.03,
   0.04, 0.05, 0.06}, chosen on 2021-2022 by ROI among thresholds with at least 200 bets. Test ROI on
   2023-2025 with a week-block bootstrap 95% interval; bets, wins and units reported per season.
   A second rule, fractional Kelly at 0.25, is reported alongside and never chosen between after
   the test.

## Decision rules (fixed now)

- "Beats the closing line" is claimed only if Q1's pooled log-loss difference has its 95% interval
  in E's favour.
- "Adds information to the line" only if Q2's test interval is above zero.
- "Profitable" only if Q3's test ROI interval is above zero in pooled 2023-2025 and the ROI is
  positive in at least 2 of the 3 test seasons.
- Anything else is reported as "does not beat the market", with the numbers, on the site too if the
  slide mentions the market at all.

## Next model work (only if Q2 shows room)

Candidate inputs tuned on 2021-2022 against the market, never on 2023-2025: handedness splits for
lineup vs starter, park, weather, travel and rest, bullpen roles (closer and setup usage). Each change gets its own
log line; the 2023-2025 test is scored once for the final model.

## Iteration log

- 2026-10-04, it 1: charter written; odds dataset downloading. No model prediction has been
  compared with any line yet.
- 2026-10-04, it 2: first run (`results/market-study-v1-asrun.md`) failed the charter's sanity
  check: Sept-Oct 2021 "current" lines were scraped after first pitch (36% moved over 15 points
  from the open; closing log loss 0.52 and 0.40). Excluded that window (394 games) and reran
  (`results/market-study.md`); results depending on validation choices are exploratory.
  Q1: the no-vig close beats E in every season, pooled 0.6722 vs 0.6751, E minus close -0.0029
  [-0.0042, -0.0015]. Q2: E adds nothing to the line (blend weight 0.08, test gain -0.00013
  [-0.00041, +0.00012]). Q3 as specified (tau 0.06, best closing price across books) shows +16% ROI
  on 600 test bets, but the audit says artifact: 18.5% of those bets took a "best" price over 10%
  above the fair no-vig price (stale or off-market quotes in scraped data); at the fair price the
  ROI is +4.3% (about one standard error); actual wins 278 vs 264 the close expected; and the close
  moved away from the model's side by 3.6 points on average (negative closing-line value). Verdict:
  does not beat the market. No profitability claim.
