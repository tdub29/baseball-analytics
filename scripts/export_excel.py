#!/usr/bin/env python
"""Export a hot-board workbook that MIRRORS the 2025 Transfer Portal Main Database.

    python scripts/export_excel.py            # -> data/portal_board.xlsx

Sheets mirror the inspo workbook's layout (same column names/order), with FIT and
a few model value-adds prepended:
  - Hitter Hot Board Data   (Name, Team, POS, B, T, PA, BA, OBP, SLG, xWOBA, ...)
  - Pitcher Hot Board Data  (Name, School, T, IP, FIP, ..., CB/CH/CT/FB/SI/SL - stuff+)
  - Hot List - Call Assignments (CRM: Date, First, Last, Div, School, ..., Notes)
  - Pitch Arsenal (per pitch)   (per-pitcher x pitch detail — the source of truth)
  - California Board            (CA/SD recruiting ties)
Inspo: C:/Users/TrevorWhite/Downloads/2025 Transfer Portal Main Database (1).xlsx
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pandas as pd
from openpyxl.formatting.rule import ColorScaleRule
from openpyxl.utils import get_column_letter

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
from ncaa.portal.db import connect  # noqa: E402

# Conditional formatting is applied to EVERY numeric stat column. Default direction
# is +1 (higher=greener); columns in a sheet's LOWER set flip to -1 (red=high).
# Binary flag columns are never shaded.
FLAG_COLS = {"CA", "SD", "SoCal", "Wt", "Ht", "Year"}
LOWER_BY_SHEET = {
    "Hitter Hot Board Data": {"K%", "Chase%", "SwStr%", "GB%"},
    "Pitcher Hot Board Data": {"FIP", "SLG", "HH%"},
    "Pitch Arsenal (per pitch)": {
        "EV", "HH%", "Barrel%", "BA", "xBA", "wOBA", "xwOBA", "Z-Con%", "Brls"},
}

# Hitter Hot Board Data — inspo column order, FIT + xSLG/DecVal/geo appended.
HIT_SQL = """
SELECT ROUND(e.fit_score,1) AS "Rating", ROUND(json_extract(e.components,'$.likelihood'),1) AS "Get%",
       ROUND(json_extract(e.components,'$.hit_tool'),1) AS "Hit",
       ROUND(json_extract(e.components,'$.power_grade'),1) AS "Pwr",
       ROUND(json_extract(e.components,'$.speed_grade'),1) AS "Spd",
       pl.full_name AS "Name", COALESCE(sh.team,'') AS "Team",
       pl.position AS "POS", pl.bats AS "B", pl.throws AS "T",
       pl.division AS "Lvl_raw", sh.level AS "Slevel",
       pl.class_year AS "Year", pl.height_in AS "Ht_in", pl.weight_lb AS "Wt",
       sh.pa AS "PA", sh.ba AS "BA", sh.obp AS "OBP", sh.slg AS "SLG",
       sh.xwoba AS "xWOBA", sh.woba AS "wOBA", sh.hr AS "HR", sh.sb AS "SB",
       sh.xba AS "xBA", sh.avg_ev AS "AVG EV", sh.ev90 AS "90EV", sh.max_ev AS "Max EV",
       sh.hardhit_pct AS "HardHit%", sh.barrel_pct AS "Barrel%", sh.barrels AS "Brls",
       sh.swspot_pct AS "SwSpot%", sh.la AS "LA", sh.gb_pct AS "GB%", sh.fb_pct AS "FB%",
       sh.ld_pct AS "LD%", sh.pull_pct AS "Pull%", sh.k_pct AS "K%",
       sh.swing_pct AS "Swing%", sh.zswing_pct AS "Z-Swing%", sh.zcon_pct AS "Z-Con%",
       sh.chase_pct AS "Chase%", sh.swstr_pct AS "SwStr%", sh.sd_plus AS "SD+",
       sh.bbe AS "BBE", sh.xslg AS "xSLG", sh.decision_value AS "DecVal",
       pl.from_school AS "From School", pl.eligibility_remaining AS "Elig",
       pl.hometown_city AS "Hometown", pl.hometown_state AS "ST", pl.ca_tie AS "CA", pl.sd_tie AS "SD", pl.socal_tie AS "SoCal"
FROM evaluations e JOIN players pl ON pl.player_id = e.player_id
LEFT JOIN stats_hitting sh ON sh.id = (
    SELECT id FROM stats_hitting x WHERE x.player_id = e.player_id
    ORDER BY COALESCE(x.pa,0)+COALESCE(x.pitches,0) DESC, x.id LIMIT 1)
