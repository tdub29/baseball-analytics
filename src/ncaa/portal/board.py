"""Build the fit-scored hot board and export it.

export_board() always writes a CSV (works with zero credentials). If
google_sheet.enabled and gspread + a service account are configured, it also
pushes the board to a tab in your Google Sheet.
"""
from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]

BOARD_SQL = """
SELECT
    e.fit_score                              AS fit,
    pl.full_name                             AS player,
    json_extract(e.components,'$.role')      AS role,
    pl.position, pl.division, pl.from_school, pl.to_school,
    pl.class_year, pl.eligibility_remaining, pl.height_in, pl.weight_lb,
    pl.current_status                        AS status,
    pl.ca_tie, pl.sd_tie, pl.socal_tie,
    pl.hometown_city, pl.hometown_state, pl.high_school, pl.ca_tie_reasons,
    json_extract(e.components,'$.hit_tool')   AS hit,
    json_extract(e.components,'$.power_grade') AS power,
    json_extract(e.components,'$.need_label') AS need,
    json_extract(e.components,'$.perf_pct')  AS perf_pct,
    json_extract(e.components,'$.level')     AS level_factor,
    json_extract(e.components,'$.likelihood') AS likelihood,
    COALESCE(sh.team, sp.team)               AS team,
    sh.pa, sh.ba, sh.obp, sh.slg, sh.xwoba, sh.xslg, sh.avg_ev,
    sh.decision_value, sh.hr,
    COALESCE(bx.ip, sp.ip) AS ip, COALESCE(bx.fip, sp.fip) AS fip,
    COALESCE(sp.k_bb, bx.k_bb) AS k_bb, sp.perceived_value, sp.t2_stuff,
    sp.inzone_whiff_pct, sp.xwhiff_pct,
    ca.priority, ca.contact, ca.scout_notes
FROM evaluations e
JOIN players pl              ON pl.player_id = e.player_id
LEFT JOIN stats_hitting sh  ON sh.id = (
    SELECT id FROM stats_hitting x WHERE x.player_id = e.player_id
    ORDER BY COALESCE(x.pa,0) + COALESCE(x.pitches,0) DESC, x.id LIMIT 1)
-- "stuff" line (Stuff+/per-pitch, 6-4-3) + "box" line (IP/FIP, box-score) merged per-column
-- so a pitcher shows both, since 6-4-3 exports carry no innings (see build_html PIT_SQL).
LEFT JOIN stats_pitching sp ON sp.id = (
    SELECT id FROM stats_pitching x WHERE x.player_id = e.player_id
    ORDER BY COALESCE(x.pitches,0) DESC, COALESCE(x.ip,0) DESC, x.id LIMIT 1)
LEFT JOIN stats_pitching bx ON bx.id = (
    SELECT id FROM stats_pitching x WHERE x.player_id = e.player_id
    AND x.ip IS NOT NULL ORDER BY COALESCE(x.ip,0) DESC, x.id LIMIT 1)
LEFT JOIN call_assignments ca ON ca.id = (
    SELECT id FROM call_assignments c WHERE c.player_id = e.player_id LIMIT 1
)
-- Only players still IN the portal and uncommitted. `evaluate` already scores
-- only ENTERED players, but a stale evaluation row survives after a player
-- commits/withdraws, so guard the board here too — COMMITTED/WITHDRAWN never show.
WHERE pl.current_status = 'ENTERED'
-- Rating is the 20-80 OFP (capped at 80), so break ties with the pre-rescale composite.
ORDER BY e.fit_score DESC, CAST(json_extract(e.components,'$.rating_0_100') AS REAL) DESC
"""


def build_board(con: sqlite3.Connection, limit: int | None = None) -> pd.DataFrame:
    df = pd.read_sql_query(BOARD_SQL, con)
    # flatten scout_notes json -> readable text
    def _notes(v):
        if not v:
            return None
        try:
            d = json.loads(v)
            return " | ".join(f"{k}: {x}" for k, x in d.items() if x)
        except Exception:
            return v
    df["scout_notes"] = df["scout_notes"].map(_notes)
    if limit:
        df = df.head(limit)
    return df


def top_per_group(con: sqlite3.Connection, group_col: str, n: int = 15) -> pd.DataFrame:
    """Top-N players per group (group_col in {'role','need','position','division'}).

    Use this so strong hitters aren't buried under a large pitcher pool in the
    global ranking — the global board is need-weighted, this is per-bucket.
    """
    df = build_board(con)
    if group_col not in df.columns:
        raise ValueError(f"group_col must be one of {list(df.columns)}")
    return (df.sort_values("fit", ascending=False)
              .groupby(df[group_col].fillna("(none)"), group_keys=False)
              .head(n)
              .reset_index(drop=True))


def export_board(con: sqlite3.Connection, config: dict, *,
                 csv_path: str | Path | None = None, limit: int | None = None,
                 per: str | None = None, top: int = 15) -> dict:
    if per:
        df = top_per_group(con, per, top)
    else:
        df = build_board(con, limit=limit)
    out = Path(csv_path) if csv_path else ROOT / "data" / "hot_board.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out, index=False)
    result = {"rows": len(df), "csv": str(out), "google_sheet": "skipped"}

    gs = (config or {}).get("google_sheet") or {}
    if gs.get("enabled"):
        try:
            result["google_sheet"] = _push_to_sheet(df, gs)
        except Exception as e:
            result["google_sheet"] = f"error: {e}"
    return result


def _push_to_sheet(df: pd.DataFrame, gs: dict) -> str:
    import gspread
    from google.oauth2.service_account import Credentials

    scopes = ["https://www.googleapis.com/auth/spreadsheets"]
    creds = Credentials.from_service_account_file(gs["service_account_json"], scopes=scopes)
    client = gspread.authorize(creds)
    sh = client.open_by_key(gs["spreadsheet_id"])
    tab = gs.get("board_tab", "Hot Board (auto)")
    try:
        ws = sh.worksheet(tab)
        ws.clear()
    except gspread.WorksheetNotFound:
        ws = sh.add_worksheet(title=tab, rows=str(len(df) + 10), cols=str(len(df.columns) + 2))
    df2 = df.where(pd.notna(df), "")
    ws.update([df2.columns.tolist()] + df2.values.tolist())
    return f"pushed {len(df)} rows to '{tab}'"
