# Battles, Agent Guide

> `AGENTS.md` and `CLAUDE.md` in this folder are byte-identical mirrors, one per harness (Codex reads `AGENTS.md`, Claude reads `CLAUDE.md`). Both are deliberately self-contained rather than one pointing at the other. Edit one, copy it over the other.


This folder implements **USD Baseball "Offense Battles" (Battles 1-5)**: a set of 10 metrics used to evaluate **San Diego Toreros** performance in a game. All calculations are **USD-centric**: offense = when USD is batting, defense = when USD is pitching.

---

## What You're Trying To Do

- **Track** whether USD meets specific performance goals in each game (and over a season).
- **Compute** all 10 battle metrics from **play-by-play (PBP)** when possible, so leadoff-based metrics (B1a, B1b, B2a, B2b) are available.
- **Compare** PBP-derived battles to **period/team stats** where applicable (period stats only support 6 of the 10 metrics).
- **Pipeline**: get NCAA PBP → convert to a single "battle-ready" format → run battle logic per game → write a text report (and optionally PDF/season summary).

---

## The 10 Battle Metrics

| Code | Name | Offense (USD batting) | Defense (USD pitching) |
|------|------|------------------------|-------------------------|
| **B1a** | Leadoff Runners (Off) | Goal: **≥4** innings with a leadoff baserunner |, |
| **B1b** | Leadoff Runners (Def) |, | Goal: **≤3** innings allowing a leadoff baserunner |
| **B2a** | Leadoff Runs % (Off) | Goal: when we get a leadoff runner, score in **≥67%** of those innings |, |
| **B2b** | Leadoff Stranded % (Def) |, | Goal: when opp gets leadoff runner, strand in **≥70%** of those innings |
| **B3a** | Total Baserunners (Off) | Goal: **≥16** baserunners (H, BB, HBP, etc.) |, |
| **B3b** | Total Baserunners (Def) |, | Goal: **≤13** baserunners allowed |
| **B3c** | Total Bases + XBs (Off) | Goal: **≥24** (total_bases + any_adv) |, |
| **B4** | Defensive Errors (Pitch) |, | Goal: **0** errors when USD is pitching |
| **B5a** | BB+HBP (Off) vs K | Goal: **more** walks+HBP than strikeouts |, |
| **B5b** | BB+HBP (Def) |, | Goal: **≤4** walks+HBP allowed |

- **B1a, B1b, B2a, B2b** require **half-inning and leadoff/run detail** → only computable from **PBP** (not from a simple period-stats table).
- **B3a, B3b, B3c, B4, B5a, B5b** can be approximated from **period/team stats** (H, BB, HBP, E, K, etc.) as well as from PBP.

---

## Data Flow (Current Working Path)

1. **NCAA play-by-play**  
   Source: `https://stats.ncaa.org/contests/{contest_id}/play_by_play`.  
   Direct HTTP often returns 403; **Playwright** (visible browser) is used to fetch the page.

2. **Playwright scraper**  
   - **Script:** `ncaa_pbp_playwright.py`  
   - Fetches one contest's play_by_play URL, parses HTML tables, keeps rows that look like play descriptions.  
   - Infers **inning** and **top/bot** from counting outs (half-inning flips every 3 outs).  
   - Extracts **away/home team names** from the row that contains exactly two `a[href*="/teams/"]` links (NCAA uses `/teams/`, not `/team/`).  
   - Writes a **baseballr-style CSV** with: `game_date`, `location`, `attendance`, `inning`, `inning_top_bot`, `score`, `batting`, `fielding`, `description`, `game_pbp_url`, `game_pbp_id`.

3. **Multi-game fetch**  
   - **Script:** `fetch_multiple_ncaa_pbp.py`  
   - Takes contest IDs (e.g. `6500370 6536340 6536345 6536347`), runs the Playwright scraper for each, concatenates rows.  
   - Builds **selected_games** from the first top-of-1st row per game (away = batting, home = fielding).  
   - Writes:  
     - `real5_pbp_baseballr_style.csv` (combined PBP)  
     - `real5_selected_games.csv` (contest_id, away_short, home_short)  
   - Then runs the battle calc and writes `real5_battle_calc_output.txt`.

