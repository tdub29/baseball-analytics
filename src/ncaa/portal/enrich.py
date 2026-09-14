"""Stat enrichment.

Two sources:
  1. import_643_csv()  — current-season metrics from 6-4-3 Charts CSV exports
                         (primary; 6-4-3 has no public API). Header auto-mapping
                         so it tolerates slightly different export layouts.
  2. collegebaseball_baseline() — historical percentile baselines (2012-2023);
                         the package's bundled tables stop at 2023 (see memory).
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

import pandas as pd

from .db import now_iso
from .resolve import Resolver
from .util import clean_str, to_float, to_int

# ── 6-4-3 / TruMedia header aliases → schema column ──────────────────────────
# Keys are schema columns; values are accepted header spellings (lowercased,
# spaces/%/+ stripped for matching).
HITTING_ALIASES = {
    "team": ["team", "newestteamname", "school"],
    "pa": ["pa"], "pitches": ["pitches"], "ba": ["ba", "avg"], "obp": ["obp"], "slg": ["slg"],
    "xwoba": ["xwoba"], "woba": ["woba"], "hr": ["hr"], "sb": ["sb"],
    # "ev"/"hh"/"zcontact"/"whiff" accept 6-4-3 batted-ball CSV export headers
    # (EV, HH%, Z-Contact%, Whiff%). Whiff% (whiffs/swing) is stored in swstr_pct
    # as the closest existing field — display-only, not used by the fit score.
    "avg_ev": ["avgev", "avgexitvelo", "exitvelo", "ev"], "ev90": ["90ev", "ev90"],
    "hardhit_pct": ["hardhit", "hh"], "barrel_pct": ["barrel"], "gb_pct": ["gb", "ground"],
    "pull_pct": ["pull"], "k_pct": ["k"], "zcon_pct": ["zcon", "zonecontact", "zcontact"],
    "chase_pct": ["chase"], "swstr_pct": ["swstrk", "swstr", "swingingstrike", "whiff"],
    "seager": ["seager"],
    # full 6-4-3 batted-ball/discipline export coverage
    "max_ev": ["maxev"], "xba": ["xba"], "swspot_pct": ["swspot"], "la": ["la"],
    "fb_pct": ["fb"], "ld_pct": ["ld"], "swing_pct": ["swing"], "zswing_pct": ["zswing"],
    "sd_plus": ["sd"], "barrels": ["barrels"], "bbe": ["bbe"],
}
PITCHING_ALIASES = {
    "team": ["team", "newestteamname", "school"], "level": ["level", "newestteamlevel"],
    "ip": ["ip"], "fip": ["fip"], "slg_against": ["slg", "slgagainst"], "k_bb": ["kbb"],
    "perceived_value": ["perceivedvalue", "pv"], "hardhit_pct": ["hardhit"],
    "ground_pct": ["ground", "gb"], "strike_pct": ["strike"], "miss_pct": ["miss"],
    "inzone_whiff_pct": ["inzonewhiff", "izwhiff"], "chase_pct": ["chase"],
    "t2_stuff": ["t2stuff", "stuff"],
    "cb_stuff": ["cbstuff"], "ch_stuff": ["chstuff"], "ct_stuff": ["ctstuff"],
    "fb_stuff": ["fbstuff"], "si_stuff": ["sistuff"], "sl_stuff": ["slstuff"],
    "cb_strike_pct": ["cbstrike"], "ch_strike_pct": ["chstrike"], "ct_strike_pct": ["ctstrike"],
    "fb_strike_pct": ["fbstrike"], "si_strike_pct": ["sistrike"], "sl_strike_pct": ["slstrike"],
}
NAME_ALIASES = ["name", "playername", "playerfullname", "fullname", "player"]
_INT_COLS = {"pa", "hr", "sb", "pitches", "barrels", "bbe"}


def _norm_header(h: str) -> str:
    s = "".join(c for c in str(h).lower() if c.isalnum())
    # fold a trailing "pct"/"percent" so "HardHitPct" == "HardHit %" == "hardhit"
    for suf in ("percent", "pct"):
        if s.endswith(suf) and len(s) > len(suf):
            return s[: -len(suf)]
    return s


def _build_map(columns, aliases) -> dict[str, str]:
    norm_to_actual = {_norm_header(c): c for c in columns}
    out = {}
    for field, opts in aliases.items():
        for opt in opts:
            if opt in norm_to_actual:
                out[field] = norm_to_actual[opt]
                break
    return out


def _find_name_col(columns) -> str | None:
    norm_to_actual = {_norm_header(c): c for c in columns}
    for a in NAME_ALIASES:
        if a in norm_to_actual:
            return norm_to_actual[a]
    return None


def detect_kind(columns) -> str:
    """'pitching' if pitcher-only fields present, else 'hitting'."""
    norm = {_norm_header(c) for c in columns}
    if {"ip", "fip"} & norm or any("stuff" in n for n in norm):
        return "pitching"
    return "hitting"


def import_643_csv(
    con: sqlite3.Connection, path: str | Path, *, season: str = "2025",
    source: str = "643", create_missing: bool = True, fuzzy: bool = True,
) -> dict:
    """Ingest one 6-4-3 export CSV into stats_hitting/stats_pitching."""
    path = Path(path)
    df = pd.read_csv(path)
    kind = detect_kind(df.columns)
    aliases = PITCHING_ALIASES if kind == "pitching" else HITTING_ALIASES
    table = "stats_pitching" if kind == "pitching" else "stats_hitting"
    colmap = _build_map(df.columns, aliases)
    name_col = _find_name_col(df.columns)
    if not name_col:
        raise ValueError(f"no name column found in {path}; headers={list(df.columns)}")

    resolver = Resolver(con)
    from .db import PlayerIndex
    idx = PlayerIndex(con)
    matched = created = rows = 0

    for _, r in df.iterrows():
        name = clean_str(r.get(name_col))
        if not name:
            continue
        team = clean_str(r.get(colmap.get("team", "___none"))) if "team" in colmap else None
        cand = resolver.resolve(name, team, fuzzy=fuzzy)
        if cand:
            pid = cand.player_id; matched += 1
        elif create_missing:
            pid, _ = idx.get_or_create(full=name, defaults={"current_status": None})
            created += 1
        else:
            continue

        srow = {"player_id": pid, "season": season, "source": f"{source}",
                "source_file": path.name, "observed_at": now_iso()}
        for field, col in colmap.items():
            raw = r.get(col)
            if field in ("team", "level"):
                srow[field] = clean_str(raw)
            elif field in _INT_COLS:
                srow[field] = to_int(raw)
            else:
                srow[field] = to_float(raw)
        cols = [k for k, v in srow.items() if v is not None]
        ph = ", ".join("?" for _ in cols)
        con.execute(
            f"INSERT OR REPLACE INTO {table} ({', '.join(cols)}) VALUES ({ph})",
            [srow[c] for c in cols],
        )
        rows += 1
    con.commit()
    return {"kind": kind, "rows": rows, "matched": matched, "created": created,
            "mapped_fields": sorted(colmap)}


def collegebaseball_baseline(season: int, variant: str = "batting", divisions=(1,)):
    """Return a DataFrame of team/player baselines for percentile context.

    Falls back gracefully: collegebaseball's bundled tables stop at 2023, so
    seasons after that raise a clear message rather than a cryptic IndexError.
    """
    try:
        import collegebaseball as cb
    except Exception as e:  # pragma: no cover
        raise RuntimeError("collegebaseball not installed") from e
    try:
        cb.lookup_season_id(season)
    except Exception:
        raise RuntimeError(
            f"season {season} not in collegebaseball's tables (coverage 2012-2023). "
            "Use 6-4-3 exports for current season, or extend the season-id table."
        )
    return cb.download_team_totals([season], variant, list(divisions), save=False)