WHERE json_extract(e.components,'$.role') = 'hitter' AND pl.current_status = 'ENTERED'
ORDER BY e.fit_score DESC
"""

# Pitcher Hot Board Data — inspo order incl. per-pitch stuff+, FIT + fastball shape.
PIT_SQL = """
SELECT ROUND(e.fit_score,1) AS "Rating", ROUND(json_extract(e.components,'$.likelihood'),1) AS "Get%",
       pl.full_name AS "Name", pl.from_school AS "School", pl.throws AS "T",
       pl.division AS "Lvl_raw", sp.level AS "Slevel",
       pl.class_year AS "Year", pl.height_in AS "Ht_in", pl.weight_lb AS "Wt",
       COALESCE(bx.ip, sp.ip) AS "IP", COALESCE(bx.fip, sp.fip) AS "FIP",
       COALESCE(sp.slg_against, bx.slg_against) AS "SLG", COALESCE(sp.k_bb, bx.k_bb) AS "K/BB",
       sp.hardhit_pct AS "HH%", sp.ground_pct AS "GB%", sp.strike_pct AS "Strike%",
       sp.miss_pct AS "Miss%", sp.inzone_whiff_pct AS "IZWhiff%", sp.chase_pct AS "Chase%",
       sp.t2_stuff AS "STUFF+",
       sp.cb_stuff AS "CB - stuff+", sp.ch_stuff AS "CH - stuff+", sp.ct_stuff AS "CT - stuff+",
       sp.fb_stuff AS "FB - stuff+", sp.si_stuff AS "SI - stuff+", sp.sl_stuff AS "SL - stuff+",
       sp.fb_velo AS "FB velo", sp.fb_ivb AS "FB iVB", sp.fb_hb AS "FB HB",
       pl.eligibility_remaining AS "Elig",
       pl.hometown_city AS "Hometown", pl.hometown_state AS "ST", pl.ca_tie AS "CA", pl.sd_tie AS "SD", pl.socal_tie AS "SoCal"
FROM evaluations e JOIN players pl ON pl.player_id = e.player_id
-- "stuff" line (Stuff+/per-pitch) + "box" line (IP/FIP) merged per-column (see build_html PIT_SQL)
LEFT JOIN stats_pitching sp ON sp.id = (
    SELECT id FROM stats_pitching x WHERE x.player_id = e.player_id
    ORDER BY COALESCE(x.pitches,0) DESC, COALESCE(x.ip,0) DESC, x.id LIMIT 1)
LEFT JOIN stats_pitching bx ON bx.id = (
    SELECT id FROM stats_pitching x WHERE x.player_id = e.player_id
    AND x.ip IS NOT NULL ORDER BY COALESCE(x.ip,0) DESC, x.id LIMIT 1)
WHERE json_extract(e.components,'$.role') = 'pitcher' AND pl.current_status = 'ENTERED'
ORDER BY e.fit_score DESC
"""

# Hot List / Call Assignments — the CRM sheet (mirrors inspo).
CALL_SQL = """
SELECT ca.assigned_date AS "Date", pl.first_name AS "First", pl.last_name AS "Last",
       pl.division AS "Div", pl.from_school AS "School", pl.summer_team AS "Summer Team",
       ca.priority AS "Priority", pl.class_year AS "Year", pl.position AS "Pos",
       ca.contact AS "Contact", ca.notes AS "Notes", ca.scout_notes AS "Scout Notes"
FROM call_assignments ca JOIN players pl ON pl.player_id = ca.player_id
ORDER BY ca.priority, pl.last_name
"""

ARS_SQL = """
SELECT pl.full_name AS "Name", pl.from_school AS "School",
       (SELECT ROUND(e.fit_score,1) FROM evaluations e WHERE e.player_id=a.player_id AND json_extract(e.components,'$.role')='pitcher' LIMIT 1) AS "Rating",
       (SELECT ROUND(json_extract(e.components,'$.likelihood'),1) FROM evaluations e WHERE e.player_id=a.player_id AND json_extract(e.components,'$.role')='pitcher' LIMIT 1) AS "Get%",
       a.throws AS "T", a.season AS "Season",
       a.pitch_type AS "Pitch", a.pitches AS "P", a.bbe AS "BBE", a.barrels AS "Brls",
       a.velo AS "Velo", a.velo90 AS "Velo90", a.max_velo AS "Max Velo", a.spin AS "Spin",
       a.ivb AS "iVB", a.hb AS "HB", a.vaa AS "VAA", a.haa AS "HAA",
       a.rel_height AS "RelHt", a.rel_side AS "RelSide", a.extension AS "Ext",
       a.stuff_plus AS "Stuff+", a.location_plus AS "Loc+", a.xrv_plus AS "xRV+",
       a.anomaly_plus AS "Anom+", a.tunnel_plus AS "Tun+", a.predmovdiff_plus AS "PMD+",
       a.ev AS "EV", a.hardhit_pct AS "HH%", a.barrel_pct AS "Barrel%",
       a.ba AS "BA", a.xba AS "xBA", a.woba AS "wOBA", a.xwoba AS "xwOBA",
       a.swing_pct AS "Swing%", a.zcontact_pct AS "Z-Con%", a.chase_pct AS "Chase%", a.whiff_pct AS "Whiff%"
