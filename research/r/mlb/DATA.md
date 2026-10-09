# Data sources for the MLB research pipeline

What every result under `results/` is built from, where it came from, under what terms, and what is
wrong with it. Measured numbers come from [results/data-audit.md](results/data-audit.md)
(`Rscript research/r/mlb/data_audit.R`, local cache only); the rebuild order is
[reproduce.sh](reproduce.sh). Raw data lives under `data/mlb/raw/`, which is gitignored: nothing in
this file's sources is committed except aggregates in result files.

> The information used here was obtained free of charge from and is copyrighted by Retrosheet.
> Interested parties may contact Retrosheet at "www.retrosheet.org".

## Summary

| Source | Used by | Seasons | Local path | Grain, natural key |
|---|---|---|---|---|
| Retrosheet season CSVs | matchup, context, totals | 2015-2025 | `data/mlb/raw/retrosheet/` | game: `gid`; plate appearance: (`gid`, `seq`) |
| MLB StatsAPI | backtest, recency, market and matchup joins | 2015-2025 | `data/mlb/raw/statsapi_*/`, `seasons/` | game: `game_pk`; team line: (`team_id`, `game_pk`, group); player line: (`person_id`, `game_pk`, group) |
| Baseball Savant batted balls | Statcast ablation only (v3, v3h; dropped) | 2015-2025 | `data/mlb/raw/statcast/` | ball in play: (`game_pk`, `at_bat_number`) |
| Chadwick register | id crosswalk (MLBAM, Retrosheet, Baseball-Reference) | snapshot | `data/mlb/raw/chadwick/register.rds` | person: `key_person`; `key_mlbam`, `key_retro`, `key_bbref` each unique where present |
| Baseball-Reference daily windows | 2019 backtest only | 2016-2019 | `data/mlb/raw/bref_batter/`, `bref_pitcher/` | player per 15-day window: (window, `bbref_id`), not checked |
| SportsBookReview odds scrape | market, matchup market tests, totals | 2021-04-01 to 2025-08-16 | `data/mlb/raw/odds/mlb_odds_dataset.json` | game per date: (date key, home name, away name, start time); no game id |

Retrieval dates are the local file times recorded in data-audit.md section 0 (with an md5 per
source, so a rebuild can confirm it is reading the same bytes). The keys and dates below are also
checked as dbt tests over a local DuckDB copy: [warehouse/README.md](warehouse/README.md).

## Retrosheet

- **What.** Retrosheet's per-season CSV release, compiled from its event files. Two files per season
  are read: `<year>gameinfo.csv` (one row per game: teams, date, doubleheader number, start time,
  weather, umpires, final score, game type) and `<year>plays.csv` (one row per event). `retro.R`
  keeps regular-season games, and plate appearances with `pa == 1`, intentional walks removed.
