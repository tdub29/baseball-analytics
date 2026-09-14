# Baseball consolidation plan

**Goal:** one public repo that showcases the baseball work optimally. It spans **both MLB and
NCAA**, so the name and the layout must too. Today the work is split across three places, the
flagship has never been pushed, and the two repos that *are* public are the two smallest pieces.

Measured 2026-09-12. Every line count below excludes `.venv`, `__pycache__`, `node_modules`,
and the mirrored skill trees.

**Decisions Trevor made 2026-09-12**, recorded here so nobody re-litigates them:

- Real data going public is **fine**. No synthetic-fixtures-only constraint.
- Using **USD** branding, names and data anywhere is **fine**.
- Everything else is the implementer's call.

---

## 1. What exists, measured

### A. `Big Projects/baseball/` — git repo, 6 commits, **never pushed**

`git remote` points at `https://github.com/tdub29/portal-app.git`, which **does not exist**
(`gh repo view` returns "Could not resolve to a Repository"). The largest body of baseball work
Trevor has is sitting on one laptop with no remote.

| Piece | Size | What it is |
|---|---|---|
| `src/portal/` | 28 files, 5,294 lines | Portal ingest, dedupe, resolve, enrich, geo, program-tier, rollup, evaluate, alerts. 7 sources: D1Baseball, VerbalCommits, Twitter, CSV, PerfectGame bio, Sidearm bio, TrackMan |
| `scripts/` | 17 files, 6,380 lines | NCAA bio fetchers (D1/D2/D3/portal), school geocoding, Excel import/export, board HTML build, Netlify publish, Supabase RLS verify, an R `baseballr` export |
| `tests/` | 13 files, 1,544 lines | pytest: bio, board, d1baseball, dedupe, geo, overlay, RLS schema, pipeline, program_tier, resolve, rollup, speed, status |
| `run.py` | 336 lines | CLI: `init`, `import-excel`, `ingest`, `enrich-643`, `evaluate`, `board`, `run-all` |
| `warehouse/` | 11 models + 4 macros + 3 tests, 925 lines SQL | dbt-duckdb rebuild of the transform layer. Staging / intermediate / marts, model contracts, source freshness, sample fixtures so a fresh clone builds green with **zero credentials** |
| `hitter-app/` | 1,242 lines | Streamlit hitter app + 3 models (`xSLG`, swing, no-swing) + league KDE artifacts |
| `pitcher-app/` | 4,033 lines | Streamlit pitcher app + 7 models (`NCAA_STUFF_PLUS_24`, `NCAA_STUFF_PLUS_ALL`, `NCAA_WHIFF`, `whiff_model_grouped_training`, `rv_with_plateloc`, `lgbm_model_2020_2023`, `best_xgboost`) |
| `supabase/` + `db/schema.sql` | 329 lines SQL | Coach-facing overlay with row-level security; SQLite pipeline schema |
| `docs/` | 10 design docs | Pipeline design, 2026 sourcing, capabilities-and-blockers, Netlify + Supabase recipes |
| `dist/` | 1 file | Published Netlify board |

**Note:** `hitter-app/` and `pitcher-app/` are `.gitignore`d here. They are separate clones of
the two public GitHub repos, which is why the local repo has only 6 commits and why the apps have
never been versioned alongside the pipeline that calls their models.

### B. `OneDrive - GOOD360/Documents/Python Scripts/Baseball/` — **no git at all**

| Piece | Size | What it is |
|---|---|---|
| 22 notebooks | ~16,000 code lines | The research lab. Every one of the 10 shipped models was trained here |
| `battles/` | 24 Python files, 6,444 lines | **A separate product.** NCAA play-by-play acquisition (Playwright + `ncaa-api.henrygd.me`) plus situational "battle" scoring and season PDF reports. Has its own `AGENTS.md`, `FETCH_AND_CALC.md`, a pytest file, and written validation notes |
| `pitcher_reports.py`, `USD_baseball_app.py` | 721 lines | Duplicates of files already in `pitcher-app/` |
| 17 `*_baseball_visuals.pdf` | — | Per-player report output, sitting loose in the parent `Python Scripts/` folder |

