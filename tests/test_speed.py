"""Speed tool grade: built from SB + triples per game off the box-score line."""
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.evaluate import _load_pool, evaluate  # noqa: E402


def _db():
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    c.executescript((ROOT / "db" / "schema.sql").read_text())
    return c


def _hitter(c, pid, name, *, sb, triples, gp):
    c.execute("INSERT INTO players (player_id, full_name, position, division, current_status) VALUES (?,?,?,?,?)",
              (pid, name, "CF", "I", "ENTERED"))
    # 6-4-3 metric line (drives the pool / other grades)
    c.execute("INSERT INTO stats_hitting (player_id,season,team,pa,ba,xwoba,avg_ev,source) VALUES (?,?,?,?,?,?,?,?)"
              .replace("?,?,?,?,?,?,?,?", "?,?,?,?,?,?,?,?"),
              (pid, "2026", "Test U", 200, .300, .380, 88.0, "643"))
    # d1baseball box-score line carries the speed counting stats
    c.execute("INSERT INTO stats_hitting (player_id,season,team,gp,sb,triples,source) VALUES (?,?,?,?,?,?,?)",
              (pid, "2026", "Test U", gp, sb, triples, "d1baseball"))


def test_load_pool_computes_per_game_speed_rates():
    c = _db()
    _hitter(c, 1, "Burner Speedster", sb=25, triples=6, gp=50)
    c.commit()
    pool = _load_pool(c)
    row = pool[pool["player_id"] == 1].iloc[0]
    assert abs(row["sb_per_g"] - 0.5) < 1e-9      # 25/50
    assert abs(row["tr_per_g"] - 0.12) < 1e-9     # 6/50


def test_rating_leans_heavily_on_wrc_plus():
    """A hitter with elite wRC+ outrates one with better 6-4-3 metrics but poor wRC+."""
    c = _db()
    # A: elite wRC+, mediocre advanced metrics
    c.execute("INSERT INTO players (player_id,full_name,position,division,current_status) VALUES (1,'Elite Wrc','CF','I','ENTERED')")
    c.execute("INSERT INTO stats_hitting (player_id,season,team,pa,ba,xwoba,avg_ev,source) VALUES (1,'2026','U',200,.250,.300,85.0,'643')")
    c.execute("INSERT INTO stats_hitting (player_id,season,team,gp,wrc_plus,source) VALUES (1,'2026','U',55,170,'d1baseball')")
    # B: poor wRC+, strong advanced metrics
    c.execute("INSERT INTO players (player_id,full_name,position,division,current_status) VALUES (2,'Weak Wrc','CF','I','ENTERED')")
    c.execute("INSERT INTO stats_hitting (player_id,season,team,pa,ba,xwoba,avg_ev,source) VALUES (2,'2026','U',200,.330,.430,95.0,'643')")
    c.execute("INSERT INTO stats_hitting (player_id,season,team,gp,wrc_plus,source) VALUES (2,'2026','U',55,70,'d1baseball')")
    c.commit()
    evaluate(c, {})
    import json
    r = {pid: json.loads(comp) for pid, comp in c.execute("SELECT player_id, components FROM evaluations")}
    assert r[1]["rating"] > r[2]["rating"]   # elite wRC+ wins despite weaker metrics


def test_speed_grade_ranks_faster_higher_and_handles_missing():
    c = _db()
    _hitter(c, 1, "Burner Speedster", sb=30, triples=7, gp=55)   # fast
    _hitter(c, 2, "Station To Station", sb=0, triples=0, gp=55)  # slow
    # a hitter with NO box-score line -> unknown wheels -> speed grade NaN/None
    c.execute("INSERT INTO players (player_id, full_name, position, division, current_status) VALUES (3,'No Boxscore','CF','I','ENTERED')")
    c.execute("INSERT INTO stats_hitting (player_id,season,team,pa,ba,xwoba,avg_ev,source) VALUES (3,'2026','Test U',200,.3,.38,88.0,'643')")
    c.commit()

    evaluate(c, {})
    import json
    grades = {}
    for r in c.execute("SELECT player_id, components FROM evaluations"):
        grades[r["player_id"]] = json.loads(r["components"]).get("speed_grade")
    assert grades[1] is not None and grades[2] is not None
    assert grades[1] > grades[2]          # the burner outgrades the clogger
    assert grades[3] is None              # no box-score line -> no speed grade
