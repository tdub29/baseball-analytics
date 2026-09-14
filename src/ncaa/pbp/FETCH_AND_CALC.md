# How USD game data is fetched and battle calc is run

## What gets run

### 1. Fetch (play-by-play and game list)

**Script:** `Baseball/battles/pbp_battle_feasibility.py`  
**Data source:** **`https://ncaa-api.henrygd.me`** (no NCAA official API; this is a third-party API).

- **Scoreboard by date:**  
  `GET https://ncaa-api.henrygd.me/scoreboard/baseball/d1/YYYY/MM/DD/all-conf`
- **Play-by-play for a game:**  
  `GET https://ncaa-api.henrygd.me/game/{contest_id}/play-by-play`

**Example (2026 games only):**

```text
python Baseball/battles/pbp_battle_feasibility.py --team-short "San Diego" --year 2026 --start-date 2026-02-18 --max-days-back 120 --out-dir Baseball
```

- Scans from `--start-date` backward, one day at a time.
- If `--year 2026` is set, only dates in 2026 are requested; when it steps into 2025 it stops.
- For each date, the script keeps only games where **`gameState == "final"`** (completed games). It skips `"pre"` (scheduled), `"in"`, etc., because play-by-play is only available for finished games.
- For each kept game it fetches PBP from `/game/{contest_id}/play-by-play` and only then adds the game to the list.

**Output files (in `--out-dir`, e.g. `Baseball/`):**

- `real5_pbp_baseballr_style.csv` – play-by-play (baseballr-style)
- `real5_selected_games.csv` – game list (contest_id, away_short, home_short)
- `real5_pbp_retrosheet_style.csv`, `Baseball/battles/real5_battle_feasibility.md`

### 2. Battle calculation

**Script:** `Baseball/battles/baseballr_battle_calc.py`

- Reads `real5_pbp_baseballr_style.csv` and `real5_selected_games.csv` from the Baseball/ directory.
- Converts PBP to battle format and runs battle metrics for **every** game in the PBP file.
- Writes `Baseball/battles/real5_battle_calc_output.txt`.

**Example:**

```text
python Baseball/battles/baseballr_battle_calc.py
```

(Assumes it’s run from the repo root or that the script’s folder contains the two CSVs above.)

---

## Why “0 games” for 2026?

The API **does** return 2026 scoreboard data. For example:

- **`https://ncaa-api.henrygd.me/scoreboard/baseball/d1/2026/02/18/all-conf`**  
  returns many games for that date.

But on that (and other) 2026 dates, every game currently has **`"gameState": "pre"`** (scheduled, not yet played). The fetch script **only** keeps games with **`gameState == "final"`**, so it never adds any of them. So you get “0 games” for 2026 because:

1. Only **final** games are used (so we can get play-by-play).
2. On the 2026 dates we’re scanning, the API only has **pre** (scheduled) games.

Once 2026 games are completed and the API marks them as `"final"` and has PBP, the **same** commands will pick them up. No code change is required; you just need to run the fetch again after 2026 games are in the books and the API is updated.

To use **all completed games so far** (including 2025), run the fetch **without** `--year` so it can look at past dates:

```text
python Baseball/battles/pbp_battle_feasibility.py --team-short "San Diego" --games 20 --start-date 2026-02-18 --max-days-back 400 --out-dir Baseball
```

That scans from 2026-02-18 back 400 days (into 2025) and returns up to 20 **final** San Diego games (today that will be 2025 games). Then run `Baseball/battles/baseballr_battle_calc.py` as above to get battle output for those games.

---

## R path (baseballr — stats.ncaa.org)

A separate R workflow uses the **baseballr** package (stats.ncaa.org) to get USD’s **schedule** and, later, play-by-play. This can return 2026 games as soon as the NCAA site has the schedule (no need to wait for `gameState == "final"` elsewhere).

### Test: list 2026 USD games

**Script:** `Baseball/r_fetch_usd_schedule_2026.R`

**Requires:** R with `install.packages("baseballr")`.

**Run in R or RStudio:**

```r
setwd("c:/Users/TrevorWhite/OneDrive - Good360/Documents/Python Scripts")  # or your repo root
source("Baseball/r_fetch_usd_schedule_2026.R")
```

Or from a terminal (if R is on PATH):

```text
cd "c:\Users\TrevorWhite\OneDrive - Good360\Documents\Python Scripts"
Rscript Baseball/r_fetch_usd_schedule_2026.R
```

The script:

1. Looks up University of San Diego’s `team_id` via `ncaa_school_id_lu("San Diego")` (Division I).
2. Fetches the 2026 schedule with `ncaa_schedule_info(team_id, year = 2026)`.
3. Prints the games and writes **`Baseball/usd_2026_schedule_baseballr.csv`**.

If the NCAA has posted the 2026 schedule, you’ll see all listed games (date, opponent, `game_info_url`, `game_pbp_url`). A follow-up script can use those URLs to fetch PBP with `ncaa_pbp(game_info_url = ...)` and write a baseballr-style CSV for the battle calc.
