# What to pull from 6-4-3 Charts (643charts.com)

For each metric: **pull it from 6-4-3 if they have it — otherwise pull the underlying data points
and the pipeline derives it.** 6-4-3 has no public API, so the path is CSV export → drop in
`data/643_exports/` → run the importer.

## The principle (read this first)

Metrics come in three buckets:

- 🟣 **Your models — never in 6-4-3.** Stuff+, xWhiff, xSLG, decision value. Always computed by
  *your* models from **raw pitch data**. There is no "pull" option; you make these.
- 🟢 **Raw-derivable.** EV, EV90, HardHit%, Barrel%, GB%, Pull%, K%, Chase%, Z-Con%, SwStr%,
  Strike%, Whiff%, InZone-Whiff%, Ground%. Pull the % from 6-4-3 if handy, **but if it's not
  available, the raw pitch export computes all of these for free** (same data Stuff+/xSLG need).
- 🔵 **Composite / proprietary — pull-only (or box score).** xwOBA, AVG/OBP/SLG, wOBA, FIP, K/BB,
  SLG-against, Perceived Value, SEAGER. These need season outcome counts or 6-4-3's proprietary
  math — the raw pitch export can't reconstruct them. Pull these as numbers.

**Upshot:** if 6-4-3 will export **raw pitch-by-pitch data**, that one file gives you Stuff+/xSLG
**and** every 🟢 metric. You then only need 6-4-3's aggregate numbers for the 🔵 composites.

Pull up to four things: (A) Portal HQ entries, (B) hitter metrics, (C) pitcher metrics,
(D) raw pitch data.

---

## A. Portal HQ — the portal-entry list  ☐

The "who's in the portal" side, and your best **D2/D3** coverage (D1Baseball is D1-only).
Per player: ☐ Name (req) · ☐ Previous school · ☐ Position · ☐ Class/eligibility · ☐ Division ·
☐ Status (entered/committed/withdrawn) + date · ☐ 6-4-3 Player ID (for cross-ref).
Save → `data/643_exports/portal_hq_entries.csv`.

---

## B. Hitter metrics  ☐  → `data/643_exports/hitters_2026.csv`

Name column required. Header spelling/case/% don't matter (importer normalizes).

| Pull this metric | Bucket | Maps to | If unavailable, pull these raw data points instead |
|---|---|---|---|
| AVG / OBP / SLG | 🔵 | `ba`/`obp`/`slg` | season PA outcomes (AB, H, BB, TB) — box score |
| **xwOBA** | 🔵 | `xwoba` | (model metric — pull it; or use your `xslg` from raw instead) |
| wOBA | 🔵 | `woba` | season outcome counts |
| HR / SB | 🔵 | `hr`/`sb` | box score |
| SEAGER | 🔵 | `seager` | proprietary — **pull-only** |
| Avg EV / 90 EV | 🟢 | `avg_ev`/`ev90` | **ExitSpeed** per batted ball |
| HardHit% | 🟢 | `hardhit_pct` | **ExitSpeed** (≥95 / BIP) |
| Barrel% | 🟢 | `barrel_pct` | **ExitSpeed + Angle** |
| GB% | 🟢 | `gb_pct` | **Angle** (or TaggedHitType) |
| Pull% | 🟢 | `pull_pct` | **Direction + BatterSide** |
| K% | 🟢 | `k_pct` | **KorBB** per PA |
| Chase% / Z-Con% / SwStr% | 🟢 | `chase_pct`/`zcon_pct`/`swstr_pct` | **PitchCall + PlateLocSide/Height** |
| — xSLG, decision value | 🟣 | `xslg`/`decision_value` | **your models** — never pulled; see D |

---

## C. Pitcher metrics  ☐  → `data/643_exports/pitchers_2026.csv`

Separate file (importer auto-detects pitching by IP/FIP).

