import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.resolve import Resolver  # noqa: E402


def _db():
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript((ROOT / "db" / "schema.sql").read_text(encoding="utf-8"))
    return con


def test_resolver_uses_stat_team_for_fuzzy_school_gate():
    con = _db()
    pid = con.execute(
        "INSERT INTO players (full_name, from_school) VALUES (?,?)",
        ("ESTEBAN SEPULVEDA", "Pepperdine University"),
    ).lastrowid
    con.execute(
        "INSERT INTO stats_hitting (player_id, season, team, source) VALUES (?,?,?,?)",
        (pid, "2026", "UC Riverside", "643"),
    )
    con.commit()

    cand = Resolver(con).resolve("Estaban Sepulveda", "UC Riverside")

    assert cand is not None
    assert cand.player_id == pid
    assert "school" in cand.reason
