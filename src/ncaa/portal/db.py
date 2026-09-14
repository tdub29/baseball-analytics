"""SQLite access layer + player upsert keyed by normalized name."""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .util import name_key

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "db" / "baseball.db"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def connect(db_path: str | Path = DEFAULT_DB) -> sqlite3.Connection:
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    return con


class PlayerIndex:
    """In-memory name_key -> player_id cache for fast cross-sheet merge.

    Load once at the start of an import, then call get_or_create() per row.
    """

    def __init__(self, con: sqlite3.Connection):
        self.con = con
        self._cache: dict[str, int] = {}
        for r in con.execute("SELECT player_id, full_name FROM players"):
            self._cache.setdefault(name_key(full=r["full_name"]), r["player_id"])

    def get_or_create(
        self,
        *,
        first: Any = None,
        last: Any = None,
        full: Any = None,
        defaults: dict[str, Any] | None = None,
    ) -> tuple[int, bool]:
        """Return (player_id, created). Merges by normalized name key."""
        if full:
            full_name = str(full).strip()
        else:
            full_name = " ".join(x for x in [str(first or "").strip(), str(last or "").strip()] if x)
        key = name_key(first=first, last=last, full=full)
        if not key:
            return self._insert(full_name or "UNKNOWN", first, last, defaults), True
        if key in self._cache:
            pid = self._cache[key]
            if defaults:
                self._fill_missing(pid, defaults)
            return pid, False
        pid = self._insert(full_name, first, last, defaults)
        self._cache[key] = pid
        return pid, True

    def create_distinct(self, *, full: Any, defaults: dict[str, Any] | None = None) -> int:
        """Always insert a NEW player, bypassing the name-key merge.

        For genuinely distinct people who share a name (two 'Joshua Martinez' at
        different schools). NOT registered in the name-key cache, so it never becomes
        the canonical target for a later name-only lookup — school routing handles it.
        """
        return self._insert(str(full).strip() or "UNKNOWN", None, None, defaults)

    def _insert(self, full_name, first, last, defaults) -> int:
        d = dict(defaults or {})
        ext = d.pop("external_ids", None)
        cols = {
            "first_name": (str(first).strip() if first is not None and str(first).strip() else None),
            "last_name": (str(last).strip() if last is not None and str(last).strip() else None),
            "full_name": full_name,
            "external_ids": json.dumps(ext) if ext else None,
            "first_seen": now_iso(),
            "last_updated": now_iso(),
            **d,
        }
        keys = ", ".join(cols)
        ph = ", ".join("?" for _ in cols)
        cur = self.con.execute(
            f"INSERT INTO players ({keys}) VALUES ({ph})", list(cols.values())
        )
        return int(cur.lastrowid)

    def _fill_missing(self, pid: int, defaults: dict[str, Any]) -> None:
        """Only set columns that are currently NULL (don't clobber)."""
        row = self.con.execute(
            "SELECT * FROM players WHERE player_id=?", (pid,)
        ).fetchone()
        sets, vals = [], []
        for k, v in defaults.items():
            if k == "external_ids":
                merged = _merge_external_ids(row["external_ids"], v)
                sets.append("external_ids=?")
                vals.append(merged)
                continue
            if k in row.keys() and row[k] in (None, "") and v not in (None, ""):
                sets.append(f"{k}=?")
                vals.append(v)
        if sets:
            sets.append("last_updated=?")
            vals.append(now_iso())
            vals.append(pid)
            self.con.execute(
                f"UPDATE players SET {', '.join(sets)} WHERE player_id=?", vals
            )


def _merge_external_ids(existing: str | None, new: Any) -> str | None:
    cur = json.loads(existing) if existing else {}
    if isinstance(new, dict):
        cur.update({k: v for k, v in new.items() if v not in (None, "")})
    return json.dumps(cur) if cur else None


def add_portal_event(
    con: sqlite3.Connection,
    *,
    player_id: int,
    event_type: str,
    source: str,
    event_date: str | None = None,
    source_url: str | None = None,
    raw: dict | None = None,
) -> bool:
    """Idempotent insert. Returns True if a new row was added."""
    try:
        con.execute(
            """INSERT INTO portal_events
                 (player_id, event_type, event_date, source, source_url, observed_at, raw_json)
               VALUES (?,?,?,?,?,?,?)""",
            (
                player_id, event_type, event_date, source, source_url,
                now_iso(), json.dumps(raw) if raw else None,
            ),
        )
        return True
    except sqlite3.IntegrityError:
        return False  # UNIQUE(player_id,event_type,source,event_date) already present


# Sources that are historical reference only, NOT evidence of current portal standing.
# The 2025 Excel workbook was imported as inspo/seed; it must never imply "in the portal".
_HISTORICAL_SOURCE_PREFIX = "excel"


def reconcile_status_from_ledger(con: sqlite3.Connection) -> dict:
    """Recompute players.current_status from the portal_events ledger alone.

    `current_status` is a derived rollup of the append-only event log, NOT a field
    to be trusted from the seed import. A player is only in the current portal by
    virtue of a real *tracker* event (d1baseball, verbalcommits, twitter, …); the
    `excel:*` seed is ignored here. Precedence: COMMITTED/WITHDRAWN supersede
    ENTERED; a player with no tracker event becomes NULL (not currently in portal).

    Idempotent. Returns before/after status counts so the caller can show the delta.
    """
    def counts() -> dict:
        return {(r[0] or "(null)"): r[1] for r in con.execute(
            "SELECT current_status, COUNT(*) FROM players GROUP BY current_status")}

    like = f"{_HISTORICAL_SOURCE_PREFIX}%"
    before = counts()
    con.execute(
        """
        UPDATE players SET
          current_status = (
            SELECT CASE
              WHEN EXISTS(SELECT 1 FROM portal_events pe WHERE pe.player_id=players.player_id
                          AND pe.event_type='COMMITTED' AND pe.source NOT LIKE ?) THEN 'COMMITTED'
              WHEN EXISTS(SELECT 1 FROM portal_events pe WHERE pe.player_id=players.player_id
                          AND pe.event_type='WITHDRAWN' AND pe.source NOT LIKE ?) THEN 'WITHDRAWN'
              WHEN EXISTS(SELECT 1 FROM portal_events pe WHERE pe.player_id=players.player_id
                          AND pe.event_type='ENTERED'   AND pe.source NOT LIKE ?) THEN 'ENTERED'
              ELSE NULL END),
          last_updated = ?
        """,
        (like, like, like, now_iso()),
    )
    con.commit()
    return {"before": before, "after": counts()}
