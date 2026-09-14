# `data/643_exports/` — drop 6-4-3 Charts CSV exports here

This is the inbox the pipeline scans for **6-4-3 Charts advanced-metric CSVs**
(`enrichment.six_four_three.inbox_dir` in `config.yaml`). 6-4-3 has no public API,
so the integration path is: **export CSV from 643charts.com → save it here → run the
importer.** Files here are gitignored (licensed data — internal USD evaluation only).

```powershell
python run.py enrich-643 --dir data/643_exports    # imports every ingestable *.csv here
python run.py evaluate                              # re-score
python run.py board --limit 150                     # or: python run.py run-all
```

## What gets imported

`cmd_enrich_643` globs `*.csv` in this folder and skips files whose name starts with
`sample_`, `demo_`, or `test_`. Season + split are inferred from the **filename**:

- a 4-digit year → the season (e.g. `hitters_2026_overall.csv` → season `2026`)
- `_vlhp` / `_vrhp` in the name → a split-tagged source (`643-vlhp` / `643-vrhp`) so
  platoon lines don't collide with the overall line on `UNIQUE(player_id, season, source)`

Hitting vs. pitching is **auto-detected** from the columns (presence of `IP`/`FIP` or any
`*stuff` column ⇒ pitching). Re-running is safe — rows upsert on `(player_id, season, source)`.

## Required + accepted columns

**A name column is the only hard requirement.** Header spelling, case, spaces, and `%`
don't matter — the importer normalizes them (`HardHit %` == `HardHitPct` == `hardhit`).
Accepted name headers: `Name`, `Player`, `PlayerName`, `PlayerFullName`, `FullName`.

Every other column is optional; unmapped columns are ignored. These are the headers the
importer maps to schema fields (any spelling that normalizes to the alias works):

### Hitters → `stats_hitting`
`Team`/`School`, `PA`, `Pitches`, `AVG`/`BA`, `OBP`, `SLG`, `xwOBA`, `wOBA`, `HR`, `SB`,
`Avg EV`/`EV`, `EV 90`, `HardHit %`/`HH%`, `Barrel%`, `Barrels`, `BBE`, `GB%`, `FB%`, `LD%`,
`Pull%`, `K%`, `Z-Contact%`, `Chase%`, `Whiff%`/`SwStr%`, `SwSpot%`, `LA`, `Max EV`, `xBA`,
`Swing%`, `Z-Swing%`, `SD+`, `SEAGER`.

Minimal viable hitter file (what `sample_hitting.csv` shows):
```
Player,School,PA,AVG,OBP,SLG,xwOBA,HR,SB,HardHit %,K %,Chase%,SEAGER
```

### Pitchers → `stats_pitching`  (auto-detected by `IP`/`FIP`/`*stuff`)
`Team`/`School`, `Level`, `IP`, `FIP`, `SLG against`, `K/BB`, `Perceived Value`/`PV`,
`HardHit%`, `Ground%`/`GB%`, `Strike%`, `Miss%`, `InZone Whiff%`, `Chase%`, `T2 Stuff`/`Stuff`,
per-pitch `FB Stuff`/`SL Stuff`/`CB Stuff`/`CH Stuff`/`CT Stuff`/`SI Stuff` and the matching
`*Strike%` columns.

> Put hitters and pitchers in **separate files**. One file per season (and optionally per
> split). Naming convention that matches what's already here:
> `hitters_2026_overall.csv`, `hitters_2026_vlhp.csv`, `pitchers_2026.csv`.

## Portal HQ entries (the "who's in the portal" list)

Save the Portal HQ export as `portal_hq_entries.csv` (see `docs/643-pull-checklist.md` §A).
Columns: Name (req), Previous school, Position, Class/eligibility, Division, Status
(entered/committed/withdrawn) + date, 6-4-3 Player ID.

## The models 6-4-3 will NOT give you (compute from raw)

Stuff+, xWhiff, xSLG, and swing-decision value are **your** models — never a 6-4-3 column.
They need **raw pitch-by-pitch** data (TrackMan/Synergy). If 6-4-3 can export raw pitch rows,
save them anywhere here (e.g. `raw_trackman_<x>.csv`) and run
`python run.py enrich-trackman --csv <path>`. Full column list: `docs/643-pull-checklist.md` §D.
