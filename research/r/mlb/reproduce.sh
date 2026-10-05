#!/usr/bin/env bash
# Rebuild every committed MLB result in research/r/mlb/results/ from raw data, in dependency order.
#
#   bash research/r/mlb/reproduce.sh            # from anywhere; cd's to the repo root
#   RSCRIPT="/c/Program Files/R/R-4.6.1/bin/Rscript.exe" bash research/r/mlb/reproduce.sh   # Windows
#
# Needs: R 4.6 with dplyr, purrr, data.table, jsonlite, baseballr, testthat, ggplot2, scales; bash, curl, GNU date
# (fetch_statcast.sh uses `date -d`). Sources, terms and known gaps: DATA.md. Every fetch is
# resumable and cached under data/mlb/raw/ (gitignored); a rerun reads the cache and only fills holes.
#
# TEST STEPS REFUSE TO RERUN ONCE SCORED. The scripts below stop with an error if their test output
# already exists: backtest.R --test, recency_study.R test (results/recency/test-components.csv),
# recency_model.R test, matchup_model.R test, totals_study.R test (no override; it also refuses when
# features.rds differs by md5 from the file its validation used). --force exists on the first four
# and turns the test seasons into validation seasons, so it is never passed here. market_study.R has
# no guard of its own but scores 2023-2025, so this script treats it the same way. `scored` below
# skips any step whose output is already committed and moves on using the committed file.
#
# Bit-identical rebuilds need the same raw files: results/data-audit.md section 0 records an md5 per
# source. A fresh fetch can differ (Retrosheet corrections, StatsAPI and Chadwick updates).
#
# Not rebuilt here (history, written by earlier code; check out the commit to rerun):
#   results/matchup-model-validation-v1.md      5b5d325  (v1, before the platoon and batted-ball fixes)
#   results/matchup-model-validation.md         3b97332  (overwritten by step 5c; `git checkout` it back)
#   results/matchup-model-v3-validation.md, -v3h-validation.md, -v3-dayahead-validation.md
#                                               fb3f5b7  (Statcast ablation, PIT_SC / HIT_X; MATCHUP-PLAN.md it 4)
#   results/market-study-v1-asrun.md            7d254ee  (first market run, before the Sept-Oct 2021 exclusion)
#   results/recency-study.md                    written by hand from results/recency/*.csv
# research/r/mlb/reliability.R is not committed, so its outputs are not part of this rebuild.
set -euo pipefail
cd "$(dirname "$0")/../../.."
R="${RSCRIPT:-Rscript}"
M=research/r/mlb
RES=$M/results
scored() {   # scored <output that marks it as scored> <command...>
  local out="$1"; shift
  if [ -e "$out" ]; then echo "skip (already scored, refuses to rerun): $out"; else "$@"; fi
}

# --- 1. fetch (network, resumable) -------------------------------------------------------------------
# StatsAPI season dates + schedule with probables (backtest) + Chadwick register (MLBAM to bbref/Retrosheet ids)
"$R" $M/fetch_cache.R mlb 2016 2019
# Baseball-Reference 15-day windows, 2016-2019 only (backtest); paced at 8 s a call, slow
"$R" $M/fetch_cache.R batter 2016 2019
"$R" $M/fetch_cache.R pitcher 2016 2019
# StatsAPI teams, rosters, team and player game logs, schedule with scores, probables, posted lineups
"$R" $M/fetch_gamelogs.R 2015 2025
# Retrosheet per-season CSV zips (retro.R unzips on demand)
mkdir -p data/mlb/raw/retrosheet
for y in $(seq 2015 2025); do
  f=data/mlb/raw/retrosheet/${y}csvs.zip
  [ -s "$f" ] || curl -sf --retry 3 -o "$f" "https://www.retrosheet.org/downloads/$y/${y}csvs.zip"
done
# Baseball Savant batted balls, one CSV per week
bash $M/fetch_statcast.sh 2015 2025
# Odds: SportsBookReview scrape, no license, private research only; stays in data/mlb/raw/odds (gitignored)
mkdir -p data/mlb/raw/odds
[ -s data/mlb/raw/odds/mlb_odds_dataset.json ] || curl -sfL -o data/mlb/raw/odds/mlb_odds_dataset.json \
  https://github.com/ArnavSaraogi/mlb-odds-scraper/releases/download/dataset/mlb_odds_dataset.json

# --- 2. validate code and data -----------------------------------------------------------------------
"$R" research/r/tests/testthat.R                 # offline unit and leak tests
"$R" $M/data_audit.R                             # results/data-audit.md

# --- 3. walk-forward backtest (ACCURACY-PLAN.md; Baseball-Reference windows) --------------------------
"$R" $M/backtest.R 2016 2018                                              # results/backtest-validation.md
scored $RES/backtest-2019.md "$R" $M/backtest.R 2016 2019 --test 2019     # test, 2019

