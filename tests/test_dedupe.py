"""Same-name players (different schools) must resolve apart and un-merge cleanly."""
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.dedupe import split_name_collisions  # noqa: E402
from ncaa.portal.resolve import Resolver  # noqa: E402


def _db():
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    c.executescript((ROOT / "db" / "schema.sql").read_text())
    return c


def test_resolver_routes_same_name_by_school():
    c = _db()
    c.executemany("INSERT INTO players (full_name, from_school) VALUES (?,?)",
                  [("Joshua Martinez", "UC Riverside"), ("Joshua Martinez", "UNC Wilmington")])
    c.commit()
    r = Resolver(c)
    assert r.resolve("Joshua Martinez", "UC Riverside").from_school == "UC Riverside"
    assert r.resolve("Joshua Martinez", "UNC Wilmington").from_school == "UNC Wilmington"


def test_split_unmerges_by_school_and_role(tmp_path):
    c = _db()
    pid = c.execute("INSERT INTO players (full_name, from_school, current_status) VALUES (?,?,?)",
                    ("Joshua Martinez", "UC Riverside", "ENTERED")).lastrowid
    # two tracker entries at different schools collapsed onto one id
    for team, dt in (("UC Riverside", "2026-06-01"), ("UNC Wilmington", "2026-05-30")):
        c.execute("INSERT INTO portal_events (player_id,event_type,event_date,source,observed_at,raw_json) "
                  "VALUES (?,?,?,?,?,?)",
                  (pid, "ENTERED", dt, "d1baseball", "2026-06-01T00:00:00",
                   f'{{"latest_team": "{team}"}}'))
    # stats: hitter at UNCW; pitcher at UCR + a prior school (CSUN, not in the tracker)
    c.execute("INSERT INTO stats_hitting (player_id,season,team,pa,source) VALUES (?,?,?,?,?)", (pid, "2026", "UNC Wilmington", 200, "643"))
    c.execute("INSERT INTO stats_pitching (player_id,season,team,ip,source) VALUES (?,?,?,?,?)", (pid, "2026", "UC Riverside", 50, "643"))
    c.execute("INSERT INTO stats_pitching (player_id,season,team,ip,source) VALUES (?,?,?,?,?)", (pid, "2025", "Cal State Northridge", 30, "643b"))
    c.commit()

    tracker = tmp_path / "t.txt"
    tracker.write_text("\n".join([
        "Player\tPosition\tClass\tLatest Team\tSeason\tDestination Team\tDate Entered",
        "Joshua Martinez", "2B\tSO\t", "UNC Wilmington", "2026\t--\t2026-06-01",
        "Joshua Martinez", "P\tJR\t", "UC Riverside", "2026\t--\t2026-06-01",
        "Showing 1 to 2 of 2 entries",
    ]), encoding="utf-8")

    res = split_name_collisions(c, tracker_path=str(tracker))
    assert res["split_players"] == 1 and res["new_players"] == 1

    rows = c.execute("SELECT player_id, from_school FROM players WHERE full_name='Joshua Martinez'").fetchall()
    assert len(rows) == 2
    by_school = {r["from_school"]: r["player_id"] for r in rows}
    uncw, ucr = by_school["UNC Wilmington"], by_school["UC Riverside"]

    # hitter stat -> UNCW; both pitching lines (UCR exact + CSUN prior-by-role) -> UCR
    assert c.execute("SELECT player_id FROM stats_hitting WHERE team='UNC Wilmington'").fetchone()[0] == uncw
    pit_ids = {r[0] for r in c.execute("SELECT player_id FROM stats_pitching")}
    assert pit_ids == {ucr}