**Roughly three quarters of this research is MLB, not NCAA.** Grepped by data source:

| MLB (Statcast / pybaseball / Savant / FanGraphs / Retrosheet / MLBAM) | NCAA (TrackMan / 6-4-3 / TruMedia / stats.ncaa.org) |
|---|---|
| `app_trumedia_integration` 3,489, `Trumediadev` 3,005, `Post_Game_Report_Generator` 2,414, `baseballmodels` 1,387, `armangle` 720, `Pitcher_scouting_report` 559, `3d_wOBA` 354 | `NCAA_Stuffplus` 750, `Bunt_outcome_research` 582, `effectivevelo` 495, `hitterapp` 432, `ideallocations` 396, `NCAA_WHIFF` 346, `pitchusage` 221, `transfer_portal_analysis` 206, `pitch_mix_effectiveness` 174, `TRANSFERSTATS` 125, `Umpire_Accuracy` 36 |
| **about 11,900 lines** | **about 3,800 lines** |

Several notebooks straddle both (`Post_Game_Report_Generator` and `app_trumedia_integration` pull
Statcast *and* TrackMan), which is itself the point: the same methods run at both levels.

### C. GitHub (`tdub29`, all public)

| Repo | Verdict |
|---|---|
| `streamlit-app-1` ("Pitcher App", 58 MB) | **Duplicate** of `baseball/pitcher-app/` |
| `hitterapp` (11 MB) | **Duplicate** of `baseball/hitter-app/` |
| `Baseball-Analysis` (R, MLB) | **The MLB pillar, under-built.** Run expectancy and win probability off MLB schedules and daily Baseball Reference stats, 2015 to 2019. Sixteen `.gitkeep` files and one real file: `src/legacy/projectbaseball_full_pipeline.R`, **604 lines with zero function definitions**. **Fold in and rebuild** (section 5b) |
| `WanBattedBall` | MLB Statcast batted-ball prediction, **top-25 finish** in the Nick Wan / NWDS Kaggle competition. A placed result is a credential. **Fold in** and say so in the README |
| `Bart`, `CBB`, `Kicker-Analysis` | Not baseball. Leave alone |
| `portal-app` | **Does not exist** |

---

## 2. Decision: one repo, named for baseball, not for one level of it

### The name cannot say NCAA

**`baseball-analytics`** — public, fresh `git init`, everything below in it.

An earlier draft of this plan called it `ncaa-baseball-analytics`. That was wrong. The MLB half is
about 11,900 notebook lines against 3,800 NCAA, plus a whole R run-expectancy and win-probability
pipeline over the 2019 to 2023 seasons, plus a top-25 Kaggle finish on MLB Statcast batted balls.
Naming the repo "ncaa" buries the larger half and tells a reader this is one school's side project
rather than work that spans the sport.

Alternatives if `baseball-analytics` is taken or reads too plain: `baseball-lab`,
`diamond-analytics`, `tw-baseball`. No league and no school in the name.

### One repo, not several

A reader clicks one link. Split across five repos, each piece looks like a weekend project.
Together it is one body of work: seven ingest sources feeding a tested warehouse, ten trained
models, two apps coaches use, a row-level-secured board, play-by-play acquisition, an MLB
modeling track, and CI. About **26,500 lines of source plus 16,000 lines of research notebooks**,
13 pytest files, dbt contracts and tests.

Splitting is worth it when two parts have genuinely different audiences. MLB and NCAA do not.
Both are the same person doing pitch-level modeling. The MLB work proves the methods are not
USD-specific; the NCAA work proves he ships them to real users. That pairing is stronger than
either half alone, which is exactly why they belong in one repo.

### `battles/` goes in, as a package