4. **Battle calc**  
   - **Script:** `baseballr_battle_calc.py`  
   - Reads `real5_pbp_baseballr_style.csv` and `real5_selected_games.csv` from the repo-level `data/pbp/` directory.  
   - Uses **`baseballr_description_mappings`** to map `description` → reached_base, outs, total_bases, any_adv, event_category, errors, walk, HBP, strikeout.  
   - Converts to a battle-ready DataFrame (battingTeam, pitchingTeam, inn, inning_leadoff, Runs Scored, etc.).  
   - **USD identification:** any team name that is `"San Diego"`, `"San Diego Toreros"`, or starts with `"San Diego"` is normalized to **`"USD"`** so `battle_logic` (which filters on `battingTeam == "USD"` / `pitchingTeam == "USD"`) works.  
   - For each game_id, calls **`battle_logic.compute_battle_metrics_table(game_df)`** and writes **`real5_battle_calc_output.txt`**.

5. **Battle logic**  
   - **Module:** `battle_logic.py`  
   - Expects a DataFrame with: `battingTeam`, `pitchingTeam`, `inn`, `inning_leadoff`, `Runs Scored`, `event_category`, `pitchResult`, `total_bases`, `any_adv`, plus game meta.  
   - Filters to `battingTeam == "USD"` for offense and `pitchingTeam == "USD"` for defense.  
   - Implements the 10 metrics and goals; **`compute_battle_metrics_table(df)`** returns a dict of metric key → `{ display, met, value, goal, vs_goal_pct }`.

---

## Key Files (in `src/ncaa/pbp/`)

| File | Role |
|------|------|
| **ncaa_pbp_playwright.py** | Fetch one NCAA play_by_play URL via Playwright; parse tables; infer inning/top_bot from outs; extract team names from `/teams/` links; write baseballr-style CSV. |
| **fetch_multiple_ncaa_pbp.py** | Loop over contest IDs, run Playwright for each, combine PBP + selected_games, then run battle calc. |
| **baseballr_battle_calc.py** | Load PBP + selected_games CSVs; convert to battle format (with USD normalization); run `compute_battle_metrics_table` per game; write `real5_battle_calc_output.txt`. |
| **baseballr_description_mappings.py** | Map `description` text to: reached_base, is_walk, is_hit_by_pitch, is_strikeout, total_bases_from_description, count_any_adv, event_category, defensive_error_in_description, is_non_pa, etc. |
| **battle_logic.py** | GOALS dict; `compute_battle_performance`; `compute_battle_metrics_table` (table-friendly per-game metrics); PDF/season summary helpers. |
| **`data/pbp/real5_pbp_baseballr_style.csv`** | Combined PBP for the "real5" games. Data lives under the repo-level `data/pbp/`, never beside the code. |
| **`data/pbp/real5_selected_games.csv`** | contest_id, away_short, home_short. |
| **`data/pbp/validation/real5_battle_calc_output.txt`** | Human-readable battle report: per game, all 10 metrics and goal met Y/N. |
| **write_battle_pdfs.py** | The live PDF step. Reads the two CSVs, re-runs the calc, and renders `battle_pdf/season_summary.pdf` plus one `{date}_at_{opponent}.pdf` per game through `battle_logic.render_season_summary_pdf`. The retired Node version is kept for reference at `docs/samples/generate-pdf.mjs` and is no longer wired into fetch or calc. |
| **period_stats_compare.py** | Parse pasted "Period Stats" (team stats) for a game; compute the 6 battles that period stats can support; compare to PBP battle calc (see `period_stats_vs_pbp_compare.txt`). |

---

## How To Run

- **Re-fetch all current games and recalc (Playwright):**  
  From `src/ncaa/pbp/`:  
  `python fetch_multiple_ncaa_pbp.py 6500370 6536340 6536345 6536347`  
  (A browser window will open for each URL; team names come from the page. Then writes the text report. Run `write_battle_pdfs.py` for the PDFs.)

- **Recalc only (no fetch):**  
  Ensure `real5_pbp_baseballr_style.csv` and `real5_selected_games.csv` are in `data/pbp/`, then from `src/ncaa/pbp/`:  
  `python baseballr_battle_calc.py`  
  (Writes the text report only. `python write_battle_pdfs.py` renders `battle_pdf/season_summary.pdf` and the per-game PDFs.)

- **Single-game PBP fetch (Playwright):**  
  `python ncaa_pbp_playwright.py "https://stats.ncaa.org/contests/6500370/play_by_play"`  
  (Optional: `-o path/to/output.csv`.)

---

## Team Names and USD