FROM pitch_arsenal a JOIN players pl ON pl.player_id = a.player_id
WHERE pl.current_status = 'ENTERED'
ORDER BY pl.full_name, a.season DESC, a.pitches DESC
"""


def fmt_ht(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return ""
    return f"{int(v)//12}'{int(v)%12}\"" if v else ""


# Level of competition -> readable D1/D2/D3/NAIA/JUCO (division I/II/III + finer 6-4-3
# stat-line codes; stat-line level wins when present, as it distinguishes JUCO/NAIA).
LEVEL_LABEL = {"BBC": "D1", "I": "D1", "1": "D1", "D1": "D1",
               "ND2": "D2", "II": "D2", "2": "D2", "D2": "D2",
               "ND3": "D3", "III": "D3", "3": "D3", "D3": "D3",
               "NAI": "NAIA", "NAIA": "NAIA", "JCO": "JUCO", "JUCO": "JUCO"}


def fmt_level(v):
    if v is None or (isinstance(v, float) and pd.isna(v)) or v == "":
        return ""
    return LEVEL_LABEL.get(str(v).strip().upper(), str(v).strip())


def _surface_bio(df):
    """Convert Ht_in -> formatted Ht, derive Lvl (D1/D2/...) from level codes, and seat
    Lvl/Year/Ht/Wt right after T."""
    if "Ht_in" in df.columns:
        df["Ht"] = df["Ht_in"].map(fmt_ht)
        df = df.drop(columns=["Ht_in"])
    if "Slevel" in df.columns and "Lvl_raw" in df.columns:
        df["Lvl"] = [fmt_level(s if pd.notna(s) else r)
                     for s, r in zip(df["Slevel"], df["Lvl_raw"])]
        df = df.drop(columns=["Slevel", "Lvl_raw"])
    if "T" in df.columns:
        cluster = [c for c in ("Lvl", "Year", "Ht", "Wt") if c in df.columns]
        rest = [c for c in df.columns if c not in cluster]
        ti = rest.index("T") + 1
        df = df[rest[:ti] + cluster + rest[ti:]]
    return df


def _flatten_notes(v):
    if not v:
        return None
    try:
        d = json.loads(v)
        return " | ".join(f"{k}: {x}" for k, x in d.items() if x)
    except Exception:
        return v


def main() -> None:
    con = connect()
    sheets = {
        "Hitter Hot Board Data": _surface_bio(pd.read_sql_query(HIT_SQL, con)),
        "Pitcher Hot Board Data": _surface_bio(pd.read_sql_query(PIT_SQL, con)),
        "Hot List - Call Assignments": pd.read_sql_query(CALL_SQL, con),
        "Pitch Arsenal (per pitch)": pd.read_sql_query(ARS_SQL, con),
    }
    con.close()
    if "Scout Notes" in sheets["Hot List - Call Assignments"]:
        sheets["Hot List - Call Assignments"]["Scout Notes"] = \
            sheets["Hot List - Call Assignments"]["Scout Notes"].map(_flatten_notes)
    cal = ROOT / "data" / "california_board.csv"
    if cal.exists():
        sheets["California Board"] = pd.read_csv(cal)

    out = ROOT / "data" / "portal_board.xlsx"
    shaded_counts: dict[str, int] = {}
    with pd.ExcelWriter(out, engine="openpyxl") as w:
        for name, df in sheets.items():
            sn = name[:31]
            df.to_excel(w, sheet_name=sn, index=False)
            ws = w.sheets[sn]
            ws.freeze_panes = "A2"
            if len(df):
                ws.auto_filter.ref = ws.dimensions   # native column filter/sort dropdowns
            # stat heatmap: 3-color scale on EVERY numeric column (skip flags + text),
            # reversed for the per-sheet lower-is-better set.
            lower = LOWER_BY_SHEET.get(name, set())
            n = len(df)
            shaded = 0
            for ci, col in enumerate(df.columns, start=1):
                if not n or col in FLAG_COLS or not pd.api.types.is_numeric_dtype(df[col]):
                    continue
                L = get_column_letter(ci)
                lo, hi = ("63BE7B", "F8696B") if col in lower else ("F8696B", "63BE7B")
                ws.conditional_formatting.add(
                    f"{L}2:{L}{n + 1}",
                    ColorScaleRule(start_type="percentile", start_value=5, start_color=lo,
                                   mid_type="percentile", mid_value=50, mid_color="FFEB84",
                                   end_type="percentile", end_value=95, end_color=hi))
                shaded += 1
            shaded_counts[name] = shaded
    print(f"wrote {out}")
    for name, df in sheets.items():
        print(f"  {name[:31]:31} {len(df):5} rows x {len(df.columns)} cols"
              f"  ({shaded_counts.get(name, 0)} cols shaded)")


if __name__ == "__main__":
    main()