Same team, same season, same players. Play-by-play is a data source the portal pipeline can use.
It becomes `src/ncaa/pbp/` rather than its own repo, because standing alone it reads as a scraper
and inside the platform it reads as another source feeding the same warehouse.

### What happens to the GitHub repos

- `streamlit-app-1` and `hitterapp`: **archive** with a one-line README pointing at the flagship.
  Their content moves into `apps/`.
- `Baseball-Analysis`: **fold in.** It is the MLB track, thin only because the code implementing
  its README lives in the OneDrive notebooks. Bring both together under `src/mlb/` and
  `research/` and it stops being scaffolding. Archive the old repo afterward with a pointer.
- `WanBattedBall`: **fold in**, and keep the original repo too, since the competition writeup
  links to it.

---

## 3. Target layout

Split at the top by level. The data sources, the vocabulary and the update cadence all differ.

```
baseball-analytics/
  README.md                 # the showcase doc: what it does, what shipped, screenshots
  pyproject.toml            # replaces the three bare requirements.txt files
  config.example.yaml
  src/
    ncaa/
      portal/               # from baseball/src/portal/  (28 files, 5,294 lines)
      pbp/                  # from OneDrive battles/     (24 files, 6,444 lines)
      cli.py                # from run.py (336 lines)
    mlb/
      pipeline/             # Baseball-Analysis R lifecycle, ported or kept as R
      statcast/             # the Savant/pybaseball acquisition the notebooks share
    common/                 # HTTP, retry, player-name resolution shared by both
  apps/
    hitter/                 # from hitter-app/ + hitterapp
    pitcher/                # from pitcher-app/ + streamlit-app-1
  models/
    ncaa/                   # Stuff+, xWhiff, xSLG, RV; 10 artifacts total
    mlb/                    # anything the MLB notebooks serialized
                            # every model gets a provenance line: which notebook trained it
  warehouse/                # dbt project, unchanged except .venv removal
  db/schema.sql
  supabase/overlay_schema.sql
  scripts/                  # the 17 fetch/geocode/publish scripts
  tests/                    # 13 pytest files + the battles test
  research/
    notebooks/
      mlb/                  # 7 notebooks, about 11,900 lines, outputs stripped
      ncaa/                 # 11 notebooks, about 3,800 lines, outputs stripped
      competitions/         # WanBattedBall, the top-25 NWDS entry
    r/                      # projectbaseball_full_pipeline.R, ncaa_baseballr_export.R
    README.md               # maps each notebook to the model it produced
  data/
    samples/                # committed fixtures so a fresh clone runs
  docs/                     # the 10 existing design docs + this plan
  .github/workflows/ci.yml
```

---

## 4. Safety gates

Trevor cleared the data and attribution questions on 2026-09-12: real data may be public, and USD
branding and names are fine to use. So two gates remain, and both are mechanical.

1. **Fresh `git init`, do not import the old history.** Six commits and no reachable remote means
   there is nothing to preserve and nothing to scrub. Starting clean removes any chance a secret
   in an old blob survives into a public repo. Back the old `.git` up to a local dir until the new
   repo is confirmed good.

2. **Secrets.** This gate stands regardless of the data decision. `config.yaml` holds a
   D1Baseball session cookie and Supabase keys. The existing `.gitignore` already covers
   `config.yaml`, `secrets/`, `.env`, `*.pem`, `*.key`, `*-service-account.json`. Carry it
   forward, then verify `git ls-files` returns nothing matching
   `config|secret|env|profiles\.yml|token|cookie`, then run `gitleaks detect` before the first
   push. A live session cookie in a public repo is a different problem from public data.

**What changed from the earlier draft:** the `.gitignore` currently ignores `data/`, `*.csv`,
`*.xlsx` and `*.txt` wholesale, which was the right default when the data question was open. Now
it should be narrowed so real exports ship: keep ignoring `db/*.db` (128 MB of SQLite), `.venv`,
`__pycache__` and `dist/`, but let `data/` and the CSVs through. That makes `usd_baseball_TM_master_file.csv`
(8,524 rows of TrackMan) and `USDHITTINGYTD.csv` first-class parts of the repo, which is what
makes the apps runnable from a clone instead of a demo nobody can start.