| Pull this metric | Bucket | Maps to | If unavailable, pull these raw data points instead |
|---|---|---|---|
| IP | 🔵 | `ip` | box score |
| FIP | 🔵 | `fip` | season HR, BB, HBP, K, IP — box score |
| K/BB | 🔵 | `k_bb` | season K, BB counts |
| SLG against | 🔵 | `slg_against` | PA outcomes allowed |
| Perceived Value | 🔵 | `perceived_value` | proprietary — **pull-only** |
| HardHit% | 🟢 | `hardhit_pct` | **ExitSpeed** allowed |
| Ground% | 🟢 | `ground_pct` | **Angle** (or TaggedHitType) |
| Strike% / Miss% | 🟢 | `strike_pct`/`miss_pct` | **PitchCall** |
| InZone Whiff% / Chase% | 🟢 | `inzone_whiff_pct`/`chase_pct` | **PitchCall + PlateLocSide/Height** |
| — **Stuff+**, per-pitch Stuff+, xWhiff | 🟣 | `t2_stuff`/`*_stuff`/`xwhiff_pct` | **your model** — never pulled; see D |

---

## D. Raw pitch-by-pitch data — powers your models AND every 🟢 metric  ☐

Your Stuff+/xSLG/xWhiff/decision models score **per pitch**, so you need **raw TrackMan/Synergy
pitch rows** for the players you evaluate (same schema as `pitcher-app/data/raw/usd_baseball_TM_master_file.csv`).
You have this for USD + opponents; for **portal players at other schools you don't** — and 6-4-3
(it integrates Synergy/Trackman across schools) is the candidate source.

**🔎 First verify in 6-4-3:** can you export **pitch-by-pitch / raw Trackman**, or only aggregates?
If only aggregates, you can't compute Stuff+/xSLG for non-USD players from 6-4-3 — that's the blocker to solve.

**Raw columns the models + 🟢 metrics need** (standard TrackMan v3 names; extra columns harmless):

- **Pitchers:** ☐ Pitcher · ☐ PitcherThrows · ☐ AutoPitchType · ☐ **RelSpeed** · ☐ **SpinRate** ·
  ☐ **InducedVertBreak** · ☐ **HorzBreak** · ☐ **RelHeight** · ☐ **RelSide** · ☐ **Extension** ·
  ☐ PitchCall · ☐ PlateLocSide · ☐ PlateLocHeight · ☐ PitchUID · ☐ Date
- **Hitters:** ☐ Batter · ☐ BatterSide · ☐ **ExitSpeed** · ☐ **Angle** · ☐ Direction ·
  ☐ **PlateLocSide** · ☐ **PlateLocHeight** · ☐ Balls · ☐ Strikes (or Count) · ☐ PitchCall ·
  ☐ PlayResult · ☐ KorBB · ☐ PitchUID · ☐ Date

Practically: **export the whole pitch-by-pitch table** per player/team. Save anywhere, e.g.
`data/643_exports/raw_trackman_<x>.csv`.

---

## E. Load it  ☐

```powershell
python run.py enrich-643 --dir data/643_exports          # A/B/C: metrics + portal entries
python run.py enrich-trackman --csv data/643_exports/raw_trackman_<x>.csv   # D: YOUR Stuff+/xSLG + 🟢 metrics
python run.py evaluate
python run.py board --limit 150                          # or: python run.py run-all
```

Safe to re-run (upsert on `player_id, season, source`). Stuff+ → `t2_stuff` (+ per-pitch),
xSLG/decision → hitter columns — all from `enrich-trackman`, not 6-4-3.

---

## Scope / tips

- **Season:** current (2026) — 6-4-3 is the current-season source (`collegebaseball` ends 2023).
- **The Stuff+ gate:** Stuff+/xSLG on a portal player is only possible with that player's **raw
  pitch data**. Confirm 6-4-3 exports pitch-level; if not, that's the next blocker.
- **Minimum viable pull:** if 6-4-3 gives raw pitch data, you only *also* need the 🔵 composites
  (xwOBA, AVG/OBP/SLG, FIP, K/BB, SLG-against, PV, SEAGER) — everything else derives from raw.
- **Primary perf signals:** pitchers rank on `t2_stuff` (your Stuff+) + FIP/PV; hitters on `xwoba`
  (6-4-3) + `xslg` (your model). Pull the 🔵 half, compute the 🟣/🟢 half from raw.
