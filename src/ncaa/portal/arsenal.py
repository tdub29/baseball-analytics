"""6-4-3 per-pitch-type PITCHER loader — one row per (pitcher, season, pitch).

Pitchers are evaluated per pitch. This stores the 6-4-3 pitcher export at its
native grain — one row per (Player, Pitch Type) — in `pitch_arsenal`, preserving
the full per-pitch suite (Stuff+, Location+, xRV+, Velo/Spin/iVB/HB/VAA/HAA/Rel/
Extension, and outcomes allowed). Per-pitcher rollups derive from this table.

Input quirks handled: Team is decorated "Name|logo_url"; dimensional cells carry
units (iVB '0.3"', RelHeight "6.3'", VAA '-9.1°').
"""
from __future__ import annotations

import re
import sqlite3
from pathlib import Path

import pandas as pd

from .db import PlayerIndex, now_iso
from .resolve import Resolver
from .util import clean_str, to_float, to_int

# pitch-type label -> normalized bucket (matches trackman._PITCH_CODE)
_CODE = {
    "fastball": "fb", "four-seam": "fb", "fourseam": "fb",
    "sinker": "si", "two-seam": "si", "twoseam": "si",
    "cutter": "ct",
    "slider": "sl", "sweeper": "sl",
    "curveball": "cb", "curve": "cb", "knucklecurve": "cb", "knuckle curve": "cb",
    "changeup": "ch", "change-up": "ch", "change": "ch", "splitter": "ch",
}


def _dim(v):
    """Strip units from a dimensional cell (iVB '0.3"', RelHeight "6.3'", VAA '-9.1°')."""
    if v is None:
        return None
    s = re.sub(r"[^0-9.\-]", "", str(v))
    try:
        return float(s) if s not in ("", "-", ".") else None
    except ValueError:
        return None


# export header -> (arsenal column, parser). to_float already strips % and commas.
SPEC = {
    "Pitches": ("pitches", to_int), "BBE": ("bbe", to_int), "Barrels": ("barrels", to_int),
    "EV": ("ev", to_float), "HH%": ("hardhit_pct", to_float), "Barrel%": ("barrel_pct", to_float),
    "BA": ("ba", to_float), "xBA": ("xba", to_float), "wOBA": ("woba", to_float), "xwOBA": ("xwoba", to_float),
    "Swing%": ("swing_pct", to_float), "Z-Contact%": ("zcontact_pct", to_float),
    "Chase%": ("chase_pct", to_float), "Whiff%": ("whiff_pct", to_float),
    "Velo": ("velo", to_float), "Velo 90": ("velo90", to_float), "Max Velo": ("max_velo", to_float),
    "Spin Rate": ("spin", to_float),
    "iVB": ("ivb", _dim), "HB": ("hb", _dim), "VAA": ("vaa", _dim), "HAA": ("haa", _dim),
    "RelHeight": ("rel_height", _dim), "RelSide": ("rel_side", _dim), "Extension": ("extension", _dim),
    "Stuff+": ("stuff_plus", to_float), "Location+": ("location_plus", to_float),
    "xRV+": ("xrv_plus", to_float), "Anomaly+": ("anomaly_plus", to_float),
    "Tunnel+": ("tunnel_plus", to_float), "PredMovDiff+": ("predmovdiff_plus", to_float),
}


def import_643_arsenal(
    con: sqlite3.Connection, path: str | Path, *,
    season: str = "2025", source: str = "643", create_missing: bool = True, fuzzy: bool = True,
) -> dict:
    """Load a 6-4-3 per-pitch-type pitcher export into pitch_arsenal."""
    path = Path(path)
    df = pd.read_csv(path)
    if "Team" in df.columns:
        df["Team"] = df["Team"].astype(str).str.split("|").str[0].str.strip()
    resolver = Resolver(con)
    idx = PlayerIndex(con)
    matched = created = rows = 0

    for _, r in df.iterrows():
        name = clean_str(r.get("Player"))
        pt = clean_str(r.get("Pitch Type"))
        if not name or not pt:
            continue
        team = clean_str(r.get("Team"))
        cand = resolver.resolve(name, team, fuzzy=fuzzy)
        if cand:
            pid = cand.player_id; matched += 1
        elif create_missing:
            pid, _ = idx.get_or_create(full=name, defaults={"current_status": None}); created += 1
        else:
            continue
        arow = {"player_id": pid, "season": str(season), "source": source,
                "source_file": path.name, "observed_at": now_iso(),
                "pitch_type": pt, "code": _CODE.get(pt.lower()), "team": team,
                "throws": clean_str(r.get("Throws"))}
        for hdr, (col, fn) in SPEC.items():
            if hdr in df.columns:
                v = fn(r.get(hdr))
                if v is not None:
                    arow[col] = v
        cols = [k for k, v in arow.items() if v is not None]
        ph = ", ".join("?" for _ in cols)
        con.execute(
            f"INSERT OR REPLACE INTO pitch_arsenal ({', '.join(cols)}) VALUES ({ph})",
            [arow[c] for c in cols],
        )
        rows += 1
    con.commit()
    types = sorted(df["Pitch Type"].astype(str).unique()) if "Pitch Type" in df.columns else []
    return {"rows": rows, "matched": matched, "created": created, "pitch_types": types}