One note, recorded once and then dropped: those files name individual athletes and carry player
IDs and hosted video URLs. Trevor has made that call, it is already public in two existing repos,
and it is his to make. Implementers should not re-raise it.

No AI co-authorship in any commit or PR, per the standing rule.

---

## 5. Cleanup

| Item | Action |
|---|---|
| `C:UsersTrevorWhiteDownloadsprobe_x_profile.py` | Delete. Mangled filename from a Unicode colon look-alike, unrelated to baseball |
| `book-to-skill-workspace/` | Delete from here. Belongs to its own workspace project |
| `.netlify/`, `.pytest_cache/`, `__pycache__/`, `warehouse/.venv/`, `warehouse/logs/`, `warehouse/target/`, `warehouse/dbt_packages/` | Delete. All regenerable |
| `sampl.txt`, `sampl copy.txt`, `sampl copy 2.txt`, `sampl copy 3.txt` | Keep the newest, delete 3. Check `PASTES.md` first, which records which paste each code path defaults to |
| `upd.txt`, `upd copy.txt` through `upd copy 5.txt` | Keep the newest, delete 5. Same check |
| `db/baseball.bak-20260702.db`, `db/*.bak_*` (3 more) | Delete. 128 MB of backups |
| `San_Diego_Toreros_logo.svg.png` at repo root | Move to `apps/pitcher/assets/`, where a duplicate already lives |
| `Post_Game_Report_Generator (1).ipynb` | Delete after diffing against the real one. 1 cell versus 44 |
| `NCAA_WHIFF-checkpoint.ipynb` | Delete. 0 cells, 72 bytes |
| `pitcher_reports.py` in 3 locations | Diff all three, keep one in `apps/pitcher/` |
| `usd_baseball_TM_master_file.csv` in 2 locations | One copy under `data/`, both apps read from there |
| 17 `*_baseball_visuals.pdf` in `Python Scripts/` root | Move 2 or 3 into `docs/samples/` as README screenshots, leave the rest local |
| 22 notebooks | Strip outputs (`nbconvert --ClearOutputPreprocessor.enabled=True`). They total about 27 MB, nearly all embedded images |
| `Untitled*.ipynb` (19 in `Python Scripts/` root) | Check whether any are baseball. Most likely not. Do not carry unexamined |

### 5b. Rebuild the MLB R pipeline — Trevor asked for this specifically

`src/legacy/projectbaseball_full_pipeline.R` is **604 lines with zero function definitions**. It
is the one piece here that is worth rewriting rather than relocating, and the rewrite is itself a
showcase item: a reader can diff the legacy file against the rebuild.

What is actually wrong with it, measured:

| Problem | Evidence | Fix |
|---|---|---|
| No decomposition | 0 `function` definitions across 604 lines | Split into `ingest`, `features`, `model`, `evaluate`, one file each, matching the directory layout the repo README already promises |
| Quadratic accumulation | `odf <- rbind(odf, f)` inside a `while` loop over every day of a season, and 7 `for` loops total | Collect into a list and `dplyr::bind_rows` once, or `purrr::map_dfr`. On a 180-day season this is the difference between seconds and minutes |
| Hardcoded seasons | `currentyearcreating <- 2015`, `endyear <- 2019`, then mutated in place | Function arguments, or the `config/baseball.yml` the repo already ships and never reads |
| Three dialects in one file | base R, `dplyr`, and `sqldf` all doing joins and filters | One dialect. `dplyr` throughout, drop the `sqldf` dependency |
| Right-assignment | `select(...) -> opening` mixed with `x <- y` | Consistent `<-`. This is cosmetic but it is on every page |
| No tests, no error handling | `tests/` holds a README and nothing else; an MLB API failure mid-loop loses the whole run | `testthat` on the feature functions, retry and resume on the ingest loop |
| Silent correctness risk | `rbind(odf, f, fill = TRUE)` passes `fill` to `rbind`, which base R ignores; that is `data.table` syntax | Verify no rows were being silently dropped or misaligned, then remove |