# --- 4. recency study (RECENCY-PLAN.md; StatsAPI game logs). Env SMOKE=1 shrinks the grid: leave unset.
"$R" $M/recency_study.R                          # results/recency/*-validation.csv
"$R" $M/recency_model.R validation               # results/recency-model-validation.md, model-predictions-validation.csv
scored $RES/recency/test-components.csv "$R" $M/recency_study.R test      # test, 2021-2025
scored $RES/recency-model-test.md "$R" $M/recency_model.R test            # test; writes model-predictions-test.csv

# --- 5. market and matchup (MARKET-PLAN.md, MATCHUP-PLAN.md; Retrosheet, odds) ------------------------
# 5a. E vs the closing line; also writes data/mlb/raw/odds/market-joined.csv, which 5c reads
scored $RES/market-study.md "$R" $M/market_study.R
# 5b. features. matchup_build.R env: HIT_X (default 0), PIT_SC (0), LINEUP_MODE (posted), FEAT_OUT
"$R" $M/matchup_build.R                                                   # data/mlb/matchup/features.rds (v2)
LINEUP_MODE=projected FEAT_OUT=data/mlb/matchup/features-v2-dayahead.rds "$R" $M/matchup_build.R
# 5c. context.rds and matchup_model.R need each other: context_features.R writes context.rds, then its
#     ablation reads predictions-validation.csv, which matchup_model.R (no OUT_TAG) writes and which
#     reads context.rds. On a cold start the first call writes context.rds and stops at the ablation.
"$R" $M/context_features.R || [ -s data/mlb/matchup/context.rds ]
"$R" $M/matchup_model.R validation               # untagged: predictions-validation.csv (overwrites matchup-model-validation.md)
"$R" $M/context_features.R                       # results/context-ablation.md
# 5d. matchup_model.R env: OUT_TAG (suffix of the result name), FEAT_IN (default data/mlb/matchup/features.rds)
OUT_TAG=-v2 "$R" $M/matchup_model.R validation
OUT_TAG=-v2-dayahead FEAT_IN=data/mlb/matchup/features-v2-dayahead.rds "$R" $M/matchup_model.R validation
scored $RES/matchup-model-v2-test.md env OUT_TAG=-v2 "$R" $M/matchup_model.R test
scored $RES/matchup-model-v2-dayahead-test.md env OUT_TAG=-v2-dayahead \
  FEAT_IN=data/mlb/matchup/features-v2-dayahead.rds "$R" $M/matchup_model.R test
# 5e. OPTIONAL robustness, exploratory (after the test was scored; decides nothing). Run with ROBUST=1.
#     matchup_build.R env: STARTER_MODE actual|rotation ("rotation" guesses the starter from the team's
#     starts two days out instead of taking the actual one); ASOF_LAG 0|1 (1 stops every as-of input two
#     days before the game). Features built with ASOF_LAG=1 carry it as an attribute and matchup_model.R
#     lags its own team inputs to match, so ASOF_LAG is not passed to the model step.
#     These two variables are in the working-tree matchup_build.R / matchup_model.R as of 2026-10-05;
#     a checkout without them stops at the first command.
if [ "${ROBUST:-0}" = 1 ]; then
  LINEUP_MODE=projected STARTER_MODE=rotation FEAT_OUT=data/mlb/matchup/features-v2-dayahead-rot.rds \
    "$R" $M/matchup_build.R
  LINEUP_MODE=projected STARTER_MODE=rotation ASOF_LAG=1 FEAT_OUT=data/mlb/matchup/features-v2-dayahead-rotlag.rds \
    "$R" $M/matchup_build.R
  scored $RES/matchup-model-explore-rot-test.md env OUT_TAG=-explore-rot \
    FEAT_IN=data/mlb/matchup/features-v2-dayahead-rot.rds "$R" $M/matchup_model.R test
  scored $RES/matchup-model-explore-rotlag-test.md env OUT_TAG=-explore-rotlag \
    FEAT_IN=data/mlb/matchup/features-v2-dayahead-rotlag.rds "$R" $M/matchup_model.R test
fi

# --- 6. totals (TOTALS-PLAN.md; features.rds, Retrosheet, odds) ---------------------------------------
"$R" $M/totals_study.R tune                      # results/totals-tune.md, reads nothing after 2020
"$R" $M/totals_study.R validation                # results/totals-validation.md, records features.rds md5
scored $RES/totals-test.md "$R" $M/totals_study.R test

# --- 7. figures for REPORT.md (needs ggplot2, scales). Reads the predictions-v2-*.csv from 5d (the test
#     CSVs exist only if 5d's test steps ran on this machine) and the local odds joins; it re-derives the
#     committed headline numbers and stops if any has drifted.
"$R" $M/figures.R                                # results/figures/*.png

echo "done; compare with: git status --short $RES"
