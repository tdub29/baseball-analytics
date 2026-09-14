"""Adapter base class + the normalized PortalEvent contract."""
from __future__ import annotations

import sqlite3
from dataclasses import asdict, dataclass, field
from datetime import date

from ..db import PlayerIndex, add_portal_event, now_iso
from ..resolve import Resolver
from ..util import eligibility_from_class, name_key, normalize_name, schools_match

VALID_EVENTS = {"ENTERED", "WITHDRAWN", "COMMITTED"}


@dataclass
class PortalEvent:
    player_name: str
    event_type: str = "ENTERED"          # ENTERED | WITHDRAWN | COMMITTED
    from_school: str | None = None
    to_school: str | None = None
    position: str | None = None
    class_year: str | None = None
    event_date: str | None = None        # YYYY-MM-DD
    source_url: str | None = None
    raw: dict = field(default_factory=dict)

    def __post_init__(self):
        self.event_type = (self.event_type or "ENTERED").upper()
        if self.event_type not in VALID_EVENTS:
            self.event_type = "ENTERED"


class BaseAdapter:
    """Subclass and implement fetch(). source_id labels the rows."""

    source_id = "base"

    def __init__(self, config: dict | None = None):
        self.config = config or {}

    def fetch(self) -> list[PortalEvent]:  # pragma: no cover - overridden
        raise NotImplementedError

    @staticmethod
    def _match_same_name_school(con: sqlite3.Connection, name: str, school: str | None) -> int | None:
        """Find an existing player with this exact name whose school agrees — used to
        keep same-name people distinct (idempotent across re-ingests)."""
        nk = name_key(full=name)
        for r in con.execute("SELECT player_id, full_name, from_school FROM players"):
            if name_key(full=r["full_name"]) == nk and schools_match(school, r["from_school"]):
                return r["player_id"]
        return None

    # ── shared persistence ───────────────────────────────────────────────────
    def ingest(self, con: sqlite3.Connection) -> dict:
        """Resolve each fetched event to a player and append to portal_events."""
        started = now_iso()
        events = self.fetch()
        resolver = Resolver(con)
        idx = PlayerIndex(con)
        new_players = new_events = status_updates = 0

        # Same name, different current school within ONE tracker = two different people
        # (e.g. two "Joshua Martinez", UC Riverside + UNC Wilmington). Flag those names so
        # we give each school its own identity instead of collapsing them by name.
        from collections import defaultdict
        by_name: dict[str, list] = defaultdict(list)
        for ev in events:
            by_name[name_key(full=ev.player_name)].append(ev.from_school)
        ambiguous = set()
        for nk, schools in by_name.items():
            distinct: list[str] = []
            for s in schools:
                if s and not any(schools_match(s, d) for d in distinct):
                    distinct.append(s)
            if len(distinct) > 1:
                ambiguous.add(nk)
        run_index: dict[tuple, int] = {}   # (name_key, school) -> pid, within this run

        for ev in events:
            nk = name_key(full=ev.player_name)
            defaults = {
                "position": ev.position, "class_year": ev.class_year,
                "from_school": ev.from_school, "current_status": ev.event_type,
            }
            if nk in ambiguous:
                # route strictly by school: reuse the same-name player whose school
                # agrees, else mint a distinct identity (never merge by name alone).
                rkey = (nk, normalize_name(ev.from_school) if ev.from_school else "")
                if rkey in run_index:
                    pid = run_index[rkey]
                else:
                    pid = self._match_same_name_school(con, ev.player_name, ev.from_school)
                    if pid is None:
                        pid = idx.create_distinct(full=ev.player_name, defaults=defaults)
                        new_players += 1
                    run_index[rkey] = pid
            else:
                cand = resolver.resolve(ev.player_name, ev.from_school)
                if cand:
                    pid = cand.player_id
                else:
                    pid, _ = idx.get_or_create(full=ev.player_name, defaults=defaults)
                    new_players += 1
            if add_portal_event(
                con, player_id=pid, event_type=ev.event_type, source=self.source_id,
                event_date=ev.event_date or str(date.today()),
                source_url=ev.source_url, raw=ev.raw or asdict(ev),
            ):
                new_events += 1
            # The tracker is the source of truth for the player's CURRENT (2026) portal
            # state. Matched existing players otherwise keep stale fields from the 2025
            # Excel seed — wrong school/position/class on the board ("not from the
            # transfer list"). So overwrite every current-state field from the event:
            # from_school, position, class_year, eligibility (derived), + to_school on a
            # commit. Bio categories (height/weight/hometown/HS/handedness) are NOT
            # touched here — those are stable, non-2026-state, and may come from bio.
            elig = eligibility_from_class(ev.class_year)
            if ev.event_type in ("COMMITTED", "WITHDRAWN"):
                con.execute(
                    "UPDATE players SET current_status=?, from_school=COALESCE(?,from_school), "
                    "to_school=COALESCE(?,to_school), position=COALESCE(?,position), "
                    "class_year=COALESCE(?,class_year), eligibility_remaining=COALESCE(?,eligibility_remaining), "
                    "last_updated=? WHERE player_id=?",
                    (ev.event_type, ev.from_school, ev.to_school, ev.position, ev.class_year, elig, now_iso(), pid),
                )
                status_updates += 1
            elif ev.event_type == "ENTERED":
                # ENTERED means currently in the portal. Set it unless a prior
                # COMMITTED/WITHDRAWN stands (re-entry is reconciled from the ledger).
                con.execute(
                    "UPDATE players SET current_status='ENTERED', from_school=COALESCE(?,from_school), "
                    "position=COALESCE(?,position), class_year=COALESCE(?,class_year), "
                    "eligibility_remaining=COALESCE(?,eligibility_remaining), last_updated=? "
                    "WHERE player_id=? AND COALESCE(current_status,'') NOT IN ('COMMITTED','WITHDRAWN')",
                    (ev.from_school, ev.position, ev.class_year, elig, now_iso(), pid),
                )

        con.execute(
            """INSERT INTO source_runs (source, started_at, finished_at, rows_in, rows_new, errors)
               VALUES (?,?,?,?,?,?)""",
            (self.source_id, started, now_iso(), len(events), new_events, None),
        )
        con.commit()
        return {"source": self.source_id, "fetched": len(events),
                "new_events": new_events, "new_players": new_players,
                "status_updates": status_updates}
