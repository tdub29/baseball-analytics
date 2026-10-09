# MLB staging warehouse (dbt + DuckDB)

A tested, typed view of the raw MLB caches: Retrosheet games and plays, StatsAPI games, schedule,
team and player game logs and rosters, and the Chadwick register, plus a Retrosheet-to-StatsAPI
game crosswalk. It exists so the keys, dates and joins the R pipeline relies on are checked by
code on every rebuild instead of by hand, and so ad hoc questions over 2M plays are one SQL query.

The frozen R features (`matchup_build.R`, `context_features.R`, the simulator) are **not** ported.
The 2023-2025 test and the 2026 forward test were scored on the R code as written; a SQL rewrite
would be a new model that has to earn its numbers again. This layer sits beside the R pipeline,
it does not feed it.

## Run

From the repo root, with the raw caches in `data/mlb/raw/` (see [../DATA.md](../DATA.md)):

```sh
Rscript research/r/mlb/export_parquet.R          # rds caches to data/mlb/parquet/
cd research/r/mlb/warehouse
cp profiles.example.yml profiles.yml             # gitignored
dbt build --profiles-dir .                       # writes data/mlb/mlb.duckdb
```

Set `MLB_DATA` to the absolute `data/mlb` path when the data lives elsewhere (a git worktree
reads the main checkout's). CI only runs `dbt parse`: the data is private and never in the repo.

## What the tests pin

- Natural keys: `gid`; (`gid`, `pn`); `game_pk`; (`game_pk`, listing time) on the schedule;
  (`team_id`, `game_pk`, group); (`person_id`, `game_pk`, `team_id`, group), since a player can
  log a line for two teams in one game; Chadwick ids unique where present.
- Dates: a Retrosheet game's first play is on `start_date` and its last on `completion_date`
  (`suspend` is the completion date). StatsAPI gives both listings of a suspended game the
  start's `officialDate`, so `official_date` is not a results-known date.
- Crosswalk: one `game_pk` per `gid`. 40 regular-season games stay unmatched, all explained (the 36
  home/away swaps in DATA.md, two doubleheaders with identical scores); a 41st warns.

Not modelled: odds (unlicensed, never leaves this machine), Statcast, StatsAPI live feeds,
Baseball-Reference windows.

## Sources and terms

> The information used here was obtained free of charge from and is copyrighted by Retrosheet.
> Interested parties may contact Retrosheet at "www.retrosheet.org".

2017-2025 probable starters and all StatsAPI data: MLB StatsAPI, copyright MLB Advanced Media,
L.P., used for private research. Chadwick register: ODC-By. The Parquet copies and the DuckDB file
are gitignored for these terms.
