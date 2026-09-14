"""Coach-board overlay: schema migration, write-back, payload — all offline.

The backend read is monkeypatched, so these never touch Supabase or Google.
"""
import json
import sqlite3
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal import overlay  # noqa: E402


@pytest.fixture
def con():
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    c.executescript((ROOT / "db" / "schema.sql").read_text())
    # two ENTERED players to tag
    for name in ("Alpha Hitter", "Bravo Pitcher"):
        c.execute("INSERT INTO players (full_name, current_status) VALUES (?, 'ENTERED')", (name,))
    c.commit()
    return c


def test_clean_temp_and_truthy():
    assert overlay._clean_temp("5") == "5"
    assert overlay._clean_temp(3) == "3"
    assert overlay._clean_temp("9") is None
    assert overlay._clean_temp("hot") is None
    assert overlay._clean_temp(None) is None
    assert overlay._truthy("TRUE") == 1 and overlay._truthy("x") == 1 and overlay._truthy("★") == 1
    assert overlay._truthy("") == 0 and overlay._truthy("no") == 0


def test_backend_of():
    assert overlay.backend_of({}) == "none"
    assert overlay.backend_of({"board_overlay": {"backend": "supabase"}}) == "supabase"
    assert overlay.backend_of({"board_overlay": {"backend": "sheet"}}) == "sheet"
    assert overlay.backend_of({"board_overlay": {"backend": "garbage"}}) == "none"


def test_ensure_overlay_columns_migrates_old_table():
    """An older DB whose call_assignments predates the overlay columns is brought up to date."""
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    c.execute("""CREATE TABLE call_assignments (
        id INTEGER PRIMARY KEY, player_id INTEGER, priority INTEGER,
        contact TEXT, notes TEXT, scout_notes TEXT, updated_at TEXT)""")
    overlay.ensure_overlay_columns(c)
    cols = {r["name"] for r in c.execute("PRAGMA table_info(call_assignments)")}
    assert {"lead_temp", "favorite", "overlay_updated_by", "overlay_updated_at"} <= cols
    overlay.ensure_overlay_columns(c)  # idempotent — no error on a second call


def test_sync_writes_back_then_seed_reads(con, monkeypatch):
    pid = con.execute("SELECT player_id FROM players WHERE full_name='Alpha Hitter'").fetchone()[0]
    fake = {str(pid): {"temp": "5", "fav": 1, "by": "TW", "at": "2026-06-03T00:00:00",
                       "notes": {"TW": "plus arm", "Coach K": "follow up"}}}
    monkeypatch.setattr(overlay, "read_overlay", lambda cfg: fake)
    cfg = {"board_overlay": {"backend": "sheet"}}

    res = overlay.sync_overlay_to_db(con, cfg)
    assert res["players"] == 1 and (res["inserted"] + res["updated"]) == 1

    row = con.execute(
        "SELECT lead_temp, favorite, priority, scout_notes, overlay_updated_by "
        "FROM call_assignments WHERE player_id=?", (pid,)).fetchone()
    assert row["lead_temp"] == "5"
    assert row["favorite"] == 1
    assert row["priority"] == 1                      # rating 5 (hot) -> priority 1, filled NULL priority
    assert row["overlay_updated_by"] == "TW"
    assert json.loads(row["scout_notes"]) == {"TW": "plus arm", "Coach K": "follow up"}

    # round-trip back out of the DB
    seed = overlay.seed_from_db(con)
    assert seed[str(pid)]["temp"] == "5"
    assert seed[str(pid)]["fav"] == 1
    assert seed[str(pid)]["notes"]["Coach K"] == "follow up"


def test_sync_merges_notes_without_clobber(con, monkeypatch):
    pid = con.execute("SELECT player_id FROM players WHERE full_name='Bravo Pitcher'").fetchone()[0]
    con.execute("INSERT INTO call_assignments (player_id, scout_notes, priority) VALUES (?,?,?)",
                (pid, json.dumps({"Existing": "keep me"}), 2))
    con.commit()
    monkeypatch.setattr(overlay, "read_overlay",
                        lambda cfg: {str(pid): {"temp": "3", "fav": 0, "notes": {"TW": "new note"}}})
    overlay.sync_overlay_to_db(con, {"board_overlay": {"backend": "sheet"}})
    row = con.execute("SELECT scout_notes, priority FROM call_assignments WHERE player_id=?", (pid,)).fetchone()
    assert json.loads(row["scout_notes"]) == {"Existing": "keep me", "TW": "new note"}
    assert row["priority"] == 2                      # existing priority NOT clobbered


def test_service_role_key_is_rejected(con):
    """A service_role key must never be accepted for the browser-facing anon_key."""
    import base64
    payload = base64.urlsafe_b64encode(b'{"role":"service_role"}').decode().rstrip("=")
    jwt = f"hdr.{payload}.sig"
    assert overlay._looks_like_service_key(jwt) is True
    assert overlay._looks_like_service_key("sb_secret_abc123") is True
    # anon JWT / publishable key pass through
    anon_payload = base64.urlsafe_b64encode(b'{"role":"anon"}').decode().rstrip("=")
    assert overlay._looks_like_service_key(f"hdr.{anon_payload}.sig") is False
    assert overlay._looks_like_service_key("sb_publishable_abc123") is False
    cfg = {"board_overlay": {"backend": "supabase",
                             "supabase": {"url": "https://ref.supabase.co", "anon_key": jwt}}}
    with pytest.raises(RuntimeError, match="SERVICE_ROLE"):
        overlay.build_overlay_payload(con, cfg)


def test_build_payload_none_and_supabase(con):
    assert overlay.build_overlay_payload(con, {}) == {"backend": "none"}
    cfg = {"board_overlay": {"backend": "supabase", "coaches": ["TW", "Coach K"],
                             "supabase": {"url": "https://ref.supabase.co/", "anon_key": "anon123"}}}
    p = overlay.build_overlay_payload(con, cfg)
    assert p["backend"] == "supabase"
    assert p["coaches"] == ["TW", "Coach K"]
    assert p["supabase"]["url"] == "https://ref.supabase.co"     # trailing slash stripped
    assert p["supabase"]["anonKey"] == "anon123"
    assert p["supabase"]["overlayTable"] == "board_overlay"
    assert isinstance(p["data"], dict)
