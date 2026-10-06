# Plan: 2026 forward test, written before any 2026 row is scored

Charter v1, 2026-10-05. The 2023-2025 test is spent (MATCHUP-PLAN.md it 6). The 2026 regular season
is the only data no choice has touched. No model in this repo has been scored on it.

## Data

- Plate appearances and games: MLB StatsAPI live feeds via `statsapi_pa.R` (2,429 final games,
  183,304 PAs). Parity with Retrosheet 2025 is 100% on scores, PA counts and outcomes
  (`results/statsapi-parity-2025.md`). Retrosheet 2026 replaces it if released before scoring.
- Odds: none. The only odds dataset used here (ArnavSaraogi/mlb-odds-scraper, scraped from
  SportsBookReview) has one release, ending 2025-08-16, and SportsBookReview's terms forbid
  scraping, so this repo does not scrape a 2026 copy. The 2026 test is scored on outcomes only. If
  a licensed source is approved later, the market rules below apply unchanged, and the source and
  its terms are recorded here first.

## Models (frozen before scoring; the commit hash is recorded at scoring time)

1. **v2**: `features.rds` recipe (`PIT_SC=0`, `HIT_X=0`, posted lineups), M5 by 2017-2022
   selection, walk-forward weekly refit exactly as in the 2023-2025 test, extended through 2026.
2. **v2 day-ahead**: the same with `LINEUP_MODE=projected`.
3. **v4**: frozen 2026-10-06 and amended the same day (MATCHUP-PLAN.md it 8,
   `results/matchup-model-v4-validation.md`): `K_SET=v4` in `matchup_build.R` (`M_PIT_V4 = 8`,
   `M_BAT_V4 = 8`, `M_REL_BB_V4 = 1` in matchup.R; `SWITCH=0`, `BB_REGIME=0`), `RECAL=0` in
   `matchup_model.R`, posted lineups, otherwise as v2. On 2017-2022 validation it is within 0.0002
   of v2 (2021-2022 +0.00013 [+0.00002, +0.00027], selected on those seasons, all of it from 2021),
   so it joins this forward test only.
4. Baselines: home field only, team run margin only, S4 (`sabr_baseline.R`).

No 2026 result may change a model, a threshold or a recipe. Bugs found during scoring are fixed,
reported, and both the as-run and corrected numbers are published.

## Metrics and decision rules (fixed now)

- Primary: pooled 2026 log loss vs outcomes, paired home-team cluster bootstrap (1,000 draws, seed
  20261005), each model vs each baseline and v4 vs v2.
- v4 replaces v2 as the default only if the paired 2026 interval favors it.
- Secondary: calibration slope, Brier score, accuracy at 50%.
- With odds: "matches or beats the close" only if the paired interval says so; closing-line value
  at the open is the skill test; "profitable" only with a week-block ROI interval above zero.

## Iteration log

- 2026-10-05: charter written. 2026 data fetched and parity-checked; nothing scored.
- 2026-10-06: odds decision recorded: no 2026 source, outcomes only (Data section).
- 2026-10-06: v4 frozen as tuned k plus `SWITCH=1`, then amended to tuned k only after review found
  SWITCH's validation result predated the keep rule. No 2026 outcome had been scored or read; no
  2026 prediction file existed for any matchup model.