Keep it in R. It uses `baseballr`, which is the mature option for this, and a Python and R repo
reads as broader than a Python-only one. Keep the original file at `research/r/legacy/` so the
before and after are both visible, and say so in the README.

Code cleanup, where it is cheap and visible:

- One `pyproject.toml` replacing the three `requirements.txt` files.
- `scripts/fetch_*_PROTOTYPE.py` (3 files): delete if the non-prototype supersedes them, otherwise
  rename to say what they actually are.
- `src/ncaa/portal/` and `src/ncaa/pbp/` both fetch NCAA pages, and the MLB notebooks both hit
  Savant. Look for the shared HTTP and retry helper before writing a new one; that is what
  `src/common/` is for.
- Run the 13 pytest files plus `battles/test_baseballr_battle_calc.py` after every move. Green
  tests are the proof the consolidation broke nothing.

---

## 6. The README is the deliverable

Most readers will read only the README. It needs, in order:

1. One sentence on what it does, then a screenshot of the board and one Streamlit app.
2. Architecture in one diagram: sources, warehouse, models, apps, board.
3. **Both tracks, up front.** NCAA is the shipped-to-users half: a transfer-portal scouting
   platform in active use by USD coaching staff. MLB is the methods half: run expectancy and win
   probability over 2019 to 2023, Statcast arm-angle and pitch modeling, and a **top-25 finish in
   the NWDS batted-ball competition**. Lead with the fact that the same pitch-level modeling runs
   at both levels, because that is the thing neither half shows alone.
4. What is in production versus what is research, stated plainly. The apps are in active use; the
   warehouse is a staged rebuild that has not cut over.
5. Quickstart that works from a fresh clone, which the warehouse already supports and the rest
   must be made to match. With real data now shipping, this should actually run end to end.

---

## 7. Phases

| Phase | Work | Done when |
|---|---|---|
| 1 | Backup, fresh `git init`, target skeleton, `.gitignore` narrowed per gate 2 | `git ls-files` shows zero secrets; `data/` and CSVs are tracked |
| 2 | Move `src/ncaa/portal`, `scripts`, `tests`, `cli.py`, `warehouse`, `db`, `supabase`, `docs` | `pytest` green, `dbt build` green from a fresh clone |
| 3 | Fold in `apps/` from both app repos and the OneDrive duplicates, dedupe models | Both Streamlit apps start and render against the committed data |
| 4 | Fold in `battles/` as `src/ncaa/pbp/`, carry its test | `pytest` green including the battle calc test |
| 5 | Build `src/mlb/` from the 7 MLB notebooks, **and rebuild the 604-line R monolith per section 5b** | The rebuilt R pipeline runs end to end on one season, `testthat` green, no `rbind`-in-a-loop, seasons passed as arguments; legacy file preserved at `research/r/legacy/` |
| 6 | `research/`: 22 notebooks outputs-stripped and split mlb/ncaa/competitions, plus the R files and the mapping README | Every notebook opens and renders on GitHub |
| 7 | Cleanup table, one `pyproject.toml`, CI | CI green on a clean runner |
| 8 | README with screenshots, `gitleaks detect`, push, archive the 3 old repos with pointers | Public URL live, gitleaks clean, `streamlit-app-1` / `hitterapp` / `Baseball-Analysis` archived |

---

## 8. Open question for Trevor

Only one left. **Repo name:** `baseball-analytics` is the proposal, deliberately with no league or
school in it. Alternatives: `baseball-lab`, `diamond-analytics`, `tw-baseball`. If no answer
comes, use `baseball-analytics`.
