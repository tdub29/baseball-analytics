"""Entity resolution: match an incoming portal entry to an existing player.

Used by source adapters. Exact normalized-name match first (fast), then fuzzy
match gated by school agreement to avoid collapsing different players who share
a common name.
"""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass

from rapidfuzz import fuzz

from .util import name_key, normalize_name

NAME_THRESHOLD = 88      # rapidfuzz token_set_ratio on names
SCHOOL_THRESHOLD = 80    # school similarity to confirm a fuzzy name match


@dataclass
class Candidate:
    player_id: int
    full_name: str
    from_school: str | None
    score: float
    reason: str


class Resolver:
    def __init__(self, con: sqlite3.Connection):
        self.con = con
        self.rows = con.execute(
            "SELECT player_id, full_name, from_school FROM players"
        ).fetchall()
        self._by_id = {r["player_id"]: r for r in self.rows}
        self._schools: dict[int, set[str]] = {r["player_id"]: set() for r in self.rows}
        # exact normalized-key index -> ALL players sharing that name (usually one, but
        # same-name different-people do exist; we disambiguate those by school below).
        self._key: dict[str, list[int]] = {}
        for r in self.rows:
            self._key.setdefault(name_key(full=r["full_name"]), []).append(r["player_id"])
            if r["from_school"]:
                self._schools.setdefault(r["player_id"], set()).add(r["from_school"])
        for table in ("stats_hitting", "stats_pitching", "pitch_arsenal", "player_bio", "player_bio_evidence"):
            if not _table_exists(con, table):
                continue
            for r in con.execute(f"SELECT DISTINCT player_id, team FROM {table} WHERE team IS NOT NULL"):
                self._schools.setdefault(r["player_id"], set()).add(r["team"])

    def _school_score(self, player_id: int, school: str | None) -> float:
        if not school:
            return 0.0
        nschool = normalize_name(school)
        scores = [
            fuzz.token_set_ratio(nschool, normalize_name(s))
            for s in self._schools.get(player_id, set())
            if s
        ]
        return max(scores) if scores else 0.0

    def resolve(
        self, name: str, school: str | None = None, *, min_score: float = NAME_THRESHOLD,
        fuzzy: bool = True,
    ) -> Candidate | None:
        """Return the best matching player, or None if below threshold.

        fuzzy=False skips the O(n) fuzzy scan after the exact-key check — use it
        for bulk stat enrichment (clean source names) where scanning a large
        players table per row would be prohibitively slow.
        """
        key = name_key(full=name)
        pids = self._key.get(key)
        if pids:
            if len(pids) == 1:
                row = self._by_id[pids[0]]
                return Candidate(pids[0], row["full_name"], row["from_school"], 100.0, "exact-key")
            # several players share this exact name — route by school so one person's
            # stats/events don't land on their namesake (e.g. two "Joshua Martinez").
            nschool = normalize_name(school) if school else None
            if nschool:
                best: tuple[int, float] | None = None
                for pid in pids:
                    ss = self._school_score(pid, school)
                    if ss >= SCHOOL_THRESHOLD and (best is None or ss > best[1]):
                        best = (pid, ss)
                if best:
                    row = self._by_id[best[0]]
                    return Candidate(best[0], row["full_name"], row["from_school"], best[1],
                                     f"exact-key+school={best[1]:.0f}")
            # no school given, or none agreed (e.g. a prior-school stat line): best effort
            row = self._by_id[pids[0]]
            return Candidate(pids[0], row["full_name"], row["from_school"], 90.0,
                             "exact-key (ambiguous name)")
        if not fuzzy:
            return None

        norm = normalize_name(name)
        if not norm:
            return None
        best: Candidate | None = None
        nschool = normalize_name(school) if school else None
        for r in self.rows:
            ns = fuzz.token_set_ratio(norm, normalize_name(r["full_name"]))
            if ns < min_score:
                continue
            # if both have a school, require school agreement before accepting
            if nschool and self._schools.get(r["player_id"]):
                ss = self._school_score(r["player_id"], school)
                if ss < SCHOOL_THRESHOLD:
                    continue
                score = 0.7 * ns + 0.3 * ss
                reason = f"fuzzy name={ns:.0f} school={ss:.0f}"
            else:
                score = ns
                reason = f"fuzzy name={ns:.0f} (no school check)"
            if best is None or score > best.score:
                best = Candidate(r["player_id"], r["full_name"], r["from_school"], score, reason)
        return best


def _table_exists(con: sqlite3.Connection, table: str) -> bool:
    return con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (table,),
    ).fetchone() is not None
