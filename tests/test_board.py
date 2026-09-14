"""Every player-facing surface must only show players still in the portal (ENTERED).

`evaluate` only scores ENTERED players, but a stale evaluation row survives once a
player commits/withdraws — so each board/site/export query carries its own status
guard. These tests seed one ENTERED + one COMMITTED player (both fully evaluated)
and assert the committed one never appears.
"""
import sqlite3
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.alerts import ALERT_SQL  # noqa: E402
from ncaa.portal.board import BOARD_SQL, build_board  # noqa: E402
from ncaa.portal.geo import CA_BOARD_SQL  # noqa: E402


def _load_consts(path: str) -> dict:
    """Exec a script file (not a package) to read its SQL constants; main() is gated
    behind __name__ == '__main__', so this is side-effect free."""
    g = {"__name__": "_test_load", "__file__": str(ROOT / path)}
    exec(compile((ROOT / path).read_text(), path, "exec"), g)
    return g


@pytest.fixture
def con():
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    c.executescript((ROOT / "db" / "schema.sql").read_text())

    def add(name, status, role):
        pid = c.execute(
            "INSERT INTO players (full_name, position, from_school, division, current_status,"
            " ca_tie, sd_tie, socal_tie) VALUES (?,?,?,?,?,1,1,1)",
            (name, "SS" if role == "hitter" else "RHP", "Test U", "I", status)).lastrowid
        c.execute("INSERT INTO evaluations (player_id, fit_score, components, run_at) VALUES (?,?,?,?)",
                  (pid, 95.0, '{"role":"%s","need_label":"X","likelihood":60}' % role, "2026-06-02"))
        if role == "hitter":
            c.execute("INSERT INTO stats_hitting (player_id,season,pa,source) VALUES (?,?,?,?)",
                      (pid, "2026", 100, "643"))
        else:
            c.execute("INSERT INTO stats_pitching (player_id,season,ip,source) VALUES (?,?,?,?)",
                      (pid, "2026", 40, "643"))
        c.execute("INSERT INTO portal_events (player_id,event_type,event_date,source,observed_at)"
                  " VALUES (?,?,?,?,?)", (pid, "ENTERED", "2026-05-01", "d1baseball", "2026-05-01T00:00:00"))

    for status in ("ENTERED", "COMMITTED", "WITHDRAWN"):
        add(f"{status} Hitter", status, "hitter")
        add(f"{status} Pitcher", status, "pitcher")
    c.commit()
    return c


def _names(rows):
    return [(dict(r).get("player") or dict(r).get("full_name") or dict(r).get("Name")) for r in rows]


def _surface_sqls():
    bh = _load_consts("scripts/build_html.py")
    ex = _load_consts("scripts/export_excel.py")
    return {
        "board.BOARD_SQL": (BOARD_SQL, ()),
        "build_html.HIT_SQL": (bh["HIT_SQL"], ()),
        "build_html.PIT_SQL": (bh["PIT_SQL"], ()),
        "export_excel.HIT_SQL": (ex["HIT_SQL"], ()),
        "export_excel.PIT_SQL": (ex["PIT_SQL"], ()),
        "alerts.ALERT_SQL": (ALERT_SQL, (50.0, 100)),
        "geo.CA_BOARD_SQL": (CA_BOARD_SQL, ()),
    }


@pytest.mark.parametrize("label", list(_surface_sqls().keys()))
def test_surface_excludes_non_entered(con, label):
    sql, params = _surface_sqls()[label]
    names = _names(con.execute(sql, params).fetchall())
    leaked = [n for n in names if n and ("COMMITTED" in n or "WITHDRAWN" in n)]
    assert not leaked, f"{label} leaked non-ENTERED players: {leaked}"
    assert names, f"{label} returned no ENTERED players (should keep the entered ones)"


def test_build_board_only_entered(con):
    df = build_board(con)
    assert set(df["status"]) == {"ENTERED"}
