"""Split same-name players the name-only resolver wrongly merged into one identity.

The authoritative signal is the TRACKER (d1baseball): if it lists the same name at two
different *current* schools, those are two different people (e.g. two "Joshua Martinez",
UC Riverside + UNC Wilmington). We split them and re-home their events and stats:

  * tracker events  -> the identity whose school matches `latest_team`
  * stat lines      -> by `team`: exact school match first; a prior-school line (team in
                       no tracker school) goes to the identity that owns that ROLE
                       (a pitching line to whichever split identity pitches), else stays
                       on the primary and is reported as ambiguous.

Stats are NOT fabricated or duplicated — only re-pointed. Bio stays on the primary (it
can't be safely attributed). Prevention lives in resolve.py (school routing) +
sources/base.py (distinct identities on ingest); this only repairs existing damage.
"""
from __future__ import annotations

import json
import sqlite3

from .db import now_iso
from .util import eligibility_from_class, name_key, normalize_name, schools_match

_STAT_TABLES = {"stats_hitting": "hit", "stats_pitching": "pit", "pitch_arsenal": "pit"}


def _tracker_lookup(con: sqlite3.Connection, tracker_path: str) -> dict:
    """(name_key, normalized_school) -> {'position', 'class_year'} from the live tracker."""
    from pathlib import Path

    from .sources.d1baseball import parse_tracker_text
    p = Path(tracker_path)
    if not p.exists():
        return {}
    out: dict = {}
    for ev in parse_tracker_text(p.read_text(encoding="utf-8", errors="replace")):
        if ev.from_school:
            out[(name_key(full=ev.player_name), normalize_name(ev.from_school))] = {
                "position": ev.position, "class_year": ev.class_year}
    return out


def _event_schools(con, pid: int) -> list[str]:
    schools: list[str] = []
    for r in con.execute("SELECT raw_json FROM portal_events WHERE player_id=? AND source='d1baseball'", (pid,)):
        lt = (json.loads(r["raw_json"]) or {}).get("latest_team") if r["raw_json"] else None
        if lt and not any(schools_match(lt, s) for s in schools):
            schools.append(lt)
    return schools


def split_name_collisions(con: sqlite3.Connection, tracker_path: str = "sampl.txt") -> dict:
    con.row_factory = sqlite3.Row
    look = _tracker_lookup(con, tracker_path)

    # over-merged = a player with 2+ d1baseball events at conflicting schools
    over = []
    for r in con.execute("""SELECT player_id FROM portal_events WHERE source='d1baseball'
                            GROUP BY player_id HAVING COUNT(*)>1"""):
        schools = _event_schools(con, r["player_id"])
        if len(schools) > 1:
            over.append((r["player_id"], schools))

    res = {"split_players": 0, "new_players": 0, "events_moved": 0,
           "stats_moved": 0, "ambiguous_stats": 0, "details": []}

    for pid, schools in over:
        base = con.execute("SELECT * FROM players WHERE player_id=?", (pid,)).fetchone()
        name = base["full_name"]
        keep = next((s for s in schools if schools_match(s, base["from_school"])), schools[0])

        ident: dict[str, int] = {}            # school -> player_id
        for s in schools:
            if s == keep:
                ident[s] = pid
            else:
                ident[s] = con.execute(
                    "INSERT INTO players (full_name, first_seen, last_updated) VALUES (?,?,?)",
                    (name, now_iso(), now_iso())).lastrowid
                res["new_players"] += 1
        res["split_players"] += 1

        # 1) re-home tracker events by school
        for e in con.execute("SELECT event_id, raw_json FROM portal_events WHERE player_id=? AND source='d1baseball'", (pid,)).fetchall():
            lt = (json.loads(e["raw_json"]) or {}).get("latest_team") if e["raw_json"] else None
            tgt_school = next((s for s in schools if schools_match(lt, s)), None)
            if tgt_school and ident[tgt_school] != pid:
                con.execute("UPDATE portal_events SET player_id=? WHERE event_id=?", (ident[tgt_school], e["event_id"]))
                res["events_moved"] += 1

        # 2) exact-team stats -> their identity; track each identity's role(s)
        role_of: dict[int, set] = {p: set() for p in ident.values()}
        leftover = []   # (table, row_id, role, team)
        for table, role in _STAT_TABLES.items():
            for row in con.execute(f"SELECT id, team FROM {table} WHERE player_id=?", (pid,)).fetchall():
                tgt_school = next((s for s in schools if schools_match(row["team"], s)), None)
                if tgt_school:
                    if ident[tgt_school] != pid:
                        con.execute(f"UPDATE {table} SET player_id=? WHERE id=?", (ident[tgt_school], row["id"]))
                        res["stats_moved"] += 1
                    role_of[ident[tgt_school]].add(role)
                else:
                    leftover.append((table, row["id"], role, row["team"]))

        # 3) prior-school stats -> the identity that owns that role (unique), else the
        #    identity with no stats; else leave on primary (ambiguous)
        for table, row_id, role, team in leftover:
            owners = [p for p, roles in role_of.items() if role in roles]
            if len(owners) == 1:
                tgt = owners[0]
            else:
                empty = [p for p, roles in role_of.items() if not roles]
                tgt = empty[0] if len(empty) == 1 and not owners else None
            if tgt and tgt != pid:
                con.execute(f"UPDATE {table} SET player_id=? WHERE id=?", (tgt, row_id))
                res["stats_moved"] += 1
                role_of[tgt].add(role)
            elif tgt is None:
                res["ambiguous_stats"] += 1

        # 4) set each identity's current-state fields from the tracker
        for s, ip in ident.items():
            meta = look.get((name_key(full=name), normalize_name(s)), {})
            pos, cy = meta.get("position"), meta.get("class_year")
            con.execute(
                "UPDATE players SET from_school=?, current_status='ENTERED', "
                "position=COALESCE(?,position), class_year=COALESCE(?,class_year), "
                "eligibility_remaining=COALESCE(?,eligibility_remaining), last_updated=? WHERE player_id=?",
                (s, pos, cy, eligibility_from_class(cy), now_iso(), ip))

        res["details"].append({"name": name, "schools": {s: ident[s] for s in schools}})

    con.commit()
    return res
