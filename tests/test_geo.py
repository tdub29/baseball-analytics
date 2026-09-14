"""Unit tests for the geographic / CA-tie layer (pure; no network)."""
import sqlite3
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.util import parse_hometown, parse_height_to_inches, to_usps  # noqa: E402
from ncaa.portal import geo  # noqa: E402


# ── hometown / state parsing ─────────────────────────────────────────────────
@pytest.mark.parametrize("raw,city,state", [
    ("San Diego, Calif.", "San Diego", "CA"),    # AP abbreviation
    ("Phoenix, Ariz.", "Phoenix", "AZ"),
    ("Chicago, IL", "Chicago", "IL"),            # USPS code
    ("Austin, Texas", "Austin", "TX"),           # full name (no AP abbrev)
    ("La Jolla, CA", "La Jolla", "CA"),
    ("", None, None),
    (None, None, None),
])
def test_parse_hometown(raw, city, state):
    assert parse_hometown(raw) == (city, state)


def test_parse_hometown_international_keeps_raw():
    # not a US state -> keep the raw trailing token rather than guess
    city, state = parse_hometown("Toronto, Ontario")
    assert city == "Toronto" and state == "Ontario"


@pytest.mark.parametrize("tok,exp", [
    ("Calif.", "CA"), ("calif", "CA"), ("CA", "CA"), ("California", "CA"),
    ("Tex.", "TX"), ("N.C.", "NC"), ("Ontario", None), ("", None),
])
def test_to_usps(tok, exp):
    assert to_usps(tok) == exp


@pytest.mark.parametrize("raw,inches", [
    ("6-2", 74), ("6'2\"", 74), ("6’0", 72), ("5-11", 71), ("", None), (None, None),
])
def test_parse_height(raw, inches):
    assert parse_height_to_inches(raw) == inches


# ── CA / San Diego classifiers ───────────────────────────────────────────────
def test_is_ca_school_excludes_pennwest():
    assert geo.is_ca_school("San Diego State University")
    assert geo.is_ca_school("University of California, Los Angeles")
    assert geo.is_ca_school("Pepperdine University")
    # PennWest California / IUP are in Pennsylvania, not California
    assert not geo.is_ca_school("Pennsylvania Western University, California")
    assert not geo.is_ca_school("Indiana University of Pennsylvania")
    assert not geo.is_ca_school("University of Texas at Austin")


def test_is_sd_school():
    assert geo.is_sd_school("San Diego State University")
    assert geo.is_sd_school("Point Loma Nazarene University")
    assert geo.is_sd_school("California State University, San Marcos")
    assert not geo.is_sd_school("California State University, Fresno")


def test_is_ca_summer():
    assert geo.is_ca_summer("CCL - Sonoma Stompers")
    assert geo.is_ca_summer("Slo Blues")
    assert not geo.is_ca_summer("Northwoods - Kalamazoo")


def test_in_sd_county():
    assert geo._in_sd_county("Chula Vista")
    assert geo._in_sd_county("La Jolla")
    assert geo._in_sd_county("Vista")
    assert not geo._in_sd_county("Mountain Vista High School")  # Highlands Ranch, CO
    assert not geo._in_sd_county("Temecula")   # Riverside County, not SD


def test_in_socal_superset_of_sd():
    # SoCal is a superset of SD County: every SD city is also SoCal.
    assert geo._in_socal("Chula Vista")        # SD County
    assert geo._in_socal("Los Angeles")        # LA County
    assert geo._in_socal("Temecula")           # Riverside County (SoCal, not SD)
    assert geo._in_socal("Anaheim")            # Orange County
    assert not geo._in_socal("Sacramento")     # NorCal
    assert not geo._in_socal("Modesto")        # Central Valley, not SoCal


# ── end-to-end scoring on an in-memory DB ────────────────────────────────────
def _db():
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript((ROOT / "db" / "schema.sql").read_text(encoding="utf-8"))
    return con


def test_score_geo_ties_flags_all_signals():
    con = _db()
    # 1: San Diego hometown (via bio) — SD + CA
    # 2: CA prior school, no hometown — CA only
    # 3: CA summer league — CA only
    # 4: out-of-state, non-CA school — neither
    con.executemany(
        "INSERT INTO players (player_id, full_name, from_school, summer_team) VALUES (?,?,?,?)",
        [(1, "A SDKID", "Vanderbilt University", None),       # non-CA school, but SD hometown
         (2, "B CALGUY", "Pepperdine University", None),
         (3, "C SUMMER", "University of Texas", "CCL - Walnut Creek"),
         (4, "D OUTSIDER", "University of Florida", "Cape Cod")],
    )
    con.execute(
        "INSERT INTO player_bio (player_id, season, source, hometown_city, hometown_state) "
        "VALUES (1,'2026','ncaa','Chula Vista','CA')")
    con.commit()

    summary = geo.score_geo_ties(con)
    assert summary["players"] == 4
    assert summary["with_hometown"] == 1
    assert summary["ca_tie"] == 3   # players 1,2,3
    assert summary["sd_tie"] == 1   # player 1 only

    rows = {r["player_id"]: r for r in con.execute(
        "SELECT player_id, ca_tie, sd_tie, hometown_city, ca_tie_reasons FROM players")}
    assert rows[1]["sd_tie"] == 1 and rows[1]["ca_tie"] == 1
    assert "SD County" in rows[1]["ca_tie_reasons"]
    assert rows[2]["ca_tie"] == 1 and rows[2]["sd_tie"] == 0
    assert rows[3]["ca_tie"] == 1 and "summer" in rows[3]["ca_tie_reasons"]
    assert rows[4]["ca_tie"] == 0 and rows[4]["sd_tie"] == 0


