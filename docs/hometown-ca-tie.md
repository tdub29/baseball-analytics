# Hometown + California / San Diego tie layer

Goal: tie **every player** to a **hometown (city, state) + high school**, and flag
any **California / San Diego connection** — the USD recruiting edge ("be our Connor
Stalions": systematize the signal no other hot board scores). A San Diego kid at a
non-CA school is the prize, which is why `from_school` alone is not enough — we need
hometown on everyone.

## How the signal is built

`players.ca_tie` / `sd_tie` / `ca_tie_reasons` are set by `src/portal/geo.py` from
**four independent signals**, so the board is useful before *and* after the scrape:

| Signal | Source | Live today? |
|---|---|---|
| hometown state == CA | NCAA/Sidearm/PG roster → `player_bio` | after bio scrape |
| hometown city in San Diego County | same | after bio scrape |
| prior school (`from_school`) is a CA / SD program | already in DB | **yes** |
| summer team in a CA league (CCL, SLO) | already in DB | **yes** |
| high school in SD County / CA | roster HS field | after bio scrape |

`sd_tie ⊆ ca_tie`. Reasons are stored as `";"`-joined evidence, e.g.
`hometown=Chula Vista (SD County);prev_school=CA`.

## Source ranking for hometown (best → fallback)

1. **6-4-3 Portal HQ export** — *if* it carries a hometown/HS column (keyed to the
   cross-school Player ID; zero new scraping). Check a fresh export first.
2. **stats.ncaa.org roster** — the spine. `scripts/fetch_ncaa_bio.py` already loads
   these pages; the table header is `[... Height, Bats, Throws, Hometown, High School]`.
   One uniform source across all programs; school_id/instance caches already built.
3. **Sidearm team sites** — most complete (adds *previous school*), per-school
   templates → targeted fallback. `src/portal/sources/sidearm_bio.py`.
4. **Perfect Game / PBR** — richest cross-check (hometown/HS/grad-year/state), gated +
   JS → verification scaffold. `src/portal/sources/perfectgame_bio.py`.

## Runbook

### 0. One-time: migrate the DB (already done)
```powershell
python scripts/migrate_db.py     # adds hometown_* + ca_tie/sd_tie/ca_tie_reasons
```

### 1. Score CA ties from what's already in the DB (no scraping)
```powershell
python run.py geo-tie            # -> data/california_board.csv (San Diego ties first)
```
Baseline today: **479 CA-tie players, 52 San Diego ties** (all from prior-school /
summer signals; `with_hometown` is 0 until step 2).

### 2. Backfill hometown via the NCAA spine (the live scrape — run yourself)
The height scrape that was running is height-only. To capture hometown, **re-run the
extended scraper**. `ensure_csv_header` auto-rotates the old 7-column
`ncaa_heights_*.csv` to `.bak` and starts fresh; school_id/instance caches persist so
only roster pages reload.
```powershell
# wait for any in-flight scrape to finish (one browser at a time vs. stats.ncaa.org)
python scripts/fetch_ncaa_bio.py --season 2026          # 2026 first; add 2025/2024 later
python run.py enrich-bio --dir data/643_exports/bio --source ncaa
python run.py geo-tie                                    # hometown signals now light up
```

### 3. Fallback for players the NCAA roster misses (Sidearm)
```powershell
# offline: parse a saved roster page
python -m portal.sources.sidearm_bio --html data/cache/usd_roster.html `
    --team "San Diego" --season 2026 --out data/643_exports/bio/sidearm_usd.csv
# or live (opt-in): add --url <roster_url> --fetch
python run.py enrich-bio --path data/643_exports/bio/sidearm_usd.csv --source sidearm
python run.py geo-tie
```

### 4. Verification / hard-to-find hometowns (Perfect Game / PBR)
Scaffold only — parse a saved profile, verify selectors in
`parse_pg_profile` / `parse_pbr_profile`, then `enrich-bio --source perfectgame`.

## Outputs
- `data/california_board.csv` — CA-tie players, San Diego first, joined to fit_score.
- `data/ca_ties_baseline.csv` — the prior-school/summer proxy snapshot.
- `players.ca_tie / sd_tie / hometown_* / ca_tie_reasons` + the same columns on the
  main `data/hot_board.csv`.

`geo-tie` is also folded into `run.py run-all` (after `evaluate`, before `board`), so
the hourly June refresh keeps CA ties current.
