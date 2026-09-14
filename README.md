# baseball-analytics

Pitch-level baseball modeling at two levels. The NCAA half is a transfer-portal scouting
platform the University of San Diego coaching staff uses: seven ingest sources feed a tested
warehouse, ten trained models score players, and two Streamlit apps and a row-level-secured
board put the output in front of coaches. The MLB half is where the same methods get validated
against far more data: run expectancy and win probability over full seasons, Statcast arm-angle
and pitch modeling, and a top-25 finish in the Nick Wan / NWDS batted-ball competition.

The pairing is the point. The NCAA work shows the models ship to real users on a deadline. The
MLB work shows they are not one school's quirk.

```
sources ──▶ ingest/dedupe/resolve ──▶ SQLite + dbt warehouse ──▶ models ──▶ apps + board
D1Baseball                            staging / intermediate      Stuff+     hitter app
VerbalCommits                         / marts, contracts          xWhiff     pitcher app
X/Twitter                             + source freshness          xSLG       Netlify board
CSV paste                                                         run value  (Supabase RLS)
PerfectGame bio
Sidearm bio
TrackMan
```

## What is in here

| Area | Size | Notes |
|---|---|---|
| `src/ncaa/portal/` | 28 files, 5,294 lines | Portal ingest, dedupe, entity resolution, enrichment, geo, program tier, rollup, fit scoring, alerts |
| `src/ncaa/pbp/` | 24 files, 6,444 lines | NCAA play-by-play acquisition (Playwright plus `ncaa-api.henrygd.me`), situational "battle" scoring, season PDF reports |
| `src/ncaa/cli.py` | 336 lines | `init`, `import-excel`, `ingest`, `enrich-643`, `evaluate`, `board`, `run-all` |
| `warehouse/` | 18 SQL files, 925 lines | dbt-duckdb rebuild of the transform layer, with model contracts, source freshness and sample fixtures |
| `apps/hitter/`, `apps/pitcher/` | 5,275 lines | The two Streamlit apps coaches open, with their 10 model artifacts |
| `scripts/` | 19 files | NCAA bio fetchers (D1/D2/D3/portal), school geocoding, Excel import and export, board HTML build, Netlify publish, Supabase RLS verify |
| `tests/` plus the pbp test | 14 pytest files | bio, board, d1baseball, dedupe, geo, overlay, RLS schema, pipeline, program tier, resolve, rollup, speed, status, battle calc |
| `research/notebooks/` | 21 notebooks | 8 MLB, 13 NCAA, outputs stripped. Every shipped model was trained in one of these |
| `research/r/` | R | `baseballr` NCAA export, and the legacy MLB run-expectancy pipeline |
| `docs/` | 11 design docs | Pipeline design, 2026 sourcing, capabilities and blockers, Netlify and Supabase recipes, the consolidation plan |

Model provenance, which notebook trained which artifact: [`models/README.md`](models/README.md).

## Production versus research, stated plainly

The two Streamlit apps and the coach board are in active use. The dbt warehouse is a staged
rebuild of the transform layer and has **not** cut over; the SQLite pipeline is still what runs.
Everything under `research/` is exactly that, and several notebooks depend on a TruMedia or
6-4-3 export this repo does not carry.

## Quickstart

Real data ships with this repo, so a fresh clone runs without credentials.

```bash
pip install -e ".[scoring,ncaa-stats]"
python -m ncaa.cli init --force            # create db/baseball.db from db/schema.sql
python -m ncaa.cli import-excel            # seed from the committed workbook
python -m ncaa.cli evaluate                # compute fit scores
python -m ncaa.cli board --limit 150       # write data/hot_board.csv
```

Live sources need a `config.yaml` (copy `config.example.yaml`). The D1Baseball adapter needs a
session cookie, and the Supabase overlay needs project keys; both degrade to no-op without them,
so the rest of the pipeline still runs.

The apps pin numpy against each other, so install one per environment:

```bash
pip install -e ".[hitter]"  && streamlit run apps/hitter/streamlit_app.py
pip install -e ".[pitcher]" && streamlit run apps/pitcher/streamlit_app.py
```

The warehouse builds green from a clone with zero credentials, off the fixtures in
`warehouse/sample_data/`:

```bash
pip install -e ".[warehouse]" && cd warehouse && dbt build
```

## Sample output

`docs/samples/` holds real per-game battle reports the pbp pipeline generated for the 2026
season. `data/portal_board.html` is a published hot board.

## What this repo replaced

A manual Excel hot board plus a call-assignment spreadsheet. The interesting constraint was that
USD's `sso.ncaa.org` login needs a 2FA code from a coach on every use, so roughly 90 percent of
the workflow is built to need no login at all: entries are detected from public sources, stats
come from `collegebaseball` against `stats.ncaa.org`, and the login is spent only on contact
fields for the top call targets. `docs/transfer-portal-pipeline.md` has the full design.

## Data and attribution

Real TrackMan and portal exports are committed on purpose, because an app nobody can start is a
screenshot. The files name individual athletes and carry player IDs. USD branding, names and
data are used with permission.

Secrets are a separate matter and are not committed: `config.yaml`, `secrets/`, `.env`, keys and
service-account JSON are all ignored, and `git ls-files` is checked against that list before any
push.
