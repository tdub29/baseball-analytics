# R: the MLB run-expectancy pipeline, before and after

Both versions are here on purpose. `legacy/projectbaseball_full_pipeline.R` is the original,
untouched. `mlb/` is the rebuild. Diffing them is the point.

```
legacy/projectbaseball_full_pipeline.R   604 lines, 1 file,  0 functions, 7 for loops
mlb/ingest.R  features.R  model.R  evaluate.R  run_season.R
tests/testthat/                          59 assertions, no network, green
ncaa_baseballr_export.R                  the NCAA export, unchanged
```

Run it:

```bash
Rscript research/r/mlb/run_season.R 2019
Rscript research/r/mlb/run_season.R 2016 2019 --out data/mlb
Rscript research/r/tests/testthat.R          # 59 pass, offline
```

## What was actually wrong, and what it cost

Six of these are structural. Three were live correctness or crash bugs, and one of those
three is the reason the original file carries a hand-written patch 280 lines after the
line that caused it.

### The `fill = TRUE` bug, and the patch it forced

The schedule loop accumulated one request per day:

```r
odf <- rbind(odf, f, fill = TRUE)
```

`fill` is `data.table` syntax. Base `rbind.data.frame` has no such argument, so `TRUE`
falls into `...` and is bound as **another row**, recycled across every column. Verified
by running it:

```
  game_pk           team
1  565000 Boston Red Sox
2       1           TRUE      <- injected, once per iteration
```

About 180 iterations a season means about 180 of those rows, all with `game_pk == 1`. The
dedupe two lines later (`duplicated(odf$game_pk)`) collapses them to exactly one, and 280
lines downstream the file carries:

```r
NEW <- filter(NEW, game_pk != 1)   #remove error row
```

The author saw the symptom and patched it by hand without finding the cause. The rebuild
collects into a list and binds once with `purrr::map_dfr`, which has no `fill` argument to
misuse, and `test-legacy-regressions.R` pins both the broken and the fixed behaviour so it
cannot come back.

### Two hard crashes on a clean run

| Line | What | Effect |
|---|---|---|
| 50 | `bref_daily_batter(day1, dayf)` | `dayf` is not defined until line 62, so a fresh session errors on the first pass |
| 543 | `baseball <- bbback` | `bbback` is never assigned anywhere in the 604 lines; the win-probability block cannot be reached |

Neither shows up if you run the file interactively top to bottom over several sessions with
objects left in the environment, which is how it was written. From `Rscript`, it stops.

### The rest

| Problem | Evidence in the original | Fix |
|---|---|---|
| No decomposition | 0 `function` definitions in 604 lines | five files, one job each; the three non-network ones are pure and testable offline |
| Quadratic accumulation | `rbind` inside a `while` over every day, 7 `for` loops total | collect into a list, `map_dfr` once |
| Hardcoded seasons | `currentyearcreating <- 2015`, then `+ 1` three lines later, so it actually ran 2016; `endyear <- 2019` was defined and never used | seasons are command-line arguments |
| Three dialects | base R, `dplyr` and `sqldf` all doing joins in one file | `dplyr` throughout, `sqldf` dependency dropped |
| Column-index surgery | `colnames(X)[93:118] <- ...`, `X <- X[,-154]`, `colnames(NEW)[150] = "Home Starter"` | prefixed joins on named keys, which cannot misalign when a source adds a column |
| 82 hand-written team lines, in two drifted copies | the batter copy mapped `San Diego NL` twice and never `San Diego AL`; `Cincinnati AL` and `Pittsburgh AL` existed only in the pitcher copy | one `TEAM_BY_CITY_LEAGUE` table plus a city-only fallback, used by both |
| Unguarded division | `H/AB`, `ER/IP` with no zero check | `safe_div` returns `NA`, because `Inf` survives `na.rm = TRUE` and poisons every downstream mean |
| No error handling | one API failure on day 84 lost the other 180 days | `safe_fetch` retries three times, then drops that day and keeps the run |
| `jarque.bera.test` on a thin set | errors below 3 values, inside a per-row loop | `normality_p` returns `NA` and the existing 0.75 default takes over |
| Filter applied at the wrong scale | `filter(df$PA > 100)` ran after the whole loop, so early-season windows were judged against a season-scale threshold | `min_pa` is a per-window argument |
| No tests | `tests/` held a README | 59 assertions, including one per named defect above |
| Right-assignment throughout | `select(...) -> opening` mixed with `x <- y` | consistent `<-` |

## What was deliberately NOT changed

The wOBA weights, the FIP constant, the three `expected_score` coefficients and the
`0.2 + 0.5p` shrinkage rule are carried over verbatim. They are fitted values from the
original 2016-2019 work, and changing them would change the numbers and break the diff
against the legacy file, which is the thing this directory exists to show. They are named
constants now (`WOBA_WEIGHTS_2013`, `FIP_CONSTANT`, `EXPECTED_SCORE_COEF`) rather than
literals buried mid-expression, so refitting is a one-line change when someone wants it.

`evaluate.R` adds one thing the original did not have: a calibration table. The legacy
file reported R-squared on score and a bare win rate with no denominator, so a 3-for-4
stretch and a 300-for-400 stretch printed the same number. A model can fit score well and
still be badly calibrated on the probability anyone would act on.
