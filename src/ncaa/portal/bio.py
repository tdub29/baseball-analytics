"""Load player height/weight (by season) into player_bio.

Height comes from NCAA rosters (scripts/fetch_ncaa_bio.py -> CSV); weight, if
available, from a 6-4-3 roster export. Both share the (player, team, season) key
of the 6-4-3 stat exports, so rows attach to players already created during stat
enrichment. Match-only by default (don't create bio-only players).

Expected CSV columns (case-insensitive): player, team, season, and any of
height_in, weight_lb, class_year, bats, throws.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path

import pandas as pd

from .db import now_iso
from .resolve import Resolver
from .util import clean_str, parse_hometown, to_int

_COLMAP = {  # csv header (lower) -> player_bio column
    "height_in": "height_in", "height": "height_in",
    "weight_lb": "weight_lb", "weight": "weight_lb", "wt": "weight_lb",
    "class_year": "class_year", "class": "class_year", "year": "class_year",
    "bats": "bats", "throws": "throws", "team": "team",
    "position": "position", "pos": "position",
    "hometown_city": "hometown_city", "hometown_state": "hometown_state",
    "high_school": "high_school", "highschool": "high_school", "hs": "high_school",
}
_INT = {"height_in", "weight_lb"}


def load_player_bio(
    con: sqlite3.Connection, path: str | Path, *,
    source: str = "ncaa", create_missing: bool = False, fuzzy: bool = False,
    source_file: str | None = None, source_url: str | None = None,
) -> dict:
    """Upsert one player_bio row per (player, season, source) from a bio CSV."""
    path = Path(path)
    source_file = source_file or path.name
    df = pd.read_csv(path)
    lower = {c.lower().strip(): c for c in df.columns}
    name_col = lower.get("player") or lower.get("name")
    season_col = lower.get("season")
    if not name_col or not season_col:
        raise ValueError(f"bio CSV needs player + season columns; got {list(df.columns)}")
    fields = {dst: lower[src] for src, dst in _COLMAP.items() if src in lower}
    # A combined "Hometown" cell ("San Diego, Calif.") — split into city/state
    # when the CSV doesn't already carry the parsed columns (Sidearm/PG feeds).
    home_col = lower.get("hometown") or lower.get("home_town")

    resolver = Resolver(con)
    from .db import PlayerIndex
    idx = PlayerIndex(con)
    matched = created = rows = evidence_rows = 0
    for _, r in df.iterrows():
        name = clean_str(r.get(name_col))
        season = clean_str(r.get(season_col))
        if not name or not season:
            continue
        team = clean_str(r.get(fields.get("team", "___"))) if "team" in fields else None
        cand = resolver.resolve(name, team, fuzzy=fuzzy)
        if cand:
            pid = cand.player_id; matched += 1
        elif create_missing:
            pid, _ = idx.get_or_create(full=name, defaults={"current_status": None}); created += 1
        else:
            continue
        brow = {"player_id": pid, "season": str(season), "source": source}
        for dst, col in fields.items():
            raw = r.get(col)
            brow[dst] = to_int(raw) if dst in _INT else clean_str(raw)
        if home_col and not brow.get("hometown_city"):
            city, state = parse_hometown(r.get(home_col))
            brow["hometown_city"] = city
            brow.setdefault("hometown_state", None)
            brow["hometown_state"] = brow.get("hometown_state") or state
        evidence_rows += _insert_bio_evidence(
            con, brow, source_file=source_file, source_url=source_url,
            raw={str(k): _jsonable(v) for k, v in r.to_dict().items()},
        )
        cols = [k for k, v in brow.items() if v is not None]
        ph = ", ".join("?" for _ in cols)
        con.execute(
            f"INSERT OR REPLACE INTO player_bio ({', '.join(cols)}) VALUES ({ph})",
            [brow[c] for c in cols],
        )
        rows += 1
    con.commit()
    return {"rows": rows, "matched": matched, "created": created,
            "evidence_rows": evidence_rows, "fields": sorted(fields)}


_EVIDENCE_FIELDS = (
    "player_id", "season", "source", "team", "height_in", "weight_lb",
    "bats", "throws", "class_year", "position", "hometown_city",
    "hometown_state", "high_school",
)


def _jsonable(value):
    if pd.isna(value):
        return None
    if hasattr(value, "item"):
        return value.item()
    return value


def _row_hash(payload: dict) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _insert_bio_evidence(
    con: sqlite3.Connection,
    brow: dict,
    *,
    source_file: str | None,
    source_url: str | None,
    raw: dict,
) -> int:
    payload = {k: brow.get(k) for k in _EVIDENCE_FIELDS}
    payload["source_file"] = source_file
    payload["source_url"] = source_url
    row_hash = _row_hash(payload)
    cols = {
        **payload,
        "source_file": source_file,
        "source_url": source_url,
        "observed_at": now_iso(),
        "row_hash": row_hash,
        "raw_json": json.dumps(raw, sort_keys=True, ensure_ascii=True),
    }
    cols = {k: v for k, v in cols.items() if v is not None}
    ph = ", ".join("?" for _ in cols)
    cur = con.execute(
        f"INSERT OR IGNORE INTO player_bio_evidence ({', '.join(cols)}) VALUES ({ph})",
        list(cols.values()),
    )
    return cur.rowcount
