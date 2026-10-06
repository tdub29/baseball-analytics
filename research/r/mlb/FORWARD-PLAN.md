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
- 2026-10-06: forward predictions written (`matchup_model.R forward` for v2, v2 day-ahead and v4;
  `FORWARD=1 sabr_baseline.R` for S4), 2,429 games each. Each run reproduces its earlier
  2017-2025 predictions exactly and every pre-2026 feature row is unchanged, so 2026 adds rows
  without touching history. A pre-scoring leakage review found no 2026 input dated on or after
  its game. No 2026 metric has been computed. The scored files, by sha256:
  - `predictions-v2-forward.csv` sha256 `3f5e9ce682e690709bbe175b509d55bcdf282ae35f8ca87472f07b20fc7f102d`
  - `predictions-v2-dayahead-forward.csv` sha256 `38dfb27406c949597a4368acd24e639179894920069499a64bf6a97f1b954c26`
  - `predictions-v4-forward.csv` sha256 `8a27a230805d51817e63ebfa9fd9fea5be86b66fe6b0fe5b789d238fa2e59067`
  - `sabr-predictions-forward.csv` sha256 `159c21f574ada21d94fb17b1db15ac76ea9f1cf2913c910344dcf7dfa0f00434`

  `forward_score.R` refuses to score if a hash differs or the model code is uncommitted.
  Retrosheet has not released the 2026 season as of 2026-10-06 (its 2026-08-09 release covers
  1897, 1908-1909, the Negro Leagues and corrections to 1910-2025), so StatsAPI stays the 2026
  source. Known simplifications (the first two also hold in the 2023-2025 test): a suspended game carries its
  original date; v2 and v4 use the posted lineup, which is the actual first nine, so their
  decision time is first pitch (v2 day-ahead uses projected lineups); 6 games at a venue with no
  Retrosheet park id (StatsAPI venue 5355) get a park factor of 1.