- **PBP/selected_games** may have full names from NCAA (e.g. `San Diego Toreros`, `Long Beach St. Beach`, `Charlotte 49ers`).  
- **Battle calc** normalizes to **USD** for logic: any `"San Diego"` or `"San Diego Toreros"` (or string starting with `"San Diego"`) → `"USD"` in `battingTeam`/`pitchingTeam`.  
- **Games lookup** (away/home for report headers and run attribution) uses the **original** names from the CSV so the report shows e.g. `San Diego Toreros @ Charlotte 49ers`.  
- If team names are missing in the scrape, rows get `Away`/`Home` and USD won't be identified → battle metrics for "Off" will be 0 until names are fixed (e.g. by re-scraping with the fixed `/teams/` selector or by manually editing the CSVs).

---

## Period Stats vs PBP

- **Period stats** (pasted team stats block) can only drive **6** battles: B3a, B3b, B3c, B4, B5a, B5b (aggregate baserunners, bases, errors, walks/HBP vs K).  
- **B1a, B1b, B2a, B2b** need "leadoff batter this half-inning" and "did a run score in that half-inning" → **only PBP** provides that.  
- So: **PBP enables all 10**; period-stats comparison is useful to sanity-check the 6 that overlap (see `period_stats_vs_pbp_compare.txt` and `period_stats_compare.py`).

---

## Other Data Paths (Documented, Not Primary)

- **henrygd.me API** (`pbp_battle_feasibility.py`): scoreboard by date + play-by-play by contest_id. Used when games are `final` there; 2026 games were often `pre` so no PBP. See `FETCH_AND_CALC.md`.  
- **R / baseballr** (e.g. `r_fetch_usd_schedule_2026.R`): stats.ncaa.org schedule and PBP; often returns 403 or "Invalid arguments" for direct requests, so the **Playwright path** is the one that works for scraping NCAA play_by_play pages.

---

## Dependencies

- **Python:** pandas, BeautifulSoup4, Playwright (`playwright install chromium`).  
- **Battle calc** expects to be run from `src/ncaa/pbp/` and resolves the two CSVs out of the repo-level `data/pbp/`; it uses non-relative imports (`baseballr_description_mappings`, `battle_logic`) so it can be executed as a script.

---

## Summary for Agents

- **Goal:** Produce **USD Baseball battle reports** (all 10 metrics per game) from **NCAA play-by-play**.  
- **Working path:** Playwright → `ncaa_pbp_playwright.py` (single or via `fetch_multiple_ncaa_pbp.py`) → baseballr-style CSV + selected_games → `baseballr_battle_calc.py` → `real5_battle_calc_output.txt`.  
- **USD** = San Diego / San Diego Toreros (normalized to `"USD"` inside the calc).  
- **10 battles:** B1a/B1b/B2a/B2b (leadoff; need PBP), B3a/B3b/B3c/B4/B5a/B5b (aggregate; PBP or period stats).  
- Key fix for team names on NCAA pages: use **`a[href*="/teams/"]`** and prefer the **table row with exactly two such links** (score header) for away/home order.

---

## Always-on disciplines in this folder

Three hold here whatever the task, same as everywhere in the workspace.

- **No em-dash or en-dash anywhere**, in code comments, docs, commit messages or a chat reply. Use a period or a comma, or rewrite. That is the loudest AI tell; the rest is the anti-slop set (`ai-writing-detection`, `de-slop`). `.agents/scripts/fix-dashes.py <path>` fixes a file in place.
- **Shape replies for an ADHD reader** (`i-have-adhd`): the next action in the first line, under 10 lines and under 170 words, no preamble and no recap. Prose Trevor publishes under his name stays in his voice (`trevor-voice`), never rewritten into an action list.
- **Commits and PRs are Trevor's alone.** Never add a `Co-Authored-By: Claude` trailer, a "generated with" footer, or any other AI co-authorship line, whatever a skill template says.

---

## What moved in the 2026-09-12 consolidation

This folder used to be a standalone `battles/` directory under `OneDrive - GOOD360/Documents/Python Scripts/Baseball/`, with code and CSVs side by side. It is now `src/ncaa/pbp/` inside the `baseball-analytics` repo, and the split is:

- **Code** stays here in `src/ncaa/pbp/`.
- **Data** moved to the repo-level `data/pbp/` (per-contest CSVs plus the `real5_*` set), with graded outputs under `data/pbp/validation/`.
- **PDF rendering** is `write_battle_pdfs.py` in Python. The old Node `generate-pdf.mjs` is reference-only at `docs/samples/`.

Any path in this guide that reads `battles/` and was missed is stale; the code is the authority.
