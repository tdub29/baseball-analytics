"""Unit tests for the per-pitcher arsenal rollup (pure; no network).

Builds an in-memory SQLite DB from db/schema.sql, seeds a synthetic pitcher
with a couple of pitch_arsenal rows, runs rollup_arsenal, and checks that the
wide stats_pitching line is the pitches-weighted collapse of the arsenal.
"""
import sqlite3
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.rollup import _weighted_mean, get_arsenal, rollup_arsenal  # noqa: E402

SCHEMA = ROOT / "db" / "schema.sql"


@pytest.fixture
def con():
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    c.executescript(SCHEMA.read_text())
    c.execute("INSERT INTO players (player_id, full_name) VALUES (1, 'Test Pitcher')")
    c.executemany(
        "INSERT INTO pitch_arsenal "
        "(player_id, season, pitch_type, code, team, pitches, stuff_plus, xrv_plus, "
        " hardhit_pct, chase_pct, velo, ivb, hb, source) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [
            # Fastball: 700 pitches, Stuff+ 90, with shape
            (1, "2025", "Fastball", "fb", "USD", 700, 90.0, 100.0, 40.0, 25.0,
             94.5, 16.0, 8.0, "643"),
            # Slider: 300 pitches, Stuff+ 110
            (1, "2025", "Slider", "sl", "USD", 300, 110.0, 120.0, 30.0, 35.0,
             None, None, None, "643"),
        ],
    )
    c.commit()
    return c


def test_weighted_mean_ignores_nulls_and_rounds():
    assert _weighted_mean([(90.0, 700), (110.0, 300)]) == 96.0
    assert _weighted_mean([(90.0, None), (110.0, 300)]) == 110.0  # None weight skipped
    assert _weighted_mean([(None, 700), (110.0, 300)]) == 110.0   # None value skipped
    assert _weighted_mean([]) is None
    assert _weighted_mean([(90.0, 0), (110.0, 0)]) is None        # zero total weight


def test_rollup_arsenal(con):
    out = rollup_arsenal(con)
    assert out == {"pitchers": 1, "season": None}

    row = con.execute(
        "SELECT * FROM stats_pitching WHERE player_id = 1 AND source = '643'"
    ).fetchone()
    assert row is not None

    # per-pitch Stuff+ fanned into the wide columns
    assert row["fb_stuff"] == 90.0
    assert row["sl_stuff"] == 110.0
    # other codes had no rows -> null
    assert row["cb_stuff"] is None and row["ch_stuff"] is None
    assert row["si_stuff"] is None and row["ct_stuff"] is None

    # overall = pitches-weighted: round((90*700 + 110*300)/1000, 1) == 96.0
    assert row["t2_stuff"] == 96.0
    # perceived_value = weighted mean of xrv_plus: (100*700 + 120*300)/1000 == 106.0
    assert row["perceived_value"] == 106.0
    # hardhit%: (40*700 + 30*300)/1000 == 37.0
    assert row["hardhit_pct"] == 37.0

    # totals + shape
    assert row["pitches"] == 1000
    assert row["fb_velo"] == 94.5      # only fb rows contribute
    assert row["fb_ivb"] == 16.0
    assert row["fb_hb"] == 8.0
    assert row["team"] == "USD"
    assert row["level"] is None        # arsenal carries no level


def test_rollup_season_filter(con):
    # a row in a different season should be excluded when season is given
    con.execute(
        "INSERT INTO pitch_arsenal "
        "(player_id, season, pitch_type, code, pitches, stuff_plus, source) "
        "VALUES (1, '2024', 'Fastball', 'fb', 500, 70.0, '643')"
    )
    con.commit()
    out = rollup_arsenal(con, season="2025")
    assert out == {"pitchers": 1, "season": "2025"}
    row = con.execute(
        "SELECT t2_stuff FROM stats_pitching WHERE player_id = 1 AND source = '643'"
    ).fetchone()
    assert row["t2_stuff"] == 96.0     # only 2025 rows rolled up


def test_get_arsenal_ordered(con):
    rows = get_arsenal(con, 1)
    assert [r["pitch_type"] for r in rows] == ["Fastball", "Slider"]  # 700 > 300
    assert rows[0]["stuff_plus"] == 90.0
    assert get_arsenal(con, 1, season="2025")[0]["code"] == "fb"
    assert get_arsenal(con, 999) == []