- **URL.** `https://www.retrosheet.org/downloads/<year>/<year>csvs.zip` (the 2015, 2020 and 2025 zips
  match the server's Content-Length; server Last-Modified 2026-08-09).
- **Terms.** Free for any use, including commercial, provided this notice appears prominently with
  the data or anything derived from it: "The information used here was obtained free of charge from
  and is copyrighted by Retrosheet. Interested parties may contact Retrosheet at "www.retrosheet.org"."
  Retrosheet makes no accuracy guarantee and corrects data over time.
- **Retrieval.** Downloaded 2026-10-04 (no fetch script existed; `reproduce.sh` step 1 now curls the
  zips). `retro.R` unzips on demand and caches `pa_<year>.rds`.
- **Grain and key.** Game: `gid` (home team code, date, game number). Plate appearance: (`gid`,
  `seq`), `seq` the PA order within the game after filtering. Both unique (audit section 5).
- **Rows by season.**

  | | 2015 | 2016 | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 |
  |---|---|---|---|---|---|---|---|---|---|---|---|
  | games | 2429 | 2428 | 2430 | 2429 | 2429 | 898 | 2429 | 2430 | 2430 | 2429 | 2430 |
  | PAs | 182677 | 183648 | 184325 | 184074 | 185764 | 66304 | 181115 | 181577 | 183630 | 181940 | 182370 |
  | balls in play | 127772 | 125544 | 125341 | 123996 | 123021 | 43569 | 120122 | 123151 | 123131 | 123012 | 123618 |

- **Known gaps.**
  - 2020 is a 60-game season (898 games). The recency study uses it as history only.
  - **Switch hitters.** `bathand` is the registered hand: 10-14% of PAs per season are `B`, with no
    record of the side actually batted. `matchup_build.R` maps every non-L/R hand to `R`, so switch
    hitters enter platoon splits, the platoon prior and park factors as right-handed, even against
    right-handed pitchers. This reaches `features.rds`, the frozen matchup test and the totals study.
  - **Batted-ball types change definition in 2020.** Popups go from 0.2-1.3% of balls in play to
    about 7%, fly balls from about 35% to 26%, line drives from about 20% to 24% (2020: 28.6%), and
    agreement with Statcast's type for the same ball rises from 84-87% to 99.8% from 2021. Pre-2020
    types and 2020-on types are different classifications; the matchup model's three-season outcome
    mix by type straddles the boundary for 2020-2022 balls.
  - 1-3% of hits and outs in play have no batted-ball type (bunts and the like); they are not balls
    in play for the matchup or Statcast matching.
  - Retrosheet and StatsAPI name opposite home teams in 36 relocated or makeup games (3 in 2015,
    3 in 2017, 28 in 2020, one each in 2021 and 2022); the 2018 tiebreakers (game 163) are not in
    Retrosheet's regular season.

## MLB StatsAPI

- **What.** The public `statsapi.mlb.com/api/v1` endpoints: `schedule` with
  `hydrate=lineups,probablePitcher` (final regular-season games with scores, venue, probable
  starters and the posted starting nine), `schedule` with `hydrate=probablePitcher` (the backtest's
  schedule), `teams`, `teams/{id}/roster?rosterType=fullSeason`, team `stats?stats=gameLog`, player
  game logs through `people?hydrate=stats(...gameLog...)`, and season dates (`baseballr::mlb_seasons_all`).
- **Terms.** MLB Advanced Media's notice (gdx.mlb.com/components/copyright.txt): the materials are
  proprietary content of MLBAM, and "Only individual, non-commercial, non-bulk use of the Materials
  is permitted and any other use of the Materials is prohibited without prior written authorization
  from MLBAM." Treated as private, non-commercial research: raw pulls stay in the gitignored cache.
- **Retrieval.** `fetch_gamelogs.R 2015 2025` (teams, rosters, team and player logs, schedule with
  lineups) on 2026-10-02 and 2026-10-03; `fetch_cache.R mlb 2016 2019` (backtest schedule, season
  dates, Chadwick) 2026-09-30 to 2026-10-02. Every call is cached by `cache_fetch()` in `ingest.R`;
  a failed call is never cached.
- **Local path.** `data/mlb/raw/statsapi_lineups/`, `statsapi_schedule/`, `statsapi_teams/`,
  `statsapi_roster/`, `statsapi_team_log/`, `statsapi_player_log/`, `seasons/`.
- **Grain and key.** Game: `game_pk` (unique). Team line: (`team_id`, `game_pk`, group), unique.
  Player line: (`person_id`, `game_pk`, group), one legitimate repeat (a player traded between the
  two teams of a suspended game, 2024). Roster row: (`person_id`, `team_id`, season).
- **Rows by season.**

  | | 2015 | 2016 | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 |
  |---|---|---|---|---|---|---|---|---|---|---|---|
  | games | 2429 | 2428 | 2430 | 2431 | 2429 | 898 | 2429 | 2430 | 2430 | 2429 | 2430 |
  | team-log rows | 9716 | 9712 | 9720 | 9724 | 9716 | 3592 | 9716 | 9720 | 9720 | 9716 | 9720 |
  | hitter lines | 50517 | 50228 | 50157 | 50255 | 50174 | 18770 | 49929 | 49875 | 50598 | 50612 | 50655 |
  | pitcher lines | 19921 | 20137 | 20483 | 21136 | 21342 | 7926 | 21360 | 20719 | 20382 | 20606 | 20708 |

- **Known gaps.**
  - **Probables are not pre-game probables.** The historical "probable" starter matches the pitcher
    credited with the start in StatsAPI's own logs in all but 0.04-0.58% of games per season, so it
    is the actual starter, written after the game. Lineups are the posted starting nine. Any model
    using them makes its prediction at first pitch, not the day before.
  - **Player logs miss some pitchers.** Logs are pulled only for players on the cached fullSeason
    rosters, and 16 pitchers who started games are absent from them (212 starts: 19 in 2021, 39 in
    2022, 123 in 2023, 31 in 2025). In 2023 that is 1.96% of pitcher batters faced and 122 team-games
    with no starter line. The recency model's pitcher estimates (E, and everything compared with it)
    lose those seasons.
  - Before the universal DH (2015-2019, 2021) about 3% of team plate appearances are pitchers
    batting, which the hitter logs skip by design.
  - 2020 is 60 games. The 2018 tiebreakers are in StatsAPI's regular season (2,431 games).

## Baseball Savant batted balls

- **What.** Savant's `statcast_search/csv` export, regular season (`hfGT=R`), batted-ball types fly
  ball, ground ball, line drive and popup: one row per ball in play with exit velocity, launch angle
  and Savant's own fields. `statcast.R` keeps game, batter, pitcher, hands, event, type, exit
  velocity, launch angle and at-bat number.
- **URL.** `https://baseballsavant.mlb.com/statcast_search/csv?...` (full query in `fetch_statcast.sh`).
- **Terms.** Footer: "© MLB Advanced Media, LP. All rights reserved.", with MLB's terms of use at
  https://www.mlb.com/official-information/terms-of-use. Handled like StatsAPI: private,
  non-commercial research, raw CSVs stay local.
- **Retrieval.** `fetch_statcast.sh 2015 2025` on 2026-10-04: one request per week, 03-15 to 11-05
  (2020 from 07-20), resumable. `statcast_bip()` caches the union as `bip_all.rds`, which is never
  invalidated: delete it after refetching any week.
- **Grain and key.** Ball in play: (`game_pk`, `at_bat_number`), unique.
- **Rows by season.** 2015 130474, 2016 123708, 2017 127555, 2018 126283, 2019 125751, 2020 43972,
  2021 121702, 2022 124265, 2023 124232, 2024 124201, 2025 124887.
- **Known gaps.**
  - **One week missing:** `bip_2016-09-06.csv` was never written (2016-09-06 to 09-12, 7 game
    dates), because `fetch_statcast.sh` does not check curl's exit status. Rerunning the script fills
    it. 2016 Retrosheet balls in play match at 96.0% instead of 99.8-100%.
  - Exit velocity or launch angle missing on 3.4% of 2015 balls, falling to 0.2-0.4% from 2021.
  - Statcast feeds only the v3 and v3h ablations (`PIT_SC=1`, `HIT_X>0`), which lost and were
    dropped; no frozen model reads it.

## Chadwick register

- **What.** The Chadwick Bureau person register: one row per person with ids across MLBAM,
  Retrosheet, Baseball-Reference, FanGraphs and others. Used to map MLBAM ids (StatsAPI, Savant)
  to Retrosheet and Baseball-Reference ids.
- **URL.** https://github.com/chadwickbureau/register, read through `baseballr::chadwick_player_lu()`.
- **License.** Open Data Commons Attribution License 1.0
  (http://opendatacommons.org/licenses/by/1.0/): attribute the Chadwick Bureau register when
  sharing data built from it.
- **Retrieval.** `fetch_cache.R mlb` on 2026-09-30, cached as `register.rds` (520,934 rows).
- **Grain and key.** Person, `key_person`. `key_mlbam` (129,732 present), `key_retro` (25,543) and
  `key_bbref` (23,982) are each unique where present.
- **Known gaps.** None found for this pipeline: every Statcast batter and pitcher, every Retrosheet
  batter and pitcher, and every backtest probable starter resolves. A newer snapshot may differ.

## Baseball-Reference daily windows

- **What.** 15-day trailing batting and pitching lines for every as-of date, through
  `baseballr::bref_daily_batter()` and `bref_daily_pitcher()`. Only the 2019 backtest
  (`backtest.R`, `results/backtest-*.md`) reads them.
- **Terms.** Sports Reference's data use policy allows reuse of facts for personal research but
  prohibits automated access "without our express written permission, use any automated means to
  access or use the Site, including scripts, bots, scrapers". The cached pulls were made that way
  (paced at 8 s a call). Keep them local, never redistribute, and treat the backtest's dependence on
  them as a terms risk.
- **Retrieval.** `fetch_cache.R batter|pitcher 2016 2019` on 2026-09-30 and 2026-10-01; 687 windows
  per source.
- **Rows by season.** Batting: 2016 92390, 2017 92975, 2018 95098, 2019 98090. Pitching: 2016 75805,
  2017 77785, 2018 81767, 2019 86553.

## SportsBookReview odds (ArnavSaraogi/mlb-odds-scraper)

- **What.** A scrape of SportsBookReview's MLB odds pages, released as one JSON file keyed by date.
  Per game: teams, final score, status, game type, venue, start time, and per book the opening and
  current moneyline, spread and total. Books named: bet365, BetMGM, BetRivers NY, Caesars,
  DraftKings, FanDuel.
- **URL.** https://github.com/ArnavSaraogi/mlb-odds-scraper, release `dataset`, asset
  `mlb_odds_dataset.json` (published 2025-08-18, 80,120,813 bytes, same size as the local file).
- **License.** None: the repository has no LICENSE file and GitHub reports no license. **Private
  research only. Never commit the file or copy any of its rows; only aggregates leave
  `data/mlb/raw/odds/`.** Derived per-game files (`market-joined.csv`, `totals-*.csv`, and
  `data/mlb/matchup/`) are gitignored for the same reason.
- **Retrieval.** Downloaded 2026-10-04.
- **Grain and key.** One entry per game under its date key. No game id: unique on (date key, home
  name, away name, start time); the joins use (date key, both names, final score). The date key is
  the Eastern date of first pitch (100% of rows; 75.6% match the UTC date).
- **Rows by season.**

  | | 2021 | 2022 | 2023 | 2024 | 2025 |
  |---|---|---|---|---|---|
  | entries | 2388 | 2671 | 2888 | 2894 | 2280 |
  | spring, All-Star, postseason | 38 | 308 | 499 | 495 | 451 |
  | regular season matched to StatsAPI | 2189 | 2360 | 2381 | 2394 | 1693 |

- **Known gaps.**
  - **Sept-Oct 2021 "current" lines are in-game scrapes**: 36% (September) and 60% (October) of
    games moved more than 15 points of no-vig probability from the open, against at most 1.51% in
    any other month, and closing log loss falls to 0.52 and 0.40. Those 394 matched games are
    excluded by every study (2021-09-01 to 2021-12-31).
  - **Odds end 2025-08-16** (1,850 of 2,430 StatsAPI games in 2025 fall in range) and start
    2021-04-01, not the 2021-03-20 the README states.
  - **No timestamps.** Neither the opening nor the current line carries a time. "Current" on a
    finished game is the last price scraped, taken as the close; the open's time is unknown, so an
    "open" bet has no known placement time.
  - **Team names that never match StatsAPI in the moneyline join**: 2021 Cleveland appears as
    "Cleveland Guardians" (StatsAPI: Indians, 154 rows) and 2025 Oakland as "Athletics Athletics"
    (StatsAPI: Athletics, 131 rows). `market_study.R`'s normaliser does not catch either, so those
    games are missing from `market-joined.csv` and from every market comparison built on it (the
    2021 market validation and the 2025 test season). `totals_study.R` maps names to Retrosheet
    codes by majority vote and keeps them.
  - The file also holds 1,791 spring training, All-Star and postseason rows; the joins drop them.
  - Books per game vary; 0.3% (2021) to 6.5% (2025) of entries have no moneyline at all. The
    best-of-books price includes stale quotes (MARKET-PLAN.md it 2), so no rule relies on it.

## Reconciliation headline (data-audit.md)

- Retrosheet vs StatsAPI: 25,155 of 25,191 games (99.86%) agree on date, both teams and final score;
  no score or date disagreements; 36 home/away swaps; 2 StatsAPI-only games (2018 tiebreakers).
- Statcast to Retrosheet balls in play: 99.54% matched (96.02% in 2016 for the missing week, 99.8%
  or better otherwise); outcome scoring agrees on 99.5-99.9% of matched balls.
- Odds to StatsAPI: 97.3% of final regular-season odds games matched (93.2% in 2021 and 92.6% in 2025
  for the name defects, 99.7% or better otherwise).
- Duplicate keys: none, apart from same-score doubleheaders (by design) and the one traded-player row.
