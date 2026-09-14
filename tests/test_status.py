"""current_status is derived from the portal-events ledger, NOT the Excel seed.

These lock in the rule that only a real *tracker* event puts a player in the portal:
the 2025 `excel:*` import is historical reference and must never imply ENTERED.
"""
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.db import reconcile_status_from_ledger  # noqa: E402
from ncaa.portal.sources.base import BaseAdapter, PortalEvent  # noqa: E402


def _db():
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    c.executescript((ROOT / "db" / "schema.sql").read_text())
    return c


def _player(c, name, status=None):
    return c.execute("INSERT INTO players (full_name, current_status) VALUES (?,?)",
                     (name, status)).lastrowid


def _event(c, pid, etype, source, date="2026-06-01"):
    c.execute("INSERT INTO portal_events (player_id,event_type,event_date,source,observed_at)"
              " VALUES (?,?,?,?,?)", (pid, etype, date, source, "2026-06-01T00:00:00"))


def test_reconcile_excludes_excel_seed():
    c = _db()
    # seeded ENTERED by the Excel import, but NO tracker event -> not current portal
    stale = _player(c, "Stale Excel Guy", "ENTERED")
    _event(c, stale, "ENTERED", "excel:names+notes")
    # real tracker entry, but status never got set (matched-existing bug) -> should become ENTERED
    real = _player(c, "Real Portal Guy", None)
    _event(c, real, "ENTERED", "d1baseball")
    # entered then committed -> COMMITTED wins
    comm = _player(c, "Committed Guy", "ENTERED")
    _event(c, comm, "ENTERED", "d1baseball"); _event(c, comm, "COMMITTED", "d1baseball")
    c.commit()

    reconcile_status_from_ledger(c)
    st = dict(c.execute("SELECT full_name, current_status FROM players").fetchall())
    assert st["Stale Excel Guy"] is None       # demoted: excel-only is not current
    assert st["Real Portal Guy"] == "ENTERED"  # promoted from NULL via the tracker event
    assert st["Committed Guy"] == "COMMITTED"


class _FakeTracker(BaseAdapter):
    source_id = "d1baseball"
    def __init__(self, events): super().__init__({}); self._events = events
    def fetch(self): return self._events


def test_ingest_entered_sets_status_on_matched_player():
    c = _db()
    # a player already present (e.g. from the Excel seed) with no current status
    pid = _player(c, "Matched Player", None)
    c.commit()
    _FakeTracker([PortalEvent(player_name="Matched Player", event_type="ENTERED",
                              from_school="State U", event_date="2026-06-01")]).ingest(c)
    assert c.execute("SELECT current_status FROM players WHERE player_id=?", (pid,)).fetchone()[0] == "ENTERED"


def test_ingest_entered_does_not_override_committed():
    c = _db()
    pid = _player(c, "Already Committed", "COMMITTED")
    c.commit()
    _FakeTracker([PortalEvent(player_name="Already Committed", event_type="ENTERED",
                              from_school="State U", event_date="2026-06-01")]).ingest(c)
    assert c.execute("SELECT current_status FROM players WHERE player_id=?", (pid,)).fetchone()[0] == "COMMITTED"


def test_ingest_entered_refreshes_stale_2026_state():
    # the Savoie bug: a matched player keeps stale 2026-state fields from the 2025 seed
    # (school, position, class). The tracker must win so the site matches the transfer list.
    c = _db()
    pid = c.execute("INSERT INTO players (full_name, from_school, position, class_year, "
                    "eligibility_remaining, current_status, height_in) VALUES (?,?,?,?,?,?,?)",
                    ("Nate Savoie", "Loyola Marymount University", "C/OF", "FR", 3, "ENTERED", 73)).lastrowid
    c.commit()
    _FakeTracker([PortalEvent(player_name="Nate Savoie", event_type="ENTERED",
                              from_school="Clemson", position="C", class_year="SO",
                              event_date="2026-06-01")]).ingest(c)
    r = c.execute("SELECT from_school, position, class_year, eligibility_remaining, height_in "
                  "FROM players WHERE player_id=?", (pid,)).fetchone()
    assert r["from_school"] == "Clemson"        # 2026 state from tracker
    assert r["position"] == "C"
    assert r["class_year"] == "SO"
    assert r["eligibility_remaining"] == 2      # derived from SO, not the stale 3
    assert r["height_in"] == 73                 # bio category untouched
