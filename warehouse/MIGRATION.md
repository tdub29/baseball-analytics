# Migration map — Python pipeline → dbt warehouse

This `warehouse/` reimplements the **transform / cleaning / rollup** layer of the
existing Python pipeline (`run.py` + `src/portal/`) as a dbt project. The cutover
is **staged and not yet applied**: `run.py` and `src/portal/` are unchanged.
Trevor flips `run.py` to read from the warehouse marts when ready. Nothing outside
`warehouse/` (plus one optional CI workflow) was touched.

## What maps to what

| Python (source of truth today) | dbt equivalent | Notes |
|---|---|---|
| `src/portal/trackman.load_trackman()` (cast numeric cols, lowercase headers, synth PitchUID) | `models/staging/stg_trackman__pitches.sql` | Same numeric coercions; `try_cast`; synthesizes a key only if `PitchUID` is null; drops the 201 null-pitcher tracking artifacts the same way `aggregate_pitching` skips `if not clean_str(pitcher)`. |
| `src/portal/trackman._pitch_flags()` (whiff / swing / strike / inzone) + hitter-app contact | `models/intermediate/int_pitches__enriched.sql` | Same `StrikeSwinging`/foul/InPlay/`ExitSpeed>0` logic; same zone box (height 1.5–3.5, \|side\| ≤ 0.83); `barrel_proxy` explicitly labelled a proxy. |
| `src/portal/arsenal._dim()` (strip units `"`, `'`, `°`) | `macros/clean_numeric.sql` | `regexp_replace('[^0-9.\-]','')` then cast; same empty/`-`/`.` → null guards. |
| `src/portal/util.to_float()` (strip `%`, `,`) | `macros/clean_numeric.sql` | Folded into the same macro (both strip non-numeric chars then cast). |
| `src/portal/arsenal._CODE` / `trackman._PITCH_CODE` (label → fb/si/sl/cb/ch/ct) | `macros/pitch_code.sql` | Same label→bucket map, case/space/hyphen-insensitive; Splitter→ch, Sweeper→sl, unknown→null. |
| `src/portal/util.name_key()` / `normalize_name()` | `macros/name_key.sql` | Lowercase, `strip_accents`, drop punctuation + suffixes, **sort tokens**. Scope note below. |
| `src/portal/arsenal.import_643_arsenal()` (load per-pitch arsenal, strip `Team\|logo`) | `models/staging/stg_643__pitch_arsenal.sql` | Same `split('|')[0]` team de-decoration; consumes Stuff+/Location+/xRV+ as-is (no recompute). |
| **`src/portal/rollup.rollup_arsenal()` + `_weighted_mean()`** | **`models/marts/mart_pitcher_arsenal.sql` + `macros/weighted_mean.sql`** | **The headline migration.** Pitches-weighted overall Stuff+ / per-code `{code}_stuff` / fb shape / `sum(pitches)`. Verified byte-equal to `_weighted_mean` on real USD pitchers (see `tests/assert_arsenal_rollup_reconciles.sql`). |
| `src/portal/trackman.aggregate_pitching()` (rate stats off flags) | `models/marts/mart_pitcher_season.sql` | Same `_rate(num,den)=round(100*num/den,1)` semantics. Stuff+/xWhiff (ML) NOT recomputed — they stay in Python. |
| 6-4-3 overall hitting load → `stats_hitting` | `models/staging/stg_643__hitting.sql` + `models/marts/mart_hitter_season.sql` | Typed conformed pass-through to the `stats_hitting` shape. |
| `INSERT OR REPLACE ... UNIQUE(player_id, season, source)` idempotency | `fct_pitch` incremental `unique_key='pitch_uid'` | Same idempotent-re-run guarantee, keyed on the immutable pitch id. |
| `scripts/init_db.py` + `db/schema.sql` table shapes | model contracts in `models/marts/_marts__models.yml` | Column names/types enforced on `fct_pitch` + dims at build time. |
| 18 pytest tests (`tests/`) | dbt generic + singular tests | Plus **new** data-quality gates the Python layer lacks (velo range, orphan check, rollup reconciliation). |

## Identity-grain difference (flagged, not hidden)

`rollup.py` groups by the **resolved `player_id`** — the Python pipeline runs a
fuzzy `Resolver` (`src/portal/resolve.py`) that merges a player across schools and
sources into one canonical id first. dbt consumes the already-exported CSVs and
has **no resolver**, so the marts key on **`(player, team)`** as the faithful
analogue. In the national 6-4-3 reference set, player names are not globally
unique (48 names appear on >1 team; a few exact `(player, team)` rows are
duplicated in the export). `(player, team)` is the correct grain here; exact
duplicates collapse in the GROUP BY (arsenal) or are deduped to the largest-sample
row (hitter). If/when the warehouse is wired downstream of the resolver, swap the
surrogate key to the resolved `player_id`.

## `name_key` scope (flagged)

`macros/name_key.sql` reproduces lowercase + de-accent + punctuation/suffix strip
+ token-sort. It intentionally does **not** reproduce the Python version's (a)
nickname expansion (`mike`→`michael`) or (b) single-letter-run merge (`a j`→`aj`)
— those exist to help *fuzzy entity resolution* in the Python loader, which is out
of dbt's scope (dbt consumes already-resolved exports). The macro gives a
deterministic accent/case/order-insensitive key, which is what the warehouse joins
need.

## Staged cutover checklist (for when Trevor is ready)

1. `dbt build` green on full data (it is — `PASS=58 WARN=1`, the warn = the 4 known bad-velo rows).
2. Point a thin read path in `src/portal/board.py` / `evaluate.py` at
   `mart_pitcher_arsenal` instead of the `rollup_arsenal()` output.
3. Keep `rollup.py` until the board has run a few cycles off the mart and matched.
4. Only then retire the Python rollup. `run.py` stays untouched until that point.
