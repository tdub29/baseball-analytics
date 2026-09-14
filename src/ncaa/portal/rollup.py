"""Per-pitcher rollup from the per-pitch `pitch_arsenal` table.

Pitchers are stored at their native 6-4-3 grain — one row per (player, season,
pitch type) — in `pitch_arsenal`. This module collapses that to one wide
`stats_pitching` line per (player, season), which is what the hot board and the
fit score consume:

  - overall quality numbers are *pitches-weighted* across the pitcher's mix
    (a pitcher throwing 70% fastballs is graded mostly on his fastball);
  - per-pitch Stuff+ fans out into the wide ``{code}_stuff`` columns;
  - fastball shape (velo/iVB/HB) comes from the ``code='fb'`` rows.

The upsert mirrors enrich.py: INSERT OR REPLACE on stats_pitching keyed by
UNIQUE(player_id, season, source), writing only non-null columns. The default
``source="643"`` marks the line as a 6-4-3-derived rollup.
"""
from __future__ import annotations

import sqlite3

from .db import now_iso

# normalized buckets that map to the wide stats_pitching {code}_stuff columns
_CODES = ("fb", "si", "sl", "cb", "ch", "ct")


def _weighted_mean(pairs) -> float | None:
    """Pitches-weighted mean, rounded to 1 dp.

    ``pairs`` is an iterable of (value, weight). Entries where either the value
    or the weight is None/NaN are ignored. Returns None if nothing usable or the
    total weight is zero.
    """
    num = 0.0
    den = 0.0
    for value, weight in pairs:
        if value is None or weight is None:
            continue
        # guard against NaN (NaN != itself) without importing math
        if value != value or weight != weight:
            continue
        num += value * weight
        den += weight
    if den == 0:
        return None
    return round(num / den, 1)


def rollup_arsenal(con: sqlite3.Connection, season: str | None = None,
                   source_out: str = "643") -> dict:
    """Derive one stats_pitching line per pitcher from pitch_arsenal.

    Reads pitch_arsenal (optionally filtered to ``season``), groups by
    (player_id, season), and upserts a pitches-weighted rollup into
    stats_pitching with source=``source_out``. Returns
    ``{"pitchers": N, "season": season}``.
    """
    sql = "SELECT * FROM pitch_arsenal"
    params: list = []
    if season is not None:
        sql += " WHERE season = ?"
        params.append(str(season))
    rows = con.execute(sql, params).fetchall()

    # group rows by (player_id, season)
    groups: dict[tuple, list] = {}
    for r in rows:
        groups.setdefault((r["player_id"], r["season"]), []).append(r)

    for (player_id, grp_season), arows in groups.items():
        # pitches-weighted overall numbers across this pitcher's pitch types
        srow: dict = {
            "player_id": player_id,
            "season": grp_season,
            "source": source_out,
            "source_file": _rollup_source_file(arows),
            "observed_at": now_iso(),
            "t2_stuff": _weighted_mean(
                (r["stuff_plus"], r["pitches"]) for r in arows),
            "perceived_value": _weighted_mean(
                (r["xrv_plus"], r["pitches"]) for r in arows),
            "hardhit_pct": _weighted_mean(
                (r["hardhit_pct"], r["pitches"]) for r in arows),
            "chase_pct": _weighted_mean(
                (r["chase_pct"], r["pitches"]) for r in arows),
        }

        # per-pitch Stuff+ fanned into the wide columns
        for code in _CODES:
            crows = [r for r in arows if r["code"] == code]
            srow[f"{code}_stuff"] = _weighted_mean(
                (r["stuff_plus"], r["pitches"]) for r in crows)

        # fastball shape from the fb rows (pitches-weighted)
        fb_rows = [r for r in arows if r["code"] == "fb"]
        srow["fb_velo"] = _weighted_mean((r["velo"], r["pitches"]) for r in fb_rows)
        srow["fb_ivb"] = _weighted_mean((r["ivb"], r["pitches"]) for r in fb_rows)
        srow["fb_hb"] = _weighted_mean((r["hb"], r["pitches"]) for r in fb_rows)

        # total pitches across types
        total = sum(r["pitches"] for r in arows if r["pitches"] is not None)
        srow["pitches"] = total or None

        # team: any non-null; level stays null (arsenal has no level)
        srow["team"] = next((r["team"] for r in arows if r["team"] is not None), None)

        cols = [k for k, v in srow.items() if v is not None]
        ph = ", ".join("?" for _ in cols)
        con.execute(
            f"INSERT OR REPLACE INTO stats_pitching ({', '.join(cols)}) VALUES ({ph})",
            [srow[c] for c in cols],
        )
    con.commit()
    return {"pitchers": len(groups), "season": season}


def _rollup_source_file(arows) -> str:
    files = sorted({r["source_file"] for r in arows if "source_file" in r.keys() and r["source_file"]})
    if not files:
        return "rollup:pitch_arsenal"
    return "rollup:" + ",".join(files[:3]) + ("..." if len(files) > 3 else "")


def get_arsenal(con: sqlite3.Connection, player_id: int,
                season: str | None = None) -> list[dict]:
    """Return a pitcher's per-pitch arsenal rows, ordered by pitches desc.

    For display/inspection — the raw per-(pitch type) lines behind the rollup.
    """
    sql = "SELECT * FROM pitch_arsenal WHERE player_id = ?"
    params: list = [player_id]
    if season is not None:
        sql += " AND season = ?"
        params.append(str(season))
    sql += " ORDER BY pitches DESC"
    return [dict(r) for r in con.execute(sql, params).fetchall()]