def test_class_year_comes_from_portal_not_bio():
    """Player's class year is the d1baseball portal value; a stale roster bio class
    must NOT override it. Bio only fills when the player has no class."""
    con = _db()
    con.executemany("INSERT INTO players (player_id, full_name, class_year) VALUES (?,?,?)",
                    [(1, "Has Portalclass", "SO"), (2, "No Class", None)])
    # bios disagree (FR) for #1 and supply JR for #2
    con.execute("INSERT INTO player_bio (player_id, season, source, class_year) VALUES (1,'2026','ncaa','FR')")
    con.execute("INSERT INTO player_bio (player_id, season, source, class_year) VALUES (2,'2026','ncaa','JR')")
    con.commit()
    geo.score_geo_ties(con)
    cls = dict(con.execute("SELECT player_id, class_year FROM players"))
    assert cls[1] == "SO"   # portal value wins over the bio FR
    assert cls[2] == "JR"   # bio fills only because there was no portal class


def test_canada_not_flagged_as_california():
    """A Toronto/Ontario kid miscoded 'Ontario, CA' by one roster must NOT be a CA tie."""
    con = _db()
    con.execute("INSERT INTO players (player_id, full_name, from_school) VALUES (1,'Cana Dian','Eastern Kentucky')")
    # NCAA row miscodes it as the SoCal city Ontario, CA; the team-site row reveals Canada.
    con.execute("INSERT INTO player_bio (player_id, season, source, hometown_city, hometown_state, high_school) "
                "VALUES (1,'2026','ncaa','Ontario','CA','St. Joan of Arc')")
    con.execute("INSERT INTO player_bio (player_id, season, source, hometown_city, hometown_state) "
                "VALUES (1,'2026','sidearm','Toronto','Ontario')")
    con.commit()
    geo.score_geo_ties(con)
    r = con.execute("SELECT ca_tie, socal_tie, sd_tie, hometown_city, hometown_state FROM players WHERE player_id=1").fetchone()
    assert r["ca_tie"] == 0 and r["socal_tie"] == 0 and r["sd_tie"] == 0
    assert r["hometown_city"] == "Toronto" and r["hometown_state"] == "Ontario"  # real hometown shown


def test_score_geo_ties_socal_middle_tier():
    """Three nested tiers: CA ⊇ SoCal ⊇ SD. A SoCal-but-not-SD hometown lights
    up socal_tie + ca_tie but NOT sd_tie; SD lights up all three."""
    con = _db()
    con.executemany(
        "INSERT INTO players (player_id, full_name, from_school, summer_team) VALUES (?,?,?,?)",
        [(1, "A SDKID", "Vanderbilt University", None),    # SD County hometown
         (2, "B LAGUY", "Vanderbilt University", None),    # LA (SoCal, not SD)
         (3, "C NORCAL", "Vanderbilt University", None),   # Sacramento (CA, not SoCal)
         (4, "D PREVCA", "Pepperdine University", None)],  # CA prev school, no hometown
    )
    con.executemany(
        "INSERT INTO player_bio (player_id, season, source, hometown_city, hometown_state) VALUES (?,?,?,?,?)",
        [(1, "2026", "ncaa", "Chula Vista", "CA"),
         (2, "2026", "ncaa", "Long Beach", "CA"),
         (3, "2026", "ncaa", "Sacramento", "CA")],
    )
    con.commit()

    summary = geo.score_geo_ties(con)
    assert summary["ca_tie"] == 4      # all four
    assert summary["socal_tie"] == 2   # players 1 (SD) + 2 (LA)
    assert summary["sd_tie"] == 1      # player 1 only

    rows = {r["player_id"]: r for r in con.execute(
        "SELECT player_id, ca_tie, socal_tie, sd_tie, ca_tie_reasons FROM players")}
    # player 1: SD ⟹ SoCal ⟹ CA
    assert (rows[1]["sd_tie"], rows[1]["socal_tie"], rows[1]["ca_tie"]) == (1, 1, 1)
    # player 2: SoCal ⟹ CA, but not SD
    assert (rows[2]["sd_tie"], rows[2]["socal_tie"], rows[2]["ca_tie"]) == (0, 1, 1)
    assert "SoCal" in rows[2]["ca_tie_reasons"]
    # player 3: CA only (NorCal hometown), not SoCal, not SD
    assert (rows[3]["sd_tie"], rows[3]["socal_tie"], rows[3]["ca_tie"]) == (0, 0, 1)
    # player 4: CA via prev school only, no hometown -> CA only
    assert (rows[4]["sd_tie"], rows[4]["socal_tie"], rows[4]["ca_tie"]) == (0, 0, 1)
    # invariant holds for everyone
    for r in rows.values():
        assert r["sd_tie"] <= r["socal_tie"] <= r["ca_tie"]


def test_canonical_hometown_prefers_trusted_source():
    con = _db()
    con.execute("INSERT INTO players (player_id, full_name) VALUES (1,'A PLAYER')")
    # NCAA (trusted) says TX; a 643 row says CA — NCAA should win the rollup.
    con.execute("INSERT INTO player_bio (player_id, season, source, hometown_state) "
                "VALUES (1,'2026','ncaa','TX')")
    con.execute("INSERT INTO player_bio (player_id, season, source, hometown_state) "
                "VALUES (1,'2026','643','CA')")
    con.commit()
    geo.score_geo_ties(con)
    row = con.execute("SELECT hometown_state, ca_tie FROM players WHERE player_id=1").fetchone()
    assert row["hometown_state"] == "TX" and row["ca_tie"] == 0
